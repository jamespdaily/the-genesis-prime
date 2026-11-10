//// The wire recorder (genesis_prime/wire_recording/recorder) and the shell's
//// use of it: a connection's file holds its header, a line for each input the
//// shell took with the time its script's clock gave it, a line for each write
//// the socket took and, when the connection ends, a closing line naming the
//// side that closed. Expected values come from these places.
//// - The layout in `genesis_prime/wire_recording`: a header (rule, client
////   build, tables digest, seed, accept ordinal), `Took` and `Wrote` lines in
////   the order they happened, a closing line, and a sequence number growing
////   from line to line.
//// - The script a test gives the listener: the seed and the times it hands the
////   connection are the values the file must hold, and the rule
////   (`script_rule`) writes the seed and the time of each input it takes, so
////   the bytes the client reads are a second record of them.
//// - The shell's own words (genesis_prime/connection/shell): a client's close
////   is the input `PeerClosed` and ends the connection from the client's side,
////   the server's stop is `Stopping` and ends it from the server's; a rule
////   that has not stopped by the deadline is killed and leaves no closing
////   line; a recording that cannot be written ends the connection before the
////   step's effects.

import ask_support
import genesis_prime/connection/script.{Issued, Script}
import genesis_prime/seed
import genesis_prime/step.{type Now, Effects, Now}
import genesis_prime/step/runtime
import genesis_prime/wire_recording.{
  type Closing, Accepted, Client, Closing, Cut, Header, PeerClosed, Read,
  Recording, Server, Took, Wrote,
}
import genesis_prime/wire_recording/recorder.{WriteError}
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import mug
import owned_test
import recording_support
import script_rule
import simplifile

fn seed_value() -> seed.Seed {
  let assert Ok(value) =
    seed.from_bytes(recording_support.counting_seed_bytes())
    as "32 bytes are a seed"
  value
}

pub fn with_no_recorder_nothing_is_opened_or_written_test() -> Nil {
  use <- owned_test.run(30_000)
  assert recorder.open_if(
      recorder: None,
      rule_name: "script_rule",
      connection: 1,
      accept_ordinal: 1,
      seed: seed_value(),
    )
    == Ok(None)
    as "no recorder opens no recording"
  assert recorder.taken(
      writer: None,
      sequence: 1,
      at: Now(monotonic_ms: 0, filetime: 0),
      input: Accepted,
    )
    == Ok(Nil)
  assert recorder.sent(writer: None, sequence: 2, bytes: <<1>>) == Ok(Nil)
  assert recorder.close_if(writer: None, sequence: 3, by: Server) == Ok(Nil)
}

pub fn a_connections_file_is_named_after_its_rule_with_dots_and_its_number_test() -> Nil {
  use <- owned_test.run(30_000)
  assert recorder.file_name(
      rule_name: "genesis_prime/login/sts_connection",
      connection: 3,
    )
    == "genesis_prime.login.sts_connection-3.jsonl"
    as "the rule's module with a dot for each slash, a dash, the connection's number and the JSON-lines suffix"
  assert recorder.file_name(rule_name: "script_rule", connection: 12)
    == "script_rule-12" <> recorder.file_suffix
}

