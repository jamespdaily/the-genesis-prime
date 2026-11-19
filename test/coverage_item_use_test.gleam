//// The item-use line of the coverage measure (`genesis_prime/coverage/item_use`), on the
//// client's real tables. Skipped where `GENESIS_NO_CLIENT=1`; run with
//// `gleam test -- --tag coverage`. Expected values come from these places.
//// - Item2 rows with an ItemSpecial whose spell4IdOnActivate is not 0: 4,725 of the client's
////   72,106 (`table_rows -- ItemSpecial`, counted over Item2.itemSpecialId00).
//// - Before items played the spells cast on their user, the activate cast played 46 of
////   them (the spells holding an Activate or QuestAdvanceObjective row).

import client_tables
import genesis_prime/coverage/item_use
import gleam/list
import owned_test
import unitest

pub fn every_item_row_with_a_spell_is_counted_once_and_more_are_played_than_before_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.tags(["dev_tool", "coverage"])
  use <- unitest.guard(client_tables.present())
  let report = item_use.measure(tables: client_tables.shared())
  let refused = list.fold(report.refused, 0, fn(sum, entry) { sum + entry.1 })
  assert report.items_with_a_spell == 4725
    as "the client's Item2 rows that cast a spell"
  assert report.played + refused == report.items_with_a_spell
    as "each row is played, or refused with a reason, once"
  assert report.played > 46
    as "more items are played than the 46 the activate cast played"
  assert report.refused != [] as "some are refused, each with its reason"
}
