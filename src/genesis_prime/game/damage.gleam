//// The value of a damage effect for a player that casts it, by the client's own
//// formula, the one its tooltip shows (`0x140565600`). The caster's connection
//// works it out once for each effect of a go and sends it as a blow
//// (genesis_prime/game/hit).
////
//// ```
//// Spell4Effects row ─▶ Formula (once, in genesis_prime/game/spell_area)
//// Formula + Attacker ─▶ value = M x (S + R)
//// Formula + OnCaster ─▶ the same, F also reading the caster's vitals
////   S = sum of each parameter value x the caster's stat for types 1 to 5, 11, 12 and 13, rounded
////   R = (dataBits01 + F) x dataBits00 as a float, F = sum of each parameter value x the caster's level for type 10
//// ```
////
//// - **The stat part** S uses the caster's Strength, Dexterity, Technology, Magic and
////   Wisdom (parameter types 1 to 5, UnitProperty2 0 to 4) and Stamina (11, property
////   40), each its live property value, and its Assault Power (12) and Support Power
////   (13), which are its Assault Rating and Support Rating times 0.25 (`0x140462930`,
////   `0x140462980`, GameFormula 1266). The products are summed in 32-bit floats, and 0.5
////   is added to the sum (taken away when it is below 0) in 32-bit floats before it is
////   cut to a whole number (`0x140566d40`).
//// - **The flat part** F reads the caster's level (type 10) (`0x140566ad0`).
//// - **What is not built:** the caster's Weapon and Weapon DPS (types 6 and 9,
////   `Spell4Effects.parameterType.6_9`, #807), the target's and the caster's health and
////   shield (types 7, 8, 14 to 17, 19, 21 to 23, 25 and 26, #791), the passed-in value
////   (18, #336), and types 20, 24 and any above 26, which neither part reads; a formula
////   that names one with a factor is refused at load (genesis_prime/game/spell_area,
////   `unread`).
//// - **The multiplier** M is the caster's DamageDealtMultiplier for the damage type,
////   1.0 for a player (UnitProperty2 140 to 143: the multiplier's default).
//// - **An Absorption row** (`absorption_formula_of`) reads dataBits00 and dataBits01 as
////   floats and is worked out as an effect on its caster is, at the go
////   (`Spell4Effects.effectType.29`).
//// - **An effect on its caster** (`value_on_caster`): the caster is also the target, so
////   the flat part F also reads the caster's own health, shield and maxima by the kinds
////   the client names (`0x140566ad0`), and the amount is the value rounded half away
////   from zero (a HealShields effect aimed at the caster, genesis_prime/game/cast).
//// - **A creature caster** has its own formula (`creature_value`): the stat part
////   reads Strength and Assault Power and is held under a cap that grows with the
////   level by GameFormula 712 (`0x140565600`).

import genesis_prime/game/unit_properties
import genesis_prime/message/float32
import genesis_prime/table/spell4_effects
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// One parameter of an effect: the unit value its type names, and the factor it
/// is multiplied by.
pub type Parameter {
  Parameter(kind: Int, value: Float)
}

/// An effect's row as the formula reads it: the multiplier dataBits00 as a float, the
/// flat base dataBits01 (an integer for a damage or heal row, a float for an Absorption
/// row) and the four parameters.
pub type Formula {
  Formula(multiplier: Float, base: Float, parameters: List(Parameter))
}

/// A damage effect's row as the formula reads it, or an error when its dataBits00,
/// read as a 32-bit float, is not finite: the one build of the formula, for a
/// player's spells (genesis_prime/game/spell_area) and a creature's attack
/// (genesis_prime/world_map/spawn).
pub fn formula_of(
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Formula, Nil) {
  use multiplier <- result.map(float32.of_column(number: effect.data_bits00))
  Formula(
    multiplier:,
    base: int.to_float(effect.data_bits01),
    parameters: parameters_of(effect:),
  )
}

/// An Absorption row's formula (`Spell4Effects.effectType.29`): dataBits00 is the
/// multiplier and dataBits01 the flat base, both 32-bit floats ('Granted 45 Absorb' is row
/// 183643's dataBits01 1110704128 = 45.0), with the parameters of a damage row. An error
/// when either is not finite. That type 29 takes the row part as a damage row does is the
/// server's choice: ComputeEffectValue gives it none.
pub fn absorption_formula_of(
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Formula, Nil) {
  use multiplier <- result.try(float32.of_column(number: effect.data_bits00))
  use base <- result.map(float32.of_column(number: effect.data_bits01))
  Formula(multiplier:, base:, parameters: parameters_of(effect:))
}

