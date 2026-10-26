//// Sending to a name from a process that must not crash when the name has no
//// process. gleam_erlang's `process.send` to a named subject asserts that a
//// process is registered, so a process that ends between a caller's check and
//// its send crashes the caller; `named_send.send` looks the name up when the
//// message is delivered and gives no error when there is none
//// (`erlang:send_after/3` in the OTP reference manual). The race itself is a
//// window of microseconds that no test can hold open, so the tests fix the two
//// states on either side of it: a name with no process, and a name with one.

import genesis_prime/connection/named_send
import gleam/erlang/process
import owned_test

pub fn a_send_to_a_name_with_no_process_is_dropped_and_not_a_crash_test() -> Nil {
  use <- owned_test.run(5000)
  let name = process.new_name("nobody_here")
  named_send.send(process.named_subject(name), "hello")
  assert process.is_alive(process.self())
    as "the sender goes on: the message went nowhere"
}

pub fn a_send_to_a_name_with_a_process_is_delivered_test() -> Nil {
  use <- owned_test.run(5000)
  let name = process.new_name("somebody_here")
  let assert Ok(Nil) = process.register(process.self(), name)
    as "the name is free"
  let subject = process.named_subject(name)
  named_send.send(subject, "hello")
  assert process.receive(subject, 1000) == Ok("hello")
    as "the process the name reaches gets the message"
}

pub fn a_send_to_a_subject_that_has_no_name_is_delivered_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = process.new_subject()
  named_send.send(subject, "hello")
  assert process.receive(subject, 1000) == Ok("hello")
    as "a subject owned by a process reaches it"
}
