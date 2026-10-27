//// The connection shell, its listener, the recorder and replay, proven on
//// the hello rule. Expected values come from these places.
//// - The hello's bytes: `vector.opcode.0x3.body`, the client's own 47 bytes
////   for the values below, in a frame of 53 bytes (length 35 00 00 00, id
////   03 00; record `0x1403355e0`, WriteMessageFrame).
//// - A ping and its pong: `opcode.0x0` and `opcode.0x1`, 07 00 00 00 00 00 then
////   the number, and 07 00 00 00 01 00 then the same number.
//// - The frame size limit, 131,070 bytes (MessageSizeLimit `0x140335ec0`).
//// - The shell's contract in the doc comment of `genesis_prime/connection/
////   shell` and the recording's layout in `genesis_prime/rule_recording`, as
////   approved on the shell card.
//// - FILETIME: 100-nanosecond intervals since 1601, 116,444,736,000,000,000 of
////   them at the Unix epoch (opcode.0x117 carries the server's time so).
//// Every wait is for an event, with a deadline a passing test never reaches.

import genesis_prime/connection/listener.{Listener}
import genesis_prime/connection/shell
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/rule_recording.{
  type Record, CountDiffers, End, Header, Incomplete, RecordAgain, StepDiffers,
  Taken,
}
import genesis_prime/rule_recording/file
import genesis_prime/rule_types
import genesis_prime/step.{
  type Input, type Rule, type Step, Accepted, ConnectionId, Effects, Input, Log,
  Now, Peer, PeerClosed, Read, ReadFailed, Rule, Socket, Stop, Stopping, Write,
  WriteFailed,
}
import gleam/bit_array
import gleam/crypto
import gleam/erlang/atom
import gleam/erlang/process.{type Pid}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/string
import gleam/time/timestamp
import hello_rule
import mug
import owned_test
import recording_support
import simplifile

/// How long one wait for an event may take, in milliseconds.
const event_wait_ms = 5000

// ---- the hello rule, pure ----

pub fn on_accept_the_rule_writes_the_server_hello_frame_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, step) = accept()
  assert step == Effects([Write(hello_frame())])
    as "vector.opcode.0x3.body in its 53-byte frame"
}

pub fn a_ping_split_across_two_reads_gets_one_pong_with_its_number_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = accept()
  let #(state, first) = take(state, Socket(Read(<<7, 0, 0, 0, 0, 0>>)))
  assert first == Effects([]) as "half a ping is not answered yet"
  let #(_, second) = take(state, Socket(Read(<<13>>)))
  assert second == Effects([Write(<<7, 0, 0, 0, 1, 0, 13>>)])
    as "opcode.0x1: the pong carries the ping's number"
}

pub fn two_pings_in_one_read_get_two_pongs_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = accept()
  let #(_, step) =
    take(state, Socket(Read(<<7, 0, 0, 0, 0, 0, 1, 7, 0, 0, 0, 0, 0, 2>>)))
  assert step
    == Effects([
      Write(<<7, 0, 0, 0, 1, 0, 1>>),
      Write(<<7, 0, 0, 0, 1, 0, 2>>),
    ])
    as "one pong for each ping, in the order they came"
}

pub fn a_peer_close_stops_and_a_read_failure_logs_and_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = accept()
  assert take(state, Socket(PeerClosed)).1 == Effects([Stop])
    as "the client closed, so the rule stops"
  let assert Effects([Log(_), Stop]) =
    take(state, Socket(ReadFailed(step.Reset))).1
    as "a read failure is logged, then the rule stops"
  Nil
}

pub fn a_frame_over_the_size_limit_logs_and_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = accept()
  // 131,071 is one byte over the limit, little-endian: ff ff 01 00.
  let assert Effects([Log(_), Stop]) =
    take(state, Socket(Read(<<0xFF, 0xFF, 0x01, 0x00, 0, 0>>))).1
    as "0x140335ec0: no frame is over 131,070 bytes"
  Nil
}

// ---- the shell, on a real socket ----

