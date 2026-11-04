//// The value of a damage effect for a player that casts it, by the client's own
//// formula, the one its tooltip shows (`0x140565600`). The caster's connection
//// works it out once for each effect of a go and sends it as a blow
//// (genesis_prime/game/hit).
////
//// ```
//// Spell4Effects row ─▶ Formula (once, in genesis_prime/game/spell_area)
//// Formula + Attacker ─▶ value = M x (S + R)
////   S = sum of each parameter value x the caster's stat for types 1-5, 11, 12, 13, rounded
////   R = (dataBits01 + F) x dataBits00, F = sum of each parameter value x the unit value its type names
//// ```
////
//// - **The stat part** S uses the caster's Assault Power (parameter type 12) and
////   Support Power (13), which are its Assault Rating and Support Rating times 0.25
////   (`0x140462930`, `0x140462980`, GameFormula 1266), and rounds half away from
////   zero (`0x140566d40`). The other stat types read the caster's attributes,
////   which a new unit holds none of, so each is 0.
//// - **The flat part** F reads the caster's level (type 10) for the level-1
////   abilities; the types that read the target's health and shield (7, 15, 17, 19,
////   21, 22) are not built, so a formula that names one is refused at load
////   (genesis_prime/game/spell_area).
//// - **The multiplier** M is the caster's DamageDealtMultiplier for the damage
////   type, 1.0 for a player (UnitProperty2 140 to 143).
//// - **A creature caster** has another formula (`0x140565600`: the level scaling
////   with GameFormula 712) and waits for the step where creatures fight.

import gleam/option.{type Option}

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

/// The first parameter type of the formula that is not built, or `None` when the
/// formula reads only what a player caster holds.
pub fn unread(formula formula: Formula) -> Option(Unread) {
  unbuilt(inputs: formula)
}

/// The effect's value for a player caster, before any rounding to a whole number
/// (`0x140565600`): Kick 4.16, Zap 9.08, Telekinetic Strike 18.0, Crush 8.94,
/// Paralytic Surge 8.14 and Stagger 3.0 at level 1 and rating 0.
pub fn value(formula formula: Formula, attacker attacker: Attacker) -> Float {
  unbuilt(inputs: #(formula, attacker))
}

/// The value as a whole number, rounded half away from zero (the server's choice,
/// since the client's tooltip shows a fraction).
pub fn rounded(value value: Float) -> Int {
  unbuilt(inputs: value)
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
