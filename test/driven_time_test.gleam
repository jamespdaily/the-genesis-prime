//// The driven clock's barrier (`driven_time.advance` returns only when every
//// participant is idle) and its timers, proven on participants of the test's own.
//// Expected values come from the contract in the doc comment of `driven_time`: a
//// message a participant sent while it took an input is taken, and the clock it
//// reads for it is counted, before `advance` returns; a timer that an input already
//// taken starts is started before the clock moves; a timer cancelled before its time
//// never fires.
//// Every wait is for an event; the one poll (`event_wait.until`) ends on a state a
//// process reaches, never on a time.

import ask_support
import driven_time
import event_wait
import genesis_prime/connection/script.{type Elapsed, Elapsed, Issued, Script}
import genesis_prime/seed
import genesis_prime/service/shell.{type ServiceTime}
import genesis_prime/step.{Now, TimerId}
import genesis_prime/wire_recording.{Accepted}
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference
import gleam/list
import gleam/option.{Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import mailbox_support
import open_wait
import owned_test

/// The participants of the barrier tests.
type Who {
  Sender
  Holder
  Starter
}

/// What a participant tells the test.
type Announced {
  /// The sender has read the clock for its input and waits for the test.
  SenderHoldsInput
  /// The holder has taken the sender's message and waits for the test before it
  /// reads the clock for it.
  HolderHoldsMessage
  /// The starter has taken its input and waits for the test before it starts its timer.
  StarterHoldsInput
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

/// What a system message asks of a process.
type SystemRequest {
  Suspend
  Resume
  Unknown
}

/// The request a system message makes.
@external(erlang, "driven_time_test_ffi", "system_request")
fn system_request(message: Dynamic) -> SystemRequest

/// Answers a system message that asks to suspend or to resume.
@external(erlang, "driven_time_test_ffi", "answer")
fn answer(message: Dynamic) -> Nil

/// A plain process that reads the clock when it starts, so it is a participant,
/// and then takes from one mailbox, in order, its own inputs (`take`) and the
/// barrier's `sys:suspend` and `sys:resume` requests, answers both, and reports to
/// `visits` as `who` once it has answered a resume, which is when the barrier is
/// done with it, so nothing the test releases on that report can reach it ahead of
/// the resume. An input waits for the test to let it go (`release`), and a request
/// that arrives meanwhile waits in the mailbox.
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
      let request = system_request(system)
      answer(system)
      case request {
        Suspend -> Nil
        Resume -> process.send(visits, who)
        Unknown ->
          panic as "a plain participant is sent nothing but its input and the barrier's sys:suspend and sys:resume"
      }
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

/// The starter's input: start a timer for `after_ms`.
type Start {
  Start(after_ms: Int)
}

/// A participant whose input, `Start`, tells the test, waits for the test to let it
/// go, and only then starts a timer on the clock, as a connection starts the timers
/// of an input after it has written that input's frames.
fn start_starter(
  time time: ServiceTime,
  announced announced: Subject(Announced),
  visits visits: Subject(Who),
  timer_to timer_to: Subject(Elapsed),
  timer_reference timer_reference: reference.Reference,
) -> Participant(Start) {
  start_participant(
    who: Starter,
    time:,
    visits:,
    joined: fn() { Nil },
    take: fn(start: Start, release) {
      process.send(announced, StarterHoldsInput)
      process.receive_forever(release)
      let _cancel =
        time.schedule(timer_to, TimerId(1), timer_reference, start.after_ms)
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

/// Returns when `advancing` has ended, or when one system message
/// (`sys:suspend` is one) waits in the participant's mailbox, which a process
/// busy in an input does not take.
fn until_the_advance_returns_or_waits_for(
  advancing advancing: Pid,
  participant participant: Pid,
  what what: String,
) -> Nil {
  event_wait.until(what, fn() {
    !process.is_alive(advancing)
    || mailbox_support.tagged(participant, atom.create("system")) == 1
  })
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
  // reaches the sender, which is busy: the first look reported, which is after the
  // barrier's resume of the participant, is the holder's, and the sender's waits
  // behind its input.
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
  until_the_advance_returns_or_waits_for(
    advancing:,
    participant: holder.pid,
    what: "the advance to return or to wait for the holder",
  )
  assert process.is_alive(advancing)
    as "advance returned while the holder held a message the sender sent late in the pass"
  process.send(holder.release, Nil)
  let _reason =
    ask_support.ended(watched: advanced, what: "the advance to return")
  Nil
}

pub fn a_timer_an_input_already_taken_starts_is_started_before_the_clock_moves_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let service_time = driven_time.service_time(time)
  let announced = process.new_subject()
  let visits = process.new_subject()
  let fired = process.new_subject()
  let timer_reference = reference.new()
  let starter =
    start_starter(
      time: service_time,
      announced:,
      visits:,
      timer_to: fired,
      timer_reference:,
    )
  process.send(starter.handle, Start(after_ms: 1000))
  assert announcement(announced, what: "the starter to hold its input")
    == StarterHoldsInput
  // The starter is in its input, which starts a 1000 ms timer once the test lets it go.
  // `advance` may move the clock by 500 ms only after the starter has started it, so
  // the timer falls due 1000 ms after the clock stood where it does now.
  let advancing = process.spawn(fn() { driven_time.advance(time:, ms: 500) })
  let advanced = process.monitor(advancing)
  until_the_advance_returns_or_waits_for(
    advancing:,
    participant: starter.pid,
    what: "the advance to return or to wait for the starter",
  )
  assert process.is_alive(advancing)
    as "advance returned while a participant held an input that starts a timer"
  process.send(starter.release, Nil)
  let _reason =
    ask_support.ended(watched: advanced, what: "the advance to return")
  driven_time.advance(time:, ms: 500)
  assert process.receive(fired, 0)
    == Ok(Elapsed(timer: TimerId(1), reference: timer_reference))
    as "the timer fell due 1000 ms after the starter's input, 500 ms after the first advance"
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

/// What a script over other scripts keeps and what the driven clock takes: the seed
/// and ordinal the wrapped scripts gave stay, so a tree's seeded listener keeps its
/// seed under a driven clock; the clock and the scheduler are the driven ones.
pub fn scripts_over_other_scripts_keep_their_seed_and_take_the_driven_clock_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let assert Ok(planted_seed) =
    seed.from_bytes(bit_array.concat(list.repeat(<<9>>, seed.byte_count)))
    as "32 bytes are a seed"
  let scheduled_by_the_wrapped = process.new_subject()
  let wrapped_now = Now(monotonic_ms: 4242, filetime: 7)
  let over = fn() {
    Ok(Issued(
      ordinal: 7,
      script: Script(
        seed: planted_seed,
        clock: fn(_input) { wrapped_now },
        node_monotonic_ms: fn(_now) { 4243 },
        schedule: fn(_subject, _timer, _reference, _after_ms) {
          process.send(scheduled_by_the_wrapped, Nil)
          fn() { Nil }
        },
        next_read: fn() { Some(5) },
      ),
    ))
  }
  let assert Ok(issued) = driven_time.scripts(time:, over:)()
    as "the scripts hand out the wrapped script"
  assert issued.ordinal == 7 as "the ordinal is the wrapped script's"
  assert issued.script.seed == planted_seed
    as "the seed is the wrapped script's, not one from the operating system"
  assert issued.script.next_read() == Some(5)
    as "the read size is the wrapped script's"
  assert issued.script.clock(Accepted) == driven_time.now(time:)
    as "the clock reads the driven time"
  assert issued.script.clock(Accepted) != wrapped_now
    as "the wrapped script's clock is not read"
  let _cancel =
    issued.script.schedule(
      process.new_subject(),
      TimerId(4),
      reference.new(),
      100,
    )
  assert driven_time.pending_of(time:, owner: process.self()) == [TimerId(4)]
    as "the timer is started on the driven clock"
  assert process.receive(scheduled_by_the_wrapped, 0) == Error(Nil)
    as "the wrapped script's scheduler started nothing"
}

pub fn scripts_over_scripts_that_have_run_out_pass_the_end_through_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  assert driven_time.scripts(time:, over: fn() { Error(Nil) })() == Error(Nil)
    as "a replay's scripts that have no connection left end the connection, as they do unwrapped"
}

/// The order of a participant of the wait tests: read the clock for an input and
/// answer, or start a timer of its own on the clock and answer.
type Order {
  Read(answer: Subject(Nil))
  StartTimer(after_ms: Int, fires: Subject(Elapsed), answer: Subject(Nil))
}

/// A participant that takes `Order`s: each reads the clock first, as a shell does for
/// each input. It is joined once it has answered its first order.
fn start_orderly_participant(time time: ServiceTime) -> Subject(Order) {
  let assert Ok(started) =
    actor.new(Nil)
    |> actor.on_message(fn(state, order: Order) {
      let _now = time.clock()
      case order {
        Read(answer:) -> process.send(answer, Nil)
        StartTimer(after_ms:, fires:, answer:) -> {
          let _cancel =
            time.schedule(fires, TimerId(1), reference.new(), after_ms)
          process.send(answer, Nil)
        }
      }
      actor.continue(state)
    })
    |> actor.start
    as "the participant started"
  let participant = started.data
  let joined = process.new_subject()
  process.send(participant, Read(answer: joined))
  open_wait.received(from: joined, what: "the participant to join the clock")
  participant
}

pub fn a_wait_whose_condition_still_fails_once_the_participants_are_quiet_fails_at_once_naming_the_wait_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let participant =
    start_orderly_participant(time: driven_time.service_time(time))
  let fires = process.new_subject()
  let started = process.new_subject()
  process.send(participant, StartTimer(after_ms: 10, fires:, answer: started))
  open_wait.received(from: started, what: "the participant to start its timer")
  let before = driven_time.now(time:)
  let ended =
    ask_support.ended_running(fn() {
      driven_time.wait_for(time:, what: "the beast to appear", condition: fn() {
        False
      })
    })
  let message = ask_support.panic_message(ask_support.raised(ended))
  assert string.contains(message, "the beast to appear")
    as "the panic names the wait"
  assert string.contains(message, "quiet")
    as "the panic says why the wait cannot end: the participants are quiet"
  assert driven_time.now(time:) == before
    as "a wait never moves the clock, which only an advance moves"
  assert process.receive(fires, 0) == Error(Nil)
    as "the participant's timer, due 10 ms after the clock, is not fired by the wait"
}

pub fn a_wait_whose_condition_a_participants_pending_input_makes_true_returns_without_moving_the_clock_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let participant =
    start_orderly_participant(time: driven_time.service_time(time))
  let fires = process.new_subject()
  let started = process.new_subject()
  process.send(participant, StartTimer(after_ms: 10, fires:, answer: started))
  open_wait.received(from: started, what: "the participant to start its timer")
  let before = driven_time.now(time:)
  let taken = process.new_subject()
  process.send(participant, Read(answer: taken))
  driven_time.wait_for(
    time:,
    what: "the participant to take its input",
    condition: fn() { mailbox_support.drain(taken) == [Nil] },
  )
  assert driven_time.now(time:) == before
    as "the input was taken with the clock where it was"
  assert process.receive(fires, 0) == Error(Nil)
    as "the participant's timer is not fired by the wait"
}

pub fn the_clock_keeps_its_mailbox_off_its_heap_test() -> Nil {
  use <- owned_test.run(30_000)
  // Every creature of a crowd reads the clock for its input, so the clock's mailbox
  // holds one read for each of 2,400 creatures at once; on the heap, each collection
  // of the clock copies them all and moves them again after a full sweep.
  let time = driven_time.new()
  assert mailbox_support.kept_off_heap(driven_time.driver(time))
    as "the clock's mailbox is outside its heap"
}

pub fn an_advance_with_no_barrier_fires_the_timers_of_the_one_participant_that_is_held_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let held = start_orderly_participant(time: driven_time.service_time(time))
  let fires = process.new_subject()
  let started = process.new_subject()
  process.send(held, StartTimer(after_ms: 10, fires:, answer: started))
  open_wait.received(from: started, what: "the participant to start its timer")
  driven_time.advance_while_a_participant_waits(
    time:,
    held: owner_of(held),
    ms: 10,
  )
  assert result.is_ok(process.receive(fires, 0))
    as "the held participant's timer, due within the advance, was fired"
}

pub fn an_advance_with_no_barrier_fails_naming_a_second_participant_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let service_time = driven_time.service_time(time)
  let held = start_orderly_participant(time: service_time)
  let second = start_orderly_participant(time: service_time)
  let fires = process.new_subject()
  let started = process.new_subject()
  process.send(held, StartTimer(after_ms: 10, fires:, answer: started))
  open_wait.received(from: started, what: "the participant to start its timer")
  let before = driven_time.now(time:)
  let ended =
    ask_support.ended_running(fn() {
      driven_time.advance_while_a_participant_waits(
        time:,
        held: owner_of(held),
        ms: 10,
      )
    })
  let message = ask_support.panic_message(ask_support.raised(ended))
  assert string.contains(message, driven_time.pid_text(owner_of(second)))
    as "the panic names the second participant"
  assert string.contains(message, "only participant")
    as "the panic says why: the barriers are dropped only for a clock with one participant"
  assert driven_time.now(time:) == before as "a refused advance moves nothing"
  assert process.receive(fires, 0) == Error(Nil) as "and fires no timer"
}

fn owner_of(participant: Subject(Order)) -> Pid {
  let assert Ok(pid) = process.subject_owner(participant)
    as "an actor's subject belongs to its process"
  pid
}
