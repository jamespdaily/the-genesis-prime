//// The poller that reads the state script for the Overview, driven by messages
//// from the test: the script runner is a fake that records each read and is
//// answered by the test, the clock stands still, and the timers never come
//// (the interval is a day), so every read, answer and deadline is a message the
//// test sends. Expected values are the poller's rules: it reads only while a
//// page is subscribed, hands each subscriber the latest reading at once, starts
//// no second read while one runs, and shows a read that failed, hung or passed
//// its deadline as the last reading marked stale with the reason.

import dashboard_reading_support as support
import dashboard_timer_support as timers
import genesis_prime/dashboard/host
import genesis_prime/dashboard/host_reading.{
  type Reading, Fresh, MachineUp, NoNewReading, ReadFailed, Stale,
}
import genesis_prime/dashboard/script
import genesis_prime/dashboard/subscribers
import gleam/bool
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import open_wait
import owned_test

/// A read the poller started: answering it ends the read.
type Call {
  Call(answer: fn(Result(script.Finished, script.Failure)) -> Nil)
}

/// The moment the stopped clock shows.
const now_ms = 5000

const deadline_ms = 15_000

/// A poller whose reads are recorded in `calls`, by the stopped clock.
fn started() -> #(Subject(host.Message), Subject(Call)) {
  started_by(fn() { now_ms })
}

/// A poller whose reads are recorded in `calls`, stamped by `clock`.
fn started_by(clock: fn() -> Int) -> #(Subject(host.Message), Subject(Call)) {
  started_with(clock, 86_400_000, subscribers.send_after)
}

/// The interval the driven poller is set to; its timers are armed for it.
const driven_interval_ms = 2000

/// A poller whose timers are the test's: each one armed or cancelled is sent to
/// `events`, and none fires until the test fires it.
fn started_driven(
  events: Subject(timers.Event),
) -> #(Subject(host.Message), Subject(Call)) {
  started_with(fn() { now_ms }, driven_interval_ms, timers.arm(events))
}

fn started_with(
  clock: fn() -> Int,
  interval_ms: Int,
  arm: subscribers.Arm(host.Message),
) -> #(Subject(host.Message), Subject(Call)) {
  let calls = process.new_subject()
  let settings =
    host.Settings(
      start_read: fn(answer) { process.send(calls, Call(answer:)) },
      now_ms: clock,
      interval_ms:,
      deadline_ms:,
      arm:,
    )
  let assert Ok(started) = host.start(settings) as "the poller did not start"
  #(started.data, calls)
}

/// What a clock process is told.
type ClockMessage {
  SetClock(ms: Int)
  AskClock(reply: Subject(Int))
}

/// A clock the test moves: a process holds the time, and the poller asks it each
/// time it stamps a reading. Returns the clock and the function that sets it.
fn moving_clock(start_ms: Int) -> #(fn() -> Int, fn(Int) -> Nil) {
  let made = process.new_subject()
  let _clock =
    process.spawn(fn() {
      let inbox = process.new_subject()
      process.send(made, inbox)
      clock_loop(inbox, start_ms)
    })
  let inbox = open_wait.received(made, "the clock")
  #(fn() { process.call_forever(inbox, AskClock) }, fn(ms) {
    process.send(inbox, SetClock(ms:))
  })
}

fn clock_loop(inbox: Subject(ClockMessage), ms: Int) -> Nil {
  case process.receive_forever(inbox) {
    SetClock(ms:) -> clock_loop(inbox, ms)
    AskClock(reply:) -> {
      process.send(reply, ms)
      clock_loop(inbox, ms)
    }
  }
}

/// What the script gives when `connections` are open and all else is healthy.
fn report(connections: Int) -> Result(script.Finished, script.Failure) {
  Ok(script.Finished(
    output: support.text(
      support.changed([
        support.Set("game_connections", int.to_string(connections)),
      ]),
    ),
    status: 0,
  ))
}

/// The next read the poller started.
fn next_read(calls: Subject(Call)) -> Call {
  open_wait.received(from: calls, what: "the poller to start a read")
}

/// The next reading a subscriber was sent.
fn next_reading(subscriber: Subject(Reading)) -> Reading {
  open_wait.received(from: subscriber, what: "a reading")
}

