//// The import of the world database's spawn file (`genesis_prime/import_world_data`)
//// into the spawn table. Expected values come from these places.
//// - The planted file (`test/fixture/world_data/spawn.tsv`): the header and rows
////   29113 to 29139 of Jim's world database, 27 Virtual Battle Beasts of World
////   3460 (Creature2 73464, faction 1441, display 26565), none with stats.
//// - The design of the world spawns (the Design artifact of issue 375, section 1):
////   an import upserts on the row id in the file, so a spawn keeps its id when its
////   row changes; deletes the world-database rows that are no longer in the file
////   and leaves every other source alone; replaces each row's stats; records the
////   file's SHA-256 and row count; a second import changes nothing; the reader
////   refuses a bad file by its line and column, and the schema refuses a bad value
////   under its constraint's name, each before anything is written.
//// - Migration 0008: the 27 Daguns are server choices.
//// Each test runs on a database of its own, copied from the migrated template.

import content_support
import database_support
import genesis_prime/digest
import genesis_prime/import_world_data.{
  type Counts, BadField, Counts, FileRefused, RepeatedId, RowRefused,
  UnequalStats, WrongFieldCount, WrongHeader,
}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import recording_support
import simplifile

/// The text of the planted file.
fn fixture() -> String {
  let assert Ok(text) =
    simplifile.read(content_support.fixture_folder <> "/spawn.tsv")
    as "the planted file is in the repository"
  text
}

/// A new database, its connection, and the import of a folder.
fn import_into(
  database database: String,
  folder folder: String,
) -> Result(Counts, import_world_data.Failure) {
  import_world_data.import_spawns(
    db: content_support.connect(database:),
    folder:,
  )
}

