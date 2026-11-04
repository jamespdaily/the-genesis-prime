//// Which units an area strikes (`genesis_prime/game/area`), on the numbers of the
//// client's rows. Expected values come from these places.
//// - Kick: area row 640 (5 units, 0 to 8 m, 180 degrees) and the cone of telegraph
////   168 (1 to 7 m over 100 degrees, flag 0x200: it does not grow by a unit's hit
////   radius) (`Spell4.58591.area`).
//// - Telekinetic Strike: area row 345 (5 units, 30 m, 360 degrees) and the rectangle
////   of telegraph 2169 (3 wide, 29 long, 1 m ahead) (`Spell4.32893.area`).
//// - Zap: area row 411 (5 units, 25 m, 360 degrees) and the twin rectangle 2837,
////   3.5 wide and 24 long, 1 m ahead, with no flag 0x200: its half width 1.75 grows by
////   the struck unit's hit radius to 4.75 (`Spell4.41438.area`). That the unit's hit
////   circle overlapping the shape is what grows it is the server's choice, from the
////   client's drawn sizing (`0x14054da10`), not a client rule.
//// - Crush: area row 404 selects 1 unit (`Spell4.32812.area`).
//// - The Virtual Battle Beast's hit radius is 3.0 (`Creature2.73464`).
//// - Facing: the unit faces (-sin yaw, -cos yaw), so a unit at distance d at the
////   angle a off the facing stands at d x (-sin(yaw + a), -cos(yaw + a)) from it
////   (`movement_command.kind_14.facing`, `0x1401b3170`).
//// - Order: nearest first, the lower unit id on a tie (the step's design, section 1).
//// - Jim's choice: a unit is struck inside the telegraph's shape and within the area
////   row's range; a spell with no telegraph is struck by its area row's range and arc.
//// - Crush's 42297 has no telegraph row, so its area row alone decides (`Spell4.32812.area`).

import genesis_prime/game/area.{
  type Candidate, type Inside, type Point, Candidate, Cone, InsideRow,
  InsideShapes, Placement, Point, Pose, Rectangle, Row,
}
import gleam/float
import gleam/list
import gleam_community/maths
import owned_test
import qcheck

const beast_hit_radius = 3.0

fn kick_row() -> area.Row {
  Row(min_range: 0.0, max_range: 8.0, degrees: 180.0, target_count: 5)
}

fn kick_cone() -> Inside {
  InsideShapes([
    Placement(
      shape: Cone(inner: 1.0, outer: 7.0, degrees: 100.0),
      ahead: 0.0,
      aside: 0.0,
      turn_degrees: 0.0,
      grows_by_hit_radius: False,
    ),
  ])
}

/// The point at `distance` from the origin, `degrees` off the facing `yaw`.
fn at(
  distance distance: Float,
  degrees degrees: Float,
  yaw yaw: Float,
) -> Point {
  let angle = yaw +. maths.degrees_to_radians(degrees)
  Point(
    x: float.negate(distance *. maths.sin(angle)),
    z: float.negate(distance *. maths.cos(angle)),
  )
}

fn beast(unit_id: Int, at: Point) -> Candidate {
  Candidate(unit_id:, at:, hit_radius: beast_hit_radius)
}

const origin = Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.0)

fn struck(
  candidates candidates: List(Candidate),
  row row: area.Row,
  inside inside: Inside,
) -> List(Int) {
  area.select(candidates:, centre: origin, row:, inside:)
}

pub fn kick_strikes_a_unit_inside_its_drawn_cone_and_not_one_outside_it_test() -> Nil {
  use <- owned_test.run(5000)
  let by = fn(distance, degrees) {
    struck(
      candidates: [beast(1, at(distance:, degrees:, yaw: 0.0))],
      row: kick_row(),
      inside: kick_cone(),
    )
  }
  assert by(6.9, 0.0) == [1] as "the cone ends at 7 m (Spell4.58591.area)"
  assert by(7.1, 0.0) == []
    as "7.1 m is past the cone, though the Beast's hit radius is 3"
  assert by(5.0, 49.0) == [1] as "the cone is 100 degrees, 50 each side"
  assert by(5.0, 51.0) == []
  assert by(0.5, 0.0) == [] as "the cone starts at 1 m"
}