pub fn a_recorder_opens_one_file_for_each_connection_and_never_overwrites_it_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let rule_name = "genesis_prime/login/sts_connection"
  let assert Ok(Some(writer)) =
    recorder.open_if(
      recorder: Some(recording_support.wire_recorder(folder)),
      rule_name:,
      connection: 3,
      accept_ordinal: 7,
      seed: seed_value(),
    )
    as "the recording opens"
  let path = folder <> "/genesis_prime.login.sts_connection-3.jsonl"
  assert simplifile.read(path)
    == Ok(
      wire_recording.encode_header(Header(
        format: wire_recording.format,
        rule: rule_name,
        client_build: 16_042,
        tables_digest: None,
        seed: seed_value(),
        accept_ordinal: 7,
        realm: None,
      )),
    )
    as "the file is named after the rule, with / as a dot, and the connection, and holds the header alone"
  let at = Now(monotonic_ms: -4, filetime: 9)
  assert recorder.taken(
      writer: Some(writer),
      sequence: 10,
      at:,
      input: Accepted,
    )
    == Ok(Nil)
  assert recorder.sent(writer: Some(writer), sequence: 11, bytes: <<1, 2>>)
    == Ok(Nil)
  assert recorder.close_if(writer: Some(writer), sequence: 12, by: Client)
    == Ok(Nil)
  assert wire_recording.read(recording_support.wire_text_in(folder))
    == Ok(Recording(
      header: Header(
        format: wire_recording.format,
        rule: rule_name,
        client_build: 16_042,
        tables_digest: None,
        seed: seed_value(),
        accept_ordinal: 7,
        realm: None,
      ),
      lines: [Took(10, at, Accepted), Wrote(11, <<1, 2>>)],
      closing: Some(Closing(12, Client)),
    ))
    as "each call appended its line, and the closing line ended the file"
  let assert Error(WriteError(path: failed, ..)) =
    recorder.open_if(
      recorder: Some(recording_support.wire_recorder(folder)),
      rule_name:,
      connection: 3,
      accept_ordinal: 8,
      seed: seed_value(),
    )
    as "a file that is there is never overwritten"
  assert failed == path as "the error names the file"
}

pub fn a_recorder_records_the_digest_of_the_tables_in_the_header_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let assert Ok(Some(_)) =
    recorder.open_if(
      recorder: Some(recorder.new(
        folder:,
        client_build: 16_042,
        tables_digest: Some("C3D4"),
        realm: None,
      )),
      rule_name: "script_rule",
      connection: 1,
      accept_ordinal: 1,
      seed: seed_value(),
    )
    as "the recording opens"
  assert string.contains(
    recording_support.wire_text_in(folder),
    "\"tables_digest\":\"C3D4\"",
  )
    as "the header holds the digest of the tables the server loaded"
}

