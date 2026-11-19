//// The development commands on the game connection (`genesis_prime/game/connection/dev_command`),
//// run as the pure rule it is: a line said on Say in, the frames and effects out. Expected
//// values come from these places.
//// - `opcode.0x1ac`: the client takes experience only by message, adding the first value to
////   its own; the source kind 1 is Cheat (`opcode.0x1ac.kind.1`). No message lowers it.
//// - `opcode.0x938`: stat 10 is the level. `opcode.0x169`: ability points, 0 for levels 1 to
////   9 (XpPerLevel.abilityPointsPerLevel).
//// - XpPerLevel.minXpForLevel: level 3 from 1710, 4 from 2860, 9 from 17330.
//// - The rise's frames are those of a gain of any source: `experience_book_test` (a Medic's
////   3 to 4 writes 0x1ac, 0x938, 0x111, 0x1a0, 0x93a, with the ability of Spell4Base 26038
////   in slot 4; 5 to 6 adds 25530, 25579 and 38210) and `experience_points_test`.
//// - `SpellLevel.spell4Id.no_prerequisite`: the committed rows hold a Medic's abilities up to
////   level 6 (`ability_book_test`): 614 (level 4, Spell4Base 26038), 1087 (5, 25692), 1191,
////   1194 and 1221 (6, 25530, 25579, 38210). A rise to level 9 grants all five, in that
////   order, in slots 4 to 8 after the bag of 4 items, and one 0x1a0 holds each at tier 1 in
////   the four action sets (`opcode.0x1a0`).
//// - The line each command is answered with is the design's choice (a System line,
////   ChatChannel row 2).
//// - `opcode.0x35c.complete_unheld`, `0x1405fbdc0.state_3`: the client takes 0x35c state 3
////   for a quest with no log entry. Quest2 2910 holds a limit of 30000 ms, 1857 is daily
////   (questRepeatPeriodEnum 1) and 10503 yearly (4); the tests' clock is 2025-04-24 20:26:40
////   UTC, the latest daily reset 2025-04-24 10:00 and the latest yearly reset 2025-01-01
////   10:00 (`quest_log_test`).
//// - QuestObjective 18604 (type 24, data 9695) of Quest2 9497 is done when quest 9695 is
////   finished; no Creature2 row receives 9497 or 9695, so the server completes them
////   (`communicator.completed_by_server`).

import ability_book_support as book_support
import ability_points_support as points_support
import connection_rule_support as rule_support
import experience_support
import game_connection_dev_command_support as dev_support
import game_connection_support as support
import genesis_prime/client_connection.{type Answer, type Request, FromStore}
import genesis_prime/game/chat_channel
import genesis_prime/game/chat_tell
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/disconnect_reason.{
  AccountDisconnected, LostUserServer,
}
import genesis_prime/message/experience_gained.{ExperienceGained}
import genesis_prime/message/player_health
import genesis_prime/message/quest_objective_progress.{QuestObjectiveProgress}
import genesis_prime/message/quest_state.{type QuestState, QuestState}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, type Outcome,
  ConnectionId, OwnEvent, StoppedWaiting, TimerId, WatchEnded, WatchId, Woken,
}
import genesis_prime/store
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import quest_support
import quest_turn_in_support

/// A Medic (class 4), level 3, holding 1800 experience: 90 past level 3's 1710.
fn medic() -> game_connection.State {
  dev_support.in_world_at(class_id: 4, level: 3, experience: 1800)
}

