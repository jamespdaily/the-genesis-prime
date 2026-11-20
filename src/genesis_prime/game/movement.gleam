//// The player's movement in the world, a feature of the game connection's rule
//// (genesis_prime/game/connection) as character select and world entry are:
//// where the connection last heard the client say the player stands, which of
//// the client's commands it refuses, and the save of that place. The rule
//// turns its effects into the store's ask and log lines.
////
//// ```
//// 0x637, 0x63A, 0xD5, 0x63B, 0xF2, 0xFB, 0xFC, 0x635, inside 0x38C
////                         ─▶ take         ─▶ the new state, or a refusal that ends the connection
//// 0x637, decoded          ─▶ moves, moved ─▶ the place kept, or a refusal that ends the connection
//// the 60 s timer          ─▶ save         ─▶ Ask store SavePlace(account, character, epoch, sequence, place, health, quests)
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
////   a move speed setting above 2 (0x140c45dd0), a command of a kind the client
////   never queues, 4, 5, 6, 7, 9, 12, 15, 16, 17, 19, 21, 22, 23, 26, 28 or 29
////   (opcode.0x637.sent_kinds), and a value the client never writes in a kind
////   it does send: kind 3's path type, time offset and blend bit are 0
////   (opcode.0x637.kinds_3_to_6); kind 25's flags words are each 0x100, 0x130,
////   0xc or 0x3c and its time offset is 0 (opcode.0x637.kind_25); kinds 10 and
////   13 have blend 0 (opcode.0x637.kinds_10_13); kind 18 has blend 1
////   (opcode.0x637.kind_18); kind 20's roll, time offset and blend are 0
////   (opcode.0x637.kind_20). A height below -2048 in a
////   platform's frame is that unit's own, which the client's clamp does not
////   bound, so it is not refused. x and z beyond +-32768 and y above 2048 are
////   kept as sent: the client sends them by up to one frame's movement past the
////   box it clamps to, and how far one frame goes is not read
////   (movement_command.position_bound).
//// - **What is not checked** is listed by `gaps`: the records of the client's
////   decode do not settle it, or settling it needs the map's units.
//// - **The client's clock** and kind 0's time are the client's own milliseconds
////   (0x140c3a004, 0x14057a190); nothing here reads them or compares them with
////   the server's clock.
//// - **The place** is `genesis_prime/game/start_place`'s, so the world never
////   changes here and a moved place is never in world 0. The WorldZone id the
////   client reports (0xF2, and 0x63A's new id) becomes the place's zone as
////   reported, so the saved zone is the last one the client reported; zone chat
////   takes it too (genesis_prime/game/chat `world_zone_reported`).
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
import genesis_prime/gap
import genesis_prime/message/bit_stream
import genesis_prime/message/client_control_echoed
import genesis_prime/message/fell_below_floor
import genesis_prime/message/float32.{type Bits}
import genesis_prime/message/impact_severity
import genesis_prime/message/move_speed_setting
import genesis_prime/message/movement_command.{type MovementCommand}
import genesis_prime/message/movement_face_unit.{MovementFaceUnit}
import genesis_prime/message/movement_kind_10.{MovementKind10}
import genesis_prime/message/movement_kind_13.{MovementKind13}
import genesis_prime/message/movement_kind_20.{MovementKind20}
import genesis_prime/message/movement_kind_25.{MovementKind25}
import genesis_prime/message/movement_kind_3.{MovementKind3}
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/player_movement.{type PlayerMovement}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/message/terrain_loaded
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/world_entry_options
import genesis_prime/message/world_zone_changed
import genesis_prime/store.{
  type AccountId, type CharacterId, type MoveAnswer, type MoveRequest,
  type QuestRow, type SessionEpoch, ExperienceRefused, HealthRefused,
  NothingSaved, PlaceRefused, PlaceSaved, QuestLogRefused, SavePlace,
}
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// The movement messages of the player in the world, which the client sends
/// inside 0x038C (genesis_prime/game/routing's table says which id is which).
pub type Message {
  /// 0x0637, the player's movement commands.
  PlayerMoved
  /// 0x063A, the WorldZone id the player stands in changing.
  ZoneChanged
  /// 0x00D5, the client's world-entry options.
  WorldEntryOptionsSent
  /// 0x063B, the move speed setting.
  SpeedChosen
  /// 0x00F2, the terrain near the player ready, with the WorldZone id the player
  /// stands in.
  TerrainReady
  /// 0x00FB, the impact severity of the player's movement.
  ImpactSeverityReported
  /// 0x00FC, a fall below the floor.
  FellBelowFloor
  /// 0x0635, the client's answer to a 0x636, carrying its value back.
  ControlEchoed
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
/// commands are in, the epoch its login was told, the number of the last
/// save it asked and whether its last state flags said it was moving.
pub opaque type State {
  State(
    place: Place,
    footing: Footing,
    session_epoch: SessionEpoch,
    save_sequence: Int,
    moving: Bool,
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
  /// Kind 3, the ForcedMove flight's timed path, with the three values the
  /// client writes as fixed (opcode.0x637.kinds_3_to_6). Its points and times
  /// are not read: the client writes 1 to 1023 points, the wire holds 0 to
  /// 1023 and a count of 0 is not refused.
  Kind3(path_type: Int, time_offset: Int, blends: Int)
  /// Kind 10, the velocity that follows the path, with its blend bit
  /// (opcode.0x637.kinds_10_13).
  Kind10(blends: Int)
  /// Kind 13, the move asked that follows the path, with its blend bit
  /// (opcode.0x637.kinds_10_13).
  Kind13(blends: Int)
  /// Kind 18, face a unit, with its blend bit (opcode.0x637.kind_18). Which
  /// unit it names is not read.
  Kind18(blends: Int)
  /// Kind 20, the spin, with the three values the client writes as fixed
  /// (opcode.0x637.kind_20). Its angles, duration and turn rate are not read.
  Kind20(roll: Int, time_offset: Int, blends: Int)
  /// Kind 25, the timed state flags: the flags word of each key and the time
  /// offset (opcode.0x637.kind_25). The count of keys is not read.
  Kind25(state_flags: List(Int), time_offset: Int)
  /// A kind the client's own code never queues for sending
  /// (opcode.0x637.sent_kinds): 4, 5, 6, 7, 9, 12, 15, 16, 17, 19, 21, 22, 23,
  /// 26, 28 or 29.
  Unsent(kind: Int)
  /// Kind 0, 8 or 11, its data read and not kept: kind 0 is the client's own
  /// clock, which nothing compares with the server's; kinds 8 and 11 are the
  /// velocity and the move asked, which the server relays and does not use.
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
  /// A kind the client's own code never sends (opcode.0x637.sent_kinds).
  UnsentKind(kind: Int)
  /// A value the client's own code never writes in a kind it does send:
  /// `field` names it in the words of the log line (opcode.0x637.kinds_3_to_6,
  /// opcode.0x637.kinds_10_13, opcode.0x637.kind_18, opcode.0x637.kind_20,
  /// opcode.0x637.kind_25).
  UnwrittenValue(kind: Int, field: String, value: Int)
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
  State(
    place:,
    footing: OnTheWorld,
    session_epoch:,
    save_sequence: 0,
    moving: False,
  )
}

/// The movement of a player placed at `place` by the server, in the world's own
/// frame, as the same login: its epoch and the number of its last save stay, so
/// the next save is numbered after every earlier one (the Holocrypt).
pub fn placed(state state: State, place place: Place) -> State {
  State(..state, place:, footing: OnTheWorld)
}

/// Whether the player went from not moving to moving between two states: the client's state
/// flags say it is moving while bit 0x2 is set, a move asked for with the velocity not near
/// zero (`movement_command.kind_24`).
pub fn started_moving(from from: State, to to: State) -> Bool {
  !from.moving && to.moving
}

/// The movement with its place in the zone the client reported; the footing
/// and the rest stay.
fn in_zone(state state: State, world_zone_id world_zone_id: Int) -> State {
  State(..state, place: start_place.in_zone(place: state.place, world_zone_id:))
}

/// The place the player last stood at in the world's own frame, with the way
/// it faced.
pub fn place(state state: State) -> Place {
  state.place
}

/// The epoch the player's login was told, which every store request of this
/// login that writes the character is fenced by.
pub fn session_epoch(state state: State) -> SessionEpoch {
  state.session_epoch
}

/// The way the player last faced in the world's own frame.
pub fn facing(state state: State) -> Facing {
  start_place.facing(state.place)
}

/// The commands of a decoded 0x637 as the rule takes them: kind 1 as the frame
/// it names, kinds 2 and 14 with their floats as 32 bits, kinds 24 and 27 with
/// their values, kinds 3, 10, 13, 18, 20 and 25 with the values the rule checks,
/// the kinds the client never sends as `Unsent`, and kinds 0, 8 and 11, their
/// data read, as `Other`.
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
    movement_command.Kind3(MovementKind3(path_type:, time_offset:, blends:, ..)) ->
      Kind3(path_type:, time_offset:, blends:)
    movement_command.Kind4(_) -> Unsent(kind: 4)
    movement_command.Kind5(_) -> Unsent(kind: 5)
    movement_command.Kind6(_) -> Unsent(kind: 6)
    movement_command.Kind7(_) -> Unsent(kind: 7)
    movement_command.Velocity(_) -> Other(kind: 8)
    movement_command.Kind9(_) -> Unsent(kind: 9)
    movement_command.Kind10(MovementKind10(blends:)) -> Kind10(blends:)
    movement_command.MoveAsked(_) -> Other(kind: 11)
    movement_command.Kind12(_) -> Unsent(kind: 12)
    movement_command.Kind13(MovementKind13(blends:)) -> Kind13(blends:)
    movement_command.Kind15(_) -> Unsent(kind: 15)
    movement_command.Kind16(_) -> Unsent(kind: 16)
    movement_command.Kind17(_) -> Unsent(kind: 17)
    movement_command.FaceUnit(MovementFaceUnit(blends:, ..)) -> Kind18(blends:)
    movement_command.FacePoint(_) -> Unsent(kind: 19)
    movement_command.Kind20(MovementKind20(roll:, time_offset:, blends:, ..)) ->
      Kind20(roll:, time_offset:, blends:)
    movement_command.Kind21(_) -> Unsent(kind: 21)
    movement_command.Kind22(_) -> Unsent(kind: 22)
    movement_command.Kind23(_) -> Unsent(kind: 23)
    movement_command.Kind25(MovementKind25(state_flags:, time_offset:, ..)) ->
      Kind25(state_flags:, time_offset:)
    movement_command.Kind26(_) -> Unsent(kind: 26)
    movement_command.Kind28(_) -> Unsent(kind: 28)
    movement_command.Kind29(_) -> Unsent(kind: 29)
  }
}

