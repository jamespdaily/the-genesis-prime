//// What reaches a connection shell from other processes, and the effects that
//// name them, proven on the signalling rule. Expected values come from these
//// places.
//// - The shell's contract in the doc comment of `genesis_prime/connection/shell`:
////   a connection joins the registry as it is accepted; a message delivered to
////   it reaches the rule as `Woken`; a watch's end comes back once as
////   `WatchEnded` with the watch's id (the watches themselves are tested in
////   `watch_test`); a target no process holds ends as the next input once the
////   step is done, before the mailbox is read, the step's watches in the order
////   opened; a timer fires once as `TimerFired`, a cancelled one never
////   does, and a timeout whose reference is not the timer's own is discarded.
//// - OTP's `erlang:send_after` and `erlang:cancel_timer`: a message already sent
////   when the timer is cancelled stays in the mailbox, which is the reason the
////   shell discards a timeout by its reference.
//// - The shell's wait during an ask: a delivered message, a timer's timeout or
////   a watch's end that arrives during it is taken after the ask's outcome,
////   and two messages from one sender in the order they were sent (Erlang
////   orders signals only per sender).
//// Every wait is for bytes the server writes, with a deadline a passing test
//// never reaches.

import ask_support
import event_wait
import genesis_prime/connection/registry
import genesis_prime/connection/script
import genesis_prime/service
import genesis_prime/step.{type Address, ConnectionId, Sessions}
import genesis_prime/step/runtime
import genesis_prime/step/watch
import genesis_prime/world_map/map_id
import gleam/erlang/atom
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import log_capture
import mailbox_support
import mug
import owned_test
import signalling_rule
import unitest

/// One record the signalling rule wrote.
type Record {
  Record(letter: Int, number: Int)
}

fn start(
  registry registry: option.Option(registry.Registry(Int)),
  sessions sessions: Result(Pid, Nil),
) -> ask_support.Server {
  start_asking(
    registry:,
    sessions:,
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
  )
}

/// As `start`, with the directory the rule's asks go through.
fn start_asking(
  registry registry: option.Option(registry.Registry(Int)),
  sessions sessions: Result(Pid, Nil),
  directory directory: fn(Nil, Int, fn(Nil) -> Nil) -> Result(service.Sent, Nil),
) -> ask_support.Server {
  ask_support.start_joined(
    rule: signalling_rule.rule(),
    directory:,
    shutdown_ms: 1000,
    registry:,
    locate: fn(address: Address) {
      case address {
        Sessions -> sessions
        step.HandOff
        | step.Store
        | step.Maps
        | step.Map(..)
        | step.Creature(..)
        | step.CharacterNamed(..)
        | step.ZoneChannel(..)
        | step.Connection(..) -> Error(Nil)
      }
    },
    with: fn(builder) {
      case registry {
        Some(registry) -> supervisor.add(builder, registry.supervised(registry))
        None -> builder
      }
    },
  )
}

fn read_record(client: mug.Socket) -> Record {
  let assert Ok(<<letter, number:64-signed>>) =
    mug.receive_exact(
      client,
      byte_size: 9,
      timeout_milliseconds: ask_support.event_wait_ms,
    )
    as "a record arrived"
  Record(letter:, number:)
}

/// The id the connection's rule was accepted with.
fn accepted_id(client: mug.Socket) -> Int {
  let Record(letter:, number:) = read_record(client)
  assert letter == signalling_rule.accepted
    as "the first record is the accept's"
  number
}

pub fn a_connection_joins_the_registry_as_it_is_accepted_and_a_delivered_message_reaches_the_rule_as_woken_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = registry.new()
  let server =
    start(registry: Some(scope), sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  assert registry.find(scope, ConnectionId(id)) == Ok(connection)
    as "the connection is the one member of the group of its id"
  assert registry.deliver(scope, ConnectionId(id), 7) == Ok(Nil)
  assert registry.deliver(scope, ConnectionId(id), 8) == Ok(Nil)
  assert read_record(client) == Record(signalling_rule.woken, 7)
    as "the first message reaches the rule as Woken"
  assert read_record(client) == Record(signalling_rule.woken, 8)
    as "and the second after it, in the order they were sent"
  assert registry.deliver(scope, ConnectionId(id + 1), 9) == Error(Nil)
    as "no connection has another id, so nothing is sent"
  ask_support.stop(server)
}

