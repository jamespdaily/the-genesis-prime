//// The connection shell as the actor Ranch starts: how it starts, what it
//// keeps off its heap, what it logs and under whose name, and how it ends.
//// Expected values come from these places.
//// - The shell's contract in the doc comment of `genesis_prime/connection/
////   shell`, as approved on the connection actor card: the start returns
////   before Ranch hands the socket over (Ranch's connection supervisor sends
////   the handshake only after `start_link` returns, so a start that waited for
////   it would serve one connection at a time); a client that is gone before
////   the handshake, or a socket whose options cannot be set, ends the
////   connection normally; a parent that stops before the handshake ends it;
////   waiting messages are kept off the heap; every line the process logs and
////   its crash report carry the connection and the peer; an exit from a
////   process other than the parent is ignored; a normal stop ends the
////   recording and a crash leaves it without `End`.
//// - OTP: `process_flag(message_queue_data, off_heap)` is read back by
////   `process_info(Pid, message_queue_data)`; an exit signal from a process
////   other than the parent reaches a process that traps exits as a message.
//// - Ranch 2.3: `ranch:handshake` exits `{shutdown, _}` when the transport's
////   handshake returns an error.
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import event_wait
import genesis_prime/connection/shell
import genesis_prime/rule_recording
import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/step.{
  type ConnectionInput, type ConnectionRule, type ConnectionStep, Accepted,
  Effects, Log, LogLine, LogWarning, OwnEffect, OwnEvent, PeerClosed, Read,
  ReadFailed, Rule, Stop, Stopping, TimerFired, Woken, Write, WriteFailed,
}
import gleam/erlang/atom
import gleam/erlang/process.{type Name, type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import log_capture
import mug
import owned_test
import recording_support
import simplifile
import unitest

/// What a close can look like to the server.
type HangUp {
  Plain
  Reset
}

/// Where a process keeps its waiting messages.
type QueueData {
  OffHeap
  OnHeap
}

/// A line the logger took: its level, its text and its metadata.
type Line =
  #(String, String, List(#(String, String)))

@external(erlang, "connection_actor_support_ffi", "exports")
fn exports(module: atom.Atom) -> List(#(String, Int))

@external(erlang, "connection_actor_support_ffi", "message_queue_data")
fn message_queue_data(pid: Pid) -> QueueData

@external(erlang, "connection_actor_support_ffi", "hang_up")
fn hang_up(port: Int, kind: HangUp) -> Int

@external(erlang, "connection_actor_support_ffi", "hand_over_to_failing_transport")
fn hand_over_to_failing_transport(pid: Pid, ref: shell.RanchRef) -> Nil

@external(erlang, "connection_actor_support_ffi", "hand_over_closed_socket")
fn hand_over_closed_socket(pid: Pid, ref: shell.RanchRef) -> Nil

@external(erlang, "connection_actor_support_ffi", "atom_text")
fn atom_text(name: Name(Nil)) -> String

@external(erlang, "erlang", "send")
fn send_raw(
  to: Pid,
  message: #(atom.Atom, atom.Atom),
) -> #(atom.Atom, atom.Atom)

@external(erlang, "erlang", "make_ref")
fn new_ranch_ref() -> shell.RanchRef

/// The rule of these tests: writes the byte 1 as its first reply, echoes what
/// it reads, stops when the client leaves or the server stops, writes a line
/// to the log on a read starting with 0xAA, and crashes on one starting with
/// 0xEE.
fn quiet_rule() -> ConnectionRule(Nil, Nil, Nil, Nil, Nil) {
  Rule(name: "quiet_rule", settings: Nil, new: fn(_settings) { Nil }, step:)
}

fn step(
  state: Nil,
  input: ConnectionInput(Nil, Nil),
) -> #(Nil, ConnectionStep(Nil)) {
  case input.event {
    OwnEvent(Accepted(..)) -> #(state, Effects([OwnEffect(Write(<<1>>))]))
    OwnEvent(Read(<<0xEE, _:bits>>)) -> panic as "the planted crash"
    OwnEvent(Read(<<0xAA, _:bits>>)) -> #(
      state,
      Effects([
        Log(LogLine(
          level: LogWarning,
          text: "the planted line",
          about: step.no_one,
        )),
        OwnEffect(Write(<<2>>)),
      ]),
    )
    OwnEvent(Read(bytes:)) -> #(state, Effects([OwnEffect(Write(bytes))]))
    OwnEvent(PeerClosed)
    | OwnEvent(ReadFailed(..))
    | OwnEvent(WriteFailed(..))
    | Stopping(..) -> #(state, Effects([Stop]))
    OwnEvent(Woken(..))
    | OwnEvent(TimerFired(..))
    | OwnEvent(step.Answered(..))
    | step.WatchEnded(..) -> #(state, Effects([]))
  }
}

