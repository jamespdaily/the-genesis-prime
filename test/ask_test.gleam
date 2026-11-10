//// The connection shell's asks, proven on the asking rule and a gate service.
//// Expected values come from these places.
//// - The shell's contract in the doc comment of `genesis_prime/connection/
////   shell` ("An ask" and "The directory's own wait"), as approved on the
////   login processes card: the outcomes, their order and when each comes.
//// - The asking rule's records in the doc comment of `asking_rule`.
//// Every wait is for an event, with a deadline a passing test never reaches,
//// except where the test is about a deadline passing: those asks wait 300
//// milliseconds.

import ask_support
import asking_rule
import gate_rule
import genesis_prime/connection/script
import genesis_prime/service
import genesis_prime/step.{ConnectionId, Now}
import genesis_prime/wire_recording/recorder.{type WireRecorder}
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry as world_map_registry
import gleam/erlang/process
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import log_capture
import mailbox_support
import mug
import open_wait
import owned_test
import recording_support
import socket_read
import wire_replay_support

/// How long an ask whose deadline is meant to pass waits, in milliseconds.
const short = 300

pub fn an_answer_before_the_deadline_comes_back_after_the_steps_effects_and_the_bytes_sent_during_the_ask_come_after_it_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  // The directory, which runs in the connection's process, reports that it was
  // called and waits for the test to say it has read the step's write. A shell
  // that made the ask before carrying out the step's effects would block here
  // before writing, and the test's read of the write would time out.
  let calls = process.new_subject()
  let reaching_the_gate =
    ask_support.directory(gate:, store: None, sent: ask_support.unreported)
  let server =
    ask_support.start(
      rule: asking_rule.rule(),
      directory: fn(request, deadline_ms, reply) {
        let acknowledged = process.new_subject()
        process.send(calls, #(acknowledged, deadline_ms))
        let Nil =
          open_wait.received(
            from: acknowledged,
            what: "the test to read the step's write before the directory goes on",
          )
        reaching_the_gate(request, deadline_ms, reply)
      },
      shutdown_ms: 1000,
      with: fn(builder) {
        supervisor.add(builder, ask_support.gate(name: gate, shutdown_ms: 1000))
      },
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.await_command,
    1,
    wait_ms: ask_support.patient,
  )
  let #(acknowledged, given_deadline) =
    open_wait.received(from: calls, what: "the shell's ask to the directory")
  let asked = ask_support.read_record(client)
  assert given_deadline == asked.milliseconds
    as "the directory is given the ask's own deadline, so a lookup on the way to the process (Maps') ends by it"
  assert asked.letter == asking_rule.asked && asked.ask == 1
    as "the step's own write was carried out before the ask was made"
  process.send(acknowledged, Nil)
  // The client sends while the ask is open; the shell reads it only after the
  // outcome, since the socket is not read again while the shell waits.
  ask_support.command(client, asking_rule.ping_command, 7, wait_ms: 0)
  let _waiting = ask_support.open_key(gate, 1)
  let outcome = ask_support.read_record(client)
  assert outcome.letter == asking_rule.outcome
    && outcome.ask == 1
    && outcome.code == asking_rule.code_opened
    && outcome.extra == 1
    as "the gate's answer comes back as the outcome of ask 1"
  assert outcome.milliseconds < asked.milliseconds
    as "the answer came before the ask's deadline"
  assert ask_support.read_pong(client) == <<0x70, 7>>
    as "the byte sent during the ask is read after the outcome"
  ask_support.stop(server)
}