pub fn the_planted_file_imports_27_beasts_and_records_its_hash_and_row_count_test() -> Nil {
  use <- owned_test.run(120_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(counts) =
    import_into(database:, folder: content_support.fixture_folder)
    as "the planted file imports"
  assert counts
    == Counts(
      inserted: 27,
      changed: 0,
      unchanged: 0,
      removed: 0,
      stats_written: 0,
      stats_deleted: 0,
    )
  assert content_support.count(
      database:,
      sql: "select count(*) from spawn where source = 'world_database' and creature_id = 73464 and world_id = 3460 and faction_id = 1441 and source_row between 29113 and 29139",
    )
    == 27
    as "27 world-database rows, each a Virtual Battle Beast of World 3460"
  assert content_support.psql(
      database:,
      sql: "select file, sha256, rows from content_import",
    )
    == "spawn.tsv|" <> digest.sha256(<<fixture():utf8>>) <> "|27"
    as "the import is recorded with the SHA-256 of the file's bytes and its row count"
}

pub fn a_second_import_changes_nothing_and_keeps_the_ids_test() -> Nil {
  use <- owned_test.run(120_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_into(database:, folder: content_support.fixture_folder)
  let ids =
    content_support.psql(
      database:,
      sql: "select string_agg(id::text, ',' order by source_row) from spawn where source = 'world_database'",
    )
  let assert Ok(counts) =
    import_into(database:, folder: content_support.fixture_folder)
  assert counts
    == Counts(
      inserted: 0,
      changed: 0,
      unchanged: 27,
      removed: 0,
      stats_written: 0,
      stats_deleted: 0,
    )
    as "nothing is inserted, changed or removed"
  assert content_support.psql(
      database:,
      sql: "select string_agg(id::text, ',' order by source_row) from spawn where source = 'world_database'",
    )
    == ids
    as "every spawn keeps its id"
}

pub fn a_changed_row_keeps_its_id_and_a_removed_row_is_deleted_and_server_choices_are_left_alone_test() -> Nil {
  use <- owned_test.run(120_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(_) =
    import_into(database:, folder: content_support.fixture_folder)
  let id_of_29113 =
    content_support.psql(
      database:,
      sql: "select id from spawn where source_row = 29113",
    )
  // A row the file changed since the last import, a stat the file no longer
  // gives, and a row the file no longer holds.
  content_support.psql(
    database:,
    sql: "update spawn set x = 1 where source_row = 29113",
  )
  content_support.psql(
    database:,
    sql: "insert into spawn_stat (spawn_id, stat, value) select id, 0, 5 from spawn where source_row = 29113",
  )
  content_support.psql(
    database:,
    sql: "insert into spawn (source, source_row, entity_type, creature_id, world_id, area_id, x, y, z, rotation_x, rotation_y, rotation_z, display_info_id, outfit_info_id, faction_id, base_faction_id, quest_checklist_index, active_prop_id, world_socket_id) values ('world_database', 1, 0, 73464, 3460, 0, 0, 0, 0, 0, 0, 0, 26565, 0, 1441, 1441, 0, 0, 0)",
  )
  let assert Ok(counts) =
    import_into(database:, folder: content_support.fixture_folder)
  assert counts
    == Counts(
      inserted: 0,
      changed: 1,
      unchanged: 26,
      removed: 1,
      stats_written: 0,
      stats_deleted: 1,
    )
    as "one row changed back, the extra row removed, and the stat the file does not give deleted"
  assert content_support.psql(
      database:,
      sql: "select id from spawn where source_row = 29113",
    )
    == id_of_29113
    as "the changed row keeps its id"
  assert content_support.count(
      database:,
      sql: "select count(*) from spawn where source = 'server_choice'",
    )
    == 27
    as "the 27 Daguns, a server choice, are left alone"
}

/// A folder holding `text` as spawn.tsv, and the import of it into a new
/// database: what the import gave, and how many world-database rows are in the
/// table afterwards.
fn import_text(
  text text: String,
) -> #(Result(Counts, import_world_data.Failure), Int) {
  use folder <- recording_support.in_folder
  let assert Ok(Nil) = simplifile.write(folder <> "/spawn.tsv", text)
    as "the test's file was written"
  let database = database_support.new_database(on: database_support.shared())
  let result = import_into(database:, folder:)
  #(
    result,
    content_support.count(
      database:,
      sql: "select count(*) from spawn where source = 'world_database'",
    ),
  )
}

/// The fixture with line `line` (1 is the header) replaced by `text`.
fn fixture_with_line(line line: Int, text text: String) -> String {
  string.split(fixture(), "\n")
  |> list.index_map(fn(existing, index) {
    case index + 1 == line {
      True -> text
      False -> existing
    }
  })
  |> string.join("\n")
}

/// The fixture's line `line` with its tab-separated field `field` (0 is the id)
/// replaced by `value`.
fn with_field(line line: Int, field field: Int, value value: String) -> String {
  with_fields(line:, changes: [#(field, value)])
}

/// The fixture's line `line` with each tab-separated field of `changes` (0 is the
/// id) replaced by its value.
fn with_fields(
  line line: Int,
  changes changes: List(#(Int, String)),
) -> String {
  let assert Ok(existing) =
    list.first(list.drop(string.split(fixture(), "\n"), line - 1))
    as "the fixture has the line"
  fixture_with_line(
    line:,
    text: string.split(existing, "\t")
      |> list.index_map(fn(held, index) {
        case list.key_find(changes, index) {
          Ok(value) -> value
          Error(Nil) -> held
        }
      })
      |> string.join("\t"),
  )
}

pub fn each_refusal_of_the_reader_names_its_line_and_column_and_writes_nothing_test() -> Nil {
  use <- owned_test.run(180_000)
  list.each(
    [
      #(
        fixture_with_line(line: 1, text: "id\tentity_type"),
        WrongHeader(found: "id\tentity_type"),
      ),
      #(
        fixture_with_line(line: 3, text: "29114\t0"),
        WrongFieldCount(line: 3, found: 2),
      ),
      #(
        with_field(line: 4, field: 5, value: "abc"),
        BadField(line: 4, column: "x", value: "abc", wanted: "a finite number"),
      ),
      #(
        with_field(line: 5, field: 6, value: "NaN"),
        BadField(line: 5, column: "y", value: "NaN", wanted: "a finite number"),
      ),
      #(
        with_field(line: 6, field: 2, value: "12.5"),
        BadField(
          line: 6,
          column: "creature_id",
          value: "12.5",
          wanted: "a whole number",
        ),
      ),
      #(
        with_field(line: 7, field: 0, value: "29113"),
        RepeatedId(line: 7, id: 29_113),
      ),
      #(
        with_field(line: 8, field: 18, value: "{0,10}"),
        UnequalStats(line: 8, ids: 2, values: 0),
      ),
    ],
    fn(case_) {
      let #(text, refusal) = case_
      let #(result, written) = import_text(text:)
      assert result == Error(FileRefused(refusal:))
        as {
          "the reader refuses it: "
          <> import_world_data.describe_refusal(refusal)
        }
      assert written == 0 as "and nothing is written"
    },
  )
}

pub fn a_value_the_schema_refuses_is_reported_under_its_constraint_and_row_and_nothing_is_written_test() -> Nil {
  use <- owned_test.run(180_000)
  // The reader judges no range: a unit type of 37 and a faction of 16384 are the
  // schema's to refuse (migration 0008).
  let #(result, written) =
    import_text(text: with_field(line: 4, field: 1, value: "37"))
  assert result
    == Error(RowRefused(
      constraint: "spawn_entity_type_is_a_unit_type",
      source_row: Some(29_115),
    ))
    as "refused under the constraint's name, with the row's id in the file"
  assert written == 0 as "the rows before it were not kept"
  let #(result, _) =
    import_text(text: with_field(line: 3, field: 13, value: "16384"))
  assert result
    == Error(RowRefused(
      constraint: "spawn_faction_id_is_14_bits",
      source_row: Some(29_114),
    ))
}

