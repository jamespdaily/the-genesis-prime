//// Which units an area strikes: pure geometry on the ground, from a centre and
//// the way it faces. The caster's connection selects a go's targets here from the
//// units its client shows (genesis_prime/game/strike), so the client is struck by
//// the picture it aimed at.
////
//// ```
//// candidates (alive foes the client shows)        centre: a unit's place and facing
////   keep those inside (the hit shapes capped by the area row's range, or the row alone)
////   order by distance from the centre, the lower unit id first on a tie
////   take the row's target count
//// ```
////
//// - **The client never selects** an area's targets: it reads the row only for the
////   UI and draws whatever units the go names, so who is struck, how many and in
////   what order is the server's rule (`Spell4AoeTargetConstraints.client_use`).
//// - **Facing** is the yaw of the last movement command of kind 14: the unit faces
////   (-sin yaw, -cos yaw), so yaw 0 faces -z and yaw pi/2 faces -x; a unit at the
////   offset (dx, dz) lies at the angle atan2(-dx, -dz) - yaw off the facing,
////   wrapped to -pi..pi (`movement_command.kind_14.facing`, `0x1401b3170`).
//// - **The area row** gives a unit's distance between `min_range` and `max_range`
////   and an angle off the facing of at most half `degrees`; 360 is all round. The
////   angle is the whole arc (`0x1405ecf20`). A spell with hit shapes uses the row's
////   range only: its shapes say where it reaches. The range stays on the distance
////   between the two centres: it is a selection constraint, not a shape, so a unit's
////   radius does not count in it.
////   (`Spell4.58591.area`: Kick's cone is narrower than its 180 degrees.)
//// - **A hit shape** is a telegraph's damage shape placed on the caster: its
////   offsets, x and z negated before the turn so a positive z is ahead
////   (`0x14054b1b0`), and its turn, which adds to the centre's yaw as a turn of the
////   unit itself does (`0x14054b1b0.shape_turn`, `0x14054b1b0.aside_offset`). The
////   point the shape is measured from is `origin_of`. A unit is inside when its hit circle touches the
////   shape: the distance from its centre to the nearest point of the shape is at most
////   its hit radius. The client sizes a drawn shape by the viewer's own radius
////   (`0x14054d170` case 4, `0x14054da10`) and tests no unit against a shape
////   (`unit.hit_radius`), so that a struck unit's body counts, for every shape
////   whatever flag 0x200 says, is the server's choice. The shapes are a circle, a
////   rectangle or box (the nearest point is the centre clamped to it, so a corner is
////   round) and a cone, an annular sector from its inner to its outer radius over its
////   angle, which has no point at its tip when its inner radius is above 0.
//// - **Distance and order** are horizontal, from centre to centre; the vertical
////   range is -1 for every row and the shapes lie on the ground
////   (`Spell4AoeTargetConstraints.targetVerticalRange`). Closest is the one order
////   the rows name (`Spell4AoeTargetConstraints.targetSelection`); what "closest"
////   measures is the server's choice.

import genesis_prime/game/start_place.{type Place}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import gleam/order
import gleam_community/maths

/// A place on the ground: x and z, the axes the client's yaw turns about.
pub type Point {
  Point(x: Float, z: Float)
}

/// The point on the ground a place stands at.
pub fn point_of(place place: Place) -> Point {
  Point(x: start_place.x(place), z: start_place.z(place))
}

/// A centre and the way it faces: the place of a caster, or of the unit a child
/// cast is made on, and the yaw of its last kind 14 command.
pub type Pose {
  Pose(at: Point, yaw: Float)
}

/// The pose of a place: its ground point and its facing's yaw.
pub fn pose_of(place place: Place) -> Pose {
  Pose(at: point_of(place:), yaw: start_place.facing(place).yaw)
}

/// A telegraph's damage shape (`TelegraphDamage.damageShapeEnum`).
pub type Shape {
  /// Shape 0.
  Circle(radius: Float)
  /// Shape 2: a box centred on the placement.
  Box(width: Float, length: Float)
  /// Shapes 4 and 8: from the inner to the outer radius, over `degrees` in all.
  Cone(inner: Float, outer: Float, degrees: Float)
  /// Shape 7: from the placement, `length` ahead of it.
  Rectangle(width: Float, length: Float)
}

/// Where a creature special's hit is centred, which is where its picture is drawn
/// (genesis_prime/game/telegraph_entries): a spell has one anchor, read from its hit rows'
/// flags (genesis_prime/game/spell_area `anchor_of`).
pub type Anchor {
  /// Rows with neither 0x4000 nor 0x1000: the client draws them on the caster each frame
  /// from its own place and facing, so the hit is centred on the caster where it stands at
  /// the strike (`0x14054b1b0.follows_caster`).
  FollowsCaster
  /// Rows with 0x4000 or 0x1000: the client draws them where the server put them at the
  /// cast's start, so the hit is centred on the pose the cast started at
  /// (`0x14054b1b0.fixed_placement`).
  FixedAtCaster
}

