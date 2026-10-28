//// What reaches a connection shell from other processes, and the effects that
//// name them, proven on the signalling rule. Expected values come from these
//// places.
//// - The shell's contract in the doc comment of `genesis_prime/connection/shell`:
////   a connection joins the registry as it is accepted; a message delivered to
////   it reaches the rule as `Woken`; a watch's end comes back once as
////   `WatchEnded` with the watch's id, an address no process holds comes back
////   the same way, an unwatched watch's end does not come back, and an id
////   already open ends the connection with an error log; a timer fires once as
////   `TimerFired` and a cancelled one never does.
//// - OTP's `erlang:send_after` and `erlang:cancel_timer`: a message already sent
////   when the timer is cancelled stays in the mailbox, which is the reason the
////   shell flushes it.
//// Every wait is for bytes the server writes, with a deadline a passing test
//// never reaches.

import ask_support
import genesis_prime/connection/registry
import genesis_prime/step.{type Address, ConnectionId, Sessions, TimerId}
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid}
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import log_capture
import mug
import owned_test
import signalling_rule

/// One record the signalling rule wrote.
type Record {
  Record(letter: Int, number: Int)
}

/// A timer the shell started: the reference `erlang:send_after` returned.
type Timer

@external(erlang, "connection_shell_ffi", "start_timer")
fn start_timer(timer: step.TimerId, after_ms: Int) -> Timer

@external(erlang, "connection_shell_ffi", "cancel_timer")
fn cancel_timer(timer: step.TimerId, started: Timer) -> Nil

@external(erlang, "erlang", "process_info")
fn process_info(pid: Pid, item: Atom) -> #(Atom, Int)

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

fn command(
  client client: mug.Socket,
  letter letter: Int,
  n n: Int,
  milliseconds milliseconds: Int,
) -> Nil {
  let assert Ok(Nil) = mug.send(client, <<letter, n, milliseconds:16>>)
    as "the command was sent"
  Nil
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
  command(client:, letter: signalling_rule.watch_command, n: 1, milliseconds: 0)
  command(client:, letter: signalling_rule.pong_command, n: 5, milliseconds: 0)
  assert read_record(client) == Record(signalling_rule.pong, 5)
    as "the watch is open and the target runs, so nothing has ended"
  let ended = process.monitor(sessions)
  process.kill(sessions)
  let _reason = ask_support.ended(ended)
  assert read_record(client) == Record(signalling_rule.watch_ended, 1)
    as "the target's end reached the rule as WatchEnded(WatchId(1))"
  command(client:, letter: signalling_rule.pong_command, n: 6, milliseconds: 0)
  assert read_record(client) == Record(signalling_rule.pong, 6)
    as "the end came once"
  ask_support.stop(server)
}

pub fn a_watch_on_an_address_no_process_holds_comes_back_as_watch_ended_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: a_sessions())
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  command(
    client:,
    letter: signalling_rule.watch_absent_command,
    n: 2,
    milliseconds: 0,
  )
  assert read_record(client) == Record(signalling_rule.watch_ended, 2)
    as "no process holds Store's address, so the watch ends at once"
  ask_support.stop(server)
}

pub fn an_unwatch_drops_the_watch_so_the_targets_end_gives_no_watch_ended_test() -> Nil {
  use <- owned_test.run(30_000)
  let sessions = a_sessions()
  let server = start(registry: None, sessions:)
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  command(client:, letter: signalling_rule.watch_command, n: 3, milliseconds: 0)
  command(
    client:,
    letter: signalling_rule.unwatch_command,
    n: 3,
    milliseconds: 0,
  )
  command(client:, letter: signalling_rule.pong_command, n: 1, milliseconds: 0)
  assert read_record(client) == Record(signalling_rule.pong, 1)
  let ended = process.monitor(sessions)
  process.kill(sessions)
  let _reason = ask_support.ended(ended)
  command(client:, letter: signalling_rule.pong_command, n: 2, milliseconds: 0)
  assert read_record(client) == Record(signalling_rule.pong, 2)
    as "the next record is the pong: the target's end sent the rule nothing, since a DOWN waiting in the mailbox comes before the client's bytes"
  ask_support.stop(server)
}

pub fn a_watch_id_already_open_ends_the_connection_with_an_error_log_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: a_sessions())
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
  let logged = process.new_subject()
  let capture = log_capture.start(from: connection, into: logged)
  let gone = process.monitor(connection)
  command(client:, letter: signalling_rule.watch_command, n: 4, milliseconds: 0)
  command(client:, letter: signalling_rule.watch_command, n: 4, milliseconds: 0)
  let assert process.Abnormal(_) = ask_support.ended(gone)
    as "the shell ended the connection abnormally"
  let assert Ok(#("error", text)) =
    process.receive(logged, within: ask_support.event_wait_ms)
    as "the first thing logged is an error"
  assert string.contains(text, "already open")
    as "the error says the watch's id is already open"
  log_capture.stop(capture)
  ask_support.stop(server)
}

pub fn a_timer_fires_once_as_timer_fired_with_its_id_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: a_sessions())
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  command(
    client:,
    letter: signalling_rule.timer_command,
    n: 1,
    milliseconds: 20,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 1)
    as "the timer fired as TimerFired(TimerId(1))"
  command(client:, letter: signalling_rule.pong_command, n: 2, milliseconds: 0)
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
  command(
    client:,
    letter: signalling_rule.timer_command,
    n: 1,
    milliseconds: 30,
  )
  command(
    client:,
    letter: signalling_rule.timer_command,
    n: 2,
    milliseconds: 90,
  )
  command(
    client:,
    letter: signalling_rule.cancel_command,
    n: 1,
    milliseconds: 0,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 2)
    as "timer 2 fired and timer 1, due earlier, did not"
  ask_support.stop(server)
}

pub fn cancelling_a_timer_that_already_fired_flushes_its_message_from_the_mailbox_test() -> Nil {
  use <- owned_test.run(30_000)
  let timer = start_timer(TimerId(1), 0)
  wait_for_message()
  assert queued() == 1 as "the timer fired, and its message waits"
  cancel_timer(TimerId(1), timer)
  assert queued() == 0
    as "the cancel found no timer to stop and flushed the message, so it never reaches the rule"
}

/// How many messages wait in this process's mailbox.
fn queued() -> Int {
  process_info(process.self(), atom.create("message_queue_len")).1
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