pub fn a_refusal_in_a_later_batch_rolls_back_the_earlier_batches_test() -> Nil {
  use <- owned_test.run(180_000)
  // 5,001 rows: the first batch of 5,000 writes, the second holds the bad row.
  let assert [header, first, ..] = string.split(fixture(), "\n")
  let rows =
    int.range(from: 1, to: 5002, with: [], run: fn(rows, number) {
      let assert [_, ..rest] = string.split(first, "\t")
      [string.join([int.to_string(number), ..rest], "\t"), ..rows]
    })
    |> list.reverse
  let bad = case list.last(rows) {
    Ok(last) -> string.replace(last, "\t0\t73464\t", "\t37\t73464\t")
    _ -> panic as "there are rows"
  }
  let text =
    string.join([header, ..list.append(list.take(rows, 5000), [bad])], "\n")
    <> "\n"
  let #(result, written) = import_text(text:)
  assert result
    == Error(RowRefused(
      constraint: "spawn_entity_type_is_a_unit_type",
      source_row: Some(5001),
    ))
  assert written == 0
    as "the one transaction rolled back the first batch of 5,000 rows too"
}

pub fn numbers_as_postgres_writes_them_import_as_the_numbers_they_are_test() -> Nil {
  use <- owned_test.run(120_000)
  // A whole number, a number with a positive exponent and one with a negative
  // exponent, as positions and as stat values, and a stat list of two.
  let text =
    with_fields(line: 2, changes: [
      #(5, "0"),
      #(6, "3.43e+06"),
      #(7, "1e-05"),
      #(18, "{0,10}"),
      #(19, "{3.43e+06,1e-05}"),
    ])
  use folder <- recording_support.in_folder
  let assert Ok(Nil) = simplifile.write(folder <> "/spawn.tsv", text)
    as "the test's file was written"
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(counts) = import_into(database:, folder:)
    as "the numbers import"
  assert counts.inserted == 27 && counts.stats_written == 2
  assert content_support.psql(
      database:,
      sql: "select x || ' ' || y || ' ' || z from spawn where source_row = 29113",
    )
    == "0 3.43e+06 1e-05"
    as "0, 3.43e+06 and 1e-05 as the real numbers they are"
  assert content_support.psql(
      database:,
      sql: "select string_agg(stat || ':' || value, ' ' order by stat) from spawn_stat",
    )
    == "0:3.43e+06 10:1e-05"
    as "the stats {0,10} with the values {3.43e+06,1e-05}"
  assert import_world_data.number("3.43e+06") == Ok(3_430_000.0)
    && import_world_data.number("1e-05") == Ok(0.00001)
    && import_world_data.number("0") == Ok(0.0)
    && import_world_data.number("-1.5") == Ok(-1.5)
    && import_world_data.number("NaN") == Error(Nil)
    && import_world_data.number("inf") == Error(Nil)
    as "the parser's forms, and no NaN or infinity"
}

pub fn a_stat_the_schema_refuses_is_reported_under_its_constraint_with_the_row_of_its_spawn_and_nothing_is_written_test() -> Nil {
  use <- owned_test.run(120_000)
  // Stat 40 is outside the 5 bits of a stat index (opcode.0x262).
  let #(result, written) =
    import_text(
      text: with_fields(line: 2, changes: [#(18, "{40}"), #(19, "{1}")]),
    )
  assert result
    == Error(RowRefused(
      constraint: "spawn_stat_is_a_stat_index",
      source_row: Some(29_113),
    ))
    as "the stat's constraint, and the row of the file its spawn came from, not a question mark"
  assert written == 0 as "nothing is written"
}

pub fn the_transaction_waits_for_every_statement_of_the_whole_world_database_test() -> Nil {
  use <- owned_test.run(5000)
  // Evidence: the import of the whole world database (77,794 rows, in 16
  // batches) on an idle machine's Postgres 18, every statement logged
  // (`log_min_duration_statement = 0`), ran 66 statements in its transaction,
  // which lasted 3.73 s from `begin` to `commit`. A pool drops the connection
  // of a transaction that outlives its checkout deadline, 5,000 ms when the
  // checkout names none (`pgo_pool.erl`, `TIMEOUT`), as `pog.transaction`'s
  // does; a loaded machine took longer and the import failed with a timeout.
  // A statement's own allowance is pog's query timeout, 5,000 ms (`pog.timeout`).
  let whole_world_database_rows = 77_794
  let statements_of_the_whole_world_database = 66
  let pog_query_timeout_ms = 5000
  assert import_world_data.transaction_deadline_ms(
      rows: whole_world_database_rows,
    )
    >= statements_of_the_whole_world_database * pog_query_timeout_ms
    as "every statement of the whole world database keeps a query's timeout"
  assert import_world_data.transaction_deadline_ms(
      rows: whole_world_database_rows,
    )
    > import_world_data.transaction_deadline_ms(rows: 27)
    as "a bigger file waits longer"
  assert import_world_data.transaction_deadline_ms(rows: 27)
    >= 6 * pog_query_timeout_ms
    as "the planted file's batch (4 statements) and the 2 that close the import"
}
