//// Every message the real client sent in a wire recording decodes with the
//// server's decoders and encodes back to the body the client sent, and a
//// changed message fails the read, naming the connection, the line and the
//// message. Expected values come from these places.
//// - The recordings under `test/wire_recording`: live logins of the real client
////   through the STS, auth and game servers. The STS connection's first requests
////   are Connect, LoginStart and KeyData in the clear, and the rest are
////   ciphered. The auth connection's one message is the login request in its
////   wrapper; the game connection's first messages are 0x058F, 0x07E0 and a
////   0x038C, all under the session key after the first. How the network cuts the
////   client's bytes into reads differs from run to run, so no check names a
////   read's line.
//// - Ping numbers are below 20 (opcode.0x0), and the client counts them up.
//// - The build in the login request is the client's (fact
////   archive_index.header).
//// - The layout of the login request in the schema (opcode.0x592): a build of
////   32 bits first, its last field a whole number of bytes, and the bit
////   stream's rule that a body ends at its last field.
//// - The cipher: the base key keys the auth connection and each new game
////   connection, and the session key folded from the 16 bytes of 0x058F re-keys
////   the game connection (vector.0x14003827c.session_fold).

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/guid
import genesis_prime/login/sts_connection
import genesis_prime/login/sts_message
import genesis_prime/message/bit_stream
import genesis_prime/message/client_message
import genesis_prime/message/movement_command
import genesis_prime/message/movement_mode
import genesis_prime/message/movement_state_flags
import genesis_prime/message/ping.{Ping}
import genesis_prime/step.{type Now, Now}
import genesis_prime/wire_recording.{type Recording, Accepted, Client, Read}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import recording_support
import wire_client_message.{
  type Received, type Unread, Bare, CutShort, Decoded, FramesRead, Inside,
  NoDecoder, NotDecoded, NotRead, PlatformLogin, RuleNotKnown, StsMessageRefused,
  Unread, Wrapped,
}
import wire_replay_support as support

fn at(n: Int) -> Now {
  Now(monotonic_ms: n, filetime: n * 10)
}

/// The recording of the connection of the rule `rule` in the committed session,
/// with its file's name.
fn committed(rule: String) -> #(String, Recording) {
  let assert Ok(connection) =
    list.find(
      support.load(support.committed_session).connections,
      fn(connection) { connection.recording.header.rule == rule },
    )
    as { "the committed session holds a connection of " <> rule }
  #(connection.name, connection.recording)
}

fn read_committed(rule: String) -> wire_client_message.Sent {
  let #(name, recording) = committed(rule)
  let assert Ok(Some(sent)) = wire_client_message.read(name, recording)
    as { name <> " holds client bytes and they read" }
  sent
}

fn frames_of(rule: String) -> #(List(Received), List(Unread)) {
  let assert FramesRead(messages:, without_decoder:) = read_committed(rule)
    as { rule <> " is a connection of frames" }
  #(messages, without_decoder)
}

/// A recording of the connection of `rule` whose reads are `reads`, written in
/// `folder` as a session of its own and read back.
fn planted(
  folder folder: String,
  rule rule: String,
  reads reads: List(BitArray),
) -> #(String, Recording) {
  support.write(
    folder:,
    connections: [support.Planted(rule:, seed: support.seed(1), ordinal: 1)],
    steps: list.flatten([
      [support.In(0, at(1), Accepted)],
      list.index_map(reads, fn(bytes, index) {
        support.In(0, at(2 + index), Read(bytes))
      }),
      [support.Closed(0, Client)],
    ]),
  )
  let assert [connection] = support.load(folder).connections
    as "the planted session holds one connection"
  #(connection.name, connection.recording)
}

