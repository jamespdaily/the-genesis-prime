//// A rating turned into a chance, as the client does for every rating: the
//// critical hit chance, the critical hit severity and the deflect chance of a
//// unit. The hit rule (genesis_prime/game/hit) reads the three.
////
//// ```
//// GameFormula 1231, 1232, 1235 ─▶ Formulas, once, when the tables load
//// to_fraction(formula, level, base, rating) ─▶ the chance, as a fraction
//// ```
////
//// - **The curve** is RatingToPercent: with per = f0 / L x f01 and knee =
////   (f02 - int0) / per, a rating below the knee gives p = per x R + int0, and
////   any other rating p = f02 + per x (R - knee) x cos(pi / 2 x (R - knee) /
////   (R - knee + f03)); the chance is the smaller of p / 100 + base and int01 /
////   100 (`0x140453b60`).
//// - **The three rows.** Critical hit chance is row 1231 (`0x140463700`), critical
////   hit severity row 1232 (`0x140463e80`) and deflect chance row 1235
////   (`0x140463340`).
//// - **A player's bases** are the UnitProperty2 default of BaseCritChance (102),
////   CriticalHitSeverityMultiplier (127) and BaseAvoidChance (101); a Novice's
////   ratings for each are 0 (`player.level1_gear_properties`).

import genesis_prime/table/loader/store as table_store
import gleam/int

/// One GameFormula row as RatingToPercent reads it.
pub type Formula {
  Formula(f0: Float, f01: Float, f02: Float, f03: Float, int0: Int, int01: Int)
}

/// The three formulas of the hit rule and a player's bases, built once when the
/// tables load.
pub type Formulas {
  Formulas(
    crit_chance: Formula,
    crit_severity: Formula,
    deflect_chance: Formula,
    /// UnitProperty2 102's default, a player's BaseCritChance.
    player_base_crit_chance: Float,
    /// UnitProperty2 127's default, a player's CriticalHitSeverityMultiplier.
    player_base_crit_severity: Float,
  )
}

/// Why the formulas cannot be built from the tables.
pub type FormulasError {
  /// A table row the formulas name is missing: the table, and the id.
  NoRow(table: String, id: Int)
}

/// The chance, as a fraction, that the formula gives a unit of `level` with the
/// base `base` and the rating `rating` (`0x140453b60`).
pub fn to_fraction(
  formula formula: Formula,
  level level: Int,
  base base: Float,
  rating rating: Float,
) -> Float {
  unbuilt(inputs: #(formula, level, base, rating))
}

/// The formulas as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`): the three GameFormula rows and
/// the two UnitProperty2 defaults. A missing row fails the load.
pub fn derivation() -> table_store.Derivation {
  unbuilt(inputs: Nil)
}

/// The formulas the tables' load built.
pub fn formulas(tables tables: table_store.Tables) -> Formulas {
  unbuilt(inputs: tables)
}

/// A sentence that says why the formulas cannot be built, for the message the
/// server stops with.
pub fn describe(error error: FormulasError) -> String {
  let NoRow(table:, id:) = error
  "the table "
  <> table
  <> " has no row "
  <> int.to_string(id)
  <> ", which the hit rule's rating formulas name"
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