/// One raise: the line said, what the frames start and end with, the gain and
/// the levels written, the abilities the rise adds (bag index and Spell4Base, in order),
/// the line answered and what the player holds afterwards.
type Raise {
  Raise(
    text: String,
    starts: List(Int),
    ends: List(Int),
    gain: Int,
    levels: List(Int),
    added: List(#(Int, Int)),
    line: String,
    held: #(Int, Int),
    why: String,
  )
}

pub fn a_raise_writes_the_frames_of_an_experience_gain_and_the_level_rise_then_one_line_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Raise(
        text: "!level 4",
        starts: [0x01C2, 0x01AC, 0x0938, 0x0111],
        ends: [0x01A0, 0x093A, 0x01C8],
        gain: 1060,
        levels: [4],
        added: [#(4, 26_038)],
        line: "level 4, experience 2860",
        held: #(4, 2860),
        why: "level 4 starts at 2860, 1060 above 1800; the Medic's 3 to 4 adds Spell4Base 26038",
      ),
      Raise(
        text: "!xp 2859",
        starts: [0x01C2, 0x01AC],
        ends: [0x01AC, 0x01C8],
        gain: 1059,
        levels: [],
        added: [],
        line: "level 3, experience 2859",
        held: #(3, 2859),
        why: "2859 is one short of level 4: a gain and no level",
      ),
      Raise(
        text: "!level 9",
        starts: [0x01C2, 0x01AC, 0x0938],
        ends: [0x01A0, 0x093A, 0x01C8],
        gain: 15_530,
        levels: [9],
        added: [
          #(4, 26_038),
          #(5, 25_692),
          #(6, 25_530),
          #(7, 25_579),
          #(8, 38_210),
        ],
        line: "level 9, experience 17330",
        held: #(9, 17_330),
        why: "level 9 starts at 17330: one 0x938 for the whole jump, and the five abilities the rows hold for levels 4 to 6",
      ),
    ],
    fn(row) {
      let #(state, taken) = dev_support.said(state: medic(), text: row.text)
      let ids = support.written_ids(taken)
      assert list.take(ids, list.length(row.starts)) == row.starts as row.why
      assert list.drop(ids, list.length(ids) - list.length(row.ends))
        == row.ends
        as "the frames end with the player's line"
      assert experience_support.gains(taken:)
        == [
          ExperienceGained(
            experience: row.gain,
            rest_experience_used: 0,
            bonus_experience: 0,
            source_kind: 1,
            source_unit_id: 0,
          ),
        ]
        as row.why
      assert list.map(experience_support.level_writes(taken:), fn(written) {
          written.1
        })
        == row.levels
        as row.why
      let frames = book_support.written(taken:)
      let added = book_support.added_in(frames:)
      assert list.map(added, fn(item) { #(item.bag_index, item.base) })
        == row.added
        as "the rise adds exactly the abilities its levels grant, in order, once each"
      assert list.all(added, fn(item) { item.reason == 49 })
        as "opcode.0x111.ability_level_up: reason 49, as the entry's"
      assert book_support.tiers_in(frames:)
        == book_support.tiers_of(
          bases: list.map(row.added, fn(item) { item.1 }),
        )
        as "one 0x1a0 holds each added ability at tier 1 in the four action sets"
      assert points_support.points_in(frames:) == []
        as "levels 1 to 9 give no ability points"
      assert support.system_lines(taken) == [row.line] as row.why
      let #(_, experience, level) = experience_support.camped(state:)
      assert #(level, experience) == row.held
        as "the player holds the level and experience reached"
    },
  )
}

pub fn a_lowering_or_an_equal_target_changes_nothing_and_says_so_in_one_system_line_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        "!level 2",
        "!level 2 would lower level 3; the client takes experience only upward: use a character at or below level 2",
        "a level below the held 3",
      ),
      #(
        "!xp 1500",
        "!xp 1500 would lower experience 1800; the client takes experience only upward: use a character at or below experience 1500",
        "an experience below the held 1800",
      ),
      #(
        "!xp 1800",
        "already at level 3, experience 1800",
        "the experience held",
      ),
      #(
        "!level 3",
        "already at level 3, experience 1800",
        "the level held, though 1800 is above its 1710",
      ),
    ],
    fn(row) {
      let #(state, taken) = dev_support.said(state: medic(), text: row.0)
      assert support.written_ids(taken) == [0x01C2, 0x01C8]
        as "opcode.0x1ac: no frame lowers the client's experience, so none is written"
      assert support.system_lines(taken) == [row.1] as row.2
      let #(_, experience, level) = experience_support.camped(state:)
      assert #(level, experience) == #(3, 1800) as "nothing changed"
    },
  )
}

pub fn the_next_save_holds_the_commanded_level_and_experience_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = dev_support.said(state: medic(), text: "!level 4")
  let #(_, taken) =
    support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert client_connection.AskStore(store.Move(store.SavePlace(
    experience:,
    level:,
    ..,
  ))) = support.ask_request(taken)
    as "the save timer asks the store to save the place"
  assert #(level, experience) == #(4, 2860)
    as "XpPerLevel: level 4 starts at 2860, which the save keeps"
}

pub fn each_accepted_command_is_logged_once_at_info_and_a_refused_one_not_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, accepted) = dev_support.said(state: medic(), text: "!level 4")
  let assert [line] = rule_support.logs_of(step: accepted, level: step.LogInfo)
    as "one info line for an accepted command"
  assert string.contains(line.text, "!level 4")
    && string.contains(line.text, "experience 1800")
    && string.contains(line.text, "experience 2860")
    as "it names the command and the values it changed"
  let #(_, refused) = dev_support.said(state: medic(), text: "!level 51")
  assert rule_support.logs(refused) == []
    as "a refused command is its System line, with no log"
}

