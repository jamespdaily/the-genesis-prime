//// The path a ForcedMove row throws a creature along (`genesis_prime/shared/forced_move`).
//// Expected values come from these places, each written out in its test:
//// - `Spell4Effects.effectType.3` and `.direction`: the columns and the five ways. The
////   rows are the client's, from `table_rows -- Spell4Effects 73826 74889 75297 287 49061`
////   (kind 4, 10 m, 375 ms, flags 1, apex 2.0; kind 4, 5 m, 187 ms; kind 9, d 0, 266 ms;
////   kind 4, 5 m, no time; kind 12, 5 to 7 m, no time, apex 1.0).
//// - `Spell4Effects.effectType.3.other_unit.command_shape`: the movers, and `0x14039fff0`
////   and `0x1403a0670`: the arc is on for gravity, flag 0x10 or kind 10, its height at
////   least 2 m, a launch with an arc lasts 2 sqrt(h / 16) seconds.
//// - `0x140783e10`: a kind 3 path whose span is under 1 ms samples its first point, so a
////   move with no time goes at once.
//// - `genesis_prime/shared/creature_path`: the leash circle clips a path.
//// The places are chosen so the arithmetic is exact: a 3-4-5 triangle between the units.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/shared/creature_path.{Circle, Standing, Timed}
import genesis_prime/shared/forced_move.{
  type Move, AlongVelocity, AtOnce, Away, Draws, Flight, Launch, Move, Random,
  Reference, ToUnit, Toward,
}
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/option.{None, Some}
import owned_test
import place_support
import spell_tables

const now = 1000

fn at(x x: Float, y y: Float, z z: Float) -> Place {
  place_support.at(world_id: 3460, world_zone_id: 6009, x:, y:, z:)
}

fn wide() -> creature_path.Circle {
  Circle(centre: at(x: 0.0, y: 0.0, z: 0.0), radius: 1000.0)
}

fn origin() -> forced_move.Reference {
  Reference(place: at(x: 0.0, y: 0.0, z: 0.0), radius: 0.0)
}

fn no_draw() -> forced_move.Draws {
  Draws(distance: 0.0, angle: 0.0)
}

/// A move with these columns and none of the others.
fn move(
  way way: forced_move.Way,
  mover mover: forced_move.Mover,
  distance distance: Float,
) -> Move {
  Move(
    way:,
    mover:,
    min_distance: distance,
    max_distance: distance,
    flight_ms: 0,
    gravity: 0.0,
    flags: 0,
    height: 0.0,
  )
}

/// The place the throw ends at, run from `from` with no velocity and a zero radius,
/// the reference at the origin.
fn end_of(
  move move: Move,
  draws draws: forced_move.Draws,
  from from: Place,
  reference reference: forced_move.Reference,
) -> creature_path.Path {
  forced_move.path(
    move:,
    draws:,
    from:,
    velocity: #(0.0, 0.0, 0.0),
    radius: 0.0,
    reference:,
    circle: wide(),
    now_ms: now,
  )
}

fn assert_at(place place: Place, x x: Float, y y: Float, z z: Float) -> Nil {
  assert place_support.near(left: start_place.x(place), right: x) as "x"
  assert place_support.near(left: start_place.y(place), right: y) as "y"
  assert place_support.near(left: start_place.z(place), right: z) as "z"
}

fn assert_ends_at(
  path path: creature_path.Path,
  x x: Float,
  y y: Float,
  z z: Float,
) -> Nil {
  assert_at(place: creature_path.end(path:), x:, y:, z:)
}

// ---- the direction ----