pub fn a_client_gets_the_hello_and_a_pong_for_its_ping_test() -> Nil {
  use <- owned_test.run(30_000)
  use server <- serving(hello_rule_as_rule(), None, 1000)
  let client = connect(server)
  assert receive(client, 53) == hello_frame() as "the hello comes first"
  assert mug.send(client, <<7, 0, 0, 0>>) == Ok(Nil) as "first half sent"
  assert mug.send(client, <<0, 0, 9>>) == Ok(Nil) as "second half sent"
  assert receive(client, 7) == <<7, 0, 0, 0, 1, 0, 9>> as "the pong for 9"
}

pub fn a_clients_close_ends_the_process_normally_test() -> Nil {
  use <- owned_test.run(30_000)
  use server <- serving(hello_rule_as_rule(), None, 1000)
  let client = connect(server)
  let _hello = receive(client, 53)
  let assert [connection] = connections(server) as "one connection process"
  let watched = process.monitor(connection)
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  assert ended(watched) == process.Normal as "a normal end"
}

pub fn a_failed_write_reaches_the_rule_and_the_steps_later_effects_are_not_carried_out_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- in_folder
  // The rule writes 64 MiB to a client that never reads, then 1 KiB, then
  // stops. The BEAM queues the first write whole; the second waits for the
  // queue and cannot finish within the 300 ms send deadline. Had the shell
  // carried out the Stop after the failed write, no WriteFailed input would
  // follow it in the recording.
  let rule = big_write_rule()
  use server <- serving(rule, Some(recorder(folder, rule)), 1000)
  let client = connect(server)
  let assert [connection] = connections(server) as "one connection process"
  assert ended(process.monitor(connection)) == process.Normal
    as "the rule stopped after the failed write"
  let _still_open = client
  let assert Ok(#(_, records)) = rule_recording.read(recording_in(folder))
    as "the recording reads"
  let assert [
    Taken(input: Input(event: Socket(Accepted(..)), ..), ..),
    Taken(input: Input(event: Socket(WriteFailed(step.SendTimedOut)), ..), ..),
    End(count: 2),
  ] = records
    as "the failed write came back as the next input, before anything else"
  Nil
}

pub fn a_rule_that_crashes_ends_only_its_connection_test() -> Nil {
  use <- owned_test.run(30_000)
  use server <- serving(crash_on_0xee_rule(), None, 1000)
  let first = connect(server)
  let _hello = receive(first, 53)
  let assert [connection] = connections(server) as "one connection process"
  let watched = process.monitor(connection)
  assert mug.send(first, <<0xEE>>) == Ok(Nil) as "the byte that crashes it"
  let assert process.Abnormal(_) = ended(watched) as "the connection crashed"
  let second = connect(server)
  assert receive(second, 53) == hello_frame()
    as "the listener still accepts and greets"
}

pub fn every_input_carries_one_time_reading_taken_as_the_shell_takes_it_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let rule = hello_rule_as_rule()
  let before_ms = monotonic_ms()
  let before_filetime = filetime_now()
  use server <- serving(rule, Some(recorder(folder, rule)), 1000)
  let client = connect(server)
  let _hello = receive(client, 53)
  assert mug.send(client, <<7, 0, 0, 0, 0, 0, 3>>) == Ok(Nil) as "a ping"
  let _pong = receive(client, 7)
  let assert [connection] = connections(server) as "one connection process"
  let watched = process.monitor(connection)
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  let _reason = ended(watched)
  let after_ms = monotonic_ms()
  let after_filetime = filetime_now()
  let assert Ok(#(_, records)) = rule_recording.read(recording_in(folder))
    as "the recording reads"
  let times =
    list.filter_map(records, fn(record) {
      case record {
        Taken(input: Input(now:, ..), ..) -> Ok(now)
        End(..) -> Error(Nil)
      }
    })
  assert list.length(times) == 3 as "accept, the ping and the close"
  assert list.all(times, fn(now) {
    now.monotonic_ms >= before_ms
    && now.monotonic_ms <= after_ms
    && now.filetime >= before_filetime
    && now.filetime <= after_filetime
  })
    as "each reading lies within the test's own readings around the session"
  assert list.map(times, fn(now) { now.monotonic_ms })
    == list.sort(list.map(times, fn(now) { now.monotonic_ms }), int.compare)
    as "readings never go back"
}

