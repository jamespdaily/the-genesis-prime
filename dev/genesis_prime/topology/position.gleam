//// A place on the map, in metres, and the distance rules both prototypes
//// share. Pure.

import gleam/float

/// A place on the map: metres east and metres north of its origin.
pub type Position {
  Position(x: Float, y: Float)
}

/// The square of the distance between two positions, in square metres. Range
/// checks compare squares, so no square root is taken on a hot path.
pub fn distance_squared(a a: Position, b b: Position) -> Float {
  let dx = a.x -. b.x
  let dy = a.y -. b.y
  dx *. dx +. dy *. dy
}

/// The position reached by walking from `from` toward `to` for `metres`
/// metres in a straight line. A walk that is long enough ends on `to`, never
/// past it.
pub fn step_toward(
  from from: Position,
  to to: Position,
  metres metres: Float,
) -> Position {
  let remaining_squared = distance_squared(a: from, b: to)
  case remaining_squared <=. metres *. metres {
    True -> to
    False -> {
      let assert Ok(remaining) = float.square_root(remaining_squared)
        as "a squared distance is not negative"
      let fraction = metres /. remaining
      Position(
        x: from.x +. { to.x -. from.x } *. fraction,
        y: from.y +. { to.y -. from.y } *. fraction,
      )
    }
  }
}

/// Whether two positions are at most `range` metres apart. A position exactly
/// `range` away is within range.
pub fn within(a a: Position, b b: Position, range range: Float) -> Bool {
  distance_squared(a:, b:) <=. range *. range
}
