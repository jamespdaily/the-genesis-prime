//// The driven clock's barrier (`driven_time.advance` returns only when every
//// participant is idle) and its timers, proven on participants of the test's own.
//// Expected values come from the contract in the doc comment of `driven_time`: a
//// message a participant sent while it took an input is taken, and the clock it
//// reads for it is counted, before `advance` returns; a timer cancelled before its
//// time never fires.
//// Every wait is for an event; the one poll (`event_wait.until`) ends on a state a
//// process reaches, never on a time.

import ask_support
import driven_time
import event_wait
import genesis_prime/connection/script.{type Elapsed}
import genesis_prime/service/shell.{type ServiceTime}
import genesis_prime/step.{TimerId}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference
import mailbox_support
import open_wait
import owned_test

/// The two participants of the barrier test.
type Who {
  Sender
  Holder
}

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

/// What a plain participant takes from its mailbox, in the order it came: its own
/// input, or anything else, which is a system message.
type Taken(message) {
  Input(message)
  Other(Dynamic)
}

/// A participant the test holds in an input: its subject, the subject that lets it
/// go on and its process.
type Participant(message) {
  Participant(handle: Subject(message), release: Subject(Nil), pid: Pid)
}

/// Answers a `sys:get_state` request and says whether `message` was one.
@external(erlang, "driven_time_test_ffi", "answered_get_state")
fn answered_get_state(message: Dynamic) -> Bool

/// A plain process that reads the clock when it starts, so it is a participant,
/// and then takes from one mailbox, in order, its own inputs (`take`) and the
/// barrier's `sys:get_state` requests, each of which it reports to `visits` as
/// `who` and answers. An input waits for the test to let it go (`release`), and a
/// request that arrives meanwhile waits in the mailbox.
fn start_participant(
  who who: Who,
  time time: ServiceTime,
  visits visits: Subject(Who),
  joined joined: fn() -> Nil,
  take take: fn(message, Subject(Nil)) -> Nil,
) -> Participant(message) {
  let ready = process.new_subject()
  let pid =
    process.spawn(fn() {
      let handle = process.new_subject()
      let release = process.new_subject()
      let _now = time.clock()
      joined()
      process.send(ready, #(handle, release))
      serve(who:, visits:, handle:, release:, take:)
    })
  let #(handle, release) =
    open_wait.received(from: ready, what: "a participant to join the clock")
  Participant(handle:, release:, pid:)
}

fn serve(
  who who: Who,
  visits visits: Subject(Who),
  handle handle: Subject(message),
  release release: Subject(Nil),
  take take: fn(message, Subject(Nil)) -> Nil,
) -> Nil {
  let taken =
    process.new_selector()
    |> process.select_map(handle, Input)
    |> process.select_other(Other)
    |> process.selector_receive_forever
  case taken {
    Input(message) -> take(message, release)
    Other(system) -> {
      process.send(visits, who)
      let assert True = answered_get_state(system)
        as "a plain participant is sent nothing but its input and sys:get_state"
      Nil
    }
  }
  serve(who:, visits:, handle:, release:, take:)
}

/// A participant that starts a timer on the clock, so it is the first the barrier
/// knows. Its input, `Work`, reads the clock, tells the test, waits for the test to
/// let it go, and sends the message it was given.
fn start_sender(
  time time: ServiceTime,
  announced announced: Subject(Announced),
  visits visits: Subject(Who),
  timer_to timer_to: Subject(Elapsed),
) -> Participant(Work) {
  start_participant(
    who: Sender,
    time:,
    visits:,
    joined: fn() {
      let _cancel = time.schedule(timer_to, TimerId(1), reference.new(), 10)
      Nil
    },
    take: fn(work: Work, release) {
      let _now = time.clock()
      process.send(announced, SenderHoldsInput)
      process.receive_forever(release)
      process.send(work.to, Message)
    },
  )
}

/// A participant whose input, `Message`, tells the test, waits for the test to let
/// it go, and only then reads the clock.
fn start_holder(
  time time: ServiceTime,
  announced announced: Subject(Announced),
  visits visits: Subject(Who),
) -> Participant(Message) {
  start_participant(
    who: Holder,
    time:,
    visits:,
    joined: fn() { Nil },
    take: fn(_message: Message, release) {
      process.send(announced, HolderHoldsMessage)
      process.receive_forever(release)
      let _now = time.clock()
      Nil
    },
  )
}

fn announcement(announced: Subject(Announced), what what: String) -> Announced {
  open_wait.received(from: announced, what: what)
}

fn visit(visits: Subject(Who), what what: String) -> Who {
  open_wait.received(from: visits, what: what)
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
  let visits = process.new_subject()
  let fired = process.new_subject()
  let sender =
    start_sender(time: service_time, announced:, visits:, timer_to: fired)
  let holder = start_holder(time: service_time, announced:, visits:)
  process.send(sender.handle, Work(to: holder.handle))
  assert announcement(announced, what: "the sender to hold its input")
    == SenderHoldsInput
  // The timer is the test's own to take: no participant reads the clock for it, so
  // the sender's read is the last one before the barrier's first look.
  let advancing = process.spawn(fn() { driven_time.advance(time:, ms: 10) })
  let advanced = process.monitor(advancing)
  // The case needs the barrier to settle the holder, which is idle, before it
  // reaches the sender, which is busy: the first look the barrier makes is the
  // holder's, and the sender's waits behind its input.
  assert visit(visits, what: "the barrier's first look at a participant")
    == Holder
  // The sender now sends the holder a message and answers; the holder takes the
  // message and waits, before it has read the clock for it.
  process.send(sender.release, Nil)
  assert announcement(
      announced,
      what: "the holder to take the sender's message",
    )
    == HolderHoldsMessage
  assert visit(visits, what: "the barrier's look at the sender") == Sender
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

pub fn a_timer_cancelled_before_its_time_never_fires_on_the_driven_clock_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let service_time = driven_time.service_time(time)
  let fired = process.new_subject()
  // The process that starts the timer ends with it cancelled: a participant that
  // stays must answer the barrier, and the test's process does not.
  let _reason =
    ask_support.ended_running(fn() {
      let cancel = service_time.schedule(fired, TimerId(1), reference.new(), 10)
      cancel()
    })
  driven_time.advance(time:, ms: 20)
  // Absence check: the limit is how long this watches for a message that must
  // not come, here a look at the mailbox now.
  assert process.receive(fired, 0) == Error(Nil)
}
