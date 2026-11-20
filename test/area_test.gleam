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
//// - Order: nearest first, the lower unit id on a tie (the step's design, section 1);
////   Furthest is Closest reversed with the same tie rule, and Random a guess marked in
////   `area` (`Spell4AoeTargetConstraints.targetSelection`: the client names the orders and
////   applies none).
//// - Shapes 1, 3, 5 and 6: the client's drawing (`0x14054d170.shapes_1_3_5_6`), whose
////   placements `spell_area` builds; the rows named in the tests are TelegraphDamage 3852,
////   3029, 6957, 2920 and 4664.
//// - Jim's choice: a unit is struck inside the telegraph's shape and within the area
////   row's range; a spell with no telegraph is struck by its area row's range and arc.
//// - Crush's 42297 has no telegraph row, so its area row alone decides (`Spell4.32812.area`).

import client_shape_rows
import genesis_prime/game/area.{
  type Candidate, type Inside, type Placement, type Point, type Pose, type Row,
  AnotherUnit, Box, Candidate, Circle, Cone, FixedAtCaster, FixedAtTarget,
  FollowsCaster, FollowsTarget, InsideRow, InsideShapes, Placement, Point, Pose,
  Rectangle, Row, TheCaster,
}
import genesis_prime/game/start_place
import gleam/float
import gleam/int
import gleam/list
import gleam_community/maths
import owned_test
import place_support
import qcheck

const beast_hit_radius = 3.0