/// The poller has handled every message sent to it before this, so a read it
/// would have started is already in `calls`.
fn handled(host: Subject(host.Message)) -> Nil {
  let _count = host.subscriber_count(host)
  Nil
}

fn no_read_started(calls: Subject(Call)) -> Bool {
  process.receive(calls, 0) == Error(Nil)
}

fn no_reading_sent(subscriber: Subject(Reading)) -> Bool {
  process.receive(subscriber, 0) == Error(Nil)
}

/// The number of game connections a reading shows, and that they are fresh.
fn fresh_connections(reading: Reading) -> Int {
  let assert Fresh(connections, read_ms) = reading.connections
    as "the connections are not fresh"
  assert read_ms == now_ms
  connections
}

pub fn the_poller_reads_only_while_a_page_is_subscribed_and_hands_each_subscriber_the_latest_at_once_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(host, calls) = started()
  let first = process.new_subject()
  let second = process.new_subject()

  // Nobody is subscribed: a tick reads nothing.
  host.poll_now(host)
  handled(host)
  assert no_read_started(calls) as "a read started with no subscriber"

  // The first subscriber starts one read and gets its reading.
  host.subscribe(host, first)
  let read = next_read(calls)
  assert no_reading_sent(first) as "a reading came before the read ended"
  read.answer(report(1))
  assert fresh_connections(next_reading(first)) == 1
  assert no_read_started(calls) as "the first subscriber started two reads"

  // A second subscriber gets the latest at once and starts no read.
  host.subscribe(host, second)
  let latest = next_reading(second)
  assert fresh_connections(latest) == 1
  handled(host)
  assert no_read_started(calls) as "a second subscriber started a read"
  assert host.subscriber_count(host) == 2

  // Both gone: a tick reads nothing.
  host.unsubscribe(host, first)
  host.unsubscribe(host, second)
  host.poll_now(host)
  assert host.subscriber_count(host) == 0
  assert no_read_started(calls) as "a read started with nobody subscribed"

  // A page that opens after the pages left waits for a read of its own: it is
  // not handed a reading that was taken before.
  let third = process.new_subject()
  host.subscribe(host, third)
  let read = next_read(calls)
  handled(host)
  assert no_reading_sent(third) as "an old reading was handed to a new page"
  read.answer(report(2))
  assert fresh_connections(next_reading(third)) == 2
  host.unsubscribe(host, third)
  assert host.subscriber_count(host) == 0
}

pub fn a_subscriber_that_dies_is_dropped_and_a_tick_then_reads_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(host, calls) = started()

  // A subscriber in a process of its own, which ends when told; the subjects
  // it receives on are made in it, since a subject is received by its maker.
  let ready = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      let mine = process.new_subject()
      let stop = process.new_subject()
      host.subscribe(host, mine)
      let reading = next_reading(mine)
      process.send(ready, #(reading, stop))
      process.receive_forever(stop)
    })
  let monitor = process.monitor(pid)
  let read = next_read(calls)
  read.answer(report(1))
  let #(reading, stop) = open_wait.received(ready, "the subscriber's reading")
  assert fresh_connections(reading) == 1
  assert host.subscriber_count(host) == 1

  process.send(stop, Nil)
  let _down =
    open_wait.selected(
      process.new_selector()
        |> process.select_specific_monitor(monitor, fn(_down) { Nil }),
      "the subscriber to end",
    )
  // The poller learns of the end by its own monitor; its count says when.
  wait_for_count(host, 0)
  host.poll_now(host)
  handled(host)
  assert no_read_started(calls) as "a read started for a page that is gone"
}

/// Asks the poller for its subscribers until it holds `count`; each ask ends
/// with the poller's answer.
fn wait_for_count(host: Subject(host.Message), count: Int) -> Nil {
  use <- bool.guard(when: host.subscriber_count(host) == count, return: Nil)
  wait_for_count(host, count)
}

pub fn a_tick_while_a_read_runs_starts_no_second_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(host, calls) = started()
  let page = process.new_subject()
  host.subscribe(host, page)

  // The read is not answered: a tick starts no second read and sends nothing.
  let read = next_read(calls)
  host.poll_now(host)
  handled(host)
  assert no_read_started(calls) as "a tick started a second read"
  assert no_reading_sent(page) as "a tick sent a reading with no read ended"

  // The answer ends the read; the next tick reads again.
  read.answer(report(1))
  assert fresh_connections(next_reading(page)) == 1
  host.poll_now(host)
  let again = next_read(calls)
  again.answer(report(2))
  assert fresh_connections(next_reading(page)) == 2
}

