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
////   offsets, x and z negated before the turn so a positive z is ahead, its
////   turn, and its sizes grown by the struck unit's hit radius unless the row has
////   flag 0x200 (`0x14054d170`, `0x14054b1b0`, `0x14054da10`). A unit is inside
////   when its centre is inside the grown shape.
//// - **Distance and order** are horizontal, from centre to centre; the vertical
////   range is -1 for every row and the shapes lie on the ground
////   (`Spell4AoeTargetConstraints.targetVerticalRange`). Closest is the one order
////   the rows name (`Spell4AoeTargetConstraints.targetSelection`); what "closest"
////   measures is the server's choice.

/// A place on the ground: x and z, the axes the client's yaw turns about.
pub type Point {
  Point(x: Float, z: Float)
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
/// facing, and whether the struck unit's hit radius grows it.
pub type Placement {
  Placement(
    shape: Shape,
    /// The offset ahead of the caster, from the row's z (positive is ahead).
    ahead: Float,
    /// The offset to the caster's left, from the row's x.
    aside: Float,
    /// The turn of the shape off the caster's facing, in degrees.
    turn_degrees: Float,
    /// False for a row with flag 0x200, whose size does not grow.
    grows_by_hit_radius: Bool,
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
  unbuilt(inputs: #(from, target, yaw))
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
  unbuilt(inputs: #(candidates, centre, row, inside))
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
