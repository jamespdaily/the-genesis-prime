//// Spawns for a test to stand a creature at, in World 3460, Warfare Woods, and
//// the `WorldSpawns` a world's term holds them in. The values are the client's
//// for Creature2 73464, the Virtual Battle Beast (the creature trace of the
//// combat core: level 1, faction 1441, display 26565, Base Health 52.6205
//// truncated to 52), so a test of the rule reads what the real spawn would carry
//// without the client's tables.

import genesis_prime/game/start_place
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/spawn.{
  type Row, type Spawn, type WorldSpawns, Row, Spawn,
}
import genesis_prime/world_map/spawn_cell
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/list
import gleam/option
import place_support

/// Warfare Woods, WorldZone 5967 (Quest2.10518).
pub const warfare_woods = 5967

/// The spawn numbered `number` of a Virtual Battle Beast, `x` units along the
/// world's x axis.
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
    level: 1,
    health: 52,
    faction_id: 1441,
    base_faction_id: 1441,
    display_info_id: 26_565,
    outfit_info_id: 0,
  )
}

/// The spawns as a world's term holds them: by id and by cell.
pub fn world_spawns(spawns spawns: List(Spawn)) -> WorldSpawns {
  spawn.WorldSpawns(
    by_id: dict.from_list(list.map(spawns, fn(spawn) { #(spawn.id, spawn) })),
    cells: spawn_cell.index(
      list.map(spawns, fn(spawn) {
        #(spawn.id, start_place.x(spawn.place), start_place.z(spawn.place))
      }),
    ),
  )
}

/// A row of the spawn table for a Virtual Battle Beast with no stats, standing
/// in World 3460 at the origin: a test changes the fields it is about with
/// record update.
pub fn beast_row(number number: Int) -> Row {
  Row(
    id: SpawnId(number),
    entity_type: 0,
    creature_id: 73_464,
    world_id: 3460,
    area_id: 0,
    x: 0.0,
    y: 0.0,
    z: 0.0,
    rotation_x: 0.0,
    rotation_y: 0.0,
    rotation_z: 0.0,
    display_info_id: 26_565,
    outfit_info_id: 0,
    faction_id: 1441,
    base_faction_id: 1441,
    health: option.None,
    level: option.None,
  )
}