pub fn every_client_message_in_every_wire_recording_decodes_test() -> Nil {
  use <- owned_test.run(30_000)
  let sessions = support.recorded_sessions()
  assert sessions != [] as "the repository holds a recorded session"
  list.each(sessions, fn(folder) {
    let session = support.load(folder)
    list.each(session.connections, fn(connection) {
      let assert Ok(Some(_)) =
        wire_client_message.read(connection.name, connection.recording)
        as {
          "every client message in "
          <> folder
          <> "/"
          <> connection.name
          <> " reads"
        }
    })
  })
}

pub fn every_decoded_message_encodes_back_to_the_body_the_client_sent_test() -> Nil {
  use <- owned_test.run(30_000)
  let messages =
    list.flat_map(support.recorded_sessions(), fn(folder) {
      list.flat_map(support.load(folder).connections, fn(connection) {
        case wire_client_message.read(connection.name, connection.recording) {
          Ok(Some(FramesRead(messages:, ..))) ->
            list.map(messages, fn(message) { #(connection.name, message) })
          Ok(Some(PlatformLogin(..))) | Ok(None) | Error(NotRead(..)) -> []
        }
      })
    })
  assert messages != [] as "the recordings hold messages"
  list.each(messages, fn(entry) {
    let #(name, message) = entry
    assert client_message.encode(message.message) == Ok(message.body)
      as {
        name
        <> " line "
        <> int.to_string(message.line)
        <> ": a decoded message encodes to the body the client sent, so every bit of it was read"
      }
  })
}

/// The messages of the player moving that the client sends in the world: the
/// movement commands and the five small messages the move step reads.
const moving_ids = [0x0637, 0x063A, 0x00D5, 0x063B, 0x00FB, 0x00FC]

/// Every message the committed sessions hold with a decoder, with the
/// connection's name and its line, in order.
fn recorded_messages() -> List(#(String, Received)) {
  list.flat_map(support.recorded_sessions(), fn(folder) {
    list.flat_map(support.load(folder).connections, fn(connection) {
      case wire_client_message.read(connection.name, connection.recording) {
        Ok(Some(FramesRead(messages:, ..))) ->
          list.map(messages, fn(message) { #(connection.name, message) })
        Ok(Some(PlatformLogin(..))) | Ok(None) | Error(NotRead(..)) -> []
      }
    })
  })
}

pub fn every_movement_message_in_every_wire_recording_decodes_and_encodes_back_to_its_body_test() -> Nil {
  use <- owned_test.run(30_000)
  let moving =
    list.filter(recorded_messages(), fn(entry) {
      list.contains(moving_ids, client_message.message_id({ entry.1 }.message))
    })
  let ids =
    list.map(moving, fn(entry) {
      client_message.message_id({ entry.1 }.message)
    })
  list.each([0x0637, 0x063A, 0x00D5, 0x063B], fn(id) {
    assert list.contains(ids, id)
      as "the committed session holds this message, which the client sends after 0x636 and 0xF1 (opcode.0x637, opcode.0x63a, opcode.0xd5, opcode.0x63b)"
  })
  list.each(moving, fn(entry) {
    let #(name, message) = entry
    assert client_message.encode(message.message) == Ok(message.body)
      as {
        name
        <> " line "
        <> int.to_string(message.line)
        <> ": the message encodes to the body the client sent"
      }
  })
  let #(_, without_decoder) = frames_of(game_connection.rule_name)
  assert list.filter(without_decoder, fn(unread) {
      list.contains(moving_ids, unread.message_id)
    })
    == []
    as "none of them is listed as having no decoder"
}

/// The kind of a movement command, its first 5 bits as written.
fn kind_of(command: movement_command.MovementCommand) -> Int {
  let assert Ok(bytes) =
    bit_stream.new_writer()
    |> movement_command.write(command)
    |> bit_stream.finish
    as "a command read from the recording is within its widths"
  let assert Ok(kind) =
    bit_stream.peek_unsigned(bit_stream.new_reader(bytes), 5)
    as "a command is at least its 5-bit kind"
  kind
}

/// The recorded messages of the number `id`, in order.
fn recorded_of(id: Int) -> List(client_message.ClientMessage) {
  recorded_messages()
  |> list.map(fn(entry) { { entry.1 }.message })
  |> list.filter(fn(message) { client_message.message_id(message) == id })
}

pub fn the_recorded_movement_holds_what_the_clients_per_frame_update_sends_test() -> Nil {
  use <- owned_test.run(30_000)
  let moves =
    list.map(recorded_of(0x0637), fn(message) {
      let assert client_message.PlayerMovement(message:) = message
        as "0x0637 is the player's movement"
      message
    })
  assert moves != [] as "the committed session holds movement"
  let commands = list.flat_map(moves, fn(move) { move.commands })
  assert commands != [] as "the recorded movement holds commands"
  list.each(commands, fn(command) {
    let kind = kind_of(command)
    assert list.contains([0, 1, 2, 8, 11, 14, 24, 27], kind)
      as "opcode.0x637: the client's per-frame update sends the kinds 0, 1, 2, 8, 11, 14, 24 and 27 only"
    case kind {
      24 -> {
        let assert movement_command.StateFlags(movement_state_flags.MovementStateFlags(
          flags:,
        )) = command
          as "kind 24 is the state flags"
        assert flags <= 0x3FFFF
          as "movement_command.kind_24: the client builds the flags from bits 0 to 17 only"
      }
      27 -> {
        let assert movement_command.Mode(movement_mode.MovementMode(mode:)) =
          command
          as "kind 27 is the mode"
        assert list.contains([0, 1, 3], mode)
          as "movement_command.kind_27: the client sends only the modes 0, 1 and 3"
      }
      _ -> Nil
    }
  })
  let clocks = list.map(moves, fn(move) { move.client_clock })
  assert clocks == list.sort(clocks, int.compare)
    as "opcode.0x637: the clock is the client's own millisecond clock, so a later message is not earlier"
}

pub fn the_recorded_zone_value_and_move_speed_are_what_the_client_keeps_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert [client_message.ZoneValueChanged(message: first), ..] =
    recorded_of(0x063A)
    as "the committed session holds a 0x63A"
  assert first.old_value == first.new_value
    as "opcode.0x63a: after 0x636 the client sends the value it keeps as both the old and the new"
  let assert [_, ..] = recorded_of(0x063B)
    as "the committed session holds a 0x63B"
  list.each(recorded_of(0x063B), fn(message) {
    let assert client_message.MoveSpeedSetting(message:) = message
      as "0x063B is the move speed setting"
    assert message.move_speed <= 2 as "opcode.0x63b: the setting is 0 to 2"
  })
}

pub fn the_login_session_holds_the_platform_logins_clear_requests_up_to_key_data_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert PlatformLogin(requests:, ciphered_reads:) =
    read_committed(sts_connection.rule_name)
    as "the STS connection reads as requests"
  // A read's line depends on how the network cut the client's bytes, so the
  // requests are checked in order, not by line.
  let assert [
    Decoded(sts_message.ConnectionOpened(..)),
    Decoded(sts_message.Transaction(sequence: 1, request: login_start)),
    Decoded(sts_message.Transaction(
      sequence: 2,
      request: sts_message.KeyData(..),
    )),
  ] = list.map(requests, fn(read) { read.1 })
    as "Connect, LoginStart and KeyData in the clear, in that order, and nothing else before the cipher"
  assert ciphered_reads > 0
    as "the reads after KeyData are ciphered and left unread"
  let assert sts_message.LoginStart(login_name:, ..) = login_start
    as "the second request is LoginStart"
  let assert [#(_, login), ..] =
    as_pairs(frames_of(auth_connection.rule_name).0)
    as "the auth connection holds a message"
  let assert client_message.LoginRequest(message: request) = login
    as "the auth connection's message is the login request"
  assert login_name == string.lowercase(request.account_name)
    as "LoginStart names the account in lower case (StsConnLib64.MT.dll!0x180006fb0), the login request names it as typed"
  let assert Ok(_) = guid.from_wire(request.user_id)
    as "the login request's UserId is 16 bytes"
  Nil
}

fn as_pairs(
  messages: List(Received),
) -> List(#(Int, client_message.ClientMessage)) {
  list.map(messages, fn(message) { #(message.line, message.message) })
}

pub fn the_auth_connection_holds_the_login_request_in_its_wrapper_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert #([login], []) = frames_of(auth_connection.rule_name)
    as "the auth connection holds one message and none without a decoder"
  assert login.carried == Wrapped
    as "the message is the login request, in 0x0244"
  let assert client_message.LoginRequest(message: request) = login.message
    as "the message is the login request"
  assert request.build == 16_042
    as "the client's build (fact archive_index.header)"
}

pub fn the_game_connection_holds_the_hello_reply_then_select_start_then_the_play_request_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(messages, _) = frames_of(game_connection.rule_name)
  let ids =
    list.filter_map(messages, fn(message) {
      case message.carried {
        Wrapped -> Ok(client_message.message_id(message.message))
        Bare | Inside(..) -> Error(Nil)
      }
    })
  let assert [0x058F, 0x07E0, 0x038C, ..] = ids
    as "0x058F first, then 0x07E0 and a 0x038C"
  assert list.contains(ids, 0x07DD) as "the Veteran character is played"
  let assert [first, ..] = messages as "the game connection holds messages"
  assert first.carried == Wrapped
    as "0x058F, the first message, is in a 0x0244 wrapper"
}

pub fn the_clients_pings_count_up_and_start_again_at_20_test() -> Nil {
  use <- owned_test.run(30_000)
  let numbers =
    frames_of(game_connection.rule_name).0
    |> list.filter(fn(message) {
      client_message.message_id(message.message) == ping.message_id
    })
    |> list.map(fn(message) {
      let assert Ok(Ping(sequence_number:)) = ping.decode(message.body)
        as "a ping's body decodes"
      sequence_number
    })
  assert numbers != [] as "the game connection holds pings"
  assert list.first(numbers) == Ok(0) as "the first ping is number 0"
  list.window_by_2(numbers)
  |> list.each(fn(pair) {
    assert pair.1 == { pair.0 + 1 } % 20
      as "each ping is one more than the one before, and 19 is followed by 0 (opcode.0x0: the number is below 20)"
  })
}

// ---- a changed message fails the read ----

/// The body of the login request in the committed session.
fn recorded_login_request_body() -> BitArray {
  let assert #([login], _) = frames_of(auth_connection.rule_name)
    as "the committed session's auth connection holds one message"
  login.body
}

/// The bytes of 0x0244 around the frame of `id` and `body`, ciphered under
/// `key`.
fn wrapped(id id: Int, body body: BitArray, key key: Int) -> BitArray {
  let assert Ok(chosen) = cipher.new(key:) as "the key is not 0"
  let assert Ok(bytes) =
    encrypted_frame.wrap(
      encrypted_frame.ClientWrapper,
      Frame(message_id: id, body:),
      chosen,
    )
    as "the frame is within the size limit"
  bytes
}

pub fn a_login_request_with_its_last_byte_cut_fails_naming_the_connection_the_line_and_the_message_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let body = recorded_login_request_body()
  let assert Ok(cut) = bit_array.slice(body, 0, bit_array.byte_size(body) - 1)
    as "the body is longer than one byte"
  let #(name, recording) =
    planted(folder:, rule: auth_connection.rule_name, reads: [
      wrapped(id: 0x0592, body: cut, key: cipher.base_key),
    ])
  assert wire_client_message.read(name, recording)
    == Error(NotRead(
      connection: name,
      line: 2,
      problem: NotDecoded(
        message_id: 0x0592,
        error: client_message.Malformed(
          message_id: 0x0592,
          error: bit_stream.EndOfData,
        ),
      ),
    ))
    as "the last field is whole bytes, so the cut body ends inside it"
}

pub fn a_login_request_with_one_extra_byte_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(name, recording) =
    planted(folder:, rule: auth_connection.rule_name, reads: [
      wrapped(
        id: 0x0592,
        body: <<recorded_login_request_body():bits, 0>>,
        key: cipher.base_key,
      ),
    ])
  assert wire_client_message.read(name, recording)
    == Error(NotRead(
      connection: name,
      line: 2,
      problem: NotDecoded(
        message_id: 0x0592,
        error: client_message.Malformed(
          message_id: 0x0592,
          error: bit_stream.TrailingBytes(count: 1),
        ),
      ),
    ))
    as "a body ends at its last field"
}

pub fn a_message_with_no_decoder_is_listed_and_the_read_goes_on_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(name, recording) =
    planted(folder:, rule: auth_connection.rule_name, reads: [
      wrapped(id: 0x0FFF, body: <<1, 2, 3>>, key: cipher.base_key),
      wrapped(
        id: 0x0592,
        body: recorded_login_request_body(),
        key: cipher.base_key,
      ),
    ])
  let assert Ok(Some(FramesRead(messages:, without_decoder:))) =
    wire_client_message.read(name, recording)
    as "a message the decoders do not know does not fail the read"
  assert without_decoder == [Unread(line: 2, message_id: 0x0FFF)]
    as "0x0FFF, which the schema holds no message of, is listed with its line"
  assert list.map(messages, fn(message) { message.line }) == [3]
    as "the login request after it is read"
}

