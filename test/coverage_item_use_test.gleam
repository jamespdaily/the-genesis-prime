//// The item-use line of the coverage measure (`genesis_prime/coverage/item_use`), on the
//// client's real tables. Skipped where `GENESIS_NO_CLIENT=1`. Expected values come from
//// these places.
//// - Item2 rows with an ItemSpecial whose spell4IdOnActivate is not 0: 4,725 of the client's
////   72,106 (`table_rows -- ItemSpecial`, counted over Item2.itemSpecialId00).
//// - The items whose spell holds an Activate (7) or QuestAdvanceObjective (42) row, read from
////   Spell4Effects.effectType alone, are a floor for the played count: the server plays each
////   such item (by the shortcut plan or the activate cast). The test checks the floor, not
////   each item.

import client_tables
import genesis_prime/coverage/item_use
import genesis_prime/table/id
import genesis_prime/table/item2
import genesis_prime/table/item_special
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/set
import owned_test
import unitest

pub fn every_item_row_with_a_spell_is_counted_once_and_no_fewer_are_played_than_hold_an_activate_row_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.tag("coverage")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let report = item_use.measure(tables:)
  assert report.items_with_a_spell == 4725
    as "the client's Item2 rows that cast a spell"
  assert list.all(report.refused, fn(entry) { entry.0 != "" && entry.1 > 0 })
    as "each refusal has a reason and a row"
  let activating =
    spell4_effects.all(tables)
    |> list.filter(fn(row) { list.contains([7, 42], row.effect_type) })
    |> list.map(fn(row) { row.spell_id })
    |> set.from_list
  let activate_items =
    list.count(item2.all(tables), fn(row) {
      case
        item_special.get(tables:, id: id.ItemSpecialId(row.item_special_id00))
      {
        Ok(special) ->
          special.spell4_id_on_activate != 0
          && set.contains(activating, special.spell4_id_on_activate)
          && spell4.get(tables:, id: id.Spell4Id(special.spell4_id_on_activate))
          != Error(Nil)
        Error(Nil) -> False
      }
    })
  assert activate_items > 0
    as "the client holds items whose spell has an Activate or QuestAdvance row"
  assert report.played >= activate_items
    as "the played count is at least the items whose spell holds an Activate or QuestAdvance row"
}
