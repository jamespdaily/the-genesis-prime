//// A server pointed at a database that has not run exactly the migration files
//// it was built with refuses to start. Expected values come from these places.
//// - The card's test: a database missing the newest migration makes the
////   server refuse to start, exit non-zero and name it, and the same database
////   fully migrated starts; the same for an applied migration whose file was
////   edited, a recorded migration with no file, a database with no record of
////   its migrations, and a record the server cannot read (a table of another
////   shape).
//// - A database that is down when the server starts is logged as unreachable
////   and asked again; once it answers, it is checked as at start: all present
////   prints the ready line then, and a missing migration ends the node with
////   status 1 naming it (Jim's decision on the readiness card).
//// - A node that ends because `main` stopped ends with status 1
////   (`genesis_prime/application`, `sigterm_test`), and prints its ready line
////   only when the server can serve (`genesis_prime/readiness`).
//// - The newest migration is the last file of `priv/migrations` in name order;
////   `0003_character_look` and the others are files of that folder.
//// Each test starts a node of its own (`serving_node`) on a database of its
//// own.

import database_support
import genesis_prime
import gleam/list
import gleam/string
import owned_test
import recording_support
import serving_node.{LateDatabase, Serving}

/// What the node prints when the server can serve: the start of its ready
/// line.
const ready_line = "serves the STS login on port"

/// The name of the last migration file, which is the newest.
fn newest_migration() -> String {
  let assert Ok(newest) = list.last(genesis_prime.load_migrations())
    as "the folder holds migrations"
  newest.name
}

/// Runs `change` on the database, as the administrator of the test's server.
fn change(database: String, change: String) -> Nil {
  let assert Ok(_) =
    database_support.psql(
      with: database_support.shared().settings,
      database:,
      arguments: ["-c", change],
    )
    as "the change to the database ran"
  Nil
}

/// Starts a node on a fully migrated database of its own after `change` has
/// run on it, and hands the node to `body`.
fn with_node_after(
  change sql: String,
  body body: fn(serving_node.Node) -> a,
) -> a {
  use folder <- recording_support.in_folder
  let database = database_support.new_database(on: database_support.shared())
  change(database, sql)
  body(serving_node.start(mode: Serving, folder:, database:))
}

/// Fails the test unless the node ended with status 1, printed `reason`, and
/// printed no ready line.
fn assert_refused(node: serving_node.Node, reason reason: String) -> Nil {
  assert serving_node.await_exit(node) == 1
    as "the server refused to start: the node ended with status 1"
  let printed = serving_node.output(node)
  assert string.contains(printed, reason)
    as "the node named the migration and what is wrong with it"
  assert !string.contains(printed, ready_line)
    as "no ready line was printed for a server that refused to start"
}

pub fn a_database_missing_the_newest_migration_refuses_the_server_and_names_it_test() -> Nil {
  use <- owned_test.run(120_000)
  let newest = newest_migration()
  use node <- with_node_after(
    change: "delete from schema_migration where name = '" <> newest <> "'",
  )
  assert_refused(node, reason: "has not run the migration " <> newest)
}

pub fn the_same_database_fully_migrated_starts_the_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use node <- with_node_after(change: "select 1")
  assert serving_node.await_output(node, ready_line)
    as "the node printed its ready line: the recorded migrations are the files"
  serving_node.terminate(node)
  assert serving_node.await_exit(node) == 0
    as "SIGTERM ends the node with status 0"
}

pub fn an_applied_migration_edited_after_it_ran_refuses_the_server_and_names_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use node <- with_node_after(
    change: "update schema_migration set sha256 = repeat('0', 64) where name = '0003_character_look'",
  )
  assert_refused(node, reason: "0003_character_look was edited after it ran")
}

pub fn a_recorded_migration_with_no_file_refuses_the_server_and_names_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use node <- with_node_after(
    change: "insert into schema_migration (name, sha256) values ('9999_no_such_file', repeat('1', 64))",
  )
  assert_refused(
    node,
    reason: "ran the migration 9999_no_such_file, which has no file",
  )
}

pub fn a_database_with_no_record_of_its_migrations_refuses_the_server_test() -> Nil {
  use <- owned_test.run(120_000)
  use node <- with_node_after(change: "drop table schema_migration")
  assert_refused(node, reason: "predates migration records")
}

pub fn a_record_the_server_cannot_read_refuses_the_server_naming_the_error_test() -> Nil {
  use <- owned_test.run(120_000)
  // The table has a column of another name, so the read fails in Postgres with
  // undefined_column (42703), not undefined_table.
  use node <- with_node_after(
    change: "alter table schema_migration rename column sha256 to hash",
  )
  assert_refused(
    node,
    reason: "schema_migration could not be read: undefined_column",
  )
}

/// Starts a node on a database that does not exist yet, waits for it to log
/// the database as unreachable, makes the database as a copy of the migrated
/// template after `change` (run on it once made), and hands the node to
/// `body`.
fn with_late_node(
  change sql: String,
  body body: fn(serving_node.Node) -> a,
) -> a {
  use folder <- recording_support.in_folder
  let shared = database_support.shared()
  let database = database_support.unused_name(on: shared)
  let node = serving_node.start(mode: LateDatabase, folder:, database:)
  assert serving_node.await_output(node, "the database is unreachable")
    as "the node gave up its first ask and logged the database as unreachable"
  assert !string.contains(serving_node.output(node), ready_line)
    as "no ready line while the database is down"
  // The change is made under another name and the database is renamed after,
  // so the node never finds the database before the change.
  let made = database_support.unused_name(on: shared)
  database_support.create_database(
    on: shared,
    name: made,
    options: "template \"" <> shared.template <> "\"",
  )
  change(made, sql)
  let assert Ok(Nil) =
    database_support.execute(
      on: shared,
      sql: "alter database \"" <> made <> "\" rename to \"" <> database <> "\"",
    )
    as "the database was renamed to the name the node asks for"
  body(node)
}

pub fn a_database_down_at_start_that_comes_up_migrated_gets_the_ready_line_late_test() -> Nil {
  use <- owned_test.run(120_000)
  use node <- with_late_node(change: "select 1")
  assert serving_node.await_output(node, ready_line)
    as "the node kept asking, and printed its ready line once the migrated database answered"
  serving_node.terminate(node)
  assert serving_node.await_exit(node) == 0
    as "SIGTERM ends the node with status 0"
}

pub fn a_database_down_at_start_that_comes_up_missing_a_migration_ends_the_node_naming_it_test() -> Nil {
  use <- owned_test.run(120_000)
  let newest = newest_migration()
  use node <- with_late_node(
    change: "delete from schema_migration where name = '" <> newest <> "'",
  )
  assert_refused(node, reason: "has not run the migration " <> newest)
}