// ---- the recorder and replay ----

pub fn a_recorded_session_holds_the_header_one_record_per_input_and_end_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let rule = hello_rule_as_rule()
  record_one_ping(rule:, folder:, number: 5)
  let assert Ok(#(header, records)) = rule_recording.read(recording_in(folder))
    as "the recording reads"
  assert header == recorded_header(rule)
    as "the header names the format, the rule, its settings and its types"
  let assert [
    Taken(input: Input(event: Socket(Accepted(..)), ..), ..),
    Taken(input: Input(event: Socket(Read(<<7, 0, 0, 0, 0, 0, 5>>)), ..), ..),
    Taken(input: Input(event: Socket(PeerClosed), ..), ..),
    End(count: 3),
  ] = records
    as "accept, the ping, the close, then End with their count"
  Nil
}

pub fn replay_gives_the_same_steps_with_no_socket_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let rule = hello_rule_as_rule()
  record_one_ping(rule:, folder:, number: 5)
  assert rule_recording.replay(recording_in(folder), rule, digest()) == Ok(3)
    as "every recorded step is the step the rule gives again"
}

pub fn a_changed_byte_in_a_recorded_read_fails_replay_at_that_record_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let rule = hello_rule_as_rule()
  record_one_ping(rule:, folder:, number: 5)
  let bytes = recording_in(folder)
  let changed =
    replace_once(bytes:, old: <<7, 0, 0, 0, 0, 0, 5>>, new: <<
      7,
      0,
      0,
      0,
      0,
      0,
      6,
    >>)
  assert changed != bytes as "the ping's number was found and changed"
  let assert Error(StepDiffers(index: 1, ..)) =
    rule_recording.replay(changed, rule, digest())
    as "the read at index 1 now gives pong 6, not the recorded pong 5"
  Nil
}

pub fn a_cut_recording_or_a_wrong_end_count_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let rule = hello_rule_as_rule()
  record_one_ping(rule:, folder:, number: 5)
  let bytes = recording_in(folder)
  let end = rule_recording.encode(end_record(3))
  let body_size = bit_array.byte_size(bytes) - bit_array.byte_size(end)
  let assert Ok(without_end) = bit_array.slice(bytes, 0, body_size)
    as "the recording ends with End(3)"
  let assert Error(Incomplete(_)) =
    rule_recording.replay(without_end, rule, digest())
    as "no End: the process never finished"
  let assert Ok(cut) = bit_array.slice(bytes, 0, bit_array.byte_size(bytes) - 1)
    as "one byte shorter"
  let assert Error(Incomplete(_)) = rule_recording.replay(cut, rule, digest())
    as "a record cut short"
  let wrong = <<without_end:bits, rule_recording.encode(end_record(4)):bits>>
  assert rule_recording.replay(wrong, rule, digest())
    == Error(CountDiffers(end: 4, records: 3))
    as "End must count the records"
}

pub fn another_rule_name_or_type_digest_fails_with_record_again_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let rule = hello_rule_as_rule()
  record_one_ping(rule:, folder:, number: 5)
  let bytes = recording_in(folder)
  assert rule_recording.replay(bytes, Rule(..rule, name: "another"), digest())
    == Error(RecordAgain(reason: "the rule"))
    as "the header names another rule"
  assert rule_recording.replay(bytes, rule, "another digest")
    == Error(RecordAgain(reason: "the rule's types"))
    as "the rule's types have changed since the recording"
}

pub fn the_servers_own_code_never_turns_recording_on_test() -> Nil {
  use <- owned_test.run(10_000)
  let assert Ok(paths) = simplifile.get_files("src")
    as "the source folder lists"
  let callers =
    list.filter(paths, fn(path) {
      string.ends_with(path, ".gleam")
      && path != "src/genesis_prime/rule_recording/file.gleam"
      && {
        let assert Ok(text) = simplifile.read(path) as "a source file reads"
        string.contains(text, "file.recorder(")
      }
    })
  assert callers == []
    as "only the dev start makes a recorder, so the server records nothing"
}

