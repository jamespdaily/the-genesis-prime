//// A place for a test to put a character at, in a world of the test's naming.

import genesis_prime/game/start_place.{type Place}

/// The place in the World row `world_id`, with the zone and the position,
/// facing as a character that has never turned does, for a test whose world is
/// not 0 (`start_place.place` refuses world 0).
pub fn at(
  world_id world_id: Int,
  world_zone_id world_zone_id: Int,
  x x: Float,
  y y: Float,
  z z: Float,
) -> Place {
  let assert Ok(place) =
    start_place.place(
      world_id:,
      world_zone_id:,
      x:,
      y:,
      z:,
      facing: start_place.unturned,
    )
    as "the test's world is not 0"
  place
}