pub fn a_connection_that_ended_leaves_its_group_and_a_message_to_it_is_dropped_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = registry.new()
  let server =
    start(registry: Some(scope), sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
  let gone = process.monitor(connection)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  let _reason = ask_support.ended(gone)
  event_wait.until(
    "the scope noticed the end by itself, so no process finds the id",
    fn() { registry.find(scope, ConnectionId(id)) == Error(Nil) },
  )
  assert registry.deliver(scope, ConnectionId(id), 1) == Error(Nil)
    as "nothing is sent to a connection that is gone"
  ask_support.stop(server)
}

pub fn a_watched_process_that_ends_comes_back_once_as_watch_ended_with_the_watchs_id_test() -> Nil {
  use <- owned_test.run(30_000)
  let sessions = ask_support.idle_process()
  let server = start(registry: None, sessions: Ok(sessions))
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  ask_support.command(
    client:,
    letter: signalling_rule.watch_command,
    n: 1,
    wait_ms: 0,
  )
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 5,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 5)
    as "the watch is open and the target runs, so nothing has ended"
  let ended = process.monitor(sessions)
  process.kill(sessions)
  let _reason = ask_support.ended(ended)
  assert read_record(client) == Record(signalling_rule.watch_ended, 1)
    as "the target's end reached the rule as WatchEnded(WatchId(1))"
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 6,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 6)
    as "the end came once"
  ask_support.stop(server)
}

pub fn a_watch_of_a_target_no_process_holds_ends_as_the_next_input_before_a_message_already_queued_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = registry.new()
  let server = start(registry: Some(scope), sessions: Error(Nil))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  // The shell is suspended, so both messages are queued before it takes
  // either. The message -1 makes the rule watch Sessions, which `locate`
  // finds no process for.
  ask_support.while_suspended(connection, fn() {
    assert registry.deliver(scope, ConnectionId(id), -1) == Ok(Nil)
    assert registry.deliver(scope, ConnectionId(id), 7) == Ok(Nil)
  })
  assert read_record(client) == Record(signalling_rule.woken, -1)
    as "X, whose step watches the target, is the first input"
  assert read_record(client) == Record(signalling_rule.watch_ended, 1)
    as "the end of X's watch is the next input, before the message queued behind X"
  assert read_record(client) == Record(signalling_rule.woken, 7)
    as "Y is taken after it"
  ask_support.stop(server)
}

pub fn two_watches_of_targets_no_process_holds_end_in_the_order_opened_before_the_next_mailbox_input_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = registry.new()
  let server = start(registry: Some(scope), sessions: Error(Nil))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  // The shell is suspended, so both messages are queued before it takes
  // either. The message -2 makes the rule watch 1 and 2 on Sessions, which
  // `locate` finds no process for.
  ask_support.while_suspended(connection, fn() {
    assert registry.deliver(scope, ConnectionId(id), -2) == Ok(Nil)
    assert registry.deliver(scope, ConnectionId(id), 7) == Ok(Nil)
  })
  assert read_record(client) == Record(signalling_rule.woken, -2)
    as "X, whose step opens both watches, is the first input"
  assert read_record(client) == Record(signalling_rule.watch_ended, 1)
    as "the first watch opened ends first"
  assert read_record(client) == Record(signalling_rule.watch_ended, 2)
    as "the second next, and both before the message queued behind X"
  assert read_record(client) == Record(signalling_rule.woken, 7)
  ask_support.stop(server)
}

pub fn a_timer_fires_once_as_timer_fired_with_its_id_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 1,
    wait_ms: 20,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 1)
    as "the timer fired as TimerFired(TimerId(1))"
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 2,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 2)
    as "the timer fired once"
  ask_support.stop(server)
}

