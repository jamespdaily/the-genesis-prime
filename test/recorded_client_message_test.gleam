//// Every message the real client sent in a saved rule recording decodes with
//// the server's decoders, and a changed message fails the read, naming the
//// recording, the input and the message. Expected values come from these
//// places.
//// - The recordings in `test/rule_recording/2026-11-01-full-session`: a live
////   login of the real client through the STS, auth and game servers. Their
////   socket reads, as the inputs of each connection's rule: the STS
////   connection's reads 1, 2 and 4 are the clear requests Connect, LoginStart
////   and KeyData, and its reads 5, 7, 8, 9, 10 and 11 (90, 195, 227, 208, 31 and 208 bytes) are
////   ciphered; the auth connection's read 1 is one login request in its
////   wrapper; the game connection's read 1 holds 0x058F, 0x07E0 and a 0x038C,
////   all under the session key after the first.
//// - The log lines the game rule wrote while it took those reads, kept in the
////   recording: one "unhandled game message" line for each message the rule
////   took and did not handle, which are the world messages inside 0x038C
////   (opcode.0x38c: the inner message is logged under its own id).
//// - Ping numbers are below 20 (opcode.0x0), and the client counts them up.
//// - The build in the login request is the client's (fact
////   archive_index.header).
//// - The layout of the login request in the schema (opcode.0x592): a build of
////   32 bits first, its last field a whole number of bytes, and the bit
////   stream's rule that a body ends at its last field.
//// - The cipher: the base key keys the auth connection and each new game
////   connection, and the session key folded from the 16 bytes of 0x058F
////   re-keys the game connection (vector.0x14003827c.session_fold).

import connection_rule_support
import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/login/sts_message
import genesis_prime/message/bit_stream
import genesis_prime/message/client_message
import genesis_prime/message/ping.{Ping}
import genesis_prime/rule_recording.{End, Header, Taken}
import genesis_prime/step.{Effects, Input, Now, Socket}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import recorded_client_message.{
  type ClientBytes, type Received, type Unread, Bare, ClearRequestAfterKeyData,
  CutShort, FramesRead, Inside, NotARecording, NotDecoded, NotRead, RuleNotKnown,
  StsMessageRefused, StsRead, Unread, Wrapped,
}
import recording_support
import rule_replay_support
import simplifile

const sts_file = "genesis_prime.login.sts_connection-3.recording"

const auth_file = "genesis_prime.login.auth_connection-4.recording"

const game_file = "genesis_prime.game.connection-5.recording"

fn read(file: String) -> ClientBytes {
  let assert Ok(Some(read)) =
    recorded_client_message.read_recording(rule_replay_support.folder <> file)
    as { file <> " holds client bytes and they read" }
  read
}

fn frames(file: String) -> #(List(Received), List(Unread)) {
  let assert FramesRead(messages:, without_decoder:) = read(file)
    as { file <> " is a connection of frames" }
  #(messages, without_decoder)
}

pub fn every_client_message_in_every_saved_rule_recording_decodes_test() -> Nil {
  use <- owned_test.run(30_000)
  let results = recorded_client_message.read_folder(rule_replay_support.folder)
  list.each(results, fn(entry) {
    let #(path, read) = entry
    assert result.replace(read, Nil) == Ok(Nil)
      as { "every client message in " <> path <> " reads" }
  })
  let held =
    list.filter_map(results, fn(entry) {
      case entry.1 {
        Ok(Some(read)) -> Ok(read)
        Ok(None) | Error(_) -> Error(Nil)
      }
    })
  assert list.length(held) == 3
    as "the session holds one recording each of the STS, auth and game connections with client bytes; the Sessions and map recordings take none"
}

pub fn every_decoded_message_encodes_back_to_the_body_the_client_sent_test() -> Nil {
  use <- owned_test.run(30_000)
  let messages =
    list.flat_map([auth_file, game_file], fn(file) { frames(file).0 })
  assert messages != [] as "the recordings hold messages"
  list.each(messages, fn(message) {
    assert client_message.encode(message.message) == Ok(message.body)
      as {
        "input "
        <> int.to_string(message.input)
        <> ": a decoded message encodes to the body the client sent, so every bit of it was read"
      }
  })
}