fn parameters_of(
  effect effect: spell4_effects.Spell4Effects,
) -> List(Parameter) {
  [
    Parameter(kind: effect.parameter_type00, value: effect.parameter_value00),
    Parameter(kind: effect.parameter_type01, value: effect.parameter_value01),
    Parameter(kind: effect.parameter_type02, value: effect.parameter_value02),
    Parameter(kind: effect.parameter_type03, value: effect.parameter_value03),
  ]
}

/// Whether the formula gives 0 to every caster: no stat parameter (kind 1 to 5, 11, 12 or
/// 13) has a value, and the multiplier is 0.0 or the base is 0.0 with no flat parameter
/// (any kind but these and 0) that has a value. Such a row has no amount the server
/// can read, whatever the caster's stats.
pub fn gives_nothing(formula formula: Formula) -> Bool {
  let has_value = fn(is_kind) {
    list.any(formula.parameters, fn(parameter) {
      parameter.value != 0.0 && is_kind(parameter.kind)
    })
  }
  let stat = has_value(is_stat)
  let flat = has_value(fn(kind) { kind != 0 && !is_stat(kind) })
  !stat && { formula.multiplier == 0.0 || { formula.base == 0.0 && !flat } }
}

/// What the formula reads of the caster: its level, its two ratings and its six
/// attributes.
pub type Attacker {
  Attacker(
    level: Int,
    assault_rating: Float,
    support_rating: Float,
    attributes: Attributes,
  )
}

/// A caster's six attributes, which parameter types 1 to 5 and 11 read (`0x140566d40`):
/// UnitProperty2 Strength (0), Dexterity (1), Technology (2), Magic (3), Wisdom (4) and
/// Stamina (40).
pub type Attributes {
  Attributes(
    strength: Float,
    dexterity: Float,
    technology: Float,
    magic: Float,
    wisdom: Float,
    stamina: Float,
  )
}

/// What the formula reads of a player caster at `level` with `properties`: the live
/// value of each rating and attribute, as the client reads each of its unit
/// (`0x140466a70`). A player starts each at its UnitProperty2 defaultValue
/// (`0x1404584b0`), the attributes at 1.0.
pub fn attacker_of(
  properties properties: unit_properties.Properties,
  level level: Int,
) -> Attacker {
  let read = fn(property) { unit_properties.value(properties:, property:) }
  Attacker(
    level:,
    assault_rating: read(unit_properties.assault_rating),
    support_rating: read(unit_properties.support_rating),
    attributes: Attributes(
      strength: read(unit_properties.strength),
      dexterity: read(unit_properties.dexterity),
      technology: read(unit_properties.technology),
      magic: read(unit_properties.magic),
      wisdom: read(unit_properties.wisdom),
      stamina: read(unit_properties.stamina),
    ),
  )
}

/// A parameter type the formula does not read for a player caster, which fails
/// the load of the spell that holds it.
pub type Unread {
  Unread(parameter_kind: Int)
}

/// The Assault Power and Support Power of a rating: 0.25 of it (GameFormula 1266's
/// first and second values, `0x140462930`, `0x140462980`).
const power_per_rating = 0.25

/// The Assault Power or Support Power of a rating (GameFormula 1266).
pub fn power_of(rating rating: Float) -> Float {
  float32.product(left: rating, right: power_per_rating)
}

/// The first parameter type of the formula that is not built, or `None` when the
/// formula reads only what a player caster holds: the level, the six attributes and the
/// two powers.
pub fn unread(formula formula: Formula) -> Option(Unread) {
  first_unread(formula:, is_read:)
}

/// The first parameter with a factor whose type `is_read` refuses.
fn first_unread(
  formula formula: Formula,
  is_read is_read: fn(Int) -> Bool,
) -> Option(Unread) {
  list.find(formula.parameters, fn(parameter) {
    parameter.value != 0.0 && !is_read(parameter.kind)
  })
  |> result.map(fn(parameter) { Unread(parameter_kind: parameter.kind) })
  |> option.from_result
}

fn is_read(kind: Int) -> Bool {
  kind == 0 || kind == 10 || is_stat(kind)
}

/// The effect's value for a player caster, before any rounding to a whole number
/// (`0x140565600`): Kick 4.16, Zap 9.08, Telekinetic Strike 18.0, Crush 8.94,
/// Paralytic Surge 8.14 and Stagger 3.0 at level 1 and rating 0.
pub fn value(formula formula: Formula, attacker attacker: Attacker) -> Float {
  value_with(formula:, attacker:, flat_of: fn(kind) {
    case kind {
      10 -> int.to_float(attacker.level)
      _ -> 0.0
    }
  })
}