pub fn the_directory_is_given_the_ask_counted_from_the_nodes_time_the_script_gave_for_the_input_test() -> Nil {
  use <- owned_test.run(30_000)
  // The script's clock and the node's time are two numbers of two clocks, as
  // in a replay: the input's `Now` is a recording's (-1000) and the node's time
  // for it is 50 000. An ask that allows 1000 ms from its input is due 1000 ms
  // after the node's time, whatever the `Now` says, and the one value is what
  // the directory is given: a shell that read the node's clock once more
  // would give a deadline of its own reading.
  let assert Ok(issued) = script.operating_system() as "the server's script"
  let scripts = fn() {
    Ok(
      script.Issued(
        ..issued,
        script: script.Script(
          ..issued.script,
          clock: fn(_taking) { Now(monotonic_ms: -1000, filetime: 5) },
          node_monotonic_ms: fn(_now) { 50_000 },
        ),
      ),
    )
  }
  let given = process.new_subject()
  let server =
    ask_support.start_scripted(
      rule: asking_rule.rule(),
      directory: fn(_request, deadline_ms, _reply) {
        process.send(given, deadline_ms)
        Error(Nil)
      },
      shutdown_ms: 1000,
      wire_recorder: None,
      scripts:,
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  ask_support.command(client, asking_rule.echo_command, 1, wait_ms: 1000)
  assert open_wait.received(
      from: given,
      what: "the ask's input time the node gave",
    )
    == 51_000
    as "the node's time for the input (50 000) and the 1000 ms the ask allows"
  ask_support.stop(server)
}

pub fn an_ask_to_an_address_with_no_running_process_gives_not_running_at_once_and_sends_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let sent = process.new_subject()
  let server =
    ask_support.start(
      rule: asking_rule.rule(),
      directory: ask_support.directory(gate:, store: None, sent: fn(reached) {
        process.send(sent, reached)
      }),
      shutdown_ms: 1000,
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.echo_command,
    1,
    wait_ms: ask_support.patient,
  )
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_not_running
    as "no process holds the gate's name"
  assert outcome.milliseconds < asked.milliseconds
    as "at once, not at the ask's deadline"
  assert process.named(gate) == Error(Nil) as "nothing runs at the address"
  // Absence check: the limit is how long this watches for a message that must
  // not come, here a look at the mailbox now.
  assert process.receive(sent, within: 0) == Error(Nil)
    as "the directory reached no process, so nothing was sent"
  ask_support.stop(server)
}

pub fn a_target_that_never_answers_gives_no_answer_in_time_and_not_before_the_deadline_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000)
  let client = ask_support.connect(server)
  ask_support.command(client, asking_rule.ignore_command, 0, wait_ms: short)
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.letter == asking_rule.outcome
    && outcome.code == asking_rule.code_no_answer_in_time
    as "the gate took the ask and never answered"
  assert outcome.milliseconds >= asked.milliseconds
    as "not before the ask's deadline"
  ask_support.stop(server)
}

pub fn a_target_that_ends_before_answering_gives_ended_before_answer_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.crash_command,
    0,
    wait_ms: ask_support.patient,
  )
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_ended_before_answer
    as "the gate crashed on the ask"
  assert outcome.milliseconds < asked.milliseconds
    as "when the target ended, not at the ask's deadline"
  ask_support.stop(server)
}

