//// The player's movement in the world, a feature of the game connection's rule
//// (genesis_prime/game/connection) as character select and world entry are:
//// where the connection last heard the client say the player stands, which of
//// the client's commands it refuses, and the save of that place. The rule
//// turns its effects into the store's ask and log lines.
////
//// ```
//// 0x637, 0x63A, 0xD5, 0x63B, 0xF2, 0xFB, 0xFC, inside 0x38C
////                         ─▶ take         ─▶ the new state, or a refusal that ends the connection
//// 0x637, decoded          ─▶ moves, moved ─▶ the place kept, or a refusal that ends the connection
//// the 60 s timer          ─▶ save         ─▶ Ask store SavePlace(account, character, epoch, sequence, place)
//// the store's answer      ─▶ saved        ─▶ a log line when nothing was saved
//// ```
////
//// - **What is kept** is the last position and the last rotation the client
////   sent while it stood in the world's own frame (kind 1 is 0); a position or
////   rotation sent while kind 1 names a platform unit is in that unit's frame
////   and is not kept (opcode.0x637). The frame is kept between messages, since
////   the client sends only the commands that changed.
//// - **What is refused** is what the client's own code never sends: a position
////   or rotation that is not finite, a height below -2048 in the world's frame
////   (the client raises it to -2048 before it sends,
////   movement_command.position_bound), state flags above 0x3ffff and a mode
////   other than 0, 1 and 3 (movement_command.kind_24, movement_command.kind_27),
////   and a move speed setting above 2 (0x140c45dd0). A height below -2048 in a
////   platform's frame is that unit's own, which the client's clamp does not
////   bound, so it is not refused. x and z beyond +-32768 and y above 2048 are
////   kept as sent: the client sends them by up to one frame's movement past the
////   box it clamps to, and how far one frame goes is not read
////   (movement_command.position_bound).
//// - **The client's clock** and kind 0's time are the client's own milliseconds
////   (0x140c3a004, 0x14057a190); nothing here reads them or compares them with
////   the server's clock.
//// - **The place** is `genesis_prime/game/start_place`'s, so the world and the
////   zone never change here and a moved place is never in world 0. The zone
////   the player crosses into (0x63A) is not read, so the saved zone is the one
////   the player entered with.
//// - **The epoch and the sequence** name the login's saves. The epoch is the
////   one the login was told when it loaded the character
////   (genesis_prime/store `SessionEpoch`); the sequence numbers the saves the
////   login asks, from 1, so a save of one login that reaches the database after
////   a newer one of its own, as a save cut short by a stop can, changes nothing.
//// - **What a crash or a takeover can lose.** A save every `save_period_ms`
////   bounds what a connection that cannot save loses. A takeover saves the older
////   login's place at its own epoch: when the newer login's load comes first the
////   save changes nothing, and the older login loses at most the movement since
////   its last save, within `save_period_ms`.

import genesis_prime/client_connection
import genesis_prime/game/start_place.{type Facing, type Place, Facing}
import genesis_prime/message/bit_stream
import genesis_prime/message/fall_value
import genesis_prime/message/fell_below_floor
import genesis_prime/message/float32.{type Bits}
import genesis_prime/message/move_speed_setting
import genesis_prime/message/movement_command.{type MovementCommand}
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_send_interval_answer
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/player_movement.{type PlayerMovement}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/message/terrain_loaded
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/zone_value_changed
import genesis_prime/store.{
  type AccountId, type CharacterId, type MoveAnswer, type MoveRequest,
  type SessionEpoch, NothingSaved, PlaceRefused, PlaceSaved, SavePlace,
}
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/result

/// The movement messages of the player in the world, which the client sends
/// inside 0x038C (genesis_prime/game/routing's table says which id is which).
pub type Message {
  /// 0x0637, the player's movement commands.
  PlayerMoved
  /// 0x063A, the player unit's value changing.
  ZoneChanged
  /// 0x00D5, the answer to the world's settings.
  IntervalAnswered
  /// 0x063B, the move speed setting.
  SpeedChosen
  /// 0x00F2, the terrain near the player ready.
  TerrainReady
  /// 0x00FB, a fall's value.
  Fell
  /// 0x00FC, a fall below the floor.
  FellBelowFloor
}

/// What the store's answer to a save says, for the game connection's rule to
/// write as a log line.
pub type Effect {
  /// Log an error: a bug of the server's.
  Fault(text: String)
  /// Log at info.
  Note(text: String)
}

