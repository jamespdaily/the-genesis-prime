//// The sitting bot's follow walk (`genesis_prime/sitting_bot/follow`): the
//// movement commands it keeps for the named character's unit and sends back as
//// its own. Expected values come from these places.
//// - The commands the server relays in 0x0638 are the kinds 1, 2, 8, 11, 14, 24
////   and 27 of the client's own 0x0637 batch, the time command left out
////   (opcode.0x637, opcode.0x638, `genesis_prime/game/movement`), and the
////   client's batch has the same layout, so a replay holds each as relayed.
//// - The client's batch starts with a time command, the clock plus twice the
////   movement send interval, 125 ms until the server sets one
////   (0x14057a190, opcode.0xf1).
//// - The tool's contract, its module doc: a replay is the commands as relayed,
////   position included; the first stamp is due the delay after it was read, and
////   each later one the stamps' distance after it; a unit that stands still
////   sends nothing.

import genesis_prime/message/float32
import genesis_prime/message/movement_command
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/movement_move_asked.{MovementMoveAsked}
import genesis_prime/message/movement_platform.{MovementPlatform}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_velocity.{MovementVelocity}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
import genesis_prime/sitting_bot/follow
import gleam/option.{None, Some}
import owned_test
import unitest

fn position(x x: Float, y y: Float, z z: Float) -> UnitPositionCommand {
  UnitPositionCommand(
    x: float32.to_bits(x),
    y: float32.to_bits(y),
    z: float32.to_bits(z),
    blends: 0,
  )
}

/// One of each command the server relays, as the client sent them standing on
/// the world (kind 1 is 0) and running: every field a value of its own.
fn relayed() -> List(RelayedMovement) {
  [
    relayed_movement.Platform(MovementPlatform(unit_id: 0)),
    relayed_movement.Position(position(x: 100.5, y: 50.25, z: -200.75)),
    relayed_movement.Velocity(MovementVelocity(
      x: 0x3C00,
      y: 0x0000,
      z: 0x4000,
      blends: 1,
    )),
    relayed_movement.MoveAsked(MovementMoveAsked(
      x: 0x0000,
      y: 0x0000,
      z: 0x4400,
      blends: 1,
    )),
    relayed_movement.Rotation(MovementRotation(
      yaw: 0x3F000000,
      pitch: 0,
      roll: 0,
      blends: 0,
    )),
    relayed_movement.StateFlags(MovementStateFlags(flags: 0x3FFFF)),
    relayed_movement.Mode(MovementMode(mode: 3)),
  ]
}

pub fn a_replay_is_every_command_as_relayed_the_position_too_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("dev_tool")
  assert follow.replayed(relayed())
    == [
      movement_command.Platform(MovementPlatform(unit_id: 0)),
      movement_command.Position(position(x: 100.5, y: 50.25, z: -200.75)),
      movement_command.Velocity(MovementVelocity(
        x: 0x3C00,
        y: 0x0000,
        z: 0x4000,
        blends: 1,
      )),
      movement_command.MoveAsked(MovementMoveAsked(
        x: 0x0000,
        y: 0x0000,
        z: 0x4400,
        blends: 1,
      )),
      movement_command.Rotation(MovementRotation(
        yaw: 0x3F000000,
        pitch: 0,
        roll: 0,
        blends: 0,
      )),
      movement_command.StateFlags(MovementStateFlags(flags: 0x3FFFF)),
      movement_command.Mode(MovementMode(mode: 3)),
    ]
    as "opcode.0x637: the position, the velocity, the move asked, the state, the mode, the rotation and the platform are the real client's, so the bot walks the path the client walked"
}

pub fn a_replay_is_sent_with_a_time_command_twice_the_send_interval_after_the_bots_clock_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("dev_tool")
  let commands = follow.replayed(relayed())
  assert follow.stamped(commands:, clock_ms: 5000)
    == [movement_command.Time(MovementTime(time: 5250)), ..commands]
    as "0x14057a190: the clock plus twice 125 ms (opcode.0xf1), then the commands"
}

/// A relayed batch that holds one rotation, whose yaw tells which it is.
fn batch(number: Int) -> List(RelayedMovement) {
  [
    relayed_movement.Rotation(MovementRotation(
      yaw: number,
      pitch: 0,
      roll: 0,
      blends: 0,
    )),
  ]
}

fn batch_replayed(number: Int) -> List(movement_command.MovementCommand) {
  follow.replayed(batch(number))
}

/// A follow of "Zed Qu", 2 s late, which has been shown his unit 7.
fn following() -> follow.Following {
  follow.shown(
    following: follow.new(near: "Zed Qu", delay_ms: 2000),
    unit_id: 7,
    name: "zed QU",
  )
}

