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
import genesis_prime/game/area.{Point}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/ability_hold
import genesis_prime/message/ability_tiers
import genesis_prime/message/action_set
import genesis_prime/message/bit_stream
import genesis_prime/message/cast_ability
import genesis_prime/message/cast_result
import genesis_prime/message/chat_channel_joined
import genesis_prime/message/chat_line
import genesis_prime/message/chat_line_accepted.{type ChatLineAccepted}
import genesis_prime/message/float32
import genesis_prime/message/game_hello_reply.{GameHelloReply}
import genesis_prime/message/item_added
import genesis_prime/message/movement_command.{type MovementCommand}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/player_health
import genesis_prime/message/player_movement.{PlayerMovement}
import genesis_prime/message/relayed_movement
import genesis_prime/message/send_chat_line.{SendChatLine}
import genesis_prime/message/send_whisper.{SendWhisper}
import genesis_prime/message/server_hello
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_effect_info
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_missed
import genesis_prime/message/spell_started
import genesis_prime/message/spell_threshold_closed
import genesis_prime/message/spell_threshold_ended
import genesis_prime/message/spell_threshold_index
import genesis_prime/message/spell_threshold_opened
import genesis_prime/message/start_movement
import genesis_prime/message/static_unit_type
import genesis_prime/message/unit_combat_state
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_create_static.{type UnitCreateStatic}
import genesis_prime/message/unit_create_tail.{type UnitCreateTail}
import genesis_prime/message/unit_death_state
import genesis_prime/message/unit_destroyed
import genesis_prime/message/unit_health
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_target
import genesis_prime/message/unit_threat
import genesis_prime/message/world_message.{WorldMessage}
import genesis_prime/table/game_formula
import genesis_prime/table/id.{GameFormulaId}
import genesis_prime/table/loader/store as table_store
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/list
import gleam/option.{type Option}
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

/// Presses the ability held at `bag_index`, as the client's action bar does
/// (opcode.0x9a): its own cast id, the bag index, the target (0 for none) and the
/// press bit 1.
pub fn press_ability(
  game game: Game,
  client_cast_id client_cast_id: Int,
  bag_index bag_index: Int,
  target target: Int,
) -> Nil {
  send_world(
    game:,
    message_id: cast_ability.message_id,
    body: press_body(client_cast_id:, bag_index:, target:, press: 1),
  )
}

/// The body of the client's 0x9a (opcode.0x9a): its cast id, the bag index, the
/// target and the press bit.
pub fn press_body(
  client_cast_id client_cast_id: Int,
  bag_index bag_index: Int,
  target target: Int,
  press press: Int,
) -> BitArray {
  let assert Ok(body) =
    cast_ability.encode(cast_ability.CastAbility(
      client_cast_id:,
      bag_index:,
      target_unit_id: target,
      press:,
    ))
    as "a press fits the message"
  body
}

/// Presses (`held` 1) or releases (`held` 0) the key of the ability held at
/// `bag_index`, as the client's action bar does under its default hold-to-continue
/// setting (opcode.0x4db): no cast id of its own, the bag index, the target (0 for
/// none) and the held bit.
pub fn hold_ability(
  game game: Game,
  bag_index bag_index: Int,
  target target: Int,
  held held: Int,
) -> Nil {
  send_world(
    game:,
    message_id: ability_hold.message_id,
    body: hold_body(bag_index:, target:, held:),
  )
}

/// The body of the client's 0x4db (opcode.0x4db): the bag index, the target and
/// the held bit.
pub fn hold_body(
  bag_index bag_index: Int,
  target target: Int,
  held held: Int,
) -> BitArray {
  let assert Ok(body) =
    ability_hold.encode(ability_hold.AbilityHold(
      bag_index:,
      target_unit_id: target,
      held:,
    ))
    as "a hold fits the message"
  body
}

/// What the client's reader makes of a cast message of the server's.
pub type CastEvent {
  /// 0x7fc: the press with this client id was refused with this result
  /// (opcode.0x7fc).
  CastRefused(client_cast_id: Int, spell4_id: Int, result: Int)
  /// 0x7fd: the press was accepted and has this server id (opcode.0x7fd).
  CastConfirmed(client_cast_id: Int, server_cast_id: Int)
  /// 0x7ff: a unit starts a cast, with its root and parent (opcode.0x7ff).
  CastStarted(
    cast_id: Int,
    spell4_id: Int,
    root_spell4_id: Int,
    parent_spell4_id: Int,
    caster_unit_id: Int,
  )
  /// 0x7f4: a cast goes off, in this phase (opcode.0x7f4).
  CastWent(cast_id: Int, phase: Int)
  /// 0x7fe: a cast ends (opcode.0x7fe).
  CastFinished(cast_id: Int)
  /// 0x816: a threshold opens for the spell, with the value the client sends back
  /// in a 0x801 (opcode.0x816).
  ThresholdOpened(spell4_id: Int, cancel_cast_id: Int)
  /// 0x817: the open threshold's index is set (opcode.0x817).
  ThresholdIndex(spell4_id: Int, index: Int)
  /// 0x814: the threshold closes, starting the cooldowns when the bit is set
  /// (opcode.0x814).
  ThresholdClosed(spell4_id: Int, start_cooldowns: Int)
  /// 0x815: the threshold ends (opcode.0x815).
  ThresholdEnded(spell4_id: Int)
}

