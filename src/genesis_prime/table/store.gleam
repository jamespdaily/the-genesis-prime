//// The client's game tables as persistent terms: one term per table, a tuple
//// of its rows indexed by id, written once by `load` and never replaced. A
//// load reads each table's file, writes its term under a key made for that
//// load, then checks that every row the server requires exists; when anything
//// fails it erases what it wrote.

import genesis_prime/table/tbl_file
import gleam/erlang/reference.{type Reference}
import simplifile

/// The tables of one load. It holds the key their terms are stored under, so a
/// process that reads a table is started with it.
pub opaque type Tables {
  Tables(key: Reference, indexes: List(Int))
}

/// One table the loader reads: the client's name, its file, and how to read
/// the file and write its term under a load's key. Each generated table
/// module makes its own.
pub opaque type Entry {
  Entry(
    table: String,
    file: String,
    index: Int,
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

/// An entry for a generated table module. `index` is the table's number among
/// the loaded tables, the second part of its term's key.
pub fn entry(
  schema schema: tbl_file.Schema,
  index index: Int,
  decode decode: fn(BitArray, tbl_file.Strings) ->
    Result(row, tbl_file.RecordError),
  id id: fn(row) -> Int,
) -> Entry {
  todo
}

/// The client's name of the entry's table.
pub fn table(entry: Entry) -> String {
  todo
}

/// The name of the entry's file, without `.tbl`.
pub fn file(entry: Entry) -> String {
  todo
}

/// The ids that have a row in the entry's table, in order.
pub fn ids(entry: Entry, tables: Tables) -> List(Int) {
  todo
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
  todo
}

/// Erases the terms of one load.
pub fn unload(tables: Tables) -> Nil {
  todo
}

/// The row with an id in the table at `index`, or an error when it has none.
/// The generated module of the table gives `row` its type.
pub fn row(tables: Tables, index: Int, id: Int) -> Result(row, Nil) {
  todo
}

/// Every row of the table at `index`, in id order.
pub fn rows(tables: Tables, index: Int) -> List(row) {
  todo
}
