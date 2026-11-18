//// The frames the connection writes for a creature's run, under random paths
//// (`genesis_prime/game/connection/frames` `path_frame`). The client animates a
//// unit by the horizontal length of kind 11's vector against the unit's display
//// row (`UpdateUnitWorldMatrix 0x1405b5070`, `GetUnitBaseMoveSpeed 0x1405b4780`),
//// and only while the move is forward of the unit's facing, so the vector the
//// frame holds must be the creature's real horizontal speed, along its path. A
//// half float keeps 10 bits of fraction, so a component is read to a relative
//// error of 2^-11, and below the smallest normal number (2^-14) to an absolute
//// one of 2^-25 (`half_float.client_value`).

import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection/frames
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/half_float
import genesis_prime/message/relayed_movement
import genesis_prime/message/unit_movement
import genesis_prime/world_map/creature_path
import gleam/float
import gleam/list
import gleam/option.{Some}
import owned_test
import place_support
import qcheck
import world_entry_support

fn at(point: #(Float, Float, Float)) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: point.0,
    y: point.1,
    z: point.2,
  )
}

fn half(bits: Int) -> Float {
  let assert Ok(value) = half_float.client_value(bits:)
    as "kind 11's components are 16 bits"
  value
}

pub fn a_running_frames_move_vector_points_along_its_path_at_its_horizontal_speed_property_test() -> Nil {
  use <- owned_test.run(30_000)
  let entered = world_entry_support.entered_after(clock_origin_ms: 600)
  let point =
    qcheck.tuple3(
      qcheck.bounded_float(from: -1000.0, to: 1000.0),
      qcheck.bounded_float(from: -200.0, to: 200.0),
      qcheck.bounded_float(from: -1000.0, to: 1000.0),
    )
  use #(from, to, speed) <- qcheck.given(qcheck.tuple3(
    point,
    point,
    qcheck.bounded_float(from: 0.01, to: 500.0),
  ))
  let along_x = to.0 -. from.0
  let along_z = to.2 -. from.2
  let assert Ok(horizontal) =
    float.square_root(along_x *. along_x +. along_z *. along_z)
    as "a sum of squares has a root"
  let assert Ok(length) =
    float.square_root(
      horizontal *. horizontal +. { to.1 -. from.1 } *. { to.1 -. from.1 },
    )
    as "a sum of squares has a root"
  case horizontal <. 1.0 {
    True -> Nil
    False -> {
      let assert Some(Frame(body:, ..)) =
        frames.path_frame(
          entered:,
          unit_id: 40,
          path: creature_path.Running(
            from: at(from),
            to: at(to),
            started_ms: 1000,
            speed:,
          ),
        )
        as "a speed within a half float's range has a frame"
      let assert Ok(unit_movement.UnitMovement(commands:, ..)) =
        unit_movement.decode(body)
      let assert [relayed_movement.MoveAsked(move)] =
        list.filter(commands, fn(command) {
          case command {
            relayed_movement.MoveAsked(..) -> True
            relayed_movement.Time(..)
            | relayed_movement.Platform(..)
            | relayed_movement.Position(..)
            | relayed_movement.TimedPath(..)
            | relayed_movement.Path(..)
            | relayed_movement.Velocity(..)
            | relayed_movement.Rotation(..)
            | relayed_movement.FaceUnit(..)
            | relayed_movement.FacePoint(..)
            | relayed_movement.StateFlags(..)
            | relayed_movement.Mode(..) -> False
          }
        })
        as "one kind 11"
      let move_x = half(move.x)
      let move_z = half(move.z)
      let wanted = speed *. horizontal /. length
      let assert Ok(read) =
        float.square_root(move_x *. move_x +. move_z *. move_z)
        as "a sum of squares has a root"
      assert move.y == 0 as "kind 11 has no vertical part"
      assert move_x *. along_x +. move_z *. along_z >=. 0.0
        as "the move is forward along the path, never against it"
      assert float.absolute_value(read -. wanted)
        <=. wanted /. 1024.0 +. 0.000_000_06
        as "its length is the creature's horizontal speed to the half float's error"
    }
  }
}