pub fn an_answer_after_the_deadline_gives_the_rule_no_input_and_is_never_taken_for_a_newer_asks_answer_test() -> Nil {
  use <- owned_test.run(30_000)
  // Connection shell only: the service shell makes no ask (its request type
  // has no values), so no answer can come late to it.
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000)
  let client = ask_support.connect(server)
  ask_support.command(client, asking_rule.await_command, 1, wait_ms: short)
  let _asked_first = ask_support.read_record(client)
  let first = ask_support.read_record(client)
  assert first.ask == 1 && first.code == asking_rule.code_no_answer_in_time
    as "ask 1 timed out"
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let assert Ok(gate_pid) = process.named(gate) as "the gate runs"
  assert list.contains(mailbox_support.monitored(connection), gate_pid)
    as "the shell keeps its monitor of the gate until the late answer or the gate's end"
  let lines = process.new_subject()
  let capture = log_capture.start(from: connection, into: lines)
  // Opening key 1 makes the gate answer ask 1, which is already over, and then
  // answer this ask, 2, in that order: the older answer is in the mailbox first.
  ask_support.command(
    client,
    asking_rule.open_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked_second = ask_support.read_record(client)
  let second = ask_support.read_record(client)
  assert second.ask == 2
    && second.code == asking_rule.code_echoed
    && second.extra == 1
    as "ask 2 got the gate's answer to ask 2, not the late answer to ask 1"
  // The late answer to ask 1 reached the shell before ask 2's, so it was
  // dropped before this ping was read: the next record is the pong.
  ask_support.command(client, asking_rule.ping_command, 9, wait_ms: 0)
  assert ask_support.read_pong(client) == <<0x70, 9>>
    as "the answer to ask 1 gave the rule no input, so no record comes before the pong"
  // Not the mailbox's length: the shell's own write of the pong leaves the
  // port's reply to it in the mailbox until the shell next runs.
  assert mailbox_support.tagged_by_reference(connection) == 0
    as {
      "the late answer was taken: no answer waits in the shell's mailbox; waiting: "
      <> mailbox_support.waiting(connection)
    }
  assert !list.contains(mailbox_support.monitored(connection), gate_pid)
    as "and dropped: the shell holds no monitor of the gate for it"
  log_capture.stop(capture)
  // Absence check: the limit is how long this watches for a message that must
  // not come, here a look at the mailbox now.
  assert process.receive(lines, 0) == Error(Nil)
    as "the late answer logged nothing"
  ask_support.stop(server)
}

pub fn a_replied_ask_leaves_no_monitor_on_the_target_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.await_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let assert Ok(gate_pid) = process.named(gate) as "the gate runs"
  assert list.contains(mailbox_support.monitored(connection), gate_pid)
    as "while the shell waits it monitors the gate"
  let _waiting = ask_support.open_key(gate, 1)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_opened
    as "the gate's answer came back"
  assert !list.contains(mailbox_support.monitored(connection), gate_pid)
    as "and the answered ask left no monitor on the gate, which it would keep for as long as the gate runs"
  ask_support.stop(server)
}

pub fn a_stop_during_an_ask_ends_the_wait_at_once_and_stopping_counts_from_the_stops_arrival_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let shutdown_ms = 2000
  let server = start_with(gate:, shutdown_ms:)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.await_command,
    1,
    wait_ms: ask_support.patient,
  )
  let asked = ask_support.read_record(client)
  let before_stop = ask_support.monotonic_ms()
  let stopped = ask_support.begin_stop_tree(server.supervisor)
  let outcome = ask_support.read_record(client)
  let stopping = ask_support.read_record(client)
  let after_stopping = ask_support.monotonic_ms()
  assert outcome.ask == 1 && outcome.code == asking_rule.code_stopped_waiting
    as "the stop ended the wait"
  assert outcome.milliseconds < asked.milliseconds
    as "at once, not at the ask's deadline"
  assert stopping.letter == asking_rule.stopping
    as "Stopping is the input after the outcome"
  // The connection settings' send deadline is 300 ms (ask_support.start).
  assert stopping.milliseconds >= before_stop + shutdown_ms - 300
    && stopping.milliseconds <= after_stopping + shutdown_ms - 300
    as "the deadline is the stop's arrival plus the shutdown time less the send deadline"
  assert ask_support.ended(
      watched: stopped,
      what: "the server's tree to end after its stop",
    )
    == ask_support.shutdown()
    as "the tree stopped when the rule had stopped"
}