pub fn a_wrapper_ciphered_under_another_key_does_not_read_as_the_message_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let body = recorded_login_request_body()
  let #(right_name, right) =
    planted(folder: folder <> "/right", rule: auth_connection.rule_name, reads: [
      wrapped(id: 0x0592, body:, key: cipher.base_key),
    ])
  let #(wrong_name, wrong) =
    planted(folder: folder <> "/wrong", rule: auth_connection.rule_name, reads: [
      wrapped(id: 0x0592, body:, key: cipher.base_key + 1),
    ])
  let assert Ok(Some(FramesRead(messages: [login], ..))) =
    wire_client_message.read(right_name, right)
    as "the login request under the base key reads"
  assert login.body == body as "it is the login request"
  assert wire_client_message.read(wrong_name, wrong)
    != Ok(Some(FramesRead(messages: [login], without_decoder: [])))
    as "the deciphered frame under another key is not the login request"
}

pub fn the_frames_after_0x058f_are_read_under_the_session_key_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let assert #([hello, ..], _) = frames_of(game_connection.rule_name)
    as "the game connection holds 0x058F first"
  let assert client_message.GameHelloReply(message: reply) = hello.message
    as "the first message is 0x058F"
  let assert Ok(session) =
    game_connection.rekeyed(session_key: reply.session_key)
    as "the session key makes a cipher"
  let hello_frame = wrapped(id: 0x058F, body: hello.body, key: cipher.base_key)
  let select = fn(cipher) {
    let assert Ok(bytes) =
      encrypted_frame.wrap(
        encrypted_frame.ClientWrapper,
        Frame(message_id: 0x07E0, body: <<>>),
        cipher,
      )
      as "the frame is within the size limit"
    bytes
  }
  let #(session_name, session_recording) =
    planted(
      folder: folder <> "/session",
      rule: game_connection.rule_name,
      reads: [<<hello_frame:bits, select(session):bits>>],
    )
  let assert Ok(Some(FramesRead(messages:, ..))) =
    wire_client_message.read(session_name, session_recording)
    as "the frames read under the session key"
  assert list.map(messages, fn(message) {
      client_message.message_id(message.message)
    })
    == [0x058F, 0x07E0]
    as "0x058F, then 0x07E0 deciphered under the session key, in one read"
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key is not 0"
  let #(base_name, base_recording) =
    planted(folder: folder <> "/base", rule: game_connection.rule_name, reads: [
      <<hello_frame:bits, select(base):bits>>,
    ])
  let assert Ok(Some(FramesRead(messages: after_hello, ..))) =
    wire_client_message.read(base_name, base_recording)
    as "the frames read"
  assert list.map(after_hello, fn(message) {
      client_message.message_id(message.message)
    })
    == [0x058F]
    as "a frame under the base key after 0x058F is no 0x07E0 under the session key"
}

