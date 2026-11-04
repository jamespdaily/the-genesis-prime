//// A spawn for a test to stand a creature at, in World 3460, Warfare Woods.
//// Its values are the client's for Creature2 73464, the Virtual Battle Beast
//// (the creature trace of the combat core: level 1, faction 1441, display
//// 26565, Base Health 52.6205 truncated to 52), so a test of the rule reads
//// what the real spawn would carry without the client's tables.

import genesis_prime/table/id.{Creature2Id, WorldLocation2Id}
import genesis_prime/world_map/spawn.{type Spawn, Spawn, WorldDatabase}
import genesis_prime/world_map/spawn_id.{SpawnId}
import place_support

/// Warfare Woods, WorldZone 5967 (Quest2.10518).
pub const warfare_woods = 5967

/// The spawn numbered `number` of a Virtual Battle Beast, `x` units along the
/// world's x axis, standing in the client's objective circle (WorldLocation2
/// 51739) as the world-database row 29112 + `number` would.
pub fn battle_beast(number number: Int, x x: Float) -> Spawn {
  Spawn(
    id: SpawnId(number),
    creature_id: Creature2Id(73_464),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: warfare_woods,
      x:,
      y: 0.0,
      z: 0.0,
    ),
    area: WorldLocation2Id(51_739),
    source: WorldDatabase(row_id: 29_112 + number),
    level: 1,
    health: 52,
    faction_id: 1441,
    display_info_id: 26_565,
  )
}
