//// The recording dump reads recordings as messages, both ways. Expected values
//// come from these places.
//// - The session's own verdict (`verdict.txt` beside the recordings): the
////   client reported the played character as 'Tess Renamed'.
//// - The client's code: it sends 0x023C through SendWorldMessage (0x1403f4900,
////   which lists 0x23c among the ids it sends), inside 0x038C inside the
////   client's wrapper; the schema has no message of that number.
//// - The fact file's body vectors: 0x0036 is one 32-bit value
////   (vector.opcode.0x36.body), 0x019B two (vector.opcode.0x19b.body), and the
////   0x0935 vector of `class_resource_message_test` is unit 0x1001, stat 5 and
////   the float 35.0, whose 32 bits are 0x420C0000.
//// - The frame reader refuses a length under the 6 bytes of a frame's header
////   (ParseWrappedMessage 0x140331620).
//// - The cipher: the base key keys a game connection until the client's 0x058F,
////   and the session key folded from its 16 bytes keys every frame after it,
////   each way (vector.0x14003827c.session_fold).
//// The failure paths are planted recordings, written into a folder of their own
//// and read back, as `wire_client_message_test`'s are.

import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/message/game_hello_reply
import genesis_prime/named_fields
import genesis_prime/recorded_message.{ClientToServer, ServerToClient}
import genesis_prime/recording_dump
import genesis_prime/step.{type Now, Now}
import genesis_prime/wire_recording.{Accepted, Client, Read}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import message_support
import owned_test
import recording_support
import wire_replay_support as support

