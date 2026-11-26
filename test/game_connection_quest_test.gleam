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
//// - Quest 10510 "Learning to Shop" (Quest2 flags 0x0C, level 3) has one objective,
////   QuestObjective 21267, a purchase in the In-Game Store: scripted (type 5), which the
////   client never completes (`QuestObjective.type.5`), and held by the server. Its
////   Prerequisite 43306 holds type 288, whose set the client fills only from 0x018A and
////   0x018B (`opcode.0x18a`, `opcode.0x18b`), and type 109, which refuses Worlds 1537, 1634
////   and 3460.
//// - The saved rows are the log's: 0x35f's entry for an accepted quest is tracked with
////   no objective done (`opcode.0x35f`, flag word 2 on a new entry), so the next save
////   writes the quest in state 1, not completed, with that entry.

import cast_support
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{AskStore}
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/message/quest_log as quest_log_message
import genesis_prime/message/quest_objective_progress
import genesis_prime/message/quest_state.{QuestState}
import genesis_prime/step.{OwnEvent, TimerFired, TimerId}
import genesis_prime/store.{Character, Move, SavePlace}
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import planted_table.{Integer}
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
  assert row.quest_id == 1872
    && quest_support.state_of(row) == 1
    && quest_support.completed_at_of(row) == None
    as "the accepted quest is saved in state 1, not completed"
  let assert Some(active) = quest_support.active_of(row)
    as "state 1 is in the client's active list"
  assert active.tracked
    && active.done_mask == 0
    && list.all(active.progress, fn(value) { value == 0 })
    as "opcode.0x35f: a new entry is tracked with no objective done and no progress"
}

/// 0x035B of the dialog's place (location 300, bag index 0xFFFFFFFF) for this quest.
fn accept_message(quest_id quest_id: Int) -> BitArray {
  let assert Ok(body) =
    quest_accept.encode(QuestAccept(
      item: ItemPlace(location: 300, bag_index: 0xFFFFFFFF),
      quest_id:,
    ))
    as "the request fits its fields"
  game_connection_support.world_message(message_id: 0x035B, body:)
}

pub fn accepting_learning_to_shop_leaves_its_store_purchase_open_across_the_save_and_the_login_test() -> Nil {
  use <- owned_test.run(30_000)
  // Quest2 10510 (flags 0x0C, level 3, either faction) names Prerequisite 43306: title 400
  // not owned (type 288, comparison 2) and a world other than 1537, 1634 and 3460 (41782).
  // The tests' character stands in World 3460, so its third world is changed to 1000 here;
  // the real row's worlds are tested at the end and in `quest_accept_test`.
  use tables <- fixture_tables.changed(table: "Prerequisite", id: 41_782, with: [
    #("objectId2", Integer(1000)),
  ])
  let character =
    Character(..game_connection_support.world_character(), level: 3)
  let mentioned = [quest_support.known(10_510, 5)]
  let holding_it = fn(held) {
    Settings(
      ..game_connection_support.settings(),
      tables:,
      held_objectives: set.from_list(held),
    )
  }
  let accept = fn(state) {
    game_connection_support.read(
      state:,
      bytes: accept_message(quest_id: 10_510),
    )
  }
  let #(state, entry) =
    game_connection_support.entered_under(
      settings: holding_it([21_267]),
      character:,
      quests: mentioned,
    )
  let #(state, taken) = accept(state)
  let answers = game_connection_support.written(taken:)
  assert game_connection_support.decoded(
      answers,
      quest_state.message_id,
      quest_state.decode,
    )
    == [QuestState(quest_id: 10_510, state: 1, objective_id: 0)]
    as "opcode.0x35c: the accepted quest is answered once, in state 1 with objective 0, and no state 2 follows"
  assert !list.contains(
    cast_support.ids(frames: answers),
    quest_objective_progress.message_id,
  )
    as "opcode.0x361: nothing is counted for the held store purchase"
  // The save timer's next save carries the log.
  let #(_, saving) =
    game_connection_support.feed(state, OwnEvent(TimerFired(TimerId(2))))
  let assert AskStore(Move(SavePlace(quests: saved, ..))) =
    game_connection_support.ask_request(saving)
    as "the save timer asks the store to save the place and the log"
  let assert [row] = saved as "the log holds the one quest"
  assert row.quest_id == 10_510
    && quest_support.state_of(row) == 1
    && quest_support.completed_at_of(row) == None
    as "the quest is saved in state 1, not completed"
  let assert Some(active) = quest_support.active_of(row)
    as "state 1 is in the client's active list"
  assert active.done_mask == 0 && active.progress == [0]
    as "opcode.0x35f: the store purchase is not done"
  // A new connection entered from the saved row.
  let #(_, login) =
    game_connection_support.entered_under(
      settings: holding_it([21_267]),
      character:,
      quests: saved,
    )
  let login_frames = game_connection_support.written(taken: login)
  let assert [log] =
    game_connection_support.decoded(
      login_frames,
      quest_log_message.message_id,
      quest_log_message.decode,
    )
    as "a login writes 0x35F"
  let assert [shopping] =
    list.filter(log.active, fn(active) { active.quest_id == 10_510 })
    as "the log holds Learning to Shop"
  assert shopping.state == 1 && shopping.progress == [0]
    as "opcode.0x35f: still accepted, with no progress"
  assert list.filter(cast_support.ids(frames: login_frames), fn(id) {
      id == quest_objective_progress.message_id || id == quest_state.message_id
    })
    == []
    as "the login's settle leaves a held objective open: no 0x361 and no 0x35c"
  // The same accept with no hold: the stand-in completes it, so the hold is what keeps
  // the quest open above.
  let #(state, _) =
    game_connection_support.entered_under(
      settings: holding_it([]),
      character:,
      quests: mentioned,
    )
  let #(_, completing) = accept(state)
  let completing_frames = game_connection_support.written(taken: completing)
  assert list.filter(cast_support.ids(frames: completing_frames), fn(id) {
      id == quest_objective_progress.message_id || id == quest_state.message_id
    })
    == [
      quest_state.message_id,
      quest_objective_progress.message_id,
      quest_state.message_id,
    ]
    as "with no hold: 0x35c state 1, 0x361 for the objective, then 0x35c state 2"
  // The client's title set is filled only by 0x018A and 0x018B, so with neither sent it
  // is empty and type 288 reads 'no title owned'. A step that starts sending them must
  // give the condition its real set.
  let everything =
    list.flatten([
      cast_support.ids(frames: game_connection_support.written(taken: entry)),
      cast_support.ids(frames: answers),
      cast_support.ids(frames: login_frames),
      cast_support.ids(frames: completing_frames),
    ])
  assert !list.contains(everything, 0x018A)
    && !list.contains(everything, 0x018B)
    as "opcode.0x18a and opcode.0x18b: the server sends no owned title"
  // The real row: World 3460 is refused by Prerequisite 41782, as the client's own check
  // refuses it, and a request the client would not send is left unanswered.
  let #(state, _) =
    game_connection_support.entered_under(
      settings: game_connection_support.settings(),
      character:,
      quests: mentioned,
    )
  let #(_, refused) = accept(state)
  assert game_connection_support.written(taken: refused) == []
    as "Prerequisite 41782 names World 3460: the quest is refused there and nothing is sent"
}
