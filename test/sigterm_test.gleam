//// What the host's stop signal does to the server's tree. Expected values come
//// from these places.
//// - CLAUDE.md and the designing-processes skill: shutdown is ordered, so a
////   stopping server gives every process its `Stopping`, and a recorded
////   process closes its recording with `End` (`genesis_prime/step/runtime`).
//// - OTP: SIGTERM makes the VM run `init:stop`, which stops the applications
////   and halts; a supervisor started outside an application is not stopped by
////   it, which is why the server stops its own tree on the signal.
//// A node of its own serves a tree with a recorded service, is sent SIGTERM and
//// ends; the recording it left is read here.

import genesis_prime/hand_off
import genesis_prime/rule_recording.{type Record, End, Taken}
import genesis_prime/server
import genesis_prime/service
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{Input, Started, Stopping}
import gleam/erlang/process
import gleam/option.{Some}
import gleam/otp/static_supervisor as supervisor
import owned_test
import recording_support

/// Runs in the node the test starts: a tree with the recorded hand-off service,
/// stopped on the signal as the server's is. Returns with the tree running.
pub fn serve(folder: String) -> Nil {
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(
      service_shell.supervised(service_shell.Settings(
        rule: hand_off.rule(),
        name: process.new_name("hand_off"),
        reach: service.Reach(
          locate: fn(_address) { Error(Nil) },
          send: fn(_to, _message) { Error(Nil) },
        ),
        shutdown_ms: 5000,
        recorder: Some(recording_support.recorder(
          folder,
          rule_module: hand_off.rule_name,
        )),
      )),
    )
    |> supervisor.start
    as "the tree started"
  process.unlink(started.pid)
  server.stop_on_sigterm(tree: started.pid)
}

@external(erlang, "sigterm_ffi", "terminate_a_serving_node")
fn terminate_a_serving_node(folder: String) -> Result(Nil, Nil)

pub fn a_services_recording_ends_with_end_when_the_server_is_stopped_by_sigterm_test() -> Nil {
  use <- owned_test.run(120_000)
  use folder <- recording_support.in_folder
  assert terminate_a_serving_node(folder) == Ok(Nil)
    as "the node ended after SIGTERM"
  let assert Ok(#(_, records)) =
    rule_recording.read(recording_support.recording_in(folder))
    as "the recording reads"
  let records: List(Record(hand_off.Message, Nil, hand_off.Answer, Nil)) =
    records
  let assert [
    Taken(input: Input(event: Started, ..), ..),
    Taken(
      input: Input(event: Stopping(..), ..),
      step: step.Effects([step.Stop]),
    ),
    End(count: 2),
  ] = records
    as "the signal reached the service as Stopping, and the recording ends with End"
  Nil
}
