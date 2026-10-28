//// The client's game tables as persistent terms: one term per table, a tuple
//// of its rows indexed by id, written once by `load` and never replaced. A
//// load reads each table's file, writes its term under its key, then checks
//// that every row the server requires exists; when anything fails it erases
//// what it wrote. A load also digests the files it read.
////
//// - **The server's key is fixed.** The server's tables are stored under
////   `ServerKey`, a constant the server writes, so the tables a rule's
////   settings hold are the same value in every run and a recording of the
////   settings compares equal to a replay's. Any other load (a test's, the
////   coverage measure's) takes a key made for it, so two loads never share
////   terms. Only the server's own start and the tests that replay a
////   recording load under `ServerKey`, and each once in a run.
//// - **The digest** is SHA-256 over every file read, each preceded by its
////   name, in the order of the entries. A recording's header holds it, so a
////   replay on other table files is told to record again.

import genesis_prime/table/loader/tbl_file
import gleam/bit_array
import gleam/crypto
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/result
import simplifile

/// What a load's terms are stored under.
pub opaque type Key {
  /// The server's own key, the same in every run.
  ServerKey
  /// A key made for one load.
  LoadKey(Reference)
}

/// The tables of one load. It holds the key their terms are stored under, so a
/// process that reads a table is started with it, and the digest of the files
/// they were read from.
pub opaque type Tables {
  Tables(key: Key, tables: List(String), digest: String)
}

/// One table the loader reads: the client's name, its file, and how to read
/// the file and write its term under a load's key. Each generated table
/// module makes its own.
pub opaque type Entry {
  Entry(
    schema: tbl_file.Schema,
    table: String,
    file: String,
    put: fn(BitArray, Key) -> Result(Nil, tbl_file.FileError),
    ids: fn(Tables) -> List(Int),
  )
}

/// A column whose every id must have a row in another table. `missing` gives
/// the ids the column holds that the other table has no row for.
pub type Requirement {
  Requirement(
    from_table: String,
    column: String,
    to_table: String,
    missing: fn(Tables) -> List(Int),
  )
}

/// Why a load failed.
pub type LoadError {
  /// A table's file could not be read.
  TableFileUnreadable(file: String, reason: simplifile.FileError)
  /// A table's file is not accepted as that table.
  TableFileInvalid(table: String, error: tbl_file.FileError)
  /// A required row is missing: a column of one table names an id the other
  /// table has no row for.
  RowMissing(from_table: String, column: String, to_table: String, id: Int)
}

/// A sentence that says why a load failed, naming the tables, for the message
/// the server stops with.
pub fn describe(error: LoadError) -> String {
  case error {
    TableFileUnreadable(file:, reason:) ->
      "the file "
      <> file
      <> ".tbl could not be read: "
      <> simplifile.describe_error(reason)
    TableFileInvalid(table:, error:) ->
      "the file of the table "
      <> table
      <> " is not accepted: "
      <> tbl_file.describe_error(error)
    RowMissing(from_table:, column:, to_table:, id:) ->
      "the table "
      <> from_table
      <> " column "
      <> column
      <> " names id "
      <> int.to_string(id)
      <> ", which the table "
      <> to_table
      <> " has no row for"
  }
}

