//// Which units an area strikes (`genesis_prime/game/area`), on the numbers of the
//// client's rows. Expected values come from these places.
//// - Kick: area row 640 (5 units, 0 to 8 m, 180 degrees) and the cone of telegraph
////   168 (1 to 7 m over 100 degrees) (`Spell4.58591.area`).
//// - Telekinetic Strike: area row 345 (5 units, 30 m, 360 degrees) and the rectangle
////   of telegraph 2169 (3 wide, 29 long, 1 m ahead) (`Spell4.32893.area`).
//// - Zap: area row 411 (5 units, 25 m, 360 degrees) and the twin rectangle 2837,
////   3.5 wide and 24 long, 1 m ahead: its half width 1.75 grows by the struck unit's
////   hit radius to 4.75 (`Spell4.41438.area`). That the unit's hit circle overlapping
////   the shape is what counts, for every shape whatever its flag 0x200, is Jim's
////   decision, from the client's drawn sizing (`0x14054da10`), not a client rule
////   (`unit.hit_radius`).
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
  type Candidate, type Inside, type Point, Box, Candidate, Circle, Cone,
  InsideRow, InsideShapes, Placement, Point, Pose, Rectangle, Row,
}
import genesis_prime/game/start_place
import gleam/float
import gleam/list
import gleam_community/maths
import owned_test
import place_support
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
  assert by(7.1, 0.0) == [1]
    as "7.1 m is past the cone's 7 m, but the Beast's hit radius of 3 reaches it (a unit's radius counts for every shape)"
  assert struck(
      candidates: [beast(1, at(distance: 10.1, degrees: 0.0, yaw: 0.0))],
      row: Row(min_range: 0.0, max_range: 30.0, degrees: 180.0, target_count: 5),
      inside: kick_cone(),
    )
    == []
    as "10.1 m is past the cone's 7 m by more than the Beast's hit radius of 3 (a 30 m row, so the shape alone decides)"
  assert struck(
      candidates: [beast(1, at(distance: 3.0, degrees: 180.0, yaw: 0.0))],
      row: Row(min_range: 0.0, max_range: 30.0, degrees: 360.0, target_count: 5),
      inside: kick_cone(),
    )
    == []
    as "3 m straight behind the caster is 3.72 m from the cone's nearest point, its inner corner 1 m out at 50 degrees, past the Beast's hit radius of 3"
  assert by(5.0, 49.0) == [1] as "the cone is 100 degrees, 50 each side"
  assert by(5.0, 51.0) == [1]
    as "1 degree past the cone's side is 0.09 m from the side line, within the Beast's hit radius of 3"
  assert by(5.0, 90.0) == []
    as "40 degrees past the side is 3.2 m from the side line, past the Beast's hit radius of 3"
  assert by(0.5, 0.0) == [1]
    as "the cone starts at 1 m, but the Beast's hit radius of 3 reaches back to it"
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

