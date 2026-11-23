//// The value of a damage effect for a player that casts it, by the client's own
//// formula, the one its tooltip shows (`0x140565600`). The caster's connection
//// works it out once for each effect of a go and sends it as a blow
//// (genesis_prime/game/hit).
////
//// ```
//// Spell4Effects row ─▶ Formula (once, in genesis_prime/game/spell_area)
//// Formula + Attacker ─▶ value = M x (S + R)
//// Formula + OnCaster ─▶ the same, F also reading the caster's vitals
//// Formula + OnCaster ─▶ Partial (the caster's side) ─ finish with the target's vitals ─▶ value
////
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
////   cut to a whole number (`0x140566d40`), which the client keeps as a signed 16-bit
////   number (`0x14056578e`).
//// - **The row part** R is (the base as an unsigned 32-bit integer made a float + F) x
////   dataBits00, and S + R is added, all in 32-bit floats and returned without rounding
////   (`0x140565782`, `0x1405659f5`).
//// - **The flat part** F reads the caster's level (type 10) (`0x140566ad0`). Each unit
////   value and difference is read as an unsigned 32-bit integer, so a negative
////   difference counts as about 4.29 billion; each product and the running sum are
////   32-bit floats.
//// - **The vital kinds** of the flat part read the caster's health and shield (8, 14, 16,
////   23, 25, 26) or the target's (7, 15, 17, 19, 21, 22) (`0x140566ad0`). The caster's
////   connection works the stat part and the caster's kinds out at the go (`partial`) and
////   the struck unit's owner adds its own vitals when the blow lands (`finish`).
//// - **The passed-in value** (type 18) is the family-33 budget curve at the level the
////   effect is evaluated at, which the caster's `passed_in` holds
////   (genesis_prime/game/passed_in_value); `ComputeEffectValue` multiplies the parameter
////   by it in the flat part (`0x140565600`, `0x1404de840`). Only an effect on its caster
////   reads it (`unread_on_caster`): a strike would read the caster's value at the go, not
////   the level of an item's spell.
//// - **What is not built:** the caster's Weapon and Weapon DPS (types 6 and 9,
////   `Spell4Effects.parameterType.6_9`), the passed-in value in a strike's row
////   (18), and types 20, 24 and any above 26, which neither part reads; a formula
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
////   level by GameFormula 712, and the stat part and the row part (the same R as a
////   player's) are each divided by its fourth value, added and multiplied, every step a
////   32-bit float (`0x140565600`, `0x1405659f5`).

import genesis_prime/game/unit_properties
import genesis_prime/message/float32
import genesis_prime/table/spell4_effects
import gleam/bool
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
/// flat base dataBits01 (an unsigned 32-bit integer made a 32-bit float for a damage or
/// heal row, a float for an Absorption row) and the four parameters.
pub type Formula {
  Formula(multiplier: Float, base: Float, parameters: List(Parameter))
}