/// The cast messages among the frames, in order, each as the client's reader
/// takes it; every other frame is skipped.
pub fn casts_in(frames frames: List(Frame)) -> List(CastEvent) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x07FC -> {
        let assert Ok(refused) = spell_cast_refused.decode(frame.body)
          as "0x7fc decodes"
        Ok(CastRefused(
          client_cast_id: refused.client_cast_id,
          spell4_id: refused.spell4_id,
          result: cast_result.to_value(refused.result),
        ))
      }
      0x07FD -> {
        let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
          as "0x7fd decodes"
        Ok(CastConfirmed(
          client_cast_id: confirmed.client_cast_id,
          server_cast_id: confirmed.server_cast_id,
        ))
      }
      0x07FF -> {
        let assert Ok(started) = spell_started.decode(frame.body)
          as "0x7ff decodes"
        Ok(CastStarted(
          cast_id: started.cast_id,
          spell4_id: started.spell4_id,
          root_spell4_id: started.root_spell4_id,
          parent_spell4_id: started.parent_spell4_id,
          caster_unit_id: started.caster_unit_id,
        ))
      }
      0x07F4 -> {
        let assert Ok(go) = spell_go.decode(frame.body) as "0x7f4 decodes"
        Ok(CastWent(cast_id: go.cast_id, phase: go.phase))
      }
      0x07FE -> {
        let assert Ok(finished) = spell_finished.decode(frame.body)
          as "0x7fe decodes"
        Ok(CastFinished(cast_id: finished.cast_id))
      }
      0x0816 -> {
        let assert Ok(opened) = spell_threshold_opened.decode(frame.body)
          as "0x816 decodes"
        Ok(ThresholdOpened(
          spell4_id: opened.spell4_id,
          cancel_cast_id: opened.cancel_cast_id,
        ))
      }
      0x0817 -> {
        let assert Ok(moved) = spell_threshold_index.decode(frame.body)
          as "0x817 decodes"
        Ok(ThresholdIndex(spell4_id: moved.spell4_id, index: moved.index))
      }
      0x0814 -> {
        let assert Ok(closed) = spell_threshold_closed.decode(frame.body)
          as "0x814 decodes"
        Ok(ThresholdClosed(
          spell4_id: closed.spell4_id,
          start_cooldowns: closed.start_cooldowns,
        ))
      }
      0x0815 -> {
        let assert Ok(ended) = spell_threshold_ended.decode(frame.body)
          as "0x815 decodes"
        Ok(ThresholdEnded(spell4_id: ended.spell4_id))
      }
      _ -> Error(Nil)
    }
  })
}

/// The units each go (0x7f4) among the frames names, in order, by cast id: the target
/// infos' unit ids in the order sent (opcode.0x7f4.target_info).
pub fn go_targets_in(frames frames: List(Frame)) -> List(#(Int, List(Int))) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x07F4 -> {
        let assert Ok(go) = spell_go.decode(frame.body) as "0x7f4 decodes"
        Ok(#(go.cast_id, list.map(go.targets, fn(target) { target.unit_id })))
      }
      _ -> Error(Nil)
    }
  })
}

/// The units each miss (0x7fb) among the frames names, in order, by cast id
/// (opcode.0x7fb).
pub fn missed_in(frames frames: List(Frame)) -> List(#(Int, List(Int))) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x07FB -> {
        let assert Ok(missed) = spell_missed.decode(frame.body)
          as "0x7fb decodes"
        Ok(#(missed.cast_id, list.map(missed.misses, fn(miss) { miss.unit_id })))
      }
      _ -> Error(Nil)
    }
  })
}

/// The health each 0x937 among the frames gives, in order: the unit, its health and
/// whether it is dead (opcode.0x937).
pub fn health_in(frames frames: List(Frame)) -> List(#(Int, Int, Bool)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x0937 -> {
        let assert Ok(health) = unit_health.decode(frame.body)
          as "0x937 decodes"
        Ok(#(health.unit_id, health.health, health.dead == 1))
      }
      _ -> Error(Nil)
    }
  })
}