fn settings(
  recorder: Option(Recorder),
) -> shell.Settings(Nil, Nil, Nil, Nil, Nil) {
  shell.Settings(
    rule: quiet_rule(),
    send_deadline_ms: 300,
    shutdown_ms: 1000,
    recorder:,
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    registry: None,
    locate: fn(_address) { Error(Nil) },
  )
}

fn start(recorder: Option(Recorder)) -> ask_support.Server {
  ask_support.start(
    rule: quiet_rule(),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms: 1000,
    recorder:,
    with: fn(builder) { builder },
  )
}

/// A client that has connected and been greeted, and its connection's process.
fn greeted(server: ask_support.Server) -> #(mug.Socket, Pid) {
  let client = ask_support.connect(server)
  assert ask_support.read_bytes(client, 1) == <<1>> as "the rule's first reply"
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  #(client, connection)
}

/// Every line waiting in the subject.
fn drain(lines: Subject(Line)) -> List(Line) {
  case process.receive(lines, 0) {
    Ok(line) -> [line, ..drain(lines)]
    Error(Nil) -> []
  }
}

fn is_warning_or_error(line: Line) -> Bool {
  line.0 == "warning" || line.0 == "error"
}

fn metadata_of(line: Line, key: String) -> Result(String, Nil) {
  list.key_find(line.2, key)
}

/// Whether a line carries the connection and the client's address.
fn names_connection_and_peer(line: Line) -> Bool {
  case metadata_of(line, "connection"), metadata_of(line, "peer") {
    Ok(connection), Ok(peer) ->
      string.starts_with(connection, "{connection_id,")
      && string.contains(peer, "127.0.0.1")
    Ok(_), Error(Nil) | Error(Nil), Ok(_) | Error(Nil), Error(Nil) -> False
  }
}

// ---- the Erlang file ----

pub fn the_connections_erlang_file_exports_only_ranch_and_socket_calls_test() -> Nil {
  use <- owned_test.run(5000)
  let exported =
    exports(atom.create("connection_shell_ffi"))
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  assert exported
    == [
      #("close", 1),
      #("handshake", 2),
      #("listener_port", 1),
      #("peer", 1),
      #("read_once", 1),
      #("send", 2),
      #("socket_message", 1),
      #("start_link", 3),
      #("start_listener", 4),
      #("suspend_listener", 1),
    ]
    as "Ranch's start callback and listener calls, the socket's calls and the decoder of its messages: no mailbox helper, timer or ask wait"
}

// ---- starting ----

pub fn fifty_clients_that_connect_at_once_each_get_their_first_reply_test() -> Nil {
  use <- owned_test.run(60_000)
  let server = start(None)
  // All fifty are connected before any is read: Ranch's connection supervisor
  // starts the connections one at a time, so a start that waited for the
  // handshake would leave the others with no reply until it gave up.
  let clients =
    list.map(list.repeat(Nil, 50), fn(_) { ask_support.connect(server) })
  list.each(clients, fn(client) {
    assert ask_support.read_bytes(client, 1) == <<1>>
      as "the rule's first reply"
  })
  ask_support.stop(server)
}