// ---------------------------------------------------------------- !quest

/// The Unix seconds of the tests' clock: the FILETIME 133,900,000,000,000,000 is
/// 2025-04-24 20:26:40 UTC.
const now_seconds = 1_745_526_400

/// The daily quest reset before `now_seconds`: 2025-04-24 10:00 UTC
/// (`quest_log_test`).
const daily_reset_seconds = 1_745_488_800

/// The first FILETIME after the next daily reset (2025-04-25 10:00 UTC, one second
/// past it) and after the next yearly reset (2026-01-01 10:00 UTC, one second past
/// it).
const after_the_next_daily_reset = 133_900_488_010_000_000

const after_the_next_yearly_reset = 134_117_352_010_000_000

/// The quest states the step writes, decoded.
fn quest_states_written(
  taken taken: ConnectionStep(Request),
) -> List(QuestState) {
  support.decoded(
    support.written(taken:),
    quest_state.message_id,
    quest_state.decode,
  )
}

/// The effects of the step that start or cancel the quest deadline timer.
fn deadline_timer_effects(
  taken taken: ConnectionStep(Request),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  list.filter(rule_support.effects_of(taken), fn(effect) {
    case effect {
      step.OwnEffect(step.StartTimer(timer:, ..))
      | step.OwnEffect(step.CancelTimer(timer:)) ->
        timer == connection_state.quest_deadline_timer
      step.OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> False
    }
  })
}

/// One quest done by command: what the log holds, the quest, the timer effects the step
/// holds, and why.
type Completion {
  Completion(
    held: List(store.QuestRow),
    quest_id: Int,
    timer: List(step.Effect(step.ConnectionEffect(Request))),
    why: String,
  )
}

pub fn a_completed_quest_is_completed_in_the_log_and_told_as_state_3_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Completion(
        held: [],
        quest_id: 5972,
        timer: [],
        why: "a quest with no entry: the client takes state 3 for it (opcode.0x35c.complete_unheld)",
      ),
      Completion(
        held: [quest_support.timed(2910, progress: [0], quest_ms_left: 0)],
        quest_id: 2910,
        timer: [
          step.OwnEffect(step.CancelTimer(connection_state.quest_deadline_timer)),
        ],
        why: "Quest2 2910's limit is 30000 ms: the entry's running deadline timer is cancelled with the quest completed",
      ),
      Completion(
        held: [quest_turn_in_support.achieved(quest_id: 10_520)],
        quest_id: 10_520,
        timer: [],
        why: "an Achieved quest a creature receives is completed in the log as well",
      ),
    ],
    fn(row) {
      let state =
        dev_support.in_world_holding_quests(level: 1, quests: row.held)
      let #(state, taken) =
        dev_support.said(
          state:,
          text: "!quest " <> int.to_string(row.quest_id) <> " done",
        )
      assert support.written_ids(taken) == [0x01C2, 0x035C, 0x01C8] as row.why
      assert quest_states_written(taken:)
        == [QuestState(quest_id: row.quest_id, state: 3, objective_id: 0)]
        as row.why
      assert support.system_lines(taken)
        == ["quest " <> int.to_string(row.quest_id) <> " completed"]
        as row.why
      assert deadline_timer_effects(taken:) == row.timer as row.why
      assert dev_support.saved_quests(state:)
        == [quest_support.completed(row.quest_id, at: now_seconds)]
        as "the log holds the quest Completed at now, and nothing else"
    },
  )
}

pub fn a_quest_already_done_is_answered_so_and_writes_no_frame_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        quest_support.completed(quest_support.one_time, at: 1_700_000_000),
        "a quest with no period that was completed",
      ),
      #(
        quest_support.completed(
          quest_support.daily,
          at: daily_reset_seconds + 100,
        ),
        "a daily quest completed after the latest daily reset",
      ),
    ],
    fn(row) {
      let held = row.0
      let state = dev_support.in_world_holding_quests(level: 1, quests: [held])
      let #(state, taken) =
        dev_support.said(
          state:,
          text: "!quest " <> int.to_string(held.quest_id) <> " done",
        )
      assert support.written_ids(taken) == [0x01C2, 0x01C8] as row.1
      assert support.system_lines(taken)
        == ["quest " <> int.to_string(held.quest_id) <> " is already done"]
        as row.1
      assert dev_support.saved_quests(state:) == [held]
        as "the entry is as it was"
      assert rule_support.logs(taken) == []
        as "a command that changes nothing is its line, with no log"
    },
  )
}

