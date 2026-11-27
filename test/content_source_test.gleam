//// What a content table keeps beside a row's values: its `source` and nothing that says
//// why. A content table is each table with a `source` column and a
//// `<table>_source_is_a_content_source` constraint (migration 0008 and its siblings), found
//// from the schema. Expected values come from these places.
//// - Migration 0053 drops the `reason` column of the 17 tables that held one; a table
////   constraint on a dropped column goes with it (the Postgres documentation, ALTER TABLE
////   DROP COLUMN), so the 34 checks on `reason` are gone too.
//// - The schema (`information_schema.columns`, `pg_constraint`) is the second source for
////   the set of tables: no literal list of them is kept here.
//// - Each table's own insert is the valid row of its refusal test: the keys the table's
////   other checks and its name tables allow (`game_number_name` lists the names a number
////   may take).

import content_support
import database_support
import gleam/list
import gleam/string
import owned_test

/// The content tables found from the schema: each table with a `source` column and a
/// constraint named `<table>_source_is_a_content_source`.
const content_tables =
  "select c.table_name from information_schema.columns c where c.table_schema = 'public' and c.column_name = 'source' and exists (select 1 from pg_constraint k where k.conrelid = format('public.%I', c.table_name)::regclass and k.conname = c.table_name || '_source_is_a_content_source') order by 1"

pub fn the_migrations_leave_no_reason_column_on_a_content_table_test() -> Nil {
  use <- owned_test.run(10_000)
  let database = database_support.new_database(on: database_support.shared())
  let tables =
    content_support.psql(database:, sql: content_tables)
    |> string.split("\n")
  assert list.length(tables) >= 17
    as "the schema's content tables were found: migrations 0008 to 0047 give 17 tables a source constraint"
  assert content_support.count(
      database:,
      sql: "select count(*) from information_schema.columns where table_schema = 'public' and column_name = 'reason' and table_name in ("
        <> content_tables
        <> ")",
    )
    == 0
    as "no content table has a reason column"
  assert content_support.count(
      database:,
      sql: "select count(*) from pg_constraint where conrelid in (select format('public.%I', table_name)::regclass from ("
        <> content_tables
        <> ") as t (table_name)) and (conname like '%reason%' or pg_get_constraintdef(oid) like '%reason%')",
    )
    == 0
    as "no check on a content table is named for a reason or reads one"
}

/// A content table's name, an insert of a row whose only text beside its values is its
/// source.
type Row {
  Row(table: String, insert: String)
}

pub fn a_server_choice_row_is_stored_with_only_its_source_test() -> Nil {
  use <- owned_test.run(10_000)
  let database = database_support.new_database(on: database_support.shared())
  let rows = [
    Row(
      "arrival_objective",
      "insert into arrival_objective (objective_id, source) values (1, 'server_choice')",
    ),
    Row(
      "class_resource",
      "insert into class_resource (class_id, name, value, unit, source) values (6, 'max', 1, 'points', 'server_choice')",
    ),
    Row(
      "click_objective",
      "insert into click_objective (objective_id, source) values (1, 'server_choice')",
    ),
    Row(
      "kill_objective",
      "insert into kill_objective (objective_id, source) values (1, 'server_choice')",
    ),
    Row(
      "held_objective",
      "insert into held_objective (objective_id, kind, source) values (1, 'instance_run', 'server_choice')",
    ),
    Row(
      "creature_faction",
      "insert into creature_faction (creature_id, faction_id, source) values (73464, 233, 'server_choice')",
    ),
    Row(
      "creature_kind",
      "insert into creature_kind (creature_id, respawn_ms, attack_spell4_id, attack_interval_ms, source) values (73464, 5000, 5649, 1500, 'server_choice')",
    ),
    Row(
      "game_number",
      "insert into game_number_name (name, unit) values ('evade_range', 'units'); insert into game_number (name, value, unit, source) values ('evade_range', 30, 'units', 'server_choice')",
    ),
    Row(
      "server_proxy",
      "insert into server_proxy (spell4_base_id, phase, spell4_id, source) values (1, 0, 2, 'server_choice')",
    ),
    Row(
      "vendor",
      "insert into vendor (creature_id, source) values (200001, 'server_choice')",
    ),
    Row(
      "vendor_item",
      "insert into vendor_item (creature_id, position, item_id, source) values (200001, 1, 5, 'server_choice')",
    ),
    Row(
      "projector_landing",
      "insert into projector_landing (creature_id, faction_enum, objective_id, world_location2_id, source) values (1, 1, 1, 1, 'server_choice')",
    ),
    Row(
      "tutorial_quest",
      "insert into tutorial_quest (quest_id, follows_quest_id, source) values (1, null, 'server_choice')",
    ),
    Row(
      "zone_welcome",
      "insert into zone_welcome (world_zone_id, tutorial_id, source) values (1, 1, 'server_choice')",
    ),
    Row(
      "spawn",
      "insert into spawn (source, entity_type, creature_id, world_id, area_id, x, y, z, rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id, faction_id, base_faction_id, active_prop_id, world_socket_id) values ('server_choice', 0, 73464, 3460, 0, 0, 0, 0, 0, 0, 0, 26565, 0, 1441, 0, 0, 0)",
    ),
    Row(
      "creature_auto_attack",
      "insert into creature_auto_attack (creature_id, spell4_id, order_index, source) values (1, 2, 0, 'retail_record')",
    ),
    Row(
      "creature_special",
      "insert into creature_special (creature_id, spell4_id, order_index, cooldown_ms, source) values (1, 2, 0, 10000, 'retail_record')",
    ),
  ]
  assert list.sort(list.map(rows, fn(row) { row.table }), string.compare)
    == string.split(content_support.psql(database:, sql: content_tables), "\n")
    as "a row is listed for each content table the schema holds"
  list.each(rows, fn(row) {
    let before =
      content_support.count(
        database:,
        sql: "select count(*) from " <> row.table,
      )
    content_support.change(database:, sql: row.insert)
    assert content_support.count(
        database:,
        sql: "select count(*) from " <> row.table,
      )
      == before + 1
      as {
        row.table <> ": the row is stored with its source and no other text"
      }
  })
}
