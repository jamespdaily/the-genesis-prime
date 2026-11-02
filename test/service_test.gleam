//// Sending to a process by the name it is registered under
//// (`genesis_prime/service.send_by_name`). Expected values come from
//// gleam_erlang's own subjects: a message sent through a subject made by
//// `process.named_subject(name)` is the tuple `#(name, message)` sent to the
//// process registered under the name, which `process.receive` on a named
//// subject takes (gleam_erlang `process.send`, `NamedSubject`). `send_by_name`
//// writes that form itself, since `process.send` on a named subject crashes
//// the sender when the name is not registered, and the test pins the form: a
//// message sent by name is received through the named subject.

import genesis_prime/service
import gleam/erlang/process
import owned_test

pub fn a_message_sent_by_name_is_received_through_the_named_subject_test() -> Nil {
  use <- owned_test.run(5000)
  let name = process.new_name("service_test_receiver")
  let assert Ok(Nil) = process.register(process.self(), name)
    as "the name is a fresh one, so no process holds it"
  let sent = service.send_by_name(name:, message: "hello")
  assert sent == Ok(process.self())
    as "the pid of the process that holds the name, which the asker monitors"
  assert process.receive(process.named_subject(name), within: 1000)
    == Ok("hello")
    as "gleam_erlang: a named subject takes the message sent to its registered process as #(name, message)"
}

pub fn a_message_sent_by_a_name_no_process_holds_is_not_sent_test() -> Nil {
  use <- owned_test.run(5000)
  let name = process.new_name("service_test_nobody")
  assert service.send_by_name(name:, message: "hello") == Error(Nil)
    as "no process holds a fresh name, and the sender does not crash"
}
