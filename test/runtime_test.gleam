//// The sentences the shells and the application log for a process that ended
//// or did not start (`genesis_prime/step/runtime`). The expected texts are
//// Erlang's own writing of the reason (`io_lib:format("~0p")`: an atom bare, a
//// tuple in braces, a map as `#{key => value}`), so the log line says what
//// ended the process.

import genesis_prime/step/runtime
import gleam/dynamic
import gleam/erlang/atom
import gleam/erlang/process
import gleam/otp/actor
import owned_test

pub fn an_exit_is_described_by_its_reason_as_erlang_writes_it_test() -> Nil {
  use <- owned_test.run(5000)
  let boom = atom.to_dynamic(atom.create("boom"))
  assert runtime.describe_exit(process.Normal) == "normal"
  assert runtime.describe_exit(process.Killed) == "killed"
  assert runtime.describe_exit(
      process.Abnormal(atom.to_dynamic(atom.create("shutdown"))),
    )
    == "shutdown"
    as "an atom is its name"
  assert runtime.describe_exit(
      process.Abnormal(dynamic.array([boom, dynamic.int(7)])),
    )
    == "{boom,7}"
    as "a tuple is not only 'a tuple': its elements are in the line"
  assert runtime.describe_exit(
      process.Abnormal(dynamic.properties([#(boom, dynamic.string("on fire"))])),
    )
    == "#{boom => <<\"on fire\">>}"
    as "a map is not only 'a map'"
}

pub fn a_start_error_is_a_phrase_for_the_caller_to_put_after_its_subject_test() -> Nil {
  use <- owned_test.run(5000)
  assert runtime.describe_start_error(actor.InitTimeout)
    == "did not start in time"
  assert runtime.describe_start_error(actor.InitFailed("no room"))
    == "failed to start: no room"
  assert runtime.describe_start_error(
      actor.InitExited(process.Abnormal(dynamic.array([dynamic.int(7)]))),
    )
    == "exited while it started: {7}"
    as "the exit reason is in the phrase, whatever its shape"
  assert runtime.describe_start_error(actor.InitExited(process.Killed))
    == "exited while it started: killed"
}