/// The 32 bits a decoded message holds a float in.
fn single(number: Int) -> Bits {
  let assert Ok(bits) = float32.bits(number)
    as "the codec reads a float in 32 bits (bit_stream.read_float32_bits)"
  bits
}

/// The message a `Reported` zone came in: 0xF2 or 0x63A, which also carries the zone
/// the player left.
pub type ReportedBy {
  ReportedByTerrainReady
  ReportedByZoneChanged(old_world_zone_id: Int)
}

/// What a movement message made of the player's movement.
pub type Taken {
  /// The message changes what the rule keeps, or nothing, and has nothing to
  /// relay: the state it leaves.
  Kept(state: State)
  /// An accepted 0xF2 or 0x63A: the state it leaves, whose place is in the zone
  /// reported, and the WorldZone id the client reports the player stands in (0xF2's, or
  /// 0x63A's new id; opcode.0xf2, opcode.0x63a), which zone chat takes
  /// (genesis_prime/game/chat `world_zone_reported`, `terrain_ready`). `by` says
  /// which message it was, and for a 0x63A holds the old id the client reports, which
  /// the zone's welcome compares with the new (genesis_prime/game/zone_welcome) and
  /// zone chat does not read.
  Reported(state: State, world_zone_id: Int, by: ReportedBy)
  /// An accepted 0x0635: the state it leaves, which it does not change, and the value
  /// the client gives back (opcode.0x635), which tells whether the client holds the
  /// 0x636 the server's last move sent (genesis_prime/game/in_world_move `echoed`).
  Echoed(state: State, echo_value: Int)
  /// An accepted 0x0637: the state it leaves, the place the player now stands
  /// at in the world's frame (`place`), the commands it sent that are relayed,
  /// in the order sent with their bits, and the kinds of those that are not
  /// (`unrelayed`, once each, in the order sent). The game connection tells the
  /// map, which decides who sees this player, and sends the commands to the
  /// connections of the players who see this one
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
    movement_command.FaceUnit(_) -> Unrelayed(18)
    movement_command.FacePoint(_) -> Unrelayed(19)
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
/// say; 0x063A and 0x00F2 give the WorldZone id they report; the others are
/// decoded and nothing more, since the server does nothing with their values:
/// 0xD5 holds the client's world-entry options (input flags and combat log
/// options), 0xFB an impact severity and 0xFC the fall below the floor. A body
/// the client's reader would refuse, or a refused command, is the refusal that
/// ends the connection.
pub fn take(
  state state: State,
  message message: Message,
  body body: BitArray,
) -> Result(Taken, Refusal) {
  case message {
    PlayerMoved ->
      decoded_moves(body:)
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
      world_zone_changed.decode(body)
      |> undecoded(world_zone_changed.message_id)
      |> result.map(fn(decoded) {
        Reported(
          state: in_zone(state:, world_zone_id: decoded.new_world_zone_id),
          world_zone_id: decoded.new_world_zone_id,
          by: ReportedByZoneChanged(
            old_world_zone_id: decoded.old_world_zone_id,
          ),
        )
      })
    WorldEntryOptionsSent ->
      world_entry_options.decode(body)
      |> undecoded(world_entry_options.message_id)
      |> result.replace(Kept(state))
    TerrainReady ->
      terrain_loaded.decode(body)
      |> undecoded(terrain_loaded.message_id)
      |> result.map(fn(decoded) {
        Reported(
          state: in_zone(state:, world_zone_id: decoded.world_zone_id),
          world_zone_id: decoded.world_zone_id,
          by: ReportedByTerrainReady,
        )
      })
    ImpactSeverityReported ->
      impact_severity.decode(body)
      |> undecoded(impact_severity.message_id)
      |> result.replace(Kept(state))
    FellBelowFloor ->
      fell_below_floor.decode(body)
      |> undecoded(fell_below_floor.message_id)
      |> result.replace(Kept(state))
    ControlEchoed ->
      client_control_echoed.decode(body)
      |> undecoded(client_control_echoed.message_id)
      |> result.map(fn(decoded) {
        Echoed(state:, echo_value: decoded.echo_value)
      })
  }
}

/// A 0x637 that is dropped: a dead player's client, whose controlled unit is its
/// ghost, or a client that has not yet taken the server's move of its player.
/// It is decoded and checked as `take` checks the body's, from the body's footing
/// `state`, so a body the client's reader would refuse, or a command its code never
/// sends, is the refusal; else dropped. The client writes the ghost's moves as the
/// body's and expects no answer (`ghost.movement`, `opcode.0x637`), and the body stays
/// where it fell.
pub fn dropped_moved(
  state state: State,
  body body: BitArray,
) -> Result(Nil, Refusal) {
  use decoded <- result.try(decoded_moves(body:))
  moved(state:, moves: moves(message: decoded))
  |> result.replace(Nil)
}

/// A 0x637's body, decoded as the client's reader reads it, or the refusal.
fn decoded_moves(
  body body: BitArray,
) -> Result(player_movement.PlayerMovement, Refusal) {
  player_movement.decode(body)
  |> undecoded(player_movement.message_id)
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
/// the client's own code never sends, in a kind or a value, is refused, and then
/// nothing of the message is kept.
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
    StateFlags(flags:) ->
      Ok(State(..state, moving: int.bitwise_and(flags, 0x2) != 0))
    Mode(mode: 0) | Mode(mode: 1) | Mode(mode: 3) -> Ok(state)
    Mode(mode:) -> Error(UnknownMode(mode:))
    Kind3(path_type:, time_offset:, blends:) -> {
      use _ <- result.try(
        written(kind: 3, field: "path type", value: path_type, only: [0]),
      )
      use _ <- result.try(
        written(kind: 3, field: "time offset", value: time_offset, only: [0]),
      )
      use _ <- result.map(
        written(kind: 3, field: "blend", value: blends, only: [0]),
      )
      state
    }
    Kind10(blends:) ->
      written(kind: 10, field: "blend", value: blends, only: [0])
      |> result.replace(state)
    Kind13(blends:) ->
      written(kind: 13, field: "blend", value: blends, only: [0])
      |> result.replace(state)
    Kind18(blends:) ->
      written(kind: 18, field: "blend", value: blends, only: [1])
      |> result.replace(state)
    Kind20(roll:, time_offset:, blends:) -> {
      use _ <- result.try(
        written(kind: 20, field: "roll", value: roll, only: [0]),
      )
      use _ <- result.try(
        written(kind: 20, field: "time offset", value: time_offset, only: [0]),
      )
      use _ <- result.map(
        written(kind: 20, field: "blend", value: blends, only: [0]),
      )
      state
    }
    Kind25(state_flags:, time_offset:) -> {
      use _ <- result.try(
        list.try_each(state_flags, fn(flags) {
          written(kind: 25, field: "state flags", value: flags, only: [
            0x100,
            0x130,
            0xc,
            0x3c,
          ])
        }),
      )
      use _ <- result.map(
        written(kind: 25, field: "time offset", value: time_offset, only: [0]),
      )
      state
    }
    Unsent(kind:) -> Error(UnsentKind(kind:))
    Other(..) -> Ok(state)
  }
}