pub fn a_periodic_quest_done_in_an_earlier_period_is_completed_again_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        quest_support.daily,
        daily_reset_seconds - 1,
        "one second before the latest daily reset",
      ),
      #(
        10_503,
        1_735_646_400,
        "before the latest yearly reset, 2025-01-01 10:00 UTC",
      ),
    ],
    fn(row) {
      let held = quest_support.completed(row.0, at: row.1)
      let state = dev_support.in_world_holding_quests(level: 1, quests: [held])
      let #(state, taken) =
        dev_support.said(
          state:,
          text: "!quest " <> int.to_string(row.0) <> " done",
        )
      assert quest_states_written(taken:)
        == [QuestState(quest_id: row.0, state: 3, objective_id: 0)]
        as row.2
      assert dev_support.saved_quests(state:)
        == [quest_support.completed(row.0, at: now_seconds)]
        as "the entry is Completed at now"
    },
  )
}

pub fn a_periodic_quests_completion_is_read_the_same_after_a_relog_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(quest_support.daily, after_the_next_daily_reset, "the daily reset"),
      #(10_503, after_the_next_yearly_reset, "the yearly reset"),
    ],
    fn(row) {
      let text = "!quest " <> int.to_string(row.0) <> " done"
      let #(first, _) =
        dev_support.said(
          state: dev_support.in_world_holding_quests(level: 1, quests: []),
          text:,
        )
      let saved = dev_support.saved_quests(state: first)
      assert saved == [quest_support.completed(row.0, at: now_seconds)]
        as "the command's completion is saved at now"
      let #(_, before_the_reset) =
        dev_support.said(
          state: dev_support.in_world_holding_quests(level: 1, quests: saved),
          text:,
        )
      assert support.system_lines(before_the_reset)
        == ["quest " <> int.to_string(row.0) <> " is already done"]
        as "a new login before the reset reads the saved row as finished"
      let relogged =
        dev_support.in_world_holding_quests(level: 1, quests: saved)
      let #(_, after_the_reset) =
        dev_support.said_at(state: relogged, text:, filetime: row.1)
      assert quest_states_written(taken: after_the_reset)
        == [QuestState(quest_id: row.0, state: 3, objective_id: 0)]
        as row.2
    },
  )
}

pub fn the_quest_the_command_completes_finishes_the_quest_waiting_on_it_and_the_server_completes_that_one_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quest2 9497 holds QuestObjective 18252 (type 3, done here) and 18604 (type 24, flags 3,
  // data 9695: done when quest 9695 is finished). No Creature2 row receives 9497, so the
  // server completes it once it is Achieved (`communicator.completed_by_server`).
  let state =
    dev_support.in_world_holding_quests(level: 1, quests: [
      quest_support.active(
        quest_id: 9497,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 1,
        progress: [1, 0],
      ),
    ])
  let #(state, taken) = dev_support.said(state:, text: "!quest 9695 done")
  assert quest_states_written(taken:)
    == [
      QuestState(quest_id: 9695, state: 3, objective_id: 0),
      QuestState(quest_id: 9497, state: 2, objective_id: 0),
    ]
    as "0x35c: 9695 Completed, then 9497 Achieved, which its objective 18604 waiting on 9695 makes"
  assert support.decoded(
      support.written(taken:),
      quest_objective_progress.message_id,
      quest_objective_progress.decode,
    )
    == [
      QuestObjectiveProgress(quest_id: 9497, objective_index: 1, progress: 1),
    ]
    as "0x361: the type 24 objective 18604, the second of 9497, is done"
  assert list.last(support.written_ids(taken)) == Ok(0x01C8)
    as "the command's line is written after the follow-ups' frames"
  let assert client_connection.AskStore(store.Items(store.TurnInQuest(
    quests: asked,
    ..,
  ))) = support.ask_request(taken)
    as "the connection asks the store for a turn-in, as it does for a quest the server completes"
  assert asked
    == [
      quest_support.completed(9497, at: now_seconds),
      quest_support.completed(9695, at: now_seconds),
    ]
    as "the turn-in saves the log with 9497 Completed beside the 9695 the command completed"
  let #(state, answered) =
    support.answer(state:, taken:, outcome: support.turn_in_saved(taken:))
  assert quest_states_written(taken: answered)
    == [QuestState(quest_id: 9497, state: 3, objective_id: 0)]
    as "the turn-in's answer tells the client 9497 is Completed"
  assert dev_support.saved_quests(state:)
    == [
      quest_support.completed(9497, at: now_seconds),
      quest_support.completed(9695, at: now_seconds),
    ]
    as "both quests are Completed in the log"
}