/// A script that gives each input a time of its own, told to `given` as it is
/// given, and the seed of 0 to 31 and the ordinal `ordinal`; a timer it is
/// asked to start is never started.
fn scripted(
  ordinal: Int,
  given: Subject(#(wire_recording.Input, Now)),
) -> script.Scripts {
  fn() {
    Ok(Issued(
      ordinal:,
      script: Script(
        seed: seed_value(),
        clock: fn(input) {
          let number = recording_support.unique_number()
          let now = Now(monotonic_ms: number, filetime: number * 7)
          process.send(given, #(input, now))
          now
        },
        node_monotonic_ms: fn(_now) { runtime.monotonic_ms() },
        schedule: fn(_subject, _timer, _reference, _after_ms) { fn() { Nil } },
        next_read: fn() { None },
      ),
    ))
  }
}

fn start(
  folder folder: String,
  scripts scripts: script.Scripts,
  shutdown_ms shutdown_ms: Int,
) -> ask_support.Server {
  ask_support.start_scripted(
    rule: script_rule.rule(),
    directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
    shutdown_ms:,
    wire_recorder: Some(recording_support.wire_recorder(folder)),
    scripts:,
    registry: None,
    locate: fn(_address) { Error(Nil) },
    with: fn(builder) { builder },
  )
}

pub fn a_connection_is_recorded_input_by_input_with_the_time_its_script_gave_each_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let given = process.new_subject()
  let server = start(folder:, scripts: scripted(5, given), shutdown_ms: 1000)
  let client = ask_support.connect(server)
  let accepted_record = ask_support.read_bytes(client, 49)
  assert mug.send(client, <<1, 2, 3, 4>>) == Ok(Nil) as "bytes"
  let read_record = ask_support.read_bytes(client, 17)
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  let _reason =
    ask_support.ended(
      watched: watched,
      what: "the connection to end after the client closed",
    )
  let assert Ok(#(Accepted, first)) = process.receive(given, 0)
    as "the clock was called for the accept"
  let assert Ok(#(Read(<<1, 2, 3, 4>>), second)) = process.receive(given, 0)
    as "the clock was called for the read, told its bytes"
  let assert Ok(#(PeerClosed, third)) = process.receive(given, 0)
    as "the clock was called for the client's close"
  assert process.receive(given, 0) == Error(Nil)
    as "no other input was taken, so no other call was made"
  let assert Ok(Recording(header:, lines:, closing: Some(closing))) =
    wire_recording.read(recording_support.wire_text_in(folder))
    as "the recording is whole"
  assert header.seed == seed_value() && header.accept_ordinal == 5
    as "the header holds the script's seed and ordinal"
  assert header.rule == "script_rule"
  let accepted_bytes = accepted_bytes(first)
  let read_bytes = script_rule.read_record_bytes(second)
  assert without_sequences(lines)
    == [
      Took(0, first, Accepted),
      Wrote(0, accepted_bytes),
      Took(0, second, Read(<<1, 2, 3, 4>>)),
      Wrote(0, read_bytes),
      Took(0, third, PeerClosed),
    ]
    as "each input with the time the script gave it, each write after its input"
  assert accepted_record == accepted_bytes && read_record == read_bytes
    as "the client read what the file says the shell wrote"
  assert grows(lines, closing) as "sequence numbers grow from line to line"
  assert closing.by == Client as "the shell's last input was the client's close"
}

/// What the script rule writes when accepted at `now`, with the tests' seed.
fn accepted_bytes(now: Now) -> BitArray {
  <<
    script_rule.accepted,
    recording_support.counting_seed_bytes():bits,
    now.monotonic_ms:64,
    now.filetime:64,
  >>
}

/// The lines with every sequence number set to 0, so a test compares what the
/// lines say and checks the numbers on their own.
fn without_sequences(
  lines: List(wire_recording.Line),
) -> List(wire_recording.Line) {
  list.map(lines, fn(line) {
    case line {
      Took(at:, input:, ..) -> Took(0, at, input)
      Wrote(bytes:, ..) -> Wrote(0, bytes)
    }
  })
}

/// Whether each line's sequence number is above the one before it, the closing
/// line's above the last line's.
fn grows(lines: List(wire_recording.Line), closing: Closing) -> Bool {
  let numbers =
    list.append(
      list.map(lines, fn(line) {
        case line {
          Took(sequence:, ..) | Wrote(sequence:, ..) -> sequence
        }
      }),
      [closing.sequence],
    )
  list.zip(numbers, list.drop(numbers, 1))
  |> list.all(fn(pair) { pair.0 < pair.1 })
}

pub fn a_server_stop_ends_the_recording_from_the_servers_side_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let given = process.new_subject()
  let server = start(folder:, scripts: scripted(1, given), shutdown_ms: 2000)
  let client = ask_support.connect(server)
  let _accepted = ask_support.read_bytes(client, 49)
  ask_support.stop(server)
  let assert Ok(Recording(lines:, closing: Some(closing), ..)) =
    wire_recording.read(recording_support.wire_text_in(folder))
    as "the recording is whole: the rule stopped in time"
  let assert [Took(input: Accepted, ..), Wrote(..), Took(input: stopping, ..)] =
    lines
    as "the accept, its write and the stop"
  assert stopping == wire_recording.Stopping
  assert closing.by == Server as "the server's stop ended the connection"
}

pub fn a_rule_that_does_not_stop_in_time_is_killed_and_its_recording_is_cut_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let given = process.new_subject()
  let ignoring =
    step.Rule(
      ..script_rule.rule(),
      step: fn(state, input: step.ConnectionInput(Nil, Nil)) {
        case input.event {
          step.Stopping(..) -> #(state, Effects([]))
          step.OwnEvent(..) | step.WatchEnded(..) ->
            script_rule.step(state, input)
        }
      },
    )
  let server =
    ask_support.start_scripted(
      rule: ignoring,
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      shutdown_ms: 300,
      wire_recorder: Some(recording_support.wire_recorder(folder)),
      scripts: scripted(1, given),
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with: fn(builder) { builder },
    )
  let client = ask_support.connect(server)
  let _accepted = ask_support.read_bytes(client, 49)
  ask_support.stop(server)
  assert wire_recording.read(recording_support.wire_text_in(folder))
    == Error(Cut(lines: 4))
    as "the header, the accept, its write and the stop, then nothing: killed at the deadline"
}

pub fn a_recording_that_cannot_be_written_ends_the_connection_before_the_steps_effects_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // A file where the recording folder should be: the recording cannot open.
  let blocked = folder <> "/blocked"
  let assert Ok(Nil) = simplifile.write(blocked, "")
    as "a file stands where the folder should be"
  let given = process.new_subject()
  let server =
    start(folder: blocked, scripts: scripted(1, given), shutdown_ms: 1000)
  let client = ask_support.connect(server)
  assert mug.receive(client, timeout_milliseconds: ask_support.event_wait_ms)
    == Error(mug.Closed)
    as "the connection closed without the accept's record, the accept's effect"
  ask_support.stop(server)
}

pub fn an_input_taken_with_the_servers_script_carries_readings_between_the_tests_own_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let server =
    ask_support.start_scripted(
      rule: script_rule.rule(),
      directory: fn(_request, _deadline_ms, _reply) { Error(Nil) },
      shutdown_ms: 1000,
      wire_recorder: Some(recording_support.wire_recorder(folder)),
      scripts: script.operating_system,
      registry: None,
      locate: fn(_address) { Error(Nil) },
      with: fn(builder) { builder },
    )
  // Each input is bounded by the test's own readings around the action that
  // caused it, so a reading reused from an earlier input falls outside.
  let before_accept = ask_support.monotonic_ms()
  let client = ask_support.connect(server)
  let _accepted = ask_support.read_bytes(client, 49)
  let after_accept = ask_support.monotonic_ms()
  let before_read = ask_support.monotonic_ms()
  assert mug.send(client, <<1>>) == Ok(Nil) as "bytes"
  let _read = ask_support.read_bytes(client, 17)
  let after_read = ask_support.monotonic_ms()
  let assert [connection] = ask_support.connections(server)
    as "one connection process"
  let watched = process.monitor(connection)
  let before_close = ask_support.monotonic_ms()
  assert mug.shutdown(client) == Ok(Nil) as "the client closed"
  let _reason =
    ask_support.ended(
      watched: watched,
      what: "the connection to end after the client closed",
    )
  let after_close = ask_support.monotonic_ms()
  let assert Ok(Recording(header:, lines:, ..)) =
    wire_recording.read(recording_support.wire_text_in(folder))
    as "the recording is whole"
  assert bit_array.byte_size(seed.bytes(header.seed)) == 32
    as "the server's script draws 32 bytes"
  let assert [
    Took(at: accepted, ..),
    Wrote(..),
    Took(at: read, ..),
    Wrote(..),
    Took(at: closed, ..),
  ] = lines
    as "an accept, a read and a close, each with its writes"
  assert accepted.monotonic_ms >= before_accept
    && accepted.monotonic_ms <= after_accept
    && read.monotonic_ms >= before_read
    && read.monotonic_ms <= after_read
    && closed.monotonic_ms >= before_close
    && closed.monotonic_ms <= after_close
    as "an input's reading lies between the test's readings around its cause"
  ask_support.stop(server)
}

/// The source files that hold `needle`, other than the recorder's own.
fn callers_of(needle: String) -> List(String) {
  let assert Ok(files) = simplifile.get_files("src")
    as "the source files are listed"
  list.filter(files, fn(path) {
    let assert Ok(text) = simplifile.read(path) as "a source file reads"
    string.ends_with(path, ".gleam")
    && path != "src/genesis_prime/wire_recording/recorder.gleam"
    && string.contains(text, needle)
  })
}

pub fn only_a_sitting_makes_a_wire_recorder_and_only_the_servers_start_asks_for_one_test() -> Nil {
  use <- owned_test.run(30_000)
  assert callers_of("recorder.new(") == ["src/genesis_prime/sitting.gleam"]
    as "only a sitting makes a wire recorder"
  assert callers_of("sitting.recorded(") == ["src/genesis_prime.gleam"]
    as "only the server's start turns a sitting on, for the folder GENESIS_RECORD_DIR names"
}