pub fn when_the_server_stops_the_rule_gets_stopping_and_a_rule_that_stops_in_time_ends_its_recording_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let rule = hello_rule_as_rule()
  let server =
    start(rule:, recorder: Some(recorder(folder, rule)), shutdown_ms: 2000)
  let client = connect(server)
  let _hello = receive(client, 53)
  stop(server)
  let assert Ok(#(_, records)) = rule_recording.read(recording_in(folder))
    as "the recording reads"
  let assert [
    Taken(..),
    Taken(input: Input(event: Stopping(..), ..), step: Effects([Stop])),
    End(count: 2),
  ] = records
    as "Stopping came as the second input, and the rule stopped"
  Nil
}

pub fn a_rule_that_does_not_stop_in_time_is_killed_and_its_recording_is_incomplete_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  let rule = ignore_stopping_rule()
  let server =
    start(rule:, recorder: Some(recorder(folder, rule)), shutdown_ms: 300)
  let client = connect(server)
  let _hello = receive(client, 53)
  stop(server)
  let bytes = recording_in(folder)
  let assert Error(Incomplete(records: 3)) =
    rule_recording.replay(bytes, rule, digest())
    as "the header, accept and Stopping, then nothing: killed at the deadline"
  Nil
}

pub fn a_recording_that_cannot_be_written_ends_the_connection_before_the_steps_effects_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- in_folder
  // A file where the recording folder should be: the recording cannot open.
  let blocked = folder <> "/blocked"
  let assert Ok(Nil) = simplifile.write(blocked, "")
    as "a file stands where the folder should be"
  let rule = hello_rule_as_rule()
  use server <- serving(rule, Some(recorder(blocked, rule)), 1000)
  let client = connect(server)
  assert mug.receive(client, timeout_milliseconds: event_wait_ms)
    == Error(mug.Closed)
    as "the connection closed without the hello, the accept's effect"
}

// ---- helpers ----

fn hello() -> server_hello.ServerHello {
  ServerHello(
    build: 16_042,
    field_2: 0x11223344,
    field_3: 0x55667788,
    field_4: 0x99AABBCC,
    field_5: 0x0102030405060708,
    field_6: 0xBEEF,
    field_7: 0x1F,
    message_table_checksum: 0x097998A0,
    field_9: 0xCAFEBABE,
    field_10: 0x1112131415161718,
    field_11: 0x21222324,
  )
}

fn hello_frame() -> BitArray {
  let assert Ok(body) =
    bit_array.base16_decode(
      "AA3E00004433221188776655CCBBAA990807060504030201EFBE1F14332FC157D75F19E3C2A2826242228264442404",
    )
    as "vector.opcode.0x3.body is hex"
  <<0x35, 0, 0, 0, 0x03, 0, body:bits>>
}

fn hello_rule_as_rule() -> Rule(
  hello_rule.Settings,
  hello_rule.State,
  Nil,
  Nil,
  Nil,
  Nil,
) {
  Rule(
    name: "hello_rule",
    settings: hello_rule.Settings(hello: hello()),
    new: hello_rule.new,
    step: hello_rule.step,
  )
}

/// The hello rule, except that a read starting with 0xEE crashes it.
fn crash_on_0xee_rule() -> Rule(
  hello_rule.Settings,
  hello_rule.State,
  Nil,
  Nil,
  Nil,
  Nil,
) {
  Rule(..hello_rule_as_rule(), step: fn(state, input: Input(Nil, Nil)) {
    case input.event {
      Socket(Read(<<0xEE, _:bits>>)) -> panic as "the planted crash"
      Socket(..) | Stopping(..) -> hello_rule.step(state, input)
      step.Started
      | step.Woken(..)
      | step.Asked(..)
      | step.WatchEnded(..)
      | step.TimerFired(..)
      | step.Answered(..)
      | step.AnsweredLate(..) -> hello_rule.step(state, input)
    }
  })
}