/// The value of a player caster's effect, the flat part reading what `flat_of` gives for
/// each parameter type (0.0 for a type that is no flat unit value).
fn value_with(
  formula formula: Formula,
  attacker attacker: Attacker,
  flat_of flat_of: fn(Int) -> Float,
) -> Float {
  let stat_part =
    list.fold(formula.parameters, 0.0, fn(sum, parameter) {
      float32.sum(
        left: sum,
        right: float32.product(
          left: float32.rounded(stat_of(attacker:, kind: parameter.kind)),
          right: parameter.value,
        ),
      )
    })
  let flat_part =
    list.fold(formula.parameters, 0.0, fn(sum, parameter) {
      sum +. parameter.value *. flat_of(parameter.kind)
    })
  let row_part = { formula.base +. flat_part } *. formula.multiplier
  int.to_float(whole_stat_part(stat_part)) +. row_part
}

/// The stat part as the client cuts it to a whole number (`0x140566d40`): 0.5 added, or
/// taken away below 0, in 32-bit floats, then the fraction dropped.
fn whole_stat_part(stat_part: Float) -> Int {
  case stat_part >=. 0.0 {
    True -> float32.sum(left: stat_part, right: 0.5)
    False -> float32.difference(left: stat_part, right: 0.5)
  }
  |> float.truncate
}

/// The caster's stat that a parameter type names in the stat part (`0x140566d40`): 1 to
/// 5 Strength, Dexterity, Technology, Magic and Wisdom, 11 Stamina, 12 the Assault Power
/// and 13 the Support Power; 0.0 for any other type, which the stat part skips.
fn stat_of(attacker attacker: Attacker, kind kind: Int) -> Float {
  let attributes = attacker.attributes
  case kind {
    1 -> attributes.strength
    2 -> attributes.dexterity
    3 -> attributes.technology
    4 -> attributes.magic
    5 -> attributes.wisdom
    11 -> attributes.stamina
    12 -> power_of(rating: attacker.assault_rating)
    13 -> power_of(rating: attacker.support_rating)
    _ -> 0.0
  }
}

/// Whether the stat part reads the parameter type (`0x140566d40`): the six attributes
/// and the two powers.
fn is_stat(kind: Int) -> Bool {
  case kind {
    1 | 2 | 3 | 4 | 5 | 11 | 12 | 13 -> True
    _ -> False
  }
}

/// What the formula reads of a caster that is also the target of its effect: its
/// stats and its own health and shield, each with its maximum.
pub type OnCaster {
  OnCaster(attacker: Attacker, vitals: Vitals)
}

/// A unit's health and shield as the formula's flat kinds read them.
pub type Vitals {
  Vitals(health: Int, max_health: Int, shield: Int, max_shield: Int)
}

/// The first parameter type of the formula that an effect on its caster does not read,
/// or `None`: it reads the stat kinds 1 to 5 and 11 to 13 and the flat kinds 7, 8, 10, 14
/// to 17, 19, 21 to 23, 25 and 26 (`0x140565600`, `0x140566d40`, `0x140566ad0`); the
/// caster's Weapon and Weapon DPS (6 and 9, #807) and the passed-in value (18, #336) are
/// not read.
pub fn caster_unread(formula formula: Formula) -> Option(Unread) {
  first_unread(formula:, is_read: is_read_on_caster)
}

fn is_read_on_caster(kind: Int) -> Bool {
  kind == 0 || is_stat(kind) || is_vital_on_caster(kind)
}

/// Whether the flat part reads the parameter type of an effect on its caster
/// (`0x140566ad0`): the level and the caster's own health and shield.
fn is_vital_on_caster(kind: Int) -> Bool {
  case kind {
    7 | 8 | 10 | 14 | 15 | 16 | 17 | 19 | 21 | 22 | 23 | 25 | 26 -> True
    _ -> False
  }
}

/// The effect's value for a caster that is also its target, before any rounding
/// (`0x140565600`): the value of a player caster with the flat kinds reading the caster's
/// own vitals, as the client reads them of the one unit it passes as caster and as
/// target (`0x140566ad0`: 7 and 8 the maximum health, 10 the level, 14 and 15 the shield,
/// 16 and 17 the maximum shield, 19 and 23 the health, 21 and 25 the maximum health less
/// the health, 22 and 26 the maximum shield less the shield).
pub fn value_on_caster(
  formula formula: Formula,
  caster caster: OnCaster,
) -> Float {
  let vitals = caster.vitals
  value_with(formula:, attacker: caster.attacker, flat_of: fn(kind) {
    case kind {
      7 | 8 -> int.to_float(vitals.max_health)
      10 -> int.to_float(caster.attacker.level)
      14 | 15 -> int.to_float(vitals.shield)
      16 | 17 -> int.to_float(vitals.max_shield)
      19 | 23 -> int.to_float(vitals.health)
      21 | 25 -> int.to_float(vitals.max_health - vitals.health)
      22 | 26 -> int.to_float(vitals.max_shield - vitals.shield)
      _ -> 0.0
    }
  })
}

