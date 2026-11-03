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
////   place already holds: a package such as `vec` brings a dependency and a
////   type conversion for three subtractions.

import genesis_prime/game/start_place.{type Place}

/// How far apart two players may stand and still see each other, in units: the
/// client's largest draw distance (unit.range).
const range = 1024.0

/// Whether the two places are within `range` of each other, inclusive:
/// exactly 1024.0 apart sees, 1024.01 does not.
pub fn sees(first first: Place, second second: Place) -> Bool {
  let dx = start_place.x(first) -. start_place.x(second)
  let dy = start_place.y(first) -. start_place.y(second)
  let dz = start_place.z(first) -. start_place.z(second)
  dx *. dx +. dy *. dy +. dz *. dz <=. range *. range
}