/// The hello rule, except that it takes `Stopping` and does not stop.
fn ignore_stopping_rule() -> Rule(
  hello_rule.Settings,
  hello_rule.State,
  Nil,
  Nil,
  Nil,
  Nil,
) {
  Rule(..hello_rule_as_rule(), step: fn(state, input: Input(Nil, Nil)) {
    case input.event {
      Stopping(..) -> #(state, Effects([]))
      Socket(..) -> hello_rule.step(state, input)
      step.Started
      | step.Woken(..)
      | step.Asked(..)
      | step.WatchEnded(..)
      | step.TimerFired(..)
      | step.Answered(..)
      | step.AnsweredLate(..) -> hello_rule.step(state, input)
    }
  })
}

/// On accept, writes 64 MiB, then 1 KiB, then stops; on a failed write, stops.
fn big_write_rule() -> Rule(
  hello_rule.Settings,
  hello_rule.State,
  Nil,
  Nil,
  Nil,
  Nil,
) {
  Rule(..hello_rule_as_rule(), step: fn(state, input: Input(Nil, Nil)) {
    case input.event {
      Socket(Accepted(..)) -> #(
        state,
        Effects([Write(<<0:size(536_870_912)>>), Write(<<0:size(8192)>>), Stop]),
      )
      Socket(WriteFailed(..)) -> #(state, Effects([Stop]))
      Socket(..) | Stopping(..) -> hello_rule.step(state, input)
      step.Started
      | step.Woken(..)
      | step.Asked(..)
      | step.WatchEnded(..)
      | step.TimerFired(..)
      | step.Answered(..)
      | step.AnsweredLate(..) -> hello_rule.step(state, input)
    }
  })
}

fn accept() -> #(hello_rule.State, Step(Nil, Nil)) {
  take(
    hello_rule.new(hello_rule.Settings(hello: hello())),
    Socket(Accepted(ConnectionId(1), Peer(address: "127.0.0.1", port: 1))),
  )
}

fn take(
  state: hello_rule.State,
  event: step.Event(Nil, Nil),
) -> #(hello_rule.State, Step(Nil, Nil)) {
  hello_rule.step(state, Input(now: Now(monotonic_ms: 0, filetime: 0), event:))
}

fn digest() -> String {
  let assert Ok(digest) =
    rule_types.digest(rule_module: "hello_rule", source_roots: ["src", "test"])
    as "the hello rule's types digest"
  digest
}

fn recorded_header(
  rule: Rule(hello_rule.Settings, a, b, c, d, e),
) -> rule_recording.Header(hello_rule.Settings) {
  Header(
    format: rule_recording.format,
    rule: rule.name,
    client_build: 16_042,
    tables_digest: None,
    settings: rule.settings,
    types_digest: digest(),
  )
}

fn recorder(
  folder: String,
  rule: Rule(hello_rule.Settings, a, b, c, d, e),
) -> file.Recorder(hello_rule.Settings) {
  file.recorder(folder:, header: recorded_header(rule))
}

fn end_record(count: Int) -> Record(Nil, Nil, Nil, Nil) {
  End(count:)
}

/// Records a session of one ping with `number`, then the client's close.
fn record_one_ping(
  rule rule: Rule(hello_rule.Settings, hello_rule.State, Nil, Nil, Nil, Nil),
  folder folder: String,
  number number: Int,
) -> Nil {
  use server <- serving(rule, Some(recorder(folder, rule)), 1000)
  let client = connect(server)
  let _hello = receive(client, 53)
  assert mug.send(client, <<7, 0, 0, 0, 0, 0, number>>) == Ok(Nil) as "a ping"
  let _pong = receive(client, 7)
  let assert [connection] = connections(server) as "one connection process"
  let watched = process.monitor(connection)
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  let _reason = ended(watched)
  Nil
}

type Server {
  Server(supervisor: Pid, name: String, port: Int)
}