pub fn an_away_throw_goes_d_further_along_the_line_from_the_reference_test() -> Nil {
  use <- owned_test.run(5000)
  // Kind 4, reference (0, 0, 0), creature (3, 0, 4), d 5: the unit step (0.6, 0, 0.8)
  // times 5 further, so (6, 0, 8). The radii, 1.2 and 0.6 here, cut nothing.
  let path =
    forced_move.path(
      move: move(way: Away, mover: Flight, distance: 5.0),
      draws: no_draw(),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      velocity: #(0.0, 0.0, 0.0),
      radius: 0.6,
      reference: Reference(place: at(x: 0.0, y: 0.0, z: 0.0), radius: 1.2),
      circle: wide(),
      now_ms: now,
    )
  assert_ends_at(path:, x: 6.0, y: 0.0, z: 8.0)
}

pub fn an_away_throw_follows_the_slope_between_the_two_units_test() -> Nil {
  use <- owned_test.run(5000)
  // The reference stands 3 m below the creature, 4 m to the side: the 3D line is 5 m
  // long, so d 10 goes twice its offset further, (4 + 8, 0 + 6, 0).
  let path =
    end_of(
      move: move(way: Away, mover: Flight, distance: 10.0),
      draws: no_draw(),
      from: at(x: 4.0, y: 0.0, z: 0.0),
      reference: Reference(place: at(x: 0.0, y: -3.0, z: 0.0), radius: 0.0),
    )
  assert_ends_at(path:, x: 12.0, y: 6.0, z: 0.0)
}

pub fn an_away_throw_from_the_same_spot_does_not_move_test() -> Nil {
  use <- owned_test.run(5000)
  let from = at(x: 3.0, y: 0.0, z: 4.0)
  assert end_of(
      move: move(way: Away, mover: Flight, distance: 10.0),
      draws: no_draw(),
      from:,
      reference: Reference(place: from, radius: 0.0),
    )
    == Standing(at: from)
}

pub fn a_toward_throw_stops_short_by_both_radii_test() -> Nil {
  use <- owned_test.run(5000)
  // Kind 3, flags 0: the creature at z 10 and the reference at the origin, d 6; the
  // creature's radius 0.5 and the reference's 1.25 cut 1.75 off, so it travels 4.25 and
  // ends at z 5.75.
  let path =
    forced_move.path(
      move: move(way: Toward, mover: Flight, distance: 6.0),
      draws: no_draw(),
      from: at(x: 0.0, y: 0.0, z: 10.0),
      velocity: #(0.0, 0.0, 0.0),
      radius: 0.5,
      reference: Reference(place: at(x: 0.0, y: 0.0, z: 0.0), radius: 1.25),
      circle: wide(),
      now_ms: now,
    )
  assert_ends_at(path:, x: 0.0, y: 0.0, z: 5.75)
}

pub fn a_toward_throw_with_flags_2_reaches_the_reference_test() -> Nil {
  use <- owned_test.run(5000)
  // Flags & 2 is no stopping short by the radii: d 6 goes the whole 6 m, to z 4.
  let path =
    forced_move.path(
      move: Move(..move(way: Toward, mover: Flight, distance: 6.0), flags: 2),
      draws: no_draw(),
      from: at(x: 0.0, y: 0.0, z: 10.0),
      velocity: #(0.0, 0.0, 0.0),
      radius: 0.5,
      reference: Reference(place: at(x: 0.0, y: 0.0, z: 0.0), radius: 1.25),
      circle: wide(),
      now_ms: now,
    )
  assert_ends_at(path:, x: 0.0, y: 0.0, z: 4.0)
}

pub fn a_toward_throw_longer_than_the_gap_ends_at_the_reference_test() -> Nil {
  use <- owned_test.run(5000)
  // d 20 over a 10 m gap is capped at the reference's place, then cut by the radii:
  // the end is 1.75 short of it, never past the reference.
  let path =
    forced_move.path(
      move: move(way: Toward, mover: Flight, distance: 20.0),
      draws: no_draw(),
      from: at(x: 0.0, y: 0.0, z: 10.0),
      velocity: #(0.0, 0.0, 0.0),
      radius: 0.5,
      reference: Reference(place: at(x: 0.0, y: 0.0, z: 0.0), radius: 1.25),
      circle: wide(),
      now_ms: now,
    )
  assert_ends_at(path:, x: 0.0, y: 0.0, z: 1.75)
  // A gap under the radii leaves nothing to travel: the throw never goes past its start.
  let near = at(x: 0.0, y: 0.0, z: 1.0)
  assert forced_move.path(
      move: move(way: Toward, mover: Flight, distance: 20.0),
      draws: no_draw(),
      from: near,
      velocity: #(0.0, 0.0, 0.0),
      radius: 0.5,
      reference: Reference(place: at(x: 0.0, y: 0.0, z: 0.0), radius: 1.25),
      circle: wide(),
      now_ms: now,
    )
    == Standing(at: near)
}