/// A damage effect's row as the formula reads it, or an error when its dataBits00,
/// read as a 32-bit float, is not finite: the one build of the formula, for a
/// player's spells (genesis_prime/game/spell_area) and a creature's attack
/// (genesis_prime/world_map/spawn). The base dataBits01 is read as an unsigned 32-bit
/// integer for both (`0x140565782`), so a column with its top bit set is 2^32 less its
/// size.
pub fn formula_of(
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Formula, Nil) {
  use multiplier <- result.map(float32.of_column(number: effect.data_bits00))
  Formula(
    multiplier:,
    base: unsigned_unit_value(number: effect.data_bits01),
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

/// Whether the formula reads a vital of the target, not the caster
/// (`0x140566ad0`: 7 the maximum health, 15 the shield, 17 the maximum shield, 19 the
/// health, 21 the maximum health less the health, 22 the maximum shield less the
/// shield), by a parameter that has a factor.
pub fn names_target_kind(formula formula: Formula) -> Bool {
  list.any(formula.parameters, fn(parameter) {
    parameter.value != 0.0 && is_target_kind(parameter.kind)
  })
}

fn is_target_kind(kind: Int) -> Bool {
  case kind {
    7 | 15 | 17 | 19 | 21 | 22 -> True
    _ -> False
  }
}

/// What the formula reads of the caster: its level, its two ratings, its six attributes
/// and the passed-in value (parameter type 18).
pub type Attacker {
  Attacker(
    level: Int,
    assault_rating: Float,
    support_rating: Float,
    attributes: Attributes,
    /// The family-33 budget curve at the level the effect is evaluated at, which
    /// parameter type 18 multiplies (genesis_prime/game/passed_in_value): the caster's
    /// own level for a spell it casts, an item's level for the spell of an item.
    passed_in: Float,
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
/// (`0x1404584b0`), the attributes at 1.0. `passed_in` is the passed-in value at the
/// player's level.
pub fn attacker_of(
  properties properties: unit_properties.Properties,
  level level: Int,
  passed_in passed_in: Float,
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
    passed_in:,
  )
}

/// A parameter type with a factor that a rule does not read, which fails the load of the
/// spell that holds it.
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
/// formula reads only what a player caster and its target hold, or a caster that is also
/// its target: the stat kinds 1 to 5 and 11 to 13 and the flat kinds 7, 8, 10, 14 to 17,
/// 19, 21 to 23, 25 and 26 (`0x140565600`, `0x140566d40`, `0x140566ad0`). The caster's
/// Weapon and Weapon DPS (6 and 9) and the passed-in value (18) are not read.
pub fn unread(formula formula: Formula) -> Option(Unread) {
  first_unread(parameters: formula.parameters, is_read:)
}

/// The first parameter type of the formula that an effect on its caster does not read:
/// `unread` less the passed-in value (18), which `value_on_caster` multiplies by the
/// caster's `passed_in`.
pub fn unread_on_caster(formula formula: Formula) -> Option(Unread) {
  first_unread(parameters: formula.parameters, is_read: is_read_on_caster)
}

/// Whether the effect row's formula holds the passed-in value (parameter type 18) with a
/// factor; a row whose multiplier is not finite holds none.
pub fn holds_passed_in(effect effect: spell4_effects.Spell4Effects) -> Bool {
  case formula_of(effect:) {
    Ok(formula) ->
      list.any(formula.parameters, fn(parameter) {
        parameter.kind == 18 && parameter.value != 0.0
      })
    Error(Nil) -> False
  }
}

/// The first parameter type of the effect row whose factor is not 0.0, whatever its
/// type but 0, which names no parameter: for a row whose data bits are no formula, such as
/// a stat modifier's, whose amount the plan takes from its data bits alone.
pub fn first_parameter_with_factor(
  effect effect: spell4_effects.Spell4Effects,
) -> Option(Unread) {
  first_unread(parameters: parameters_of(effect:), is_read: fn(kind) {
    kind == 0
  })
}

/// The first parameter with a factor whose type `is_read` refuses.
fn first_unread(
  parameters parameters: List(Parameter),
  is_read is_read: fn(Int) -> Bool,
) -> Option(Unread) {
  list.find(parameters, fn(parameter) {
    parameter.value != 0.0 && !is_read(parameter.kind)
  })
  |> result.map(fn(parameter) { Unread(parameter_kind: parameter.kind) })
  |> option.from_result
}

/// The effect's value for a player caster, before any rounding to a whole number
/// (`0x140565600`): Kick 4.16, Zap 9.08, Telekinetic Strike 18.0, Crush 8.94,
/// Paralytic Surge 8.14 and Stagger 3.0 at level 1 and rating 0.
pub fn value(formula formula: Formula, attacker attacker: Attacker) -> Float {
  value_with(formula:, attacker:, flat_of: fn(kind) {
    level_value(level: attacker.level, kind:)
  })
}

/// What the flat part reads of a caster that holds only its level: the level for type 10,
/// 0.0 for any other type (`0x140566ad0`).
fn level_value(level level: Int, kind kind: Int) -> Float {
  case kind {
    10 -> unsigned_unit_value(number: level)
    _ -> 0.0
  }
}

/// The value of a player caster's effect, the flat part reading what `flat_of` gives for
/// each parameter type (0.0 for a type that is no flat unit value).
fn value_with(
  formula formula: Formula,
  attacker attacker: Attacker,
  flat_of flat_of: fn(Int) -> Float,
) -> Float {
  let stat_part =
    stat_part_of(parameters: formula.parameters, stat_of: fn(kind) {
      stat_of(attacker:, kind:)
    })
  value_of_parts(
    stat_part: whole_stat_part(stat_part),
    base: formula.base,
    multiplier: formula.multiplier,
    flat_terms: flat_terms_of(parameters: formula.parameters, flat_of:),
  )
}

/// Each parameter's value times the unit value `flat_of` gives for its type, in 32-bit
/// floats and in parameter order (`0x140566ad0`).
fn flat_terms_of(
  parameters parameters: List(Parameter),
  flat_of flat_of: fn(Int) -> Float,
) -> List(Float) {
  list.map(parameters, fn(parameter) {
    float32.product(left: parameter.value, right: flat_of(parameter.kind))
  })
}

/// The value from its parts, in 32-bit floats (`0x140565600`): the row part and the stat
/// part added. The player's M is 1.0, so it changes nothing.
fn value_of_parts(
  stat_part stat_part: Int,
  base base: Float,
  multiplier multiplier: Float,
  flat_terms flat_terms: List(Float),
) -> Float {
  float32.sum(
    left: int.to_float(stat_part),
    right: row_part_of(base:, multiplier:, flat_terms:),
  )
}

/// The row part R, in 32-bit floats (`0x140565782`): the flat terms summed in order from
/// 0.0 (`0x140566ad0`), the base (already an unsigned integer made a float) + the flat
/// sum, times the row's multiplier. A player and a creature share it.
fn row_part_of(
  base base: Float,
  multiplier multiplier: Float,
  flat_terms flat_terms: List(Float),
) -> Float {
  let flat_part =
    list.fold(flat_terms, 0.0, fn(sum, term) {
      float32.sum(left: sum, right: term)
    })
  float32.product(
    left: float32.sum(left: float32.rounded(base), right: flat_part),
    right: multiplier,
  )
}

/// A unit value or difference as the flat part reads it: an unsigned 32-bit integer made
/// a 32-bit float (`0x140566b51` mov eax, eax; cvtsi2ss xmm0, rax), so a negative number
/// counts as 2^32 less its size and a number above 2^24 loses its low bits.
fn unsigned_unit_value(number number: Int) -> Float {
  float32.rounded(int.to_float(int.bitwise_and(number, 0xFFFFFFFF)))
}

/// The sum of each parameter's value times the caster's stat it names, `stat_of` giving
/// the stat of a parameter type (0.0 for a type that is no stat), each stat held as a
/// 32-bit float and each product and the running sum in 32-bit floats (`0x140566d40`).
/// Player and creature casters share it.
fn stat_part_of(
  parameters parameters: List(Parameter),
  stat_of stat_of: fn(Int) -> Float,
) -> Float {
  list.fold(parameters, 0.0, fn(sum, parameter) {
    float32.sum(
      left: sum,
      right: float32.product(
        left: float32.rounded(stat_of(parameter.kind)),
        right: parameter.value,
      ),
    )
  })
}

/// The stat part as the client cuts it to a whole number (`0x140566d40`): 0.5 added, or
/// taken away below 0, in 32-bit floats, then the fraction dropped, and the result kept
/// as a signed 16-bit number (`0x14056578e`), so 32768 is -32768.
fn whole_stat_part(stat_part: Float) -> Int {
  let whole =
    case stat_part >=. 0.0 {
      True -> float32.sum(left: stat_part, right: 0.5)
      False -> float32.difference(left: stat_part, right: 0.5)
    }
    |> float.truncate
  let low_16_bits = int.bitwise_and(whole, 0xFFFF)
  case low_16_bits >= 0x8000 {
    True -> low_16_bits - 0x10000
    False -> low_16_bits
  }
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

/// What the formula reads of a caster that is also the target, from its stats and vitals:
/// the passed-in value is the cast's own when it has one (an item's), else the stats' own.
pub fn on_caster_with(
  stats stats: Attacker,
  vitals vitals: Vitals,
  passed_in passed_in: Option(Float),
) -> OnCaster {
  OnCaster(
    attacker: Attacker(
      ..stats,
      passed_in: option.unwrap(passed_in, stats.passed_in),
    ),
    vitals:,
  )
}

/// A unit's health and shield as the formula's flat kinds read them.
pub type Vitals {
  Vitals(health: Int, max_health: Int, shield: Int, max_shield: Int)
}

fn is_read(kind: Int) -> Bool {
  kind == 0 || is_stat(kind) || is_flat(kind)
}

/// Whether an effect on its caster reads the parameter type: the kinds `is_read` names and
/// 18, the passed-in value (`0x140565600`).
fn is_read_on_caster(kind: Int) -> Bool {
  is_read(kind) || kind == 18
}

/// Whether the flat part reads the parameter type (`0x140566ad0`): the level and a
/// vital of the caster or of the target.
fn is_flat(kind: Int) -> Bool {
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
  value_with(formula:, attacker: caster.attacker, flat_of: fn(kind) {
    unit_value_of(caster:, kind:)
  })
}

/// What a flat kind reads of the caster: the level for 10, the passed-in value for 18,
/// else the vital the kind names (`0x140566ad0`).
fn unit_value_of(caster caster: OnCaster, kind kind: Int) -> Float {
  case kind {
    10 -> unsigned_unit_value(number: caster.attacker.level)
    18 -> caster.attacker.passed_in
    _ -> vital_of(vitals: caster.vitals, kind:)
  }
}

/// The vital a kind names of one unit as the flat part reads it
/// (`unsigned_unit_value`), 0.0 for a kind that names none (`0x140566ad0`: 7 and 8 the maximum health, 14 and 15 the shield, 16 and 17 the
/// maximum shield, 19 and 23 the health, 21 and 25 the maximum health less the health,
/// 22 and 26 the maximum shield less the shield). 7, 15, 17, 19, 21 and 22 are the
/// target's kinds and 8, 14, 16, 23, 25 and 26 the caster's; the unit passed is the one
/// read.
fn vital_of(vitals vitals: Vitals, kind kind: Int) -> Float {
  case kind {
    7 | 8 -> unsigned_unit_value(number: vitals.max_health)
    14 | 15 -> unsigned_unit_value(number: vitals.shield)
    16 | 17 -> unsigned_unit_value(number: vitals.max_shield)
    19 | 23 -> unsigned_unit_value(number: vitals.health)
    21 | 25 -> unsigned_unit_value(number: vitals.max_health - vitals.health)
    22 | 26 -> unsigned_unit_value(number: vitals.max_shield - vitals.shield)
    _ -> 0.0
  }
}

/// A formula after the caster's part is worked out and the target's is not: the stat
/// part as the client cuts it to a whole number, the row's base and multiplier, and the
/// flat terms in parameter order. `finish` adds the target's vitals to it
/// (`0x140565600`, `0x140566ad0`).
pub type Partial {
  Partial(stat_part: Int, base: Float, multiplier: Float, terms: List(Term))
}

/// One parameter's flat term, in the order the client sums them (`0x140566ad0`): the
/// value the caster's own level and vitals give (`Known`, the parameter's factor times
/// the unit value), or the target's vital kind it still waits for (`OfTarget`, with the
/// parameter's factor).
pub type Term {
  Known(Float)
  OfTarget(kind: Int, factor: Float)
}

/// The formula worked out as far as the caster's side goes: the stat part, and each flat
/// term from the caster's level and vitals (kinds 8, 10, 14, 16, 23, 25 and 26), while
/// the target's kinds (7, 15, 17, 19, 21 and 22) stay `OfTarget`
/// (`0x140566ad0`: param_1 is the caster, param_2 the target).
pub fn partial(formula formula: Formula, caster caster: OnCaster) -> Partial {
  let stat_part =
    stat_part_of(parameters: formula.parameters, stat_of: fn(kind) {
      stat_of(attacker: caster.attacker, kind:)
    })
  Partial(
    stat_part: whole_stat_part(stat_part),
    base: formula.base,
    multiplier: formula.multiplier,
    terms: list.map(formula.parameters, fn(parameter) {
      case is_target_kind(parameter.kind) {
        True -> OfTarget(kind: parameter.kind, factor: parameter.value)
        False ->
          Known(float32.product(
            left: parameter.value,
            right: unit_value_of(caster:, kind: parameter.kind),
          ))
      }
    }),
  )
}

/// The value of the formula once the target's vitals are known, built as `value_on_caster`
/// builds it (`0x140565600`, `0x140566ad0`).
pub fn finish(partial partial: Partial, target target: Vitals) -> Float {
  value_of_parts(
    stat_part: partial.stat_part,
    base: partial.base,
    multiplier: partial.multiplier,
    flat_terms: list.map(partial.terms, fn(term) {
      case term {
        Known(known) -> known
        OfTarget(kind:, factor:) ->
          float32.product(left: factor, right: vital_of(vitals: target, kind:))
      }
    }),
  )
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

/// A stat part above the creature's cap, in 32-bit floats: ((1 - e^(-(S - c) / c)) x
/// overflow + 1) x (c / divisor) (`0x140565600`, `0x1405659f5`; the exponential is
/// `ExpF`, `0x1408fc7f0`).
fn beyond_the_cap(
  stat_part stat_part: Float,
  cap cap: Float,
  scaling scaling: CreatureScaling,
) -> Float {
  let over =
    quotient(left: float32.difference(left: stat_part, right: cap), right: cap)
  let decay = float32.rounded(float.exponential(0.0 -. over))
  float32.sum(
    left: float32.product(
      left: float32.difference(left: 1.0, right: decay),
      right: scaling.overflow,
    ),
    right: 1.0,
  )
  |> float32.product(right: quotient(left: cap, right: scaling.divisor))
}

/// The 32-bit quotient of two 32-bit floats: the exact 64-bit quotient rounded once to 32
/// bits, as the client's single-precision divide gives. A divisor of 0.0 gives 0.0, as
/// the client's test of each divisor and of the cap against 0.0 does (`0x140565923`).
fn quotient(left left: Float, right right: Float) -> Float {
  use <- bool.guard(when: right == 0.0, return: 0.0)
  float32.rounded(value: left /. right)
}

/// What the creature formula reads of a creature caster: its level, its Strength
/// (property 0) and its Assault Power (its AssaultRating, property 35, times 0.25,
/// GameFormula 1266), each as the content load works out the creature's
/// properties (genesis_prime/world_map/spawn).
pub type Creature {
  Creature(level: Int, strength: Float, assault_power: Float)
}

/// GameFormula 712's four values, which scale a creature's stat part
/// (`0x140565600`): c = (level x `per_level` + `base`) x the absolute value of the
/// mean of the stat parameters; a stat part above c grows only to ((1 - e^(-(S - c) / c)) x
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
  first_unread(parameters: formula.parameters, is_read: is_read_for_a_creature)
}

fn is_read_for_a_creature(kind: Int) -> Bool {
  kind == 0 || kind == 1 || kind == 10 || kind == 12
}

/// The effect's value for a creature caster, before any rounding to a whole number
/// (`0x140565600`), every step a 32-bit float (`0x1405659f5`): the stat part cut as a
/// player's is (`0x140566d40`), held under the creature's cap, and the row part
/// (`row_part_of`, as a player's), each divided by GameFormula 712's fourth value, added,
/// and multiplied by `multiplier`, the creature's DamageDealtMultiplier of the effect's
/// damage type (UnitProperty2 140 + damage type, 1.0 for a type with none).
/// Effect 184741 of a level-1 Virtual Battle Beast (Strength and Assault Power
/// 10.47, multiplier 1.0) is 12.
pub fn creature_value(
  formula formula: Formula,
  creature creature: Creature,
  scaling scaling: CreatureScaling,
  multiplier multiplier: Float,
) -> Float {
  let stat_part =
    stat_part_of(parameters: formula.parameters, stat_of: fn(kind) {
      case kind {
        1 -> creature.strength
        12 -> creature.assault_power
        _ -> 0.0
      }
    })
    |> whole_stat_part
    |> int.to_float
  let cap = cap_of(formula:, level: creature.level, scaling:)
  let capped = case stat_part <=. cap {
    True -> quotient(left: stat_part, right: scaling.divisor)
    False -> beyond_the_cap(stat_part:, cap:, scaling:)
  }
  let row_part =
    row_part_of(
      base: formula.base,
      multiplier: formula.multiplier,
      flat_terms: flat_terms_of(
        parameters: formula.parameters,
        flat_of: fn(kind) { level_value(level: creature.level, kind:) },
      ),
    )
  float32.product(
    left: multiplier,
    right: float32.sum(
      left: capped,
      right: quotient(left: row_part, right: scaling.divisor),
    ),
  )
}

/// The creature's cap c on the stat part, in 32-bit floats (`0x140565600`, `0x1405659f5`):
/// (level x `per_level` + `base`) x |mean|, the level read as an unsigned 32-bit integer.
/// The mean is taken over every parameter whose type is a stat type (1 to 5, 11, 12 or
/// 13), a value of 0 included, and the absolute value is taken once, after the division;
/// with no such parameter the mean is 0 (`0x140565683`, `0x1405657e3`).
fn cap_of(
  formula formula: Formula,
  level level: Int,
  scaling scaling: CreatureScaling,
) -> Float {
  let stat_parameters = list.filter(formula.parameters, is_stat_parameter)
  let mean = case stat_parameters {
    [] -> 0.0
    _ ->
      quotient(
        left: list.fold(stat_parameters, 0.0, fn(sum, parameter) {
          float32.sum(left: sum, right: parameter.value)
        }),
        right: int.to_float(list.length(stat_parameters)),
      )
  }
  float32.product(
    left: float32.sum(
      left: float32.product(
        left: unsigned_unit_value(number: level),
        right: scaling.per_level,
      ),
      right: scaling.base,
    ),
    right: float.absolute_value(mean),
  )
}

/// Whether a parameter's type is one the cap's mean counts (`0x140565683`): 1 to 5, 11, 12
/// or 13, the stat types of the stat part.
fn is_stat_parameter(parameter: Parameter) -> Bool {
  let kind = parameter.kind
  { kind >= 1 && kind <= 5 } || { kind >= 11 && kind <= 13 }
}
