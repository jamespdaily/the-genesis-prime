//// The spawn table as the server reads it at start: one query for every row, the
//// rows handed to the pure selection (genesis_prime/world_map/spawn), and the
//// spawns that start put into one persistent term for each world, under the
//// load's key (genesis_prime/content/term).
////
//// ```
//// content.load ─▶ rows(db) ─▶ spawn.select(rows, tables) ─▶ put(key, selection)
//// a map's start ─▶ world(key, its world id) ─▶ WorldSpawns: no copy, no query
//// ```
////
//// - **The term** of a world is `WorldSpawns(by_id, cells)`, put once for every
////   row of the client's World table, empty for a world with no spawn that
////   starts.
//// - **The query** is `sql/load_spawns.sql`, run by the load's own pool before
////   the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/content/term
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/world_map/spawn.{
  type Row, type Selection, type WorldSpawns, Row,
}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/list
import gleam/result
import pog

/// The table's name in the log and in a term.
pub const table = "spawn"

/// Every row of the spawn table, in world and id order, or why the query failed.
pub fn rows(db db: pog.Connection) -> Result(List(Row), pog.QueryError) {
  sql.load_spawns(db)
  |> result.map(fn(returned) {
    list.map(returned.rows, fn(row) {
      Row(
        id: SpawnId(row.id),
        entity_type: row.entity_type,
        creature_id: row.creature_id,
        world_id: row.world_id,
        area_id: row.area_id,
        x: row.x,
        y: row.y,
        z: row.z,
        rotation_x: row.rotation_x,
        rotation_y: row.rotation_y,
        rotation_z: row.rotation_z,
        display_info_id: row.display_info_id,
        outfit_info_id: row.outfit_info_id,
        faction_id: row.faction_id,
        base_faction_id: row.base_faction_id,
        health: row.health,
        level: row.level,
      )
    })
  })
}

/// Writes each world's spawns of the selection under the key, once.
pub fn put(key key: Key, selection selection: Selection) -> Nil {
  dict.each(selection.worlds, fn(world_id, spawns) {
    put_world(key:, world_id:, spawns:)
  })
}

/// Writes one world's spawns under the key, once.
pub fn put_world(
  key key: Key,
  world_id world_id: Int,
  spawns spawns: WorldSpawns,
) -> Nil {
  term.put(key:, table:, id: world_id, value: spawns)
}

/// The spawns that start in the world, as the load put them under the key. The
/// load puts a term for every row of the client's World table, empty for a world
/// with no spawn, so a world with no term is a bug and crashes the reader.
pub fn world(key key: Key, world_id world_id: Int) -> WorldSpawns {
  term.get(key:, table:, id: world_id)
}
