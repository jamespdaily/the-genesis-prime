//// Runs a test body in a process the test owns, so a hung test fails and
//// what a test started stops with it. Every test body runs inside `run`.

import gleam/bool
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import open_wait
import owned_key
import unitest

pub type Outcome(a) {
  Returned(a)
  Skipped
  Crashed
}

/// What the waiting caller hears: the body's end, a one-time build the body
/// opened or closed (`database_support.once`), or a wait the body began or
/// ended (`open_wait.named`).
type Event(a) {
  Finished(Outcome(a))
  Down
  BuildOpened(key: String)
  BuildClosed
  WaitOpened(what: String)
  WaitClosed
}

/// Why a body ended without returning.
type Failure {
  PastDeadline(waiting: List(String))
  BuildNeverEnded(keys: String)
}

/// The longest a one-time build may stay open: the body's own build, or its
/// wait for another test's build of the same key.
const build_limit_ms = 120_000

/// Runs a test body in its own process, with a deadline. When the body
/// returns, crashes or runs past the deadline, that process is killed, so
/// every process linked to it stops too. A body that skips through
/// `unitest.guard` is skipped in the caller, so the runner reports a skip.
///
/// The deadline counts the body's own work. While the body is inside
/// `database_support.once`, building a value or waiting for another test's
/// build of it, the deadline waits, and goes on with the time it had left when
/// the value is there: a one-time build serves the whole run, so whichever test
/// asks first would otherwise pay for all of it. A call from a process the body
/// started is not the body's, so its time counts. An open build has a limit of
/// its own (`build_limit_ms`); past it the test fails, naming the key.
///
/// A wait of the body (a read of the server's frames, a poll of a state) has no
/// limit of its own: it ends with the event it waits for, or the deadline ends
/// the test, and the failure then names the waits still open, the innermost
/// first.
///
/// A body that returns after more than half its deadline prints one
/// `check WARNING` line with the test's name, the milliseconds of its own work
/// and its deadline, which `./check`'s summary repeats. It warns and never
/// fails: a loaded machine runs the same work slower, so the warning shows a
/// test that is near its deadline before the deadline ends it.
///
/// A body that returns with persistent terms still stored under the keys it made
/// (`owned_key`) fails, and the terms are erased so the tests after it do not
/// pay for them. A body that crashes or runs past its deadline fails for that,
/// and its terms are erased too.
pub fn run(timeout_ms: Int, body: fn() -> a) -> a {
  let reply = process.new_subject()
  let worker =
    process.spawn_unlinked(fn() {
      mark_body(
        opened: fn(key) { process.send(reply, BuildOpened(key)) },
        closed: fn() { process.send(reply, BuildClosed) },
      )
      open_wait.reporting(
        opened: fn(what) { process.send(reply, WaitOpened(what)) },
        closed: fn() { process.send(reply, WaitClosed) },
      )
      process.send(
        reply,
        Finished(case run_unless_skipped(body) {
          Ok(value) -> Returned(value)
          Error(Nil) -> Skipped
        }),
      )
      process.sleep_forever()
    })
  let monitor = process.monitor(worker)
  let started = monotonic_milliseconds()
  let #(outcome, own_left) =
    wait(
      reply:,
      monitor:,
      own_left: timeout_ms,
      open: [],
      waiting: [],
      build_began: started,
      since: started,
    )
  let used = timeout_ms - own_left
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
    Error(PastDeadline(waiting:)) ->
      panic as {
        "the test ran past its deadline "
        <> case waiting {
          [] -> "with no wait open"
          _ -> "while waiting for: " <> string.join(waiting, " > ")
        }
      }
    Error(BuildNeverEnded(keys:)) ->
      panic as {
        "a one-time build stayed open past its "
        <> int.to_string(build_limit_ms)
        <> " ms limit: "
        <> keys
      }
  }
}

/// Waits for the body's end and returns it with the deadline left. `own_left`
/// is the deadline not yet used, `open` the keys of the builds the body is
/// inside (the innermost first), `build_began` when the outermost of them
/// opened and `since` when the last event came. The time with a build open is
/// not taken from `own_left`. `waiting` holds the names of the waits the body is
/// inside, the innermost first; they do not stop the deadline.
fn wait(
  reply reply: process.Subject(Event(a)),
  monitor monitor: process.Monitor,
  own_left own_left: Int,
  open open: List(String),
  waiting waiting: List(String),
  build_began build_began: Int,
  since since: Int,
) -> #(Result(Outcome(a), Failure), Int) {
  let within = case open {
    [] -> int.max(own_left, 0)
    _ -> int.max(build_limit_ms - { since - build_began }, 0)
  }
  let received =
    process.new_selector()
    |> process.select(reply)
    |> process.select_specific_monitor(monitor, fn(_down) { Down })
    |> process.selector_receive(within:)
  let now = monotonic_milliseconds()
  let own_left = case open {
    [] -> own_left - { now - since }
    _ -> own_left
  }
  case received {
    Error(Nil) ->
      case open {
        [] -> #(Error(PastDeadline(waiting:)), own_left)
        _ -> #(
          Error(BuildNeverEnded(string.join(list.reverse(open), " > "))),
          own_left,
        )
      }
    Ok(Finished(outcome)) -> #(Ok(outcome), own_left)
    Ok(Down) -> #(Ok(Crashed), own_left)
    Ok(BuildOpened(key)) ->
      wait(
        reply:,
        monitor:,
        own_left:,
        open: [key, ..open],
        waiting:,
        build_began: case open {
          [] -> now
          _ -> build_began
        },
        since: now,
      )
    Ok(BuildClosed) ->
      wait(
        reply:,
        monitor:,
        own_left:,
        open: list.drop(open, 1),
        waiting:,
        build_began:,
        since: now,
      )
    Ok(WaitOpened(what)) ->
      wait(
        reply:,
        monitor:,
        own_left:,
        open:,
        waiting: [what, ..waiting],
        build_began:,
        since: now,
      )
    Ok(WaitClosed) ->
      wait(
        reply:,
        monitor:,
        own_left:,
        open:,
        waiting: list.drop(waiting, 1),
        build_began:,
        since: now,
      )
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

/// Marks the calling process as a test body: its one-time builds
/// (`owned_test_ffi:counting_build/2`) call `opened` with the key when one
/// starts and `closed` when it has ended.
@external(erlang, "owned_test_ffi", "mark_body")
fn mark_body(
  opened opened: fn(String) -> Nil,
  closed closed: fn() -> Nil,
) -> Nil

/// Returns when the process has ended, at once if it already has.
@external(erlang, "owned_key_ffi", "wait_until_dead")
fn wait_until_dead(pid: process.Pid) -> Nil

/// Milliseconds on the VM's monotonic clock, for the time a body used.
@external(erlang, "owned_test_ffi", "monotonic_milliseconds")
fn monotonic_milliseconds() -> Int

/// The module and function a body closure was written in, as `module:function`.
@external(erlang, "owned_test_ffi", "body_name")
fn body_name(body: fn() -> a) -> String
