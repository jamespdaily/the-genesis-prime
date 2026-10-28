//// A scripted client's side of a game connection, over TCP against the game
//// listener: the hello it reads, the 0x58F it answers with, the cipher it keys
//// from the session key, and the messages it sends and reads after that. It is
//// written from the fact file's records (opcode.0x3, opcode.0x58f,
//// opcode.0x244, opcode.0x3dc, opcode.0x25c, opcode.0x38c) and shares only the
//// message codec, the frame and the cipher with the server, each tested
//// against the client's own vectors.
////
//// The client reads the server's hello inside 0x3DC under the base key, sends
//// 0x58F inside 0x244 under the base key, and keys its cipher from the session
//// key right after sending it (HandleLoginGameServerHello 0x140038120). Every
//// message after that goes inside 0x244 under the session key's cipher, and
//// every message from the server arrives inside 0x3DC under it.

import frame_reader
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{ClientWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/server_hello
import genesis_prime/message/world_message.{WorldMessage}
import gleam/list
import tcp_client.{type Client}

/// How long a test waits for the server to write the bytes it must, in
/// milliseconds.
const wait_ms = 5000

/// A connection that has sent 0x58F: the socket and the cipher the session
/// key made.
pub type Game {
  Game(socket: Client, cipher: Cipher)
}

/// The cipher the client keys from the session key right after sending 0x58F
/// (HandleLoginGameServerHello 0x140038120).
pub fn session_cipher(session_key session_key: BitArray) -> Cipher {
  let assert Ok(key) = cipher.session_key(session_key, cipher.base_key)
    as "the session key is 16 bytes"
  let assert Ok(session) = cipher.new(key) as "the session key makes a cipher"
  session
}

/// The bytes the client writes for a message: its frame inside 0x244 under
/// `cipher`.
pub fn client_bytes(
  message_id message_id: Int,
  body body: BitArray,
  cipher cipher: Cipher,
) -> BitArray {
  let assert Ok(bytes) =
    encrypted_frame.wrap(ClientWrapper, Frame(message_id, body), cipher)
    as "the message wraps"
  bytes
}

/// The body of 0x58F: the value from the hand-off (0), the 16-byte session
/// key, a 64-bit 0, the account name and the 32-bit 3 (opcode.0x58f).
pub fn hello_reply_body(
  session_key session_key: BitArray,
  account_name account_name: String,
) -> BitArray {
  let assert Ok(body) =
    game_hello_reply.encode(GameHelloReply(
      field_1: 0,
      session_key:,
      field_3: 0,
      account_name:,
      field_5: 3,
    ))
    as "0x58F encodes"
  body
}

/// The bytes of 0x58F inside 0x244 under the base key.
pub fn hello_reply(
  session_key session_key: BitArray,
  account_name account_name: String,
) -> BitArray {
  client_bytes(
    message_id: game_hello_reply.message_id,
    body: hello_reply_body(session_key:, account_name:),
    cipher: cipher.base(),
  )
}

/// The message inside a 0x3DC frame the server wrote, opened under `cipher`.
pub fn in_the_game_wrapper(outer outer: Frame, cipher cipher: Cipher) -> Frame {
  assert outer.message_id == 0x03DC
    as "opcode.0x3dc: every game server message arrives inside 0x3DC"
  let assert Ok(inner) = encrypted_frame.unwrap(outer, cipher)
    as "the message opens under the cipher"
  inner
}

/// Connects to the game listener and reads its hello: message 3 inside 0x3DC
/// under the base key, with the build and the message table checksum the client
/// checks (opcode.0x3).
pub fn open(port: Int) -> Client {
  let assert Ok(socket) = tcp_client.connect(port)
    as "the client could not connect to the game listener"
  let assert Ok([outer, ..]) =
    frame_reader.read(have: <<>>, count: 1, next: fn() {
      tcp_client.receive_some(socket, wait_ms)
    })
    as "the game server did not greet the client"
  assert outer.message_id == 0x03DC
    as "opcode.0x3dc: the game server's hello arrives inside 0x3DC"
  let assert Ok(hello) = encrypted_frame.unwrap(outer, cipher.base())
    as "the hello opens under the base key, which the game connection holds until 0x58F"
  assert hello.message_id == 0x0003 as "opcode.0x3: the hello is message 3"
  let assert Ok(decoded) = server_hello.decode(hello.body)
    as "the hello decodes"
  assert decoded.build == 16_042 && decoded.message_table_checksum == 0x097998A0
    as "opcode.0x3: the client checks build 16042 and checksum 0x097998A0"
  socket
}

/// Answers the hello with 0x58F inside 0x244 under the base key, then keys
/// the cipher from the session key.
pub fn answer_hello(
  socket socket: Client,
  session_key session_key: BitArray,
  account_name account_name: String,
) -> Game {
  let assert Ok(Nil) =
    tcp_client.send(socket, hello_reply(session_key:, account_name:))
    as "the server closed the connection before 0x58F"
  Game(socket:, cipher: session_cipher(session_key:))
}

/// Connects, reads the hello and answers it.
pub fn connect(
  port port: Int,
  session_key session_key: BitArray,
  account_name account_name: String,
) -> Game {
  answer_hello(socket: open(port), session_key:, account_name:)
}

/// Sends a message inside 0x244 under the session cipher.
pub fn send(
  game game: Game,
  message_id message_id: Int,
  body body: BitArray,
) -> Nil {
  let assert Ok(Nil) =
    tcp_client.send(
      game.socket,
      client_bytes(message_id:, body:, cipher: game.cipher),
    )
    as "the server closed the connection before the message"
  Nil
}

/// Sends a create-character request the way LuaCreateCharacter does: the 0x25B
/// frame goes into 0x25C as plain bytes, and the whole 0x25C frame is ciphered
/// once, after its length, inside 0x244 (opcode.0x25c; LuaCreateCharacter
/// 0x140023e90, the one cipher call 0x140024b0c).
pub fn send_create(game game: Game, body body: BitArray) -> Nil {
  let assert Ok(plain) = frame.encode(0x025B, body) as "0x25B frames"
  send(game:, message_id: 0x025C, body: plain)
}

/// Sends a world message the way SendWorldMessage does: its whole frame inside
/// 0x38C with the 5-bit value 3, inside 0x244 (opcode.0x38c).
pub fn send_world(
  game game: Game,
  message_id message_id: Int,
  body body: BitArray,
) -> Nil {
  send(
    game:,
    message_id: world_message.message_id,
    body: world_body(kind: 3, message_id:, body:),
  )
}

/// The body of 0x38C that carries a world message: its 5-bit value `kind` and
/// the message's whole frame (opcode.0x38c).
pub fn world_body(
  kind kind: Int,
  message_id message_id: Int,
  body body: BitArray,
) -> BitArray {
  let assert Ok(inner) = frame.encode(message_id, body) as "the message frames"
  let assert Ok(carried) =
    world_message.encode(WorldMessage(field_1: kind, inner_frame: inner))
    as "0x38C encodes"
  carried
}

/// Reads until `count` messages have arrived from the server, each opened from
/// its 0x3DC wrapper under the session cipher, in order.
pub fn read(game game: Game, count count: Int) -> List(Frame) {
  let assert Ok(outers) =
    frame_reader.read(have: <<>>, count:, next: fn() {
      tcp_client.receive_some(game.socket, wait_ms)
    })
    as "the game server did not write the messages"
  assert list.length(outers) == count
    as "the game server wrote no more messages than the test reads"
  list.map(outers, in_the_game_wrapper(_, game.cipher))
}

/// Whether the server closes the connection within the wait.
pub fn closed(game game: Game) -> Bool {
  tcp_client.await_close(game.socket, wait_ms)
}

/// Closes the client's end of the connection, as a client that leaves does.
pub fn close(game game: Game) -> Nil {
  tcp_client.close(game.socket)
}
