//// Which two players in a map see each other: the distance between their
//// places is at most `range` units, in three dimensions. The map applies it to
//// every pair when a player joins or moves (genesis_prime/world_map/map).
////
//// - **The range, 1024 units,** is the client's largest draw distance
////   (lod.viewDistance, 256 to 1024, default 640): the client removes no unit by
////   distance (unit.range), so the server sends every player the client could
////   draw, whatever its setting, and a player past the range is one no client
////   draws as a nameplate or model of its own.
//// - **One threshold, no margin:** at the range a unit is at or past every
////   client's draw distance, so a crossing is not seen as flicker. A server
////   choice.
//// - **The distance helper is our own,** a squared distance on the x, y and z a
////   place already holds, compared with the squared range. The manifest's
////   `gleam_community_maths.euclidean_distance` takes the two points as a list of
////   coordinate pairs and gives a `Result` of the root through
////   `minkowski_distance`'s float power, so each pair of players would build a
////   list, take a root and unwrap a result for a comparison that three
////   subtractions answer; a package such as `vec` adds a dependency and a type
////   conversion for the same three subtractions.

import genesis_prime/game/start_place.{type Place}

/// How far apart two players may stand and still see each other, in units: the
/// client's largest draw distance (unit.range).
pub const range = 1024.0

/// Whether the two places are within `range` of each other, inclusive:
/// exactly 1024.0 apart sees, 1024.01 does not.
pub fn sees(first first: Place, second second: Place) -> Bool {
  squared_distance(first:, second:) <=. range *. range
}

/// The square of the distance between two places, in three dimensions: compared
/// with a squared range, it needs no root.
pub fn squared_distance(first first: Place, second second: Place) -> Float {
  let dx = start_place.x(first) -. start_place.x(second)
  let dy = start_place.y(first) -. start_place.y(second)
  let dz = start_place.z(first) -. start_place.z(second)
  dx *. dx +. dy *. dy +. dz *. dz
}