pub fn the_dump_names_the_players_unit_and_lists_a_message_with_no_decoder_by_its_number_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert Ok(names) = named_fields.from_schema_file()
    as "the schema the codec is generated from reads"
  let connections =
    support.load(support.committed_session).connections
    |> list.map(fn(connection) { #(connection.name, connection.recording) })
  let entries = recording_dump.entries(connections:, names:)
  let assert Ok(created) =
    list.find(entries, fn(entry) {
      entry.direction == Some(ServerToClient)
      && entry.message_id == Some(0x0262)
      && entry.name == "unit_create_player"
    })
    as "the server wrote the player's unit, named by the schema"
  assert string.contains(created.fields, "name: \"Tess Renamed\"")
    as "the unit is the character the client reported (verdict.txt: strName = 'Tess Renamed')"
  let assert Ok(unhandled) =
    list.find(entries, fn(entry) {
      entry.direction == Some(ClientToServer)
      && entry.message_id == Some(0x023C)
    })
    as "the client sent 0x023C (0x1403f4900)"
  assert unhandled.name == "unhandled"
    as "no message of the schema the client sends has the number 0x023C"
  assert unhandled.depth == 2
    as "it came inside 0x038C inside the client's wrapper (0x1403f4900)"
}

// ---- the server's direction and the failure paths, from planted recordings ----

fn at(n: Int) -> Now {
  Now(monotonic_ms: n, filetime: n * 10)
}

/// The body of 0x0036, the highest character level 3.
const level_3_body = <<3, 0, 0, 0>>

/// The body of 0x019B for unit 0x1001, its second value 0x2002.
const unit_0x1001_body = <<0x01, 0x10, 0x00, 0x00, 0x02, 0x20, 0x00, 0x00>>

/// The same message for unit 0x1002.
const unit_0x1002_body = <<0x02, 0x10, 0x00, 0x00, 0x02, 0x20, 0x00, 0x00>>

/// The bytes of a frame in a wrapper, ciphered under `cipher`.
fn wrapped(
  wrapper wrapper: encrypted_frame.Wrapper,
  id id: Int,
  body body: BitArray,
  cipher cipher: Cipher,
) -> BitArray {
  let assert Ok(bytes) =
    encrypted_frame.wrap(wrapper, Frame(message_id: id, body:), cipher)
    as "the frame is within the size limit"
  bytes
}

/// A frame the auth server writes, under the base key.
fn base_written(id id: Int, body body: BitArray) -> BitArray {
  wrapped(
    wrapper: encrypted_frame.AuthWrapper,
    id:,
    body:,
    cipher: cipher.base(),
  )
}

/// What the dump holds of a planted connection of the rule `rule`: the steps in
/// the order the node saw them, written into `folder` as a session of its own.
fn dumped(
  folder folder: String,
  rule rule: String,
  steps steps: List(support.Step),
) -> List(recording_dump.Entry) {
  support.write(
    folder:,
    connections: [support.Planted(rule:, seed: support.seed(1), ordinal: 1)],
    steps:,
  )
  let assert Ok(names) = named_fields.from_schema_file()
    as "the schema the codec is generated from reads"
  let connections =
    support.load(folder).connections
    |> list.map(fn(connection) { #(connection.name, connection.recording) })
  recording_dump.entries(connections:, names:)
}

/// The printed lines of a planted auth connection's steps, unfiltered.
fn auth_lines(
  folder folder: String,
  steps steps: List(support.Step),
) -> List(String) {
  dumped(folder:, rule: auth_connection.rule_name, steps:)
  |> recording_dump.printed(filter: no_filter())
}

/// A word of a printed line: sequence, time, direction, connection, "depth",
/// the depth, the opcode, the name, then the fields.
fn word(line: String, index: Int) -> String {
  let assert Ok(found) = list.drop(string.split(line, " "), index) |> list.first
    as { "the line has " <> int.to_string(index + 1) <> " words: " <> line }
  found
}

fn no_filter() -> recording_dump.Filter {
  let assert Ok(#(_, filter)) = recording_dump.parse(["any"])
    as "a path alone is an unfiltered dump"
  filter
}

pub fn a_server_frame_cut_mid_frame_ends_the_dump_with_a_stopped_line_that_says_server_to_client_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let whole = base_written(id: 0x0036, body: level_3_body)
  let assert Ok(cut) = bit_array.slice(whole, 0, bit_array.byte_size(whole) - 1)
    as "the frame is longer than one byte"
  let lines =
    auth_lines(folder:, steps: [
      support.In(0, at(1), Accepted),
      support.Out(0, whole),
      support.Out(0, cut),
      support.Closed(0, Client),
    ])
  let assert [message, stopped] = lines
    as "the whole frame is printed, then the cut one ends the dump"
  assert word(message, 7) == "max_character_level"
    as "the whole frame before the cut is read (vector.opcode.0x36.body)"
  assert word(stopped, 2) == "server→client"
    as "the cut frame is the server's write, the last line of that side"
  assert word(stopped, 6) == "-"
    as "a stopped line is no message, so it has no opcode"
  assert word(stopped, 7) == "stopped"
  assert string.contains(
    stopped,
    "CutShort(" <> int.to_string(bit_array.byte_size(cut)) <> ")",
  )
    as "the bytes of the frame that are there"
}

pub fn a_client_frame_the_reader_refuses_ends_the_dump_with_a_stopped_line_that_says_client_to_server_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let lines =
    auth_lines(folder:, steps: [
      support.In(0, at(1), Accepted),
      support.In(0, at(2), Read(<<2, 0, 0, 0, 0, 0>>)),
      support.Closed(0, Client),
    ])
  let assert [stopped] = lines as "no message came before the refused frame"
  assert word(stopped, 2) == "client→server"
  assert word(stopped, 6) == "-"
  assert word(stopped, 7) == "stopped"
  assert string.contains(stopped, "LengthBelowHeader(2)")
    as "a length of 2 is under the 6 bytes of a header (0x140331620)"
}

pub fn a_server_frame_the_reader_refuses_ends_the_dump_with_a_stopped_line_that_says_server_to_client_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let lines =
    auth_lines(folder:, steps: [
      support.In(0, at(1), Accepted),
      support.Out(0, <<2, 0, 0, 0, 0, 0>>),
      support.Closed(0, Client),
    ])
  let assert [stopped] = lines as "no message came before the refused frame"
  assert word(stopped, 2) == "server→client"
  assert word(stopped, 6) == "-"
  assert string.contains(stopped, "LengthBelowHeader(2)")
}

pub fn a_server_body_that_is_not_its_message_is_printed_as_malformed_and_the_dump_goes_on_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let lines =
    auth_lines(folder:, steps: [
      support.In(0, at(1), Accepted),
      support.Out(0, base_written(id: 0x0036, body: <<3, 0, 0>>)),
      support.Out(0, base_written(id: 0x0036, body: level_3_body)),
      support.Closed(0, Client),
    ])
  let assert [malformed, read] = lines
    as "both frames are printed: a body that is no message does not stop the dump"
  assert word(malformed, 2) == "server→client"
  assert word(malformed, 6) == "0x0036"
  assert word(malformed, 7) == "malformed"
  assert string.contains(malformed, "EndOfData")
    as "0x0036 is one 32-bit value, so 3 bytes end inside it"
  assert word(read, 7) == "max_character_level"
  assert string.contains(read, "highest_level: 3") as "vector.opcode.0x36.body"
}

