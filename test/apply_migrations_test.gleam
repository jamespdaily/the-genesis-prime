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
import genesis_prime/digest
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

/// Runs a copy of the script on `database` beside a folder of migration files:
/// the real first one, which makes `schema_migration`, and `extra`, each a path
/// under the folder and the file's text. The script reads the folder next to
/// its own `dev` folder, so the copy is the script, the file it sources and the
/// folder in a folder of their own, removed afterwards. Gives what the script
/// printed, or what it printed when it failed.
fn script_over(
  shared shared: Shared,
  database database: String,
  extra extra: List(#(String, String)),
) -> Result(String, database_support.CommandFailed) {
  let folder = "build/apply_migrations_" <> database
  let assert Ok(Nil) = simplifile.create_directory_all(folder <> "/dev")
    as "the copy's dev folder"
  let assert Ok(Nil) = simplifile.create_directory_all(folder <> "/setup_check")
    as "the copy's setup_check folder"
  let assert Ok(Nil) =
    simplifile.create_directory_all(folder <> "/priv/migrations")
    as "the copy's migration folder"
  list.each(
    [
      "dev/apply_migrations.sh",
      "setup_check/sha256.sh",
      "priv/migrations/0000_schema_migration.sql",
    ],
    fn(file) {
      let assert Ok(Nil) = simplifile.copy_file(file, folder <> "/" <> file)
        as "a file copied"
    },
  )
  list.each(extra, fn(file) {
    let path = folder <> "/priv/migrations/" <> file.0
    let assert Ok(Nil) = simplifile.create_directory_all(parent_of(path))
      as "the file's folder"
    let assert Ok(Nil) = simplifile.write(path, file.1) as "a file written"
  })
  let result =
    database_support.run_command(
      "bash",
      [folder <> "/dev/apply_migrations.sh", database],
      database_support.psql_environment(shared.settings),
    )
  let assert Ok(Nil) = simplifile.delete(folder) as "the copy removed"
  result
}

/// The folder a path is in.
fn parent_of(path: String) -> String {
  let assert Ok(#(_file, parent)) =
    path |> string.reverse |> string.split_once("/")
    as "a path with a folder"
  string.reverse(parent)
}

/// What `query` prints on the database, trimmed.
fn printed_by(
  shared shared: Shared,
  database database: String,
  query query: String,
) -> String {
  let assert Ok(printed) =
    database_support.psql(with: shared.settings, database:, arguments: [
      "-At",
      "-c",
      query,
    ])
    as "the query ran"
  string.trim(printed)
}

pub fn a_file_that_fails_is_neither_applied_nor_recorded_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_empty_database(on: shared, options: "")
  let output =
    failed_output(
      script_over(shared:, database:, extra: [
        #(
          "0001_fails.sql",
          "create table made_then_lost (a int);\nselect 1 / 0;\n",
        ),
      ]),
    )
  assert string.contains(output, "division by zero")
    as "the script stopped at the file that failed"
  assert list.map(recorded(shared, database), fn(row) { row.name })
    == ["0000_schema_migration"]
    as "the first file is applied and recorded, the failing one is not"
  assert printed_by(
      shared:,
      database:,
      query: "select to_regclass('made_then_lost') is null",
    )
    == "t"
    as "the failing file's first statement was rolled back with the rest"
}

pub fn a_file_that_succeeds_whose_record_fails_leaves_nothing_behind_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_empty_database(on: shared, options: "")
  // The file makes a table and then a constraint that its own record breaks, so
  // the file runs to its end and the insert after it fails: the file and its
  // record are one transaction, or the table would stay.
  let output =
    failed_output(
      script_over(shared:, database:, extra: [
        #(
          "0001_effect.sql",
          "create table effect_left (a int);\nalter table schema_migration add constraint no_such_record check (name <> '0001_effect');\n",
        ),
      ]),
    )
  assert string.contains(output, "no_such_record")
    as "the insert of the record is what failed"
  assert list.map(recorded(shared, database), fn(row) { row.name })
    == ["0000_schema_migration"]
    as "only the first file is recorded"
  assert printed_by(
      shared:,
      database:,
      query: "select to_regclass('effect_left') is null",
    )
    == "t"
    as "the file's table was rolled back with its failed record"
  assert printed_by(
      shared:,
      database:,
      query: "select count(*) from pg_constraint where conname = 'no_such_record'",
    )
    == "0"
    as "and so was its constraint"
}

pub fn only_the_files_directly_in_the_folder_are_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_empty_database(on: shared, options: "")
  let assert Ok(_) =
    script_over(shared:, database:, extra: [
      #("0001_real.sql", "create table real_one (a int);\n"),
      #("old/0002_in_a_subfolder.sql", "create table in_a_subfolder (a int);\n"),
    ])
    as "the script applied the files"
  assert list.map(recorded(shared, database), fn(row) { row.name })
    == ["0000_schema_migration", "0001_real"]
    as "the server reads the folder one level deep, and so does the script"
  assert printed_by(
      shared:,
      database:,
      query: "select to_regclass('in_a_subfolder') is null",
    )
    == "t"
}

pub fn a_file_that_would_end_the_transaction_or_run_concurrently_is_refused_before_any_file_runs_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  list.each(
    [
      #("COMMIT", "create table ended (a int);\ncommit;\n"),
      #("BEGIN", "begin;\ncreate table ended (a int);\n"),
      #("ROLLBACK", "create table ended (a int);\n  rollback ;\n"),
      #(
        "START TRANSACTION",
        "start transaction;\ncreate table ended (a int);\n",
      ),
      #(
        "CONCURRENTLY",
        "create index concurrently ended on schema_migration (name);\n",
      ),
    ],
    fn(row) {
      let database =
        database_support.new_empty_database(on: shared, options: "")
      let output =
        failed_output(
          script_over(shared:, database:, extra: [
            #("0001_fine.sql", "create table fine (a int);\n"),
            #("0002_refused.sql", row.1),
          ]),
        )
      assert string.contains(output, "0002_refused.sql holds")
        || string.contains(output, "0002_refused.sql uses")
        as { "the script names the file it refused for " <> row.0 }
      assert string.contains(output, "one transaction") as "and says why"
      assert printed_by(
          shared:,
          database:,
          query: "select to_regclass('schema_migration') is null",
        )
        == "t"
        as "no file ran, the first one included: the folder is refused whole"
    },
  )
}

pub fn a_comment_or_a_function_body_is_no_statement_that_ends_the_transaction_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_empty_database(on: shared, options: "")
  let assert Ok(_) =
    script_over(shared:, database:, extra: [
      #(
        "0001_words.sql",
        "-- not run concurrently; no commit; here\ncreate function one() returns int language plpgsql as $$\nbegin\n  return 1;\nend $$;\n",
      ),
    ])
    as "the script applied a file whose comment and function body hold the words"
  assert printed_by(shared:, database:, query: "select one()") == "1"
}

pub fn a_file_whose_name_is_not_letters_digits_and_underscores_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  let shared = database_support.shared()
  let database = database_support.new_empty_database(on: shared, options: "")
  let output =
    failed_output(
      script_over(shared:, database:, extra: [
        #("0001 spaced.sql", "select 1;\n"),
      ]),
    )
  assert string.contains(output, "0001 spaced.sql is not a name of letters")
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
    row.sha256 == digest.sha256(bytes)
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
