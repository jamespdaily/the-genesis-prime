//// This module contains the code to run the sql queries defined in
//// `./dev/genesis_prime/import_world_data/sql`.
//// > 🐿️ This module was generated automatically using v4.7.0 of
//// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
////

import gleam/dynamic/decode
import gleam/option.{type Option}
import pog

/// A row you get from running the `delete_removed_spawns` query
/// defined in `./dev/genesis_prime/import_world_data/sql/delete_removed_spawns.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type DeleteRemovedSpawnsRow {
  DeleteRemovedSpawnsRow(removed: Int)
}

/// Deletes the world-database spawns whose row id is no longer in the file (`$1`
/// is every row id of the file), with their stats, and leaves every row of any
/// other source alone. Gives how many were deleted.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn delete_removed_spawns(
  db: pog.Connection,
  arg_1: List(Int),
) -> Result(pog.Returned(DeleteRemovedSpawnsRow), pog.QueryError) {
  let decoder = {
    use removed <- decode.field(0, decode.int)
    decode.success(DeleteRemovedSpawnsRow(removed:))
  }

  "-- Deletes the world-database spawns whose row id is no longer in the file (`$1`
-- is every row id of the file), with their stats, and leaves every row of any
-- other source alone. Gives how many were deleted.
with removed as (
  delete from spawn
  where source = 'world_database'
    and source_row <> all($1::int[])
  returning 1
)
select count(*)::int as removed from removed;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// Records that a file of the world database was imported: its name, the SHA-256
/// of its bytes and its row count, and when. An import of the same file again
/// replaces the record.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn record_import(
  db: pog.Connection,
  arg_1: String,
  arg_2: String,
  arg_3: Int,
) -> Result(pog.Returned(Nil), pog.QueryError) {
  let decoder = decode.map(decode.dynamic, fn(_) { Nil })

  "-- Records that a file of the world database was imported: its name, the SHA-256
-- of its bytes and its row count, and when. An import of the same file again
-- replaces the record.
insert into content_import (file, sha256, rows, imported_at)
values ($1, $2, $3, now())
on conflict (file) do update set
  sha256 = excluded.sha256,
  rows = excluded.rows,
  imported_at = excluded.imported_at;
"
  |> pog.query
  |> pog.parameter(pog.text(arg_1))
  |> pog.parameter(pog.text(arg_2))
  |> pog.parameter(pog.int(arg_3))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `source_row_of_spawn` query
/// defined in `./dev/genesis_prime/import_world_data/sql/source_row_of_spawn.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type SourceRowOfSpawnRow {
  SourceRowOfSpawnRow(source_row: Option(Int))
}

/// The row id in the file of a spawn, by the spawn's own id: a refused stat names
/// its spawn by that id, and the importer reports the row of the file.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn source_row_of_spawn(
  db: pog.Connection,
  arg_1: Int,
) -> Result(pog.Returned(SourceRowOfSpawnRow), pog.QueryError) {
  let decoder = {
    use source_row <- decode.field(0, decode.optional(decode.int))
    decode.success(SourceRowOfSpawnRow(source_row:))
  }

  "-- The row id in the file of a spawn, by the spawn's own id: a refused stat names
-- its spawn by that id, and the importer reports the row of the file.
select source_row
from spawn
where id = $1;
"
  |> pog.query
  |> pog.parameter(pog.int(arg_1))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `upsert_spawn_stats` query
/// defined in `./dev/genesis_prime/import_world_data/sql/upsert_spawn_stats.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UpsertSpawnStatsRow {
  UpsertSpawnStatsRow(written: Int, deleted: Int)
}