/// An entry for a generated table module. A table's term is stored under its
/// load's key and the table's name.
pub fn entry(
  schema schema: tbl_file.Schema,
  decode decode: fn(BitArray, tbl_file.Strings) ->
    Result(row, tbl_file.RecordError),
  id id: fn(row) -> Int,
) -> Entry {
  Entry(
    schema:,
    table: schema.table,
    file: schema.file,
    put: fn(bytes, key) {
      tbl_file.read(bytes:, schema:, decode:, id:)
      |> result.map(fn(table) { put_term(#(key, schema.table), table) })
    },
    ids: fn(tables) { list.map(rows(tables:, table: schema.table), id) },
  )
}

/// The digest of the files the tables were read from, as upper-case hex.
pub fn digest(tables: Tables) -> String {
  tables.digest
}

/// The schema the entry's file is read by.
pub fn schema(entry: Entry) -> tbl_file.Schema {
  entry.schema
}

/// The name of the entry's file, without `.tbl`.
pub fn file(entry: Entry) -> String {
  entry.file
}

/// The ids that have a row in the entry's table, in order.
pub fn ids(entry entry: Entry, tables tables: Tables) -> List(Int) {
  entry.ids(tables)
}

/// Reads every entry's file from the folder, writes each table's term under
/// `key`, then checks each requirement. Stops at the first failure and erases
/// the terms it wrote. A key is used by one load.
pub fn load(
  under key: Reference,
  from folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
) -> Result(Tables, LoadError) {
  load_under(key: LoadKey(key), folder:, entries:, requirements:)
}

/// `load` under the server's own key. The server loads once at start, and a
/// test that replays a recording loads once in its run; a second load under
/// this key replaces the terms of the first.
pub fn load_for_server(
  from folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
) -> Result(Tables, LoadError) {
  load_under(key: ServerKey, folder:, entries:, requirements:)
}

fn load_under(
  key key: Key,
  folder folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
) -> Result(Tables, LoadError) {
  case
    put_each(
      key:,
      folder:,
      entries:,
      written: [],
      hasher: crypto.new_hasher(crypto.Sha256),
    )
  {
    Error(#(error, written)) -> {
      unload(Tables(key:, tables: written, digest: ""))
      Error(error)
    }
    Ok(#(written, digest)) -> {
      let tables = Tables(key:, tables: written, digest:)
      case first_missing_row(tables, requirements) {
        Ok(Nil) -> Ok(tables)
        Error(error) -> {
          unload(tables)
          Error(error)
        }
      }
    }
  }
}

/// Reads and writes each entry in turn, giving the tables written and the
/// digest of the files read, or the first error with the tables written
/// before it.
fn put_each(
  key key: Key,
  folder folder: String,
  entries entries: List(Entry),
  written written: List(String),
  hasher hasher: crypto.Hasher,
) -> Result(#(List(String), String), #(LoadError, List(String))) {
  case entries {
    [] -> Ok(#(written, bit_array.base16_encode(crypto.digest(hasher))))
    [entry, ..rest] ->
      case put_one(key:, folder:, entry:, hasher:) {
        Ok(hasher) ->
          put_each(key:, folder:, entries: rest, hasher:, written: [
            entry.table,
            ..written
          ])
        Error(error) -> Error(#(error, written))
      }
  }
}

/// Reads one entry's file and writes its term, giving the hasher with the
/// file's name and bytes added.
fn put_one(
  key key: Key,
  folder folder: String,
  entry entry: Entry,
  hasher hasher: crypto.Hasher,
) -> Result(crypto.Hasher, LoadError) {
  use bytes <- result.try(
    simplifile.read_bits(folder <> "/" <> entry.file <> ".tbl")
    |> result.map_error(TableFileUnreadable(entry.file, _)),
  )
  use Nil <- result.map(
    entry.put(bytes, key)
    |> result.map_error(TableFileInvalid(entry.table, _)),
  )
  hasher
  |> crypto.hash_chunk(<<entry.file:utf8, 0>>)
  |> crypto.hash_chunk(bytes)
}

fn first_missing_row(
  tables: Tables,
  requirements: List(Requirement),
) -> Result(Nil, LoadError) {
  case requirements {
    [] -> Ok(Nil)
    [requirement, ..rest] ->
      case requirement.missing(tables) {
        [id, ..] ->
          Error(RowMissing(
            from_table: requirement.from_table,
            column: requirement.column,
            to_table: requirement.to_table,
            id:,
          ))
        [] -> first_missing_row(tables, rest)
      }
  }
}

/// Erases the terms of one load.
pub fn unload(tables: Tables) -> Nil {
  list.each(tables.tables, fn(table) { erase_term(#(tables.key, table)) })
}

/// The row with an id in the named table, or an error when it has none. The
/// generated module of the table gives `row` its type.
pub fn row(
  tables tables: Tables,
  table table: String,
  id id: Int,
) -> Result(row, Nil) {
  tbl_file.row(get_term(#(tables.key, table)), id)
}

/// Every row of the named table, in id order.
pub fn rows(tables tables: Tables, table table: String) -> List(row) {
  tbl_file.rows(get_term(#(tables.key, table)))
}

/// Writes a table's term.
@external(erlang, "store_ffi", "put")
fn put_term(key: #(Key, String), table: tbl_file.Table(row)) -> Nil

/// A table's term. The type of its rows is the caller's to name.
@external(erlang, "persistent_term", "get")
fn get_term(key: #(Key, String)) -> tbl_file.Table(row)

/// Erases a table's term.
@external(erlang, "store_ffi", "erase")
fn erase_term(key: #(Key, String)) -> Nil
