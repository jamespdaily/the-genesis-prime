//// A place on the map, in metres, and the distance rules both prototypes
//// share. Pure.

/// A place on the map: metres east and metres north of its origin.
pub type Position {
  Position(x: Float, y: Float)
}

/// The square of the distance between two positions, in square metres. Range
/// checks compare squares, so no square root is taken on a hot path.
pub fn distance_squared(a: Position, b: Position) -> Float {
  todo as "body in the build commit"
}

/// The position reached by walking from `from` toward `to` for `metres`
/// metres in a straight line. A walk that is long enough ends on `to`, never
/// past it.
pub fn step_toward(from: Position, to: Position, metres: Float) -> Position {
  todo as "body in the build commit"
}

/// Whether two positions are at most `range` metres apart. A position exactly
/// `range` away is within range.
pub fn within(a: Position, b: Position, range: Float) -> Bool {
  todo as "body in the build commit"
}