pub fn a_recorded_session_with_asks_replays_to_the_same_bytes_with_no_other_process_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- recording_support.in_folder
  let gate = process.new_name("gate")
  let server =
    start_recorded(
      gate:,
      shutdown_ms: 1000,
      wire_recorder: recording_support.wire_recorder(folder),
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.echo_command,
    5,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let _echoed = ask_support.read_record(client)
  ask_support.command(
    client,
    asking_rule.open_command,
    1,
    wait_ms: ask_support.patient,
  )
  let _asked = ask_support.read_record(client)
  let _opened = ask_support.read_record(client)
  ask_support.command(client, asking_rule.ping_command, 3, wait_ms: 0)
  let _pong = ask_support.read_pong(client)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  let assert Ok(Nil) = mug.shutdown(client) as "the client closed"
  let _reason =
    ask_support.ended(
      watched: watched,
      what: "the connection to end after the client closed",
    )
  ask_support.stop(server)
  assert process.named(gate) == Error(Nil)
    as "no other process runs: the gate and the listener are gone"
  // The replay runs a gate of its own, on the answers it gives again.
  let replayed_gate = process.new_name("replayed_gate")
  wire_replay_support.empty_fixture(folder)
  assert wire_replay_support.run_with(
      folder:,
      rule: asking_rule.rule(),
      directory: ask_support.directory(
        gate: replayed_gate,
        store: None,
        sent: ask_support.unreported,
      ),
      with: fn(builder) {
        supervisor.add(
          builder,
          ask_support.gate(name: replayed_gate, shutdown_ms: 1000),
        )
      },
    )
    == Ok(Nil)
    as "the session the shell recorded, two asks and a ping, writes the same bytes again"
}

pub fn a_connection_step_of_stop_then_write_still_writes_the_bytes_before_the_socket_closes_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.stop_then_write_command,
    4,
    wait_ms: 0,
  )
  assert ask_support.read_pong(client) == <<0x71, 4>>
    as "the write after Stop reached the client"
  assert socket_read.receive(
      socket: client,
      limit: socket_read.Open,
      what: "the socket to close",
    )
    == Error(mug.Closed)
    as "and the socket closed after it"
  ask_support.stop(server)
}

pub fn the_writes_of_a_step_before_its_stop_leave_in_the_order_the_rule_gave_and_then_the_socket_closes_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.pongs_then_stop_command,
    4,
    wait_ms: 0,
  )
  assert [ask_support.read_pong(client), ask_support.read_pong(client)]
    == [<<0x70, 4>>, <<0x71, 4>>]
    as "the asking rule's contract: a step's effects are carried out in the order it gave them, the two writes first and Stop last"
  assert socket_read.receive(
      socket: client,
      limit: socket_read.Open,
      what: "the socket to close",
    )
    == Error(mug.Closed)
    as "and the socket closed after them"
  ask_support.stop(server)
}

pub fn the_write_of_a_step_before_its_ask_leaves_before_the_ask_is_made_test() -> Nil {
  use <- owned_test.run(30_000)
  let gate = process.new_name("gate")
  let server = start_with(gate:, shutdown_ms: 1000)
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.pong_then_ask_command,
    9,
    wait_ms: ask_support.patient,
  )
  assert ask_support.read_pong(client) == <<0x70, 9>>
    as "the asking rule's contract: the write the step gave before its ask leaves first"
  let asked = ask_support.read_record(client)
  assert asked.letter == asking_rule.asked && asked.ask == 1
    as "the ask's own record is the step's last write: the ask is made after the step's effects"
  ask_support.stop(server)
}

// ---- helpers ----

fn start_with(
  gate gate: process.Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
) -> ask_support.Server {
  ask_support.start(
    rule: asking_rule.rule(),
    directory: ask_support.directory(
      gate:,
      store: None,
      sent: ask_support.unreported,
    ),
    shutdown_ms:,
    with: fn(builder) {
      supervisor.add(builder, ask_support.gate(name: gate, shutdown_ms: 1000))
    },
  )
}

