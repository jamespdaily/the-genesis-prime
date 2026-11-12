//// What the load derives for the communicator (`genesis_prime/game/communicator`): the
//// CommunicatorMessages rows of each quest they deliver, and the creatures that receive
//// each quest. Expected values come from the client's rows.

import character_tables
import client_tables
import genesis_prime/game/communicator
import genesis_prime/table/id.{Quest2Id}
import genesis_prime/table/quest2
import gleam/int
import gleam/list
import owned_test
import unitest

pub fn deliveries_hold_every_row_by_quest_delivered_test() -> Nil {
  use <- owned_test.run(10_000)
  // `0x14043add0` files each row under its questIdDelivered, whatever its flags: rows
  // 1281 and 2081 (flags 1) deliver 3673, row 1907 delivers 3741. A row's quest00 is
  // not its delivery, and quest 0 has no rows.
  let tables = character_tables.shared()
  assert communicator.delivering_row_ids(tables:, quest_id: 3673)
    == [1281, 2081]
  assert communicator.delivering_row_ids(tables:, quest_id: 3741) == [1907]
  assert communicator.delivering_row_ids(tables:, quest_id: 0) == []
}

pub fn receivers_of_a_quest_are_its_creature2_rows_test() -> Nil {
  use <- owned_test.run(10_000)
  // The creatures whose questIdReceive00 to 24 name the quest, with their factionId
  // (`0x14043c700`'s receiver): Creature2 11063, 12959 and 16622 (faction 171) receive
  // 3673; 30336 (faction 170) receives 6654.
  let tables = character_tables.shared()
  assert communicator.receivers_of(tables:, quest_id: 3673)
    == [#(11_063, 171), #(12_959, 171), #(16_622, 171)]
  assert communicator.receivers_of(tables:, quest_id: 6654) == [#(30_336, 170)]
}

pub fn the_server_completes_1313_quests_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Measured over the client's Quest2 and Creature2 tables: of 5194 quests, 1368 have no
  // creature that receives them and no flag 0x10000 (the communicator's turn-in by row),
  // and 55 of those are contracts (flag 0x80000, `Contract:Complete` `0x1406a3ba0`).
  let tables = client_tables.shared()
  let quests = quest2.all(tables)
  let unreceived =
    list.filter(quests, fn(quest) {
      communicator.receivers_of(tables:, quest_id: quest.id) == []
      && int.bitwise_and(quest.flags, 0x10000) == 0
    })
  let contracts =
    list.filter(unreceived, fn(quest) {
      int.bitwise_and(quest.flags, 0x80000) != 0
    })
  assert list.length(quests) == 5194
  assert list.length(unreceived) == 1368
  assert list.length(contracts) == 55
  assert list.length(
      list.filter(quests, fn(quest) {
        communicator.completed_by_server(tables:, quest:)
      }),
    )
    == 1313
    as "the predicate holds for the 1313 quests that are neither received, by row nor contracts"
}

pub fn the_tutorials_giver_less_quests_are_completed_by_the_server_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // The Exile tutorial's quests no creature gives or receives (Quest2.10513's completion
  // text says the server decides when they end): the predicate holds for each.
  let tables = client_tables.shared()
  list.each(
    [10_513, 10_527, 10_518, 10_529, 10_521, 10_532, 10_524, 10_533],
    fn(quest_id) {
      let assert Ok(quest) = quest2.get(tables:, id: Quest2Id(quest_id))
        as {
          "Quest2 " <> int.to_string(quest_id) <> " is in the client's table"
        }
      assert communicator.receivers_of(tables:, quest_id:) == []
        as { "no creature receives " <> int.to_string(quest_id) }
      assert communicator.completed_by_server(tables:, quest:)
        as { "the server completes " <> int.to_string(quest_id) }
    },
  )
}
