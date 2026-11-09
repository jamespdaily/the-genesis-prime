//// The game connection's quest reset timer (`genesis_prime/game/connection`,
//// `genesis_prime/game/quest_log`): the periodic reset, 0x0362, the server sends
//// when a daily or weekly reset passes while the player is in the world.
//// Expected values come from these places.
//// - `opcode.0x362`, 0x140611e30 and 0x140489aa0: the message is the reset time and
////   the periods that reset, a bit for each (1 daily, 2 weekly, 4 monthly, 8
////   yearly, the client's `Quest2.questRepeatPeriodEnum` 1 to 4); the client does
////   nothing for a time equal to the one it holds, and re-rolls its offers for a
////   new one, so one message goes out for each reset that passed, not one for each
////   period.
//// - The reset instants are the server's choice (Jim, 2026-11-08): daily at 10:00
////   UTC, weekly on Tuesday at 10:00 UTC, monthly and yearly at the first daily
////   reset of the month and year. They are calendar dates, in Unix seconds with
////   their FILETIME (100 ns since 1601: Unix seconds times 10,000,000 plus
////   116,444,736,000,000,000): the tests' connection enters at Thursday 2025-04-24
////   20:26:40 UTC (`world_entry_support.filetime`), when the latest reset is the
////   daily one at 10:00 that day, so the next one is Friday 2025-04-25 10:00, which is
////   48,800,000 ms (13 h 33 min 20 s) later.
//// - 2025-04-29 and 2025-04-30 are not the first of a month or of a year, so the
////   monthly and yearly bits stay clear.

import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{type Answer, type Message, type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/quest_periodic_reset.{
  type QuestPeriodicReset, QuestPeriodicReset,
}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, OwnEffect, OwnEvent, StartTimer,
  TimerFired, TimerId, Unwatch, Watch,
}
import gleam/list
import gleam/option.{None}
import owned_test

/// A FILETIME of 2025-04-25 09:00:00 UTC, an hour before the daily reset.
const friday_9 = 133_900_452_000_000_000

/// A FILETIME of 2025-04-28 10:00:00 UTC, a Monday: a daily reset.
const monday_10 = 133_903_080_000_000_000

/// A FILETIME of 2025-04-29 10:00:00 UTC, a Tuesday: a daily and the weekly reset.
const tuesday_10 = 133_903_944_000_000_000

/// A FILETIME of 2025-04-30 11:00:00 UTC, the Wednesday an hour after a daily reset.
const wednesday_11 = 133_904_844_000_000_000

/// The reset timer's id.
const timer = TimerId(10)

fn fired(
  state state: game_connection.State,
  at filetime: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  let event: step.Event(ConnectionEvent(Message, Answer)) =
    OwnEvent(TimerFired(timer))
  game_connection.step(state, support.input_at(filetime:, event:))
}

/// The timers the step starts with their waits, in order.
fn started(taken taken: ConnectionStep(Request)) -> List(#(step.TimerId, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer:, after_ms:)) -> Ok(#(timer, after_ms))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The 0x362 messages the step writes, decoded.
fn resets_sent(
  taken taken: ConnectionStep(Request),
) -> List(QuestPeriodicReset) {
  game_connection_support.written(taken:)
  |> list.filter(fn(frame: Frame) {
    frame.message_id == quest_periodic_reset.message_id
  })
  |> list.map(fn(frame: Frame) {
    let assert Ok(message) = quest_periodic_reset.decode(frame.body)
      as "0x362 decodes"
    message
  })
}

pub fn a_reset_passing_during_play_sends_the_periodic_reset_once_with_every_period_that_reset_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(entered, entry) =
    game_connection_support.entered_with_quests(quests: [])
  assert list.contains(started(taken: entry), #(timer, 48_800_000))
    as "the play entry starts the reset timer for the next reset, Friday 2025-04-25 10:00 UTC, 48,800,000 ms after the entry"
  // The timer fires an hour early: nothing has reset, so nothing is sent and the
  // timer is started again for the hour left.
  let #(state, taken) = fired(state: entered, at: friday_9)
  assert resets_sent(taken:) == []
    as "0x140611e30: a reset time the client holds does nothing, so none is sent for no reset"
  assert started(taken:) == [#(timer, 3_600_000)]
    as "the timer starts again for the hour left to the next reset"
  assert support.writes(taken) == []
    && support.asked(taken) == None
    && !support.stops(taken)
    as "an early firing sends and asks for nothing"
  // Four daily resets passed unseen: one message with the latest time and the daily
  // bit, not four.
  let #(state, taken) = fired(state:, at: monday_10)
  assert resets_sent(taken:)
    == [QuestPeriodicReset(reset_time: 1_745_834_400, periods: 1)]
    as "0x140489aa0: the daily quests reset, and the time is the latest reset, Monday 2025-04-28 10:00 UTC"
  assert started(taken:) == [#(timer, 86_400_000)]
    as "the next reset is the next day's"
  // The weekly reset is at the daily one's time on Tuesday: one message, both bits.
  let #(state, taken) = fired(state:, at: tuesday_10)
  assert resets_sent(taken:)
    == [QuestPeriodicReset(reset_time: 1_745_920_800, periods: 3)]
    as "Tuesday 2025-04-29 10:00 UTC is the weekly reset and a daily one: bits 1 and 2 in one message, with the new time"
  assert started(taken:) == [#(timer, 86_400_000)]
    as "and the timer is set for the next day's reset"
  // A second firing at the same time has nothing new to tell.
  let #(_, taken) = fired(state:, at: tuesday_10)
  assert resets_sent(taken:) == []
    as "the client was told the time already: the reset is sent once"
  assert started(taken:) == [#(timer, 86_400_000)]
  // Resets of a daily and of the weekly passed while the timer was late: one
  // message with the latest time and both bits.
  let #(_, taken) = fired(state: entered, at: wednesday_11)
  assert resets_sent(taken:)
    == [QuestPeriodicReset(reset_time: 1_746_007_200, periods: 3)]
    as "after missed resets one message goes out with the latest reset, Wednesday 2025-04-30 10:00 UTC, and the bit of each period that reset since the time the client was told"
  assert started(taken:) == [#(timer, 82_800_000)]
    as "the next reset is 23 hours after the late firing"
}
