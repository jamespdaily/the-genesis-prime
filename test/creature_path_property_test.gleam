//// A creature's run along many points, under random polylines
//// (`genesis_prime/world_map/creature_path`). The client moves a unit along a kind 4 path at
//// one constant speed over the whole polyline, each leg taking its 3D length over the speed,
//// and holds the last point once it is there (`0x1407813d0`, `movement_command.kind_4` mode
//// 0). The server's timing is that model: it starts at the command's time, uses the speed
//// as sent and counts continuous distance, where the client starts at its first update
//// at or after the command and rounds each point's time to a millisecond. These properties
//// prove the server's model, not the client's frame times.

import creature_path_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/world_map/creature_path.{Running}
import gleam/float
import gleam/int
import gleam/list
import owned_test
import qcheck

type Point =
  #(Float, Float, Float)

fn point() -> qcheck.Generator(Point) {
  qcheck.tuple3(
    qcheck.bounded_float(from: -1000.0, to: 1000.0),
    qcheck.bounded_float(from: -200.0, to: 200.0),
    qcheck.bounded_float(from: -1000.0, to: 1000.0),
  )
}

/// The points of a polyline of 2 to 30 points, a speed, and the start time.
fn polylines() -> qcheck.Generator(#(List(Point), Float, Int)) {
  qcheck.tuple3(
    qcheck.generic_list(point(), qcheck.bounded_int(from: 2, to: 30)),
    qcheck.bounded_float(from: 0.01, to: 500.0),
    qcheck.bounded_int(from: 0, to: 100_000),
  )
}

/// The legs of the points in order, each with its 3D length.
fn legs_of(places: List(Place)) -> List(#(Place, Place, Float)) {
  list.map(list.window_by_2(places), fn(leg) {
    #(leg.0, leg.1, creature_path.distance(from: leg.0, to: leg.1))
  })
}

fn total_of(legs: List(#(Place, Place, Float))) -> Float {
  list.fold(legs, 0.0, fn(sum, leg) { sum +. leg.2 })
}

/// The time `fraction` of the way through a run of `duration_ms` that began at `started_ms`.
fn time_at(
  started_ms started_ms: Int,
  duration_ms duration_ms: Float,
  fraction fraction: Float,
) -> Int {
  started_ms + float.truncate(fraction *. duration_ms)
}

pub fn a_polyline_is_run_at_its_speed_along_its_whole_length_property_test() -> Nil {
  use <- owned_test.run(30_000)
  use #(#(points, speed, started_ms), fraction) <- qcheck.given(qcheck.tuple2(
    polylines(),
    qcheck.bounded_float(from: -0.1, to: 1.2),
  ))
  let path = support.running(points:, started_ms:, speed:)
  let places = support.points_of(path:)
  let legs = legs_of(places)
  let total = total_of(legs)
  let duration_ms = total /. speed *. 1000.0
  let now_ms = time_at(started_ms:, duration_ms:, fraction:)
  let arrives_ms =
    started_ms + float.truncate(float.ceiling(total /. speed *. 1000.0))
  assert creature_path.arrives_ms(path:, now_ms:) == arrives_ms
    as "the run ends at its start plus its length over its speed, rounded up"
  let here = creature_path.place_at(path:, now_ms:)
  let assert [first, ..] = places as "a polyline has points"
  let assert Ok(last) = list.last(places) as "a polyline has points"
  case now_ms < started_ms, now_ms >= arrives_ms {
    True, _ -> {
      assert here == first
        as "before its start the creature is at the first point"
    }
    False, True -> {
      assert here == last as "once it has arrived it holds the last point"
    }
    False, False -> {
      let tolerance = 0.000_001 *. float.max(1.0, total)
      let travelled = speed *. int.to_float(now_ms - started_ms) /. 1000.0
      let wanted = float.min(travelled, total)
      let #(_, on_the_way) =
        list.fold(legs, #(0.0, False), fn(state, leg) {
          let #(before, found) = state
          let #(from, to, length) = leg
          let on_the_leg =
            float.absolute_value(
              creature_path.distance(from:, to: here)
              +. creature_path.distance(from: here, to:)
              -. length,
            )
            <=. tolerance
          let at_that_length =
            float.absolute_value(
              before +. creature_path.distance(from:, to: here) -. wanted,
            )
            <=. tolerance
          #(before +. length, found || { on_the_leg && at_that_length })
        })
      assert on_the_way
        as "the place is on a leg, at the length of the polyline the speed has covered"
    }
  }
}