pub fn a_timer_started_again_with_the_same_id_after_it_fired_fires_again_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 1,
    wait_ms: 20,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 1)
    as "the first start of timer 1 fired as TimerFired(TimerId(1))"
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 1,
    wait_ms: 20,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 1)
    as "the shell's contract: a timer that fired is forgotten, so the rule may start its id again and it fires again"
  ask_support.stop(server)
}

pub fn a_rule_that_starts_a_timer_with_a_negative_id_ends_its_connection_since_the_shell_keeps_those_ids_for_its_own_timers_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  ask_support.command(
    client:,
    letter: signalling_rule.negative_timer_command,
    n: 1,
    wait_ms: 60_000,
  )
  event_wait.until("the connection ended", fn() {
    ask_support.connections(server) == []
  })
  assert mug.receive(client, ask_support.event_wait_ms) == Error(mug.Closed)
    as "the shell closed the socket"
  ask_support.stop(server)
}

pub fn a_cancelled_timer_never_fires_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  // One step starts timer 1 for no time, then timer 2, the witness, then cancels
  // timer 1. The witness is started after timer 1, so it is due after it however
  // late the step runs, and its firing is an input of a later step, so it comes
  // after the cancel. A cancel that fails to stop timer 1 or its timeout lets
  // timer 1 fire before the witness, and a cancel that ignores its timer's id
  // takes the witness down with timer 1.
  ask_support.command(
    client:,
    letter: signalling_rule.start_witness_then_cancel_command,
    n: 1,
    wait_ms: 100,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 2)
    as "timer 2 fired and timer 1, due earlier, never reached the rule"
  ask_support.stop(server)
}

pub fn a_timer_that_fired_during_an_ask_and_is_started_again_by_its_outcome_is_not_fired_by_the_old_timeout_test() -> Nil {
  use <- owned_test.run(30_000)
  let replies = process.new_subject()
  let server =
    start_asking(
      registry: None,
      sessions: Ok(ask_support.idle_process()),
      directory: asked_through(replies, ask_support.idle_process()),
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  // Timer 2 fires at once, during the ask's wait, so its timeout is in the
  // mailbox when the outcome comes. The outcome's step cancels timer 2 and
  // starts it again with a minute to run: the old timeout names a timer id
  // that is running, with another reference, and must not fire it.
  let assert Ok(Nil) =
    mug.send(client, <<
      signalling_rule.timer_command, 2, 0:16, signalling_rule.ask_command,
      signalling_rule.restarting_ask, 20_000:16,
    >>)
    as "the step was sent"
  let assert Ok(reply) = process.receive(replies, ask_support.event_wait_ms)
    as "the shell made the ask"
  event_wait.until("the timer's timeout waits in the mailbox", fn() {
    mailbox_support.tagged_by_reference(connection) == 1
  })
  reply(Nil)
  assert read_record(client)
    == Record(signalling_rule.answered, signalling_rule.restarting_ask)
    as "the ask's outcome is the first input after the step"
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 9,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 9)
    as "the old timeout was dropped by its reference: no timer_fired record comes before the pong"
  ask_support.stop(server)
}

pub fn a_timer_that_fired_during_an_ask_and_is_cancelled_by_its_outcome_never_reaches_the_rule_test() -> Nil {
  use <- owned_test.run(30_000)
  let replies = process.new_subject()
  let server =
    start_asking(
      registry: None,
      sessions: Ok(ask_support.idle_process()),
      directory: asked_through(replies, ask_support.idle_process()),
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  // Timer 1 fires at once, during the ask's wait, so its timeout is in the
  // mailbox when the outcome comes; the outcome's step cancels timer 1.
  let assert Ok(Nil) =
    mug.send(client, <<
      signalling_rule.timer_command, 1, 0:16, signalling_rule.ask_command, 1,
      20_000:16,
    >>)
    as "the step was sent"
  let assert Ok(reply) = process.receive(replies, ask_support.event_wait_ms)
    as "the shell made the ask"
  event_wait.until("the timer's timeout waits in the mailbox", fn() {
    mailbox_support.tagged_by_reference(connection) == 1
  })
  reply(Nil)
  assert read_record(client) == Record(signalling_rule.answered, 1)
    as "the ask's outcome is the first input after the step"
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 9,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 9)
    as "the timeout of the cancelled timer was dropped: no timer_fired record comes before the pong"
  ask_support.stop(server)
}

