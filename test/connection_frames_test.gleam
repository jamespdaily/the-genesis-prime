//// The frames the connection writes for a creature's timed path
//// (`genesis_prime/game/connection/frames` `path_frame`). Expected values come from the
//// client's reading of 0x638: kind 0 sets the time and kind 3 holds the times and
//// points of a timed path (`movement_command.kind_0`, `movement_command.kind_3`), with
//// float bits as IEEE 754 binary32 (1.0 is 0x3F800000, 2.0 0x40000000, -3.0 0xC0400000,
//// 4.0 0x40800000, 5.0 0x40A00000, 6.0 0x40C00000 and 1.5 0x3FC00000).

import creature_path_support as support
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection/frames
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/game/world_entry
import genesis_prime/message/float32
import genesis_prime/message/movement_face_point.{MovementFacePoint}
import genesis_prime/message/movement_face_unit.{MovementFaceUnit}
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_move_asked.{MovementMoveAsked}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_timed_path.{MovementTimedPath}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement.{type UnitMovement, UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_turn
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test
import place_support
import world_entry_support

/// A player that entered a map whose clock started at 600 ms on the monotonic clock.
fn entered() -> world_entry.Entered {
  world_entry_support.entered_after(clock_origin_ms: 600)
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
        ..moving(x: 0, z: 0, flags: 0)
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
      ..moving(x: 0, z: 0, flags: 0)
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
      ..moving(x: 0, z: 0, flags: 0)
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

/// The one 0x638 of a face for unit 40 at monotonic 1000 ms, decoded.
fn faced(face face: creature_turn.Face) -> UnitMovement {
  let Frame(message_id:, body:) =
    frames.face_frame(entered: entered(), unit_id: 40, face:, at_ms: 1000)
  assert message_id == 0x0638 as "a face is written as one 0x638"
  let assert Ok(movement) = unit_movement.decode(body)
    as "the frame is a 0x638 the client's reader takes"
  movement
}

pub fn a_face_unit_frame_is_kind_0_then_kind_18_naming_the_unit_with_the_blend_bit_set_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x638 with reset 0: kind 0 holds the map's time (1000 less the start 600 is 400) and kind 18
  // the unit id and the blend bit, which is 1 so the client turns the creature over half a
  // second (`opcode.0x638`, `movement_command.kind_0`, `movement_command.kind_18`).
  let movement = faced(face: creature_turn.Unit(unit_id: 20))
  assert movement.reset_movement == 0 && movement.server_time == 400
  assert movement.commands
    == [
      relayed_movement.Time(MovementTime(time: 400)),
      relayed_movement.FaceUnit(MovementFaceUnit(unit_id: 20, blends: 1)),
    ]
    as "kind 0, then kind 18 naming the unit, blend 1; no position command"
}

pub fn a_face_point_frame_is_kind_0_then_kind_19_at_the_place_test() -> Nil {
  use <- owned_test.run(5000)
  let movement =
    faced(face: creature_turn.Point(place: at(x: 1.0, y: 2.0, z: -3.0)))
  assert movement.commands
    == [
      relayed_movement.Time(MovementTime(time: 400)),
      relayed_movement.FacePoint(MovementFacePoint(
        x: 0x3F800000,
        y: 0x40000000,
        z: 0xC0400000,
        blends: 1,
      )),
    ]
    as "kind 0, then kind 19 with the place's x, y and z as float bits, blend 1"
}

pub fn a_fixed_face_frame_is_kind_0_then_kind_14_that_takes_the_facing_at_once_test() -> Nil {
  use <- owned_test.run(5000)
  let movement =
    faced(
      face: creature_turn.Fixed(facing: Facing(yaw: 1.5, pitch: 0.0, roll: 0.0)),
    )
  assert movement.commands
    == [
      relayed_movement.Time(MovementTime(time: 400)),
      relayed_movement.Rotation(MovementRotation(
        yaw: 0x3FC00000,
        pitch: 0,
        roll: 0,
        blends: 0,
      )),
    ]
    as "kind 0, then kind 14 with the blend bit clear (`0x140715350`), and no position command"
}

/// The 0x638 of a creature that stops at a place, decoded.
fn placed() -> UnitMovement {
  let Frame(message_id:, body:) =
    frames.placed_frame(
      entered: entered(),
      unit_id: 40,
      place: at(x: 1.0, y: 2.0, z: -3.0),
      at_ms: 1000,
    )
  assert message_id == 0x0638 as "a stop is written as one 0x638"
  let assert Ok(movement) = unit_movement.decode(body)
    as "the frame is a 0x638 the client's reader takes"
  movement
}

/// The kind 11 and kind 24 commands of a frame, in order.
fn movement_states(
  movement: UnitMovement,
) -> List(relayed_movement.RelayedMovement) {
  list.filter(movement.commands, fn(command) {
    case command {
      relayed_movement.MoveAsked(..) | relayed_movement.StateFlags(..) -> True
      relayed_movement.Time(..)
      | relayed_movement.Platform(..)
      | relayed_movement.Position(..)
      | relayed_movement.TimedPath(..)
      | relayed_movement.Path(..)
      | relayed_movement.Velocity(..)
      | relayed_movement.Rotation(..)
      | relayed_movement.FaceUnit(..)
      | relayed_movement.FacePoint(..)
      | relayed_movement.Mode(..) -> False
    }
  })
}

/// Kind 11 for a move of `x` and `z` (half float bits) with the blend bit the
/// player sends, and kind 24 with the flags.
fn moving(
  x x: Int,
  z z: Int,
  flags flags: Int,
) -> List(relayed_movement.RelayedMovement) {
  [
    relayed_movement.MoveAsked(MovementMoveAsked(x:, y: 0, z:, blends: 1)),
    relayed_movement.StateFlags(MovementStateFlags(flags:)),
  ]
}

pub fn a_path_frame_carries_the_movement_state_its_path_implies_test() -> Nil {
  use <- owned_test.run(5000)
  // The client animates a unit by kind 24's bit 0x2 and the horizontal length of kind 11's
  // vector, both from the unit's movement commands and not from its path (0x1405b5070); the
  // player sends kind 11 in units a second with the blend bit 1 (the recorded sitting).
  // Half floats: 3.0 is 0x4200, 4.0 0x4400, 10.0 0x4900.
  let cases = [
    #(
      "a run along +x at 10.0 is a move of 10.0 along x and the moving bit",
      sent(path: creature_path.Running(
        from: at(x: 0.0, y: 0.0, z: 0.0),
        via: [],
        to: at(x: 26.0, y: 0.0, z: 0.0),
        started_ms: 1000,
        speed: 10.0,
      )),
      moving(x: 0x4900, z: 0, flags: 2),
    ),
    #(
      "a run up a slope keeps the horizontal part of the velocity and drops its height: 13.0 along (3, 12, 4) is (3, 12, 4) a second",
      sent(path: creature_path.Running(
        from: at(x: 0.0, y: 0.0, z: 0.0),
        via: [],
        to: at(x: 3.0, y: 12.0, z: 4.0),
        started_ms: 1000,
        speed: 13.0,
      )),
      moving(x: 0x4200, z: 0x4400, flags: 2),
    ),
    #(
      "a flight is no walk: it stops the one that ran before the throw",
      sent(path: creature_path.Timed(
        first: #(1000, at(x: 1.0, y: 2.0, z: -3.0)),
        rest: [#(1375, at(x: 4.0, y: 5.0, z: 6.0))],
        turned_to: None,
      )),
      moving(x: 0, z: 0, flags: 0),
    ),
    #(
      "a turn in place is no walk",
      sent(path: creature_path.Timed(
        first: #(1000, at(x: 1.0, y: 2.0, z: -3.0)),
        rest: [],
        turned_to: Some(Facing(yaw: 1.5, pitch: 0.0, roll: 0.0)),
      )),
      moving(x: 0, z: 0, flags: 0),
    ),
    #("a stop ends the animation", placed(), moving(x: 0, z: 0, flags: 0)),
    #(
      "a turn at a unit says nothing of movement, so it does not stop a run",
      faced(face: creature_turn.Unit(unit_id: 20)),
      [],
    ),
    #(
      "a turn at a point says nothing of movement",
      faced(face: creature_turn.Point(place: at(x: 1.0, y: 2.0, z: -3.0))),
      [],
    ),
    #(
      "a fixed turn says nothing of movement",
      faced(
        face: creature_turn.Fixed(facing: Facing(
          yaw: 1.5,
          pitch: 0.0,
          roll: 0.0,
        )),
      ),
      [],
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, movement, expected) = row
    assert movement_states(movement) == expected as reason
  })
  assert frames.path_frame(
      entered: entered(),
      unit_id: 40,
      path: creature_path.Running(
        from: at(x: 0.0, y: 0.0, z: 0.0),
        via: [],
        to: at(x: 26.0, y: 0.0, z: 0.0),
        started_ms: 1000,
        speed: 70_000.0,
      ),
    )
    == None
    as "a speed no half float holds is still no frame"
}

