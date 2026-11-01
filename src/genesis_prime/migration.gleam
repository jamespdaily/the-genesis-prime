//// Whether a database has run exactly the migration files the server was
//// built with: the rule the server's readiness applies after its first read
//// (genesis_prime/readiness).
////
//// A migration is a file in priv/migrations, named by its name without
//// `.sql`, and the SHA-256 of its bytes as lower-case hex. A database records
//// each file it ran in `schema_migration`, with the same two values
//// (dev/apply_migrations.sh writes the row in the transaction that runs the
//// file). The two lists must agree: a file with no row is a migration the
//// database lacks, a row with no file is a migration this build does not
//// know, and a row whose hash differs from its file's is a migration edited
//// after it ran. A database with no `schema_migration` table was made before
//// the record existed, and one that cannot be read is no database to trust.
//// Each is a reason to refuse to start, reported by the
//// first name in byte order, so one run names one migration.

import gleam/dict
import gleam/list
import gleam/string

/// One migration: its name, and the SHA-256 of its file's bytes as lower-case
/// hex, as a file has it and as the database recorded it.
pub type Migration {
  Migration(name: String, sha256: String)
}

/// What a database recorded.
pub type Recorded {
  /// The rows of its `schema_migration` table.
  Recorded(migrations: List(Migration))
  /// It has no `schema_migration` table.
  NoRecord
  /// The database answered, and reading its `schema_migration` failed with
  /// this error (a permission refused, a table of another shape).
  Unreadable(reason: String)
}

/// Why a database is not the one the files describe.
pub type Refusal {
  /// The database has no `schema_migration` table: it was made before the
  /// record existed.
  DatabasePredatesRecords
  /// A file the database never ran.
  NotApplied(name: String)
  /// The database's `schema_migration` could not be read, for the reason given.
  RecordUnreadable(reason: String)
  /// A migration whose file's hash differs from the one recorded when it ran.
  Edited(name: String)
  /// A recorded migration with no file in the folder.
  NoFile(name: String)
}

/// Compares the files with what the database recorded: `Ok` when they name the
/// same migrations with the same hashes, else the first difference by name in
/// byte order.
pub fn check(
  files files: List(Migration),
  recorded recorded: Recorded,
) -> Result(Nil, Refusal) {
  case recorded {
    NoRecord -> Error(DatabasePredatesRecords)
    Unreadable(reason:) -> Error(RecordUnreadable(reason:))
    Recorded(migrations: applied) -> {
      let in_files = hashes(files)
      let in_database = hashes(applied)
      let names =
        list.append(files, applied)
        |> list.map(fn(migration) { migration.name })
        |> list.unique
        |> list.sort(string.compare)
      let refusal =
        list.find_map(names, fn(name) {
          case dict.get(in_files, name), dict.get(in_database, name) {
            Ok(file), Ok(recorded) if file == recorded -> Error(Nil)
            Ok(_), Ok(_) -> Ok(Edited(name))
            Ok(_), Error(Nil) -> Ok(NotApplied(name))
            Error(Nil), Ok(_) -> Ok(NoFile(name))
            Error(Nil), Error(Nil) -> Error(Nil)
          }
        })
      case refusal {
        Ok(refusal) -> Error(refusal)
        Error(Nil) -> Ok(Nil)
      }
    }
  }
}

fn hashes(migrations: List(Migration)) -> dict.Dict(String, String) {
  list.map(migrations, fn(migration) { #(migration.name, migration.sha256) })
  |> dict.from_list
}

/// A sentence that names the migration and what is wrong with it, for the log
/// and the crash of a server that refuses to start.
pub fn describe(refusal: Refusal) -> String {
  case refusal {
    DatabasePredatesRecords ->
      "the database predates migration records: it has no schema_migration table; run dev/apply_migrations.sh --adopt on it once if it already ran the first four migrations"
    RecordUnreadable(reason:) ->
      "the database's schema_migration could not be read: " <> reason
    NotApplied(name:) ->
      "the database has not run the migration "
      <> name
      <> "; apply it with dev/apply_migrations.sh"
    Edited(name:) ->
      "the migration "
      <> name
      <> " was edited after it ran: its file's hash differs from the one the database recorded"
    NoFile(name:) ->
      "the database ran the migration "
      <> name
      <> ", which has no file in priv/migrations"
  }
}
