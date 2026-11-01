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
import genesis_prime/service
import genesis_prime/step.{type Address, ConnectionId, Sessions}
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

/// One record the signalling rule wrote.
type Record {
  Record(letter: Int, number: Int)
}

fn start(
  registry registry: option.Option(registry.Registry),
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
  registry registry: option.Option(registry.Registry),
  sessions sessions: Result(Pid, Nil),
  directory directory: fn(Nil, Int, fn(Nil) -> Nil) -> Result(service.Sent, Nil),
) -> ask_support.Server {
  ask_support.start_joined(
    rule: signalling_rule.rule(),
    directory:,
    shutdown_ms: 1000,
    recorder: None,
    registry:,
    locate: fn(address: Address) {
      case address {
        Sessions -> sessions
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
  let server = start(registry: Some(scope), sessions: Ok(a_sessions()))
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
  let server = start(registry: Some(scope), sessions: Ok(a_sessions()))
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
  let server = start(registry: None, sessions: Ok(a_sessions()))
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
  let server = start(registry: None, sessions: Ok(a_sessions()))
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  // Timer 2 runs first: it is the witness that time passed, and a cancel that
  // ignores its timer's id would take it down with timer 1. Timer 1 is started
  // and cancelled in one step, so whether its 0 ms timeout was sent before the
  // cancel does not depend on how fast the machine is: the cancel stops it or
  // flushes it.
  ask_support.command(
    client:,
    letter: signalling_rule.timer_command,
    n: 2,
    wait_ms: 100,
  )
  ask_support.command(
    client:,
    letter: signalling_rule.start_then_cancel_command,
    n: 1,
    wait_ms: 0,
  )
  assert read_record(client) == Record(signalling_rule.timer_fired, 2)
    as "timer 2 fired and timer 1, due earlier, never reached the rule"
  ask_support.stop(server)
}

pub fn a_timer_cancelled_and_started_again_in_one_step_fires_only_the_second_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: Ok(a_sessions()))
  let client = ask_support.connect(server)
  let _id = accepted_id(client)
  // One read, one step: timer 1 starts with 0 ms, is cancelled and starts
  // again with 100 ms. The first timeout, which `erlang:cancel_timer` cannot
  // recall once it is in flight, is no longer the timer's own, and timer 2,
  // started in the same step, fires after the first's timeout is due.
  let step_bytes = <<
    signalling_rule.timer_command, 1, 0:16, signalling_rule.cancel_command, 1,
    0:16, signalling_rule.timer_command, 1, 100:16,
    signalling_rule.timer_command, 2, 200:16,
  >>
  let assert Ok(Nil) = mug.send(client, step_bytes) as "the step was sent"
  assert read_record(client) == Record(signalling_rule.timer_fired, 1)
    as "timer 1 fired once, from its second start"
  assert read_record(client) == Record(signalling_rule.timer_fired, 2)
    as "and the first start's timeout reached the rule as nothing: the next record is timer 2's"
  ask_support.stop(server)
}

pub fn a_timer_that_fired_during_an_ask_and_is_cancelled_by_its_outcome_never_reaches_the_rule_test() -> Nil {
  use <- owned_test.run(30_000)
  let replies = process.new_subject()
  let server =
    start_asking(
      registry: None,
      sessions: Ok(a_sessions()),
      directory: asked_through(replies),
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
  let sessions = a_sessions()
  let replies = process.new_subject()
  let server =
    start_asking(
      registry: Some(scope),
      sessions: Ok(sessions),
      directory: asked_through(replies),
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

/// A directory that hands each ask's reply to `replies` and says it went to a
/// process that runs and never answers by itself.
fn asked_through(
  replies: process.Subject(fn(Nil) -> Nil),
) -> fn(Nil, Int, fn(Nil) -> Nil) -> Result(service.Sent, Nil) {
  let target = process.spawn_unlinked(process.sleep_forever)
  fn(_request, _deadline_ms, reply) {
    process.send(replies, reply)
    Ok(service.ToService(pid: target))
  }
}

pub fn a_message_no_selector_takes_is_dropped_and_logged_by_its_kind_with_the_connection_named_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(registry: None, sessions: Ok(a_sessions()))
  let client = ask_support.connect(server)
  let id = accepted_id(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let lines = process.new_subject()
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  let _sent =
    send_raw(
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

@external(erlang, "erlang", "send")
fn send_raw(to: Pid, message: #(atom.Atom, BitArray)) -> #(atom.Atom, BitArray)