pub fn a_spell_with_no_telegraph_is_struck_within_its_area_rows_range_and_arc_test() -> Nil {
  use <- owned_test.run(5000)
  let by = fn(distance, degrees) {
    struck(
      candidates: [beast(1, at(distance:, degrees:, yaw: 0.0))],
      row: kick_row(),
      inside: InsideRow,
    )
  }
  assert by(7.9, 0.0) == [1] as "a row of 8 m and 180 degrees, as Kick's is"
  assert by(8.1, 0.0) == []
  assert by(5.0, 89.0) == [1] as "the row's angle is 180 degrees, 90 each side"
  assert by(5.0, 91.0) == []
}

pub fn crushs_twin_cone_strikes_a_beast_2_m_ahead_because_the_hit_circle_reaches_inside_its_inner_radius_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Row(min_range: 0.0, max_range: 25.0, degrees: 360.0, target_count: 1)
  let twin =
    InsideShapes([
      Placement(
        shape: Cone(inner: 1.0, outer: 26.0, degrees: 45.0),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
        grows_by_hit_radius: True,
      ),
    ])
  assert struck(
      candidates: [beast(1, at(distance: 2.0, degrees: 0.0, yaw: 0.0))],
      row:,
      inside: twin,
    )
    == [1]
    as "Spell4.32812.area: the twin 5123 has flag 64 and no 0x200, so it grows; its inner radius 1 shrinks by the Beast's 3.0 to 0 (server choice: the hit circle overlaps the shape, 0x14054d170 case 4)"
}

pub fn a_unit_inside_the_telegraph_but_beyond_the_area_rows_range_is_not_struck_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Row(min_range: 0.0, max_range: 25.0, degrees: 360.0, target_count: 1)
  let long_cone =
    InsideShapes([
      Placement(
        shape: Cone(inner: 1.0, outer: 26.0, degrees: 45.0),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
        grows_by_hit_radius: True,
      ),
    ])
  let by = fn(distance) {
    struck(
      candidates: [beast(1, at(distance:, degrees: 0.0, yaw: 0.0))],
      row:,
      inside: long_cone,
    )
  }
  assert by(24.9) == [1]
    as "Crush's long cone runs 1 to 26 m (Spell4.32812.area)"
  assert by(25.1) == []
    as "inside the cone but past the area row's 25 m: the row caps the shape"
}

pub fn a_unit_behind_telekinetic_strike_is_struck_by_the_area_row_and_not_by_its_rectangle_test() -> Nil {
  use <- owned_test.run(5000)
  let behind = [beast(1, at(distance: 10.0, degrees: 180.0, yaw: 0.0))]
  let row =
    Row(min_range: 0.0, max_range: 30.0, degrees: 360.0, target_count: 5)
  let rectangle =
    InsideShapes([
      Placement(
        shape: Rectangle(width: 3.0, length: 29.0),
        ahead: 1.0,
        aside: 0.0,
        turn_degrees: 0.0,
        grows_by_hit_radius: True,
      ),
    ])
  assert struck(candidates: behind, row:, inside: InsideRow) == [1]
    as "360 degrees is all round (0x1405ecf20)"
  assert struck(candidates: behind, row:, inside: rectangle) == []
    as "the rectangle lies ahead of the caster"
}

