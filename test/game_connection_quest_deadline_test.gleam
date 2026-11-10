//// The game connection's quest deadline timer (`genesis_prime/game/connection`,
//// `genesis_prime/game/quest_log`): a timed quest the player holds is botched when its
//// time runs out, and the time left is saved. Expected values come from these places.
//// - `Quest2.maxTimeAllowedMS` (milliseconds; the client's table has 14 timed quests
////   and the fixture none, so the tests give quests 1872 and 1806 a limit of 60,000 and
////   120,000 ms): a quest with a limit is timed. The client shows the countdown and
////   sends nothing at zero (`opcode.0x35c`: the state of a quest changes only by this
////   message), so the server sends the Botched state, 4.
//// - `opcode.0x35c`: 15 bits of quest id, 32 of state, 32 of objective id, 79 bits in 10
////   bytes. For quest 1872 (0x750) in state 4 the bits are 0x50, 0x07 and, state 4 being
////   bit 2 of the 32, bit 17 of the body, 0x02; quest 1806 (0x70E) starts with 0x0E.
//// - `opcode.0x35f`, `0x1406118a0`: a `quest_ms_left` of 0 shows a full timer, so a
////   running quest is saved with at least 1 ms left, and a saved 0 means a full timer.
//// - The tests' connection is at 1000 ms when it enters (`connection_rule_support`'s
////   `now_ms`); the other times are the tests' choice. Every deadline is the time of the
////   entry or accept plus the milliseconds left, so 1872 with a full timer entered at
////   1000 ms is due at 61,000 ms, and 1806 with 90,000 ms left at 91,000 ms.

import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{type Request, AskStore}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state as connection_state
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/quest_abandon.{QuestAbandon}
import genesis_prime/message/quest_accept.{QuestAccept}
import genesis_prime/message/quest_log as quest_message
import genesis_prime/step.{
  type ConnectionStep, CancelTimer, OwnEffect, OwnEvent, StartTimer, TimerFired,
  TimerId,
}
import genesis_prime/store.{Move, QuestRow, SavePlace}
import gleam/list
import gleam/option.{None}
import owned_test
import quest_support

const deadline_timer = TimerId(11)

const limits = [#(1872, 60_000), #(1806, 120_000)]

/// 0x35C {quest 1872, state 4, objective 0} and the same for 1806.
const botched_1872 = <<0x50, 0x07, 0x02, 0, 0, 0, 0, 0, 0, 0>>

const botched_1806 = <<0x0e, 0x07, 0x02, 0, 0, 0, 0, 0, 0, 0>>

fn fire(
  state state: game_connection.State,
  timer timer: step.TimerId,
  at ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(
    state,
    support.input_at_ms(ms:, event: OwnEvent(TimerFired(timer))),
  )
}

fn read(
  state state: game_connection.State,
  message_id message_id: Int,
  body body: BitArray,
  at ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(
    state,
    support.input_at_ms(
      ms:,
      event: OwnEvent(
        step.Read(game_connection_support.world_message(message_id:, body:)),
      ),
    ),
  )
}

/// The player's accept of quest 1872 from the communicator, a dialog accept: location
/// 300 and bag index -1 (`opcode.0x35b`).
fn accepts_1872(
  state state: game_connection.State,
  at ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Ok(body) =
    quest_accept.encode(QuestAccept(
      item: ItemPlace(location: 300, bag_index: 4_294_967_295),
      quest_id: 1872,
    ))
    as "the dialog's accept fits the message"
  read(state:, message_id: quest_accept.message_id, body:, at: ms)
}

fn abandons(
  state state: game_connection.State,
  quest_id quest_id: Int,
  at ms: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let assert Ok(body) = quest_abandon.encode(QuestAbandon(quest_id:))
    as "a quest id fits the message"
  read(state:, message_id: quest_abandon.message_id, body:, at: ms)
}

/// The timer effects of the step, in order.
fn timer_effects(
  taken taken: ConnectionStep(Request),
) -> List(step.Effect(step.ConnectionEffect(Request))) {
  list.filter(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer:, ..)) | OwnEffect(CancelTimer(timer:)) ->
        timer == deadline_timer
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> False
    }
  })
}

/// The 0x35C bodies the step writes, in order.
fn quest_states(taken taken: ConnectionStep(Request)) -> List(BitArray) {
  game_connection_support.written(taken:)
  |> list.filter(fn(frame) { frame.message_id == 0x035C })
  |> list.map(fn(frame) { frame.body })
}