/// Makes the stats of one batch of spawn rows the file's: the stat triples (the
/// row id in the file, the stat index and its value) are written, a stat a row
/// had that the file no longer gives is deleted, and a stat that is the same is
/// left alone. `$4` is the row ids of the whole batch, so a row with no stats in
/// the file loses the stats it had. Gives how many stats were written (inserted
/// or changed) and how many were deleted.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn upsert_spawn_stats(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Float),
  arg_4: List(Int),
) -> Result(pog.Returned(UpsertSpawnStatsRow), pog.QueryError) {
  let decoder = {
    use written <- decode.field(0, decode.int)
    use deleted <- decode.field(1, decode.int)
    decode.success(UpsertSpawnStatsRow(written:, deleted:))
  }

  "-- Makes the stats of one batch of spawn rows the file's: the stat triples (the
-- row id in the file, the stat index and its value) are written, a stat a row
-- had that the file no longer gives is deleted, and a stat that is the same is
-- left alone. `$4` is the row ids of the whole batch, so a row with no stats in
-- the file loses the stats it had. Gives how many stats were written (inserted
-- or changed) and how many were deleted.
with incoming as (
  select *
  from unnest($1::int[], $2::smallint[], $3::real[])
    as t (source_row, stat, value)
),
mapped as (
  select spawn.id as spawn_id, incoming.stat, incoming.value
  from incoming
  join spawn on spawn.source_row = incoming.source_row
),
deleted as (
  delete from spawn_stat
  using spawn
  where spawn_stat.spawn_id = spawn.id
    and spawn.source_row = any($4::int[])
    and not exists (
      select 1 from mapped
      where mapped.spawn_id = spawn_stat.spawn_id
        and mapped.stat = spawn_stat.stat
    )
  returning 1
),
written as (
  insert into spawn_stat (spawn_id, stat, value)
  select spawn_id, stat, value from mapped
  on conflict (spawn_id, stat) do update set value = excluded.value
  where spawn_stat.value is distinct from excluded.value
  returning 1
)
select
  (select count(*) from written)::int as written,
  (select count(*) from deleted)::int as deleted;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.float(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.returning(decoder)
  |> pog.execute(db)
}

/// A row you get from running the `upsert_spawns` query
/// defined in `./dev/genesis_prime/import_world_data/sql/upsert_spawns.sql`.
///
/// > 🐿️ This type definition was generated automatically using v4.7.0 of the
/// > [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub type UpsertSpawnsRow {
  UpsertSpawnsRow(inserted: Int, changed: Int)
}

