//// A timed path of a thrown creature (`genesis_prime/world_map/creature_path`). Expected
//// values come from the client's reading of kind 3 type 0 (`0x140783e10`, the sampler
//// `SampleTimedPathKeys`): straight lines between the points, the first point held before
//// the first time and the last held after the last time (`cc_state.forced_move_end`: the
//// unit keeps the path's last point).

import creature_path_support as support
import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/world_map/creature_path.{Standing, Timed, TooManyPoints}
import gleam/float
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

// ------------------------------------------------------------ a run along many points
//
// Expected values come from the client's timing of a kind 4 path: one constant speed
// over the whole polyline, each leg taking its 3D length over the speed, the last point
// held after the end (`0x1407813d0`, `movement_command.kind_4` mode 0). The L is (0, 0, 0),
// (30, 0, 0), (30, 0, 40): 70 long, so at 10 a second it runs 7 s.

type Point =
  #(Float, Float, Float)

fn l_path(speed speed: Float) -> creature_path.Path {
  support.running(
    points: [#(0.0, 0.0, 0.0), #(30.0, 0.0, 0.0), #(30.0, 0.0, 40.0)],
    started_ms: 1000,
    speed:,
  )
}

fn coordinates(place: Place) -> Point {
  #(start_place.x(place), start_place.y(place), start_place.z(place))
}

fn close(first: Point, second: Point) -> Bool {
  float.absolute_value(first.0 -. second.0) <=. 0.000_000_001
  && float.absolute_value(first.1 -. second.1) <=. 0.000_000_001
  && float.absolute_value(first.2 -. second.2) <=. 0.000_000_001
}

/// The place, the velocity and the arrival time of a path at `now_ms`.
fn walked(
  path path: creature_path.Path,
  now_ms now_ms: Int,
) -> #(Point, Point, Int) {
  #(
    coordinates(creature_path.place_at(path:, now_ms:)),
    creature_path.velocity(path:, now_ms:),
    creature_path.arrives_ms(path:, now_ms:),
  )
}

/// A path as its points, its start and its speed, which is what two paths of one run
/// share whatever the float noise of the walk that made them.
fn outline(path path: creature_path.Path) -> #(List(Point), Int, Float) {
  case path {
    Standing(at:) -> #([coordinates(at)], 0, 0.0)
    creature_path.Running(started_ms:, speed:, ..) -> #(
      list.map(support.points_of(path:), coordinates),
      started_ms,
      speed,
    )
    Timed(..) -> panic as "a run's rest is a run or standing"
  }
}

fn same_outline(first: creature_path.Path, second: creature_path.Path) -> Bool {
  let #(first_points, first_start, first_speed) = outline(path: first)
  let #(second_points, second_start, second_speed) = outline(path: second)
  first_start == second_start
  && first_speed == second_speed
  && list.length(first_points) == list.length(second_points)
  && list.all(list.zip(first_points, second_points), fn(pair) {
    close(pair.0, pair.1)
  })
}

pub fn a_path_with_corners_is_walked_leg_by_leg_test() -> Nil {
  use <- owned_test.run(5000)
  let cases = [
    #(
      "at exactly the corner (3000 ms in) the creature is at it and runs the second leg, a point passed exactly belongs to the next leg",
      l_path(speed: 10.0),
      4000,
      #(#(30.0, 0.0, 0.0), #(0.0, 0.0, 10.0), 8000),
    ),
    #(
      "a repeated middle point makes an empty leg that is skipped: 15 along is 5 into the last leg, with no division by zero",
      support.running(
        points: [
          #(0.0, 0.0, 0.0),
          #(10.0, 0.0, 0.0),
          #(10.0, 0.0, 0.0),
          #(10.0, 0.0, 20.0),
        ],
        started_ms: 1000,
        speed: 10.0,
      ),
      2500,
      #(#(10.0, 0.0, 5.0), #(0.0, 0.0, 10.0), 4000),
    ),
    #(
      "a rising leg is counted along its 3D length: 13 a second along 3-4-0 is (7.8, 10.4, 0) a second",
      support.running(
        points: [#(0.0, 0.0, 0.0), #(3.0, 4.0, 0.0), #(3.0, 4.0, 12.0)],
        started_ms: 1000,
        speed: 13.0,
      ),
      1000,
      #(#(0.0, 0.0, 0.0), #(7.8, 10.4, 0.0), 2308),
    ),
    #(
      "8.5 units in at 17 a second (500 ms) is 3.5 into the leg after the 5 of the rising one",
      support.running(
        points: [#(0.0, 0.0, 0.0), #(3.0, 4.0, 0.0), #(3.0, 4.0, 12.0)],
        started_ms: 1000,
        speed: 17.0,
      ),
      1500,
      #(#(3.0, 4.0, 3.5), #(0.0, 0.0, 17.0), 2000),
    ),
    #(
      "a hand-built run of points all equal has no length: it arrives where it starts and has no velocity",
      support.running(
        points: [#(5.0, 5.0, 5.0), #(5.0, 5.0, 5.0), #(5.0, 5.0, 5.0)],
        started_ms: 1000,
        speed: 10.0,
      ),
      1500,
      #(#(5.0, 5.0, 5.0), #(0.0, 0.0, 0.0), 1000),
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, path, now_ms, expected) = row
    let #(place, velocity, arrives_ms) = walked(path:, now_ms:)
    assert close(place, expected.0) as reason
    assert close(velocity, expected.1) as reason
    assert arrives_ms == expected.2 as reason
  })
}