/// The quest rows of the save the step asks for.
fn saved_quests(taken taken: ConnectionStep(Request)) -> List(store.QuestRow) {
  let assert AskStore(Move(SavePlace(quests:, ..))) =
    game_connection_support.ask_request(taken)
    as "the step asks the store to save the place and the quests"
  quests
}

/// The quest of the 0x35F in the step's frames, with its milliseconds left.
fn quest_ms_left_sent(
  taken taken: ConnectionStep(Request),
) -> List(#(Int, Int)) {
  let assert [frame] =
    game_connection_support.written(taken:)
    |> list.filter(fn(frame) { frame.message_id == quest_message.message_id })
    as "one 0x35F"
  let assert Ok(message) = quest_message.decode(frame.body) as "0x35F decodes"
  list.map(message.active, fn(active) {
    #(active.quest_id, active.quest_ms_left)
  })
}

pub fn a_timed_quest_is_botched_at_its_deadline_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_time_limits(limits:)
  let #(entered, entry) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.timed(1872, progress: [], quest_ms_left: 0),
      quest_support.timed(1806, progress: [0], quest_ms_left: 90_000),
    ])
  assert timer_effects(taken: entry)
    == [OwnEffect(StartTimer(deadline_timer, 60_000))]
    as "the entry starts the timer for the earliest deadline: 1872's full 60,000 ms, due at 61,000 ms"
  // Early: the timer fires 21,000 ms before the deadline, so nothing is botched and
  // the timer is started again for what is left.
  let #(early, taken) = fire(state: entered, timer: deadline_timer, at: 40_000)
  assert quest_states(taken:) == []
    as "a quest before its deadline is not botched"
  assert timer_effects(taken:)
    == [OwnEffect(StartTimer(deadline_timer, 21_000))]
    as "an early firing starts the timer again for the 21,000 ms left"
  assert support.asked(taken) == None as "an early firing saves nothing"
  // On time: 1872 is botched, and the timer moves to 1806, due at 91,000 ms.
  let #(_, taken) = fire(state: early, timer: deadline_timer, at: 61_000)
  assert quest_states(taken:) == [botched_1872]
    as "0x35C tells the client 1872 is Botched, and only 1872"
  assert timer_effects(taken:)
    == [OwnEffect(StartTimer(deadline_timer, 30_000))]
    as "the timer starts again for 1806, 91,000 ms - 61,000 ms"
  assert saved_quests(taken:)
    == [
      QuestRow(
        quest_id: 1806,
        state: 1,
        completed_at: None,
        active: store_active_1806(ms_left: 30_000),
      ),
      QuestRow(quest_id: 1872, state: 4, completed_at: None, active: None),
    ]
    as "the botch is saved at once: 1872 held Botched with no active entry, 1806 with 30,000 ms left"
  // Late: both are past their deadlines when the timer fires, so one step botches both
  // in quest id order and leaves no timer.
  let #(_, taken) = fire(state: entered, timer: deadline_timer, at: 200_000)
  assert quest_states(taken:) == [botched_1806, botched_1872]
    as "every entry past its deadline is botched in one step, one 0x35C each"
  assert timer_effects(taken:) == []
    as "no timed quest is left, so no timer starts"
}

fn store_active_1806(ms_left ms_left: Int) -> option.Option(store.ActiveQuest) {
  let QuestRow(active:, ..) =
    quest_support.timed(1806, progress: [0], quest_ms_left: ms_left)
  active
}

