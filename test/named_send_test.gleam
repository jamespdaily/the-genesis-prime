//// Sending to a name from a process that must not crash when the name has no
//// process. gleam_erlang's `process.send` to a named subject asserts that a
//// process is registered, so a process that ends between a caller's check and
//// its send crashes the caller; `named_send.send` looks the name up when the
//// message is delivered and gives no error when there is none
//// (`erlang:send_after/3` in the OTP reference manual). The race itself is a
//// window of microseconds that no test can hold open, so the tests fix the two
//// states on either side of it: a name with no process, and a name with one.
//// Messages from one process to another arrive in the order they were sent
//// (the OTP reference manual, "Processes", signal ordering), which a timer of
//// 0 ms does not give: its message waits on a timer wheel of a scheduler, so
//// a test sends a hundred thousand in a row and checks the order they arrive in.

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

/// The numbers `next` to `last`, each sent to the subject by `named_send.send`
/// from one process, as fast as it can.
fn send_in_a_row(subject: process.Subject(Int), next: Int, last: Int) -> Nil {
  case next > last {
    True -> Nil
    False -> {
      named_send.send(subject, next)
      send_in_a_row(subject, next + 1, last)
    }
  }
}

fn receive_in_a_row(
  subject: process.Subject(Int),
  next: Int,
  last: Int,
) -> Result(Nil, Int) {
  case next > last {
    True -> Ok(Nil)
    False ->
      case process.receive(subject, 5000) {
        Ok(number) if number == next -> receive_in_a_row(subject, next + 1, last)
        Ok(number) -> Error(number)
        Error(Nil) -> Error(0)
      }
  }
}

pub fn messages_sent_in_a_row_to_a_name_arrive_in_the_order_they_were_sent_test() -> Nil {
  use <- owned_test.run(60_000)
  let name = process.new_name("in_order")
  let assert Ok(Nil) = process.register(process.self(), name)
    as "the name is free"
  let subject = process.named_subject(name)
  let last = 100_000
  process.spawn(fn() { send_in_a_row(subject, 1, last) })
  assert receive_in_a_row(subject, 1, last) == Ok(Nil)
    as "a delivery that a map sent before another about the same unit is not handed over after it: 'unit appeared' then 'unit left' reach a player in that order (OTP reference manual: signals between two processes arrive in the order sent)"
}

pub fn messages_sent_in_a_row_to_a_subject_arrive_in_the_order_they_were_sent_test() -> Nil {
  use <- owned_test.run(60_000)
  let subject = process.new_subject()
  let last = 100_000
  process.spawn(fn() { send_in_a_row(subject, 1, last) })
  assert receive_in_a_row(subject, 1, last) == Ok(Nil)
    as "a subject that names no process keeps the order as well"
}
