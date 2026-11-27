//// The frames the connection writes for a creature's timed path
//// (`genesis_prime/game/connection/frames` `path_frame`). Expected values come from the
//// client's reading of 0x638: kind 0 sets the time and kind 3 holds the times and
//// points of a timed path (`movement_command.kind_0`, `movement_command.kind_3`), with
//// float bits as IEEE 754 binary32 (1.0 is 0x3F800000, 2.0 0x40000000, -3.0 0xC0400000,
//// 4.0 0x40800000, 5.0 0x40A00000, 6.0 0x40C00000 and 1.5 0x3FC00000).

import ask_support
import creature_path_support as support
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection/frames
import genesis_prime/game/player_life
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/game/world_entry
import genesis_prime/message/float32
import genesis_prime/message/movement_face_point.{MovementFacePoint}
import genesis_prime/message/movement_face_unit.{MovementFaceUnit}
import genesis_prime/message/movement_float_vector.{MovementFloatVector}
import genesis_prime/message/movement_kind_10.{MovementKind10}
import genesis_prime/message/movement_kind_13.{MovementKind13}
import genesis_prime/message/movement_kind_21.{MovementKind21}
import genesis_prime/message/movement_kind_26.{MovementKind26}
import genesis_prime/message/movement_move_asked.{MovementMoveAsked}
import genesis_prime/message/movement_rotation.{MovementRotation}
import genesis_prime/message/movement_state_flags.{MovementStateFlags}
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_timed_path.{MovementTimedPath}
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_create_ghost
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/message/unit_float_stat_changed.{UnitFloatStatChanged}
import genesis_prime/message/unit_movement.{type UnitMovement, UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/step.{Now}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_turn
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
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
    frames.path_frame(entered: entered(), unit_id: 40, path:, face: None)
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
      kept: 1,
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
      face: None,
      path: creature_path.Standing(at: at(x: 1.0, y: 2.0, z: -3.0)),
    )
    == None
    as "a creature that stands has no path to write"
}

/// The one 0x638 of a face for unit 40 at monotonic 1000 ms, decoded.
fn faced(face face: creature_turn.Face) -> UnitMovement {
  let Frame(message_id:, body:) =
    frames.face_frame(
      entered: entered(),
      unit_id: 40,
      standing_at: at(x: 1.0, y: 2.0, z: -3.0),
      face:,
      at_ms: 1000,
    )
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
  // A creature killed or held keeps its facing by kind 14 with the blend bit clear
  // (`0x140715350`), as the client reads the bit: no kind 19, which would keep turning a corpse
  // that flies on after its death toward a point it left behind. The roll is carried as it is.
  let cases = [
    #("yaw only", Facing(yaw: 1.5, pitch: 0.0, roll: 0.0), #(0x3FC00000, 0, 0)),
    #(
      "yaw, pitch and roll",
      Facing(yaw: -2.0, pitch: 0.5, roll: 0.25),
      #(0xC0000000, 0x3F000000, 0x3E800000),
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, facing, #(yaw, pitch, roll)) = row
    let movement = faced(face: creature_turn.Fixed(facing:))
    assert movement.commands
      == [
        relayed_movement.Time(MovementTime(time: 400)),
        relayed_movement.Rotation(MovementRotation(
          yaw:,
          pitch:,
          roll:,
          blends: 0,
        )),
      ]
      as {
        reason
        <> ": kind 0, then kind 14 with the bit clear, no position command"
      }
  })
}

