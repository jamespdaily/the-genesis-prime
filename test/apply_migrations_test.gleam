//// The script that applies the migration files and records them
//// (`dev/apply_migrations.sh`), which `./check`, the tests' template database
//// and the play database all use. Expected values come from these places.
//// - The card's tests: each file is applied and recorded by name and hash; a
////   database made before the record has its first four migrations marked
////   applied once, and then starts.
//// - The hash is the SHA-256 of the file's bytes as lower-case hex, computed
////   here by `genesis_prime/migration`, not by the script.
//// - A file and its record are one transaction (the script's own header): a
////   file that fails leaves neither.
//// - The four migrations that ran before the record existed are
////   `0001_account_and_character` to `0004_character_needs_rename`; their
////   files are unchanged by the record.

import database_support.{type Shared}
import genesis_prime
import genesis_prime/migration.{type Migration, Migration, Recorded}
import gleam/list
import gleam/result
import gleam/string
import owned_test
import simplifile

/// The migrations that ran on a database before the record existed.
const first_four = [
  "0001_account_and_character", "0002_character_list_columns",
  "0003_character_look", "0004_character_needs_rename",
]

/// What a database recorded: the rows of its schema_migration, by name.
fn recorded(shared: Shared, database: String) -> List(Migration) {
  let assert Ok(printed) =
    database_support.psql(with: shared.settings, database:, arguments: [
      "-At",
      "-c",
      "select name || '|' || sha256 from schema_migration order by name",
    ])
    as "the record reads"
  printed
  |> string.split("\n")
  |> list.filter(fn(line) { line != "" })
  |> list.map(fn(line) {
    let assert [name, sha256] = string.split(line, "|")
      as "a row is a name and a hash"
    Migration(name:, sha256:)
  })
}

/// A database that has the four first migrations' tables and no record, as the
/// play database was before the record existed.
fn database_made_before_the_record(shared: Shared) -> String {
  let database = database_support.new_empty_database(on: shared, options: "")
  list.each(first_four, fn(name) {
    let assert Ok(_) =
      database_support.psql(with: shared.settings, database:, arguments: [
        "-f",
        "priv/migrations/" <> name <> ".sql",
      ])
      as "an old migration applied"
  })
  database
}

fn failed_output(
  result: Result(String, database_support.CommandFailed),
) -> String {
  let assert Error(database_support.CommandFailed(output:)) = result
    as "the script refused"
  output
}

pub fn a_migrated_database_has_each_file_recorded_with_its_name_and_hash_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  assert Recorded(recorded(shared, database)) == Recorded(files())
    as "the rows are the files: name and the SHA-256 of the bytes"
  assert migration.check(files: files(), recorded: Recorded(files())) == Ok(Nil)
}

fn files() -> List(Migration) {
  genesis_prime.load_migrations()
}

pub fn applying_again_applies_nothing_and_records_nothing_twice_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_database(on: shared)
  let before = recorded(shared, database)
  let assert Ok(printed) =
    database_support.migrate(with: shared.settings, database:, arguments: [])
    as "applying to a migrated database succeeds"
  assert !string.contains(printed, "applying") as "no file was applied again"
  assert recorded(shared, database) == before
}

pub fn a_file_that_fails_is_neither_applied_nor_recorded_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_empty_database(on: shared, options: "")
  // The script reads the folder next to its own `dev` folder, so a copy of it
  // beside a folder of two files: the real first one and one that creates a
  // table and then fails.
  let folder = "build/apply_migrations_" <> database
  let assert Ok(Nil) = simplifile.create_directory_all(folder <> "/dev")
    as "the copy's dev folder"
  let assert Ok(Nil) =
    simplifile.create_directory_all(folder <> "/priv/migrations")
    as "the copy's migration folder"
  let assert Ok(Nil) =
    simplifile.copy_file(
      "dev/apply_migrations.sh",
      folder <> "/dev/apply_migrations.sh",
    )
    as "the script copied"
  let assert Ok(Nil) =
    simplifile.copy_file(
      "priv/migrations/0000_schema_migration.sql",
      folder <> "/priv/migrations/0000_schema_migration.sql",
    )
    as "the first migration copied"
  let assert Ok(Nil) =
    simplifile.write(
      folder <> "/priv/migrations/0001_fails.sql",
      "create table made_then_lost (a int);\nselect 1 / 0;\n",
    )
    as "the failing file written"
  let output =
    failed_output(database_support.run_command(
      "bash",
      [folder <> "/dev/apply_migrations.sh", database],
      database_support.psql_environment(shared.settings),
    ))
  assert string.contains(output, "division by zero")
    as "the script stopped at the file that failed"
  assert list.map(recorded(shared, database), fn(row) { row.name })
    == ["0000_schema_migration"]
    as "the first file is applied and recorded, the failing one is not"
  let assert Ok(printed) =
    database_support.psql(with: shared.settings, database:, arguments: [
      "-At",
      "-c",
      "select to_regclass('made_then_lost') is null",
    ])
    as "the table's existence reads"
  assert string.trim(printed) == "t"
    as "the failing file's first statement was rolled back with the rest"
  let assert Ok(Nil) = simplifile.delete(folder) as "the copy removed"
  Nil
}

pub fn a_database_made_before_the_record_is_refused_until_it_is_adopted_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_made_before_the_record(shared)
  let output =
    failed_output(
      database_support.migrate(with: shared.settings, database:, arguments: []),
    )
  assert string.contains(output, "--adopt")
    as "the script says to adopt the database, and applied nothing to it"
}

pub fn adopting_marks_the_first_four_migrations_applied_once_and_the_rest_apply_after_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_made_before_the_record(shared)
  let assert Ok(_) =
    database_support.migrate(with: shared.settings, database:, arguments: [
      "--adopt",
    ])
    as "the database is adopted"
  let adopted = recorded(shared, database)
  assert list.map(adopted, fn(row) { row.name })
    == ["0000_schema_migration", ..first_four]
    as "the record holds the first migration and the four, by name"
  assert list.all(adopted, fn(row) {
    let assert Ok(bytes) =
      simplifile.read_bits("priv/migrations/" <> row.name <> ".sql")
      as "the file reads"
    row.sha256 == migration.sha256(bytes)
  })
    as "each by the hash of its file's bytes"
  assert string.contains(
    failed_output(
      database_support.migrate(with: shared.settings, database:, arguments: [
        "--adopt",
      ]),
    ),
    "already has schema_migration",
  )
    as "a second adopt is refused: it is done once"
  let assert Ok(printed) =
    database_support.migrate(with: shared.settings, database:, arguments: [])
    as "the newer files apply to the adopted database"
  assert string.contains(printed, "applying 0005_")
    as "the migration newer than the four applies"
  assert !string.contains(printed, "applying 0001")
    as "and the four are not applied again"
  assert migration.check(
      files: files(),
      recorded: Recorded(recorded(shared, database)),
    )
    == Ok(Nil)
    as "the adopted and migrated database holds exactly the files' migrations"
}

pub fn a_database_that_did_not_run_the_first_four_is_not_adopted_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_empty_database(on: shared, options: "")
  let output =
    failed_output(
      database_support.migrate(with: shared.settings, database:, arguments: [
        "--adopt",
      ]),
    )
  assert string.contains(output, "did not run 0001 to 0004")
  assert result.is_error(
    database_support.psql(with: shared.settings, database:, arguments: [
      "-c",
      "select 1 from schema_migration",
    ]),
  )
    as "nothing was recorded"
}
