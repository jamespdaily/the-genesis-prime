//// The release: Gleam's Erlang shipment exported by `release/build`, started
//// by its own start script with every setting in its environment, and the tree
//// it starts. Expected values come from three places.
//// - The issue: the release starts from environment settings, and a setting
////   that is missing stops it with its name.
//// - CLAUDE.md, "Game tables load once at start into named records; a missing
////   row fails the load": a start whose tables lack a row the server requires
////   fails naming both tables, and starts no tree.
//// - Postgres: `pg_stat_activity` lists a row for each connection to a
////   database, with the database's name in `datname` and the time the
////   connection began in `backend_start`.
////
//// The release is started in a child operating system process, as the image
//// will start it, with the folder of tables of no rows in `planted_table`, so
//// no client file is needed. The pool is the test's own database.

import genesis_prime/server
import genesis_prime/shutdown
import genesis_prime/table/creature2
import genesis_prime/table/loader/store
import genesis_prime/table/localized_text
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import owned_test
import planted_table.{Integer}
import pog
import released_child
import released_shipment
import template_database

/// How long a test waits for the release to start, ask it to stop and end: the
/// child's own limit on its silence, plus the export when this test is the
/// first to need the release, plus its database and its end.
const child_deadline_ms = 180_000

/// How long a test waits for the release's pool to open its first connection.
/// No message announces the connection, so the wait asks again until it is
/// there or this deadline passes.
const connection_deadline_ms = 10_000

const connection_asked_again_ms = 50

fn environment(
  database: template_database.Database,
  tables: String,
) -> List(#(String, String)) {
  [
    #("GENESIS_TABLE_DIR", tables),
    ..released_child.database_environment(database)
  ]
}

pub fn a_release_starts_from_its_environment_and_stops_on_sigterm_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use tables <- planted_table.in_empty_tables_folder
  let script = released_shipment.start_script()
  let since = now(database)
  use child <- released_child.run_program(
    program: script,
    arguments: [],
    environment: environment(database, tables),
  )
  let assert Ok(_) =
    released_child.lines_until(child, string.contains(
      _,
      released_child.server_running,
    ))
    as "the release did not say it was running"
  assert wait_for_a_connection_made_since(database, since)
    as "the release's pool did not connect to the database named in PGDATABASE"

  released_child.terminate(child)
  let assert Ok(#(_lines, status)) = released_child.lines_until_exit(child)
    as "the release did not end after SIGTERM"
  assert status == 0 as "the release did not end with status 0 after SIGTERM"
}

pub fn a_release_started_without_a_setting_stops_naming_it_test() -> Nil {
  use <- owned_test.run(child_deadline_ms)
  use database <- template_database.run
  use tables <- planted_table.in_empty_tables_folder
  let script = released_shipment.start_script()
  // PGHOST is read for the pool and GENESIS_TABLE_DIR for the tables.
  list.each(["PGHOST", "GENESIS_TABLE_DIR"], fn(missing) {
    let settings =
      environment(database, tables)
      |> list.filter(fn(setting) { setting.0 != missing })
    use child <- released_child.run_program(
      program: script,
      arguments: [],
      environment: settings,
    )
    let assert Ok(#(lines, status)) = released_child.lines_until_exit(child)
      as { "the release started without " <> missing <> " did not end" }
    assert status != 0
      as { "the release started without " <> missing <> " ended with status 0" }
    assert list.any(lines, string.contains(_, missing))
      as { "the release did not name " <> missing <> " as missing" }
    assert !list.any(lines, string.contains(_, released_child.server_running))
      as { "the release started without " <> missing <> " said it was running" }
  })
}

pub fn a_start_with_a_required_row_missing_fails_naming_both_tables_and_starts_no_tree_test() -> Nil {
  use <- owned_test.run(30_000)
  use database <- template_database.run
  use folder <- planted_table.in_folder([
    #("Creature2", creature2_file(14_610)),
    #(
      "LocalizedText",
      localized_text_file([
        localized_text_row(1, 7),
      ]),
    ),
  ])
  let pool_settings =
    template_database.pool_settings(
      for: database,
      pool_name: process.new_name("release_test_pool"),
      pool_size: 2,
    )
  let key = reference.new()
  let started =
    server.start(server.Settings(
      pool: pool_settings,
      tables: server.TableSettings(
        key:,
        folder:,
        entries: [creature2.entry(), localized_text.entry()],
        requirements: [creature2_names_a_localized_text()],
      ),
      shutdown: shutdown.new(drain_deadline_ms: 1000, flush_deadline_ms: 1000),
    ))
  let expected =
    store.RowMissing(
      from_table: "Creature2",
      column: "localizedTextIdName",
      to_table: "LocalizedText",
      id: 14_610,
    )
  assert started == Error(server.TablesNotLoaded(expected))
    as "CLAUDE.md: a missing row fails the load; Creature2 row 1 names LocalizedText id 14610, which the planted LocalizedText lacks"
  let assert Error(error) = started
  assert string.contains(server.describe(error), "Creature2")
    as "the message does not name the table with the column"
  assert string.contains(server.describe(error), "LocalizedText")
    as "the message does not name the table with the missing row"
  assert process.named(pool_settings.name) == Error(Nil)
    as "the tree started: the database pool is running"
  assert planted_table.persistent_terms_under(key) == 0
    as "the failed load left its tables behind"
}