pub fn the_rest_of_a_path_drops_the_points_it_has_passed_test() -> Nil {
  use <- owned_test.run(5000)
  let corner = #(30.0, 0.0, 0.0)
  let end = #(30.0, 0.0, 40.0)
  let cases = [
    #(
      "1000 ms in, before the corner: the run from (10, 0, 0) through the corner, started now",
      2000,
      support.running(
        points: [#(10.0, 0.0, 0.0), corner, end],
        started_ms: 2000,
        speed: 10.0,
      ),
    ),
    #(
      "4000 ms in, past the corner: the run from (30, 0, 10) to the end",
      5000,
      support.running(
        points: [#(30.0, 0.0, 10.0), end],
        started_ms: 5000,
        speed: 10.0,
      ),
    ),
    #(
      "after the arrival, before its timer: the creature stands at the end, so a viewer is sent no run",
      9000,
      Standing(at: support.at(end)),
    ),
    #(
      "before the start: the path itself, the run does not start early",
      500,
      l_path(speed: 10.0),
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, now_ms, expected) = row
    assert same_outline(
      creature_path.rest_of(path: l_path(speed: 10.0), now_ms:),
      expected,
    )
      as reason
  })
}

pub fn a_run_at_another_speed_goes_on_through_its_points_test() -> Nil {
  use <- owned_test.run(5000)
  let cases = [
    #(
      "at 5 a second from 1000 ms in: the same points from (10, 0, 0), the 60 left taking 12 s",
      5.0,
      support.running(
        points: [#(10.0, 0.0, 0.0), #(30.0, 0.0, 0.0), #(30.0, 0.0, 40.0)],
        started_ms: 2000,
        speed: 5.0,
      ),
      14_000,
    ),
    #(
      "a speed of 0 roots the creature where it is",
      0.0,
      Standing(at: support.at(#(10.0, 0.0, 0.0))),
      2000,
    ),
    #(
      "a speed below 0 roots it too",
      -3.0,
      Standing(at: support.at(#(10.0, 0.0, 0.0))),
      2000,
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, speed, expected, arrives_ms) = row
    let changed =
      creature_path.with_speed(path: l_path(speed: 10.0), speed:, now_ms: 2000)
    assert same_outline(changed, expected) as reason
    assert creature_path.arrives_ms(path: changed, now_ms: 2000) == arrives_ms
      as reason
  })
}

pub fn more_points_than_a_kind_4_holds_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let through = fn(points: List(Point), speed: Float) {
    let assert [from, ..rest] = list.map(points, support.at)
      as "a path has points"
    let assert [to, ..before_to] = list.reverse(rest) as "a path has two points"
    creature_path.through(
      from:,
      via: list.reverse(before_to),
      to:,
      speed:,
      now_ms: 1000,
    )
  }
  let origin = #(0.0, 0.0, 0.0)
  let loop = [origin, #(10.0, 0.0, 0.0), origin]
  let equal = [#(5.0, 5.0, 5.0), #(5.0, 5.0, 5.0), #(5.0, 5.0, 5.0)]
  let cases = [
    #(
      "1024 points are one more than the 10-bit count holds",
      through(support.line(count: 1024), 10.0),
      Error(TooManyPoints(count: 1024)),
    ),
    #(
      "1023 points are the most it holds",
      through(support.line(count: 1023), 10.0),
      Ok(support.running(
        points: support.line(count: 1023),
        started_ms: 1000,
        speed: 10.0,
      )),
    ),
    #(
      "a loop that returns to its start still runs",
      through(loop, 10.0),
      Ok(support.running(points: loop, started_ms: 1000, speed: 10.0)),
    ),
    #(
      "points all equal have no length: the creature stands at the last",
      through(equal, 10.0),
      Ok(Standing(at: support.at(#(5.0, 5.0, 5.0)))),
    ),
  ]
  list.each(cases, fn(row) {
    let #(reason, made, expected) = row
    assert made == expected as reason
  })
}
