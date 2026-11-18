//// A timed path of a thrown creature (`genesis_prime/world_map/creature_path`). Expected
//// values come from the client's reading of kind 3 type 0 (`0x140783e10`, the sampler
//// `SampleTimedPathKeys`): straight lines between the points, the first point held before
//// the first time and the last held after the last time (`cc_state.forced_move_end`: the
//// unit keeps the path's last point).

import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/world_map/creature_path.{Standing, Timed}
import gleam/list
import gleam/option.{None, Some}
import owned_test
import place_support

fn at(x x: Float, y y: Float, z z: Float) -> Place {
  place_support.at(world_id: 3460, world_zone_id: 6009, x:, y:, z:)
}

/// (0, 0, 0) at 1000 ms, (10, 0, 0) at 1100 and (10, 0, 20) at 1300.
fn path() -> creature_path.Path {
  Timed(
    first: #(1000, at(x: 0.0, y: 0.0, z: 0.0)),
    rest: [
      #(1100, at(x: 10.0, y: 0.0, z: 0.0)),
      #(1300, at(x: 10.0, y: 0.0, z: 20.0)),
    ],
    turned_to: None,
  )
}

pub fn a_timed_path_is_linear_between_its_points_test() -> Nil {
  use <- owned_test.run(5000)
  // Halfway through the first, 100 ms, segment (at 1050) it has gone 5 of 10 m along x;
  // halfway through the second, 200 ms, segment (at 1200) it has gone 10 of 20 m along z.
  assert creature_path.place_at(path: path(), now_ms: 1050)
    == at(x: 5.0, y: 0.0, z: 0.0)
  assert creature_path.place_at(path: path(), now_ms: 1100)
    == at(x: 10.0, y: 0.0, z: 0.0)
  assert creature_path.place_at(path: path(), now_ms: 1200)
    == at(x: 10.0, y: 0.0, z: 10.0)
}

pub fn a_timed_path_holds_its_last_point_after_its_last_time_test() -> Nil {
  use <- owned_test.run(5000)
  assert creature_path.place_at(path: path(), now_ms: 1300)
    == at(x: 10.0, y: 0.0, z: 20.0)
  assert creature_path.place_at(path: path(), now_ms: 90_000)
    == at(x: 10.0, y: 0.0, z: 20.0)
  assert creature_path.place_at(path: path(), now_ms: 400)
    == at(x: 0.0, y: 0.0, z: 0.0)
    as "before its first time the unit is at the first point"
}

pub fn a_timed_path_ends_at_its_last_point_and_last_time_test() -> Nil {
  use <- owned_test.run(5000)
  assert creature_path.end(path: path()) == at(x: 10.0, y: 0.0, z: 20.0)
  assert creature_path.arrives_ms(path: path(), now_ms: 1050) == 1300
}

pub fn a_timed_path_has_the_velocity_of_its_segment_and_none_outside_test() -> Nil {
  use <- owned_test.run(5000)
  // 10 m in 100 ms is 100 m a second along x; 20 m in 200 ms is 100 m a second along z.
  assert creature_path.velocity(path: path(), now_ms: 1050)
    == #(100.0, 0.0, 0.0)
  assert creature_path.velocity(path: path(), now_ms: 1200)
    == #(0.0, 0.0, 100.0)
  assert creature_path.velocity(path: path(), now_ms: 1300) == #(0.0, 0.0, 0.0)
  assert creature_path.velocity(path: path(), now_ms: 500) == #(0.0, 0.0, 0.0)
}

pub fn the_rest_of_a_timed_path_starts_at_its_place_now_test() -> Nil {
  use <- owned_test.run(5000)
  assert creature_path.rest_of(path: path(), now_ms: 1050)
    == Timed(
      first: #(1050, at(x: 5.0, y: 0.0, z: 0.0)),
      rest: [
        #(1100, at(x: 10.0, y: 0.0, z: 0.0)),
        #(1300, at(x: 10.0, y: 0.0, z: 20.0)),
      ],
      turned_to: None,
    )
  assert creature_path.rest_of(path: path(), now_ms: 1200)
    == Timed(
      first: #(1200, at(x: 10.0, y: 0.0, z: 10.0)),
      rest: [#(1300, at(x: 10.0, y: 0.0, z: 20.0))],
      turned_to: None,
    )
  assert creature_path.rest_of(path: path(), now_ms: 1300)
    == Standing(at: at(x: 10.0, y: 0.0, z: 20.0))
    as "a path that is run has no rest"
}

/// The same flight turning the creature to yaw 1.5 (kind 14, `turned_to`).
fn turning_path() -> creature_path.Path {
  let assert Timed(first:, rest:, ..) = path()
  Timed(first:, rest:, turned_to: Some(turned()))
}

fn turned() -> start_place.Facing {
  Facing(yaw: 1.5, pitch: 0.0, roll: 0.0)
}

pub fn a_throw_that_turns_the_creature_faces_it_during_and_after_the_flight_test() -> Nil {
  use <- owned_test.run(5000)
  // Kind 14 sets the unit's rotation and the path moves its position only
  // (`movement_command.kind_14`), so every place along the path and its end have the
  // turned yaw.
  assert start_place.facing(creature_path.place_at(
      path: turning_path(),
      now_ms: 1050,
    ))
    == turned()
    as "during the flight"
  assert start_place.facing(creature_path.place_at(
      path: turning_path(),
      now_ms: 5000,
    ))
    == turned()
    as "after the flight"
  assert creature_path.end(path: turning_path())
    == start_place.turned(place: at(x: 10.0, y: 0.0, z: 20.0), facing: turned())
    as "the creature ends at the last point, turned"
  assert creature_path.rest_of(path: turning_path(), now_ms: 1300)
    == Standing(at: creature_path.end(path: turning_path()))
    as "a viewer arriving once it is run is sent the turned end"
}

/// A speed of 0 is a root (Spell4Effects 1781) and one below 0 is what stacked
/// negative flats leave (Spell4Effects 192472): the creature does not run, which for
/// a speed below 0 is the server's choice.
pub fn arrives_ms_refuses_a_speed_of_zero_or_below_test() -> Nil {
  use <- owned_test.run(5000)
  let from = at(x: 0.0, y: 0.0, z: 0.0)
  let target = at(x: 30.0, y: 0.0, z: 0.0)
  let circle = creature_path.Circle(centre: from, radius: 55.0)
  list.each([0.0, -0.1, -1.0], fn(speed) {
    let chase =
      creature_path.toward(
        from:,
        target:,
        stop_short: 4.0,
        circle:,
        speed:,
        now_ms: 5000,
      )
    let walk = creature_path.straight(from:, to: target, speed:, now_ms: 5000)
    assert chase == Standing(at: from)
      as "a chase at that speed leaves the creature where it is"
    assert walk == Standing(at: from)
      as "a walk at that speed leaves the creature where it is"
    assert creature_path.arrives_ms(path: walk, now_ms: 6000) == 6000
      as "so no arrival is computed from the speed"
  })
  assert creature_path.straight(
      from: target,
      to: target,
      speed: 0.0,
      now_ms: 5000,
    )
    == Standing(at: target)
    as "a creature already at its target is there, whatever its speed"
  assert creature_path.straight(from:, to: target, speed: 10.0, now_ms: 5000)
    == creature_path.Running(
      from:,
      via: [],
      to: target,
      started_ms: 5000,
      speed: 10.0,
    )
    as "a speed above 0 runs"
}