pub fn a_creature_arriving_home_turns_to_its_spawn_facing_over_the_clients_blend_test() -> Nil {
  use <- owned_test.run(5000)
  // A home facing is written as kind 19 toward the point 1 m on along the facing from the
  // unit's place (1, 2, -3), blend bit set: the client turns the unit over half a second and
  // its facing from the unit to the point is the facing (`movement_command.kind_19`,
  // `0x140715c00`). The client's yaw and pitch of a direction are atan2(-x, -z) and asin(y)
  // (`0x1401b3170`), so the direction is (-sin yaw cos pitch, sin pitch, -cos yaw cos pitch):
  // yaw 0 faces -z, pi/2 faces -x, pi faces +z, -pi/2 faces +x, a positive pitch faces up.
  // Float bits written from that formula: 1.0 0x3F800000, 1.5 0x3FC00000, 2.0 0x40000000,
  // 2.5 0x40200000, -2.0 0xC0000000, -3.0 0xC0400000, -4.0 0xC0800000; 1 - sqrt(3)/2 is
  // 0x3E0930A3 and -3 + sqrt(3)/2 is 0xC008930A.
  let half_turn = 3.141592653589793
  let cases = [
    #("yaw 0 faces -z", 0.0, 0.0, #(0x3F800000, 0x40000000, 0xC0800000)),
    #("yaw pi/2 faces -x", half_turn /. 2.0, 0.0, #(0, 0x40000000, 0xC0400000)),
    #("yaw pi faces +z", half_turn, 0.0, #(0x3F800000, 0x40000000, 0xC0000000)),
    #(
      "yaw -pi/2 faces +x",
      0.0 -. half_turn /. 2.0,
      0.0,
      #(0x40000000, 0x40000000, 0xC0400000),
    ),
    #(
      "yaw pi/2 and pitch pi/6 faces -x, tilted up: x is cos 30 degrees short, y 0.5 above",
      half_turn /. 2.0,
      half_turn /. 6.0,
      #(0x3E0930A3, 0x40200000, 0xC0400000),
    ),
    #(
      "yaw pi and pitch -pi/6 faces +z, tilted down: z is cos 30 degrees on, y 0.5 below",
      half_turn,
      0.0 -. half_turn /. 6.0,
      #(0x3F800000, 0x3FC00000, 0xC008930A),
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, yaw, pitch, #(x, y, z)) = row
    let movement =
      faced(face: creature_turn.Home(facing: Facing(yaw:, pitch:, roll: 0.0)))
    assert movement.commands
      == [
        relayed_movement.Time(MovementTime(time: 400)),
        relayed_movement.FacePoint(MovementFacePoint(x:, y:, z:, blends: 1)),
      ]
      as {
        reason
        <> ": kind 0, then kind 19 at the point 1 m along the facing, blend 1"
      }
  })
}

