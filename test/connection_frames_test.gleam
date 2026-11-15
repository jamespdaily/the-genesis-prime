//// The frames the connection writes for a creature's timed path
//// (`genesis_prime/game/connection/frames` `path_frame`). Expected values come from the
//// client's reading of 0x638: kind 0 sets the time and kind 3 holds the times and
//// points of a timed path (`movement_command.kind_0`, `movement_command.kind_3`), with
//// float bits as IEEE 754 binary32 (1.0 is 0x3F800000, 2.0 0x40000000, -3.0 0xC0400000,
//// 4.0 0x40800000, 5.0 0x40A00000, 6.0 0x40C00000 and 1.5 0x3FC00000).

import character_tables
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection/frames
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/game/world_entry
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_timed_path.{MovementTimedPath}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement.{type UnitMovement, UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/world_map/creature_path
import gleam/option.{None, Some}
import owned_test
import place_support
import world_entry_support

/// A player that entered a map whose clock started at 600 ms on the monotonic clock.
fn entered() -> world_entry.Entered {
  let #(_, entered) =
    world_entry_support.entry(
      tables: character_tables.shared(),
      character: world_entry_support.character(class: 4, faction: 167, level: 1),
    )
  world_entry.Entered(..entered, clock_origin_ms: 600)
}

fn at(x x: Float, y y: Float, z z: Float) -> Place {
  place_support.at(world_id: 3460, world_zone_id: 6009, x:, y:, z:)
}

/// The one 0x638 of a path for unit 40, decoded.
fn sent(path path: creature_path.Path) -> UnitMovement {
  let assert Some(Frame(message_id: 0x0638, body:)) =
    frames.path_frame(entered: entered(), unit_id: 40, path:)
    as "a timed path is written as one 0x638"
  let assert Ok(movement) = unit_movement.decode(body)
    as "the frame is a 0x638 the client's reader takes"
  movement
}

pub fn a_timed_path_frame_turns_each_time_into_server_time_test() -> Nil {
  use <- owned_test.run(5000)
  let movement =
    sent(path: creature_path.Timed(
      first: #(1000, at(x: 1.0, y: 2.0, z: -3.0)),
      rest: [#(1375, at(x: 4.0, y: 5.0, z: 6.0))],
      turned_to: None,
    ))
  assert movement
    == UnitMovement(
      unit_id: 40,
      server_time: 400,
      reset_movement: 0,
      kept: 0,
      commands: [
        relayed_movement.Time(MovementTime(time: 400)),
        relayed_movement.TimedPath(
          MovementTimedPath(times: [400, 775], points: [
            MovementFloatVector(x: 0x3F800000, y: 0x40000000, z: 0xC0400000),
            MovementFloatVector(x: 0x40800000, y: 0x40A00000, z: 0x40C00000),
          ]),
        ),
      ],
    )
    as "the monotonic times 1000 and 1375 less the map's start 600 are 400 and 775, the first also the clock of kind 0"
}

pub fn a_timed_path_of_one_point_places_the_creature_there_test() -> Nil {
  use <- owned_test.run(5000)
  let movement =
    sent(path: creature_path.Timed(
      first: #(1000, at(x: 1.0, y: 2.0, z: -3.0)),
      rest: [],
      turned_to: None,
    ))
  assert movement.commands
    == [
      relayed_movement.Time(MovementTime(time: 400)),
      relayed_movement.Position(UnitPositionCommand(
        x: 0x3F800000,
        y: 0x40000000,
        z: 0xC0400000,
        blends: 0,
      )),
    ]
    as "a flight of no length is a kind 2 at its point, which places the unit at once (0x140714120)"
}

pub fn a_timed_path_that_turns_the_creature_ends_with_its_rotation_test() -> Nil {
  use <- owned_test.run(5000)
  let movement =
    sent(path: creature_path.Timed(
      first: #(1000, at(x: 1.0, y: 2.0, z: -3.0)),
      rest: [#(1375, at(x: 4.0, y: 5.0, z: 6.0))],
      turned_to: Some(Facing(yaw: 1.5, pitch: 0.0, roll: 0.0)),
    ))
  assert movement.commands
    == [
      relayed_movement.Time(MovementTime(time: 400)),
      relayed_movement.TimedPath(
        MovementTimedPath(times: [400, 775], points: [
          MovementFloatVector(x: 0x3F800000, y: 0x40000000, z: 0xC0400000),
          MovementFloatVector(x: 0x40800000, y: 0x40A00000, z: 0x40C00000),
        ]),
      ),
      relayed_movement.Rotation(MovementRotation(
        yaw: 0x3FC00000,
        pitch: 0,
        roll: 0,
        blends: 0,
      )),
    ]
    as "the path's turn is one kind 14 after the path, the yaw 1.5 as float bits"
}

pub fn a_standing_creature_has_no_path_frame_test() -> Nil {
  use <- owned_test.run(5000)
  assert frames.path_frame(
      entered: entered(),
      unit_id: 40,
      path: creature_path.Standing(at: at(x: 1.0, y: 2.0, z: -3.0)),
    )
    == None
    as "a creature that stands has no path to write"
}