pub fn paralytic_surge_strikes_a_unit_in_its_box_only_in_its_cone_only_or_in_both_and_a_unit_in_neither_is_not_struck_test() -> Nil {
  use <- owned_test.run(5000)
  let box =
    Placement(
      shape: Box(width: 8.0, length: 8.0),
      ahead: 9.3,
      aside: 0.0,
      turn_degrees: 45.0,
    )
  let cone =
    Placement(
      shape: Cone(inner: 1.0, outer: 10.75, degrees: 62.5),
      ahead: 0.0,
      aside: 0.0,
      turn_degrees: 0.0,
    )
  let row =
    Row(min_range: 0.0, max_range: 15.0, degrees: 180.0, target_count: 5)
  // The box is a square turned 45 degrees about its centre, 9.3 m ahead: its corner
  // nearest the caster is 9.3 - 5.66 = 3.64 m ahead and its farthest 14.96 m; the
  // cone reaches 10.75 m within 31.25 degrees of the facing. The units have no body
  // (hit radius 0), so that only the shapes' own geometry is read; a Beast's hit
  // radius of 3 would grow both shapes.
  let point_unit = fn(unit_id, at) { Candidate(unit_id:, at:, hit_radius: 0.0) }
  let candidates = [
    point_unit(1, at(distance: 2.0, degrees: 0.0, yaw: 0.0)),
    point_unit(2, at(distance: 9.3, degrees: 0.0, yaw: 0.0)),
    point_unit(3, at(distance: 14.0, degrees: 0.0, yaw: 0.0)),
    point_unit(4, at(distance: 12.0, degrees: 40.0, yaw: 0.0)),
  ]
  assert struck(candidates:, row:, inside: InsideShapes([box])) == [2, 3]
    as "the box alone holds the unit in both and the unit 14 m ahead, past the cone's 10.75 m: Spell4.42352.area, telegraph 2888"
  assert struck(candidates:, row:, inside: InsideShapes([cone])) == [1, 2]
    as "the cone alone holds the unit 2 m ahead, short of the box's near corner, and the unit in both: telegraph 2889"
  assert struck(candidates:, row:, inside: InsideShapes([box, cone]))
    == [1, 2, 3]
    as "inside either drawn shape (it has no never-drawn twin), and the unit at 40 degrees, 12 m is in neither and within the row's 15 m and 180 degrees: it is not struck"
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
  // The Beast behind stands 3 m from the caster: 3.72 m from the cone's inner corner,
  // past its hit radius of 3, so only the Beast ahead is struck.
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

pub fn zaps_rectangle_and_kicks_cone_both_grow_by_the_hit_radius_test() -> Nil {
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
    == [1]
    as "Kick's cone has flag 0x200, which only stops its drawing growing: the Beast's hit radius of 3 still reaches it from 7.1 m"
}

pub fn a_unit_just_outside_a_shape_by_less_than_its_hit_radius_is_struck_and_by_more_is_not_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Row(min_range: 0.0, max_range: 30.0, degrees: 360.0, target_count: 5)
  let placed = fn(shape, ahead) {
    InsideShapes([
      Placement(shape:, ahead:, aside: 0.0, turn_degrees: 0.0),
    ])
  }
  let struck_at = fn(inside, x, z) {
    struck(candidates: [beast(1, Point(x:, z:))], row:, inside:) == [1]
  }
  // The Beast's hit radius is 3.0 (Creature2.73464); a unit is struck when that
  // radius touches the shape, so each edge reaches 3 m further out. Each pair
  // stands 0.1 m inside and 0.1 m outside the grown edge. The unit faces -z.
  let circle = placed(Circle(radius: 5.0), 0.0)
  assert struck_at(circle, 7.9, 0.0) as "a circle of 5 m reaches 8 m"
  assert !struck_at(circle, 8.1, 0.0)
  let rectangle = placed(Rectangle(width: 2.0, length: 10.0), 0.0)
  assert struck_at(rectangle, 3.9, -5.0)
    as "a strip 2 m wide reaches 1 + 3 m aside"
  assert !struck_at(rectangle, 4.1, -5.0)
  assert struck_at(rectangle, 0.0, -12.9)
    as "a strip 10 m long reaches 13 m ahead"
  assert !struck_at(rectangle, 0.0, -13.1)
  assert struck_at(rectangle, 0.0, 2.9) as "and 3 m behind its start"
  assert !struck_at(rectangle, 0.0, 3.1)
  let box = placed(Box(width: 4.0, length: 6.0), 10.0)
  assert struck_at(box, 4.9, -10.0) as "a box 4 m wide reaches 2 + 3 m aside"
  assert !struck_at(box, 5.1, -10.0)
  assert struck_at(box, 0.0, -15.9)
    as "a box 6 m long centred 10 m ahead reaches 3 + 3 m either side of its centre"
  assert !struck_at(box, 0.0, -16.1)
  assert struck_at(box, 0.0, -4.1)
  assert !struck_at(box, 0.0, -3.9)
  assert !struck_at(rectangle, 3.9, -12.9)
    as "2.9 m past a side and 2.9 m past the end is 4.10 m from the corner, not within 3"
  assert !struck_at(box, 4.9, -15.9)
    as "2.9 m past a side and 2.9 m past the end is 4.10 m from the corner, not within 3"
  assert struck_at(box, 4.9, -13.0)
    as "2.9 m past a side, level with the end: 2.9 m from the box"
  let cone = placed(Cone(inner: 4.0, outer: 10.0, degrees: 90.0), 0.0)
  assert struck_at(cone, 0.0, -12.9) as "a cone to 10 m reaches 13 m"
  assert !struck_at(cone, 0.0, -13.1)
  assert struck_at(cone, 0.0, -1.1) as "a cone from 4 m reaches back to 1 m"
  assert !struck_at(cone, 0.0, -0.9)
}

pub fn a_unit_just_outside_a_cones_side_by_less_than_its_hit_radius_is_struck_and_by_more_is_not_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Row(min_range: 0.0, max_range: 30.0, degrees: 360.0, target_count: 5)
  let cone =
    InsideShapes([
      Placement(
        shape: Cone(inner: 1.0, outer: 10.0, degrees: 90.0),
        ahead: 0.0,
        aside: 0.0,
        turn_degrees: 0.0,
      ),
    ])
  let struck_at = fn(distance, degrees) {
    struck(
      candidates: [beast(1, at(distance:, degrees:, yaw: 0.0))],
      row:,
      inside: cone,
    )
    == [1]
  }
  // The cone's sides lie 45 degrees off the facing. A unit 5 m out and d degrees
  // past a side is 5 x sin(d) m from the side line: 35.4 degrees is 2.9 m, 38.4
  // degrees 3.1 m, each side of the Beast's hit radius of 3.
  assert struck_at(5.0, 80.4) as "2.9 m from the side line"
  assert !struck_at(5.0, 83.4) as "3.1 m from the side line"
  assert struck_at(5.0, -80.4)
  assert !struck_at(5.0, -83.4)
  assert !struck_at(2.9, 180.0)
    as "2.9 m straight behind the apex: the cone has no shape at its tip, its sides start 1 m out, so the nearest point is the inner corner, 3.68 m away"
  assert struck_at(12.0, 55.0)
    as "10 degrees past a side, 12 m out: 2.76 m from the outer corner"
  assert !struck_at(12.0, 59.0)
    as "14 degrees past a side, 12 m out: 3.33 m from the outer corner, though 2.9 m from the side's line"
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

pub fn a_places_pose_is_its_ground_point_and_its_yaw_test() -> Nil {
  use <- owned_test.run(5000)
  let place =
    start_place.turned(
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x: 12.5,
        y: -7.0,
        z: -30.25,
      ),
      facing: start_place.Facing(yaw: 1.25, pitch: 0.5, roll: 0.25),
    )
  assert area.pose_of(place:) == Pose(at: Point(x: 12.5, z: -30.25), yaw: 1.25)
    as "the point on the ground (x and z) and the yaw; pitch, roll and the height play no part"
}