pub fn a_throw_to_the_unit_ends_the_radii_plus_d_short_of_it_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell 36297's row 75297: kind 9, d 0, flags 1. With the radii 0.5 and 1.25 the
  // creature at z 10 ends 1.75 short of the reference at the origin, and with d 2 it
  // ends 3.75 short.
  let pull = move(way: ToUnit, mover: Flight, distance: 0.0)
  let from = at(x: 0.0, y: 0.0, z: 10.0)
  let reference = Reference(place: at(x: 0.0, y: 0.0, z: 0.0), radius: 1.25)
  let throw = fn(move) {
    forced_move.path(
      move:,
      draws: no_draw(),
      from:,
      velocity: #(0.0, 0.0, 0.0),
      radius: 0.5,
      reference:,
      circle: wide(),
      now_ms: now,
    )
  }
  assert_ends_at(path: throw(pull), x: 0.0, y: 0.0, z: 1.75)
  assert_ends_at(
    path: throw(Move(..pull, min_distance: 2.0, max_distance: 2.0)),
    x: 0.0,
    y: 0.0,
    z: 3.75,
  )
}

pub fn a_random_throw_goes_d_at_the_drawn_angle_on_the_ground_test() -> Nil {
  use <- owned_test.run(5000)
  // Kind 5, angle fraction 0.25: a quarter turn, from the x axis to the z axis, so d 4
  // from (1, 2, 3) is (1, 2, 7) and the height is kept.
  let path =
    end_of(
      move: move(way: Random, mover: Flight, distance: 4.0),
      draws: Draws(distance: 0.0, angle: 0.25),
      from: at(x: 1.0, y: 2.0, z: 3.0),
      reference: origin(),
    )
  assert_ends_at(path:, x: 1.0, y: 2.0, z: 7.0)
}

pub fn a_velocity_throw_of_a_standing_creature_does_not_move_test() -> Nil {
  use <- owned_test.run(5000)
  // Kind 6: the creature's velocity times d, and a creature that stands has none.
  let from = at(x: 3.0, y: 0.0, z: 4.0)
  assert end_of(
      move: move(way: AlongVelocity, mover: Flight, distance: 5.0),
      draws: no_draw(),
      from:,
      reference: origin(),
    )
    == Standing(at: from)
}

pub fn a_velocity_throw_follows_the_running_path_times_d_test() -> Nil {
  use <- owned_test.run(5000)
  // Running at (2, 0, 1) a second, d 3 goes (6, 0, 3) from (1, 0, 1).
  let path =
    forced_move.path(
      move: move(way: AlongVelocity, mover: Flight, distance: 3.0),
      draws: no_draw(),
      from: at(x: 1.0, y: 0.0, z: 1.0),
      velocity: #(2.0, 0.0, 1.0),
      radius: 0.0,
      reference: origin(),
      circle: wide(),
      now_ms: now,
    )
  assert_ends_at(path:, x: 7.0, y: 0.0, z: 4.0)
}

// ---- the distance ----