/// The frame the client's position is in: the world's, or the frame of the
/// unit the player stands on, which the client names in kind 1 (0 for none).
/// Only `footing` makes one, so no platform has unit id 0.
pub opaque type Footing {
  OnTheWorld
  OnPlatform(unit_id: Int)
}

/// The frame kind 1's unit id names: the world's for 0, else the frame of that
/// unit. `Error(Nil)` for a number below 0 or above 0xFFFFFFFF, which is no
/// unit id.
pub fn footing(unit_id unit_id: Int) -> Result(Footing, Nil) {
  case unit_id {
    0 -> Ok(OnTheWorld)
    unit_id if unit_id > 0 && unit_id <= 0xFFFFFFFF -> Ok(OnPlatform(unit_id:))
    _ -> Error(Nil)
  }
}

/// Where the player stands and how it is held: the last place the client's
/// commands put it, in the world's own frame, the frame the client's later
/// commands are in, the epoch its login was told and the number of the last
/// save it asked.
pub opaque type State {
  State(
    place: Place,
    footing: Footing,
    session_epoch: SessionEpoch,
    save_sequence: Int,
  )
}

/// One command of a 0x637 the rule acts on. The floats are the 32 bits the
/// message carries them as, so a value that is no finite float is one the rule
/// can refuse; the commands the rule does not act on are `Other`.
pub type Command {
  /// Kind 1: the frame the commands after it are in.
  Standing(footing: Footing)
  /// Kind 2: the position x, y, z.
  Position(x: Bits, y: Bits, z: Bits)
  /// Kind 14: the rotation yaw, pitch, roll.
  Rotation(yaw: Bits, pitch: Bits, roll: Bits)
  /// Kind 24: the unit's state flags.
  StateFlags(flags: Int)
  /// Kind 27: the movement mode.
  Mode(mode: Int)
  /// Any other kind, its data read and not kept: kind 0 is the client's own
  /// clock, which nothing compares with the server's.
  Other(kind: Int)
}

/// A 0x637 as the rule takes it: the client's clock in milliseconds and its
/// commands in the order they were sent.
pub type Moves {
  Moves(client_clock: Int, commands: List(Command))
}

/// Why a command is refused, which ends the connection: the client's own code
/// never sends it.
pub type Refusal {
  /// A position or rotation float that is infinite or not a number; `kind` is
  /// the command's kind, 2 or 14.
  NotFinite(kind: Int)
  /// A height below -2048 in the world's frame, which the client raises to
  /// -2048 before it sends (movement_command.position_bound).
  BelowTheWorld(y: Float)
  /// State flags above 0x3ffff (movement_command.kind_24).
  UnknownStateFlags(flags: Int)
  /// A mode other than 0, 1 and 3 (movement_command.kind_27).
  UnknownMode(mode: Int)
  /// A move speed setting above 2 (0x140c45dd0).
  UnknownSpeedSetting(setting: Int)
  /// A body the client's own reader would refuse.
  NotDecoded(undecoded: client_connection.Undecoded)
}

/// How long after the player enters the world, and after each save, the
/// place is saved again: 60 seconds, a server choice. A connection whose own
/// save fails, or that crashes, loses at most this much movement.
pub const save_period_ms = 60_000

/// The movement of a player that enters the world at `place` as the login whose
/// epoch is `session_epoch`: in the world's own frame, with no save asked yet.
pub fn entered(
  place place: Place,
  session_epoch session_epoch: SessionEpoch,
) -> State {
  State(place:, footing: OnTheWorld, session_epoch:, save_sequence: 0)
}

/// The place the player last stood at in the world's own frame, with the way
/// it faced.
pub fn place(state state: State) -> Place {
  state.place
}

/// The way the player last faced in the world's own frame.
pub fn facing(state state: State) -> Facing {
  start_place.facing(state.place)
}

/// The commands of a decoded 0x637 as the rule takes them: kind 1 as the frame
/// it names, kinds 2 and 14 with their floats as 32 bits, kinds 24 and 27 with
/// their values, and every other kind, its data read, as `Other`.
pub fn moves(message message: PlayerMovement) -> Moves {
  Moves(
    client_clock: message.client_clock,
    commands: list.map(message.commands, command),
  )
}