/// The units each 0x88c among the frames marks dead or alive, in order
/// (opcode.0x88c).
pub fn deaths_in(frames frames: List(Frame)) -> List(#(Int, Bool)) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x088C -> {
        let assert Ok(state) = unit_death_state.decode(frame.body)
          as "0x88c decodes"
        Ok(#(state.unit_id, state.dead == 1))
      }
      _ -> Error(Nil)
    }
  })
}

/// The units each 0x355 among the frames removes, in order (opcode.0x355).
pub fn removals_in(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x0355 -> {
        let assert Ok(gone) = unit_destroyed.decode(frame.body)
          as "0x355 decodes"
        Ok(gone.unit_id)
      }
      _ -> Error(Nil)
    }
  })
}

/// The yaw of a unit at `from` that faces `target`: atan2(-dx, -dz), since a unit
/// faces (-sin yaw, -cos yaw) (`movement_command.kind_14.facing`, `0x1401b3170`).
pub fn yaw_toward(
  from from: #(Float, Float),
  target target: #(Float, Float),
) -> Float {
  area.bearing(
    from: Point(x: from.0, z: from.1),
    target: Point(x: target.0, z: target.1),
    yaw: 0.0,
  )
}

/// Reads game messages, waiting on the server and never for a fixed time, until the
/// frames read so far satisfy `found`, and gives all of them in order with the bytes
/// kept; a connection that ends or no progress within `within_ms` stops the test.
pub fn read_until(
  game game: Game,
  have have: BitArray,
  within_ms within_ms: Int,
  found found: fn(List(Frame)) -> Bool,
) -> #(List(Frame), BitArray) {
  read_until_from(game:, have:, frames: [], within_ms:, found:)
}

