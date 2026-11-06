//// A rating turned into a chance, as the client does for every rating: the
//// critical hit chance and severity, the deflect chance, the strikethrough, the
//// critical deflect, the glance chance and amount and the mitigation of a unit.
//// The hit rule (genesis_prime/game/hit) reads them.
////
//// ```
//// GameFormula 1230, 1231, 1232, 1234, 1235, 1236, 1245, 1271 ─▶ Formulas, once, when the tables load
//// to_fraction(formula, level, base, rating) ─▶ the chance, as a fraction
//// ```
////
//// - **The curve** is RatingToPercent: with per = f0 / L x f01 and knee =
////   (f02 - int0) / per, a rating below the knee gives p = per x R + int0, and
////   any other rating p = f02 + per x (R - knee) x cos(pi / 2 x (R - knee) /
////   (R - knee + f03)); the chance is the smaller of p / 100 + base and int01 /
////   100 (`0x140453b60`). A formula whose per is not positive gives p = int0.
//// - **The rows.** Critical hit chance is row 1231 (`0x140463700`), critical hit
////   severity 1232 (`0x140463e80`), deflect chance 1235 (`0x140463340`),
////   strikethrough 1230 (`0x140462ef0`), critical deflect 1236 (`0x140463ac0`),
////   glance chance 1245 and glance amount 1271 (`0x140453b60.callers`) and
////   mitigation 1234, never below 0 (`0x140464240`).
//// - **A player's bases** are the UnitProperty2 default of BaseCritChance (102),
////   CriticalHitSeverityMultiplier (127) and BaseAvoidReduceChance (104); a
////   Novice's ratings for each are 0 (`player.level1_gear_properties`). The
////   regeneration properties a player has no item for are read here too, as the
////   same kind of default: HealthRegenMultiplier (8) and ShieldTickTime (177)
////   (`UnitProperty2.176`).

import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId, UnitProperty2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/unit_property2
import gleam/bool
import gleam/float
import gleam/int
import gleam/result
import gleam_community/maths

/// One GameFormula row as RatingToPercent reads it.
pub type Formula {
  Formula(f0: Float, f01: Float, f02: Float, f03: Float, int0: Int, int01: Int)
}

/// The formulas of the hit rule and a player's bases, built once when the tables
/// load.
pub type Formulas {
  Formulas(
    crit_chance: Formula,
    crit_severity: Formula,
    deflect_chance: Formula,
    strikethrough: Formula,
    crit_deflect: Formula,
    glance_chance: Formula,
    glance_amount: Formula,
    mitigation: Formula,
    /// UnitProperty2 102's default, a player's BaseCritChance.
    player_base_crit_chance: Float,
    /// UnitProperty2 127's default, a player's CriticalHitSeverityMultiplier.
    player_base_crit_severity: Float,
    /// UnitProperty2 104's default, a player's BaseAvoidReduceChance.
    player_base_strikethrough: Float,
    /// UnitProperty2 8's default, a player's HealthRegenMultiplier.
    player_health_regen_multiplier: Float,
    /// UnitProperty2 177's default, a player's ShieldTickTime in milliseconds.
    player_shield_tick_ms: Int,
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
  let per = formula.f0 /. int.to_float(int.max(level, 1)) *. formula.f01
  let percent = percent_of(formula:, per:, rating:)
  float.min(percent /. 100.0 +. base, int.to_float(formula.int01) /. 100.0)
}

/// The percentage of the curve: linear below the knee, then the cosine tail
/// (`0x140453b60`); the formula's intercept when its slope is not positive.
fn percent_of(
  formula formula: Formula,
  per per: Float,
  rating rating: Float,
) -> Float {
  let intercept = int.to_float(formula.int0)
  use <- bool.guard(when: per <=. 0.0, return: intercept)
  let knee = { formula.f02 -. intercept } /. per
  use <- bool.guard(when: rating <. knee, return: per *. rating +. intercept)
  let beyond = rating -. knee
  formula.f02
  +. per
  *. beyond
  *. maths.cos(maths.pi() /. 2.0 *. beyond /. { beyond +. formula.f03 })
}

/// A mitigation as a fraction, never below 0 (`0x140464240`).
pub fn mitigation_fraction(
  formulas formulas: Formulas,
  level level: Int,
  base base: Float,
  rating rating: Float,
) -> Float {
  float.max(
    0.0,
    to_fraction(formula: formulas.mitigation, level:, base:, rating:),
  )
}

/// The formulas as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`): the GameFormula rows and the
/// five UnitProperty2 defaults. A missing row fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: formulas_key, build: fn(tables) {
    build(tables:) |> result.map_error(fn(error) { describe(error:) })
  })
}

const formulas_key: table_store.DerivedKey(Formulas) =
  table_store.DerivedKey("RatingFormulas")

/// Builds the formulas from the loaded tables, or why they cannot be built; the
/// derivation's body.
pub fn build(
  tables tables: table_store.Tables,
) -> Result(Formulas, FormulasError) {
  let formula = fn(number: Int) {
    game_formula.get(tables:, id: GameFormulaId(number))
    |> result.map(fn(row) {
      Formula(
        f0: row.datafloat0,
        f01: row.datafloat01,
        f02: row.datafloat02,
        f03: row.datafloat03,
        int0: row.dataint0,
        int01: row.dataint01,
      )
    })
    |> result.replace_error(NoRow(table: "GameFormula", id: number))
  }
  let default = fn(number: Int) {
    unit_property2.get(tables:, id: UnitProperty2Id(number))
    |> result.map(fn(row) { row.default_value })
    |> result.replace_error(NoRow(table: "UnitProperty2", id: number))
  }
  use strikethrough <- result.try(formula(1230))
  use crit_chance <- result.try(formula(1231))
  use crit_severity <- result.try(formula(1232))
  use mitigation <- result.try(formula(1234))
  use deflect_chance <- result.try(formula(1235))
  use crit_deflect <- result.try(formula(1236))
  use glance_chance <- result.try(formula(1245))
  use glance_amount <- result.try(formula(1271))
  use player_base_crit_chance <- result.try(default(102))
  use player_base_crit_severity <- result.try(default(127))
  use player_base_strikethrough <- result.try(default(104))
  use player_health_regen_multiplier <- result.try(default(8))
  use player_shield_tick_ms <- result.map(default(177))
  Formulas(
    crit_chance:,
    crit_severity:,
    deflect_chance:,
    strikethrough:,
    crit_deflect:,
    glance_chance:,
    glance_amount:,
    mitigation:,
    player_base_crit_chance:,
    player_base_crit_severity:,
    player_base_strikethrough:,
    player_health_regen_multiplier:,
    player_shield_tick_ms: float.round(player_shield_tick_ms),
  )
}

/// The formulas the tables' load built.
pub fn formulas(tables tables: table_store.Tables) -> Formulas {
  table_store.derived(tables:, key: formulas_key)
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