/// One decoded command as the rule takes it. The codec reads each float in 32
/// bits and kind 1's unit id in 32 bits, so neither is out of range.
fn command(command: MovementCommand) -> Command {
  case command {
    movement_command.Platform(MovementPlatform(unit_id:)) -> {
      let assert Ok(footing) = footing(unit_id:)
        as "kind 1's unit id is 32 bits (movement_platform)"
      Standing(footing:)
    }
    movement_command.Position(UnitPositionCommand(x:, y:, z:, ..)) ->
      Position(x: single(x), y: single(y), z: single(z))
    movement_command.Rotation(MovementRotation(yaw:, pitch:, roll:, ..)) ->
      Rotation(yaw: single(yaw), pitch: single(pitch), roll: single(roll))
    movement_command.StateFlags(MovementStateFlags(flags:)) ->
      StateFlags(flags:)
    movement_command.Mode(MovementMode(mode:)) -> Mode(mode:)
    movement_command.Time(_) -> Other(kind: 0)
    movement_command.Kind3(_) -> Other(kind: 3)
    movement_command.Kind4(_) -> Other(kind: 4)
    movement_command.Kind5(_) -> Other(kind: 5)
    movement_command.Kind6(_) -> Other(kind: 6)
    movement_command.Kind7(_) -> Other(kind: 7)
    movement_command.Velocity(_) -> Other(kind: 8)
    movement_command.Kind9(_) -> Other(kind: 9)
    movement_command.Kind10(_) -> Other(kind: 10)
    movement_command.MoveAsked(_) -> Other(kind: 11)
    movement_command.Kind12(_) -> Other(kind: 12)
    movement_command.Kind13(_) -> Other(kind: 13)
    movement_command.Kind15(_) -> Other(kind: 15)
    movement_command.Kind16(_) -> Other(kind: 16)
    movement_command.Kind17(_) -> Other(kind: 17)
    movement_command.Kind18(_) -> Other(kind: 18)
    movement_command.Kind19(_) -> Other(kind: 19)
    movement_command.Kind20(_) -> Other(kind: 20)
    movement_command.Kind21(_) -> Other(kind: 21)
    movement_command.Kind22(_) -> Other(kind: 22)
    movement_command.Kind23(_) -> Other(kind: 23)
    movement_command.Kind25(_) -> Other(kind: 25)
    movement_command.Kind26(_) -> Other(kind: 26)
    movement_command.Kind28(_) -> Other(kind: 28)
    movement_command.Kind29(_) -> Other(kind: 29)
  }
}

/// The 32 bits a decoded message holds a float in.
fn single(number: Int) -> Bits {
  let assert Ok(bits) = float32.bits(number)
    as "the codec reads a float in 32 bits (bit_stream.read_float32_bits)"
  bits
}

/// What a movement message made of the player's movement.
pub type Taken {
  /// The message changes what the rule keeps, or nothing, and has nothing to
  /// relay: the state it leaves.
  Kept(state: State)
  /// An accepted 0x0637: the state it leaves, the place the player now stands
  /// at in the world's frame (`place`), the commands it sent that are relayed,
  /// in the order sent with their bits, and the kinds of those that are not
  /// (`unrelayed`, once each, in the order sent). The game connection tells the
  /// map, which relays the commands to the players who see this one
  /// (genesis_prime/world_map/map `Moved`).
  Relayed(
    state: State,
    place: Place,
    commands: List(RelayedMovement),
    unrelayed: List(Int),
  )
}

/// What a command of a 0x0637 is to the players who see the sender.
type Relay {
  /// A kind the server relays, with its data.
  Sent(command: RelayedMovement)
  /// Kind 0, the sender's own client clock, which is no one else's
  /// (movement_command.kind_0): dropped.
  Clock
  /// Any other kind: dropped, and named once per connection in a log line,
  /// since the client's writer may send it and `opcode.0x637` does not say
  /// what it means for another player.
  Unrelayed(kind: Int)
}

/// The commands of a 0x0637 that other players are sent, in order, and the
/// kinds of the others, each once in the order first sent: kind 0 is the
/// sender's clock and is never relayed or named, and the kinds
/// `genesis_prime/message/relayed_movement` does not hold are named.
fn relayed(
  commands commands: List(MovementCommand),
) -> #(List(RelayedMovement), List(Int)) {
  let relays = list.map(commands, relay)
  #(
    list.filter_map(relays, fn(relay) {
      case relay {
        Sent(command:) -> Ok(command)
        Clock | Unrelayed(..) -> Error(Nil)
      }
    }),
    list.filter_map(relays, fn(relay) {
      case relay {
        Unrelayed(kind:) -> Ok(kind)
        Sent(..) | Clock -> Error(Nil)
      }
    })
      |> list.unique,
  )
}

