//// What reaches a connection shell from other processes, and the effects that
//// name them, proven on the signalling rule. Expected values come from these
//// places.
//// - The shell's contract in the doc comment of `genesis_prime/connection/shell`:
////   a connection joins the registry as it is accepted; a message delivered to
////   it reaches the rule as `Woken`; a watch's end comes back once as
////   `WatchEnded` with the watch's id (the watches themselves are tested in
////   `watch_test`); a timer fires once as `TimerFired`, a cancelled one never
////   does, and a timeout whose reference is not the timer's own is discarded.
//// - OTP's `erlang:send_after` and `erlang:cancel_timer`: a message already sent
////   when the timer is cancelled stays in the mailbox, which is the reason the
////   shell flushes it.
//// Every wait is for bytes the server writes, with a deadline a passing test
//// never reaches.

import ask_support
import genesis_prime/connection/registry
import genesis_prime/step.{type Address, ConnectionId, Sessions, TimerId}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/erlang/reference.{type Reference}
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import mug
import owned_test
import signalling_rule
import socket_watch

/// One record the signalling rule wrote.
type Record {
  Record(letter: Int, number: Int)
}

/// A timer the shell started: what `erlang:send_after` returned.
type Timer

@external(erlang, "connection_shell_ffi", "start_timer")
fn start_timer(timer: step.TimerId, after_ms: Int) -> #(Timer, Reference)

@external(erlang, "connection_shell_ffi", "cancel_timer")
fn cancel_timer(timer: step.TimerId, started: Timer, of: Reference) -> Nil

@external(erlang, "erlang", "send")
fn send_timeout(to: Pid, message: #(Atom, step.TimerId, Reference)) -> Dynamic

fn start(
  registry registry: option.Option(registry.Registry),
  sessions sessions: Pid,
) -> ask_support.Server {
  ask_support.start_joined(
    rule: signalling_rule.rule(),
    directory: fn(_request, _reply) { Error(Nil) },
    shutdown_ms: 1000,
    recorder: None,
    registry:,
    locate: fn(address: Address) {
      case address {
        Sessions -> Ok(sessions)
        step.HandOff
        | step.Store
        | step.Maps
        | step.Map(..)
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

/// A process the rule's watches name as Sessions, which a test ends.
fn a_sessions() -> Pid {
  process.spawn_unlinked(process.sleep_forever)
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
  let server = start(registry: Some(scope), sessions: a_sessions())
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
  let server = start(registry: Some(scope), sessions: a_sessions())
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
  let gone = process.monitor(connection)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  let _reason = ask_support.ended(gone)
  assert left(
    scope:,
    connection: ConnectionId(id),
    within_ms: ask_support.event_wait_ms,
  )
    as "the scope noticed the end by itself, so no process finds the id"
  assert registry.deliver(scope, ConnectionId(id), 1) == Error(Nil)
    as "nothing is sent to a connection that is gone"
  ask_support.stop(server)
}

/// Waits until the scope holds no process for the connection.
fn left(
  scope scope: registry.Registry,
  connection connection: step.ConnectionId,
  within_ms within_ms: Int,
) -> Bool {
  case registry.find(scope, connection), within_ms > 0 {
    Error(Nil), _ -> True
    Ok(_), True -> {
      process.sleep(1)
      left(scope:, connection:, within_ms: within_ms - 1)
    }
    Ok(_), False -> False
  }
}

pub fn a_watched_process_that_ends_comes_back_once_as_watch_ended_with_the_watchs_id_test() -> Nil {
  use <- owned_test.run(30_000)
  let sessions = a_sessions()
  let server = start(registry: None, sessions:)
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

pub fn a_timer_fires_once_as_timer_fired_with_its_id_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: a_sessions())
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

pub fn a_cancelled_timer_never_fires_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: a_sessions())
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  // Timer 1 would fire first; timer 2 is the witness that time passed.
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 1,
    wait_ms: 30,
  )
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 2,
    wait_ms: 90,
  )
  ask_support.command(
    client:,
    letter: signalling_rule.cancel_command,
    n: 1,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 2)
    as "timer 2 fired and timer 1, due earlier, did not"
  ask_support.stop(server)
}

pub fn cancelling_a_timer_that_already_fired_flushes_its_message_from_the_mailbox_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(timer, reference) = start_timer(TimerId(1), 0)
  wait_for_message()
  assert queued() == 1 as "the timer fired, and its message waits"
  cancel_timer(TimerId(1), timer, reference)
  assert queued() == 0
    as "the cancel found no timer to stop and flushed the message, so it never reaches the rule"
}

pub fn a_timeout_of_a_cancelled_or_replaced_timer_is_discarded_by_its_reference_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: a_sessions())
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
  // Timer 1 is cancelled and started again, so its first timeout, which
  // `erlang:cancel_timer` cannot recall once it is in flight, carries a
  // reference that is no longer the timer's own.
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 1,
    wait_ms: 60_000,
  )
  ask_support.command(
    client:,
    letter: signalling_rule.cancel_command,
    n: 1,
    wait_ms: 0,
  )
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 1,
    wait_ms: 60_000,
  )
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 4,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 4)
    as "the timers are set"
  let _sent =
    send_timeout(connection, #(timer_fired(), TimerId(1), reference.new()))
  let _sent =
    send_timeout(connection, #(timer_fired(), TimerId(2), reference.new()))
  ask_support.command(
    client:,
    letter: signalling_rule.pong_command,
    n: 5,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.pong, 5)
    as "the stale timeouts, of a running timer's id and of an id no timer holds, reached the rule as nothing, and the connection goes on"
  ask_support.stop(server)
}

fn timer_fired() -> Atom {
  atom.create("timer_fired")
}

/// How many messages wait in this process's mailbox.
fn queued() -> Int {
  socket_watch.mailbox_length(process.self())
}

/// Waits until a message is in the mailbox; a timer of 0 ms fires within a
/// few milliseconds, and a test that never sees one runs past its deadline.
fn wait_for_message() -> Nil {
  case queued() {
    0 -> {
      process.sleep(1)
      wait_for_message()
    }
    _ -> Nil
  }
}
