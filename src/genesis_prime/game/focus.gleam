//// The numbers of a healer's Focus, as pure functions: what a Focus cost needs to be held,
//// the share of the pool recovered and what each tick adds. The pool itself, its timer and
//// its payments are the class resource's (genesis_prime/game/class_resource, slot -1).
////
//// ```
//// GameFormula 88, 1237, 1243, 1267 ─▶ Formulas, once, when the tables load
//// properties 5, 6, 56, 107, 108, 135, 158 and the level ─▶ Numbers
//// required_points(cost, modifier, intensity_fraction) ─▶ the whole points a press needs
//// share(numbers, in_combat) ─▶ per_tick(maximum, share) ─▶ the points a tick adds
//// ```
////
//// - **A cost needs `(int)(m x cost + 0.5)` whole points**, where `m` is the intensity fraction x GameFormula 1267's
////   datafloat01 + property 135 (`CheckInnateCost` 0x1403b3320 case 0xe, `FUN_140462a90`).
////   A negative cost is read by the client as an unsigned 32-bit number, about 4.29e9, and
////   a number past the 32-bit range comes out as -2147483648 (`required_points`); no
////   Spell4 row holds a negative Focus cost.
//// - **The intensity fraction** is RatingToPercent over GameFormula 1243 with the base
////   property 158 and the rating property 56, and 0 when both are 0 (`FUN_140462af0`, the
////   early return at 0x140462b15 to 0x140462b24).
//// - **The in-combat share** is RatingToPercent over GameFormula 1237 with the base
////   property 107 and the rating property 6 at the unit's level (`FUN_1404602f0`); **the
////   out-of-combat share** is property 108 alone (`GetFocusRegenNonCombat` 0x14064ac80).
//// - **A tick** adds the maximum x the share x GameFormula 88's dataint0 (500) x 0.001
////   (`GetFocusRegenInCombat` 0x14064a8b0): the client tells it as a per-tick amount of a
////   500 ms tick, which the server runs.
//// - **The level** is the player's one level, where the client reads its +0x3c word and
////   falls back to +0x38 (`FUN_140462af0`, `FUN_1404602f0`).

import genesis_prime/game/rating.{type Formula, Formula}
import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/message/float32
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/float
import gleam/int
import gleam/result

/// The GameFormula rows the Focus rule reads.
pub type Formulas {
  Formulas(
    /// GameFormula 88's dataint0: the milliseconds between two recovery ticks.
    tick_ms: Int,
    /// GameFormula 1237: the recovery rating's curve.
    recovery: Formula,
    /// GameFormula 1243: the cost intensity's curve.
    intensity: Formula,
    /// GameFormula 1267's datafloat01: what the intensity fraction adds to the cost
    /// modifier for each whole unit.
    intensity_weight: Float,
  )
}

/// A healer's properties the Focus rule reads, as the player's properties hold them.
pub type Numbers {
  Numbers(
    /// BaseFocusPool (5): the maximum.
    maximum: Float,
    /// RatingFocusRecovery (6).
    recovery_rating: Float,
    /// BaseFocusRecoveryInCombat (107).
    recovery_in_combat: Float,
    /// BaseFocusRecoveryOutofCombat (108).
    recovery_out_of_combat: Float,
    /// FocusCostModifier (135).
    cost_modifier: Float,
    /// RatingIntensity (56).
    intensity_rating: Float,
    /// BaseIntensity (158).
    intensity_base: Float,
    level: Int,
  )
}

/// Why the formulas cannot be built from the tables.
type FormulasError {
  /// A table row the Focus rule reads is missing: the table, and the id.
  NoRow(table: String, id: Int)
}

const formulas_key: table_store.DerivedKey(Formulas) =
  table_store.DerivedKey("FocusFormulas")

/// The formulas as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`). A missing row fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: formulas_key, build: fn(tables) {
    build(tables:) |> result.map_error(fn(error) { describe(error:) })
  })
}

/// Builds the formulas from the loaded tables, or why they cannot be built; the
/// derivation's body.
fn build(tables tables: table_store.Tables) -> Result(Formulas, FormulasError) {
  let row = fn(number: Int) {
    game_formula.get(tables:, id: GameFormulaId(number))
    |> result.replace_error(NoRow(table: "GameFormula", id: number))
  }
  let curve = fn(row: game_formula.GameFormula) {
    Formula(
      f0: row.datafloat0,
      f01: row.datafloat01,
      f02: row.datafloat02,
      f03: row.datafloat03,
      int0: row.dataint0,
      int01: row.dataint01,
    )
  }
  use tick <- result.try(row(88))
  use recovery <- result.try(row(1237))
  use intensity <- result.try(row(1243))
  use weight <- result.map(row(1267))
  Formulas(
    tick_ms: tick.dataint0,
    recovery: curve(recovery),
    intensity: curve(intensity),
    intensity_weight: weight.datafloat01,
  )
}