pub fn the_deadline_timer_follows_the_earliest_timed_quest_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_time_limits(limits:)
  // Accepting the quest with the earlier deadline cancels the timer and starts it for
  // that one: 1872 accepted at 10,000 ms is due at 70,000 ms, before 1806 at 121,000 ms.
  let #(entered, entry) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.known(1872, 5),
      quest_support.timed(1806, progress: [0], quest_ms_left: 0),
    ])
  assert timer_effects(taken: entry)
    == [OwnEffect(StartTimer(deadline_timer, 120_000))]
    as "the entry starts the timer for 1806's full 120,000 ms"
  let #(accepted, taken) = accepts_1872(state: entered, at: 10_000)
  assert timer_effects(taken:)
    == [
      OwnEffect(CancelTimer(deadline_timer)),
      OwnEffect(StartTimer(deadline_timer, 60_000)),
    ]
    as "a running timer is cancelled before it starts again, so the id is never started twice"
  // The timer fires for 1872: it is botched and the timer goes on to 1806.
  let #(saving, taken) =
    fire(state: accepted, timer: deadline_timer, at: 70_000)
  assert quest_states(taken:) == [botched_1872] as "the botch of the earliest"
  assert timer_effects(taken:)
    == [OwnEffect(StartTimer(deadline_timer, 51_000))]
    as "the timer that fired is not running, so it starts without a cancel, for 121,000 ms - 70,000 ms"
  // The player goes on playing once the store answers the save of the botch.
  let #(botched, _) =
    game_connection_support.answer(
      state: saving,
      taken:,
      outcome: game_connection_support.place_saved(),
    )
  // Abandoning the last timed quest cancels the timer.
  let #(_, taken) = abandons(state: botched, quest_id: 1806, at: 80_000)
  assert timer_effects(taken:) == [OwnEffect(CancelTimer(deadline_timer))]
    as "no timed quest is left, so the timer is cancelled and not started"
  // With no timer running, an accept starts one and cancels nothing.
  let #(entered_alone, entry) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.known(1872, 5),
    ])
  assert timer_effects(taken: entry) == []
    as "no timed quest, so the entry starts no deadline timer"
  let #(_, taken) = accepts_1872(state: entered_alone, at: 10_000)
  assert timer_effects(taken:)
    == [OwnEffect(StartTimer(deadline_timer, 60_000))]
    as "the first timed quest starts the timer, with nothing to cancel"
  // Abandoning a quest that is not the earliest leaves the timer alone, and abandoning
  // the earliest moves it to the next.
  let #(both, _) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.timed(1872, progress: [], quest_ms_left: 0),
      quest_support.timed(1806, progress: [0], quest_ms_left: 0),
    ])
  let #(_, taken) = abandons(state: both, quest_id: 1806, at: 5000)
  assert timer_effects(taken:) == []
    as "1806's deadline is not the earliest, so the timer keeps its time"
  let #(_, taken) = abandons(state: both, quest_id: 1872, at: 5000)
  assert timer_effects(taken:)
    == [
      OwnEffect(CancelTimer(deadline_timer)),
      OwnEffect(StartTimer(deadline_timer, 116_000)),
    ]
    as "the timer moves to 1806: 121,000 ms - 5000 ms"
}

pub fn a_timed_quest_saves_its_time_left_and_never_zero_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_time_limits(limits:)
  let #(entered, _) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.timed(1872, progress: [], quest_ms_left: 0),
    ])
  // 20,000 ms of the 60,000 have passed at 21,000 ms.
  let #(_, taken) =
    fire(state: entered, timer: connection_state.save_timer, at: 21_000)
  assert saved_quests(taken:)
    == [quest_support.timed(1872, progress: [], quest_ms_left: 40_000)]
    as "the periodic save writes the time left, 61,000 ms - 21,000 ms"
  // The save timer fires at the deadline before the deadline timer does: 0 would show
  // a full timer on the next login (0x1406118a0), so 1 ms is saved.
  let #(_, taken) =
    fire(state: entered, timer: connection_state.save_timer, at: 61_000)
  assert saved_quests(taken:)
    == [quest_support.timed(1872, progress: [], quest_ms_left: 1)]
    as "opcode.0x35f: 0 means a full timer, so a quest at its deadline is saved with 1 ms left"
}

pub fn a_timed_quest_resumes_from_its_saved_time_left_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_time_limits(limits:)
  // 30,000 ms saved: the timer runs for them, and the client is sent them.
  let #(_, entry) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.timed(1872, progress: [], quest_ms_left: 30_000),
    ])
  assert timer_effects(taken: entry)
    == [OwnEffect(StartTimer(deadline_timer, 30_000))]
    as "the entry starts the timer for the 30,000 ms saved"
  assert quest_ms_left_sent(taken: entry) == [#(1872, 30_000)]
    as "0x35F carries the time left"
  // A saved 0 is a full timer (`0x1406118a0`).
  let #(_, entry) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.timed(1872, progress: [], quest_ms_left: 0),
    ])
  assert timer_effects(taken: entry)
    == [OwnEffect(StartTimer(deadline_timer, 60_000))]
    as "a saved 0 shows the client a full timer, so the server's runs for the full 60,000 ms"
  assert quest_ms_left_sent(taken: entry) == [#(1872, 0)]
    as "0x35F carries the 0 the client reads as a full timer"
  // A quest with no limit in its Quest2 row has no timer.
  let #(_, entry) =
    game_connection_support.entered_with_quests_on(tables:, quests: [
      quest_support.timed(2417, progress: [], quest_ms_left: 0),
    ])
  assert timer_effects(taken: entry) == []
    as "Quest2 2417 has no maxTimeAllowedMS, so no timer runs"
}