/// A run of two points as it was worked out before a run could hold more: the place
/// along the line, the velocity along it and the arrival time.
fn before_place_at(
  from from: Place,
  to to: Place,
  started_ms started_ms: Int,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Place {
  let length = creature_path.distance(from: from, to: to)
  let run = speed *. int.to_float(int.max(0, now_ms - started_ms)) /. 1000.0
  case length <=. 0.0 || run >=. length {
    True -> to
    False -> creature_path.along(from:, to:, fraction: run /. length)
  }
}

fn before_velocity(
  from from: Place,
  to to: Place,
  started_ms started_ms: Int,
  speed speed: Float,
  now_ms now_ms: Int,
) -> #(Float, Float, Float) {
  let length = creature_path.distance(from:, to:)
  let run = speed *. int.to_float(int.max(0, now_ms - started_ms)) /. 1000.0
  case length <=. 0.0 || run >=. length {
    True -> #(0.0, 0.0, 0.0)
    False -> {
      let scale = speed /. length
      let #(fx, fy, fz) = support.coordinates(from)
      let #(tx, ty, tz) = support.coordinates(to)
      #({ tx -. fx } *. scale, { ty -. fy } *. scale, { tz -. fz } *. scale)
    }
  }
}

pub fn a_path_of_two_points_is_what_it_was_property_test() -> Nil {
  use <- owned_test.run(30_000)
  // The formulas of the path at origin/main 548056f0, whose two-point runs were seen live.
  use #(#(points, speed, started_ms), fraction, new_speed) <- qcheck.given(
    qcheck.tuple3(
      qcheck.map(polylines(), fn(polyline) {
        #(list.take(polyline.0, 2), polyline.1, polyline.2)
      }),
      qcheck.bounded_float(from: -0.1, to: 1.2),
      qcheck.bounded_float(from: -5.0, to: 500.0),
    ),
  )
  let path = support.running(points:, started_ms:, speed:)
  let assert [from, to] = support.points_of(path:)
    as "a run of two points has two points"
  let length = creature_path.distance(from:, to:)
  let duration_ms = length /. speed *. 1000.0
  let now_ms = time_at(started_ms:, duration_ms:, fraction:)
  assert creature_path.place_at(path:, now_ms:)
    == before_place_at(from:, to:, started_ms:, speed:, now_ms:)
  assert creature_path.velocity(path:, now_ms:)
    == before_velocity(from:, to:, started_ms:, speed:, now_ms:)
  assert creature_path.arrives_ms(path:, now_ms:)
    == started_ms + float.truncate(float.ceiling(length /. speed *. 1000.0))
  let during_ms =
    time_at(
      started_ms:,
      duration_ms:,
      fraction: float.clamp(fraction, min: 0.0, max: 0.99),
    )
  let here = before_place_at(from:, to:, started_ms:, speed:, now_ms: during_ms)
  assert creature_path.rest_of(path:, now_ms: during_ms)
    == Running(from: here, via: [], to:, started_ms: during_ms, speed:)
    as "a late viewer is sent the run from where the creature is, as the creature's rule built it"
  assert creature_path.with_speed(path:, speed: new_speed, now_ms: during_ms)
    == creature_path.straight(
      from: here,
      to:,
      speed: new_speed,
      now_ms: during_ms,
    )
    as "a change of speed goes on from where the creature is, as the creature's rule built it"
}

pub fn the_rest_of_a_path_is_the_same_walk_from_now_property_test() -> Nil {
  use <- owned_test.run(30_000)
  use #(#(points, speed, started_ms), early, later) <- qcheck.given(
    qcheck.tuple3(
      polylines(),
      qcheck.bounded_float(from: 0.0, to: 0.99),
      qcheck.bounded_float(from: 0.0, to: 0.5),
    ),
  )
  let path = support.running(points:, started_ms:, speed:)
  let total = total_of(legs_of(support.points_of(path:)))
  let duration_ms = total /. speed *. 1000.0
  let first_ms = time_at(started_ms:, duration_ms:, fraction: early)
  let second_ms = first_ms + float.truncate(later *. duration_ms)
  let assert Running(from: rest_from, via: rest_via, started_ms: rest_start, ..) as rest =
    creature_path.rest_of(path:, now_ms: first_ms)
    as "a path still being run has a rest"
  let assert Running(via:, ..) = path as "the path is a run"
  assert list.length(rest_via) <= list.length(via)
    as "the rest holds no point the path has not"
  assert rest_start == first_ms
    && creature_path.distance(
      from: rest_from,
      to: creature_path.place_at(path:, now_ms: first_ms),
    )
    <=. 0.000_001 *. float.max(1.0, total)
    as "the rest starts now, from where the creature is"
  assert creature_path.distance(
      from: creature_path.place_at(path: rest, now_ms: second_ms),
      to: creature_path.place_at(path:, now_ms: second_ms),
    )
    <=. 0.000_001 *. float.max(1.0, total)
    as "the rest puts the creature where the path does, later"
  assert int.absolute_value(
      creature_path.arrives_ms(path: rest, now_ms: first_ms)
      - creature_path.arrives_ms(path:, now_ms: first_ms),
    )
    <= 1
    as "and ends it within a millisecond of where the path does"
}