pub fn a_burst_of_plain_and_reset_hang_ups_logs_no_warning_or_error_test() -> Nil {
  use <- owned_test.run(60_000)
  let lines = process.new_subject()
  let capture = log_capture.start_all(into: lines)
  let server = start(None)
  let ports =
    list.append(
      list.map(list.repeat(Nil, 100), fn(_) { hang_up(server.port, Plain) }),
      list.map(list.repeat(Nil, 100), fn(_) { hang_up(server.port, Reset) }),
    )
  event_wait.until("every connection ended", fn() {
    ask_support.connections(server) == []
  })
  ask_support.stop(server)
  log_capture.stop(capture)
  let listener = atom_text(server.name)
  let ours = fn(line: Line) {
    string.contains(line.1, listener)
    || case metadata_of(line, "peer") {
      Ok(peer) ->
        list.any(ports, fn(port) {
          string.ends_with(peer, "," <> int.to_string(port) <> "}")
        })
      Error(Nil) -> False
    }
  }
  assert list.filter(drain(lines), fn(line) {
      is_warning_or_error(line) && ours(line)
    })
    == []
    as "a client that closes or resets before the first read is no error: no line of these connections or of their listener at warning or error"
}

pub fn a_client_gone_before_the_handshake_ends_the_connection_normally_with_no_recording_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  let #(reason, lines, files) = hand_over(hand_over_to_failing_transport)
  assert reason == process.Normal as "a normal end"
  assert files == Ok([]) as "no recording was opened"
  assert list.filter(lines, is_warning_or_error) == []
    as "and nothing is logged as an error"
  assert list.any(lines, fn(line) {
    line.0 == "debug"
    && string.contains(line.1, "left before the handshake finished")
  })
    as "the debug line says the client left"
}

pub fn a_socket_whose_options_cannot_be_set_ends_the_connection_normally_with_no_recording_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("serial")
  let #(reason, lines, files) = hand_over(hand_over_closed_socket)
  assert reason == process.Normal as "a normal end"
  assert files == Ok([]) as "no recording was opened"
  assert list.filter(lines, is_warning_or_error) == []
    as "and nothing is logged as an error"
  assert list.any(lines, fn(line) {
    line.0 == "debug"
    && string.contains(line.1, "socket options could not be set")
  })
    as "the debug line says the options failed, in words other than a client that left"
}

/// Starts a connection's process as Ranch's connection supervisor does, hands
/// it the socket by `hand_over`, and says how it ended, what it logged at
/// debug level and above, and what the recorder's folder holds.
fn hand_over(
  hand_over: fn(Pid, shell.RanchRef) -> Nil,
) -> #(
  process.ExitReason,
  List(Line),
  Result(List(String), simplifile.FileError),
) {
  use folder <- recording_support.in_folder
  let before = log_capture.primary_level()
  log_capture.set_primary_level(atom.create("debug"))
  let ref = new_ranch_ref()
  let assert Ok(connection) =
    shell.start(
      ref,
      settings(
        Some(recording_support.recorder(folder, rule_module: "hello_rule")),
      ),
    )
    as "the connection started before any handover"
  process.unlink(connection)
  let watched = process.monitor(connection)
  let lines = process.new_subject()
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  hand_over(connection, ref)
  let reason = ask_support.ended(watched)
  log_capture.stop(capture)
  log_capture.set_primary_level(before)
  #(reason, drain(lines), simplifile.read_directory(folder))
}

pub fn a_parent_that_stops_before_the_handshake_ends_the_connection_with_no_recording_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let assert Ok(connection) =
    shell.start(
      new_ranch_ref(),
      settings(
        Some(recording_support.recorder(folder, rule_module: "hello_rule")),
      ),
    )
    as "the connection started"
  process.unlink(connection)
  let watched = process.monitor(connection)
  // The test process is the parent. The connection traps exits only once it
  // holds the socket, so before that the parent's stop ends it.
  process.send_abnormal_exit(connection, atom.create("shutdown"))
  assert ask_support.ended(watched) == ask_support.shutdown()
    as "the connection ended with the parent's reason"
  assert simplifile.read_directory(folder) == Ok([])
    as "no recording was opened"
}

