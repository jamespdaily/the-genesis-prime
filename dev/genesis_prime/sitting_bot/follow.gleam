//// The sitting bot's follow walk: it keeps the movement commands the server
//// relays for the named character's unit and sends each back as its own 0x0637
//// some time later, so the bot walks the path the real client walked, on the
//// ground it walked, and the client animates it from the same velocity, move
//// and state commands the real client's own player sent.
////
//// ```
//// 0x0262 of the named name ─▶ shown        ─▶ the unit to follow
//// 0x0638 of that unit      ─▶ moved        ─▶ a replay, due `delay_ms` after the
////                                              server stamped it, in the order and
////                                              at the spacing of the stamps
//// the bot's clock          ─▶ take_due     ─▶ the commands to send as a 0x0637
//// 0x0355 of that unit      ─▶ removed      ─▶ nothing left to replay
//// ```
////
//// - A replay is every command as the server relayed it (the kinds 1, 2, 8, 11,
////   14, 24 and 27 of `relayed_movement`, the ones the server relays of the
////   client's own batch, opcode.0x637), position included: the bot stands where
////   the named character stood, 2 s later. The velocity, the move asked, the
////   state flags, the mode and the rotation are the real client's, so the
////   animation they give is too.
//// - The spacing is the spacing of the server's stamps (`server_time` of each
////   0x0638, opcode.0x638), not of the bytes' arrival, so a burst read at once
////   replays as it was walked. The first stamp is due `delay_ms` after the
////   bot's own clock read it; each later one is due the stamp's distance after.
//// - The time the bot's own batch is sent with is the bot's clock: the header
////   holds it, and the time command before the commands holds it plus twice the
////   movement send interval, as the client's own batch does (0x14057a190,
////   opcode.0xf1). The server takes neither (kind 0 is never relayed, and the
////   client clock is not read), so the bot's clock only has to be its own.
//// - A unit that stands still sends no 0x0638, so the bot stands still.

import genesis_prime/message/movement_command.{type MovementCommand}
import genesis_prime/message/movement_kind_4.{MovementKind4}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// The client's movement send interval until the server sets one (opcode.0xf1),
/// which the time command of a batch is placed twice after the clock.
const send_interval_ms = 125

/// The server's clock in 0x0638 is the map's, mod 2^32 (opcode.0x638).
const server_time_modulus = 4_294_967_296

/// The bot's clock when it read the first stamp, and that stamp.
pub type Origin {
  Origin(server_time: Int, elapsed_ms: Int)
}

/// One replay: the commands to send and the time on the bot's clock they are
/// due.
pub type Replay {
  Replay(due_ms: Int, commands: List(MovementCommand))
}

/// The unit followed, if the named character's has been shown, and the replays
/// waiting for their time.
pub type Following {
  Following(
    near: String,
    delay_ms: Int,
    unit_id: Option(Int),
    origin: Option(Origin),
    waiting: List(Replay),
  )
}

/// A follow of the character with this name that has seen nothing yet: each
/// replay is due `delay_ms` after the server stamped it.
pub fn new(near near: String, delay_ms delay_ms: Int) -> Following {
  Following(near:, delay_ms:, unit_id: None, origin: None, waiting: [])
}

/// A unit shown to the bot: when its name is the named character's, in any case
/// as names are unique in any case, it is the unit to follow, with nothing
/// waiting from an earlier one.
pub fn shown(
  following following: Following,
  unit_id unit_id: Int,
  name name: String,
) -> Following {
  use <- bool.guard(
    when: string.lowercase(name) != string.lowercase(following.near),
    return: following,
  )
  Following(..following, unit_id: Some(unit_id), origin: None, waiting: [])
}

/// A unit removed: the followed unit's end stops the follow, and what was waiting
/// is dropped.
pub fn removed(
  following following: Following,
  unit_id unit_id: Int,
) -> Following {
  use <- bool.guard(when: following.unit_id != Some(unit_id), return: following)
  Following(..following, unit_id: None, origin: None, waiting: [])
}

/// A 0x0638 of a unit, stamped `server_time`, read when the bot's clock was
/// `elapsed_ms`: the followed unit's commands wait for their time, any other
/// unit's are dropped.
pub fn moved(
  following following: Following,
  unit_id unit_id: Int,
  server_time server_time: Int,
  commands commands: List(RelayedMovement),
  elapsed_ms elapsed_ms: Int,
) -> Following {
  use <- bool.guard(when: following.unit_id != Some(unit_id), return: following)
  let origin = case following.origin {
    Some(origin) -> origin
    None -> Origin(server_time:, elapsed_ms:)
  }
  let after_ms =
    { server_time - origin.server_time + server_time_modulus }
    % server_time_modulus
  let replay =
    Replay(
      due_ms: origin.elapsed_ms + after_ms + following.delay_ms,
      commands: replayed(commands),
    )
  Following(
    ..following,
    origin: Some(origin),
    waiting: list.append(following.waiting, [replay]),
  )
}

/// When the next replay is due on the bot's clock, if any waits.
pub fn next_due_ms(following: Following) -> Option(Int) {
  case following.waiting {
    [Replay(due_ms:, ..), ..] -> Some(due_ms)
    [] -> None
  }
}

/// The commands of the next replay when its time has come, and the follow
/// without it.
pub fn take_due(
  following following: Following,
  elapsed_ms elapsed_ms: Int,
) -> Result(#(List(MovementCommand), Following), Nil) {
  case following.waiting {
    [Replay(due_ms:, commands:), ..rest] if due_ms <= elapsed_ms ->
      Ok(#(commands, Following(..following, waiting: rest)))
    _ -> Error(Nil)
  }
}

/// The commands of a 0x0638 as the client's own 0x0637 holds them: each one as
/// relayed.
pub fn replayed(commands: List(RelayedMovement)) -> List(MovementCommand) {
  list.map(commands, fn(command) {
    case command {
      relayed_movement.Time(data) -> movement_command.Time(data)
      relayed_movement.Platform(data) -> movement_command.Platform(data)
      relayed_movement.Position(data) -> movement_command.Position(data)
      relayed_movement.Path(data) ->
        movement_command.Kind4(MovementKind4(
          points: data.points,
          speed: data.speed,
          path_type: data.path_type,
          mode: data.mode,
          field_5: 0,
          field_6: 0,
        ))
      relayed_movement.Velocity(data) -> movement_command.Velocity(data)
      relayed_movement.MoveAsked(data) -> movement_command.MoveAsked(data)
      relayed_movement.Rotation(data) -> movement_command.Rotation(data)
      relayed_movement.StateFlags(data) -> movement_command.StateFlags(data)
      relayed_movement.Mode(data) -> movement_command.Mode(data)
    }
  })
}

/// The commands as a batch with the bot's clock: the time command first, the
/// clock plus twice the movement send interval, as the client's own batch
/// starts (0x14057a190).
pub fn stamped(
  commands commands: List(MovementCommand),
  clock_ms clock_ms: Int,
) -> List(MovementCommand) {
  [
    movement_command.Time(MovementTime(time: clock_ms + 2 * send_interval_ms)),
    ..commands
  ]
}