pub fn the_next_save_holds_the_completed_quest_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    dev_support.said(
      state: dev_support.in_world_holding_quests(level: 1, quests: []),
      text: "!quest 5972 done",
    )
  let #(_, taken) =
    support.feed(
      state:,
      event: step.OwnEvent(step.TimerFired(connection_state.save_timer)),
    )
  let assert client_connection.AskStore(store.Move(store.SavePlace(quests:, ..))) =
    support.ask_request(taken)
    as "the save timer asks the store to save the place and the quests"
  assert quests == [quest_support.completed(5972, at: now_seconds)]
    as "store.SavePlace carries a Completed row, state 3 with its completion time"
}

pub fn an_accepted_quest_command_is_logged_once_at_info_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = dev_support.in_world_holding_quests(level: 1, quests: [])
  let #(_, taken) = dev_support.said(state:, text: "!quest 5972 done")
  let assert [line] = rule_support.logs_of(step: taken, level: step.LogInfo)
    as "one info line for an accepted command"
  assert string.contains(line.text, "!quest 5972 done")
    as "it names the command and the quest"
  assert rule_support.logs(taken) == [line] as "and no other line"
}

pub fn a_command_for_a_quest_the_server_is_completing_runs_after_its_turn_in_and_finds_it_done_test() -> Nil {
  use <- owned_test.run(60_000)
  // Quests 9497 and 9695 are Achieved and no Creature2 row receives either, so the entry
  // queues the server's completion of both: 9497 is asked of the store first and 9695
  // waits in the queue. The command line for 9695 is held behind the asks.
  let #(state, entry) =
    support.entered_under(
      settings: support.settings_with_dev_commands(),
      character: support.world_character(),
      quests: [
        quest_turn_in_support.achieved(quest_id: 9497),
        quest_turn_in_support.achieved(quest_id: 9695),
      ],
    )
  let #(state, held) = dev_support.said(state:, text: "!quest 9695 done")
  assert support.written_ids(held) == []
    as "the line waits while the store works"
  let #(state, second) =
    support.answer(
      state:,
      taken: entry,
      outcome: support.turn_in_saved(taken: entry),
    )
  let assert client_connection.AskStore(store.Items(store.TurnInQuest(..))) =
    support.ask_request(second)
    as "the answer's input asks for the quest that waited in the queue"
  let #(_, third) =
    support.answer(
      state:,
      taken: second,
      outcome: support.turn_in_saved(taken: second),
    )
  assert quest_states_written(taken: third)
    == [QuestState(quest_id: 9695, state: 3, objective_id: 0)]
    as "the server's completion writes 9695's state 3 once, and the command writes none"
  assert support.system_lines(third) == ["quest 9695 is already done"]
    as "the held command finds the quest finished by the server's completion"
}

// ---- !currency ----
//
// Expected values come from these places.
// - `opcode.0x919` and `opcode.0xdd.with_0x919`: a set writes the 0x919 total, and the 0xdd
//   gain only when the total is higher; the 0x1c8 line is the command's System line.
// - `character_currency` holds one row for each currency the player has: the connection
//   holds what the store's load gave (a missing row reads as 0) and the request names it.
// - The tests' player is account 7, character 42, epoch 1 (`game_connection_support`).

const credits_800 = store.HeldCurrency(currency_type_id: 1, amount: 800)

/// The player holding these currencies after it said the line.
fn granting(
  currencies currencies: List(store.HeldCurrency),
  text text: String,
) -> #(game_connection.State, step.ConnectionStep(Request)) {
  dev_support.said(
    state: dev_support.in_world_holding_currencies(currencies:),
    text:,
  )
}

/// The step after the store answered the ask `taken` ended with.
fn answered(
  state state: game_connection.State,
  taken taken: step.ConnectionStep(Request),
  outcome outcome: Outcome(Answer),
) -> #(game_connection.State, step.ConnectionStep(Request)) {
  support.answer(state:, taken:, outcome:)
}

/// The step after this event, at the monotonic time 1 ms.
fn fed(
  state state: game_connection.State,
  event event: Event(ConnectionEvent(client_connection.Message, Answer)),
) -> #(game_connection.State, step.ConnectionStep(Request)) {
  support.at(state:, ms: 1, event:)
}