pub fn each_replay_is_due_the_delay_after_the_first_stamp_at_the_stamps_spacing_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("dev_tool")
  // Three moves stamped 125 and 375 ms apart; the second and third are read
  // late and together (the bot's clock 10,900 and 10,901), which changes nothing.
  let held =
    following()
    |> follow.moved(
      unit_id: 7,
      server_time: 50_000,
      commands: batch(1),
      elapsed_ms: 10_000,
    )
    |> follow.moved(
      unit_id: 7,
      server_time: 50_125,
      commands: batch(2),
      elapsed_ms: 10_900,
    )
    |> follow.moved(
      unit_id: 7,
      server_time: 50_500,
      commands: batch(3),
      elapsed_ms: 10_901,
    )
  assert follow.next_due_ms(held) == Some(12_000)
    as "the first stamp is due the delay after the bot's clock read it"
  assert follow.take_due(following: held, elapsed_ms: 11_999) == Error(Nil)
    as "a replay is not taken before its time"
  let assert Ok(#(first, held)) =
    follow.take_due(following: held, elapsed_ms: 12_000)
  assert first == batch_replayed(1)
  assert follow.next_due_ms(held) == Some(12_125)
    as "the second is due the stamps' 125 ms after the first"
  let assert Ok(#(second, held)) =
    follow.take_due(following: held, elapsed_ms: 12_125)
  assert second == batch_replayed(2)
  assert follow.next_due_ms(held) == Some(12_500)
    as "the third is due the stamps' 375 ms after the second, whatever the arrival"
  let assert Ok(#(third, held)) =
    follow.take_due(following: held, elapsed_ms: 20_000)
  assert third == batch_replayed(3)
  assert follow.next_due_ms(held) == None
}

pub fn stamps_that_wrap_past_2_to_the_32_keep_their_spacing_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("dev_tool")
  let held =
    following()
    |> follow.moved(
      unit_id: 7,
      server_time: 4_294_967_290,
      commands: batch(1),
      elapsed_ms: 1000,
    )
    |> follow.moved(
      unit_id: 7,
      server_time: 119,
      commands: batch(2),
      elapsed_ms: 1001,
    )
  let assert Ok(#(_, held)) = follow.take_due(following: held, elapsed_ms: 3000)
  assert follow.next_due_ms(held) == Some(3125)
    as "the map's clock is mod 2^32 (opcode.0x638): 4,294,967,290 to 119 is 125 ms"
}

pub fn a_move_of_another_unit_or_before_the_named_unit_is_shown_is_not_followed_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("dev_tool")
  let strangers =
    follow.new(near: "Zed Qu", delay_ms: 2000)
    |> follow.moved(
      unit_id: 7,
      server_time: 1,
      commands: batch(1),
      elapsed_ms: 1,
    )
  assert follow.next_due_ms(strangers) == None
    as "a unit not yet shown as the named character is no one to follow"
  let held =
    following()
    |> follow.shown(unit_id: 8, name: "Ann Qu")
    |> follow.moved(
      unit_id: 8,
      server_time: 1,
      commands: batch(1),
      elapsed_ms: 1,
    )
  assert follow.next_due_ms(held) == None
    as "another unit's moves are not replayed"
}

pub fn a_unit_that_stands_still_leaves_nothing_to_replay_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("dev_tool")
  assert follow.next_due_ms(following()) == None
    as "a standing unit sends no 0x0638 (opcode.0x637), so the bot stands still"
}

pub fn the_followed_units_removal_stops_the_follow_and_drops_what_waited_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("dev_tool")
  let held =
    following()
    |> follow.moved(
      unit_id: 7,
      server_time: 50_000,
      commands: batch(1),
      elapsed_ms: 10_000,
    )
    |> follow.removed(unit_id: 8)
  assert follow.next_due_ms(held) == Some(12_000)
    as "another unit's removal changes nothing"
  let held = follow.removed(following: held, unit_id: 7)
  assert follow.next_due_ms(held) == None
    as "opcode.0x355: the unit is gone, and what it was to walk is not replayed"
  let held =
    follow.moved(
      following: held,
      unit_id: 7,
      server_time: 60_000,
      commands: batch(2),
      elapsed_ms: 20_000,
    )
  assert follow.next_due_ms(held) == None
    as "a unit that is not shown is not followed"
}

pub fn the_named_character_shown_again_is_followed_from_a_new_first_stamp_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("dev_tool")
  let held =
    following()
    |> follow.moved(
      unit_id: 7,
      server_time: 50_000,
      commands: batch(1),
      elapsed_ms: 10_000,
    )
    |> follow.removed(unit_id: 7)
    |> follow.shown(unit_id: 9, name: "Zed Qu")
    |> follow.moved(
      unit_id: 9,
      server_time: 90_000,
      commands: batch(2),
      elapsed_ms: 30_000,
    )
  assert follow.next_due_ms(held) == Some(32_000)
    as "a new unit has its own first stamp, with nothing left of the old one"
  let assert Ok(#(commands, _)) =
    follow.take_due(following: held, elapsed_ms: 32_000)
  assert commands == batch_replayed(2)
}
