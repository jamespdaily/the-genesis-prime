//// What a connection's timer for the earliest of several deadlines is told when that
//// deadline moves (`genesis_prime/game/deadline_timer`), which the quest log's timer and the
//// held items' timer share. The rule is the server's own: the timer follows the earliest
//// deadline, and a moved deadline cancels the running timer before it starts it again, since
//// the shell ends a connection that starts a timer that runs.

import genesis_prime/game/deadline_timer.{
  CancelDeadlineTimer, StartDeadlineTimer,
}
import gleam/list
import gleam/option.{None, Some}
import owned_test

pub fn the_timer_follows_the_earliest_deadline_test() -> Nil {
  use <- owned_test.run(10_000)
  // #(deadline before, deadline after, now, the timer's moves, why)
  let cases = [
    #(None, None, 1000, [], "no deadline before or after: nothing"),
    #(
      None,
      Some(61_000),
      1000,
      [StartDeadlineTimer(after_ms: 60_000)],
      "a first deadline starts the timer for the time to it",
    ),
    #(
      Some(61_000),
      None,
      1000,
      [CancelDeadlineTimer],
      "no deadline left cancels the running timer",
    ),
    #(Some(61_000), Some(61_000), 1000, [], "the same deadline moves nothing"),
    #(
      Some(31_000),
      Some(121_000),
      10_000,
      [CancelDeadlineTimer, StartDeadlineTimer(after_ms: 111_000)],
      "a moved deadline cancels the running timer, then starts it for the new one",
    ),
    #(
      None,
      Some(500),
      1000,
      [StartDeadlineTimer(after_ms: 0)],
      "a deadline already past starts the timer in 0 ms, never a negative time",
    ),
  ]
  list.each(cases, fn(row) {
    let #(before, after, now_ms, expected, why) = row
    assert deadline_timer.moved(before:, after:, now_ms:) == expected as why
  })
}