pub fn a_message_a_timeout_and_a_watch_end_that_arrive_during_an_ask_are_taken_after_its_outcome_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = registry.new()
  let sessions = ask_support.idle_process()
  let replies = process.new_subject()
  let server =
    start_asking(
      registry: Some(scope),
      sessions: Ok(sessions),
      directory: asked_through(replies, ask_support.idle_process()),
    )
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  ask_support.command(
    client:,
    letter: signalling_rule.watch_command,
    n: 1,
    wait_ms: 0,
  )
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 3,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 3)
    as "the watch is open"
  let assert Ok(Nil) =
    mug.send(client, <<
      signalling_rule.timer_command, 2, 0:16, signalling_rule.ask_command, 1,
      20_000:16,
    >>)
    as "the step was sent"
  let assert Ok(reply) = process.receive(replies, ask_support.event_wait_ms)
    as "the shell made the ask"
  assert registry.deliver(scope, ConnectionId(id), 7) == Ok(Nil)
  assert registry.deliver(scope, ConnectionId(id), 8) == Ok(Nil)
  process.kill(sessions)
  event_wait.until(
    "a message, a timeout and a watch's end all wait in the mailbox",
    fn() {
      mailbox_support.tagged(connection, atom.create("woken")) == 2
      && mailbox_support.tagged(connection, atom.create("DOWN")) == 1
      && mailbox_support.tagged_by_reference(connection) == 1
    },
  )
  reply(Nil)
  assert read_record(client) == Record(signalling_rule.answered, 1)
    as "the ask's outcome came first: nothing was taken during the wait"
  let after = list.map([1, 2, 3, 4], fn(_) { read_record(client) })
  assert list.contains(after, Record(signalling_rule.timer_fired, 2))
    as "the timeout was taken after the outcome"
  assert list.contains(after, Record(signalling_rule.watch_ended, 1))
    as "so was the watch's end"
  assert list.filter(after, fn(record) {
      record.letter == signalling_rule.woken
    })
    == [
      Record(signalling_rule.woken, 7),
      Record(signalling_rule.woken, 8),
    ]
    as "and the two messages, in the order the test sent them"
  ask_support.stop(server)
}

/// A directory that hands each ask's reply to `replies` and says it went to
/// `target`.
fn asked_through(
  replies: process.Subject(fn(Nil) -> Nil),
  target: Pid,
) -> fn(Nil, Int, fn(Nil) -> Nil) -> Result(service.Sent, Nil) {
  fn(_request, _deadline_ms, reply) {
    process.send(replies, reply)
    Ok(service.ToService(pid: target))
  }
}

pub fn a_message_no_selector_takes_is_dropped_and_logged_by_its_kind_with_the_connection_named_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let lines = process.new_subject()
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  mailbox_support.send_raw(
    connection,
    #(atom.create("stray_message"), <<
      "a-fake-session-key":utf8,
    >>),
  )
  let assert Ok(#(level, text, metadata)) =
    process.receive(lines, ask_support.event_wait_ms)
    as "the stray message was logged"
  log_capture.stop(capture)
  assert level == "warning" as "a message nobody takes is a warning"
  assert string.contains(text, "stray_message")
    as "the line names the message's kind, its tag"
  assert !string.contains(text, "a-fake-session-key")
    as "and never its contents, which could hold a secret"
  assert list.key_find(metadata, "connection")
    == Ok("{connection_id," <> int.to_string(id) <> "}")
    as "the line names the connection by the id its rule was accepted with"
  assert case list.key_find(metadata, "peer") {
    Ok(peer) -> string.contains(peer, "127.0.0.1")
    Error(Nil) -> False
  }
    as "and the client's address"
  assert mailbox_support.tagged(connection, atom.create("stray_message")) == 0
    as "the message was taken from the mailbox"
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 1,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 1)
    as "and the connection goes on"
  ask_support.stop(server)
}