fn kick_row() -> area.Row {
  Row(
    min_range: 0.0,
    max_range: 8.0,
    degrees: 180.0,
    target_count: 5,
    order: area.Nearest,
  )
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
      row: Row(
        min_range: 0.0,
        max_range: 30.0,
        degrees: 180.0,
        target_count: 5,
        order: area.Nearest,
      ),
      inside: kick_cone(),
    )
    == []
    as "10.1 m is past the cone's 7 m by more than the Beast's hit radius of 3 (a 30 m row, so the shape alone decides)"
  assert struck(
      candidates: [beast(1, at(distance: 3.0, degrees: 180.0, yaw: 0.0))],
      row: Row(
        min_range: 0.0,
        max_range: 30.0,
        degrees: 360.0,
        target_count: 5,
        order: area.Nearest,
      ),
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
    Row(
      min_range: 0.0,
      max_range: 25.0,
      degrees: 360.0,
      target_count: 1,
      order: area.Nearest,
    )
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
    Row(
      min_range: 0.0,
      max_range: 25.0,
      degrees: 360.0,
      target_count: 1,
      order: area.Nearest,
    )
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
    Row(
      min_range: 0.0,
      max_range: 15.0,
      degrees: 180.0,
      target_count: 5,
      order: area.Nearest,
    )
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
    Row(
      min_range: 0.0,
      max_range: 30.0,
      degrees: 360.0,
      target_count: 5,
      order: area.Nearest,
    )
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
    Row(
      min_range: 0.0,
      max_range: 25.0,
      degrees: 360.0,
      target_count: 1,
      order: area.Nearest,
    )
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
    Row(
      min_range: 0.0,
      max_range: 25.0,
      degrees: 360.0,
      target_count: 5,
      order: area.Nearest,
    )
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
    Row(
      min_range: 0.0,
      max_range: 30.0,
      degrees: 360.0,
      target_count: 5,
      order: area.Nearest,
    )
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
    Row(
      min_range: 0.0,
      max_range: 30.0,
      degrees: 360.0,
      target_count: 5,
      order: area.Nearest,
    )
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

/// -0.0, a zero the sign of which `=:=` tells apart from 0.0 on OTP 29.
fn negative_zero() -> Float {
  float.negate(0.0)
}

pub fn bearing_of_a_target_on_the_point_is_0_with_negative_zero_test() -> Nil {
  use <- owned_test.run(5000)
  let from = Point(x: 0.0, z: 0.0)
  list.each(
    [
      Point(x: negative_zero(), z: 0.0),
      Point(x: 0.0, z: negative_zero()),
      Point(x: negative_zero(), z: negative_zero()),
    ],
    fn(target) {
      assert area.bearing(from:, target:, yaw: 0.0) == 0.0
        as "a target on the unit's own point bears 0 whatever the sign of a zero difference (the doc of `bearing`)"
    },
  )
}

pub fn area_with_a_cone_takes_a_unit_on_its_centre_at_negative_zero_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    Row(
      min_range: 0.0,
      max_range: 8.0,
      degrees: 90.0,
      target_count: 5,
      order: area.Nearest,
    )
  assert struck(
      candidates: [beast(1, Point(x: 0.0, z: 0.0))],
      row:,
      inside: InsideRow,
    )
    == [1]
    as "a unit on the centre is at distance 0, inside minRange 0, and at bearing 0, inside the 90 degree cone"
  assert struck(
      candidates: [beast(1, Point(x: negative_zero(), z: 0.0))],
      row:,
      inside: InsideRow,
    )
    == [1]
    as "the same unit with a negative zero in x is on the centre all the same"
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

pub fn the_origin_of_a_placement_is_the_point_the_hit_measures_from_test() -> Nil {
  use <- owned_test.run(5000)
  // The point itself is the client's: worked from the matrix of `0x14054b1b0.aside_offset` and
  // `0x14054b1b0.shape_turn` (the offset (-aside, -ahead) turned by the rows (cos, -sin) and
  // (sin, cos) of the yaw), not computed by `origin_of`. x offset 1 at yaw 0 -> (-1, 0) and at
  // yaw 90 -> (0, 1) are the emulator's runs; a z offset of 2 lies 2 along -z at yaw 0 and 2
  // along -x at yaw 90; row 3881 (z offset 16, x offset -6) from a unit at (100, 200) gives
  // (106, 184) at yaw 0 and (84, 194) at yaw 90.
  let quarter = maths.pi() /. 2.0
  list.each(
    [
      #(Point(x: 0.0, z: 0.0), 0.0, 0.0, 1.0, Point(x: -1.0, z: 0.0)),
      #(Point(x: 0.0, z: 0.0), quarter, 0.0, 1.0, Point(x: 0.0, z: 1.0)),
      #(Point(x: 0.0, z: 0.0), 0.0, 2.0, 0.0, Point(x: 0.0, z: -2.0)),
      #(Point(x: 0.0, z: 0.0), quarter, 2.0, 0.0, Point(x: -2.0, z: 0.0)),
      #(Point(x: 100.0, z: 200.0), 0.0, 16.0, -6.0, Point(x: 106.0, z: 184.0)),
      #(
        Point(x: 100.0, z: 200.0),
        quarter,
        16.0,
        -6.0,
        Point(x: 84.0, z: 194.0),
      ),
    ],
    fn(case_) {
      let #(at, yaw, ahead, aside, wanted) = case_
      let got = area.origin_of(centre: Pose(at:, yaw:), ahead:, aside:)
      assert float.loosely_equals(got.x, wanted.x, tolerating: 0.000_001)
        && float.loosely_equals(got.z, wanted.z, tolerating: 0.000_001)
        as "the origin is the point the client's matrix puts the offsets at"
    },
  )
  // The hit measures its shapes from that same point, so a fighter standing on it is inside a
  // circle of any radius and a box centred there, whatever the pose and the row's offsets.
  qcheck.given(
    qcheck.tuple4(
      qcheck.tuple3(
        qcheck.bounded_float(from: -500.0, to: 500.0),
        qcheck.bounded_float(from: -500.0, to: 500.0),
        qcheck.bounded_float(from: -3.1, to: 3.1),
      ),
      qcheck.bounded_float(from: -20.0, to: 20.0),
      qcheck.bounded_float(from: -20.0, to: 20.0),
      qcheck.bounded_float(from: 0.5, to: 10.0),
    ),
    fn(drawn) {
      let #(#(x, z, yaw), ahead, aside, size) = drawn
      let pose = Pose(at: Point(x:, z:), yaw:)
      let there = area.origin_of(centre: pose, ahead:, aside:)
      list.each(
        [Circle(radius: size), Box(width: size, length: size)],
        fn(shape) {
          assert area.select(
              candidates: [Candidate(unit_id: 1, at: there, hit_radius: 0.0)],
              centre: pose,
              row: Row(
                min_range: 0.0,
                max_range: 1000.0,
                degrees: 360.0,
                target_count: 1,
                order: area.Nearest,
              ),
              inside: InsideShapes([
                Placement(shape:, ahead:, aside:, turn_degrees: 0.0),
              ]),
            )
            == [1]
            as "a fighter on the origin is inside a shape centred there"
        },
      )
    },
  )
}