pub fn six_units_in_kicks_area_the_nearest_five_are_struck_and_a_tie_goes_to_the_lower_id_test() -> Nil {
  use <- owned_test.run(5000)
  let candidates = [
    beast(15, at(distance: 6.0, degrees: 0.0, yaw: 0.0)),
    beast(14, at(distance: 5.0, degrees: 10.0, yaw: 0.0)),
    beast(13, at(distance: 5.0, degrees: -10.0, yaw: 0.0)),
    beast(12, at(distance: 4.0, degrees: 0.0, yaw: 0.0)),
    beast(11, at(distance: 3.0, degrees: 0.0, yaw: 0.0)),
    beast(10, at(distance: 2.0, degrees: 0.0, yaw: 0.0)),
  ]
  list.each([kick_cone(), InsideRow], fn(inside) {
    assert struck(candidates:, row: kick_row(), inside:) == [10, 11, 12, 13, 14]
      as "Spell4AoeTargetConstraints.targetSelection 1, Closest, 5 units; the sixth is not taken"
  })
}

pub fn crush_strikes_one_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Row(min_range: 0.0, max_range: 25.0, degrees: 360.0, target_count: 1)
  assert struck(
      candidates: [
        beast(2, at(distance: 9.0, degrees: 0.0, yaw: 0.0)),
        beast(1, at(distance: 12.0, degrees: 0.0, yaw: 0.0)),
      ],
      row:,
      inside: InsideRow,
    )
    == [2]
    as "Spell4.32812.area: row 404 takes one, the nearest"
}

pub fn turning_half_a_turn_moves_kicks_strike_to_the_beast_behind_test() -> Nil {
  use <- owned_test.run(5000)
  let candidates = [
    beast(1, at(distance: 3.0, degrees: 0.0, yaw: 0.0)),
    beast(2, at(distance: 3.0, degrees: 180.0, yaw: 0.0)),
  ]
  let facing = fn(yaw, inside) {
    area.select(
      candidates:,
      centre: Pose(at: Point(x: 0.0, z: 0.0), yaw:),
      row: kick_row(),
      inside:,
    )
  }
  list.each([kick_cone(), InsideRow], fn(inside) {
    assert facing(0.0, inside) == [1] as "yaw 0 faces -z"
    assert facing(maths.pi(), inside) == [2]
      as "the last kind 14 yaw is the facing: a half turn faces the other Beast"
  })
}

pub fn zaps_rectangle_grows_by_the_hit_radius_and_kicks_cone_does_not_test() -> Nil {
  use <- owned_test.run(5000)
  let zap_row =
    Row(min_range: 0.0, max_range: 25.0, degrees: 360.0, target_count: 5)
  let zap =
    InsideShapes([
      Placement(
        shape: Rectangle(width: 3.5, length: 24.0),
        ahead: 1.0,
        aside: 0.0,
        turn_degrees: 0.0,
        grows_by_hit_radius: True,
      ),
    ])
  let to_the_side = fn(side) { [beast(1, Point(x: side, z: -10.0))] }
  assert struck(candidates: to_the_side(4.7), row: zap_row, inside: zap) == [1]
    as "3.5 wide is 1.75 each side, 4.75 with the Beast's hit radius 3.0 (0x14054da10)"
  assert struck(candidates: to_the_side(4.8), row: zap_row, inside: zap) == []
  assert struck(
      candidates: [beast(1, at(distance: 7.1, degrees: 0.0, yaw: 0.0))],
      row: kick_row(),
      inside: kick_cone(),
    )
    == []
    as "Kick's cone has flag 0x200, so the Beast's hit radius adds nothing"
}

pub fn a_unit_straight_ahead_of_any_facing_is_at_bearing_zero_test() -> Nil {
  use <- owned_test.run(5000)
  qcheck.given(
    qcheck.tuple2(
      qcheck.bounded_float(from: -3.1, to: 3.1),
      qcheck.bounded_float(from: 0.5, to: 30.0),
    ),
    fn(drawn) {
      let #(yaw, distance) = drawn
      let ahead =
        Point(
          x: float.negate(distance *. maths.sin(yaw)),
          z: float.negate(distance *. maths.cos(yaw)),
        )
      assert float.absolute_value(area.bearing(
          from: Point(x: 0.0, z: 0.0),
          target: ahead,
          yaw:,
        ))
        <. 0.0001
        as "a unit at d x (-sin yaw, -cos yaw) lies at angle 0 (0x1401b3170)"
    },
  )
}
