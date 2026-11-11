//// The spawn table's schema (migration 0008): each constraint refuses its own
//// bad row, under its own name. Expected values come from these places.
//// - Message 0x262 (`opcode.0x262`, `world_data.entity_type`): a unit type is 6
////   bits and 37 and above fail the client's read; a faction and a base faction
////   are 14 bits; a stat index is 5 bits; a position and a rotation are 32-bit
////   floats the client places the unit by, so NaN and the infinities are refused
////   (as migration 0007 refuses them for a character's place).
//// - The design of the world spawns (the Design artifact of issue 375, section
////   0): a row of the world database names its row in the file and any other row
////   states its reason, which says something; a source row is in the table once;
////   an import's file hash is 64 lower-case hex characters and its rows count is
////   not negative.
//// Each test runs on a database of its own, copied from the migrated template.

import database_support
import gleam/dict
import gleam/list
import gleam/string
import owned_test

/// The columns of a world-database row of a Virtual Battle Beast that satisfies
/// every constraint.
fn good_row() -> dict.Dict(String, String) {
  dict.from_list([
    #("source", "'world_database'"),
    #("source_row", "1"),
    #("reason", "null"),
    #("entity_type", "0"),
    #("creature_id", "73464"),
    #("world_id", "3460"),
    #("area_id", "0"),
    #("x", "0"),
    #("y", "0"),
    #("z", "0"),
    #("rotation_x", "0"),
    #("rotation_y", "0"),
    #("rotation_z", "0"),
    #("display_info_id", "26565"),
    #("outfit_info_id", "0"),
    #("faction_id", "1441"),
    #("base_faction_id", "1441"),
    #("active_prop_id", "0"),
    #("world_socket_id", "0"),
  ])
}

/// The insert of a good row with these columns changed.
fn insert_with(changes: List(#(String, String))) -> String {
  let row =
    list.fold(changes, good_row(), fn(row, change) {
      dict.insert(row, change.0, change.1)
    })
  let columns = dict.keys(row)
  "insert into spawn ("
  <> string.join(columns, ", ")
  <> ") values ("
  <> string.join(
    list.map(columns, fn(column) {
      let assert Ok(value) = dict.get(row, column) as "the column has a value"
      value
    }),
    ", ",
  )
  <> ")"
}

/// The text Postgres refused the statement with, or fails the test when it ran.
fn refused(statement statement: String) -> String {
  let database = database_support.new_database(on: database_support.shared())
  let assert Error(database_support.CommandFailed(output:)) =
    database_support.psql(
      with: database_support.settings(),
      database:,
      arguments: ["-c", statement],
    )
    as { "the statement was refused: " <> statement }
  output
}

fn assert_refused_by(
  statement statement: String,
  constraint constraint: String,
) -> Nil {
  let output = refused(statement:)
  assert string.contains(output, "\"" <> constraint <> "\"")
    as {
      "the constraint "
      <> constraint
      <> " refuses it; Postgres said: "
      <> output
    }
}

pub fn each_spawn_constraint_refuses_its_own_bad_row_under_its_own_name_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each(
    [
      #([#("entity_type", "37")], "spawn_entity_type_is_a_unit_type"),
      #([#("faction_id", "16384")], "spawn_faction_id_is_14_bits"),
      #([#("base_faction_id", "16384")], "spawn_base_faction_id_is_14_bits"),
      #([#("creature_id", "0")], "spawn_creature_id_is_in_18_bits"),
      #([#("creature_id", "262144")], "spawn_creature_id_is_in_18_bits"),
      #([#("world_id", "0")], "spawn_world_id_is_positive"),
      #([#("area_id", "-1")], "spawn_area_id_is_not_negative"),
      #([#("display_info_id", "0")], "spawn_display_info_id_is_in_17_bits"),
      #([#("display_info_id", "131072")], "spawn_display_info_id_is_in_17_bits"),
      #([#("outfit_info_id", "-1")], "spawn_outfit_info_id_is_in_15_bits"),
      #([#("outfit_info_id", "32768")], "spawn_outfit_info_id_is_in_15_bits"),
      #([#("active_prop_id", "-1")], "spawn_active_prop_id_is_not_negative"),
      #([#("world_socket_id", "16384")], "spawn_world_socket_id_is_in_14_bits"),
      #([#("world_socket_id", "-1")], "spawn_world_socket_id_is_in_14_bits"),
      #([#("source_row", "0")], "spawn_source_row_is_positive"),
      #(
        [
          #("source", "'made_up'"),
          #("reason", "'a reason'"),
          #("source_row", "null"),
        ],
        "spawn_source_is_a_content_source",
      ),
      #([#("x", "'NaN'")], "spawn_position_is_finite"),
      #([#("z", "'Infinity'")], "spawn_position_is_finite"),
      #([#("rotation_y", "'-Infinity'")], "spawn_rotation_is_finite"),
      #([#("source_row", "null")], "spawn_world_database_row_has_a_source_row"),
      #(
        [
          #("source", "'server_choice'"),
          #("source_row", "5"),
          #("reason", "'a reason'"),
        ],
        "spawn_world_database_row_has_a_source_row",
      ),
      #(
        [#("source", "'server_choice'"), #("source_row", "null")],
        "spawn_other_source_states_its_reason",
      ),
      #(
        [#("source", "'retail_record'"), #("source_row", "null")],
        "spawn_other_source_states_its_reason",
      ),
      #(
        [#("source", "'game_master'"), #("source_row", "null")],
        "spawn_other_source_states_its_reason",
      ),
      #(
        [
          #("source", "'server_choice'"),
          #("source_row", "null"),
          #("reason", "'   '"),
        ],
        "spawn_reason_says_something",
      ),
    ],
    fn(case_) {
      assert_refused_by(statement: insert_with(case_.0), constraint: case_.1)
    },
  )
}