/// A shape placed on the caster: where it lies against the caster's place and
/// facing. The struck unit's hit radius grows it.
pub type Placement {
  Placement(
    shape: Shape,
    /// The offset ahead of the caster, from the row's z (positive is ahead).
    ahead: Float,
    /// The row's x offset, negated before the turn: a positive x lies at
    /// (-cos yaw, sin yaw) from the caster.
    aside: Float,
    /// The turn of the shape off the caster's facing, in degrees.
    turn_degrees: Float,
  )
}

/// A unit that may be struck, as the connection's picture gives it: the unit id,
/// its place and its hit radius. The connection leaves out the dead, the units
/// that are not foes and the caster before it gives candidates.
pub type Candidate {
  Candidate(unit_id: Int, at: Point, hit_radius: Float)
}

/// An area row: `Spell4AoeTargetConstraints` minRange, maxRange, angle and
/// targetCount, in the client's units.
pub type Row {
  Row(min_range: Float, max_range: Float, degrees: Float, target_count: Int)
}

/// How a unit counts as inside the area (genesis_prime/game/spell_area `inside`).
pub type Inside {
  /// By the area row alone: the unit's distance between `min_range` and
  /// `max_range` and its angle off the facing. A spell with no telegraph row.
  InsideRow
  /// By any of these shapes placed on the centre, capped by the row's range: the
  /// unit's distance from the centre is between `min_range` and `max_range`, whatever
  /// the row's angle.
  InsideShapes(placements: List(Placement))
}

/// The angle of `target` off the facing `yaw` of a unit at `from`, in radians
/// wrapped to -pi..pi: atan2(-dx, -dz) - yaw (`movement_command.kind_14.facing`).
/// 0 for a target on the unit's own point.
pub fn bearing(
  from from: Point,
  target target: Point,
  yaw yaw: Float,
) -> Float {
  let dx = target.x -. from.x
  let dz = target.z -. from.z
  // The sum of squares is +0.0 for either sign of a zero difference, which `==`
  // (`=:=` on floats) tells apart from -0.0.
  case dx *. dx +. dz *. dz == 0.0 {
    True -> 0.0
    False -> wrapped(maths.atan2(float.negate(dx), float.negate(dz)) -. yaw)
  }
}

fn wrapped(angle: Float) -> Float {
  let two_pi = 2.0 *. maths.pi()
  case angle >. maths.pi() {
    True -> wrapped(angle -. two_pi)
    False ->
      case angle <. float.negate(maths.pi()) {
        True -> wrapped(angle +. two_pi)
        False -> angle
      }
  }
}

fn distance(from from: Point, to to: Point) -> Float {
  let dx = to.x -. from.x
  let dz = to.z -. from.z
  let assert Ok(root) = float.square_root(dx *. dx +. dz *. dz)
    as "a sum of squares is not negative"
  root
}

/// The ground distance between two bodies' edges: the distance between their points
/// less both hit radii, never below 0. The client's own reach test measures in three
/// dimensions (`0x1403ad690`), so the ground distance is never larger than its.
pub fn edge_gap(
  from from: Point,
  from_radius from_radius: Float,
  to to: Point,
  to_radius to_radius: Float,
) -> Float {
  float.max(distance(from:, to:) -. from_radius -. to_radius, 0.0)
}

/// Whether the candidate is inside the area of the row at the centre.
fn is_inside(
  candidate candidate: Candidate,
  centre centre: Pose,
  row row: Row,
  inside inside: Inside,
) -> Bool {
  let reach = distance(from: centre.at, to: candidate.at)
  let in_range = reach >=. row.min_range && reach <=. row.max_range
  case inside {
    InsideRow ->
      in_range
      && float.absolute_value(bearing(
        from: centre.at,
        target: candidate.at,
        yaw: centre.yaw,
      ))
      <=. maths.degrees_to_radians(row.degrees /. 2.0) +. 0.000001
    InsideShapes(placements:) ->
      in_range
      && list.any(placements, fn(placement) {
        in_shape(candidate:, centre:, placement:)
      })
  }
}

/// The point a row's shape is measured from when it is placed on a unit at `centre`: the
/// unit's point moved `ahead` along its facing and `aside` to the side a positive x offset
/// lies on, (-cos yaw, sin yaw). The telegraph's entry names this point for a row the client
/// does not offset itself, and the hit measures from it, so the picture and the hit agree.
pub fn origin_of(
  centre centre: Pose,
  ahead ahead: Float,
  aside aside: Float,
) -> Point {
  let facing_x = float.negate(maths.sin(centre.yaw))
  let facing_z = float.negate(maths.cos(centre.yaw))
  Point(
    x: centre.at.x +. ahead *. facing_x -. aside *. maths.cos(centre.yaw),
    z: centre.at.z +. ahead *. facing_z +. aside *. maths.sin(centre.yaw),
  )
}