fn ordered_row(order order: area.Order, target_count target_count: Int) -> Row {
  Row(min_range: 0.0, max_range: 30.0, degrees: 360.0, target_count:, order:)
}

/// The ids `select_ordered` takes of `candidates` in an area that is the row's range alone.
fn ordered(
  candidates candidates: List(Candidate),
  order order: area.Order,
  target_count target_count: Int,
  seed seed: Int,
) -> List(Int) {
  area.select_ordered(
    candidates:,
    centre: origin,
    row: ordered_row(order:, target_count:),
    inside: InsideRow,
    seed:,
  )
}

pub fn furthest_takes_the_farthest_inside_first_and_a_tie_goes_to_the_lower_unit_id_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4AoeTargetConstraints.targetSelection 2 is Furthest; the client orders nothing, so
  // the order is the rule's: Closest reversed, with Closest's tie rule (the lower unit id).
  let candidates = [
    beast(3, at(distance: 9.0, degrees: 0.0, yaw: 0.0)),
    beast(8, at(distance: 6.0, degrees: 90.0, yaw: 0.0)),
    beast(2, at(distance: 6.0, degrees: -90.0, yaw: 0.0)),
    beast(1, at(distance: 2.0, degrees: 0.0, yaw: 0.0)),
    beast(9, at(distance: 31.0, degrees: 0.0, yaw: 0.0)),
  ]
  list.each(
    [
      #(1, [3]),
      #(2, [3, 2]),
      #(3, [3, 2, 8]),
      #(4, [3, 2, 8, 1]),
      #(9, [3, 2, 8, 1]),
    ],
    fn(case_) {
      let #(target_count, wanted) = case_
      assert ordered(candidates:, order: area.Furthest, target_count:, seed: 0)
        == wanted
        as "the farthest inside first (unit 9 stands outside the 30 m row), units 2 and 8 tied at 6 m by the lower id, at most the target count"
    },
  )
}

/// Units `unit_ids`, each once, standing 5 m out at its own angle.
fn spread(unit_ids unit_ids: List(Int)) -> List(Candidate) {
  list.unique(unit_ids)
  |> list.map(fn(unit_id) {
    beast(unit_id, at(distance: 5.0, degrees: int.to_float(unit_id), yaw: 0.0))
  })
}

pub fn random_is_the_same_for_a_seed_and_never_repeats_a_unit_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client names Random and orders nothing, so the order is a guess marked in `area`
  // (units by the MurmurHash3 finalizer of `seed * 0x9E3779B1 + unit_id`, masked to 32
  // bits). Worked outside the code: for units 10, 20 and 30, seed 0 puts 20, 10, 30 in
  // that order and seed 7 puts 20, 30, 10, so the seed orders them. The property holds
  // each unit once and no more than the target count.
  let worked = spread(unit_ids: [10, 20, 30])
  assert ordered(
      candidates: worked,
      order: area.Random,
      target_count: 3,
      seed: 0,
    )
    == [20, 10, 30]
    as "seed 0 orders units 10, 20 and 30 as 20, 10, 30"
  assert ordered(
      candidates: worked,
      order: area.Random,
      target_count: 3,
      seed: 7,
    )
    == [20, 30, 10]
    as "seed 7 orders them as 20, 30, 10"
  qcheck.given(
    qcheck.tuple3(
      qcheck.bounded_int(from: 0, to: 1_000_000_000),
      qcheck.list_from(qcheck.bounded_int(from: 1, to: 60)),
      qcheck.bounded_int(from: 1, to: 8),
    ),
    fn(drawn) {
      let #(seed, unit_ids, target_count) = drawn
      let candidates = spread(unit_ids:)
      let found = ordered(candidates:, order: area.Random, target_count:, seed:)
      assert list.unique(found) == found as "a unit is taken once"
      assert list.length(found)
        == int.min(target_count, list.length(candidates))
        as "as many as the target count, or all there are"
    },
  )
}