/// The kind 4 points a path frame carries, in order, as the float bits of each.
fn written_points(
  path path: creature_path.Path,
) -> Option(List(#(Int, Int, Int))) {
  case frames.path_frame(entered: entered(), unit_id: 40, path:) {
    None -> None
    Some(Frame(body:, ..)) -> {
      let assert Ok(UnitMovement(commands:, ..)) = unit_movement.decode(body)
        as "the frame is a 0x638 the client's reader takes"
      let assert [relayed_movement.Path(path)] =
        list.filter(commands, fn(command) {
          case command {
            relayed_movement.Path(..) -> True
            relayed_movement.Time(..)
            | relayed_movement.Platform(..)
            | relayed_movement.Position(..)
            | relayed_movement.TimedPath(..)
            | relayed_movement.Velocity(..)
            | relayed_movement.Rotation(..)
            | relayed_movement.FaceUnit(..)
            | relayed_movement.FacePoint(..)
            | relayed_movement.StateFlags(..)
            | relayed_movement.MoveAsked(..)
            | relayed_movement.Mode(..) -> False
          }
        })
        as "one kind 4"
      Some(list.map(path.points, fn(point) { #(point.x, point.y, point.z) }))
    }
  }
}

pub fn a_path_frame_holds_every_point_or_none_test() -> Nil {
  use <- owned_test.run(5000)
  // Kind 4's count is 10 bits, so 1023 points are the most it holds
  // (`movement_command.kind_4`); a point is three 32-bit floats, x counting up here.
  let cases = [
    #("28 points are written in order", 28),
    #("1023 points, the most a kind 4 holds, are written in order", 1023),
    #(
      "1024 points are more than the count holds: no frame, and the connection lives",
      1024,
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, count) = row
    let path =
      support.running(
        points: support.line(count:),
        started_ms: 1000,
        speed: 10.0,
      )
    case count > 1023 {
      True -> {
        assert written_points(path:) == None as reason
      }
      False -> {
        assert written_points(path:)
          == Some(
            list.index_map(support.line(count:), fn(_, index) {
              #(float32.to_bits(int.to_float(index)), 0, 0)
            }),
          )
          as reason
      }
    }
  })
  // The count is checked before any geometry: a first leg of 1e200 squares past the
  // largest float, which the geometry would crash on.
  let huge =
    support.running(
      points: [#(1.0e200, 0.0, 0.0), ..support.line(count: 1023)],
      started_ms: 1000,
      speed: 10.0,
    )
  assert written_points(path: huge) == None
    as "1024 points are refused before the geometry of their first leg is computed"
}

pub fn a_two_point_path_frame_is_the_bytes_it_was_test() -> Nil {
  use <- owned_test.run(5000)
  // The body the path frame made for this run before a run could hold more points,
  // taken from origin/main 548056f0: unit 40, kind 0 at 400 (1000 less the map's 600),
  // kind 4 of (1.5, -2, 3) and (26, 4.5, -7.25) at 7.5 (half float 0x4780), type 0, mode 0,
  // then kind 11 and kind 24.
  let assert Ok(before) =
    bit_array.base16_decode(
      "280000009001000010001900004004000000FE01000000060000020200800E0200800402004007063C02000000002C5C230000D0E05800000000",
    )
    as "a hex string"
  let assert Some(Frame(message_id: 0x0638, body:)) =
    frames.path_frame(
      entered: entered(),
      unit_id: 40,
      path: creature_path.Running(
        from: at(x: 1.5, y: -2.0, z: 3.0),
        via: [],
        to: at(x: 26.0, y: 4.5, z: -7.25),
        started_ms: 1000,
        speed: 7.5,
      ),
    )
  assert body == before
}