pub fn a_server_message_with_no_decoder_is_printed_as_unhandled_with_its_size_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let lines =
    auth_lines(folder:, steps: [
      support.In(0, at(1), Accepted),
      support.Out(0, base_written(id: 0x0FFF, body: <<1, 2, 3>>)),
      support.Closed(0, Client),
    ])
  let assert [line] = lines as "one line"
  assert word(line, 2) == "server→client"
  assert word(line, 6) == "0x0FFF"
  assert word(line, 7) == "unhandled"
    as "the schema holds no message of 0x0FFF the server sends"
  assert string.ends_with(line, "3 bytes") as "the size of the body"
}

pub fn the_servers_writes_after_0x058f_are_read_under_the_session_key_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let assert Ok(hello_body) =
    game_hello_reply.encode(game_hello_reply.GameHelloReply(
      field_1: 0,
      session_key: message_support.session_key(),
      field_3: 0,
      account_name: "a",
      field_5: 0,
    ))
    as "the hello reply encodes"
  let base = cipher.base()
  let hello =
    wrapped(
      wrapper: encrypted_frame.ClientWrapper,
      id: 0x058F,
      body: hello_body,
      cipher: base,
    )
  let assert Ok(session) =
    game_connection.rekeyed(session_key: message_support.session_key())
    as "the session key makes a cipher"
  let level = fn(cipher) {
    wrapped(
      wrapper: encrypted_frame.GameWrapper,
      id: 0x0036,
      body: level_3_body,
      cipher:,
    )
  }
  let lines =
    dumped(folder:, rule: game_connection.rule_name, steps: [
      support.In(0, at(1), Accepted),
      support.Out(0, level(base)),
      support.In(0, at(2), Read(hello)),
      support.Out(0, level(session)),
      support.Out(0, level(base)),
      support.Closed(0, Client),
    ])
    |> recording_dump.printed(filter: no_filter())
  let assert [before, hello_line, after, with_base, ..] = lines
    as "the write before 0x058F, the hello, the write after it, and the write under the base key after it"
  assert word(before, 7) == "max_character_level"
    as "before 0x058F the server's frames are under the base key"
  assert word(hello_line, 2) == "client→server"
  assert word(hello_line, 7) == "game_hello_reply"
  assert word(after, 2) == "server→client"
  assert word(after, 4) == "depth" && word(after, 5) == "1"
    as "the message is inside the server's wrapper"
  assert word(after, 7) == "max_character_level"
    as "after 0x058F the server's frames are under the session key"
  assert string.contains(after, "highest_level: 3")
  assert word(with_base, 7) != "max_character_level"
    as "a frame under the base key after 0x058F is not the message under the session key"
}