fn relay(command: MovementCommand) -> Relay {
  case command {
    movement_command.Platform(data) -> Sent(relayed_movement.Platform(data))
    movement_command.Position(data) -> Sent(relayed_movement.Position(data))
    movement_command.Velocity(data) -> Sent(relayed_movement.Velocity(data))
    movement_command.MoveAsked(data) -> Sent(relayed_movement.MoveAsked(data))
    movement_command.Rotation(data) -> Sent(relayed_movement.Rotation(data))
    movement_command.StateFlags(data) -> Sent(relayed_movement.StateFlags(data))
    movement_command.Mode(data) -> Sent(relayed_movement.Mode(data))
    movement_command.Time(_) -> Clock
    movement_command.Kind3(_) -> Unrelayed(3)
    movement_command.Kind4(_) -> Unrelayed(4)
    movement_command.Kind5(_) -> Unrelayed(5)
    movement_command.Kind6(_) -> Unrelayed(6)
    movement_command.Kind7(_) -> Unrelayed(7)
    movement_command.Kind9(_) -> Unrelayed(9)
    movement_command.Kind10(_) -> Unrelayed(10)
    movement_command.Kind12(_) -> Unrelayed(12)
    movement_command.Kind13(_) -> Unrelayed(13)
    movement_command.Kind15(_) -> Unrelayed(15)
    movement_command.Kind16(_) -> Unrelayed(16)
    movement_command.Kind17(_) -> Unrelayed(17)
    movement_command.Kind18(_) -> Unrelayed(18)
    movement_command.Kind19(_) -> Unrelayed(19)
    movement_command.Kind20(_) -> Unrelayed(20)
    movement_command.Kind21(_) -> Unrelayed(21)
    movement_command.Kind22(_) -> Unrelayed(22)
    movement_command.Kind23(_) -> Unrelayed(23)
    movement_command.Kind25(_) -> Unrelayed(25)
    movement_command.Kind26(_) -> Unrelayed(26)
    movement_command.Kind28(_) -> Unrelayed(28)
    movement_command.Kind29(_) -> Unrelayed(29)
  }
}

/// What one movement message does to where the player stands: the body is
/// decoded and 0x0637 and 0x063B are checked as `moved` and `speed_setting`
/// say; the others are decoded and nothing more, since what their values mean
/// is not read (the client trace's unknowns: 0x63A's and 0xF2's value is likely
/// the zone, 0xD5's three values are not read, 0xFB is a fall's value and 0xFC
/// the fall below the floor). A body the client's reader would refuse, or a
/// refused command, is the refusal that ends the connection.
pub fn take(
  state state: State,
  message message: Message,
  body body: BitArray,
) -> Result(Taken, Refusal) {
  case message {
    PlayerMoved ->
      player_movement.decode(body)
      |> undecoded(player_movement.message_id)
      |> result.try(fn(decoded) {
        use state <- result.map(moved(state:, moves: moves(message: decoded)))
        let #(commands, unrelayed) = relayed(commands: decoded.commands)
        Relayed(state:, place: place(state:), commands:, unrelayed:)
      })
    SpeedChosen ->
      move_speed_setting.decode(body)
      |> undecoded(move_speed_setting.message_id)
      |> result.try(fn(decoded) { speed_setting(setting: decoded.move_speed) })
      |> result.replace(Kept(state))
    ZoneChanged ->
      zone_value_changed.decode(body)
      |> undecoded(zone_value_changed.message_id)
      |> result.replace(Kept(state))
    IntervalAnswered ->
      movement_send_interval_answer.decode(body)
      |> undecoded(movement_send_interval_answer.message_id)
      |> result.replace(Kept(state))
    TerrainReady ->
      terrain_loaded.decode(body)
      |> undecoded(terrain_loaded.message_id)
      |> result.replace(Kept(state))
    Fell ->
      fall_value.decode(body)
      |> undecoded(fall_value.message_id)
      |> result.replace(Kept(state))
    FellBelowFloor ->
      fell_below_floor.decode(body)
      |> undecoded(fell_below_floor.message_id)
      |> result.replace(Kept(state))
  }
}

/// A decode that failed, as the refusal for the message it was read for.
fn undecoded(
  decoded: Result(message, bit_stream.DecodeError),
  message_id: Int,
) -> Result(message, Refusal) {
  client_connection.decoded(decoded, message_id:)
  |> result.map_error(NotDecoded)
}

