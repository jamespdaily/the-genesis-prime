//// The test helper `owned_test.run`. Expected values are the helper's own
//// contract, stated in its doc comment: when the body returns, crashes or runs
//// past the deadline, its process is killed so every process linked to it
//// stops, and a crash or a missed deadline fails the test with the messages
//// named below. A panic is observed from outside, in a separate unlinked
//// process, because the helper's panic is what these tests assert on.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process.{type Pid}
import gleam/result
import owned_test
import unitest

pub fn a_process_linked_to_the_body_is_dead_after_the_body_returns_test() -> Nil {
  use <- owned_test.run(5000)
  let reported = process.new_subject()
  owned_test.run(5000, fn() {
    let linked = process.spawn(fn() { process.sleep_forever() })
    process.send(reported, linked)
  })
  let assert Ok(linked) = process.receive(reported, 0)
    as "the body did not report its linked process"
  assert is_dead_within(linked, 5000)
}

pub fn a_body_that_runs_past_its_deadline_fails_with_the_deadline_message_test() -> Nil {
  use <- owned_test.run(5000)
  let reason =
    exit_reason_of(fn() { owned_test.run(50, fn() { process.sleep_forever() }) })
  assert panic_message(reason) == Ok("the test ran past its deadline")
}

pub fn a_body_that_runs_past_its_deadline_is_stopped_and_the_run_goes_on_test() -> Nil {
  use <- owned_test.run(5000)
  let reported = process.new_subject()
  let reason =
    exit_reason_of(fn() {
      owned_test.run(50, fn() {
        process.send(reported, process.self())
        process.sleep_forever()
      })
    })
  assert reason != process.Normal
  let assert Ok(hung) = process.receive(reported, 0)
    as "the hung body did not report its process"
  assert is_dead_within(hung, 5000)
}

pub fn a_body_that_crashes_fails_with_the_crash_message_test() -> Nil {
  use <- owned_test.run(5000)
  let reason =
    exit_reason_of(fn() {
      owned_test.run(5000, fn() { panic as "the planted body crashed" })
    })
  assert panic_message(reason) == Ok("the test body crashed")
}

pub fn a_body_that_skips_is_skipped_not_crashed_test() -> Nil {
  use <- owned_test.run(5000)
  let reason =
    exit_reason_of(fn() {
      owned_test.run(5000, fn() {
        use <- unitest.guard(False)
        Nil
      })
    })
  assert is_skip(reason)
    as "a skip inside the helper reached the runner as a crash, not a skip"
}

fn is_skip(reason: process.ExitReason) -> Bool {
  case reason {
    process.Abnormal(reason:) -> is_skip_reason(reason)
    process.Normal | process.Killed -> False
  }
}

@external(erlang, "owned_test_ffi", "is_skip")
fn is_skip_reason(reason: Dynamic) -> Bool

fn is_dead_within(pid: Pid, timeout: Int) -> Bool {
  let monitor = process.monitor(pid)
  let outcome =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(_down) { Nil })
    |> process.selector_receive(within: timeout)
  outcome == Ok(Nil)
}

/// Runs the work in a separate unlinked process and waits for it to exit, so a
/// panic inside it is seen as a reason and does not fail this test.
fn exit_reason_of(work: fn() -> a) -> process.ExitReason {
  let worker = process.spawn_unlinked(work)
  let monitor = process.monitor(worker)
  let selected =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(down) { down })
    |> process.selector_receive(within: 5000)
  case selected {
    Ok(process.ProcessDown(reason:, ..)) -> reason
    Ok(process.PortDown(..)) -> panic as "a port went down, not the worker"
    Error(Nil) -> panic as "the worker did not exit within 5000 ms"
  }
}

/// The message of a Gleam panic that ended a process: the exit reason is the
/// panic's map and a stack trace, and the map's `message` key holds the text.
fn panic_message(reason: process.ExitReason) -> Result(String, Nil) {
  case reason {
    process.Abnormal(raw) -> {
      let assert Ok(key) = atom.get("message")
        as "the atom `message` is not known"
      decode.run(raw, panic_details())
      |> result.replace_error(Nil)
      |> result.try(dict.get(_, key))
      |> result.try(fn(value) {
        decode.run(value, decode.string) |> result.replace_error(Nil)
      })
    }
    process.Normal | process.Killed -> Error(Nil)
  }
}

fn panic_details() -> decode.Decoder(dict.Dict(atom.Atom, Dynamic)) {
  decode.field(0, decode.dict(atom.decoder(), decode.dynamic), decode.success)
}
