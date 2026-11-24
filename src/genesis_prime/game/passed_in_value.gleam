//// The passed-in value of an effect (parameter type 18): the number its formula multiplies
//// the parameter by (`0x140565600`).
////
//// ```
//// GameFormula 991, 65, 253 ─▶ the family-33 budget curve at each level 0 to 150 (once, at load)
//// a level ─▶ `of_level`             the value at that level
//// an Item2 ─▶ `of_item`             the value at the item's power level
//// ```
////
//// - **The value** is the family-33 item budget curve (`0x14041f1b0`) at the level the effect
////   is evaluated at (`0x1404de840`, `EvaluateEffectToken` `0x1404de8d0`): the caster's own
////   level, or for the spell of an item the item's level (`CasterItemLevel`,
////   `0x140675e20`), which is Item2.powerLevel (`0x14040d060`).
//// - **Not modelled:** the client moves an item's level for a mentored or PvP-flagged player
////   and by a world's bounds (`LevelScaleItemBudget` `0x14040f710`); the server has none of
////   that state, so an item's value is the curve at its power level. A guess.
//// - **An item with Item2.flags bit 3** builds at level 1 (`0x14040d060`); no item whose
////   spell holds a type 18 row has it, so `of_item` does not model it.

import genesis_prime/game/item_property
import genesis_prime/table/id.{type Item2Id}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// The curve at each level of 0 to `highest_level`, by level.
type Curve {
  Curve(values: Dict(Int, Float))
}

/// The highest level the curve is worked out for: the highest Item2.powerLevel.
pub const highest_level = 150

const curve_key: table_store.DerivedKey(Curve) =
  table_store.DerivedKey("PassedInValue")

/// The curve as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`); a GameFormula row the curve reads that
/// the tables lack fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: curve_key, build: fn(tables) {
    all_levels()
    |> list.try_map(fn(level) {
      item_property.rune_budget_curve(tables:, level:)
      |> result.map(fn(value) { #(level, value) })
      |> result.map_error(item_property.describe)
    })
    |> result.map(fn(values) { Curve(values: dict.from_list(values)) })
  })
}

fn all_levels() -> List(Int) {
  int.range(from: 0, to: highest_level + 1, with: [], run: fn(levels, level) {
    [level, ..levels]
  })
  |> list.reverse
}

/// The passed-in value at `level`: the curve the tables' load built, a level above its end
/// read at its end.
pub fn of_level(tables tables: table_store.Tables, level level: Int) -> Float {
  let curve = table_store.derived(tables:, key: curve_key)
  let assert Ok(value) =
    dict.get(curve.values, int.clamp(level, min: 0, max: highest_level))
    as "the curve holds every level from 0 to its highest"
  value
}

/// The passed-in value of the spell of an item: the curve at the item's level.
pub fn of_item(
  tables tables: table_store.Tables,
  item2_id item2_id: Item2Id,
) -> Float {
  of_level(tables:, level: level_of_item(tables:, item2_id:))
}

/// The level of an item's spell: Item2.powerLevel. The item's row is in the tables: the use
/// check read it, and a worn item's row is one the gear read. Every item whose spell holds a
/// type 18 row has Item2.flags bit 20, the power-level override, so the row's own powerLevel
/// stands (the server sends 0 in 0x111 `field_27`, still open).
pub fn level_of_item(
  tables tables: table_store.Tables,
  item2_id item2_id: Item2Id,
) -> Int {
  let assert Ok(row) = item2.get(tables:, id: item2_id)
    as "the item's Item2 row is in the tables: the use check and the gear read it"
  row.power_level
}
