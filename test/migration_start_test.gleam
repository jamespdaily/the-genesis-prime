//// A server pointed at a database that has not run exactly the migration files
//// it was built with refuses to start. Expected values come from these places.
//// - The card's test: a database missing the newest migration makes the
////   server refuse to start, exit non-zero and name it, and the same database
////   fully migrated starts; the same for an applied migration whose file was
////   edited, a recorded migration with no file, and a database with no record
////   of its migrations.
//// - A node that ends because `main` stopped ends with status 1
////   (`genesis_prime/application`, `sigterm_test`), and prints its ready line
////   only when the server can serve (`genesis_prime/readiness`).
//// - The newest migration is the last file of `priv/migrations` in name order;
////   `0003_character_look` and the others are files of that folder.
//// Each test starts a node of its own (`serving_node`) on a database of its
//// own.

import database_support
import gleam/list
import gleam/string
import owned_test
import recording_support
import serving_node.{Serving}
import simplifile

/// What the node prints when the server can serve: the start of its ready
/// line.
const ready_line = "serves the STS login on port"

/// How long a node has to start or to end; a passing test never reaches it.
const node_wait_ms = 60_000

/// The name of the last migration file, which is the newest.
fn newest_migration() -> String {
  let assert Ok(names) = simplifile.read_directory("priv/migrations")
    as "the migration folder reads"
  let assert Ok(newest) =
    names
    |> list.filter(string.ends_with(_, ".sql"))
    |> list.sort(string.compare)
    |> list.last
    as "the folder holds migrations"
  string.drop_end(newest, string.length(".sql"))
}

/// Starts a node on a fully migrated database of its own after `change` has
/// run on it, and hands the node to `body`.
fn with_node_after(
  change change: String,
  body body: fn(serving_node.Node) -> a,
) -> a {
  use folder <- recording_support.in_folder
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let assert Ok(_) =
    database_support.psql(with: shared.settings, database:, arguments: [
      "-c",
      change,
    ])
    as "the change to the database ran"
  body(serving_node.start(mode: Serving, folder:, database:))
}

/// Fails the test unless the node ended with status 1, printed `reason`, and
/// printed no ready line.
fn assert_refused(node: serving_node.Node, reason reason: String) -> Nil {
  assert serving_node.await_exit(node, node_wait_ms) == Ok(1)
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
  assert serving_node.await_output(node, ready_line, node_wait_ms)
    as "the node printed its ready line: the recorded migrations are the files"
  serving_node.terminate(node)
  assert serving_node.await_exit(node, node_wait_ms) == Ok(0)
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