pub fn a_currency_command_asks_the_store_and_waits_in_granting_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        [credits_800],
        "!currency 1 5000",
        800,
        5000,
        "a character with credits",
      ),
      #([], "!currency 1 5000", 0, 5000, "no credits row reads as 0 held"),
      #(
        [store.HeldCurrency(currency_type_id: 1, amount: 8000)],
        "!currency 1 100",
        8000,
        100,
        "a lowering is asked too",
      ),
    ],
    fn(row) {
      let #(currencies, text, held, after, why) = row
      let #(_, taken) = granting(currencies:, text:)
      assert support.ask_request(taken)
        == dev_support.currency_asked(currency_type_id: 1, held:, after:)
        as why
      let assert Some(ask) = rule_support.asked(taken)
      assert ask.deadline_ms == rule_support.now_ms + 4000
        as "the settings' ask deadline from the time of the input"
      assert support.written_ids(taken) == [0x01C2]
        as "opcode.0x1c2: the line is answered before the ask, and nothing else is written until the answer"
      assert !rule_support.stops(taken)
    },
  )
}

pub fn a_chat_line_during_the_grant_waits_and_reads_the_new_amount_after_the_answer_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, taken) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let #(state, second) = dev_support.said(state:, text: "!currency 1 100")
  let #(state, third) = dev_support.said(state:, text: "!level 4")
  assert rule_support.asked(second) == None
    && support.written_ids(second) == []
    && rule_support.asked(third) == None
    && support.written_ids(third) == []
    as "the bytes of two lines wait in the connection while the first ask is out: nothing is asked or written"
  let #(state, first_answer) =
    answered(state:, taken:, outcome: dev_support.currency_set(amount: 5000))
  assert support.ask_request(first_answer)
    == dev_support.currency_asked(currency_type_id: 1, held: 5000, after: 100)
    as "the held second line is read after the answer, when the player holds the new 5000"
  let #(_, second_answer) =
    answered(
      state:,
      taken: first_answer,
      outcome: dev_support.currency_set(amount: 100),
    )
  assert list.contains(support.written_ids(second_answer), 0x01AC)
    as "opcode.0x1ac: the held !level 4 is taken after the second answer and raises the level"
  // The held bytes are bounded: past the limit the connection ends.
  let #(state, _) = granting(currencies: [], text: "!currency 1 5000")
  let #(state, kept) =
    support.read(state, <<0:size(rule_support.held_limit * 8)>>)
  assert !rule_support.stops(kept)
    as "bytes up to the limit are kept for after the answer"
  let #(_, over) = support.read(state, <<0>>)
  assert rule_support.stops(over) && rule_support.asked(over) == None
    as "one byte past the limit ends the connection with nothing asked"
}

pub fn a_map_message_and_a_timer_during_the_grant_are_taken_in_order_after_its_answer_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, taken) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let #(state, struck) =
    support.at(
      state:,
      ms: 1,
      event: support.a_beast_strike(support.own_unit_id),
    )
  assert support.written_ids(struck) == [] && rule_support.asked(struck) == None
    as "the strike on the player waits behind the ask"
  let #(state, fired) =
    support.fired_at(state:, timer: connection_state.save_timer, ms: 2)
  assert support.written_ids(fired) == [] && rule_support.asked(fired) == None
    as "the save timer waits behind the ask and does not end the connection"
  let assert Some(ask) = rule_support.asked(taken)
  let #(_, answer) =
    support.at(
      state:,
      ms: 3,
      event: OwnEvent(step.Answered(
        ask: ask.ask,
        outcome: dev_support.currency_set(amount: 5000),
      )),
    )
  let ids = support.written_ids(answer)
  assert list.take(ids, 3) == [0x0919, 0x00DD, 0x01C8]
    as "the command's frames and line come first"
  assert list.last(ids) == Ok(player_health.message_id)
    as "the strike is taken after them, its health the last frame"
  let assert client_connection.AskStore(store.Move(store.SavePlace(health:, ..))) =
    support.ask_request(answer)
    as "the held save timer is taken last and asks to save the place"
  assert health == Some(735)
    as "the place is saved with the health the strike left, so the save came after it"
}

/// A player of another connection, who speaks.
fn another_speaker() -> chat_tell.Speaker {
  chat_tell.Speaker(
    realm_id: 1,
    character_id: 7,
    name: "Zed Other",
    faction_id: 167,
    unit_id: 9,
    map: support.camp_map(),
    incarnation: support.incarnation,
  )
}

fn a_line(
  channel_type channel_type: chat_channel.ChannelType,
) -> chat_tell.Line {
  chat_tell.Line(channel_type:, channel_id: 0, text: [0x48, 0x69], formats: [])
}