fn read_until_from(
  game game: Game,
  have have: BitArray,
  frames frames: List(Frame),
  within_ms within_ms: Int,
  found found: fn(List(Frame)) -> Bool,
) -> #(List(Frame), BitArray) {
  use <- bool.guard(when: found(frames), return: #(frames, have))
  case poll(game:, have:, wait_ms: within_ms) {
    Ok(#([], _)) ->
      panic as "the server wrote nothing while a client waited for a message"
    Ok(#(more, have)) ->
      read_until_from(
        game:,
        have:,
        frames: list.append(frames, more),
        within_ms:,
        found:,
      )
    Error(error) ->
      panic as {
        "the game server's connection failed while a client waited: "
        <> mug.describe_error(error)
      }
  }
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

/// Gives each game message already held whole in `have`, or else waits up to
/// `wait_ms` for the server to write, and gives each game message
/// that has arrived whole, opened from its 0x3DC wrapper under the session
/// cipher, keeping the bytes of one not yet whole. A wait that ends with nothing
/// written gives no message; the connection ending gives the reason, for a client
/// that stays on it for long and ends cleanly when the server closes it.
pub fn poll(
  game game: Game,
  have have: BitArray,
  wait_ms wait_ms: Int,
) -> Result(#(List(Frame), BitArray), mug.Error) {
  let assert Ok(#(held, rest)) = frame_reader.decode(received: have)
    as "the server wrote bytes that are frames"
  case held {
    [_, ..] -> Ok(#(opened(game:, outers: held), rest))
    [] ->
      case mug.receive(game.socket, timeout_milliseconds: wait_ms) {
        Ok(more) -> {
          let assert Ok(#(outers, rest)) =
            frame_reader.decode(received: <<rest:bits, more:bits>>)
            as "the server wrote bytes that are frames"
          Ok(#(opened(game:, outers:), rest))
        }
        Error(mug.Timeout) -> Ok(#([], rest))
        Error(error) -> Error(error)
      }
  }
}

fn opened(game game: Game, outers outers: List(Frame)) -> List(Frame) {
  list.map(outers, in_the_game_wrapper(_, game.cipher))
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

/// What the client's view of other units holds after a message of the server:
/// 0x262, of a player, a creature or a static object, creates a unit at its first kind 2
/// position (0x1404586e0), 0x638 moves
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

/// The unit a 0x262 creates: a player's, a creature's or a static object's.
pub type Created {
  PlayerCreated(unit: UnitCreatePlayer)
  CreatureCreated(unit: UnitCreateCreature)
  ObjectCreated(unit: UnitCreateStatic)
}

/// The unit the body of a 0x262 creates: a player's when the body reads as one,
/// else a creature's, else a static object's of type 10, 11 or 32 (the type is in
/// the body, `opcode.0x262`, `opcode.0x262.simple`), or `Error(Nil)` for a body
/// that is none of them.
pub fn created_unit(body body: BitArray) -> Result(Created, Nil) {
  unit_create_player.decode(body)
  |> result.map(PlayerCreated)
  |> result.lazy_or(fn() {
    unit_create_creature.decode(body) |> result.map(CreatureCreated)
  })
  |> result.replace_error(Nil)
  |> result.lazy_or(fn() { object_created(body:) })
}

/// The static object the body creates, or `Error(Nil)` for one whose type is not
/// a static object's.
fn object_created(body body: BitArray) -> Result(Created, Nil) {
  use unit <- result.try(
    unit_create_static.decode(body) |> result.replace_error(Nil),
  )
  case unit.unit_type {
    static_unit_type.Simple
    | static_unit_type.Platform
    | static_unit_type.SimpleCollidable -> Ok(ObjectCreated(unit:))
    static_unit_type.Other(_) -> Error(Nil)
  }
}

fn created(others others: Others, body body: BitArray) -> Others {
  let assert Ok(unit) = created_unit(body:)
    as "0x0262 decodes as a player's, a creature's or a static object's"
  case unit {
    PlayerCreated(unit:) -> dict.insert(others, unit.unit_id, placed_at(unit:))
    CreatureCreated(unit:) ->
      dict.insert(others, unit.unit_id, first_position(unit.tail))
    ObjectCreated(unit:) ->
      dict.insert(others, unit.unit_id, first_position(unit.tail))
  }
}

/// Where a 0x262's tail places its unit: the kind 2 command that is the first of
/// its commands (0x1404586e0).
fn first_position(tail: UnitCreateTail) -> #(Float, Float, Float) {
  let assert [start_movement.Position(placed), ..] = tail.movement_commands
    as "0x0262 places the unit with a kind 2 command first"
  standing(placed)
}

/// The creatures the 0x262 among the messages create, in the order sent: a 0x262
/// that is a player's or a static object's is left out.
pub fn creatures_created_in(
  frames frames: List(Frame),
) -> List(UnitCreateCreature) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x0262 ->
        case created_unit(body: frame.body) {
          Ok(CreatureCreated(unit:)) -> Ok(unit)
          Ok(PlayerCreated(..)) | Ok(ObjectCreated(..)) | Error(Nil) ->
            Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
}

/// Where a 0x262 places its unit: the kind 2 command that is the first of its
/// commands (0x1404586e0).
pub fn placed_at(unit unit: UnitCreatePlayer) -> #(Float, Float, Float) {
  first_position(unit.tail)
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
    relayed_movement.Time(_)
    | relayed_movement.Platform(_)
    | relayed_movement.Path(_)
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

/// Where a creature's 0x262 places it, as `placed_at` reads a player's.
pub fn creature_placed_at(
  unit unit: UnitCreateCreature,
) -> #(Float, Float, Float) {
  first_position(unit.tail)
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
/// before the six armor items, the weapon and the three abilities (0x111,
/// opcode.0x111.ability_bag, opcode.0x111.equipped_set),
/// their tiers (0x1A0, opcode.0x1a0), the action set (0x19D, opcode.0x19d), 0x6BC,
/// 0x636 and 0x61; then the zone channel (opcode.0x1da, opcode.0x1bc).
pub const world_entry_ids = [
  0x00AD,
  0x0262,
  0x019B,
  0x0111,
  0x0111,
  0x0111,
  0x0111,
  0x0111,
  0x0111,
  0x0111,
  0x0111,
  0x0111,
  0x0111,
  0x01A0,
  0x019D,
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

/// The id of the zone channel the entry's burst joins the player to: the channel
/// of the 0x1bc among the messages of an entry (opcode.0x1bc), whose type is 9.
pub fn zone_channel_in(frames frames: List(Frame)) -> Int {
  let assert Ok(Frame(body:, ..)) =
    list.find(frames, fn(frame) { frame.message_id == 0x01BC })
    as "the burst holds 0x01BC"
  let assert Ok(joined) = chat_channel_joined.decode(body) as "0x01BC decodes"
  assert joined.channel_type == 9 as "the burst's channel is the zone channel"
  joined.channel_id
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

// ---- chat: what the client sends and reads ----

/// A line the client's chat sends: the channel's type and id, the text (as its
/// UTF-16 units, of characters below 0x10000) and the slot the client keeps it
/// in until the server answers (opcode.0x1c3). The client's ids start at 1
/// (0x140405cb0).
pub fn send_line(
  game game: Game,
  channel_type channel_type: Int,
  channel_id channel_id: Int,
  text text: String,
  chat_message_id chat_message_id: Int,
) -> Nil {
  let assert Ok(body) =
    send_chat_line.encode(SendChatLine(
      channel_type:,
      channel_id:,
      text: bit_stream.utf16_units(text),
      formats: [],
      chat_message_id:,
    ))
    as "a line of the bot's text fits its fields"
  send_world(game:, message_id: send_chat_line.message_id, body:)
}

/// Says a line on Say, channel (4, 0), which the client makes itself.
pub fn say(
  game game: Game,
  text text: String,
  chat_message_id chat_message_id: Int,
) -> Nil {
  send_line(game:, channel_type: 4, channel_id: 0, text:, chat_message_id:)
}

/// Whispers a line to a character by name, with an empty realm name and the
/// account bit clear, as the client's whisper does (opcode.0x1d4).
pub fn whisper(
  game game: Game,
  target target: String,
  text text: String,
  chat_message_id chat_message_id: Int,
) -> Nil {
  let assert Ok(body) =
    send_whisper.encode(SendWhisper(
      target_name: bit_stream.utf16_units(target),
      target_realm_name: [],
      text: bit_stream.utf16_units(text),
      formats: [],
      chat_message_id:,
      account: 0,
    ))
    as "a whisper of the bot's text fits its fields"
  send_world(game:, message_id: send_whisper.message_id, body:)
}

/// A line as the client's chat shows another player's: the channel it arrived
/// on, the sender's name and the text (opcode.0x1c8).
pub type HeardLine {
  HeardLine(channel_type: Int, channel_id: Int, sender: String, text: String)
}

/// The line a 0x1c8 shows, by its channel, strSender and text.
pub fn heard_line(frame frame: Frame) -> Result(HeardLine, Nil) {
  use <- bool.guard(
    when: frame.message_id != chat_line.message_id,
    return: Error(Nil),
  )
  let assert Ok(line) = chat_line.decode(frame.body) as "0x01C8 decodes"
  Ok(HeardLine(
    channel_type: line.channel_type,
    channel_id: line.channel_id,
    sender: line.sender_name,
    text: from_units(line.text),
  ))
}

/// Reads until the next 0x1c8 and gives the line it shows, dropping the
/// messages before it and keeping the bytes beyond it.
pub fn read_chat(
  game game: Game,
  have have: BitArray,
) -> #(HeardLine, BitArray) {
  let #(frame, rest) = next(game:, have:)
  case heard_line(frame:) {
    Ok(line) -> #(line, rest)
    Error(Nil) -> read_chat(game:, have: rest)
  }
}

/// Reads until the server answers the line sent with `chat_message_id`: the 0x1c2
/// it gives, dropping the messages before it. An answer that is a refusal (0x1d3)
/// or a failed whisper (0x1d9) for that slot stops the caller with its message.
pub fn read_accepted(
  game game: Game,
  have have: BitArray,
  chat_message_id chat_message_id: Int,
) -> #(ChatLineAccepted, BitArray) {
  let #(frame, rest) = next(game:, have:)
  case frame.message_id {
    0x01C2 -> {
      let assert Ok(accept) = chat_line_accepted.decode(frame.body)
        as "0x01C2 decodes"
      case accept.chat_message_id == chat_message_id {
        True -> #(accept, rest)
        False -> read_accepted(game:, have: rest, chat_message_id:)
      }
    }
    0x01D3 | 0x01D9 ->
      panic as "the server refused the bot's line instead of accepting it"
    _ -> read_accepted(game:, have: rest, chat_message_id:)
  }
}

/// Pings and reads every message the server wrote up to its pong, which is all
/// that it wrote before it took the ping: the messages come back in order, and
/// the bytes beyond the pong are kept. After a ping and pong of another
/// connection that took its steps first, it holds all that they told this one.
pub fn read_until_pong(
  game game: Game,
  have have: BitArray,
  number number: Int,
) -> #(List(Frame), BitArray) {
  send_ping(game:, number:)
  collect_until_pong(game:, have:, number:, found: [])
}

fn collect_until_pong(
  game game: Game,
  have have: BitArray,
  number number: Int,
  found found: List(Frame),
) -> #(List(Frame), BitArray) {
  let #(outer, rest) = next_outer(game:, have:)
  case outer {
    Frame(message_id: 0x0001, body: <<answered:size(8)>>)
      if answered == number
    -> #(list.reverse(found), rest)
    Frame(message_id: 0x0001, ..) ->
      collect_until_pong(game:, have: rest, number:, found:)
    Frame(..) ->
      collect_until_pong(game:, have: rest, number:, found: [
        in_the_game_wrapper(outer:, cipher: game.cipher),
        ..found
      ])
  }
}

/// How many of the lines show no sender name, which is where the client would
/// have no name to show: a count of the lookups of a name (0x597) it would have
/// to ask for, which is none while every line carries its sender's name
/// (chat.name_lookup).
pub fn name_lookups_needed(lines lines: List(HeardLine)) -> Int {
  list.count(lines, fn(line) { line.sender == "" })
}

/// The text of a line's UTF-16 units, with a unit that pairs with no other shown
/// as the replacement character, as a client's text box would show it.
pub fn from_units(units: List(Int)) -> String {
  bit_stream.from_utf16(units) |> result.unwrap(or: "\u{FFFD}")
}

/// A scripted client's chat: its connection and the chat message id of its next
/// line. The client's ids start at 1 (0x140405cb0), and each line takes the next.
pub type Chatter {
  Chatter(game: Game, next_id: Int)
}

/// A chatter that has sent no line.
pub fn chatter(game game: Game) -> Chatter {
  Chatter(game:, next_id: 1)
}

/// Sends a line on the channel with the chatter's next id, which is given back
/// with the chatter that holds the one after it.
pub fn line_next(
  chatter chatter: Chatter,
  channel_type channel_type: Int,
  channel_id channel_id: Int,
  text text: String,
) -> #(Chatter, Int) {
  send_line(
    game: chatter.game,
    channel_type:,
    channel_id:,
    text:,
    chat_message_id: chatter.next_id,
  )
  #(Chatter(..chatter, next_id: chatter.next_id + 1), chatter.next_id)
}

/// Says a line on Say, with the chatter's next id, as `line_next` sends one.
pub fn say_next(
  chatter chatter: Chatter,
  text text: String,
) -> #(Chatter, Int) {
  line_next(chatter:, channel_type: 4, channel_id: 0, text:)
}

/// Whispers a line with the chatter's next id, as `say_next` says one.
pub fn whisper_next(
  chatter chatter: Chatter,
  target target: String,
  text text: String,
) -> #(Chatter, Int) {
  whisper(game: chatter.game, target:, text:, chat_message_id: chatter.next_id)
  #(Chatter(..chatter, next_id: chatter.next_id + 1), chatter.next_id)
}

/// What the entry's items, tiers and action set give the player's action bar, as
/// the client keeps them: the weapon equipped in slot 16, the other equipped
/// items (armor pieces and the shield) by bag index, the abilities in the bag by
/// bag index, and the bar slots of action set 0 whose ability the client can
/// show (the ability's item is held, and its tier is set for action set 0).
pub type Loadout {
  Loadout(
    weapon: Option(Int),
    armor: List(#(Int, Int)),
    abilities: List(#(Int, Int)),
    bar: List(#(Int, Int)),
  )
}

/// The loadout the messages of an entry give (opcode.0x111.ability_bag: an item
/// at location 4 is an ability, its item id the Spell4Base id and its bag index
/// the slot a press names; lua.ActionBarFrame.InitializeBars: the weapon is the
/// item equipped in slot 16, location 0, and any other item at location 0 is an
/// equipped piece at its bag index (opcode.0x111.equipped_set); opcode.0x1a0: a tier per base and set;
/// opcode.0x19d: a type 4 shortcut is an ability by its Spell4Base id, in the bar
/// slot its bag index names, and the client shows it when it holds the ability,
/// 0x1403c1bf0).
pub fn loadout_in(frames frames: List(Frame)) -> Loadout {
  let items =
    list.filter(frames, fn(frame) { frame.message_id == item_added.message_id })
    |> list.map(fn(frame) {
      let assert Ok(added) = item_added.decode(frame.body) as "0x0111 decodes"
      added.item
    })
  let weapon =
    list.find(items, fn(item) { item.location == 0 && item.bag_index == 16 })
    |> result.map(fn(item) { item.item_id })
    |> option.from_result
  let armor =
    list.filter(items, fn(item) { item.location == 0 && item.bag_index != 16 })
    |> list.map(fn(item) { #(item.bag_index, item.item_id) })
  let abilities =
    list.filter(items, fn(item) { item.location == 4 })
    |> list.map(fn(item) { #(item.bag_index, item.item_id) })
  let held_with_tier =
    list.filter_map(frames, fn(frame) {
      case frame.message_id == ability_tiers.message_id {
        True -> {
          let assert Ok(tiers) = ability_tiers.decode(frame.body)
            as "0x01A0 decodes"
          Ok(tiers.tiers)
        }
        False -> Error(Nil)
      }
    })
    |> list.flatten
    |> list.filter(fn(tier) { tier.action_set_index == 0 })
    |> list.map(fn(tier) { tier.spell4_base_id })
  let bar =
    list.filter_map(frames, fn(frame) {
      case frame.message_id == action_set.message_id {
        True -> {
          let assert Ok(set) = action_set.decode(frame.body) as "0x019D decodes"
          Ok(set)
        }
        False -> Error(Nil)
      }
    })
    |> list.filter(fn(set) { set.action_set_index == 0 && set.result == 1 })
    |> list.flat_map(fn(set) { set.shortcuts })
    |> list.filter(fn(shortcut) {
      shortcut.shortcut_type == 4
      && list.any(abilities, fn(ability) { ability.1 == shortcut.object_id })
      && list.contains(held_with_tier, shortcut.object_id)
    })
    |> list.map(fn(shortcut) { #(shortcut.bag_index, shortcut.object_id) })
  Loadout(weapon:, armor:, abilities:, bar:)
}

/// The figures the character sheet shows (lua.Character.UpdateAttributes), whole
/// numbers.
pub type Sheet {
  Sheet(
    assault_power: Int,
    support_power: Int,
    max_health: Int,
    max_shield: Int,
  )
}

/// The GameFormula row that holds the factors from a rating to a power: its
/// first value for Assault Power (0x14064c960) and its second for Support Power
/// (0x14064ca50).
const power_formula = 1266

/// The factor Assault Power uses when the table has no GameFormula row 1266:
/// the client's own 0.25 (0x14064c960). Support Power has no read fallback, so a
/// table without the row stops the bot.
const assault_power_without_the_row = 0.25

/// The sheet's figures for the player a 0x262 creates, with the client's
/// tables: Assault Power is property 35 times GameFormula 1266's first value
/// (0x14064c960), Support Power is property 36 times its second value
/// (0x14064ca50), Max Health is property 7 cut to a whole number (0x14064a6d0)
/// and Max Shields is property 41 (0x14064faa0); a property the 0x262 does not
/// set is 0. Power and shields show rounded to the whole number.
pub fn sheet(
  unit unit: UnitCreatePlayer,
  tables tables: table_store.Tables,
) -> Sheet {
  let power = game_formula.get(tables:, id: GameFormulaId(power_formula))
  let assault_factor = case power {
    Ok(row) -> row.datafloat0
    Error(Nil) -> assault_power_without_the_row
  }
  let assert Ok(support_factor) = result.map(power, fn(row) { row.datafloat01 })
    as "the client's tables hold GameFormula row 1266, whose second value 0x14064ca50 reads"
  let property = fn(id) {
    case
      list.find(unit.tail.properties, fn(property) {
        property.property_id == id
      })
    {
      Ok(property) -> property_value(property)
      Error(Nil) -> 0.0
    }
  }
  Sheet(
    assault_power: float.round(property(35) *. assault_factor),
    support_power: float.round(property(36) *. support_factor),
    max_health: float.truncate(property(7)),
    max_shield: float.round(property(41)),
  )
}

/// The float a property holds as its value.
fn property_value(property: unit_property.UnitProperty) -> Float {
  let assert Ok(bits) = float32.bits(property.value)
    as "a property's value is 32 bits"
  let assert Ok(value) = float32.value(bits)
    as "the server sends a finite property value"
  value
}

/// What a frame says of a fight, as the client reads it.
pub type FightEvent {
  /// 0x908: the unit targets another with this threat (opcode.0x908).
  Targeted(unit_id: Int, target_unit_id: Int, threat: Int)
  /// 0x90a: the unit holds this threat toward another, 0 erasing it (opcode.0x90a).
  Threatens(unit_id: Int, other_unit_id: Int, threat: Int)
  /// 0x89a: the unit is in a fight or out of one (opcode.0x89a).
  InCombat(unit_id: Int, in_combat: Bool)
  /// 0x938 of stat 20: the unit's shield (opcode.0x938).
  ShieldIs(unit_id: Int, shield: Int)
  /// 0x92f: the player's own health (opcode.0x92f).
  OwnHealthIs(unit_id: Int, health: Int)
  /// 0x638: the unit's command kinds in order, and the place the commands leave the
  /// unit at when they hold one: a kind 4 path's last point (movement_command.kind_4),
  /// or a kind 2 position with its blend bit clear, which places the unit at once
  /// (`0x140714120`).
  Moves(unit_id: Int, kinds: List(Int), ends_at: Option(#(Float, Float, Float)))
  /// 0x7f4: each target's unit with the effect ids and raw damage of its effects
  /// (opcode.0x7f4).
  Went(cast_id: Int, targets: List(#(Int, List(#(Int, Int)))))
  /// 0x7ff: a unit's cast starts (opcode.0x7ff).
  Started(cast_id: Int, caster_unit_id: Int, spell4_id: Int)
  /// 0x937: a unit's health (opcode.0x937).
  HealthIs(unit_id: Int, health: Int)
}

/// The fight's frames among the frames, in order.
pub fn fight_in(frames frames: List(Frame)) -> List(FightEvent) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x0908 -> {
        let assert Ok(target) = unit_target.decode(frame.body)
          as "0x908 decodes"
        Ok(Targeted(
          unit_id: target.unit_id,
          target_unit_id: target.target_unit_id,
          threat: target.threat,
        ))
      }
      0x090A -> {
        let assert Ok(threat) = unit_threat.decode(frame.body)
          as "0x90a decodes"
        Ok(Threatens(
          unit_id: threat.unit_id,
          other_unit_id: threat.other_unit_id,
          threat: threat.threat,
        ))
      }
      0x089A -> {
        let assert Ok(state) = unit_combat_state.decode(frame.body)
          as "0x89a decodes"
        Ok(InCombat(unit_id: state.unit_id, in_combat: state.in_combat == 1))
      }
      0x0938 -> {
        let assert Ok(changed) = unit_stat_changed.decode(frame.body)
          as "0x938 decodes: the server sends it only for stat 20"
        Ok(ShieldIs(unit_id: changed.unit_id, shield: changed.value))
      }
      0x092F -> {
        let assert Ok(health) = player_health.decode(frame.body)
          as "0x92f decodes"
        Ok(OwnHealthIs(unit_id: health.unit_id, health: health.health))
      }
      0x0937 -> {
        let assert Ok(health) = unit_health.decode(frame.body)
          as "0x937 decodes"
        Ok(HealthIs(unit_id: health.unit_id, health: health.health))
      }
      0x0638 -> {
        let assert Ok(moved) = unit_movement.decode(frame.body)
          as "0x638 decodes"
        let ends_at =
          list.find_map(moved.commands, ends_at_of) |> option.from_result
        Ok(Moves(
          unit_id: moved.unit_id,
          kinds: list.map(moved.commands, relayed_kind),
          ends_at:,
        ))
      }
      0x07F4 -> {
        let assert Ok(go) = spell_go.decode(frame.body) as "0x7f4 decodes"
        Ok(Went(
          cast_id: go.cast_id,
          targets: list.map(go.targets, fn(target) {
            #(target.unit_id, list.filter_map(target.effects, damage_of))
          }),
        ))
      }
      0x07FF -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "0x7ff decodes"
        Ok(Started(
          cast_id: start.cast_id,
          caster_unit_id: start.caster_unit_id,
          spell4_id: start.spell4_id,
        ))
      }
      _ -> Error(Nil)
    }
  })
}

/// The last point of a kind 4 path command, or the place of a kind 2 position
/// command with its blend bit clear, or `Error(Nil)` for another command.
fn ends_at_of(
  command: relayed_movement.RelayedMovement,
) -> Result(#(Float, Float, Float), Nil) {
  case command {
    relayed_movement.Path(path) -> {
      use point <- result.try(list.last(path.points))
      use x <- result.try(float32.bits(point.x) |> result.try(float32.value))
      use y <- result.try(float32.bits(point.y) |> result.try(float32.value))
      use z <- result.try(float32.bits(point.z) |> result.try(float32.value))
      Ok(#(x, y, z))
    }
    relayed_movement.Position(position) if position.blends == 0 ->
      Ok(standing(position))
    _ -> Error(Nil)
  }
}

/// An effect info's Spell4Effects id and raw damage, or `Error(Nil)` for an effect
/// that is not damage.
fn damage_of(
  effect: spell_effect_info.SpellEffectInfo,
) -> Result(#(Int, Int), Nil) {
  case effect.result {
    spell_effect_result.Damage(damage) ->
      Ok(#(effect.spell4_effects_id, damage.description.raw_damage))
    _ -> Error(Nil)
  }
}

/// A relayed command's kind, its first 5 bits (opcode.0x638).
fn relayed_kind(command: relayed_movement.RelayedMovement) -> Int {
  case command {
    relayed_movement.Time(..) -> 0
    relayed_movement.Platform(..) -> 1
    relayed_movement.Position(..) -> 2
    relayed_movement.Path(..) -> 4
    relayed_movement.Velocity(..) -> 8
    relayed_movement.MoveAsked(..) -> 11
    relayed_movement.Rotation(..) -> 14
    relayed_movement.StateFlags(..) -> 24
    relayed_movement.Mode(..) -> 27
  }
}

/// The health each 0x937 among the events gives `unit`, in order.
pub fn health_of(events events: List(FightEvent), unit unit: Int) -> List(Int) {
  list.filter_map(events, fn(event) {
    case event {
      HealthIs(unit_id:, health:) if unit_id == unit -> Ok(health)
      _ -> Error(Nil)
    }
  })
}

/// Each 0x638 of `unit` among the events: its command kinds and the place its
/// commands leave it at, when they hold one.
pub fn moves_of(
  events events: List(FightEvent),
  unit unit: Int,
) -> List(#(List(Int), Option(#(Float, Float, Float)))) {
  list.filter_map(events, fn(event) {
    case event {
      Moves(unit_id:, kinds:, ends_at:) if unit_id == unit ->
        Ok(#(kinds, ends_at))
      _ -> Error(Nil)
    }
  })
}
