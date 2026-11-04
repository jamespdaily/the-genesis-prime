//// Spawns for a test to stand a creature at, in World 3460, Warfare Woods, and
//// the `WorldSpawns` a world's term holds them in. The values are the client's
//// for Creature2 73464, the Virtual Battle Beast (the creature trace of the
//// combat core: level 1, faction 1441, display 26565, Base Health 52.6205
//// truncated to 52), so a test of the rule reads what the real spawn would carry
//// without the client's tables.

import database_support
import genesis_prime/content/spawn as content_spawn
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/spawn.{type Row, type Spawn, Row, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/list
import gleam/option
import owned_key
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

/// The worlds the tests' maps may run in: every World row a test uses.
const worlds = [22, 51, 426, 870, 990, 1061, 1387, 3460, 3461, 6009]

/// A key whose terms hold these spawns for World 3460 and no spawn for every
/// other world a test's map may run in, as the content load leaves them. It is
/// the test's own, erased when the body ends: a test with no spawns takes
/// `key_without_spawns` and puts nothing.
pub fn key_with(spawns spawns: List(Spawn)) -> table_store.Key {
  let key = owned_key.new_fixture_key()
  put_worlds(key:, spawns:)
  key
}

/// The key every test with no spawns shares: the terms are put once per run and
/// never erased, as the content load leaves them for a database with no spawn.
pub fn key_without_spawns() -> table_store.Key {
  database_support.once("spawn_support_key_without_spawns", fn() {
    let key = owned_key.new_shared_key()
    put_worlds(key:, spawns: [])
    key
  })
}

fn put_worlds(key key: table_store.Key, spawns spawns: List(Spawn)) -> Nil {
  list.each(worlds, fn(world_id) {
    content_spawn.put_world(key:, world_id:, spawns: case world_id {
      3460 -> spawn.world_spawns(spawns:)
      _ -> spawn.no_spawns()
    })
  })
}