/// The chat tells the step sends other connections.
fn chat_tells(
  taken taken: step.ConnectionStep(Request),
) -> List(#(step.Address, chat_tell.Tell)) {
  list.filter_map(rule_support.effects_of(taken), fn(effect) {
    case effect {
      step.OwnEffect(step.Tell(to:, request: client_connection.TellChat(tell:))) ->
        Ok(#(to, tell))
      step.OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

pub fn a_chat_delivery_during_the_grant_is_dropped_and_a_whisper_is_answered_not_heard_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let said =
    chat_tell.Said(
      speaker: another_speaker(),
      line: a_line(channel_type: chat_channel.Say),
    )
  let #(_, said) =
    fed(state:, event: OwnEvent(Woken(client_connection.SentByChat(said))))
  assert support.written_ids(said) == []
    && chat_tells(taken: said) == []
    && !rule_support.stops(said)
    as "a said line is dropped: the player waits on the store, so the client's chat is not written"
  let whisper =
    chat_tell.Whisper(
      whisper: 5,
      speaker: another_speaker(),
      from: ConnectionId(8),
      line: a_line(channel_type: chat_channel.Whisper),
    )
  let #(_, whispered) =
    fed(state:, event: OwnEvent(Woken(client_connection.SentByChat(whisper))))
  assert support.written_ids(whispered) == []
    && chat_tells(taken: whispered)
    == [#(step.Connection(ConnectionId(8)), chat_tell.NotHeard(whisper: 5))]
    as "a whisper is answered NotHeard to its sender"
}

pub fn a_connection_end_during_the_grant_saves_the_place_then_ends_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(
        "the peer closed",
        OwnEvent(step.PeerClosed),
        rule_support.now_ms + 4000,
        None,
      ),
      #(
        "a read failed",
        OwnEvent(step.ReadFailed(step.OtherSocketFailure(reason: "broken"))),
        rule_support.now_ms + 4000,
        None,
      ),
      #(
        "the server stops with less time than the ask's deadline",
        step.Stopping(deadline_ms: 3000),
        3000,
        Some(LostUserServer),
      ),
      #(
        "another login takes the account's session",
        support.taken_over(),
        rule_support.now_ms + 4000,
        Some(AccountDisconnected),
      ),
    ],
    fn(row) {
      let #(why, event, deadline_ms, notice) = row
      let #(state, asking) =
        granting(currencies: [credits_800], text: "!currency 1 5000")
      assert support.ask_request(asking)
        == dev_support.currency_asked(
          currency_type_id: 1,
          held: 800,
          after: 5000,
        )
        as "the connection waits on the store"
      let #(state, ending) = support.feed(state:, event:)
      assert support.ask_request(ending)
        == support.save_asked(1, support.entry_place())
        as { why <> ": the place is saved first, as in the world" }
      let assert Some(ask) = rule_support.asked(ending)
      assert ask.deadline_ms == deadline_ms as why
      let #(_, saved) =
        support.answer(state:, taken: ending, outcome: support.place_saved())
      assert rule_support.stops(saved)
        as { why <> ": then the connection ends" }
      assert option.map(notice, fn(_) {
          support.disconnect(saved, support.keyed())
        })
        == notice
        as why
    },
  )
}

pub fn a_watch_that_ends_or_a_claim_timer_that_fires_during_the_grant_ends_the_connection_as_a_bug_test() -> Nil {
  use <- owned_test.run(60_000)
  let claim_timer = TimerId(1)
  let #(state, taken) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let #(_, watch) = fed(state:, event: WatchEnded(WatchId(2)))
  assert support.ask_request(watch)
    == support.save_asked(1, support.entry_place())
    && list.length(rule_support.logs_of(step: watch, level: step.LogError)) == 1
    as "the map's watch ending is a bug: one error line, and the held player's place is saved first, as for any end"
  let #(state, held) =
    fed(state:, event: OwnEvent(step.TimerFired(claim_timer)))
  assert rule_support.asked(held) == None && !rule_support.stops(held)
    as "a firing in the wait is held, as every timer is"
  let #(_, answer) =
    answered(state:, taken:, outcome: dev_support.currency_set(amount: 5000))
  assert support.ask_request(answer)
    == support.save_asked(1, support.entry_place())
    && list.length(rule_support.logs_of(step: answer, level: step.LogError))
    == 1
    as "taken after the answer, a claim timer the rule did not start is a bug: one error line and the place saved"
}