pub fn a_read_past_its_deadline_is_sent_as_stale_and_a_late_answer_is_dropped_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(host, calls) = started()
  let page = process.new_subject()
  host.subscribe(host, page)
  let first = next_read(calls)
  first.answer(report(1))
  assert fresh_connections(next_reading(page)) == 1

  // The second read hangs; the deadline comes.
  host.poll_now(host)
  let hung = next_read(calls)
  host.deadline_now(host)
  let stale = next_reading(page)
  let reason = ReadFailed("the state script did not finish in 15 s")
  assert stale.machine == Stale(MachineUp, reason, now_ms)
  assert stale.connections == Stale(1, reason, now_ms)
  assert stale.server == Stale(support.running_server(), reason, now_ms)

  // The hung read answers late: nothing is sent.
  hung.answer(report(3))
  handled(host)
  assert no_reading_sent(page) as "a late answer was sent"

  // The next tick reads again, and its answer is sent fresh.
  host.poll_now(host)
  let next = next_read(calls)
  next.answer(report(2))
  assert fresh_connections(next_reading(page)) == 2
}

pub fn a_failing_script_is_sent_as_stale_with_its_reason_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(host, calls) = started()
  let page = process.new_subject()
  host.subscribe(host, page)
  let first = next_read(calls)
  first.answer(report(1))
  let good = next_reading(page)
  assert good.updater == Fresh(support.idle_updater(), now_ms)

  host.poll_now(host)
  let failing = next_read(calls)
  failing.answer(
    Ok(script.Finished(output: <<"podman: no route\nmore\n":utf8>>, status: 1)),
  )
  let stale = next_reading(page)
  let reason =
    ReadFailed("the state script exited with status 1: podman: no route")
  assert stale.machine == Stale(MachineUp, reason, now_ms)
  assert stale.updater == Stale(support.idle_updater(), reason, now_ms)
  assert stale.connections == Stale(1, reason, now_ms)

  // A runner that could not run the script is the same: stale, with its reason.
  host.poll_now(host)
  let missing = next_read(calls)
  missing.answer(Error(script.NotFound("dev/play_service/state.sh")))
  let absent = next_reading(page)
  assert absent.connections
    == Stale(
      1,
      ReadFailed("the state script is not found: dev/play_service/state.sh"),
      now_ms,
    )
}

pub fn a_page_that_leaves_and_returns_while_a_read_runs_waits_for_that_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(host, calls) = started()

  // The page leaves while the read runs and another opens: no second read starts.
  let first = process.new_subject()
  host.subscribe(host, first)
  let read = next_read(calls)
  host.unsubscribe(host, first)
  let second = process.new_subject()
  host.subscribe(host, second)
  handled(host)
  assert no_read_started(calls)
    as "a returning page started a read beside one that runs"

  // The answer of the read that ran across the gap is the new page's reading.
  read.answer(report(1))
  assert fresh_connections(next_reading(second)) == 1
  assert no_reading_sent(first) as "a page that left was sent a reading"
  assert no_read_started(calls) as "the answer started a read"

  // A read that ends while nobody is subscribed is dropped: the next page waits
  // for a read of its own and is not handed it.
  let #(host, calls) = started()
  let third = process.new_subject()
  host.subscribe(host, third)
  let read = next_read(calls)
  host.unsubscribe(host, third)
  read.answer(report(2))
  handled(host)
  let fourth = process.new_subject()
  host.subscribe(host, fourth)
  let own = next_read(calls)
  handled(host)
  assert no_reading_sent(fourth)
    as "a read from before the gap was handed to a new page"
  own.answer(report(3))
  assert fresh_connections(next_reading(fourth)) == 3
}