pub fn the_distance_is_the_drawn_fraction_between_the_two_columns_test() -> Nil {
  use <- owned_test.run(5000)
  // dataBits01 4, dataBits02 8, fraction 0.5: d = 6, along (0.6, 0, 0.8) from (3, 0, 4),
  // which is (3 + 3.6, 0, 4 + 4.8).
  let path =
    end_of(
      move: Move(
        ..move(way: Away, mover: Flight, distance: 4.0),
        max_distance: 8.0,
      ),
      draws: Draws(distance: 0.5, angle: 0.0),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      reference: origin(),
    )
  assert_ends_at(path:, x: 6.6, y: 0.0, z: 8.8)
}

pub fn a_fixed_helper_moves_its_fixed_distance_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 73826 (spell 36010, "Generic Knockback - 10 m"): dataBits01 and 02 are both
  // 10.0, so any draw gives 10 m: (3 + 6, 0, 4 + 8).
  let helper = Move(..knockback_10(), flags: 1)
  list.each([0.0, 0.5, 0.999], fn(fraction) {
    let path =
      end_of(
        move: helper,
        draws: Draws(distance: fraction, angle: 0.0),
        from: at(x: 3.0, y: 0.0, z: 4.0),
        reference: origin(),
      )
    assert_ends_at(path:, x: 9.0, y: 0.0, z: 12.0)
  })
}

/// Row 73826: kind 4 (away, flight), dataBits01 and 02 10.0, dataBits03 375, flags 1,
/// apex height 2.0, gravity 0.
fn knockback_10() -> Move {
  Move(
    way: Away,
    mover: Flight,
    min_distance: 10.0,
    max_distance: 10.0,
    flight_ms: 375,
    gravity: 0.0,
    flags: 1,
    height: 2.0,
  )
}

// ---- the movers ----

pub fn an_at_once_kind_is_a_place_not_a_path_test() -> Nil {
  use <- owned_test.run(5000)
  // Kind 1 sets the unit down at the destination: no flight.
  let path =
    end_of(
      move: move(way: Away, mover: AtOnce, distance: 5.0),
      draws: no_draw(),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      reference: origin(),
    )
  assert path == Standing(at: at(x: 6.0, y: 0.0, z: 8.0))
}

pub fn a_flight_is_two_timed_points_over_its_milliseconds_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 73826: from (3, 0, 4) at now to (9, 0, 12) at now + 375, with no point between:
  // an apex height alone does not arc.
  let from = at(x: 3.0, y: 0.0, z: 4.0)
  assert end_of(
      move: knockback_10(),
      draws: no_draw(),
      from:,
      reference: origin(),
    )
    == Timed(
      first: #(now, from),
      rest: [#(now + 375, at(x: 9.0, y: 0.0, z: 12.0))],
      turned_to: None,
    )
}

