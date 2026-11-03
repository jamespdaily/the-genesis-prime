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
import genesis_prime/game/connection as game_connection
import genesis_prime/message/float32
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/movement_command.{type MovementCommand}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/player_movement.{PlayerMovement}
import genesis_prime/message/relayed_movement
import genesis_prime/message/server_hello
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/world_message.{WorldMessage}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import login_client
import mug

/// How long a test waits for the server to write the bytes it must, in
/// milliseconds.
const wait_ms = 5000

/// A connection that has sent 0x58F: the socket and the cipher the session
/// key made.
pub type Game {
  Game(socket: mug.Socket, cipher: Cipher)
}

/// The cipher the client keys from the session key right after sending 0x58F
/// (HandleLoginGameServerHello 0x140038120).
pub fn session_cipher(session_key session_key: BitArray) -> Cipher {
  let assert Ok(session) = game_connection.rekeyed(session_key:)
    as "the session key makes a cipher"
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
fn open(port: Int) -> mug.Socket {
  let socket = login_client.connect(port)
  let assert Ok([outer, ..]) =
    frame_reader.read(have: <<>>, count: 1, next: fn() {
      mug.receive(socket, timeout_milliseconds: wait_ms)
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
fn answer_hello(
  socket socket: mug.Socket,
  session_key session_key: BitArray,
  account_name account_name: String,
) -> Game {
  let assert Ok(Nil) =
    mug.send(socket, hello_reply(session_key:, account_name:))
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
    mug.send(game.socket, client_bytes(message_id:, body:, cipher: game.cipher))
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

/// Sends a world message as the client does: inside 0x038C, whose first byte is
/// the 5-bit value 3 of SendWorldMessage (opcode.0x38c), inside 0x244 under the
/// session cipher.
pub fn send_world(
  game game: Game,
  message_id message_id: Int,
  body body: BitArray,
) -> Nil {
  send(game:, message_id: 0x038C, body: world_body(kind: 3, message_id:, body:))
}

/// The movement command of kind 2 that puts the player at x, y, z with its
/// bit clear, as the client's movement update sends it (opcode.0x637).
pub fn position_command(x x: Float, y y: Float, z z: Float) -> MovementCommand {
  movement_command.Position(UnitPositionCommand(
    x: float32.to_bits(x),
    y: float32.to_bits(y),
    z: float32.to_bits(z),
    blends: 0,
  ))
}

/// The movement command of kind 14 that turns the player to yaw, pitch and
/// roll in radians, with its bit clear (opcode.0x637).
pub fn rotation_command(
  yaw yaw: Float,
  pitch pitch: Float,
  roll roll: Float,
) -> MovementCommand {
  movement_command.Rotation(MovementRotation(
    yaw: float32.to_bits(yaw),
    pitch: float32.to_bits(pitch),
    roll: float32.to_bits(roll),
    blends: 0,
  ))
}

/// The body of 0x0637 that holds `commands`, sent when the client's own clock
/// reads `client_clock` milliseconds (opcode.0x637).
pub fn moves_body(
  client_clock client_clock: Int,
  commands commands: List(MovementCommand),
) -> BitArray {
  let assert Ok(body) =
    player_movement.encode(PlayerMovement(client_clock:, commands:))
    as "0x0637 encodes"
  body
}

/// Reads until `count` messages have arrived from the server, each opened from
/// its 0x3DC wrapper under the session cipher, in order.
pub fn read(game game: Game, count count: Int) -> List(Frame) {
  let assert Ok(outers) =
    frame_reader.read(have: <<>>, count:, next: fn() {
      mug.receive(game.socket, timeout_milliseconds: wait_ms)
    })
    as "the game server did not write the messages"
  assert list.length(outers) == count
    as "the game server wrote no more messages than the test reads"
  list.map(outers, in_the_game_wrapper(_, game.cipher))
}

/// Reads the next message the server wrote, still inside its 0x3DC wrapper (or
/// bare, like a pong), keeping the bytes read beyond it in `have`, so a read
/// that held several messages loses none. The next call is given the bytes
/// returned.
fn next_outer(game game: Game, have have: BitArray) -> #(Frame, BitArray) {
  let assert #([outer], rest) = outers_kept(game:, have:, count: 1)
  #(outer, rest)
}

/// Reads `count` messages as the server wrote them, keeping the bytes beyond
/// them.
fn outers_kept(
  game game: Game,
  have have: BitArray,
  count count: Int,
) -> #(List(Frame), BitArray) {
  let assert Ok(kept) =
    frame_reader.read_kept(have:, count:, next: fn() {
      mug.receive(game.socket, timeout_milliseconds: wait_ms)
    })
    as "the game server did not write the messages"
  kept
}

/// Reads the next game message, opened from its 0x3DC wrapper under the session
/// cipher, keeping the bytes beyond it.
pub fn next(game game: Game, have have: BitArray) -> #(Frame, BitArray) {
  let #(outer, rest) = next_outer(game:, have:)
  #(in_the_game_wrapper(outer:, cipher: game.cipher), rest)
}

/// Reads `count` game messages in order, keeping the bytes beyond them.
pub fn read_kept(
  game game: Game,
  have have: BitArray,
  count count: Int,
) -> #(List(Frame), BitArray) {
  let #(outers, rest) = outers_kept(game:, have:, count:)
  #(list.map(outers, in_the_game_wrapper(_, game.cipher)), rest)
}

/// Takes what the server has already written, without waiting for more, and
/// drops the whole messages in it: the bytes of a message not yet whole are
/// kept, so the next read starts where the stream is. For a client that walks
/// among other players and does not read what it is sent.
pub fn drain(game game: Game, have have: BitArray) -> BitArray {
  case mug.receive(game.socket, timeout_milliseconds: 0) {
    Ok(more) ->
      drain(game:, have: whole_messages_dropped(<<have:bits, more:bits>>))
    Error(mug.Timeout) -> whole_messages_dropped(have)
    Error(error) ->
      panic as {
        "the game server's connection failed while a client drained it: "
        <> mug.describe_error(error)
      }
  }
}

fn whole_messages_dropped(received: BitArray) -> BitArray {
  let assert Ok(#(_frames, rest)) = frame_reader.decode(received:)
    as "the server wrote bytes that are frames"
  rest
}

/// Reads until the server's answer to a ping, the bare pong, and gives its
/// number: the game messages that come first, other players' units among them,
/// are dropped. The bytes beyond the pong are kept.
pub fn pong_among_messages(
  game game: Game,
  have have: BitArray,
) -> #(Int, BitArray) {
  let #(outer, rest) = next_outer(game:, have:)
  case outer {
    Frame(message_id: 0x0001, body: <<number:size(8)>>) -> #(number, rest)
    Frame(..) -> pong_among_messages(game:, have: rest)
  }
}

/// Where another player's unit stands, as the client's unit would: the last
/// kind 2 position it was given.
pub type Others =
  Dict(Int, #(Float, Float, Float))

/// What the client's view of other players holds after a message of the server:
/// 0x262 creates a unit at its first kind 2 position (0x1404586e0), 0x638 moves
/// the unit it names to each kind 2 position it carries, in order, so the last
/// is where it stands (0x140787150), a 0x638 for a unit the client does not hold
/// is dropped, as the client logs it and goes on (opcode.0x638), and 0x355
/// removes the unit (0x1403d98f0). Any other message changes nothing. The first
/// 0x262 of a connection is the player's own, so a caller keeps its model from
/// the messages after the entry's burst.
pub fn observe(others others: Others, frame frame: Frame) -> Others {
  case frame.message_id {
    0x0262 -> created(others:, body: frame.body)
    0x0638 -> moved(others:, body: frame.body)
    0x0355 -> removed(others:, body: frame.body)
    _ -> others
  }
}

fn created(others others: Others, body body: BitArray) -> Others {
  let assert Ok(unit) = unit_create_player.decode(body) as "0x0262 decodes"
  dict.insert(others, unit.unit_id, placed_at(unit:))
}

/// Where a 0x262 places its unit: the kind 2 command that is the first of its
/// commands (0x1404586e0).
pub fn placed_at(unit unit: UnitCreatePlayer) -> #(Float, Float, Float) {
  let assert [start_movement.Position(placed), ..] = unit.movement_commands
    as "0x0262 places the unit with a kind 2 command first"
  standing(placed)
}

fn moved(others others: Others, body body: BitArray) -> Others {
  let assert Ok(moved) = unit_movement.decode(body) as "0x0638 decodes"
  case dict.get(others, moved.unit_id) {
    Error(Nil) -> others
    Ok(held) ->
      dict.insert(
        others,
        moved.unit_id,
        list.fold(moved.commands, held, last_position),
      )
  }
}

/// Where a unit stands after one more command: a kind 2 puts it there, any
/// other kind leaves it.
fn last_position(
  at: #(Float, Float, Float),
  command: relayed_movement.RelayedMovement,
) -> #(Float, Float, Float) {
  case command {
    relayed_movement.Position(placed) -> standing(placed)
    relayed_movement.Platform(_)
    | relayed_movement.Velocity(_)
    | relayed_movement.MoveAsked(_)
    | relayed_movement.Rotation(_)
    | relayed_movement.StateFlags(_)
    | relayed_movement.Mode(_) -> at
  }
}

