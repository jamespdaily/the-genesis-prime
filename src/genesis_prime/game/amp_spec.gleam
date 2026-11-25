//// The client's check of the AMPs a player picks (`0x1403d02a0`), as a pure rule.
////
//// ```
//// load: EldanAugmentation + EldanAugmentationCategory + GameFormula 942 ─▶ Specs
//// level ─▶ power_total(specs, level)                      the power a level gives
//// held ids + picked ids ─▶ check(specs, class_id, level, held, picks) ─▶ Ok, or the refusal
//// ```

import genesis_prime/table/eldan_augmentation
import genesis_prime/table/eldan_augmentation_category
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type ClassId, type EldanAugmentationId, GameFormulaId,
}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

/// The AMP rows, their categories and the power formula, read once at the tables' load.
pub opaque type Specs {
  Specs(
    amps: Dict(Int, eldan_augmentation.EldanAugmentation),
    categories: Dict(Int, eldan_augmentation_category.EldanAugmentationCategory),
    power: game_formula.GameFormula,
  )
}

/// The formula the client reads the AMP power from (`0x1403cdbf0`).
const power_formula = 942

const specs_key: table_store.DerivedKey(Specs) =
  table_store.DerivedKey("AmpSpecs")

/// Why the client's check refuses a list, with the number it names the result by.
pub type Refusal {
  /// The power is not enough: the total is below 1 or the costs pass it (31).
  NotEnoughPower(id: EldanAugmentationId, total: Int)
  /// An AMP has no row (35).
  InvalidId(id: EldanAugmentationId)
  /// An AMP belongs to another class (4).
  InvalidClass(id: EldanAugmentationId, class_id: ClassId)
  /// A category's tier 1 or 2 AMP is picked before enough power is spent in the category
  /// below it (33).
  LockedCategoryTier(category: Int, tier: Int, spent: Int, needed: Int)
  /// An AMP is picked without the AMP it requires (34).
  InvalidSeries(id: EldanAugmentationId, required: EldanAugmentationId)
}

/// The specs as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`).
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: specs_key, build: fn(tables) {
    use power <- result.map(
      game_formula.get(tables:, id: GameFormulaId(power_formula))
      |> result.replace_error("no GameFormula row 942, the AMP power"),
    )
    Specs(
      amps: eldan_augmentation.all(tables)
        |> list.map(fn(row) { #(row.id, row) })
        |> dict.from_list,
      categories: eldan_augmentation_category.all(tables)
        |> list.map(fn(row) { #(row.id, row) })
        |> dict.from_list,
      power:,
    )
  })
}

/// The specs the tables' load built.
pub fn specs(tables tables: table_store.Tables) -> Specs {
  table_store.derived(tables:, key: specs_key)
}

/// The power a level gives.
pub fn power_total(specs _specs: Specs, level _level: Int) -> Int {
  0
}

/// The client's check of the held AMPs followed by the picks.
pub fn check(
  specs _specs: Specs,
  class_id _class_id: ClassId,
  level _level: Int,
  held _held: List(EldanAugmentationId),
  picks _picks: List(EldanAugmentationId),
) -> Result(Nil, Refusal) {
  Ok(Nil)
}

/// The client's number for the result.
pub fn result_of(refusal refusal: Refusal) -> Int {
  case refusal {
    NotEnoughPower(..) -> 31
    InvalidId(..) -> 35
    InvalidClass(..) -> 4
    LockedCategoryTier(..) -> 33
    InvalidSeries(..) -> 34
  }
}

/// A sentence that says which AMP the check refused and why, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotEnoughPower(..) -> "not enough power"
    InvalidId(..) -> "no such AMP"
    InvalidClass(..) -> "another class"
    LockedCategoryTier(..) -> "category tier locked"
    InvalidSeries(..) -> "series incomplete"
  }
}