pub fn a_flight_with_gravity_rises_by_four_h_s_one_minus_s_test() -> Nil {
  use <- owned_test.run(5000)
  // Gravity 32 and an apex height 3 over 800 ms from (3, 0, 4) to (9, 0, 12): nine
  // points, 100 ms apart. At s = 0.5 the line is at (6, 0, 8) and the point is 3 m up;
  // at s = 0.25 it is 4 * 3 * 0.25 * 0.75 = 2.25 m up.
  let arc = Move(..knockback_10(), flight_ms: 800, gravity: 32.0, height: 3.0)
  let path =
    end_of(
      move: arc,
      draws: no_draw(),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      reference: origin(),
    )
  let assert Timed(first: #(first_time, _), rest:, turned_to: None) = path
  assert first_time == now
  assert list.map(rest, fn(point) { point.0 })
    == [1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800]
  let assert [_, quarter, _, middle, ..] = rest
  assert_at(place: middle.1, x: 6.0, y: 3.0, z: 8.0)
  assert_at(place: quarter.1, x: 4.5, y: 2.25, z: 6.0)
  let assert Ok(landing) = list.last(rest)
  assert_at(place: landing.1, x: 9.0, y: 0.0, z: 12.0)
}

pub fn an_arc_height_is_at_least_two_metres_test() -> Nil {
  use <- owned_test.run(5000)
  // Flag 0x10 with dataBits06 0.5: h = 2, so the middle point is 2 m up.
  let arc = Move(..knockback_10(), flags: 0x10, height: 0.5)
  let path =
    end_of(
      move: arc,
      draws: no_draw(),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      reference: origin(),
    )
  let assert Timed(rest: [_, _, _, middle, ..], ..) = path
  assert_at(place: middle.1, x: 6.0, y: 2.0, z: 8.0)
}

pub fn kind_10_always_arcs_test() -> Nil {
  use <- owned_test.run(5000)
  // `0x1405d6e12` sets the arc for kind 10 with no gravity and no flag: of_row writes it
  // as flag 0x10, so the flight to the reference 10 m away (d 0) has nine points.
  let row =
    spell4_effects.Spell4Effects(
      ..spell_tables.blank_effect(
        id: 1,
        spell: 1,
        effect_type: 3,
        target_flags: 2,
      ),
      data_bits00: 10,
      data_bits03: 800,
    )
  let assert Ok(arc) = forced_move.of_row(row:)
  let path =
    end_of(
      move: arc,
      draws: no_draw(),
      from: at(x: 0.0, y: 0.0, z: 10.0),
      reference: origin(),
    )
  let assert Timed(rest:, ..) = path
  assert list.length(rest) == 8
}

pub fn a_flight_with_only_an_apex_height_does_not_arc_test() -> Nil {
  use <- owned_test.run(5000)
  // Rows 73826 and 74889 (spells 36010 and 36215): dataBits06 2.0 and 1.0, gravity 0,
  // flags 1. `0x1405d6e12` arcs on gravity, flag 0x10 or kind 10 only, so each flies the
  // straight line: two points.
  let row = fn(distance_bits, time, height_bits) {
    spell4_effects.Spell4Effects(
      ..spell_tables.blank_effect(
        id: 1,
        spell: 1,
        effect_type: 3,
        target_flags: 2,
      ),
      data_bits00: 4,
      data_bits01: distance_bits,
      data_bits02: distance_bits,
      data_bits03: time,
      data_bits05: 1,
      data_bits06: height_bits,
    )
  }
  list.each(
    [
      row(1_092_616_192, 375, 1_073_741_824),
      row(1_084_227_584, 187, 1_065_353_216),
    ],
    fn(row) {
      let assert Ok(flight) = forced_move.of_row(row:)
      let path =
        end_of(
          move: flight,
          draws: no_draw(),
          from: at(x: 3.0, y: 0.0, z: 4.0),
          reference: origin(),
        )
      let assert Timed(rest: [_], ..) = path
    },
  )
}

pub fn a_launch_with_an_arc_lasts_two_root_h_over_sixteen_test() -> Nil {
  use <- owned_test.run(5000)
  // h 16 gives 2 * sqrt(1) = 2 s whatever dataBits03 holds (`0x1403a0670`).
  let launch =
    Move(
      ..move(way: Away, mover: Launch, distance: 10.0),
      flight_ms: 999,
      flags: 0x10,
      height: 16.0,
    )
  let path =
    end_of(
      move: launch,
      draws: no_draw(),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      reference: origin(),
    )
  assert creature_path.arrives_ms(path:, now_ms: now) == now + 2000
}

pub fn a_launch_without_an_arc_flies_straight_over_its_milliseconds_test() -> Nil {
  use <- owned_test.run(5000)
  let launch =
    Move(
      ..move(way: Away, mover: Launch, distance: 10.0),
      flight_ms: 500,
      height: 16.0,
    )
  let from = at(x: 3.0, y: 0.0, z: 4.0)
  assert end_of(move: launch, draws: no_draw(), from:, reference: origin())
    == Timed(
      first: #(now, from),
      rest: [#(now + 500, at(x: 9.0, y: 0.0, z: 12.0))],
      turned_to: None,
    )
}

pub fn a_flight_of_zero_milliseconds_is_at_once_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 287: kind 4, d 5, dataBits03 0. A kind 3 path of span below 1 ms samples its first
  // point (`0x140783e10`), so the creature would not move: it is set down at (6, 0, 8).
  let path =
    end_of(
      move: move(way: Away, mover: Flight, distance: 5.0),
      draws: no_draw(),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      reference: origin(),
    )
  assert path == Standing(at: at(x: 6.0, y: 0.0, z: 8.0))
}

pub fn a_launch_with_no_arc_and_no_time_is_at_once_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 49061: kind 12 (away, launch), 5 to 7 m, dataBits03 0, dataBits06 1.0 and no
  // gravity or flag, so no arc: with fraction 0.5, d = 6 from (3, 0, 4): (6.6, 0, 8.8).
  let launch =
    Move(
      ..move(way: Away, mover: Launch, distance: 5.0),
      max_distance: 7.0,
      height: 1.0,
    )
  let path =
    end_of(
      move: launch,
      draws: Draws(distance: 0.5, angle: 0.0),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      reference: origin(),
    )
  let assert Standing(at: landing) = path
  assert_at(place: landing, x: 6.6, y: 0.0, z: 8.8)
}

