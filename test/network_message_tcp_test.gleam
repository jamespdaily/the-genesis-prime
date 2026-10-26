//// The network layer's own messages over TCP, against the real auth and game
//// listeners: the client's ping (message 0), which the server answers at once
//// with a pong (message 1) carrying the same byte, a pong from the client, and
//// the close notice (message 2). All three travel bare, never inside 0x244 and
//// never ciphered, on every connection and in every state of it (records
//// opcode.0x0, opcode.0x1, opcode.0x2; ReadMessageFrame 0x140331990 handles
//// ids 0 to 2 before any wrapper is looked at; the live login recorded in
//// test/recording/2026-10-26-login/auth-001.recording holds the client's first
//// ping on the auth connection, 07 00 00 00 00 00 00). The tests skip where
//// `GENESIS_NO_CLIENT=1`, because the server they start loads the client's
//// tables.
////
//// Every wait is for bytes the server writes, a line it logs or the socket
//// closing; the deadlines are for a server that does not answer, never a pause.

import environment
import frame_reader
import game_client
import game_server
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/login/account
import genesis_prime/login/account_store
import genesis_prime/login/handoff
import genesis_prime/message/delete_character.{DeleteCharacter}
import gleam/string
import log_capture
import login_client
import owned_test
import tcp_client.{type Client}
import template_database
import unitest

/// How long a test waits for what the server must write, in milliseconds.
const wait_ms = 5000

/// A ping with a sequence number, as the client writes it: the whole frame is
/// 7 bytes, 07 00 00 00 00 00 and the number (opcode.0x0).
fn ping(number number: Int) -> BitArray {
  <<7:size(32)-little, 0:size(16)-little, number>>
}

/// A pong with a sequence number: 07 00 00 00 01 00 and the number
/// (opcode.0x1).
fn pong(number number: Int) -> BitArray {
  <<7:size(32)-little, 1:size(16)-little, number>>
}

/// The close notice: 06 00 00 00 02 00, with an empty body (opcode.0x2).
fn close_notice() -> BitArray {
  <<6:size(32)-little, 2:size(16)-little>>
}

fn send(client client: Client, bytes bytes: BitArray) -> Nil {
  let assert Ok(Nil) = tcp_client.send(client, bytes)
    as "the server closed the connection before the client finished sending"
  Nil
}

/// The next frame the server writes, bare as the network layer's own
/// messages are.
fn next_frame(client client: Client) -> Frame {
  let assert Ok([frame]) =
    frame_reader.read(have: <<>>, count: 1, next: fn() {
      tcp_client.receive_some(client, wait_ms)
    })
    as "the server wrote no frame"
  frame
}

fn warning_about(text: String) -> fn(log_capture.Event) -> Bool {
  fn(event: log_capture.Event) {
    event.level == "warning" && string.contains(event.text, text)
  }
}

/// Starts the server and an auth connection that has read the server's hello.
fn auth_connection(running running: game_server.Running) -> Client {
  let socket = login_client.connect(running.ports.auth_port)
  let assert [hello] =
    login_client.read_frames(client: socket, have: <<>>, count: 1)
    as "the auth server did not greet the client"
  assert hello.message_id == 0x0003 as "opcode.0x3: the hello is message 3"
  socket
}

/// A game connection that has read the hello and not yet sent 0x58F.
fn game_connection_before_the_key(
  running running: game_server.Running,
) -> Client {
  game_client.open(running.game_port)
}

/// A game connection on its session key's cipher, at character select.
fn game_connection_playing(
  running running: game_server.Running,
  database database: template_database.Database,
) -> game_client.Game {
  let assert Ok(made) =
    account_store.create(database.connection, "jim", "secret")
    as "the account is created"
  let game =
    game_client.connect(
      port: running.game_port,
      session_key: handoff.issue(running.session_keys, account.identity(made)),
      account_name: "jim",
    )
  game_client.send(game:, message_id: 0x07E0, body: <<>>)
  let assert [_listed] = game_client.read(game:, count: 1)
    as "the character list, so the connection plays"
  game
}