fn localized_text_row(id: Int, version: Int) -> List(planted_table.Cell) {
  planted_table.row(localized_text.schema, [
    #("ID", Integer(id)),
    #("version", Integer(version)),
  ])
}

fn localized_text_file(rows: List(List(planted_table.Cell))) -> BitArray {
  planted_table.bytes(planted_table.table(localized_text.schema, rows))
}

/// A Creature2 file of one row, id 1, whose `localizedTextIdName` is the id.
fn creature2_file(localized_text_id_name: Int) -> BitArray {
  planted_table.bytes(
    planted_table.table(creature2.schema, [
      planted_table.row(creature2.schema, [
        #("ID", Integer(1)),
        #("localizedTextIdName", Integer(localized_text_id_name)),
      ]),
    ]),
  )
}

/// The rule that Creature2's `localizedTextIdName` names a LocalizedText row.
fn creature2_names_a_localized_text() -> store.Requirement {
  store.Requirement(
    from_table: "Creature2",
    column: "localizedTextIdName",
    to_table: "LocalizedText",
    missing: fn(tables) {
      creature2.all(tables)
      |> list.map(fn(row) { row.localized_text_id_name })
      |> list.filter(fn(id) { result.is_error(localized_text.get(tables, id)) })
    },
  )
}

/// The database's clock, as text, read before the release starts.
fn now(database: template_database.Database) -> String {
  let assert Ok(returned) =
    pog.query("select clock_timestamp()::text")
    |> pog.returning(decode.at([0], decode.string))
    |> pog.execute(on: database.connection)
    as "the database's clock could not be read"
  let assert [time] = returned.rows
  time
}

/// Whether the database has a connection other than this test's own that began
/// after `since`, asked again until there is one or the deadline passes.
fn wait_for_a_connection_made_since(
  database: template_database.Database,
  since: String,
) -> Bool {
  wait_for(connection_deadline_ms, fn() {
    let assert Ok(returned) =
      pog.query(
        "select count(*)::int from pg_stat_activity where datname = $1 and backend_start > $2::text::timestamptz",
      )
      |> pog.parameter(pog.text(database.name))
      |> pog.parameter(pog.text(since))
      |> pog.returning(decode.at([0], decode.int))
      |> pog.execute(on: database.connection)
      as "the database's connections could not be counted"
    returned.rows != [0]
  })
}

fn wait_for(remaining_ms: Int, ready: fn() -> Bool) -> Bool {
  case ready(), remaining_ms > 0 {
    True, _ -> True
    False, False -> False
    False, True -> {
      process.sleep(connection_asked_again_ms)
      wait_for(int.max(0, remaining_ms - connection_asked_again_ms), ready)
    }
  }
}