/// Writes one batch of the world database's spawn rows (one array for each
/// column, in the order of the rows) as `world_database` rows keyed by their row id
/// in the file: a row not in the table is inserted, a row whose values differ is
/// updated and keeps its id, and a row that is the same is left alone. Gives how
/// many were inserted and how many changed. A row the schema refuses fails the
/// statement, naming the constraint.
///
/// > 🐿️ This function was generated automatically using v4.7.0 of
/// > the [squirrel package](https://github.com/giacomocavalieri/squirrel).
///
pub fn upsert_spawns(
  db: pog.Connection,
  arg_1: List(Int),
  arg_2: List(Int),
  arg_3: List(Int),
  arg_4: List(Int),
  arg_5: List(Int),
  arg_6: List(Float),
  arg_7: List(Float),
  arg_8: List(Float),
  arg_9: List(Float),
  arg_10: List(Float),
  arg_11: List(Float),
  arg_12: List(Int),
  arg_13: List(Int),
  arg_14: List(Int),
  arg_15: List(Int),
  arg_16: List(Int),
  arg_17: List(Int),
  arg_18: List(Int),
) -> Result(pog.Returned(UpsertSpawnsRow), pog.QueryError) {
  let decoder = {
    use inserted <- decode.field(0, decode.int)
    use changed <- decode.field(1, decode.int)
    decode.success(UpsertSpawnsRow(inserted:, changed:))
  }

  "-- Writes one batch of the world database's spawn rows (one array for each
-- column, in the order of the rows) as `world_database` rows keyed by their row id
-- in the file: a row not in the table is inserted, a row whose values differ is
-- updated and keeps its id, and a row that is the same is left alone. Gives how
-- many were inserted and how many changed. A row the schema refuses fails the
-- statement, naming the constraint.
with incoming as (
  select *
  from unnest(
    $1::int[], $2::smallint[], $3::int[], $4::int[], $5::int[],
    $6::real[], $7::real[], $8::real[], $9::real[], $10::real[], $11::real[],
    $12::int[], $13::int[], $14::int[], $15::int[], $16::int[], $17::bigint[],
    $18::int[]
  ) as t (
    source_row, entity_type, creature_id, world_id, area_id,
    x, y, z, rotation_x, rotation_y, rotation_z,
    display_info_id, outfit_info_id, faction_id, base_faction_id,
    quest_checklist_index, active_prop_id, world_socket_id
  )
),
written as (
  insert into spawn (
    source, source_row, entity_type, creature_id, world_id, area_id,
    x, y, z, rotation_x, rotation_y, rotation_z,
    display_info_id, outfit_info_id, faction_id, base_faction_id,
    quest_checklist_index, active_prop_id, world_socket_id
  )
  select
    'world_database', source_row, entity_type, creature_id, world_id, area_id,
    x, y, z, rotation_x, rotation_y, rotation_z,
    display_info_id, outfit_info_id, faction_id, base_faction_id,
    quest_checklist_index, active_prop_id, world_socket_id
  from incoming
  on conflict (source, source_row) do update set
    entity_type = excluded.entity_type,
    creature_id = excluded.creature_id,
    world_id = excluded.world_id,
    area_id = excluded.area_id,
    x = excluded.x,
    y = excluded.y,
    z = excluded.z,
    rotation_x = excluded.rotation_x,
    rotation_y = excluded.rotation_y,
    rotation_z = excluded.rotation_z,
    display_info_id = excluded.display_info_id,
    outfit_info_id = excluded.outfit_info_id,
    faction_id = excluded.faction_id,
    base_faction_id = excluded.base_faction_id,
    quest_checklist_index = excluded.quest_checklist_index,
    active_prop_id = excluded.active_prop_id,
    world_socket_id = excluded.world_socket_id
  where (
    spawn.entity_type, spawn.creature_id, spawn.world_id, spawn.area_id,
    spawn.x, spawn.y, spawn.z, spawn.rotation_x, spawn.rotation_y,
    spawn.rotation_z, spawn.display_info_id, spawn.outfit_info_id,
    spawn.faction_id, spawn.base_faction_id, spawn.quest_checklist_index,
    spawn.active_prop_id, spawn.world_socket_id
  ) is distinct from (
    excluded.entity_type, excluded.creature_id, excluded.world_id,
    excluded.area_id, excluded.x, excluded.y, excluded.z, excluded.rotation_x,
    excluded.rotation_y, excluded.rotation_z, excluded.display_info_id,
    excluded.outfit_info_id, excluded.faction_id, excluded.base_faction_id,
    excluded.quest_checklist_index, excluded.active_prop_id,
    excluded.world_socket_id
  )
  returning (xmax = 0) as inserted
)
select
  (count(*) filter (where inserted))::int as inserted,
  (count(*) filter (where not inserted))::int as changed
from written;
"
  |> pog.query
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_1))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_2))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_3))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_4))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_5))
  |> pog.parameter(pog.array(fn(value) { pog.float(value) }, arg_6))
  |> pog.parameter(pog.array(fn(value) { pog.float(value) }, arg_7))
  |> pog.parameter(pog.array(fn(value) { pog.float(value) }, arg_8))
  |> pog.parameter(pog.array(fn(value) { pog.float(value) }, arg_9))
  |> pog.parameter(pog.array(fn(value) { pog.float(value) }, arg_10))
  |> pog.parameter(pog.array(fn(value) { pog.float(value) }, arg_11))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_12))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_13))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_14))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_15))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_16))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_17))
  |> pog.parameter(pog.array(fn(value) { pog.int(value) }, arg_18))
  |> pog.returning(decoder)
  |> pog.execute(db)
}