fn removed(others others: Others, body body: BitArray) -> Others {
  let assert Ok(gone) = unit_destroyed.decode(body) as "0x0355 decodes"
  dict.delete(others, gone.unit_id)
}

fn standing(
  placed: unit_position_command.UnitPositionCommand,
) -> #(Float, Float, Float) {
  let value = fn(bits) {
    let assert Ok(bits) = float32.bits(bits) as "the codec reads 32 bits"
    let assert Ok(value) = float32.value(bits)
      as "the server places a unit at a finite position"
    value
  }
  #(value(placed.x), value(placed.y), value(placed.z))
}

/// The ids of the messages that put a player in the world, in the order the
/// client needs (opcode.0xad, opcode.0x262, opcode.0x19b, opcode.0x6bc,
/// opcode.0x636, opcode.0xf1, opcode.0x61): 0xAD first; 0x262 before 0x19B; 0x19B
/// before 0x6BC, 0x636 and 0x61; then the zone channel (opcode.0x1da, opcode.0x1bc).
pub const world_entry_ids = [
  0x00AD,
  0x0262,
  0x019B,
  0x06BC,
  0x0636,
  0x00F1,
  0x0061,
  0x01DA,
  0x01BC,
]

/// The 0x262 among the messages of an entry, decoded: the player the burst
/// creates.
pub fn unit_create_player_in(frames frames: List(Frame)) -> UnitCreatePlayer {
  let assert Ok(Frame(body:, ..)) =
    list.find(frames, fn(frame) { frame.message_id == 0x0262 })
    as "the burst holds 0x0262"
  let assert Ok(player) = unit_create_player.decode(body) as "0x0262 decodes"
  player
}

