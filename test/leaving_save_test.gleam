//// The ladder a leaving player's save is tried on when the store gives no
//// answer (`genesis_prime/game/leaving_save`). Expected values come from these
//// places.
//// - The server's choice for the waits and the window, in `genesis_prime`'s
////   settings: 1, 2, 4 and 8 s, then 10 s, inside 20 s for a logout.
//// - The rule: a retry is made only when its wait ends before the deadline; a
////   stop's deadline, the listener's shutdown bound, replaces a logout's; the
////   first stop reconciles the running retry with its deadline.
//// - The worked table of the design: the attempts of a logout whose every
////   try fails at once are at 0, 1, 3, 7 and 15 s, and the next wait ends at 25 s.

import genesis_prime/game/leaving_save.{
  type Deadline, type Next, type Reconciled, ForLogout, ForStop, GiveUp, Keep,
  RetryAfter, RetryNow,
}
import gleam/list
import leaving_support
import owned_test
import qcheck

fn production() -> leaving_save.Retries {
  leaving_support.retries()
}

pub fn the_production_ladder_waits_1_2_4_8_then_10_seconds_for_every_later_failure_test() -> Nil {
  use <- owned_test.run(5000)
  // #(failures before, wait)
  let rows = [
    #(0, 1000),
    #(1, 2000),
    #(2, 4000),
    #(3, 8000),
    #(4, 10_000),
    #(9, 10_000),
  ]
  list.each(rows, fn(row) {
    assert leaving_save.wait_ms(retries: production(), failed: row.0) == row.1
      as "the ladder's entry, then the last wait for every later failure"
  })
}

pub fn a_failure_is_retried_only_when_its_wait_ends_before_the_deadline_test() -> Nil {
  use <- owned_test.run(5000)
  // #(failed, deadline, now, next, why)
  let rows: List(#(Int, Deadline, Int, Next, String)) = [
    #(0, ForLogout(20_000), 0, RetryAfter(1000), "the first wait fits"),
    #(4, ForLogout(20_000), 15_000, GiveUp, "25000 is at or past 20000"),
    #(4, ForStop(23_000), 15_000, GiveUp, "25000 is at or past 23000"),
    #(2, ForStop(23_000), 18_000, RetryAfter(4000), "22000 is before 23000"),
    #(
      1,
      ForLogout(3000),
      1000,
      GiveUp,
      "a wait that ends at the deadline is not made",
    ),
  ]
  list.each(rows, fn(row) {
    assert leaving_save.after_failure(
        retries: production(),
        failed: row.0,
        deadline: row.1,
        now_ms: row.2,
      )
      == row.3
      as row.4
  })
}

pub fn every_failure_of_a_logout_is_retried_while_its_wait_ends_inside_the_window_whatever_the_start_test() -> Nil {
  use <- owned_test.run(5000)
  // Failures at once: the attempts are at 0, 1, 3, 7 and 15 s; the next wait ends at 25 s.
  let attempts_at = [0, 1000, 3000, 7000, 15_000]
  let deadline = leaving_save.logout_deadline(retries: production(), now_ms: 0)
  assert deadline == ForLogout(20_000) as "within_ms after the end began"
  let expected = [
    RetryAfter(1000),
    RetryAfter(2000),
    RetryAfter(4000),
    RetryAfter(8000),
    GiveUp,
  ]
  list.zip(attempts_at, expected)
  |> list.index_map(fn(attempt, failed) {
    assert leaving_save.after_failure(
        retries: production(),
        failed:,
        deadline:,
        now_ms: attempt.0,
      )
      == attempt.1
      as "the ladder's waits, and the fifth failure gives up: 15 s + 10 s ends at 25 s, past 20 s"
  })
  Nil
}

pub fn a_retry_always_ends_before_the_deadline_and_an_ask_never_outlasts_it_test() -> Nil {
  use <- owned_test.run(20_000)
  use #(failed, #(deadline_ms, now_ms)) <- qcheck.given(qcheck.tuple2(
    qcheck.bounded_int(from: 0, to: 20),
    qcheck.tuple2(
      qcheck.bounded_int(from: 0, to: 100_000),
      qcheck.bounded_int(from: 0, to: 100_000),
    ),
  ))
  list.each([ForLogout(deadline_ms), ForStop(deadline_ms)], fn(deadline) {
    case
      leaving_save.after_failure(
        retries: production(),
        failed:,
        deadline:,
        now_ms:,
      )
    {
      RetryAfter(wait_ms:) -> {
        assert now_ms + wait_ms < deadline_ms
          as "a retry's wait ends before the deadline"
      }
      GiveUp -> {
        assert now_ms + 10_000 >= deadline_ms
          as "a failure gives up only when its wait, at most the ladder's 10 s, would end at or past the deadline"
      }
    }
    let within_ms =
      leaving_save.ask_within_ms(deadline:, now_ms:, ask_deadline_ms: 5000)
    assert within_ms <= 5000 as "an ask is never longer than the ask deadline"
    assert within_ms <= deadline_ms - now_ms
      as "an ask never outlasts what the deadline leaves"
  })
}

pub fn an_asks_time_is_the_shorter_of_the_ask_deadline_and_what_the_deadline_leaves_test() -> Nil {
  use <- owned_test.run(5000)
  // #(deadline, now, ask within)
  let rows = [
    #(ForLogout(20_000), 0, 5000),
    #(ForStop(23_000), 22_000, 1000),
    #(ForStop(23_000), 23_000, 0),
    #(ForStop(23_000), 24_000, -1000),
  ]
  list.each(rows, fn(row) {
    assert leaving_save.ask_within_ms(
        deadline: row.0,
        now_ms: row.1,
        ask_deadline_ms: 5000,
      )
      == row.2
      as "min(ask deadline, what the deadline leaves); zero or less is no time"
  })
}

pub fn the_first_stop_reconciles_the_running_retry_with_its_deadline_test() -> Nil {
  use <- owned_test.run(5000)
  // #(retry_at, now, deadline, result, why)
  let rows: List(#(Int, Int, Deadline, Reconciled, String)) = [
    #(
      15_000,
      8000,
      ForStop(28_000),
      Keep,
      "the timer fires before the deadline",
    ),
    #(
      15_000,
      8000,
      ForStop(15_000),
      RetryNow,
      "a retry at the deadline has no time",
    ),
    #(15_000, 8000, ForStop(10_000), RetryNow, "a retry after the deadline"),
    #(
      15_000,
      8000,
      ForStop(8000),
      leaving_save.Expired,
      "a deadline at or before now",
    ),
  ]
  list.each(rows, fn(row) {
    assert leaving_save.reconciled(
        retry_at_ms: row.0,
        now_ms: row.1,
        deadline: row.2,
      )
      == row.3
      as row.4
  })
}

pub fn the_first_stop_replaces_a_logouts_deadline_and_a_second_stop_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  assert leaving_save.stopped(deadline: ForLogout(20_000), stop_ms: 31_000)
    == ForStop(31_000)
    as "the stop's deadline replaces a logout's"
  assert leaving_save.stopped(deadline: ForLogout(20_000), stop_ms: 10_000)
    == ForStop(10_000)
    as "also when the stop's is earlier: the stop's is Ranch's bound"
  assert leaving_save.stopped(deadline: ForStop(31_000), stop_ms: 40_000)
    == ForStop(31_000)
    as "a second stop changes nothing"
  assert leaving_save.at_ms(deadline: ForLogout(20_000)) == 20_000
  assert leaving_save.at_ms(deadline: ForStop(31_000)) == 31_000
}