pub fn random_gives_each_inside_unit_a_fair_share_of_first_places_test() -> Nil {
  use <- owned_test.run(60_000)
  // The same guess; the bounds are this test's tolerance for the 32-bit mix over 3000 seeds
  // (an even share is 33 percent).
  let candidates = [
    beast(10, at(distance: 4.0, degrees: 0.0, yaw: 0.0)),
    beast(20, at(distance: 5.0, degrees: 90.0, yaw: 0.0)),
    beast(30, at(distance: 6.0, degrees: 180.0, yaw: 0.0)),
  ]
  let firsts =
    int.range(from: 0, to: 3000, with: [], run: fn(seeds, seed) {
      [seed, ..seeds]
    })
    |> list.flat_map(fn(seed) {
      ordered(candidates:, order: area.Random, target_count: 1, seed:)
    })
  list.each([10, 20, 30], fn(unit_id) {
    let share = list.count(firsts, fn(first) { first == unit_id })
    assert share >= 840 && share <= 1170
      as "each of three units is first in 28 to 39 percent of 3000 seeds"
  })
}

pub fn every_order_selects_only_units_inside_and_at_most_the_target_count_test() -> Nil {
  use <- owned_test.run(60_000)
  qcheck.given(
    qcheck.tuple4(
      qcheck.bounded_int(from: 0, to: 2),
      qcheck.bounded_int(from: 0, to: 1_000_000_000),
      qcheck.list_from(qcheck.bounded_int(from: 1, to: 40)),
      qcheck.bounded_int(from: 0, to: 6),
    ),
    fn(drawn) {
      let #(order_number, seed, unit_ids, target_count) = drawn
      let order = case order_number {
        0 -> area.Nearest
        1 -> area.Furthest
        _ -> area.Random
      }
      // Unit n stands n m out: the 30 m row holds units 1 to 30 and not 31 to 40.
      let candidates =
        list.unique(unit_ids)
        |> list.map(fn(unit_id) {
          beast(
            unit_id,
            at(distance: int.to_float(unit_id), degrees: 0.0, yaw: 0.0),
          )
        })
      let row = ordered_row(order:, target_count:)
      let found =
        area.select_ordered(
          candidates:,
          centre: origin,
          row:,
          inside: InsideRow,
          seed:,
        )
      assert list.all(found, fn(unit_id) { unit_id <= 30 })
        as "a unit past the row's 30 m is never taken"
      assert list.length(found) <= target_count
        as "no more than the target count"
      // Unit n stands n m out, so the nearest first are the lowest ids.
      assert area.select(candidates:, centre: origin, row:, inside: InsideRow)
        == list.take(
          list.sort(
            list.filter(list.unique(unit_ids), fn(id) { id <= 30 }),
            int.compare,
          ),
          target_count,
        )
        as "the player's select is the nearest units whatever the row's order"
    },
  )
}

