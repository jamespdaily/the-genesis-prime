//// The client's game tables as persistent terms: one term per table, a tuple
//// of its rows indexed by id, written once by `load` and never replaced. A
//// load reads each table's file, writes its term under a key made for that
//// load, then checks that every row the server requires exists; when anything
//// fails it erases what it wrote.

import genesis_prime/table/loader/tbl_file
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/result
import simplifile

/// The tables of one load. It holds the key their terms are stored under, so a
/// process that reads a table is started with it.
pub opaque type Tables {
  Tables(key: Reference, tables: List(String))
}

/// One table the loader reads: the client's name, its file, and how to read
/// the file and write its term under a load's key. Each generated table
/// module makes its own.
pub opaque type Entry {
  Entry(
    schema: tbl_file.Schema,
    table: String,
    file: String,
    put: fn(BitArray, Reference) -> Result(Nil, tbl_file.FileError),
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
  case put_each(key:, folder:, entries:, written: []) {
    Error(#(error, written)) -> {
      unload(Tables(key:, tables: written))
      Error(error)
    }
    Ok(written) -> {
      let tables = Tables(key:, tables: written)
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

/// Reads and writes each entry in turn, giving the tables written, or the
/// first error with the tables written before it.
fn put_each(
  key key: Reference,
  folder folder: String,
  entries entries: List(Entry),
  written written: List(String),
) -> Result(List(String), #(LoadError, List(String))) {
  case entries {
    [] -> Ok(written)
    [entry, ..rest] ->
      case put_one(key:, folder:, entry:) {
        Ok(Nil) ->
          put_each(key:, folder:, entries: rest, written: [
            entry.table,
            ..written
          ])
        Error(error) -> Error(#(error, written))
      }
  }
}

fn put_one(
  key key: Reference,
  folder folder: String,
  entry entry: Entry,
) -> Result(Nil, LoadError) {
  use bytes <- result.try(
    simplifile.read_bits(folder <> "/" <> entry.file <> ".tbl")
    |> result.map_error(TableFileUnreadable(entry.file, _)),
  )
  entry.put(bytes, key)
  |> result.map_error(TableFileInvalid(entry.table, _))
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
fn put_term(key: #(Reference, String), table: tbl_file.Table(row)) -> Nil

/// A table's term. The type of its rows is the caller's to name.
@external(erlang, "persistent_term", "get")
fn get_term(key: #(Reference, String)) -> tbl_file.Table(row)

/// Erases a table's term.
@external(erlang, "store_ffi", "erase")
fn erase_term(key: #(Reference, String)) -> Nil