fn start(
  rule rule: Rule(settings, state, Nil, Nil, Nil, Nil),
  recorder recorder: option.Option(file.Recorder(settings)),
  shutdown_ms shutdown_ms: Int,
) -> Server {
  let name =
    "test-"
    <> string.lowercase(bit_array.base16_encode(crypto.strong_random_bytes(8)))
  let connection =
    shell.Settings(rule:, send_deadline_ms: 300, shutdown_ms:, recorder:)
  let assert Ok(started) =
    supervisor.new(supervisor.OneForOne)
    |> supervisor.add(
      listener.supervised(Listener(name:, port: 0, connection:)),
    )
    |> supervisor.start
    as "the listener started"
  process.unlink(started.pid)
  let assert Ok(port) = listener.port(name) as "the listener has a port"
  Server(supervisor: started.pid, name:, port:)
}

/// Stops the server's tree as a stop of the server does, and waits for it to
/// end.
fn stop(server: Server) -> Nil {
  let watched = process.monitor(server.supervisor)
  process.send_abnormal_exit(server.supervisor, atom.create("shutdown"))
  let _reason = ended(watched)
  Nil
}

fn serving(
  rule: Rule(settings, state, Nil, Nil, Nil, Nil),
  recorder: option.Option(file.Recorder(settings)),
  shutdown_ms: Int,
  body: fn(Server) -> a,
) -> a {
  let server = start(rule:, recorder:, shutdown_ms:)
  let result = body(server)
  stop(server)
  result
}

fn connect(server: Server) -> mug.Socket {
  let assert Ok(client) =
    mug.new("127.0.0.1", port: server.port)
    |> mug.ip_version_preference(mug.Ipv4Only)
    |> mug.timeout(event_wait_ms)
    |> mug.connect
    as "the client connected"
  client
}

fn receive(client: mug.Socket, bytes: Int) -> BitArray {
  let assert Ok(received) =
    mug.receive_exact(
      client,
      byte_size: bytes,
      timeout_milliseconds: event_wait_ms,
    )
    as "the bytes arrived"
  received
}

/// The server's connection processes, as Ranch lists them. The list is read
/// after the client has its first bytes, so the process exists.
fn connections(server: Server) -> List(Pid) {
  procs(server.name, atom.create("connections"))
}

fn ended(watched: process.Monitor) -> process.ExitReason {
  let assert Ok(down) =
    process.new_selector()
    |> process.select_specific_monitor(watched, fn(down) { down })
    |> process.selector_receive(within: event_wait_ms)
    as "the process ended"
  case down {
    process.ProcessDown(reason:, ..) -> reason
    process.PortDown(reason:, ..) -> reason
  }
}

fn in_folder(body: fn(String) -> a) -> a {
  let folder = recording_support.new_folder()
  let result = body(folder)
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder was removed"
  result
}

/// The one recording in the folder.
fn recording_in(folder: String) -> BitArray {
  let assert Ok([name]) = simplifile.read_directory(folder)
    as "one recording in the folder"
  let assert Ok(bytes) = simplifile.read_bits(folder <> "/" <> name)
    as "the recording reads"
  bytes
}

fn replace_once(
  bytes bytes: BitArray,
  old old: BitArray,
  new new: BitArray,
) -> BitArray {
  case bytes {
    <<>> -> <<>>
    _ -> {
      let size = bit_array.byte_size(old)
      case bit_array.slice(bytes, 0, size) {
        Ok(start) if start == old -> {
          let assert Ok(rest) =
            bit_array.slice(bytes, size, bit_array.byte_size(bytes) - size)
            as "the rest after the match"
          <<new:bits, rest:bits>>
        }
        _ -> {
          let assert <<first, rest:bytes>> = bytes as "a byte to keep"
          <<first, replace_once(bytes: rest, old:, new:):bits>>
        }
      }
    }
  }
}

fn filetime_now() -> Int {
  let #(seconds, nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  seconds * 10_000_000 + nanoseconds / 100 + 116_444_736_000_000_000
}

fn monotonic_ms() -> Int {
  monotonic_ms_ffi(atom.create("millisecond"))
}

@external(erlang, "erlang", "monotonic_time")
fn monotonic_ms_ffi(unit: atom.Atom) -> Int

@external(erlang, "ranch", "procs")
fn procs(ref: String, kind: atom.Atom) -> List(Pid)