// ---- memory ----

pub fn a_connection_keeps_its_waiting_messages_off_its_heap_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(None)
  let #(_client, connection) = greeted(server)
  case message_queue_data(connection) {
    OffHeap -> Nil
    OnHeap -> panic as "the connection keeps its waiting messages on its heap"
  }
  ask_support.stop(server)
}

// ---- other processes' exits ----

pub fn an_exit_from_a_process_that_is_not_the_parent_gives_no_input_and_no_warning_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(None)
  let #(client, connection) = greeted(server)
  let lines = process.new_subject()
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  process.send_abnormal_exit(connection, atom.create("planted_exit"))
  // A marker from the same sender, after the exit: Erlang orders signals per
  // sender, so the marker's own warning is the first line the connection
  // logs, if the exit gave it none.
  let _marker =
    send_raw(connection, #(
      atom.create("marker_after_exit"),
      atom.create("marker_after_exit"),
    ))
  let assert Ok(#(level, text, _)) =
    process.receive(lines, ask_support.event_wait_ms)
    as "the marker was logged"
  log_capture.stop(capture)
  assert level == "warning" && string.contains(text, "marker_after_exit")
    as "the first line is the marker's stray warning, so the exit logged nothing"
  assert mug.send(client, <<5>>) == Ok(Nil)
  assert ask_support.read_bytes(client, 1) == <<5>>
    as "the connection took the exit as no input and goes on"
  ask_support.stop(server)
}

// ---- the log ----

pub fn a_line_the_rule_logs_carries_the_connection_and_the_peer_address_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(None)
  let #(client, connection) = greeted(server)
  let lines = process.new_subject()
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  assert mug.send(client, <<0xAA>>) == Ok(Nil)
  let assert Ok(line) = process.receive(lines, ask_support.event_wait_ms)
    as "the rule's line was logged"
  log_capture.stop(capture)
  assert line.0 == "warning" && line.1 == "the planted line"
  assert names_connection_and_peer(line)
    as "the line names the connection and the client's address"
  ask_support.stop(server)
}

pub fn a_crash_report_carries_the_connection_and_the_peer_address_test() -> Nil {
  use <- owned_test.run(30_000)
  let server = start(None)
  let #(client, connection) = greeted(server)
  let lines = process.new_subject()
  let capture = log_capture.start_with_metadata(from: connection, into: lines)
  assert mug.send(client, <<0xEE>>) == Ok(Nil) as "the byte that crashes it"
  let report = first_error(lines)
  log_capture.stop(capture)
  assert names_connection_and_peer(report)
    as "the crash report names the connection and the client's address"
}

/// The first line at error level, or a failure when none comes in time.
fn first_error(lines: Subject(Line)) -> Line {
  let assert Ok(line) = process.receive(lines, ask_support.event_wait_ms)
    as "a line at error level was logged"
  case line.0 {
    "error" -> line
    _ -> first_error(lines)
  }
}

// ---- stopping ----

pub fn a_crash_leaves_the_recording_without_end_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let server =
    start(Some(recording_support.recorder(folder, rule_module: "hello_rule")))
  let #(client, connection) = greeted(server)
  let watched = process.monitor(connection)
  assert mug.send(client, <<0xEE>>) == Ok(Nil) as "the byte that crashes it"
  let assert process.Abnormal(_) = ask_support.ended(watched)
    as "the connection crashed"
  let assert Ok(#(_, records)) =
    rule_recording.read(recording_support.recording_in(folder))
    as "the recording reads as far as it goes"
  assert !list.any(records, fn(record) {
    case record {
      rule_recording.End(..) -> True
      rule_recording.Taken(..) -> False
    }
  })
    as "a crash leaves no End, so the recording never replays"
  ask_support.stop(server)
}