/// Sends the network layer's ping with the number, bare: never wrapped and
/// never ciphered (opcode.0x0).
pub fn send_ping(game game: Game, number number: Int) -> Nil {
  let assert Ok(bytes) = frame.encode(0x0000, <<number:size(8)>>)
    as "a ping frames"
  let assert Ok(Nil) = mug.send(game.socket, bytes)
    as "the server closed the connection before the ping"
  Nil
}

/// Reads the server's answer to a ping: the bare pong and its number
/// (opcode.0x1).
pub fn read_pong(game game: Game) -> Int {
  let assert Ok([Frame(message_id: 0x0001, body: <<number:size(8)>>)]) =
    frame_reader.read(have: <<>>, count: 1, next: fn() {
      mug.receive(game.socket, timeout_milliseconds: wait_ms)
    })
    as "the game server answered the ping with one bare pong"
  number
}

/// Whether the server closes the connection within the wait: what it sends
/// meanwhile is read and dropped, and a reset counts as a close.
pub fn closed(game game: Game) -> Bool {
  case mug.receive(game.socket, timeout_milliseconds: wait_ms) {
    Ok(_) -> closed(game:)
    Error(mug.Timeout) -> False
    Error(mug.Closed) | Error(mug.Econnreset) | Error(mug.Econnaborted) -> True
    Error(error) ->
      panic as {
        "the wait for the server to close ended with "
        <> mug.describe_error(error)
      }
  }
}

/// Closes the client's end of the connection, as a client that leaves does. A
/// connection the server closed first has nothing left to close, so a failed
/// close is no failure of the test.
pub fn close(game game: Game) -> Nil {
  mug.shutdown(game.socket) |> result.unwrap(Nil)
}