/// Whether the unit's hit circle overlaps the placed shape.
fn in_shape(
  candidate candidate: Candidate,
  centre centre: Pose,
  placement placement: Placement,
) -> Bool {
  let origin =
    origin_of(centre:, ahead: placement.ahead, aside: placement.aside)
  let yaw = centre.yaw +. maths.degrees_to_radians(placement.turn_degrees)
  let shape_x = float.negate(maths.sin(yaw))
  let shape_z = float.negate(maths.cos(yaw))
  let dx = candidate.at.x -. origin.x
  let dz = candidate.at.z -. origin.z
  let forward = dx *. shape_x +. dz *. shape_z
  let sideways = dx *. maths.cos(yaw) -. dz *. maths.sin(yaw)
  let reach = distance(from: origin, to: candidate.at)
  let gap = case placement.shape {
    Circle(radius:) -> float.max(reach -. radius, 0.0)
    Box(width:, length:) ->
      gap_to_box(
        sideways:,
        forward:,
        half_width: width /. 2.0,
        near: float.negate(length /. 2.0),
        far: length /. 2.0,
      )
    Rectangle(width:, length:) ->
      gap_to_box(
        sideways:,
        forward:,
        half_width: width /. 2.0,
        near: 0.0,
        far: length,
      )
    Cone(inner:, outer:, degrees:) ->
      gap_to_cone(
        angle: bearing(from: origin, target: candidate.at, yaw:),
        reach:,
        inner:,
        outer:,
        half_angle: maths.degrees_to_radians(degrees /. 2.0),
      )
  }
  gap <=. candidate.hit_radius
}

/// The distance from a point to a box that is `half_width` either side of the shape's
/// line and from `near` to `far` along it: 0 inside, else to the nearest point of the
/// box, which is the point clamped to it.
fn gap_to_box(
  sideways sideways: Float,
  forward forward: Float,
  half_width half_width: Float,
  near near: Float,
  far far: Float,
) -> Float {
  distance(
    from: Point(x: 0.0, z: 0.0),
    to: Point(
      x: float.max(float.absolute_value(sideways) -. half_width, 0.0),
      z: float.max(float.max(near -. forward, forward -. far), 0.0),
    ),
  )
}

/// The distance from a unit at distance `reach` from a cone's apex and `angle` off its
/// facing to the cone: inside its angle, how far it is outside the band from `inner`
/// to `outer`; beyond a side, the distance to the nearer side segment, which runs from
/// `inner` to `outer` along the ray at `half_angle`, ending at its corners.
fn gap_to_cone(
  angle angle: Float,
  reach reach: Float,
  inner inner: Float,
  outer outer: Float,
  half_angle half_angle: Float,
) -> Float {
  let beyond = float.absolute_value(angle) -. half_angle
  case beyond <=. 0.000001 {
    True -> float.max(float.max(inner -. reach, reach -. outer), 0.0)
    False -> {
      let along = float.max(inner, float.min(outer, reach *. maths.cos(beyond)))
      distance(
        from: Point(x: along, z: 0.0),
        to: Point(x: reach *. maths.cos(beyond), z: reach *. maths.sin(beyond)),
      )
    }
  }
}

/// How far from the centre the hit shapes reach at most: the farthest point of any of
/// them, from the placement's offset and the shape's own extent (a circle's radius, a
/// cone's outer radius, a box's or rectangle's far corner), or `None` when the area is the
/// row alone (`InsideRow`), which holds no shape. A rule that needs a distance from the
/// centre to a unit it can still strike caps it by the area row's `max_range` and adds the
/// struck unit's hit radius itself (`in_shape`).
pub fn farthest_of(inside inside: Inside) -> Option(Float) {
  case inside {
    InsideRow -> None
    InsideShapes(placements:) ->
      list.map(placements, fn(placement) {
        length_of(placement.ahead, placement.aside)
        +. extent_of(shape: placement.shape)
      })
      |> list.reduce(float.max)
      |> option.from_result
  }
}

/// The farthest point of a shape from its own placement.
fn extent_of(shape shape: Shape) -> Float {
  case shape {
    Circle(radius:) -> radius
    Box(width:, length:) -> length_of(width /. 2.0, length /. 2.0)
    Cone(outer:, ..) -> outer
    Rectangle(width:, length:) -> length_of(width /. 2.0, length)
  }
}

/// The length of the vector (a, b).
fn length_of(a: Float, b: Float) -> Float {
  distance(from: Point(x: 0.0, z: 0.0), to: Point(x: a, z: b))
}

/// The unit ids the area strikes, nearest first: the candidates inside, ordered
/// by distance from the centre with the lower unit id first on a tie, at most the
/// row's target count.
pub fn select(
  candidates candidates: List(Candidate),
  centre centre: Pose,
  row row: Row,
  inside inside: Inside,
) -> List(Int) {
  list.filter(candidates, fn(candidate) {
    is_inside(candidate:, centre:, row:, inside:)
  })
  |> list.map(fn(candidate) {
    #(distance(from: centre.at, to: candidate.at), candidate.unit_id)
  })
  |> list.sort(fn(first, second) {
    float.compare(first.0, second.0)
    |> order.break_tie(int.compare(first.1, second.1))
  })
  |> list.take(row.target_count)
  |> list.map(fn(found) { found.1 })
}