pub fn the_login_session_holds_the_platform_logins_three_clear_requests_and_its_ciphered_rest_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert StsRead(requests:, ciphered_bytes:) = read(sts_file)
    as "the STS connection reads as requests"
  let assert [
    #(1, sts_message.ConnectionOpened(..)),
    #(2, sts_message.Transaction(sequence: 1, request: login_start)),
    #(4, sts_message.Transaction(sequence: 2, request: sts_message.KeyData(..))),
  ] = requests
    as "Connect, LoginStart and KeyData, in reads 1, 2 and 4"
  let assert sts_message.LoginStart(login_name:, ..) = login_start
    as "the second request is LoginStart"
  let assert [#(_, game_hello), ..] = frames(auth_file).0 |> as_pairs
    as "the auth connection holds a message"
  let assert client_message.LoginRequest(message: request) = game_hello
    as "the auth connection's message is the login request"
  assert login_name == string.lowercase(request.account_name)
    as "LoginStart names the account in lower case (StsConnLib64.MT.dll!0x180006fb0), the login request names it as typed"
  assert ciphered_bytes == 90 + 195 + 227 + 208 + 31 + 208
    as "the six reads after the KeyData request are ciphered"
}

fn as_pairs(
  messages: List(Received),
) -> List(#(Int, client_message.ClientMessage)) {
  list.map(messages, fn(message) { #(message.input, message.message) })
}

pub fn the_auth_connection_holds_the_login_request_in_its_wrapper_test() -> Nil {
  use <- owned_test.run(30_000)
  let assert #([login], []) = frames(auth_file)
    as "the auth connection holds one message and none without a decoder"
  assert login.input == 1 && login.carried == Wrapped
    as "read 1 holds the login request in 0x0244"
  let assert client_message.LoginRequest(message: request) = login.message
    as "the message is the login request"
  assert request.build == 16_042
    as "the client's build (fact archive_index.header)"
}

pub fn the_game_connection_holds_the_hello_reply_then_select_start_then_the_play_request_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(messages, _) = frames(game_file)
  let ids =
    list.filter_map(messages, fn(message) {
      case message.carried {
        Wrapped -> Ok(client_message.message_id(message.message))
        Bare | Inside(..) -> Error(Nil)
      }
    })
  let assert [0x058F, 0x07E0, 0x038C, ..] = ids
    as "0x058F first, then 0x07E0 and a 0x038C, all in read 1"
  assert list.count(ids, fn(id) { id == 0x07DD }) == 1
    as "the Veteran character is played once"
  let assert [first, ..] = messages as "the game connection holds messages"
  assert first.input == 1 && first.carried == Wrapped
    as "0x058F is in read 1 (Accepted is input 0)"
}

pub fn the_clients_pings_count_up_and_start_again_at_20_test() -> Nil {
  use <- owned_test.run(30_000)
  let numbers =
    frames(game_file).0
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

pub fn the_messages_the_decoders_do_not_know_are_the_ones_the_rule_logged_as_unhandled_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(messages, without_decoder) = frames(game_file)
  let unhandled_ids =
    list.append(
      list.map(without_decoder, fn(unread) { unread.message_id }),
      list.filter_map(messages, fn(message) {
        case message.carried {
          Inside(carrier: 0x038C) ->
            Ok(client_message.message_id(message.message))
          Inside(..) | Bare | Wrapped -> Error(Nil)
        }
      }),
    )
  let logged = logged_unhandled_ids(game_file)
  assert logged != [] as "the game rule logged unhandled messages"
  assert list.sort(unhandled_ids, int.compare) == logged
    as "each message inside a 0x038C, the ones with a decoder and the ones without, is a message the game rule logged as unhandled, and no other message is"
  assert list.map(without_decoder, fn(unread) { unread.message_id })
    |> list.unique
    |> list.sort(int.compare)
    == [
      0x00D5, 0x012B, 0x018F, 0x023C, 0x023D, 0x0269, 0x03EC, 0x03ED, 0x0570,
      0x0637, 0x063A, 0x063B, 0x07CC, 0x07EA, 0x082D,
    ]
    as "the ids the recording's unhandled lines name, but 0x00F2 and 0x0635, which the schema has layouts for (opcode.0xf2, opcode.0x635)"
}

/// The id of each message the game rule logged as unhandled while it took the
/// recording's inputs, sorted.
fn logged_unhandled_ids(file: String) -> List(Int) {
  let assert Ok(bytes) =
    simplifile.read_bits(rule_replay_support.folder <> file)
    as "the recording reads"
  let assert Ok(#(_, records)) = rule_recording.read(bytes)
    as "the recording is a recording"
  records
  |> list.flat_map(fn(record) {
    case record {
      Taken(step: recorded, ..) -> connection_rule_support.logs(recorded)
      End(..) -> []
    }
  })
  |> list.filter_map(fn(line) {
    case line.about.message {
      Some(#("unhandled", id)) -> Ok(id)
      Some(_) | None -> Error(Nil)
    }
  })
  |> list.sort(int.compare)
}

// ---- a changed message fails the read ----

pub fn a_login_request_with_its_last_byte_cut_fails_naming_the_recording_the_input_and_the_message_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let body = recorded_login_request_body()
  let assert Ok(cut) = bit_array.slice(body, 0, bit_array.byte_size(body) - 1)
    as "the body is longer than one byte"
  let path =
    plant(folder:, number: 1, rule: auth_connection.rule_name, reads: [
      wrapped(id: 0x0592, body: cut, key: cipher.base_key),
    ])
  assert recorded_client_message.read_recording(path)
    == Error(NotRead(
      recording: path,
      input: 0,
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
  let path =
    plant(folder:, number: 1, rule: auth_connection.rule_name, reads: [
      wrapped(
        id: 0x0592,
        body: <<recorded_login_request_body():bits, 0>>,
        key: cipher.base_key,
      ),
    ])
  assert recorded_client_message.read_recording(path)
    == Error(NotRead(
      recording: path,
      input: 0,
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
  let path =
    plant(folder:, number: 1, rule: auth_connection.rule_name, reads: [
      wrapped(id: 0x0637, body: <<1, 2, 3>>, key: cipher.base_key),
      wrapped(
        id: 0x0592,
        body: recorded_login_request_body(),
        key: cipher.base_key,
      ),
    ])
  let assert Ok(Some(FramesRead(messages:, without_decoder:))) =
    recorded_client_message.read_recording(path)
    as "a message the decoders do not know does not fail the read"
  assert without_decoder == [Unread(input: 0, message_id: 0x0637)]
    as "0x0637 is listed with its input"
  assert list.map(messages, fn(message) { message.input }) == [1]
    as "the login request after it is read"
}

pub fn a_wrapper_ciphered_under_another_key_does_not_read_as_the_message_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let body = recorded_login_request_body()
  let right =
    plant(folder:, number: 1, rule: auth_connection.rule_name, reads: [
      wrapped(id: 0x0592, body:, key: cipher.base_key),
    ])
  let wrong =
    plant(folder:, number: 2, rule: auth_connection.rule_name, reads: [
      wrapped(id: 0x0592, body:, key: cipher.base_key + 1),
    ])
  let assert Ok(Some(FramesRead(messages: [login], ..))) =
    recorded_client_message.read_recording(right)
    as "the login request under the base key reads"
  assert login.body == body as "it is the login request"
  assert result.map(recorded_client_message.read_recording(wrong), fn(read) {
      read == Some(FramesRead(messages: [login], without_decoder: []))
    })
    != Ok(True)
    as "the deciphered frame under another key is not the login request"
}

pub fn the_frames_after_0x058f_are_read_under_the_session_key_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let assert #([hello, ..], _) = frames(game_file)
    as "the game connection holds 0x058F first"
  let assert client_message.GameHelloReply(message: reply) = hello.message
    as "the first message is 0x058F"
  let assert Ok(folded) =
    cipher.session_key(bytes: reply.session_key, base_key: cipher.base_key)
    as "the session key is 16 bytes"
  let assert Ok(session) = cipher.new(folded) as "the folded key is not 0"
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
  let session_path =
    plant(folder:, number: 1, rule: game_connection.rule_name, reads: [
      <<hello_frame:bits, select(session):bits>>,
    ])
  let assert Ok(Some(FramesRead(messages:, ..))) =
    recorded_client_message.read_recording(session_path)
    as "the frames read under the session key"
  assert list.map(messages, fn(message) {
      client_message.message_id(message.message)
    })
    == [0x058F, 0x07E0]
    as "0x058F, then 0x07E0 deciphered under the session key, in one read"
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key is not 0"
  let base_path =
    plant(folder:, number: 2, rule: game_connection.rule_name, reads: [
      <<hello_frame:bits, select(base):bits>>,
    ])
  let assert Ok(Some(FramesRead(messages: after_hello, ..))) =
    recorded_client_message.read_recording(base_path)
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
  let assert Ok(cut) = bit_array.slice(whole, 0, 391)
    as "the recorded 0x0244 is 392 bytes"
  let auth =
    plant(folder:, number: 1, rule: auth_connection.rule_name, reads: [cut])
  assert recorded_client_message.read_recording(auth)
    == Error(NotRead(recording: auth, input: 0, problem: CutShort(bytes: 391)))
    as "391 of the frame's 392 bytes are there"
}

pub fn a_clear_request_after_key_data_in_the_same_read_fails_the_read_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  // Every byte after the KeyData request is ciphered, so a request read in
  // the clear after it is never counted as ciphered or passed as read.
  let key_data = <<
    "POST /Auth/KeyData STS/1.0\r\ns:2\r\nl:45\r\n\r\n<Request>\n<KeyData>AAAA</KeyData>\n</Request>\n":utf8,
  >>
  let ping = <<"POST /Sts/Ping STS/1.0\r\nl:0\r\n\r\n":utf8>>
  let path =
    plant(folder:, number: 1, rule: sts_connection.rule_name, reads: [
      <<key_data:bits, ping:bits>>,
    ])
  assert recorded_client_message.read_recording(path)
    == Error(NotRead(
      recording: path,
      input: 0,
      problem: ClearRequestAfterKeyData,
    ))
    as "the Ping after KeyData is reported"
}

pub fn an_unknown_platform_login_command_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let path =
    plant(folder:, number: 1, rule: sts_connection.rule_name, reads: [
      <<"POST /Sts/Unknown STS/1.0\r\nl:0\r\n\r\n":utf8>>,
    ])
  assert recorded_client_message.read_recording(path)
    == Error(NotRead(
      recording: path,
      input: 0,
      problem: StsMessageRefused(sts_message.UnknownCommand(
        protocol: "Sts",
        command: "Unknown",
      )),
    ))
    as "the login has no command Unknown"
}

pub fn a_recording_of_a_rule_that_is_no_connection_but_took_socket_bytes_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let path =
    plant(folder:, number: 1, rule: "genesis_prime/sessions", reads: [<<1>>])
  assert recorded_client_message.read_recording(path)
    == Error(NotRead(
      recording: path,
      input: 0,
      problem: RuleNotKnown(rule: "genesis_prime/sessions"),
    ))
    as "a recording of another rule with socket bytes is reported, never passed unread"
}

pub fn a_file_that_is_no_recording_fails_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let path = folder <> "/genesis_prime.login.auth_connection-1.recording"
  let assert Ok(Nil) = simplifile.write_bits(path, <<1, 2, 3>>)
    as "the file was written"
  let assert Error(NotARecording(recording:, ..)) =
    recorded_client_message.read_recording(path)
    as "three bytes are no recording"
  assert recording == path as "the failure names the file"
}

