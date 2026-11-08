//// Runs a test body in a process the test owns, so a hung test fails and
//// what a test started stops with it. Every test body runs inside `run`.

import gleam/erlang/process
import gleam/int
import owned_key
import unitest

pub type Outcome(a) {
  Returned(a)
  Skipped
  Crashed
}

/// Runs a test body in its own process, with a deadline. When the body
/// returns, crashes or runs past the deadline, that process is killed, so
/// every process linked to it stops too. A body that skips through
/// `unitest.guard` is skipped in the caller, so the runner reports a skip.
///
/// A body that returns with persistent terms still stored under the keys it made
/// (`owned_key`) fails, and the terms are erased so the tests after it do not
/// pay for them. A body that crashes or runs past its deadline fails for that,
/// and its terms are erased too.
pub fn run(timeout_ms: Int, body: fn() -> a) -> a {
  run_counting_waits(timeout_ms, owned_key.waited_ms, body)
}

/// `run`, with `waited_ms` the way the deadline learns how long the body's
/// process has waited for room among the loads: `run` gives the real count
/// (`owned_key.waited_ms`), and a test of the deadline's extension gives its own,
/// so the deadline's rule is checked with no wait and no clock.
pub fn run_counting_waits(
  timeout_ms: Int,
  waited_ms: fn(process.Pid) -> Int,
  body: fn() -> a,
) -> a {
  let reply = process.new_subject()
  let worker =
    process.spawn_unlinked(fn() {
      process.send(reply, case run_unless_skipped(body) {
        Ok(value) -> Returned(value)
        Error(Nil) -> Skipped
      })
      process.sleep_forever()
    })
  let monitor = process.monitor(worker)
  let outcome =
    process.new_selector()
    |> process.select(reply)
    |> process.select_specific_monitor(monitor, fn(_down) { Crashed })
    |> receive_within(timeout_ms:, waited_ms:, worker:, extended_ms: 0)
  // The body is ended first, so it puts nothing more, and then its terms are
  // counted and erased, whatever ended it: its return, a crash or the deadline.
  process.kill(worker)
  wait_until_dead(worker)
  let left_behind = owned_key.left_behind(worker)
  owned_key.erase_left(worker)
  case outcome {
    Ok(Returned(value)) ->
      case left_behind {
        0 -> value
        count ->
          panic as {
            "the test left "
            <> int.to_string(count)
            <> " persistent terms behind under the keys it made, which stay in the literal area for the rest of the run: erase them"
          }
      }
    Ok(Skipped) ->
      unitest.guard(False, fn() { panic as "a skipped body does not run" })
    Ok(Crashed) -> panic as "the test body crashed"
    Error(Nil) -> panic as "the test ran past its deadline"
  }
}

/// Waits for the body's outcome for `timeout_ms` of its own time: the time it
/// spent waiting for room among the loads (`waited_ms`) is added to the
/// deadline, so a test is not failed for the gate's wait. `extended_ms` is what
/// has been added so far.
fn receive_within(
  selector selector: process.Selector(Outcome(a)),
  timeout_ms timeout_ms: Int,
  waited_ms waited_ms: fn(process.Pid) -> Int,
  worker worker: process.Pid,
  extended_ms extended_ms: Int,
) -> Result(Outcome(a), Nil) {
  case process.selector_receive(selector, within: timeout_ms) {
    Ok(outcome) -> Ok(outcome)
    Error(Nil) ->
      case waited_ms(worker) - extended_ms {
        more if more > 0 ->
          receive_within(
            selector:,
            timeout_ms: more,
            waited_ms:,
            worker:,
            extended_ms: extended_ms + more,
          )
        _ -> Error(Nil)
      }
  }
}

/// Runs the body, returning Error when it throws unitest's skip
/// (`{gleam_unitest, skip}`, unitest_ffi:skip/0).
@external(erlang, "owned_test_ffi", "run_unless_skipped")
fn run_unless_skipped(body: fn() -> a) -> Result(a, Nil)

/// Returns when the process has ended, at once if it already has.
@external(erlang, "owned_key_ffi", "wait_until_dead")
fn wait_until_dead(pid: process.Pid) -> Nil
