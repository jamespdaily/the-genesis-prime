//// Which entries of the game connection send 0x025E, the player character's own
//// state, run as the pure rule it is (`genesis_prime/game/connection`).
//// Expected values come from these places.
//// - `opcode.0x25e.entry_order`: a second world entry from character select
////   (a character switch, a new 0xAD) makes the client a new game object, so its
////   handler runs on fresh state and the message is sent again; a second copy in
////   the same game object adds its items and pets again and raises
////   CharacterCreated again.
//// - `0x1403b6de0`: the client's handler of a 0xAD while in the world (the
////   Holocrypt's join) removes the units and loads the world again on the same
////   game object, so the Holocrypt's burst sends no second 0x25E.

import game_connection_support
import genesis_prime/message/player_character_state
import gleam/list
import owned_test

fn count_of_0x25e(ids ids: List(Int)) -> Int {
  list.count(ids, fn(id) { id == player_character_state.message_id })
}

pub fn a_second_entry_from_character_select_sends_0x25e_again_once_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(first, first_taken) = game_connection_support.entered()
  assert count_of_0x25e(ids: game_connection_support.written_ids(first_taken))
    == 1
    as "opcode.0x25e.entry_order: the first entry sends it once"
  let #(_, second_taken) =
    game_connection_support.entered_from(
      in_character_select: game_connection_support.camp_from(first),
      character: game_connection_support.world_character(),
    )
  let second = game_connection_support.written_ids(second_taken)
  assert count_of_0x25e(ids: second) == 1
    as "opcode.0x25e.entry_order: a character switch is a new game object in the client, which needs its own 0x25E, once"
  assert list.take_while(second, fn(id) { id != 0x019B }) == [0x00AD, 0x0262]
    as "and it comes after 0xAD, 0x262 and 0x19B as in the first entry"
  assert list.drop_while(second, fn(id) { id != 0x019B })
    |> list.take(2)
    == [0x019B, 0x025E]
    as "right after 0x19B"
}

pub fn the_holocrypts_rejoin_in_the_same_game_object_sends_no_second_0x25e_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, first) = game_connection_support.entered()
  assert count_of_0x25e(ids: game_connection_support.written_ids(first)) == 1
    as "the play's entry sends it"
  let #(_, rejoined) = game_connection_support.at_the_holocrypt()
  let ids = game_connection_support.written_ids(rejoined)
  assert list.contains(ids, 0x00AD) && list.contains(ids, 0x019B)
    as "0x1403b6de0: the join at the Holocrypt is a 0xAD in the world and a 0x19B again, the burst of an entry"
  assert count_of_0x25e(ids:) == 0
    as "opcode.0x25e.entry_order: a second 0x25E in the same game object would add its items and pets again and raise CharacterCreated again"
}