// ---- helpers ----

/// The body of the login request in the saved login session.
fn recorded_login_request_body() -> BitArray {
  let assert #([login], _) = frames(auth_file)
    as "the saved login session's auth connection holds one message"
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

/// Writes a recording of `rule` in `folder`, whose inputs are the socket
/// reads `reads`, and returns its path.
fn plant(
  folder folder: String,
  number number: Int,
  rule rule: String,
  reads reads: List(BitArray),
) -> String {
  let path =
    folder
    <> "/"
    <> string.replace(rule, "/", ".")
    <> "-"
    <> int.to_string(number)
    <> ".recording"
  let header =
    Header(
      format: rule_recording.format,
      rule:,
      client_build: 16_042,
      tables_digest: None,
      settings: Nil,
      types_digest: "planted",
    )
  let taken =
    list.map(reads, fn(bytes) {
      rule_recording.encode(Taken(
        input: Input(
          now: Now(monotonic_ms: 0, filetime: 0),
          event: Socket(step.Read(bytes:)),
        ),
        step: Effects([]),
      ))
    })
  let encoded =
    bit_array.concat([
      rule_recording.encode(header),
      ..list.append(taken, [
        rule_recording.encode(End(count: list.length(reads))),
      ])
    ])
  let assert Ok(Nil) = simplifile.write_bits(path, encoded)
    as "the planted recording was written"
  path
}