/// Whether `value` of `field` in a command of `kind` is one the client writes,
/// among `only`, or why the command is refused.
fn written(
  kind kind: Int,
  field field: String,
  value value: Int,
  only only: List(Int),
) -> Result(Nil, Refusal) {
  use <- bool.guard(when: list.contains(only, value), return: Ok(Nil))
  Error(UnwrittenValue(kind:, field:, value:))
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

/// What the rule leaves unchecked in the client's 0x637, for the coverage
/// measure.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Movement",
      missing: "A 0x637 is not refused for a kind 0 time too far before the message's clock, a per-frame yaw outside one turn, a count of 0 points in kind 3 or 0 keys in kind 25, or kind 20's turn rate of 0: the client's records do not settle them (a tiny turn rate can round to 0 in the half float the client writes).",
    ),
    gap.Entry(
      area: "Movement",
      missing: "A 0x637 is not refused for a kind 1 platform or a kind 18 unit whose unit type the client never names, or that is no unit the player has: that needs the map's units.",
    ),
    gap.Entry(
      area: "Movement",
      missing: "A blend of 1 in kinds 2, 8, 11 and 14 is taken: the client's per-frame update writes 0 or 1 and the other builders write 0, and the server cannot tell which builder sent the command.",
    ),
  ]
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
    UnsentKind(kind:) ->
      "0x0637 holds a command of kind "
      <> int.to_string(kind)
      <> ", which the client never sends"
    UnwrittenValue(kind:, field:, value:) ->
      "0x0637 holds kind "
      <> int.to_string(kind)
      <> "'s "
      <> field
      <> " "
      <> int.to_string(value)
      <> " (0x"
      <> int.to_base16(value)
      <> "), which the client never writes"
    NotDecoded(undecoded:) -> client_connection.describe_undecoded(undecoded:)
  }
}