/// The entries of a connection of messages at +0, +100 and +500 ms, written by
/// the server: unit 0x1001, unit 0x1002 and unit 0x1001, then a frame cut short
/// that stops the read at +500 ms.
fn timed_entries(folder: String) -> List(recording_dump.Entry) {
  let whole = base_written(id: 0x019B, body: unit_0x1001_body)
  let assert Ok(cut) = bit_array.slice(whole, 0, bit_array.byte_size(whole) - 1)
    as "the frame is longer than one byte"
  dumped(folder:, rule: auth_connection.rule_name, steps: [
    support.In(0, at(1000), Accepted),
    support.Out(0, whole),
    support.In(0, at(1100), wire_recording.Woken),
    support.Out(0, base_written(id: 0x019B, body: unit_0x1002_body)),
    support.In(0, at(1500), wire_recording.Woken),
    support.Out(0, whole),
    support.Out(0, cut),
    support.Closed(0, Client),
  ])
}

/// What the dump prints for the arguments over `timed_entries`: each line as
/// its time and unit, and `stopped` for the line that is no message.
fn kept(folder: String, arguments: List(String)) -> List(String) {
  let assert Ok(#(_, filter)) = recording_dump.parse(["any", ..arguments])
    as "the arguments are taken"
  timed_entries(folder)
  |> recording_dump.printed(filter:)
  |> list.map(fn(line) {
    case word(line, 7) {
      "stopped" -> "stopped"
      _ -> word(line, 1) <> " " <> unit_of(line)
    }
  })
}

fn unit_of(line: String) -> String {
  case
    string.contains(line, "unit_id: 4097"),
    string.contains(line, "unit_id: 4098")
  {
    True, _ -> "0x1001"
    False, True -> "0x1002"
    False, False -> "no unit"
  }
}

pub fn the_unit_filter_keeps_the_messages_of_that_unit_and_the_stopped_line_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  assert kept(folder, [])
    == ["+0ms 0x1001", "+100ms 0x1002", "+500ms 0x1001", "stopped"]
    as "unfiltered: a write takes the time of the input before it"
  assert kept(folder, ["--unit", "4097"])
    == ["+0ms 0x1001", "+500ms 0x1001", "stopped"]
    as "unit 0x1001 is 4097"
  assert kept(folder, ["--unit", "4098"]) == ["+100ms 0x1002", "stopped"]
  assert kept(folder, ["--unit", "9"]) == ["stopped"]
    as "a unit no message names keeps the line that says why the read stopped"
}

pub fn the_time_filters_keep_the_messages_within_them_and_the_stopped_line_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  assert kept(folder, ["--from", "100", "--to", "100"])
    == ["+100ms 0x1002", "stopped"]
    as "both bounds are inclusive"
  assert kept(folder, ["--from", "101"]) == ["+500ms 0x1001", "stopped"]
  assert kept(folder, ["--to", "99"]) == ["+0ms 0x1001", "stopped"]
  assert kept(folder, ["--from", "600"]) == ["stopped"]
    as "the stopped line at +500 ms is kept outside the window"
}

pub fn arguments_the_dump_does_not_take_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert recording_dump.parse([]) == Error(Nil) as "a path is needed"
  assert recording_dump.parse(["p", "--from"]) == Error(Nil)
    as "an option needs a value"
  assert recording_dump.parse(["p", "--from", "soon"]) == Error(Nil)
    as "a value is a whole number"
  assert recording_dump.parse(["p", "--unknown", "1"]) == Error(Nil)
    as "only --from, --to and --unit are taken"
  assert result.is_ok(recording_dump.parse(["p", "--unit", "1"]))
}

pub fn a_float_field_prints_as_its_bits_and_as_the_float_they_hold_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let lines =
    auth_lines(folder:, steps: [
      support.In(0, at(1), Accepted),
      support.Out(
        0,
        base_written(id: 0x0935, body: <<
          0x01, 0x10, 0x00, 0x00, 0x05, 0x00, 0x80, 0x41, 0x08,
        >>),
      ),
      support.Closed(0, Client),
    ])
  let assert [line] = lines as "one message"
  assert word(line, 7) == "unit_float_stat_changed"
  assert string.contains(
    line,
    "value: " <> int.to_string(0x420C0000) <> " (35.0)",
  )
    as "the bits as the record holds them, then the float they are"
}