pub fn a_ping_on_the_auth_connection_is_answered_with_the_echoing_pong_and_the_connection_stays_open_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let socket = auth_connection(running:)
  send(client: socket, bytes: ping(number: 0))
  let first = next_frame(client: socket)
  assert first.message_id == 1 && first.body == <<0>>
    as "opcode.0x0, opcode.0x1: a ping is answered at once with a pong, bare, that echoes its byte (ReadMessageFrame 0x140331990)"
  send(client: socket, bytes: ping(number: 19))
  let second = next_frame(client: socket)
  assert second.message_id == 1 && second.body == <<19>>
    as "opcode.0x1: the pong carries the ping's own number, here the largest, 19; the connection stayed open for the second ping"
}

pub fn a_ping_on_the_game_connection_before_the_session_key_is_answered_with_the_echoing_pong_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let socket = game_connection_before_the_key(running:)
  send(client: socket, bytes: ping(number: 7))
  let answer = next_frame(client: socket)
  assert answer.message_id == 1 && answer.body == <<7>>
    as "opcode.0x0, opcode.0x1: the client pings every connection, the game connection before its 0x58F included, and the pong is bare"
}

pub fn a_ping_on_the_game_connection_at_character_select_is_answered_with_the_echoing_pong_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let game = game_connection_playing(running:, database:)
  send(client: game.socket, bytes: ping(number: 3))
  let answer = next_frame(client: game.socket)
  assert answer.message_id == 1 && answer.body == <<3>>
    as "opcode.0x0, opcode.0x1: the ping is bare and never ciphered, so the pong is too, under the session key's cipher as before it"
  let assert Ok(delete) =
    delete_character.encode(DeleteCharacter(character_id: 1))
    as "0x352 encodes"
  game_client.send(game:, message_id: 0x0352, body: delete)
  let assert [deleted] = game_client.read(game:, count: 1)
    as "the connection plays on: the cipher's stream was not touched by the ping, so the next request is read and answered"
  assert deleted.message_id == 0x00E6
    as "opcode.0xe6: a delete the account cannot make is answered with 0xE6"
}

pub fn a_ping_with_a_number_of_20_ends_the_auth_connection_and_logs_the_reason_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let capture = log_capture.start()
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let socket = auth_connection(running:)
  send(client: socket, bytes: ping(number: 20))
  assert tcp_client.await_close(socket, wait_ms)
    as "opcode.0x0: the number is 0 to 19 (SendNetworkPings takes it mod 20), so the client never sends 20 and the server ends the connection"
  let assert Ok(_) =
    log_capture.next_matching(
      capture:,
      within: wait_ms,
      matching: warning_about("sequence_number"),
    )
    as "the reason is logged as a warning, naming the field"
  Nil
}

pub fn a_ping_with_a_number_of_20_ends_the_game_connection_and_logs_the_reason_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let capture = log_capture.start()
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let socket = game_connection_before_the_key(running:)
  send(client: socket, bytes: ping(number: 20))
  assert tcp_client.await_close(socket, wait_ms)
    as "opcode.0x0: the number is 0 to 19, so the client never sends 20 and the server ends the connection"
  let assert Ok(_) =
    log_capture.next_matching(
      capture:,
      within: wait_ms,
      matching: warning_about("sequence_number"),
    )
    as "the reason is logged as a warning, naming the field"
  Nil
}

pub fn the_close_notice_and_a_pong_get_no_reply_on_the_auth_connection_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let socket = auth_connection(running:)
  send(client: socket, bytes: close_notice())
  send(client: socket, bytes: pong(number: 5))
  send(client: socket, bytes: ping(number: 9))
  let answer = next_frame(client: socket)
  assert answer.message_id == 1 && answer.body == <<9>>
    as "opcode.0x2, opcode.0x1: a close notice and a pong are accepted and answered with nothing, so the first frame the server writes is the pong of the ping after them"
}

pub fn the_close_notice_and_a_pong_get_no_reply_on_the_game_connection_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
  use database <- template_database.run
  let running = game_server.start(database:, answer_deadline_ms: 5000)
  let socket = game_connection_before_the_key(running:)
  send(client: socket, bytes: close_notice())
  send(client: socket, bytes: pong(number: 5))
  send(client: socket, bytes: ping(number: 9))
  let answer = next_frame(client: socket)
  assert answer.message_id == 1 && answer.body == <<9>>
    as "opcode.0x2, opcode.0x1: a close notice and a pong are accepted and answered with nothing, so the first frame the server writes is the pong of the ping after them"
}
