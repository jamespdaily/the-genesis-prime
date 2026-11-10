//// The game connection's quest accept (`genesis_prime/game/connection/quest`,
//// `genesis_prime/game/quest`): the client's 0x035B read inside 0x038C with the player
//// in the world. Expected values come from these places.
//// - `opcode.0x35b` and `opcode.0x35c`: the dialog's accept is location 300, bag index
////   0xFFFFFFFF and the quest in 15 bits (0x2c ff ff ff ff then 1872 << 41, as the
////   message test works it by hand); the answer is the quest in 15 bits, the state 1
////   in 32 and the objective 0 in 32, so quest 1872 is 0x0750 and state 1 sets bit 15:
////   50 87 then eight zero bytes.
//// - Quest 1872 is a communicator quest (Quest2 flags 0x404, the fixture's row) with no
////   other condition for a level 1 player, so a log that holds it mentioned (state 5)
////   lets the dialog's accept take it without a giver in reach (`CanAcceptQuest`
////   `0x140552550`, check 11).
//// - The saved rows are the log's: 0x35f's entry for an accepted quest is tracked with
////   no objective done (`opcode.0x35f`, flag word 2 on a new entry), so the next save
////   writes the quest in state 1, not completed, with that entry.

import game_connection_support
import genesis_prime/client_connection.{AskStore}
import genesis_prime/message/quest_state
import genesis_prime/step.{OwnEvent, TimerFired, TimerId}
import genesis_prime/store.{Move, SavePlace}
import gleam/list
import gleam/option.{None, Some}
import owned_test
import quest_support

/// 0x035B of the dialog's place and quest 1872.
const accept_1872 = <<0x2c, 0xff, 0xff, 0xff, 0xff, 0xa1, 0x0e>>

/// 0x035C of quest 1872, state 1, objective 0.
const answer_1872 = <<0x50, 0x87, 0, 0, 0, 0, 0, 0, 0, 0>>

pub fn accepting_a_quest_answers_and_saves_it_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    game_connection_support.entered_with_quests(quests: [
      quest_support.known(1872, 5),
    ])
  let #(state, taken) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.world_message(
        message_id: 0x035B,
        body: accept_1872,
      ),
    )
  let answers =
    game_connection_support.written(taken:)
    |> list.filter(fn(frame) { frame.message_id == quest_state.message_id })
  assert list.map(answers, fn(frame) { frame.body }) == [answer_1872]
    as "opcode.0x35c: the accepted quest 1872 is answered once, in state 1 with objective 0"
  // The same request again: the quest is held (check 2), so nothing is sent.
  let #(state, taken) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.world_message(
        message_id: 0x035B,
        body: accept_1872,
      ),
    )
  assert game_connection_support.written(taken:) == []
    as "CanAcceptQuest 0x140552550 check 2: a quest already held is declined, and the connection goes on"
  // The save timer's next save carries the log.
  let #(_, taken) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2))))
  let assert AskStore(Move(SavePlace(quests:, ..))) =
    game_connection_support.ask_request(taken)
    as "the save timer asks the store to save the place and the log"
  let assert [row] = quests as "the log holds the one quest, now accepted"
  assert row.quest_id == 1872 && row.state == 1 && row.completed_at == None
    as "the accepted quest is saved in state 1, not completed"
  let assert Some(active) = row.active
    as "state 1 is in the client's active list"
  assert active.tracked
    && active.done_mask == 0
    && list.all(active.progress, fn(value) { value == 0 })
    as "opcode.0x35f: a new entry is tracked with no objective done and no progress"
}