/// The formulas the tables' load built.
pub fn formulas(tables tables: table_store.Tables) -> Formulas {
  table_store.derived(tables:, key: formulas_key)
}

/// A sentence that says why the formulas cannot be built, for the message the server
/// stops with.
fn describe(error error: FormulasError) -> String {
  let NoRow(table:, id:) = error
  "the table "
  <> table
  <> " has no row "
  <> int.to_string(id)
  <> ", which the Focus rule reads"
}

/// The Focus rule's numbers from the player's properties: each property's value, and the
/// level.
pub fn numbers(properties properties: Properties) -> Numbers {
  let value = fn(property) { unit_properties.value(properties:, property:) }
  Numbers(
    maximum: value(unit_properties.focus_pool),
    recovery_rating: value(unit_properties.focus_recovery_rating),
    recovery_in_combat: value(unit_properties.focus_recovery_in_combat),
    recovery_out_of_combat: value(unit_properties.focus_recovery_out_of_combat),
    cost_modifier: value(unit_properties.focus_cost_modifier),
    intensity_rating: value(unit_properties.intensity_rating),
    intensity_base: value(unit_properties.intensity_base),
    level: unit_properties.level(properties:),
  )
}

/// The fraction the cost's intensity adds: 0 with a rating and a base of 0, else the
/// curve of GameFormula 1243 (`FUN_140462af0`).
pub fn intensity_fraction(
  formulas formulas: Formulas,
  numbers numbers: Numbers,
) -> Float {
  use <- bool.guard(
    when: numbers.intensity_rating == 0.0 && numbers.intensity_base == 0.0,
    return: 0.0,
  )
  rating.to_fraction(
    formula: formulas.intensity,
    level: numbers.level,
    base: numbers.intensity_base,
    rating: numbers.intensity_rating,
  )
}

/// The whole points of Focus a cost needs, as the client's check works them out: `m x cost +
/// 0.5` in 32-bit floats with `m` the cost modifier plus the intensity fraction x the
/// formula's weight, cut to a signed 32-bit whole number, where a value out of that range
/// gives -2147483648. The press passes when the whole points held are at least this
/// number. A cost of 0 or more is read as it is (`CheckInnateCost` 0x1403b3320 case 0xe,
/// 0x1403b37f0 to 0x1403b3813). A negative cost takes the other path (0x1403b33aa to
/// 0x1403b33d9): the cost is loaded zero-extended into 64 bits and converted as a signed
/// 64-bit number, so it is read as 2^32 + cost, and the cut number is taken as an absolute
/// value in 32 bits, which leaves -2147483648 as it is; a negative cost with a multiplier
/// from 0.5 up therefore passes. No Spell4 row holds a negative Focus cost
/// (`table_rows -- Spell4 innateCostType0=15`).
pub fn required_points(
  formulas formulas: Formulas,
  cost cost: Int,
  modifier modifier: Float,
  intensity_fraction intensity_fraction: Float,
) -> Int {
  let multiplier =
    float32.sum(
      left: float32.product(
        left: float32.rounded(intensity_fraction),
        right: formulas.intensity_weight,
      ),
      right: float32.rounded(modifier),
    )
  let unsigned_cost = case cost < 0 {
    True -> cost + unsigned_range
    False -> cost
  }
  let scaled =
    float32.product(
      left: multiplier,
      right: float32.rounded(int.to_float(unsigned_cost)),
    )
  let whole = float.truncate(float32.sum(left: scaled, right: 0.5))
  let cut = case whole < smallest_whole || whole > largest_whole {
    True -> smallest_whole
    False -> whole
  }
  case cost < 0 && cut != smallest_whole {
    True -> int.absolute_value(cut)
    False -> cut
  }
}

/// The 32-bit unsigned range, which the client reads a cost in.
const unsigned_range = 4_294_967_296

/// The smallest 32-bit signed whole number: what the client's float cut gives for a value
/// out of range, and what its absolute value leaves unchanged.
const smallest_whole = -2_147_483_648

const largest_whole = 2_147_483_647

/// The share of the pool recovered each second: in combat the curve of GameFormula 1237
/// over properties 107 and 6 at the level, out of combat property 108 alone.
pub fn share(
  formulas formulas: Formulas,
  numbers numbers: Numbers,
  in_combat in_combat: Bool,
) -> Float {
  case in_combat {
    True ->
      rating.to_fraction(
        formula: formulas.recovery,
        level: numbers.level,
        base: numbers.recovery_in_combat,
        rating: numbers.recovery_rating,
      )
    False -> numbers.recovery_out_of_combat
  }
}

/// The points one tick adds to a pool of `maximum` at the share `share`: the maximum x
/// the share x the tick in seconds (`GetFocusRegenInCombat` 0x14064a8b0).
pub fn per_tick(
  formulas formulas: Formulas,
  maximum maximum: Float,
  share share: Float,
) -> Float {
  maximum *. share *. int.to_float(formulas.tick_ms) *. 0.001
}