/// The ids the placements hold among `units` (id, distance, degrees off the facing), for a
/// hit radius of `hit_radius`, ascending.
fn held(
  placements placements: List(Placement),
  units units: List(#(Int, Float, Float)),
  hit_radius hit_radius: Float,
) -> List(Int) {
  area.select(
    candidates: list.map(units, fn(unit) {
      Candidate(
        unit_id: unit.0,
        at: at(distance: unit.1, degrees: unit.2, yaw: 0.0),
        hit_radius:,
      )
    }),
    centre: origin,
    row: ordered_row(order: area.Nearest, target_count: 99),
    inside: InsideShapes(placements),
  )
  |> list.sort(int.compare)
}

pub fn a_ring_and_a_pie_hold_the_units_the_clients_shape_code_draws_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x14054d170 case 1: a ring from param00 to param01 whole round (the angle 2 pi, as shape 4
  // with 360 degrees); case 5: a circle from param00 to param01 missing a slice of param02
  // degrees, drawn as the arc 2 pi less param02 with the facing turned by pi (bytes at
  // 0x140b79fac), so the slice lies ahead of the row's own turn. TelegraphDamage 3852 is the
  // ring (3 to 5), 3029 the pie (0 to 7, 90 degrees, turned 150) and 6957 the pie (4 to 13,
  // 105 degrees, turned 180); the placements are as those rows give them.
  let assert [ring] = client_shape_rows.placements_of(row_id: 3852)
  let units = [
    #(1, 4.0, 0.0),
    #(2, 4.0, 180.0),
    #(3, 2.0, 0.0),
    #(4, 6.0, 90.0),
  ]
  assert held(placements: [ring], units:, hit_radius: 0.0) == [1, 2]
    as "the units between the radii, in front and behind"
  assert held(placements: [ring], units:, hit_radius: 1.5) == [1, 2, 3, 4]
    as "a hit radius of 1.5 reaches in to 1.5 and out to 6.5 from the 3 to 5 ring"
  let assert [pie_3029] = client_shape_rows.placements_of(row_id: 3029)
  let round = [
    #(1, 4.0, 0.0),
    #(2, 4.0, 90.0),
    #(3, 4.0, 150.0),
    #(4, 4.0, 210.0),
    #(5, 4.0, -90.0),
    #(6, 8.0, 0.0),
  ]
  assert held(placements: [pie_3029], units: round, hit_radius: 0.0)
    == [1, 2, 4, 5]
    as "row 3029: everything within 7 m but the 90 degree slice ahead of its 150 degree turn (150 is in it; 90 and 210 are clear of it)"
  assert held(placements: [pie_3029], units: round, hit_radius: 1.5)
    == [1, 2, 4, 5, 6]
    as "a hit radius of 1.5 reaches the unit at 8 m, 1 past the 7 m edge"
  let assert [pie_6957] = client_shape_rows.placements_of(row_id: 6957)
  let behind = [
    #(1, 8.0, 0.0),
    #(2, 8.0, 180.0),
    #(3, 8.0, 120.0),
    #(4, 2.0, 0.0),
    #(5, 14.5, 0.0),
  ]
  assert held(placements: [pie_6957], units: behind, hit_radius: 0.0) == [1, 3]
    as "row 6957: the 4 to 13 ring but the 105 degree slice ahead of its 180 degree turn, which is behind the caster; the units inside 4 and beyond 13 are out"
}

pub fn two_boxes_make_a_cross_and_shape_6_is_the_unhalved_box_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x14054d170 case 3: box 0 has param00 wide and param02 long, box 1 the two swapped; case 6
  // takes the params as the half sizes where case 2 halves them, so it is twice the box.
  // TelegraphDamage 2920 is the cross (2.5 wide, 18 long) and 4664 shape 6 (params 1, 17, 2,
  // 4 ahead); the placements are as those rows give them.
  let units = [
    #(1, 8.0, 0.0),
    #(2, 8.0, 90.0),
    #(3, 8.0, 180.0),
    #(4, 8.0, 45.0),
    #(5, 8.5, 270.0),
  ]
  let cross = client_shape_rows.placements_of(row_id: 2920)
  let assert [arm, _] = cross as "the cross is two boxes"
  assert held(placements: cross, units:, hit_radius: 0.0) == [1, 2, 3, 5]
    as "inside along each arm, ahead, to the side and behind, and not on the diagonal at 45 degrees"
  assert held(placements: [arm], units:, hit_radius: 0.0) == [1, 3]
    as "the first box alone holds the units ahead and behind; the second is what the cross adds"
  let assert [full] = client_shape_rows.placements_of(row_id: 4664)
  let half = Placement(..full, shape: Box(width: 1.0, length: 2.0))
  let near = [#(1, 3.0, 15.0), #(2, 5.9, 0.0)]
  assert held(placements: [half], units: near, hit_radius: 0.0) == []
    as "the shape 2 box (1 by 2, centred 4 ahead) holds neither unit: 3 m out at 15 degrees is 0.78 aside, past its half width of 0.5, and 5.9 m is past its far side at 5"
  assert held(placements: [full], units: near, hit_radius: 0.0) == [1, 2]
    as "shape 6 on the same params is twice the box, 2 by 4 centred 4 ahead: its half width is 1 and it reaches 6"
}

fn pose_from(drawn: #(Float, Float, Float)) -> Pose {
  Pose(at: Point(x: drawn.0, z: drawn.1), yaw: drawn.2)
}

fn drawn_pose() -> qcheck.Generator(Pose) {
  qcheck.map(
    qcheck.tuple3(
      qcheck.bounded_float(from: -500.0, to: 500.0),
      qcheck.bounded_float(from: -500.0, to: 500.0),
      qcheck.bounded_float(from: -3.1, to: 3.1),
    ),
    pose_from,
  )
}

pub fn an_anchor_fixed_at_the_start_never_follows_the_caster_and_a_following_one_never_reads_the_start_test() -> Nil {
  use <- owned_test.run(5000)
  qcheck.given(
    qcheck.tuple4(drawn_pose(), drawn_pose(), drawn_pose(), drawn_pose()),
    fn(drawn) {
      let #(caster, other_caster, started_at, other_start) = drawn
      let primary = TheCaster
      assert area.centre_of(
          anchor: FixedAtCaster,
          caster:,
          started_at:,
          primary:,
        )
        == area.centre_of(
          anchor: FixedAtCaster,
          caster: other_caster,
          started_at:,
          primary:,
        )
        as "a row fixed at the start (0x1405a4e60 stores the pose once) does not move with the caster"
      assert area.centre_of(
          anchor: FollowsCaster,
          caster:,
          started_at:,
          primary:,
        )
        == area.centre_of(
          anchor: FollowsCaster,
          caster:,
          started_at: other_start,
          primary:,
        )
        as "a row that follows its unit (0x14054b1b0.follows_caster) never reads the start"
    },
  )
  each_anchor_by_each_primary()
}

/// The centre of each of the four anchors for each kind of primary target.
fn each_anchor_by_each_primary() -> Nil {
  let caster = Pose(at: Point(x: 10.0, z: 20.0), yaw: 1.0)
  let started_at = Pose(at: Point(x: -3.0, z: 4.0), yaw: -0.5)
  let unit = Pose(at: Point(x: 7.0, z: 8.0), yaw: 0.0)
  [
    #(
      FollowsCaster,
      TheCaster,
      caster,
      "a row drawn on the caster each frame is centred where it stands now",
    ),
    #(
      FollowsCaster,
      AnotherUnit(pose: unit),
      caster,
      "the caster's row is the caster's whoever the primary target is",
    ),
    #(
      FixedAtCaster,
      TheCaster,
      started_at,
      "a row drawn at the 0x7ff's entry stays at the start pose",
    ),
    #(
      FixedAtCaster,
      AnotherUnit(pose: unit),
      started_at,
      "a fixed row of a child cast on a struck unit is at the caster's start, not on the unit",
    ),
    #(
      FollowsTarget,
      TheCaster,
      caster,
      "the primary target is the caster: its place now",
    ),
    #(
      FollowsTarget,
      AnotherUnit(pose: unit),
      unit,
      "a row on another primary target is on that unit",
    ),
    #(
      FixedAtTarget,
      TheCaster,
      started_at,
      "the primary target is the caster: its start pose",
    ),
    #(
      FixedAtTarget,
      AnotherUnit(pose: unit),
      unit,
      "another primary target: the place the picture shows it at",
    ),
  ]
  |> list.each(fn(row) {
    let #(anchor, primary, expected, reason) = row
    assert area.centre_of(anchor:, caster:, started_at:, primary:) == expected
      as reason
  })
}
