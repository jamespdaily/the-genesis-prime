//// The value of a damage effect for a player that casts it, by the client's own
//// formula, the one its tooltip shows (`0x140565600`). The caster's connection
//// works it out once for each effect of a go and sends it as a blow
//// (genesis_prime/game/hit).
////
//// ```
//// Spell4Effects row ─▶ Formula (once, in genesis_prime/game/spell_area)
//// Formula + Attacker ─▶ value = M x (S + R)
////   S = sum of each parameter value x the caster's stat for types 12 and 13, rounded
////   R = (dataBits01 + F) x dataBits00 as a float, F = sum of each parameter value x the caster's level for type 10
//// ```
////
//// - **The stat part** S uses the caster's Assault Power (parameter type 12) and
////   Support Power (13), which are its Assault Rating and Support Rating times 0.25
////   (`0x140462930`, `0x140462980`, GameFormula 1266), and rounds half away from
////   zero (`0x140566d40`).
//// - **The flat part** F reads the caster's level (type 10) (`0x140566ad0`).
//// - **What is not built:** every other parameter type, which reads an attribute the
////   level-1 abilities' rows never name or a health or shield of the target; a
////   formula that names one is refused at load (genesis_prime/game/spell_area,
////   `unread`).
//// - **The multiplier** M is the caster's DamageDealtMultiplier for the damage type,
////   1.0 for a player (UnitProperty2 140 to 143: the multiplier's default).
//// - **A creature caster** has its own formula (`creature_value`): the stat part
////   reads Strength and Assault Power and is held under a cap that grows with the
////   level by GameFormula 712 (`0x140565600`).

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// One parameter of an effect: the unit value its type names, and the factor it
/// is multiplied by.
pub type Parameter {
  Parameter(kind: Int, value: Float)
}

/// A damage effect's row as the formula reads it: the multiplier dataBits00 as a
/// float, the integer dataBits01, and the four parameters.
pub type Formula {
  Formula(multiplier: Float, base: Int, parameters: List(Parameter))
}

/// What the formula reads of the caster: its level and its two ratings.
pub type Attacker {
  Attacker(level: Int, assault_rating: Float, support_rating: Float)
}

/// A parameter type the formula does not read for a player caster, which fails
/// the load of the spell that holds it.
pub type Unread {
  Unread(parameter_kind: Int)
}

/// The Assault Power and Support Power of a rating: 0.25 of it (GameFormula 1266's
/// first and second values, `0x140462930`, `0x140462980`).
const power_per_rating = 0.25

/// The first parameter type of the formula that is not built, or `None` when the
/// formula reads only what a player caster holds: the level and the two powers.
pub fn unread(formula formula: Formula) -> Option(Unread) {
  case
    list.find(formula.parameters, fn(parameter) {
      parameter.value != 0.0 && !is_read(parameter.kind)
    })
  {
    Ok(parameter) -> Some(Unread(parameter_kind: parameter.kind))
    Error(Nil) -> None
  }
}

fn is_read(kind: Int) -> Bool {
  kind == 10 || kind == 12 || kind == 13 || kind == 0
}

/// The effect's value for a player caster, before any rounding to a whole number
/// (`0x140565600`): Kick 4.16, Zap 9.08, Telekinetic Strike 18.0, Crush 8.94,
/// Paralytic Surge 8.14 and Stagger 3.0 at level 1 and rating 0.
pub fn value(formula formula: Formula, attacker attacker: Attacker) -> Float {
  let stat_part =
    list.fold(formula.parameters, 0.0, fn(sum, parameter) {
      case parameter.kind {
        12 ->
          sum +. parameter.value *. attacker.assault_rating *. power_per_rating
        13 ->
          sum +. parameter.value *. attacker.support_rating *. power_per_rating
        _ -> sum
      }
    })
  let flat_part =
    list.fold(formula.parameters, 0.0, fn(sum, parameter) {
      case parameter.kind {
        10 -> sum +. parameter.value *. int.to_float(attacker.level)
        _ -> sum
      }
    })
  let row_part =
    { int.to_float(formula.base) +. flat_part } *. formula.multiplier
  int.to_float(float.round(stat_part)) +. row_part
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
  case
    list.find(formula.parameters, fn(parameter) {
      parameter.value != 0.0 && !is_read_for_a_creature(parameter.kind)
    })
  {
    Ok(parameter) -> Some(Unread(parameter_kind: parameter.kind))
    Error(Nil) -> None
  }
}

fn is_read_for_a_creature(kind: Int) -> Bool {
  kind == 0 || kind == 1 || kind == 10 || kind == 12
}

/// The effect's value for a creature caster, before any rounding to a whole number
/// (`0x140565600`): the stat part rounded half away from zero, held under the
/// creature's cap, plus the row part, both divided by GameFormula 712's fourth
/// value. The multiplier M is 1.0: a creature's DamageDealtMultiplier (UnitProperty2
/// 140 to 143) is the default's. Effect 184741 of a level-1 Virtual Battle Beast
/// (Strength and Assault Power 10.47) is 12.
pub fn creature_value(
  formula formula: Formula,
  creature creature: Creature,
  scaling scaling: CreatureScaling,
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
  let row_part =
    { int.to_float(formula.base) +. flat_part } *. formula.multiplier
  { capped +. row_part } /. scaling.divisor
}