/// One answer of the store to a `!currency 1 5000` of a player holding 800 credits.
type Answered {
  Answered(
    why: String,
    outcome: Outcome(Answer),
    ids: List(Int),
    lines: List(String),
    warnings: Int,
    errors: Int,
    held_after: Int,
  )
}

pub fn a_currency_answer_updates_the_amounts_and_writes_the_frames_and_one_line_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      Answered(
        why: "CurrencySet: the total and the gain, then the line",
        outcome: dev_support.currency_set(amount: 5000),
        ids: [0x0919, 0x00DD, 0x01C8],
        lines: ["credits 5000"],
        warnings: 0,
        errors: 0,
        held_after: 5000,
      ),
      Answered(
        why: "ItemsNotSaved: the warning and the not-set line, nothing changed",
        outcome: step.Answer(FromStore(store.ForItems(store.ItemsNotSaved))),
        ids: [0x01C8],
        lines: ["!currency 1 was not set"],
        warnings: 1,
        errors: 0,
        held_after: 800,
      ),
      Answered(
        why: "SaveRefused: the error and the not-set line, nothing changed",
        outcome: step.Answer(
          FromStore(
            store.ForItems(store.SaveRefused(
              constraint: "character_currency_type_is_kept",
            )),
          ),
        ),
        ids: [0x01C8],
        lines: ["!currency 1 was not set"],
        warnings: 0,
        errors: 1,
        held_after: 800,
      ),
    ],
    fn(row) {
      let #(state, taken) =
        granting(currencies: [credits_800], text: "!currency 1 5000")
      let #(state, answer) = answered(state:, taken:, outcome: row.outcome)
      assert support.written_ids(answer) == row.ids as row.why
      assert support.system_lines(answer) == row.lines as row.why
      assert list.length(rule_support.logs_of(
          step: answer,
          level: step.LogWarning,
        ))
        == row.warnings
        as row.why
      assert list.length(rule_support.logs_of(
          step: answer,
          level: step.LogError,
        ))
        == row.errors
        as row.why
      assert !rule_support.stops(answer) && rule_support.asked(answer) == None
        as "the connection goes on in the world"
      let #(_, next) = dev_support.said(state:, text: "!currency 1 1")
      assert support.ask_request(next)
        == dev_support.currency_asked(
          currency_type_id: 1,
          held: row.held_after,
          after: 1,
        )
        as { row.why <> ": the next ask holds the total the answer left" }
    },
  )
}

pub fn a_store_that_gives_no_answer_to_a_currency_ask_ends_the_connection_with_reason_8_and_saves_the_place_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      #(step.Answer(FromStore(store.Unavailable)), 1),
      #(step.NotRunning, 1),
      #(step.NoAnswerInTime, 1),
      #(step.EndedBeforeAnswer, 1),
      #(StoppedWaiting, 0),
    ],
    fn(row) {
      let #(outcome, errors) = row
      let #(state, taken) =
        granting(currencies: [credits_800], text: "!currency 1 5000")
      let #(state, answer) = answered(state:, taken:, outcome:)
      assert support.ask_request(answer)
        == support.save_asked(1, support.entry_place())
        as "one SavePlace ask, as in the world"
      let assert Some(ask) = rule_support.asked(answer)
      assert ask.deadline_ms == rule_support.now_ms + 4000
        as "the settings' ask deadline, not a stop's"
      assert list.length(rule_support.logs_of(
          step: answer,
          level: step.LogError,
        ))
        == errors
        as "an error line for a store that failed, none for a stop"
      assert support.written_ids(answer) == []
        as "no frame and no line: nothing says whether the total was set"
      let #(_, saved) =
        support.answer(state:, taken: answer, outcome: support.place_saved())
      assert support.disconnect(saved, support.keyed()) == LostUserServer
        as "the place saved, 0x036A reason 8"
    },
  )
}

pub fn each_currency_use_is_logged_once_at_info_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, taken) =
    granting(currencies: [credits_800], text: "!currency 1 5000")
  let assert [line] = rule_support.logs_of(step: taken, level: step.LogInfo)
    as "one info line for an accepted command, before its ask"
  assert string.contains(line.text, "!currency 1 5000")
    && string.contains(line.text, "800")
    as "it names the command and the total held"
  let #(_, answer) =
    answered(state:, taken:, outcome: dev_support.currency_set(amount: 5000))
  assert rule_support.logs(answer) == []
    as "the answer logs nothing more for a set that was saved"
  let #(_, refused) =
    granting(currencies: [credits_800], text: "!currency 99 1")
  assert rule_support.logs(refused) == []
    as "a refused command is its System line, with no log"
}
