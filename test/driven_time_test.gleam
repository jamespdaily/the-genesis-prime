//// The driven clock's barrier (`driven_time.advance` returns only when every
//// participant is idle), proven on two participants of its own. Expected values
//// come from the contract in the doc comment of `driven_time`: a message a
//// participant sent while it took an input is taken, and the clock it reads for it
//// is counted, before `advance` returns.
//// Every wait is for an event; the one poll (`event_wait.until`) ends on a state a
//// process reaches, never on a time.

import ask_support
import driven_time
import event_wait
import genesis_prime/connection/script.{type Elapsed}
import genesis_prime/service/shell.{type ServiceTime}
import genesis_prime/step.{TimerId}
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference
import gleam/otp/actor
import mailbox_support
import open_wait
import owned_test

/// What a participant tells the test.
type Announced {
  /// The sender has read the clock for its input and waits for the test.
  SenderHoldsInput
  /// The holder has taken the sender's message and waits for the test before it
  /// reads the clock for it.
  HolderHoldsMessage
}

/// The test's order to the sender: take an input, then send `to` a message.
type Work {
  Work(to: Subject(Message))
}

/// What the sender sends the holder.
type Message {
  Message
}

/// A participant the test holds in an input: its subject, the subject that lets
/// it go on and its process.
type Participant(message) {
  Participant(handle: Subject(message), release: Subject(Nil), pid: Pid)
}

/// A participant that reads the clock when it starts and starts a timer on it, so
/// it is the first the barrier knows. Its input, `Work`, reads the clock, tells the
/// test, waits for the test to let it go, and sends the message it was given.
fn start_sender(
  time time: ServiceTime,
  announced announced: Subject(Announced),
  timer_to timer_to: Subject(Elapsed),
) -> Participant(Work) {
  let assert Ok(started) =
    actor.new_with_initialiser(5000, fn(handle) {
      let _now = time.clock()
      let _cancel = time.schedule(timer_to, TimerId(1), reference.new(), 10)
      let release = process.new_subject()
      Ok(
        actor.initialised(release)
        |> actor.returning(#(handle, release)),
      )
    })
    |> actor.on_message(fn(release, work: Work) {
      let _now = time.clock()
      process.send(announced, SenderHoldsInput)
      process.receive_forever(release)
      process.send(work.to, Message)
      actor.continue(release)
    })
    |> actor.start
    as "the sender started"
  let #(handle, release) = started.data
  Participant(handle:, release:, pid: started.pid)
}

/// A participant that reads the clock when it starts. Its input, `Message`, tells
/// the test, waits for the test to let it go, and only then reads the clock.
fn start_holder(
  time time: ServiceTime,
  announced announced: Subject(Announced),
) -> Participant(Message) {
  let assert Ok(started) =
    actor.new_with_initialiser(5000, fn(handle) {
      let _now = time.clock()
      let release = process.new_subject()
      Ok(
        actor.initialised(release)
        |> actor.returning(#(handle, release)),
      )
    })
    |> actor.on_message(fn(release, _message: Message) {
      process.send(announced, HolderHoldsMessage)
      process.receive_forever(release)
      let _now = time.clock()
      actor.continue(release)
    })
    |> actor.start
    as "the holder started"
  let #(handle, release) = started.data
  Participant(handle:, release:, pid: started.pid)
}

fn announcement(announced: Subject(Announced), what what: String) -> Announced {
  open_wait.named(what, fn() { process.receive_forever(announced) })
}

/// How many system messages (`sys:get_state` is one) wait in the process's
/// mailbox, which a process busy in an input does not take.
fn system_messages_waiting(pid: Pid) -> Int {
  mailbox_support.tagged(pid, atom.create("system"))
}

pub fn a_message_sent_late_in_a_pass_is_taken_before_advance_returns_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let service_time = driven_time.service_time(time)
  let announced = process.new_subject()
  let fired = process.new_subject()
  // The sender joins the clock's participants first and the holder second, and
  // the barrier visits the newest first: the holder, then the sender.
  let sender = start_sender(time: service_time, announced:, timer_to: fired)
  let holder = start_holder(time: service_time, announced:)
  process.send(sender.handle, Work(to: holder.handle))
  assert announcement(announced, what: "the sender to hold its input")
    == SenderHoldsInput
  // The timer is the test's own to take: no participant reads the clock for it, so
  // the sender's read is the last one before the barrier's first look.
  let advancing = process.spawn(fn() { driven_time.advance(time:, ms: 10) })
  let advanced = process.monitor(advancing)
  event_wait.until(
    "the barrier's pass to reach the sender, whose input it waits behind",
    fn() { system_messages_waiting(sender.pid) == 1 },
  )
  // The pass has settled the holder, which was idle. The sender now sends it a
  // message and answers; the holder takes the message and waits, before it has
  // read the clock for it.
  process.send(sender.release, Nil)
  assert announcement(
      announced,
      what: "the holder to take the sender's message",
    )
    == HolderHoldsMessage
  event_wait.until("the advance to return or to wait for the holder", fn() {
    !process.is_alive(advancing) || system_messages_waiting(holder.pid) == 1
  })
  assert process.is_alive(advancing)
    as "advance returned while the holder held a message the sender sent late in the pass"
  process.send(holder.release, Nil)
  let _reason =
    ask_support.ended(watched: advanced, what: "the advance to return")
  Nil
}
