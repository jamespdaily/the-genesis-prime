//// Runs a test body in a process the test owns, so a hung test fails and
//// what a test started stops with it. Every test body runs inside `run`.

import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/io
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
/// A body that returns after more than half its deadline prints one
/// `check WARNING` line with the test's name, the milliseconds it used and its
/// deadline, which `./check`'s summary repeats. It warns and never fails: a
/// loaded machine runs the same work slower, so the warning shows a test that
/// is near its deadline before the deadline ends it.
///
/// A body that returns with persistent terms still stored under the keys it made
/// (`owned_key`) fails, and the terms are erased so the tests after it do not
/// pay for them. A body that crashes or runs past its deadline fails for that,
/// and its terms are erased too.
pub fn run(timeout_ms: Int, body: fn() -> a) -> a {
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
  let started = monotonic_milliseconds()
  let outcome =
    process.new_selector()
    |> process.select(reply)
    |> process.select_specific_monitor(monitor, fn(_down) { Crashed })
    |> process.selector_receive(within: timeout_ms)
  let used = monotonic_milliseconds() - started
  // The body is ended first, so it puts nothing more, and then its terms are
  // counted and erased, whatever ended it: its return, a crash or the deadline.
  process.kill(worker)
  wait_until_dead(worker)
  let left_behind = owned_key.left_behind(worker)
  owned_key.erase_left(worker)
  case outcome {
    Ok(Returned(value)) ->
      case left_behind {
        0 -> {
          warn_when_near_deadline(body:, used:, timeout_ms:)
          value
        }
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

fn warn_when_near_deadline(
  body body: fn() -> a,
  used used: Int,
  timeout_ms timeout_ms: Int,
) -> Nil {
  use <- bool.guard(used * 2 <= timeout_ms, Nil)
  io.println_error(
    "check WARNING: test "
    <> body_name(body)
    <> " used "
    <> int.to_string(used)
    <> " ms of its "
    <> int.to_string(timeout_ms)
    <> " ms deadline",
  )
}

/// Runs the body, returning Error when it throws unitest's skip
/// (`{gleam_unitest, skip}`, unitest_ffi:skip/0).
@external(erlang, "owned_test_ffi", "run_unless_skipped")
fn run_unless_skipped(body: fn() -> a) -> Result(a, Nil)

/// Returns when the process has ended, at once if it already has.
@external(erlang, "owned_key_ffi", "wait_until_dead")
fn wait_until_dead(pid: process.Pid) -> Nil

/// Milliseconds on the VM's monotonic clock, for the time a body used.
@external(erlang, "owned_test_ffi", "monotonic_milliseconds")
fn monotonic_milliseconds() -> Int

/// The module and function a body closure was written in, as `module:function`.
@external(erlang, "owned_test_ffi", "body_name")
fn body_name(body: fn() -> a) -> String