/// As `start_with`, with the connections recorded on the wire.
fn start_recorded(
  gate gate: process.Name(service.Call(gate_rule.Message, gate_rule.Answer)),
  shutdown_ms shutdown_ms: Int,
  wire_recorder wire_recorder: WireRecorder,
) -> ask_support.Server {
  ask_support.start_scripted(
    rule: asking_rule.rule(),
    directory: ask_support.directory(
      gate:,
      store: None,
      sent: ask_support.unreported,
    ),
    shutdown_ms:,
    wire_recorder: Some(wire_recorder),
    scripts: script.operating_system,
    registry: None,
    locate: fn(_address) { Error(Nil) },
    with: fn(builder) {
      supervisor.add(builder, ask_support.gate(name: gate, shutdown_ms: 1000))
    },
  )
}

// ---- a leave's ask of a map's run ----

pub fn a_directory_that_got_no_reply_in_time_gives_no_answer_in_time_at_once_and_sends_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  let server =
    ask_support.start(
      rule: asking_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) {
        Ok(service.NoReplyInTime)
      },
      shutdown_ms: 1000,
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.echo_command,
    1,
    wait_ms: ask_support.patient,
  )
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.letter == asking_rule.outcome
    && outcome.code == asking_rule.code_no_answer_in_time
    as "the directory's lookup got no reply by the deadline: the rule is told no answer came, never that the process is not running"
  assert outcome.milliseconds < asked.milliseconds
    as "at once: the deadline has passed, so there is nothing to wait for"
  ask_support.stop(server)
}

/// A server whose directory asks the run of a map through `maps`, as the
/// server's directory does for a leave.
fn start_asking_a_run(
  maps maps: process.Name(world_map_registry.Message),
) -> ask_support.Server {
  ask_support.start(
    rule: asking_rule.rule(),
    directory: fn(_request, deadline_ms, _reply) {
      world_map_registry.ask_run(
        maps:,
        map: MapId(world_id: 3460, instance: 0),
        incarnation: 1,
        message: map.Leave(connection: ConnectionId(1)),
        deadline_ms:,
        reply: fn(_answer) { Nil },
      )
    },
    shutdown_ms: 1000,
    with: fn(builder) { builder },
  )
}

pub fn a_leave_whose_find_maps_never_answers_because_it_exited_after_the_find_gives_no_answer_in_time_test() -> Nil {
  use <- owned_test.run(30_000)
  // A stand-in for Maps that takes the find and ends without answering: the
  // find is sent, so Maps was running, and gone by the deadline.
  let maps = process.new_name("stand_in_maps")
  let registered = process.new_subject()
  let _stand_in =
    process.spawn_unlinked(fn() {
      let assert Ok(Nil) = process.register(process.self(), maps)
        as "the stand-in holds Maps' name"
      process.send(registered, Nil)
      let anything =
        process.new_selector() |> process.select_other(fn(message) { message })
      let _find = process.selector_receive_forever(anything)
      Nil
    })
  let Nil =
    open_wait.received(from: registered, what: "the stand-in to register")
  let server = start_asking_a_run(maps:)
  let client = ask_support.connect(server)
  ask_support.command(client, asking_rule.echo_command, 1, wait_ms: short)
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_no_answer_in_time
    as "no reply from Maps: a live map may still hold the player, so the rule is told no answer came"
  assert outcome.milliseconds >= asked.milliseconds
    as "not before the ask's deadline"
  ask_support.stop(server)
}

pub fn a_leave_when_maps_is_not_running_gives_not_running_at_once_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start_asking_a_run(maps: process.new_name("no_maps"))
  let client = ask_support.connect(server)
  ask_support.command(
    client,
    asking_rule.echo_command,
    1,
    wait_ms: ask_support.patient,
  )
  let asked = ask_support.read_record(client)
  let outcome = ask_support.read_record(client)
  assert outcome.code == asking_rule.code_not_running
    as "no process holds Maps' name, so no map runs and no player is held"
  assert outcome.milliseconds < asked.milliseconds
  ask_support.stop(server)
}
