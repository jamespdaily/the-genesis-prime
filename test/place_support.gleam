//// A place for a test to put a character at, in a world of the test's naming.

import genesis_prime/game/start_place.{type Place}

/// The hit radius of a player: the Race row's hitRadius, 1.2 for the eight player races
/// as the table's 32-bit float reads (genesis_prime/game/hit_radius).
pub const player_hit_radius = 1.2000000476837158

/// Where the live character of the client's 0x262 vector stands, in World 3460
/// (vector.opcode.0x262.roxo_alive): the place a test puts a unit at.
pub fn live_character_place() -> Place {
  at(world_id: 3460, world_zone_id: 6009, x: 4605.65, y: -7.571, z: 494.996)
}

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