pub fn a_spawn_id_is_positive_test() -> Nil {
  use <- owned_test.run(120_000)
  // TimerId(0) is the map's sweep, so no spawn is numbered 0.
  assert_refused_by(
    statement: "insert into spawn (id, source, source_row, entity_type, creature_id, world_id, area_id, x, y, z, rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id, faction_id, base_faction_id, active_prop_id, world_socket_id) overriding system value values (0, 'world_database', 1, 0, 73464, 3460, 0, 0, 0, 0, 0, 0, 0, 26565, 0, 1441, 1441, 0, 0)",
    constraint: "spawn_id_is_positive",
  )
}

pub fn a_source_row_is_in_the_table_once_test() -> Nil {
  use <- owned_test.run(120_000)
  assert_refused_by(
    statement: insert_with([]) <> "; " <> insert_with([]),
    constraint: "spawn_source_row_is_unique",
  )
}

pub fn each_spawn_stat_and_import_constraint_refuses_its_own_bad_row_under_its_own_name_test() -> Nil {
  use <- owned_test.run(120_000)
  // Spawn 1 is the first Virtual Defense Dagun, which migration 0008 inserts.
  assert_refused_by(
    statement: "insert into spawn_stat (spawn_id, stat, value) values (1, 32, 1)",
    constraint: "spawn_stat_is_a_stat_index",
  )
  assert_refused_by(
    statement: "insert into spawn_stat (spawn_id, stat, value) values (1, 0, 'NaN')",
    constraint: "spawn_stat_value_is_finite",
  )
  assert_refused_by(
    statement: "insert into content_import (file, sha256, rows, imported_at) values ('spawn.tsv', 'not a hash', 1, now())",
    constraint: "content_import_sha256_is_lower_case_hex",
  )
  assert_refused_by(
    statement: "insert into content_import (file, sha256, rows, imported_at) values ('spawn.tsv', repeat('A', 64), 1, now())",
    constraint: "content_import_sha256_is_lower_case_hex",
  )
  assert_refused_by(
    statement: "insert into content_import (file, sha256, rows, imported_at) values ('spawn.tsv', repeat('a', 64), -1, now())",
    constraint: "content_import_rows_is_not_negative",
  )
}

pub fn the_daguns_of_migration_0008_are_27_server_choices_that_state_their_row_test() -> Nil {
  use <- owned_test.run(120_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(output) =
    database_support.psql(
      with: database_support.settings(),
      database:,
      arguments: [
        "-At",
        "-c",
        "select count(*), count(distinct reason), min(creature_id), max(creature_id), min(faction_id), min(display_info_id) from spawn where source = 'server_choice'",
      ],
    )
    as "the query ran"
  assert string.trim(output) == "27|27|73465|73465|1442|26578"
    as "27 Virtual Defense Daguns (Creature2 73465), each with its own reason naming the world-database row whose offset it takes, faction 1442 (Creature2.factionId), display 26578 (Creature2DisplayGroupEntry 27216)"
}