pub fn a_recording_that_ends_inside_a_frame_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let whole =
    wrapped(
      id: 0x0592,
      body: recorded_login_request_body(),
      key: cipher.base_key,
    )
  let whole_bytes = bit_array.byte_size(whole)
  let assert Ok(cut) = bit_array.slice(whole, 0, whole_bytes - 1)
    as "the frame is longer than one byte"
  let #(name, recording) =
    planted(folder:, rule: auth_connection.rule_name, reads: [cut])
  assert wire_client_message.read(name, recording)
    == Error(NotRead(
      connection: name,
      line: 2,
      problem: CutShort(bytes: whole_bytes - 1),
    ))
    as "all of the frame but its last byte is there"
}

pub fn a_clear_request_after_key_data_in_the_same_read_fails_the_read_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // Every byte after the KeyData request is ciphered, so a request read in the
  // clear after it is never counted as ciphered or passed as read.
  let key_data = <<
    "POST /Auth/KeyData STS/1.0\r\ns:2\r\nl:45\r\n\r\n<Request>\n<KeyData>AAAA</KeyData>\n</Request>\n":utf8,
  >>
  let ping = <<"POST /Sts/Ping STS/1.0\r\nl:0\r\n\r\n":utf8>>
  let #(name, recording) =
    planted(folder:, rule: sts_connection.rule_name, reads: [
      <<key_data:bits, ping:bits>>,
    ])
  assert wire_client_message.read(name, recording)
    == Error(NotRead(
      connection: name,
      line: 2,
      problem: wire_client_message.ClearRequestAfterKeyData,
    ))
    as "the Ping after KeyData is reported"
}