/// The whole number an effect on its caster gives: `value_on_caster` rounded half away
/// from zero (the server's choice, as each damage step rounds), and never below 0, since
/// the fields that carry it are unsigned.
pub fn amount_on_caster(
  formula formula: Formula,
  caster caster: OnCaster,
) -> Int {
  int.max(0, float.round(value_on_caster(formula:, caster:)))
}

/// A stat part above the creature's cap: ((1 - e^(-(S - c) / c)) x overflow + 1) x
/// c (`0x140565600`).
fn beyond_the_cap(
  stat_part stat_part: Float,
  cap cap: Float,
  overflow overflow: Float,
) -> Float {
  let over = { stat_part -. cap } /. cap
  { { 1.0 -. float.exponential(0.0 -. over) } *. overflow +. 1.0 } *. cap
}

/// What the creature formula reads of a creature caster: its level, its Strength
/// (property 0) and its Assault Power (its AssaultRating, property 35, times 0.25,
/// GameFormula 1266), each as the content load works out the creature's
/// properties (genesis_prime/world_map/spawn).
pub type Creature {
  Creature(level: Int, strength: Float, assault_power: Float)
}

/// GameFormula 712's four values, which scale a creature's stat part
/// (`0x140565600`): c = (level x `per_level` + `base`) x the mean of the stat
/// parameters; a stat part above c grows only to ((1 - e^(-(S - c) / c)) x
/// `overflow` + 1) x c; and the stat and row parts are divided by `divisor`.
pub type CreatureScaling {
  CreatureScaling(
    per_level: Float,
    base: Float,
    overflow: Float,
    divisor: Float,
  )
}

/// The first parameter type the creature formula does not read, or `None`: it reads
/// Strength (type 1), Assault Power (12) and the level (10).
pub fn creature_unread(formula formula: Formula) -> Option(Unread) {
  first_unread(formula:, is_read: is_read_for_a_creature)
}

fn is_read_for_a_creature(kind: Int) -> Bool {
  kind == 0 || kind == 1 || kind == 10 || kind == 12
}

/// The effect's value for a creature caster, before any rounding to a whole number
/// (`0x140565600`): the stat part rounded half away from zero, held under the
/// creature's cap, plus the row part, both divided by GameFormula 712's fourth
/// value, times `multiplier`, the creature's DamageDealtMultiplier of the effect's
/// damage type (UnitProperty2 140 + damage type, 1.0 for a type with none).
/// Effect 184741 of a level-1 Virtual Battle Beast (Strength and Assault Power
/// 10.47, multiplier 1.0) is 12.
pub fn creature_value(
  formula formula: Formula,
  creature creature: Creature,
  scaling scaling: CreatureScaling,
  multiplier multiplier: Float,
) -> Float {
  let stat_parameters =
    list.filter(formula.parameters, fn(parameter) {
      parameter.kind == 1 || parameter.kind == 12
    })
  let stat_part =
    list.fold(stat_parameters, 0.0, fn(sum, parameter) {
      case parameter.kind {
        1 -> sum +. parameter.value *. creature.strength
        _ -> sum +. parameter.value *. creature.assault_power
      }
    })
    |> float.round
    |> int.to_float
  let mean = case stat_parameters {
    [] -> 0.0
    _ ->
      list.fold(stat_parameters, 0.0, fn(sum, parameter) {
        sum +. parameter.value
      })
      /. int.to_float(list.length(stat_parameters))
  }
  let cap =
    { int.to_float(creature.level) *. scaling.per_level +. scaling.base }
    *. mean
  let capped = case stat_part <=. cap || cap <=. 0.0 {
    True -> stat_part
    False -> beyond_the_cap(stat_part:, cap:, overflow: scaling.overflow)
  }
  let flat_part =
    list.fold(formula.parameters, 0.0, fn(sum, parameter) {
      case parameter.kind {
        10 -> sum +. parameter.value *. int.to_float(creature.level)
        _ -> sum
      }
    })
  let row_part = { formula.base +. flat_part } *. formula.multiplier
  { capped +. row_part } /. scaling.divisor *. multiplier
}
