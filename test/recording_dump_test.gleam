//// The recording dump reads the server's writes under the session key. The
//// unhandled-message ranking takes its messages from the dump, so a wrong key
//// there makes the ranking read garbage. Expected values come from these places.
//// - The fact file's body vector: 0x0036 is one 32-bit value
////   (vector.opcode.0x36.body).
//// - The cipher: the base key keys a game connection until the client's 0x058F,
////   and the session key folded from its 16 bytes keys every frame after it,
////   each way (vector.0x14003827c.session_fold).
//// The recording is planted, written into a folder of its own and read back, as
//// `wire_client_message_test`'s are.

import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/game_hello_reply
import genesis_prime/named_fields
import genesis_prime/recording_dump
import genesis_prime/wire_recording.{Accepted, Client, Read}
import gleam/int
import gleam/list
import gleam/string
import message_support
import owned_test
import recording_support
import wire_replay_support as support

/// The body of 0x0036, the highest character level 3.
const level_3_body = <<3, 0, 0, 0>>

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

pub fn the_servers_writes_after_0x058f_are_read_under_the_session_key_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let assert Ok(hello_body) =
    game_hello_reply.encode(game_hello_reply.GameHelloReply(
      account_id: 0,
      session_key: message_support.session_key(),
      zero: 0,
      account_name: "a",
      three: 0,
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
      support.In(0, support.now_at(1), Accepted),
      support.Out(0, level(base)),
      support.In(0, support.now_at(2), Read(hello)),
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
