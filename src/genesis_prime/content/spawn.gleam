//// The spawn table as the server reads it at start: one query for every row, the
//// rows handed to the pure selection (genesis_prime/world_map/spawn), and the
//// spawns that start put into one persistent term for each world, under the
//// load's key (genesis_prime/content/term).
////
//// ```
//// content.load ─▶ rows(db) ─▶ spawn.select(rows, tables) ─▶ put(key, selection)
//// a map's start ─▶ world(key, its world id) ─▶ WorldSpawns: no copy, no query
//// the same load  ─▶ spawn.summon_checks(tables, formulas, kinds) ─▶ put_summon_checks(key, checks)
//// a map's start, a creature's start ─▶ summon_checks(key): what a run-only spawn is checked with
//// the same load  ─▶ selection.visibility ─▶ put (with the worlds)
//// the connection's settings ─▶ visibility(key): each world's visibility prerequisites, loaded
//// ```
////
//// - **The term** of a world is `WorldSpawns(by_id, objects, cells)`, put once for every
////   row of the client's World table, empty for a world with no spawn that
////   starts.
//// - **The summon checks** are one term (id 0 of table `spawn_summon_checks`),
////   put with the worlds' terms, so a map answers a development summon and a
////   creature's start builds the same run-only spawn from them, with no table
////   read during play.
//// - **The visibility prerequisites** are one term (id 0 of table `spawn_visibility`),
////   put with the worlds' terms: for each world with any, the loaded prerequisites
////   its started spawns and sent objects hide behind, so the connection works out
////   what a player sees with no table read during play.
//// - **The query** is `sql/load_spawns.sql`, run by the load's own pool before
////   the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/world_map/spawn.{
  type Row, type Selection, type SummonChecks, type WorldSpawns, Row,
}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict.{type Dict}
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
        world_object_id: row.active_prop_id,
        world_socket_id: row.world_socket_id,
        health: row.health,
        level: row.level,
      )
    })
  })
}

/// The table name of the visibility prerequisites in a term.
const visibility_table = "spawn_visibility"

/// Writes each world's spawns of the selection under the key, once, and the
/// visibility prerequisites of the worlds.
pub fn put(key key: Key, selection selection: Selection) -> Nil {
  dict.each(selection.worlds, fn(world_id, spawns) {
    put_world(key:, world_id:, spawns:)
  })
  put_visibility(key:, visibility: selection.visibility)
}

/// Writes the visibility prerequisites of the worlds under the key, once: a world
/// with none has no entry.
pub fn put_visibility(
  key key: Key,
  visibility visibility: Dict(Int, List(Prerequisite)),
) -> Nil {
  store.put_content(key:, table: visibility_table, id: 0, value: visibility)
}

/// The visibility prerequisites of each world as the load put them under the key:
/// a world with none has no entry. The load puts the term before the tree starts,
/// so a reader that finds none is a bug and crashes.
pub fn visibility(key key: Key) -> Dict(Int, List(Prerequisite)) {
  store.content(key:, table: visibility_table, id: 0)
}

/// Writes one world's spawns under the key, once.
pub fn put_world(
  key key: Key,
  world_id world_id: Int,
  spawns spawns: WorldSpawns,
) -> Nil {
  store.put_content(key:, table:, id: world_id, value: spawns)
}

/// The spawns that start in the world, as the load put them under the key. The
/// load puts a term for every row of the client's World table, empty for a world
/// with no spawn, so a world with no term is a bug and crashes the reader.
pub fn world(key key: Key, world_id world_id: Int) -> WorldSpawns {
  store.content(key:, table:, id: world_id)
}

/// The table name of the summon checks in a term.
const summon_checks_table = "spawn_summon_checks"

/// Writes the summon checks under the key, once.
pub fn put_summon_checks(key key: Key, checks checks: SummonChecks) -> Nil {
  store.put_content(key:, table: summon_checks_table, id: 0, value: checks)
}

/// The summon checks the load put under the key. The load puts the term before
/// the tree starts, so a reader that finds none is a bug and crashes.
pub fn summon_checks(key key: Key) -> SummonChecks {
  store.content(key:, table: summon_checks_table, id: 0)
}
