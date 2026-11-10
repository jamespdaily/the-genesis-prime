//// What the load derives for the communicator (`genesis_prime/game/communicator`): the
//// CommunicatorMessages rows of each quest they deliver, and the creatures that receive
//// each quest. Expected values come from the client's rows.

import character_tables
import genesis_prime/game/communicator
import owned_test

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