pub fn a_home_facing_straight_up_or_down_is_kind_19_at_a_point_over_or_under_the_place_test() -> Nil {
  use <- owned_test.run(5000)
  // Straight up or down is the point 1 m above or below the place (1, 2, -3), whatever the
  // yaw: the client's direction-to-angles gives yaw 0 and pitch plus or minus pi/2 there
  // (`0x1401b3170`), so the yaw is not shown. Yaw pi is the one that would show if it were.
  let half_turn = 3.141592653589793
  list.each(
    [#(half_turn /. 2.0, 0x40400000), #(0.0 -. half_turn /. 2.0, 0x3F800000)],
    fn(row) {
      let #(pitch, y) = row
      let movement =
        faced(
          face: creature_turn.Home(facing: Facing(
            yaw: half_turn,
            pitch:,
            roll: 0.0,
          )),
        )
      assert movement.commands
        == [
          relayed_movement.Time(MovementTime(time: 400)),
          relayed_movement.FacePoint(MovementFacePoint(
            x: 0x3F800000,
            y:,
            z: 0xC0400000,
            blends: 1,
          )),
        ]
        as "the point is straight over or under the place: x 1.0 and z -3.0 are the place's"
    },
  )
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

/// The commands of a frame that set the unit's velocity, requested move, rotation or movement
/// state by a track or a default (kinds 10, 11, 13, 21, 24 and 26), in order.
fn movement_states(
  movement: UnitMovement,
) -> List(relayed_movement.RelayedMovement) {
  list.filter(movement.commands, fn(command) {
    case command {
      relayed_movement.MoveAsked(..)
      | relayed_movement.StateFlags(..)
      | relayed_movement.VelocityDefault(..)
      | relayed_movement.MoveDefault(..)
      | relayed_movement.RotationDefault(..)
      | relayed_movement.StateDefault(..) -> True
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

/// Kinds 10, 13, 21 and 26, each with its blend bit 1: the client's own defaults for a unit
/// that runs a kind 4 path (`movement_command.defaults_with_kind_4_path`,
/// `movement_command.kind_13`, `movement_command.kind_21`).
fn path_defaults() -> List(relayed_movement.RelayedMovement) {
  [
    relayed_movement.VelocityDefault(MovementKind10(blends: 1)),
    relayed_movement.MoveDefault(MovementKind13(blends: 1)),
    relayed_movement.RotationDefault(MovementKind21(blends: 1)),
    relayed_movement.StateDefault(MovementKind26(blends: 1)),
  ]
}

pub fn a_creatures_0x638_turns_the_clients_ground_lift_on_and_carries_the_movement_state_its_path_implies_test() -> Nil {
  use <- owned_test.run(5000)
  // A run sends kinds 10, 13, 21 and 26 with the blend bit 1: the client then takes the
  // velocity, the requested move (which its pace and its state's moving bit follow), the
  // facing and the state from the path itself (`movement_command.defaults_with_kind_4_path`).
  // A stop, a flight and a turn keep their explicit commands.
  // The client's ground lift runs only while the 0x638's second bit is 1 (the unit's
  // ground-follow flag), and pulls a unit above the ground down only while its state flags
  // hold 0x100, so a creature's moving state is 0x102 and its standing state 0x100; a flight's
  // state is 0, so its arc is not pulled down (`unit.ground_lift.server_commands`).
  let cases = [
    #(
      "a run along +x at 10.0 takes the client's four defaults and no explicit move or state",
      sent(path: creature_path.Running(
        from: at(x: 0.0, y: 0.0, z: 0.0),
        via: [],
        to: at(x: 26.0, y: 0.0, z: 0.0),
        started_ms: 1000,
        speed: 10.0,
      )),
      path_defaults(),
    ),
    #(
      "a run up a slope takes the same four defaults: the path gives the velocity and the facing",
      sent(path: creature_path.Running(
        from: at(x: 0.0, y: 0.0, z: 0.0),
        via: [],
        to: at(x: 3.0, y: 12.0, z: 4.0),
        started_ms: 1000,
        speed: 13.0,
      )),
      path_defaults(),
    ),
    #(
      "a run of three points takes the same four defaults: they follow each leg",
      sent(path: creature_path.Running(
        from: at(x: 0.0, y: 0.0, z: 0.0),
        via: [at(x: 10.0, y: 0.0, z: 0.0)],
        to: at(x: 10.0, y: 0.0, z: 10.0),
        started_ms: 1000,
        speed: 10.0,
      )),
      path_defaults(),
    ),
    #(
      "a flight is no walk and has no ground bit: it stops the one that ran before the throw and its arc is not pulled down",
      sent(path: creature_path.Timed(
        first: #(1000, at(x: 1.0, y: 2.0, z: -3.0)),
        rest: [#(1375, at(x: 4.0, y: 5.0, z: 6.0))],
        turned_to: None,
      )),
      moving(x: 0, z: 0, flags: 0),
    ),
    #(
      "a turn in place is a timed frame: no walk and no ground bit",
      sent(path: creature_path.Timed(
        first: #(1000, at(x: 1.0, y: 2.0, z: -3.0)),
        rest: [],
        turned_to: Some(Facing(yaw: 1.5, pitch: 0.0, roll: 0.0)),
      )),
      moving(x: 0, z: 0, flags: 0),
    ),
    #("a stop ends the animation", placed(), moving(x: 0, z: 0, flags: 0x100)),
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
    assert movement.kept == 1
      as { reason <> ": the second bit is 1, which turns the client's lift on" }
  })
  // Another player's relayed move has no evidence for the lift: the client's code reads the bit
  // for every unit, but what a player's own client sends for another's unit is not in the
  // facts, so its bit stays 0 and its commands go through as they came
  // (`unit.ground_lift.server_commands`).
  let relayed = [relayed_movement.StateFlags(MovementStateFlags(flags: 0x102))]
  let Frame(body:, ..) =
    frames.unit_moved_frame(unit_id: 41, server_time_ms: 400, commands: relayed)
  let assert Ok(UnitMovement(kept:, commands:, ..)) = unit_movement.decode(body)
    as "the frame is a 0x638 the client's reader takes"
  assert kept == 0 && commands == relayed
    as "another player's relayed move keeps the bit 0 and its own commands"
  assert frames.path_frame(
      entered: entered(),
      unit_id: 40,
      face: None,
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
  case frames.path_frame(entered: entered(), unit_id: 40, path:, face: None) {
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
            | relayed_movement.VelocityDefault(..)
            | relayed_movement.MoveDefault(..)
            | relayed_movement.Rotation(..)
            | relayed_movement.RotationDefault(..)
            | relayed_movement.FaceUnit(..)
            | relayed_movement.FacePoint(..)
            | relayed_movement.StateFlags(..)
            | relayed_movement.StateDefault(..)
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
  // then kind 11 and kind 24. Three things differ from that body: bit 65, the second bit after
  // the unit and the time and the reset bit, is 1 (byte 8 0x10 to 0x12), the command count
  // (5 bits after it) is 6 and not 4, and the 91 bits of kind 11 and kind 24 are replaced by the
  // 24 bits of kinds 10, 13, 21 and 26, each its kind and the blend bit 1
  // (`movement_command.defaults_with_kind_4_path`); the bytes were repacked by a script that
  // reads the old bits and shares no code with the codec.
  let assert Ok(before) =
    bit_array.base16_decode(
      "28000000900100001A001900004004000000FE01000000060000020200800E0200800402004007063C0200000000A86DAD03",
    )
    as "a hex string"
  let assert Some(Frame(message_id: 0x0638, body:)) =
    frames.path_frame(
      entered: entered(),
      unit_id: 40,
      face: None,
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

/// The ghost's 0x262 of type 23 carries the bone values the player's own 0x262
/// carries: the client applies a ghost's list to its face when the race and
/// gender have bones (InitUnitFromCreate 0x140456960 case 23, ReadUnitCreateGhostData
/// 0x140096970; record `0x140096970.ghost_fields`).
pub fn a_ghost_wears_the_characters_own_bone_values_test() -> Nil {
  use <- owned_test.run(5000)
  let entered = entered()
  let entered =
    world_entry.Entered(
      ..entered,
      unit: UnitCreatePlayer(..entered.unit, bone_values: [3, 7, 11]),
    )
  let Frame(message_id:, body:) =
    frames.own_unit_frame(
      entered:,
      now: Now(monotonic_ms: 700, filetime: 0),
      written: player_life.GhostCreated(place: at(x: 1.0, y: 2.0, z: 3.0)),
    )
  assert message_id == 0x0262 as "the ghost is created by a 0x262"
  let assert Ok(ghost) = unit_create_ghost.decode(body)
    as "the frame is a 0x262 of type 23 the client's reader takes"
  assert ghost.bone_values == [3, 7, 11]
    as "the six-bit count and the three 32-bit values the player's 0x262 carries"
}

/// 0x935 of the stat of a resource slot: slot -1 is stat 1, Focus, and slots 0 to 7 are
/// stats 2 to 9 (`opcode.0x935`, `ApplyUnitStat` 0x1403d9a60 case 1 stores the float at
/// the unit's +0x218, Focus; `opcode.0x262.resource_stats` for the slots).
pub fn a_resource_frame_of_slot_minus_1_is_0x935_of_stat_1_and_slots_0_to_7_keep_their_stats_test() -> Nil {
  use <- owned_test.run(5000)
  // Slot, the stat it is written as.
  [#(-1, 1), #(0, 2), #(7, 9)]
  |> list.each(fn(row) {
    let #(slot, stat_id) = row
    let Frame(message_id:, body:) =
      frames.resource_frame(unit_id: 0x1001, slot:, value: 35.0)
    assert message_id == 0x0935
    assert unit_float_stat_changed.decode(body)
      == Ok(UnitFloatStatChanged(
        unit_id: 0x1001,
        stat_id:,
        value: float32.to_bits(35.0),
      ))
  })
}

pub fn unit_removed_frame_past_32_bits_crashes_naming_unit_destroyed_test() -> Nil {
  use <- owned_test.run(10_000)
  let ended =
    ask_support.ended_running(fn() {
      let _ = frames.unit_removed_frame(unit_id: 4_294_967_296)
      Nil
    })
  let text = ask_support.panic_message(ask_support.raised(ended))
  assert string.contains(text, "unit_destroyed")
    as {
      "the crash names the message (schema row unit_destroyed); it says: "
      <> text
    }
  assert string.contains(text, "unit_id")
    as { "the crash names the 32-bit field; it says: " <> text }
}