pub fn a_tick_while_a_read_runs_past_six_seconds_shows_every_fact_stale_with_its_age_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(clock, set_clock) = moving_clock(1000)
  let #(host, calls) = started_by(clock)
  let page = process.new_subject()
  host.subscribe(host, page)
  next_read(calls).answer(report(0))
  assert next_reading(page)
    == support.every_fact(composed_ms: 1000, freshness: support.AllFresh(1000))

  // The second read hangs; six seconds after the last reading every fact is
  // shown stale because no new reading came, and nothing failed.
  host.poll_now(host)
  let hung = next_read(calls)
  set_clock(7000)
  host.poll_now(host)
  assert next_reading(page)
    == support.every_fact(
      composed_ms: 7000,
      freshness: support.AllStale(NoNewReading, 1000),
    )
  assert no_read_started(calls) as "a tick started a second read"

  // The age goes on counting at the next tick.
  set_clock(9000)
  host.poll_now(host)
  assert next_reading(page)
    == support.every_fact(
      composed_ms: 9000,
      freshness: support.AllStale(NoNewReading, 1000),
    )

  // The read's answer makes every fact fresh again.
  set_clock(9500)
  hung.answer(report(2))
  let again = next_reading(page)
  assert again.connections == Fresh(2, 9500)
  assert again.server == Fresh(support.running_server(), 9500)
}

// ---------------------------------------------------------------------------
// The poller's timer, driven by the test.

/// What the poller did to its timers since the last look, after it has handled
/// what was sent to it.
fn timers_changed(
  host: Subject(host.Message),
  events: Subject(timers.Event),
) -> List(timers.Event) {
  handled(host)
  all_events(events, [])
}

fn all_events(
  events: Subject(timers.Event),
  found: List(timers.Event),
) -> List(timers.Event) {
  case timers.next(events:) {
    Ok(next) -> all_events(events, [next, ..found])
    Error(Nil) -> list.reverse(found)
  }
}

/// The timer that is the only change, which is armed for the interval.
fn the_one_timer_armed(changes: List(timers.Event)) -> timers.Event {
  let assert [armed] = changes
    as "one timer should have been armed, and nothing else"
  let assert timers.Armed(after_ms:, ..) = armed
    as "the change is not an arming"
  assert after_ms == driven_interval_ms
  armed
}

pub fn each_tick_arms_the_next_tick_for_as_long_as_a_page_is_subscribed_test() -> Nil {
  use <- owned_test.run(5000)
  let events = process.new_subject()
  let #(host, calls) = started_driven(events)
  host.subscribe(host:, subscriber: process.new_subject())
  let first = the_one_timer_armed(timers_changed(host, events))
  let _read = next_read(calls)

  // A tick while the read runs starts no second read; it arms the next tick.
  timers.fire(first)
  let second = the_one_timer_armed(timers_changed(host, events))
  assert no_read_started(calls)
  timers.fire(second)
  let _third = the_one_timer_armed(timers_changed(host, events))
  assert no_read_started(calls)
  Nil
}

pub fn the_last_page_to_leave_cancels_the_timer_and_a_later_tick_of_it_arms_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let events = process.new_subject()
  let #(host, _calls) = started_driven(events)
  let page = process.new_subject()
  host.subscribe(host:, subscriber: page)
  let armed = the_one_timer_armed(timers_changed(host, events))

  host.unsubscribe(host:, subscriber: page)
  let assert timers.Armed(timer:, ..) = armed
  assert timers_changed(host, events) == [timers.Cancelled(timer:)]

  timers.fire(armed)
  assert timers_changed(host, events) == []
}

pub fn a_tick_sent_before_its_timer_was_cancelled_starts_no_second_timer_chain_test() -> Nil {
  use <- owned_test.run(5000)
  let events = process.new_subject()
  let #(host, _calls) = started_driven(events)
  let leaving = process.new_subject()
  host.subscribe(host:, subscriber: leaving)
  let stale = the_one_timer_armed(timers_changed(host, events))
  host.unsubscribe(host:, subscriber: leaving)
  host.subscribe(host:, subscriber: process.new_subject())
  let assert [timers.Cancelled(..), current] = timers_changed(host, events)
    as "the first timer was cancelled and a second was armed"

  // The first timer's tick is in the mailbox: it is dropped and arms nothing.
  timers.fire(stale)
  assert timers_changed(host, events) == []

  // The second timer's tick arms one timer.
  timers.fire(current)
  let _next = the_one_timer_armed(timers_changed(host, events))
  Nil
}
