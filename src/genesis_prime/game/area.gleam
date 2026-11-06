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
////   range only: its shapes say where it reaches.
////   (`Spell4.58591.area`: Kick's cone is narrower than its 180 degrees.)
//// - **A hit shape** is a telegraph's damage shape placed on the caster: its
////   offsets, x and z negated before the turn so a positive z is ahead
////   (`0x14054b1b0`), and its turn. A unit is inside when its hit circle overlaps the
////   shape, which the server chooses to read as the outer radius and the half
////   extents grown by the unit's hit radius, and a cone's inner radius shrunk by it
////   but not below 0, as the client sizes a drawn shape by the viewer's own radius
////   (`0x14054d170` case 4, `0x14054da10`). Every shape grows, whatever flag 0x200
////   says: that flag only stops the drawn shape growing by the viewer's radius, and
////   the client tests no unit against a shape (`unit.hit_radius`); that a struck
////   unit's body counts is the server's choice. A cone's angle is not grown. The
////   direction of a row's turn is not read; every shape built so far has none.
//// - **Distance and order** are horizontal, from centre to centre; the vertical
////   range is -1 for every row and the shapes lie on the ground
////   (`Spell4AoeTargetConstraints.targetVerticalRange`). Closest is the one order
////   the rows name (`Spell4AoeTargetConstraints.targetSelection`); what "closest"
////   measures is the server's choice.

import genesis_prime/game/start_place.{type Place}
import gleam/float
import gleam/int
import gleam/list
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
  case dx == 0.0 && dz == 0.0 {
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

/// Whether the unit's hit circle overlaps the placed shape.
fn in_shape(
  candidate candidate: Candidate,
  centre centre: Pose,
  placement placement: Placement,
) -> Bool {
  let grown = candidate.hit_radius
  let facing_x = float.negate(maths.sin(centre.yaw))
  let facing_z = float.negate(maths.cos(centre.yaw))
  let origin =
    Point(
      x: centre.at.x
        +. placement.ahead
        *. facing_x
        -. placement.aside
        *. maths.cos(centre.yaw),
      z: centre.at.z
        +. placement.ahead
        *. facing_z
        +. placement.aside
        *. maths.sin(centre.yaw),
    )
  let yaw = centre.yaw +. maths.degrees_to_radians(placement.turn_degrees)
  let shape_x = float.negate(maths.sin(yaw))
  let shape_z = float.negate(maths.cos(yaw))
  let dx = candidate.at.x -. origin.x
  let dz = candidate.at.z -. origin.z
  let forward = dx *. shape_x +. dz *. shape_z
  let sideways = dx *. maths.cos(yaw) -. dz *. maths.sin(yaw)
  let reach = distance(from: origin, to: candidate.at)
  case placement.shape {
    Circle(radius:) -> reach <=. radius +. grown
    Box(width:, length:) ->
      float.absolute_value(sideways) <=. width /. 2.0 +. grown
      && float.absolute_value(forward) <=. length /. 2.0 +. grown
    Rectangle(width:, length:) ->
      float.absolute_value(sideways) <=. width /. 2.0 +. grown
      && forward >=. float.negate(grown)
      && forward <=. length +. grown
    Cone(inner:, outer:, degrees:) ->
      reach >=. float.max(0.0, inner -. grown)
      && reach <=. outer +. grown
      && float.absolute_value(bearing(from: origin, target: candidate.at, yaw:))
      <=. maths.degrees_to_radians(degrees /. 2.0) +. 0.000001
  }
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
