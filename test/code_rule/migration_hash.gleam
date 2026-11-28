//// The migration-hash rule: a file of `priv/migrations` has the SHA-256 its
//// row of the list records, so a pull request cannot change a migration a
//// database may have run (the server refuses a database whose recorded hash
//// differs, genesis_prime/migration).
////
//// ```
//// genesis_prime.load_migrations ──► name, SHA-256 of each file
//// the list (`list_path`) ──────────► name, recorded SHA-256 of each row
////        each file ─► no row, or a different hash ─► breach
////        each row ─► no file ─► breach; out of order or repeated ─► breach
//// ```
////
//// - The hash is the one `genesis_prime.load_migrations` computes for the
////   server, so the list holds what a database records.
//// - The list holds one `name sha256` row per file, sorted by name. A new
////   migration adds its row in the same pull request.
//// - A file with no row is a breach at the file's path; every other breach is
////   at its row of the list.

import code_rule/list_file
import code_rule/source.{type Breach, Breach}
import genesis_prime/migration.{type Migration}
import gleam/dict
import gleam/list
import gleam/string

/// A row of the list: a migration's name, its recorded hash, and its line of
/// the list file (counted from 1).
pub type Listed {
  Listed(name: String, sha256: String, line: Int)
}

/// The list of recorded hashes.
pub const list_path = "test/code_rule/migration_hashes.txt"

/// The rows of the list text.
pub fn parse_list(text text: String) -> List(Listed) {
  list_file.rows(text)
  |> list.map(fn(entry) {
    let #(row, line) = entry
    let assert [name, sha256] = string.split(row, " ")
      as list_file.bad_row(line:, what: "is not a name and a hash")
    Listed(name:, sha256:, line:)
  })
}

/// A breach for each migration with no row, each row with no migration or a
/// different hash, and each row not after the row before it by name.
pub fn breaches(
  migrations migrations: List(Migration),
  listed listed: List(Listed),
) -> List(Breach) {
  let recorded =
    list.map(listed, fn(row) { #(row.name, row.sha256) }) |> dict.from_list
  let actual =
    list.map(migrations, fn(migration) { #(migration.name, migration.sha256) })
    |> dict.from_list
  let without_row =
    list.filter_map(migrations, fn(migration) {
      case dict.has_key(recorded, migration.name) {
        True -> Error(Nil)
        False ->
          Ok(Breach(
            path: "priv/migrations/" <> migration.name <> ".sql",
            line: 1,
            rule: "a migration with no row in " <> list_path,
          ))
      }
    })
  let at_rows =
    list.filter_map(listed, fn(row) {
      case dict.get(actual, row.name) {
        Error(Nil) -> Ok(at_row(row, "has no migration file"))
        Ok(sha256) if sha256 == row.sha256 -> Error(Nil)
        Ok(_) ->
          Ok(at_row(row, "differs from its file: the migration was changed"))
      }
    })
  let disordered =
    list_file.disordered(
      rows: listed,
      compare: fn(before, row) { string.compare(before.name, row.name) },
      path: list_path,
      line: fn(row) { row.line },
      name: fn(row) { row.name },
      what: "is not after the row before it",
    )
  list.flatten([without_row, at_rows, disordered])
}

fn at_row(row: Listed, what: String) -> Breach {
  Breach(path: list_path, line: row.line, rule: row.name <> " " <> what)
}