pub fn flags_4_faces_the_reference_and_flags_8_faces_along_the_move_test() -> Nil {
  use <- owned_test.run(5000)
  // The client's yaw is atan2(-dx, -dz) of the direction faced (`genesis_prime/shared/area`).
  // Flag 4: from the end (6, 0, 8) to the reference at the origin, atan2(6, 8).
  // Flag 8: along the move (3, 0, 4) to (6, 0, 8), atan2(-3, -4). An at-once move that
  // turns is one timed point, which carries the facing.
  let from = at(x: 3.0, y: 0.0, z: 4.0)
  let turned = fn(flags) {
    end_of(
      move: Move(..move(way: Away, mover: AtOnce, distance: 5.0), flags: flags),
      draws: no_draw(),
      from:,
      reference: origin(),
    )
  }
  let assert Timed(first: #(time, end), rest: [], turned_to: Some(toward)) =
    turned(4)
  assert time == now
  assert_at(place: end, x: 6.0, y: 0.0, z: 8.0)
  assert place_support.near(left: toward.yaw, right: 0.6435011087932844)
  let assert Timed(rest: [], turned_to: Some(along), ..) = turned(8)
  assert place_support.near(left: along.yaw, right: -2.498091544796509)
  assert toward.pitch == 0.0 && toward.roll == 0.0
}

// ---- the leash ----

pub fn a_throw_past_the_leash_circle_ends_on_it_test() -> Nil {
  use <- owned_test.run(5000)
  // The away throw from (3, 0, 4) to (9, 0, 12) crosses a circle of radius 8 about the
  // origin where the point is 8 m out along (0.6, 0, 0.8): (4.8, 0, 6.4).
  let path =
    forced_move.path(
      move: move(way: Away, mover: Flight, distance: 10.0),
      draws: no_draw(),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      velocity: #(0.0, 0.0, 0.0),
      radius: 0.0,
      reference: origin(),
      circle: Circle(centre: at(x: 0.0, y: 0.0, z: 0.0), radius: 8.0),
      now_ms: now,
    )
  assert_ends_at(path:, x: 4.8, y: 0.0, z: 6.4)
}

pub fn a_throw_inside_the_leash_circle_is_not_clipped_test() -> Nil {
  use <- owned_test.run(5000)
  let path =
    forced_move.path(
      move: move(way: Away, mover: Flight, distance: 10.0),
      draws: no_draw(),
      from: at(x: 3.0, y: 0.0, z: 4.0),
      velocity: #(0.0, 0.0, 0.0),
      radius: 0.0,
      reference: origin(),
      circle: Circle(centre: at(x: 0.0, y: 0.0, z: 0.0), radius: 20.0),
      now_ms: now,
    )
  assert_ends_at(path:, x: 9.0, y: 0.0, z: 12.0)
}
