//// A place in a world: the three numbers of a position the client's messages
//// carry (the first three floats of message 0xAD and of a character of message
//// 0x117), in metres. No client record says which of them is the height, so
//// distances use all three.

/// A place in a world.
pub type Position {
  Position(x: Float, y: Float, z: Float)
}

/// The square of the distance between two positions, in square metres. Range
/// checks compare squares, so no square root is taken.
pub fn distance_squared(a a: Position, b b: Position) -> Float {
  let dx = a.x -. b.x
  let dy = a.y -. b.y
  let dz = a.z -. b.z
  dx *. dx +. dy *. dy +. dz *. dz
}

/// Whether two positions are at most `range` metres apart. A position exactly
/// `range` away is within range.
pub fn within(a a: Position, b b: Position, range range: Float) -> Bool {
  distance_squared(a:, b:) <=. range *. range
}
