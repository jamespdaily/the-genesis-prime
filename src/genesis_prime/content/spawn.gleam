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
//// the same load  ─▶ counts(rows) ─▶ objective_units.reused ─▶ put_reused_unit_objectives(key)
//// the connection's settings ─▶ reused_unit_objectives(key): the objectives whose unit counts again
//// the same load  ─▶ stored(rows) ─▶ put_stored_spawns(key)
//// the connection's settings ─▶ stored_spawns(key): the stored spawns, which a saved quest's used objects are kept against
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
//// - **The reused unit objectives** are one term (id 0 of table `spawn_reused_unit_objectives`),
////   put with the worlds' terms: the objectives, of every type that counts a use of a unit
////   or a cast at one, whose creatures have fewer spawn rows than the objective's count
////   (genesis_prime/game/objective_units `reused`), so the connection counts each other
////   objective's unit once with no table read during play.
//// - **The query** is `sql/load_spawns.sql`, run by the load's own pool before
////   the tree starts; nothing queries the table during play.

import genesis_prime/content/sql
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/table/loader/store.{type Key}
import genesis_prime/world_map/spawn.{
  type Row, type Selection, type SummonChecks, type WorldSpawns, Row,
}
import genesis_prime/world_map/spawn_id.{type StoredSpawns, SpawnId}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/result
import gleam/set.{type Set}
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

/// The number of spawn rows of each Creature2 id, in every world: a creature with no row
/// has no entry.
pub fn counts(rows rows: List(Row)) -> Dict(Int, Int) {
  list.fold(rows, dict.new(), fn(counts, row) {
    dict.upsert(counts, row.creature_id, fn(counted) {
      option.unwrap(counted, 0) + 1
    })
  })
}

/// The table name of the reused unit objectives in a term.
const reused_unit_objectives_table = "spawn_reused_unit_objectives"

/// Writes the QuestObjective ids of the objectives whose unit counts again
/// (`objective_units.reused`) under the key, once.
pub fn put_reused_unit_objectives(
  key key: Key,
  objectives objectives: Set(Int),
) -> Nil {
  store.put_content(
    key:,
    table: reused_unit_objectives_table,
    id: 0,
    value: objectives,
  )
}

/// The reused unit objectives the load put under the key. The load puts the term before
/// the tree starts, so a reader that finds none is a bug and crashes.
pub fn reused_unit_objectives(key key: Key) -> Set(Int) {
  store.content(key:, table: reused_unit_objectives_table, id: 0)
}

/// The table name of the stored spawns in a term.
const stored_spawns_table = "stored_spawns"

/// The stored spawn rows, of every world, whether or not a row starts. A row the server
/// places for an objective that no stored row serves is not among them: its id is above the
/// highest stored one and the map's alone (genesis_prime/world_map/objective_spawn).
pub fn stored(rows rows: List(Row)) -> StoredSpawns {
  spawn_id.stored(ids: set.from_list(list.map(rows, fn(row) { row.id })))
}

/// Writes the stored spawns under the key, once.
pub fn put_stored_spawns(key key: Key, stored stored: StoredSpawns) -> Nil {
  store.put_content(key:, table: stored_spawns_table, id: 0, value: stored)
}

/// The stored spawns the load put under the key: what a saved quest's used objects are
/// checked against (genesis_prime/game/quest_log `without_lost_spawns`). The load puts the
/// term before the tree starts, so a reader that finds none is a bug and crashes.
pub fn stored_spawns(key key: Key) -> StoredSpawns {
  store.content(key:, table: stored_spawns_table, id: 0)
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