/// What a 0x637 does to where the player stands, command by command in the
/// order sent: the frame of kind 1 holds for the commands after it and for later
/// messages; a position or rotation in the world's frame is kept; a command
/// the client's own code never sends is refused, and then nothing of the
/// message is kept.
pub fn moved(state state: State, moves moves: Moves) -> Result(State, Refusal) {
  list.try_fold(moves.commands, state, apply)
}

/// What one command does to the state, or why it is refused.
fn apply(state: State, command: Command) -> Result(State, Refusal) {
  case command {
    Standing(footing:) -> Ok(State(..state, footing:))
    Position(x:, y:, z:) -> {
      use x <- result.try(finite(x, kind: 2))
      use y <- result.try(finite(y, kind: 2))
      use z <- result.try(finite(z, kind: 2))
      case state.footing {
        OnTheWorld if y <. -2048.0 -> Error(BelowTheWorld(y:))
        OnTheWorld ->
          Ok(State(..state, place: start_place.moved(state.place, x:, y:, z:)))
        OnPlatform(..) -> Ok(state)
      }
    }
    Rotation(yaw:, pitch:, roll:) -> {
      use yaw <- result.try(finite(yaw, kind: 14))
      use pitch <- result.try(finite(pitch, kind: 14))
      use roll <- result.try(finite(roll, kind: 14))
      case state.footing {
        OnTheWorld ->
          Ok(
            State(
              ..state,
              place: start_place.turned(
                state.place,
                Facing(yaw:, pitch:, roll:),
              ),
            ),
          )
        OnPlatform(..) -> Ok(state)
      }
    }
    StateFlags(flags:) if flags > 0x3ffff -> Error(UnknownStateFlags(flags:))
    StateFlags(..) -> Ok(state)
    Mode(mode: 0) | Mode(mode: 1) | Mode(mode: 3) -> Ok(state)
    Mode(mode:) -> Error(UnknownMode(mode:))
    Other(..) -> Ok(state)
  }
}

/// The float the bits of a command of `kind` hold, or why the command is
/// refused.
fn finite(bits: Bits, kind kind: Int) -> Result(Float, Refusal) {
  float32.value(bits) |> result.replace_error(NotFinite(kind:))
}

/// Whether a move speed setting is one the client has: 0 to 2 (0x140c45dd0).
pub fn speed_setting(setting setting: Int) -> Result(Nil, Refusal) {
  use <- bool.guard(
    when: setting < 0 || setting > 2,
    return: Error(UnknownSpeedSetting(setting:)),
  )
  Ok(Nil)
}

/// A sentence that says what the client sent that is refused, for the log.
pub fn describe(refusal refusal: Refusal) -> String {
  case refusal {
    NotFinite(kind: 2) -> "0x0637 holds a position that is not finite"
    NotFinite(kind: 14) -> "0x0637 holds a rotation that is not finite"
    NotFinite(kind:) ->
      "0x0637 holds a command of kind "
      <> int.to_string(kind)
      <> " that is not finite"
    BelowTheWorld(y:) ->
      "0x0637 holds a height of " <> float.to_string(y) <> ", below -2048"
    UnknownStateFlags(flags:) ->
      "0x0637 holds state flags 0x" <> int.to_base16(flags) <> ", above 0x3ffff"
    UnknownMode(mode:) ->
      "0x0637 holds the mode " <> int.to_string(mode) <> ", none of 0, 1 and 3"
    UnknownSpeedSetting(setting:) ->
      "0x063B holds the move speed setting "
      <> int.to_string(setting)
      <> ", above 2"
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
  }
}

/// The save of where the player stands now, named by the login's epoch and
/// numbered one above the last save this login asked, and the state that holds
/// that number. A save asked and never answered keeps its number, so a late
/// answer is never taken for a newer save's.
pub fn save(
  state state: State,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
) -> #(State, MoveRequest) {
  let save_sequence = state.save_sequence + 1
  #(
    State(..state, save_sequence:),
    SavePlace(
      account_id:,
      character_id:,
      session_epoch: state.session_epoch,
      save_sequence:,
      place: state.place,
    ),
  )
}

/// What the store's answer to the save says: nothing for a saved place, a note
/// for a save that changed nothing, and an error for a place the database
/// refused.
pub fn saved(answer answer: MoveAnswer) -> List(Effect) {
  case answer {
    PlaceSaved -> []
    NothingSaved -> [
      Note(
        text: "a save changed nothing: a later login holds the character, a newer save of this login was stored first, or the account has no such character",
      ),
    ]
    PlaceRefused -> [
      Fault(text: "the database refused the place it was asked to save"),
    ]
  }
}