@external(erlang, "connection_actor_support_ffi", "kept_asks")
fn kept_asks(connection: Pid) -> Int

pub fn a_late_answer_between_steps_gives_the_rule_no_input_and_drops_the_kept_ask_test() -> Nil {
  use <- owned_test.run(30_000)
  let replies = process.new_subject()
  let target = ask_support.idle_process()
  let server =
    start_asking(
      registry: None,
      sessions: Ok(ask_support.idle_process()),
      directory: asked_through(replies, target),
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  // Ask 1 has 100 ms and nobody answers: its outcome is NoAnswerInTime, and
  // the shell keeps its tag and its monitor of the target.
  ask_support.command(
    client:,
    letter: signalling_rule.ask_command,
    n: 1,
    wait_ms: 100,
  )
  let assert Ok(reply) = process.receive(replies, ask_support.event_wait_ms)
    as "the shell made the ask"
  assert read_record(client) == Record(signalling_rule.answered, 1)
    as "the ask came back as the rule's input"
  assert kept_asks(connection) == 1 as "the shell keeps the ask"
  assert list.contains(mailbox_support.monitored(connection), target)
    as "and its monitor of the target"
  // The answer comes between steps, with no ask waiting.
  reply(Nil)
  event_wait.until("the late answer was taken and its ask dropped", fn() {
    kept_asks(connection) == 0
  })
  assert !list.contains(mailbox_support.monitored(connection), target)
    as "the ask's monitor was dropped with it"
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 9,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 9)
    as "the late answer gave the rule no input: the next record is the pong"
  ask_support.stop(server)
}

pub fn the_end_of_a_kept_asks_target_gives_the_rule_no_input_and_drops_the_kept_ask_test() -> Nil {
  use <- owned_test.run(30_000)
  let replies = process.new_subject()
  let target = ask_support.idle_process()
  let server =
    start_asking(
      registry: None,
      sessions: Ok(ask_support.idle_process()),
      directory: asked_through(replies, target),
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  ask_support.command(
    client:,
    letter: signalling_rule.ask_command,
    n: 1,
    wait_ms: 100,
  )
  let assert Ok(_reply) = process.receive(replies, ask_support.event_wait_ms)
    as "the shell made the ask"
  assert read_record(client) == Record(signalling_rule.answered, 1)
    as "the ask came back as the rule's input"
  assert kept_asks(connection) == 1 as "the shell keeps the ask"
  process.kill(target)
  event_wait.until("the target's end was taken and its ask dropped", fn() {
    kept_asks(connection) == 0
  })
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 9,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 9)
    as "the end gave the rule no input: the next record is the pong"
  ask_support.stop(server)
}

// ---- a tell ----

/// A lookup of the process `sessions` that logs each call to `lookups` with a
/// generation number of its own, and gives a way to tell it that sends the
/// same number to `told` each time it is used, so a test reads which lookup
/// each tell went through.
fn counting_lookup(
  sessions sessions: Pid,
  lookups lookups: process.Subject(Int),
  told told: process.Subject(Int),
) -> fn(Address) -> Result(watch.Found(fn(Nil) -> Nil), Nil) {
  fn(_address) {
    let generation = runtime.unique_id()
    process.send(lookups, generation)
    Ok(
      watch.Tellable(pid: sessions, sender: fn(_request) {
        process.send(told, generation)
      }),
    )
  }
}

fn start_telling(
  locate locate: fn(Address) -> Result(watch.Found(fn(Nil) -> Nil), Nil),
  deliver deliver: fn(Address, Nil) -> Result(Nil, Nil),
) -> ask_support.Server {
  ask_support.start_telling(
    rule: signalling_rule.rule(),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms: 1000,
    wire_recorder: None,
    scripts: script.operating_system,
    registry: None,
    locate:,
    deliver:,
    with: fn(builder) { builder },
  )
}