pub fn an_unknown_platform_login_command_is_listed_and_the_read_goes_on_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(name, recording) =
    planted(folder:, rule: sts_connection.rule_name, reads: [
      <<"POST /Sts/Unknown STS/1.0\r\nl:0\r\n\r\n":utf8>>,
    ])
  assert wire_client_message.read(name, recording)
    == Ok(
      Some(PlatformLogin(
        requests: [#(2, NoDecoder(protocol: "Sts", command: "Unknown"))],
        ciphered_reads: 0,
      )),
    )
    as "the login has no command Unknown, which the rule logs as unhandled and goes on from"
}

pub fn a_connect_whose_body_is_no_connect_fails_the_read_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(name, recording) =
    planted(folder:, rule: sts_connection.rule_name, reads: [
      <<"POST /Sts/Connect STS/1.0\r\nl:5\r\n\r\nxxxxx":utf8>>,
    ])
  let assert Error(NotRead(connection:, line: 2, problem: StsMessageRefused(_))) =
    wire_client_message.read(name, recording)
    as "a Connect with no XML body is refused by the STS message decoder"
  assert connection == name as "the failure names the connection"
}

pub fn a_recording_of_a_rule_that_is_no_connection_but_took_socket_bytes_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let #(name, recording) =
    planted(folder:, rule: "genesis_prime/account_session", reads: [<<1>>])
  assert wire_client_message.read(name, recording)
    == Error(NotRead(
      connection: name,
      line: 2,
      problem: RuleNotKnown(rule: "genesis_prime/account_session"),
    ))
    as "a recording of another rule with socket bytes is reported, never passed unread"
  let #(quiet_name, quiet) =
    planted(
      folder: folder <> "/quiet",
      rule: "genesis_prime/account_session",
      reads: [],
    )
  assert wire_client_message.read(quiet_name, quiet) == Ok(None)
    as "a rule that took no socket read holds no client bytes"
}