/// The state that numbers the next save, one above the last this login asked, and that
/// number: for a request that carries the save's number itself.
pub fn next_save(state state: State) -> #(State, Int) {
  let save_sequence = state.save_sequence + 1
  #(State(..state, save_sequence:), save_sequence)
}

/// The save of where the player stands now, named by the login's epoch and
/// numbered one above the last save this login asked, and the state that holds
/// that number, with the `health` the player keeps (`player_life.saved_health`)
/// and the `experience` and `level` it has and the `quests` rows of the quest
/// log the player keeps (`quest_log.rows`). A save asked and never answered
/// keeps its number, so a late answer is never taken for a newer save's.
pub fn save(
  state state: State,
  account_id account_id: AccountId,
  character_id character_id: CharacterId,
  health health: Option(Int),
  experience experience: Int,
  level level: Int,
  quests quests: List(QuestRow),
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
      health:,
      experience:,
      level:,
      quests:,
    ),
  )
}

/// What the store's answer to the save says: nothing for a saved place, a note
/// for a save that changed nothing, and an error for a place, a quest row, a
/// health or an experience the database refused.
pub fn saved(answer answer: MoveAnswer) -> List(Effect) {
  case answer {
    PlaceSaved -> []
    NothingSaved -> [
      Note(
        text: "a save changed nothing: a later login holds the character, a newer save of this login was stored first, or the account has no such character",
      ),
    ]
    PlaceRefused(constraint:) -> [
      Fault(
        text: "the database refused the place it was asked to save, by the constraint "
        <> constraint,
      ),
    ]
    QuestLogRefused(constraint:) -> [
      Fault(
        text: "the database refused a quest row of the log it was asked to save, by the constraint "
        <> constraint,
      ),
    ]
    HealthRefused -> [
      Fault(text: "the database refused the health it was asked to save"),
    ]
    ExperienceRefused -> [
      Fault(text: "the database refused the experience it was asked to save"),
    ]
  }
}