/// Sends the rule's command and reads the pong that follows it, so every
/// effect of the commands before has been carried out.
fn command_then_pong(
  client client: mug.Socket,
  letter letter: Int,
  n n: Int,
  pong pong: Int,
) -> Nil {
  ask_support.command(client:, letter:, n:, wait_ms: 0)
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: pong,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, pong)
  Nil
}

pub fn a_tell_goes_through_the_target_resolved_when_the_watch_opened_and_looks_nothing_up_test() -> Nil {
  use <- owned_test.run(30_000)
  let lookups = process.new_subject()
  let told = process.new_subject()
  let server =
    start_telling(
      locate: counting_lookup(
        sessions: ask_support.idle_process(),
        lookups:,
        told:,
      ),
      deliver: fn(_address, _request) { Error(Nil) },
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  command_then_pong(
    client:,
    letter: signalling_rule.watch_command,
    n: 1,
    pong: 1,
  )
  let assert [generation] = mailbox_support.drain(lookups)
    as "the watch's open resolved the target once, before any tell"
  list.each([2, 3, 4], fn(pong) {
    command_then_pong(
      client:,
      letter: signalling_rule.tell_command,
      n: 0,
      pong:,
    )
  })
  assert mailbox_support.drain(lookups) == [] as "a tell looks nothing up"
  assert mailbox_support.drain(told) == [generation, generation, generation]
    as "each tell went through the resolve the watch's open made"
  ask_support.stop(server)
}

pub fn a_tell_after_the_watch_is_dropped_goes_nowhere_and_one_after_a_watch_opened_again_goes_through_the_new_resolve_test() -> Nil {
  use <- owned_test.run(30_000)
  let lookups = process.new_subject()
  let told = process.new_subject()
  let server =
    start_telling(
      locate: counting_lookup(
        sessions: ask_support.idle_process(),
        lookups:,
        told:,
      ),
      deliver: fn(_address, _request) { Error(Nil) },
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  command_then_pong(
    client:,
    letter: signalling_rule.watch_command,
    n: 1,
    pong: 1,
  )
  let assert [first] = mailbox_support.drain(lookups)
  command_then_pong(
    client:,
    letter: signalling_rule.unwatch_command,
    n: 1,
    pong: 2,
  )
  command_then_pong(
    client:,
    letter: signalling_rule.tell_command,
    n: 0,
    pong: 3,
  )
  assert mailbox_support.drain(told) == []
    as "the watch was dropped: the tell has no target and is dropped"
  command_then_pong(
    client:,
    letter: signalling_rule.watch_command,
    n: 1,
    pong: 4,
  )
  let assert [second] = mailbox_support.drain(lookups)
  assert second != first
  command_then_pong(
    client:,
    letter: signalling_rule.tell_command,
    n: 0,
    pong: 5,
  )
  assert mailbox_support.drain(told) == [second]
    as "a rejoin tells the run it joined, never the one it left"
  ask_support.stop(server)
}

pub fn a_tell_after_the_watched_process_ended_goes_nowhere_test() -> Nil {
  use <- owned_test.run(30_000)
  let lookups = process.new_subject()
  let told = process.new_subject()
  let sessions = ask_support.idle_process()
  let server =
    start_telling(
      locate: counting_lookup(sessions:, lookups:, told:),
      deliver: fn(_address, _request) { Error(Nil) },
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  command_then_pong(
    client:,
    letter: signalling_rule.watch_command,
    n: 1,
    pong: 1,
  )
  let ended = process.monitor(sessions)
  process.kill(sessions)
  let _reason = ask_support.ended(ended)
  assert read_record(client) == Record(signalling_rule.watch_ended, 1)
  command_then_pong(
    client:,
    letter: signalling_rule.tell_command,
    n: 0,
    pong: 2,
  )
  assert mailbox_support.drain(told) == []
    as "the process the tell would reach is gone: its end forgot the way to it"
  ask_support.stop(server)
}

// ---- a socket closed by the peer ----

pub fn a_read_that_cannot_be_armed_because_the_peer_closed_reaches_the_rule_as_a_closed_socket_with_no_warning_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("serial")
  let lines = process.new_subject()
  let scope = registry.new()
  let server =
    start(registry: Some(scope), sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  let gone = process.monitor(connection)
  // The message 0 gives the rule nothing to write, so the step ends in arming
  // the socket's read. The client's close is queued behind the message, and
  // the shell's own port has closed itself by the time it is armed: the arm
  // fails (einval) while the close waits in the mailbox.
  ask_support.while_suspended(connection, fn() {
    assert registry.deliver(scope, ConnectionId(id), 0) == Ok(Nil)
    let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
    event_wait.until("the close reached the connection's mailbox", fn() {
      mailbox_support.queued(connection) >= 2
    })
  })
  let _reason = ask_support.ended(gone)
  ask_support.stop(server)
  log_capture.stop(capture)
  assert list.filter(mailbox_support.drain(lines), fn(line) {
      line.0 == "warning" || line.0 == "error"
    })
    == []
    as "a socket the peer closed is no warning, whichever call found it out"
}

pub fn a_tell_to_a_connection_is_delivered_with_no_watch_and_one_that_is_gone_is_dropped_with_no_warning_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("serial")
  let lines = process.new_subject()
  let delivered = process.new_subject()
  let server =
    start_telling(
      locate: fn(_address) { Error(Nil) },
      deliver: fn(address, _request) {
        process.send(delivered, address)
        case address {
          step.Connection(ConnectionId(99)) -> Error(Nil)
          step.Connection(..)
          | step.Sessions
          | step.HandOff
          | step.Store
          | step.Maps
          | step.CharacterNamed(..)
          | step.ZoneChannel(..)
          | step.Creature(..)
          | step.Map(..) -> Ok(Nil)
        }
      },
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  // Only this test's connection is read: another test's connection or Ranch
  // listener logging at the same time is no line of this one.
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  command_then_pong(
    client:,
    letter: signalling_rule.tell_connection_command,
    n: 7,
    pong: 1,
  )
  command_then_pong(
    client:,
    letter: signalling_rule.tell_connection_command,
    n: 99,
    pong: 2,
  )
  assert mailbox_support.drain(delivered)
    == [step.Connection(ConnectionId(7)), step.Connection(ConnectionId(99))]
    as "each tell reached the settings' deliver by the connection's address, with no watch opened"
  ask_support.stop(server)
  log_capture.stop(capture)
  assert list.filter(mailbox_support.drain(lines), fn(line) {
      line.0 == "warning" || line.0 == "error"
    })
    == []
    as "a connection that is gone is no warning: a player's viewers end all the time"
}

pub fn a_join_makes_the_connection_a_member_of_the_group_and_a_leave_or_its_end_removes_it_test() -> Nil {
  use <- owned_test.run(30_000)
  let scope = registry.new()
  let server =
    start(registry: Some(scope), sessions: Ok(ask_support.idle_process()))
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
  command_then_pong(
    client:,
    letter: signalling_rule.join_command,
    n: 5,
    pong: 1,
  )
  assert registry.find_named(scope, "5") == Ok(connection)
    as "JoinGroup(CharacterNamed) made the connection the group's member, once its step's effects were carried out"
  command_then_pong(
    client:,
    letter: signalling_rule.join_command,
    n: 5,
    pong: 2,
  )
  assert registry.find_named(scope, "5") == Ok(connection)
    as "a second JoinGroup of the same group leaves the connection a member"
  command_then_pong(
    client:,
    letter: signalling_rule.leave_command,
    n: 5,
    pong: 3,
  )
  assert registry.find_named(scope, "5") == Error(Nil)
    as "LeaveGroup removed it: one leave is enough after two joins, since a group holds a process once"
  command_then_pong(
    client:,
    letter: signalling_rule.leave_command,
    n: 5,
    pong: 4,
  )
  command_then_pong(
    client:,
    letter: signalling_rule.join_command,
    n: 6,
    pong: 5,
  )
  let gone = process.monitor(connection)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  let _reason = ask_support.ended(gone)
  event_wait.until("the scope noticed the end by itself", fn() {
    registry.find_named(scope, "6") == Error(Nil)
  })
  ask_support.stop(server)
}

pub fn a_tell_to_a_zone_channel_is_delivered_with_no_watch_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("serial")
  let lines = process.new_subject()
  let delivered = process.new_subject()
  let server =
    start_telling(
      locate: fn(_address) { Error(Nil) },
      deliver: fn(address, _request) {
        process.send(delivered, address)
        Ok(Nil)
      },
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  // Only this test's connection is read: another test's connection or Ranch
  // listener logging at the same time is no line of this one.
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  command_then_pong(
    client:,
    letter: signalling_rule.tell_zone_command,
    n: 9,
    pong: 1,
  )
  assert mailbox_support.drain(delivered)
    == [
      step.ZoneChannel(
        map: map_id.MapId(world_id: 1, instance: 0),
        incarnation: 1,
        top_zone_id: 9,
      ),
    ]
    as "the tell reached the settings' deliver by the zone channel's address, with no watch opened"
  ask_support.stop(server)
  log_capture.stop(capture)
  assert list.filter(mailbox_support.drain(lines), fn(line) {
      line.0 == "warning" || line.0 == "error"
    })
    == []
    as "a tell to a zone channel needs no watch and warns of none"
}

pub fn a_tell_through_a_watch_goes_through_that_watchs_target_only_and_one_through_a_watch_that_found_none_logs_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("serial")
  let lines = process.new_subject()
  let lookups = process.new_subject()
  let told = process.new_subject()
  let found =
    counting_lookup(sessions: ask_support.idle_process(), lookups:, told:)
  let server =
    start_telling(
      locate: fn(address) {
        case address {
          step.CharacterNamed("held") -> found(address)
          step.CharacterNamed(..)
          | step.Sessions
          | step.HandOff
          | step.Store
          | step.Maps
          | step.Map(..)
          | step.Creature(..)
          | step.ZoneChannel(..)
          | step.Connection(..) -> Error(Nil)
        }
      },
      deliver: fn(_address, _request) { Error(Nil) },
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  // Only this test's connection is read: another test's connection or Ranch
  // listener logging at the same time is no line of this one.
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  // Watch 1 is on Sessions, which this lookup holds no process for, so it found
  // none; the tell through it is dropped without a line.
  ask_support.command(
    client:,
    letter: signalling_rule.watch_command,
    n: 1,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.watch_ended, 1)
    as "a watch of a target no process holds ends"
  command_then_pong(
    client:,
    letter: signalling_rule.tell_watched_command,
    n: 1,
    pong: 2,
  )
  assert mailbox_support.drain(told) == []
    as "the watch that found no process has no way to tell, so the tell goes nowhere"
  ask_support.stop(server)
  log_capture.stop(capture)
  assert list.filter(mailbox_support.drain(lines), fn(line) {
      line.0 == "warning" || line.0 == "error"
    })
    == []
    as "a tell through a watch that found none is no warning: an offline whisper's target ends its watch instead"
}

pub fn a_tell_through_a_watch_reaches_the_process_its_own_watch_found_and_not_another_watchs_test() -> Nil {
  use <- owned_test.run(30_000)
  let lookups = process.new_subject()
  let told = process.new_subject()
  let server =
    start_telling(
      locate: counting_lookup(
        sessions: ask_support.idle_process(),
        lookups:,
        told:,
      ),
      deliver: fn(_address, _request) { Error(Nil) },
    )
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  command_then_pong(
    client:,
    letter: signalling_rule.watch_command,
    n: 1,
    pong: 1,
  )
  command_then_pong(
    client:,
    letter: signalling_rule.watch_command,
    n: 2,
    pong: 2,
  )
  let assert [first, second] = mailbox_support.drain(lookups)
    as "each watch resolved its target once"
  command_then_pong(
    client:,
    letter: signalling_rule.tell_watched_command,
    n: 2,
    pong: 3,
  )
  command_then_pong(
    client:,
    letter: signalling_rule.tell_watched_command,
    n: 1,
    pong: 4,
  )
  assert mailbox_support.drain(told) == [second, first]
    as "each tell went through the way its own watch found, whichever watch was opened first"
  ask_support.stop(server)
}
