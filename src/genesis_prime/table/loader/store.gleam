//// The client's game tables as persistent terms: one term per table, a tuple
//// of its rows indexed by id, written once by `load` and never replaced. A
//// load reads each table's file, writes its term under its key, then checks
//// that every row the server requires exists, then builds each derived value;
//// when anything fails it erases what it wrote. A load also digests the files
//// it read.
////
//// - **A derived value** is built once from the loaded tables, after the
////   requirements hold, and stored as a term of its own under the same key, so
////   every reader takes it from the tables' key without building it again. It
////   is not part of the `Tables` value, which a rule's settings hold and a
////   recording's header writes.
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
import gleam/erlang/atom.{type Atom}
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/result
import simplifile

/// What a load's terms are stored under.
pub opaque type Load {
  /// The server's own key, the same in every run.
  ServerKey
  /// A key made for one load.
  LoadKey(Reference)
}

/// The name of one term of a load, a table's rows or a derived value, and the
/// type of what it holds: the load writes the term from a decoder or a build
/// function of that type (`entry`, `derivation`), and a read by the key gives
/// that type back, so a reader cannot name another one. A generated table
/// module and each derivation declare theirs once, as a constant.
pub type Key(value) {
  Key(name: String)
}

/// The tables of one load. It holds the key their terms are stored under, so a
/// process that reads a table is started with it, and the digest of the files
/// they were read from.
pub opaque type Tables {
  Tables(load: Load, tables: List(String), digest: String)
}

/// One table the loader reads: the client's name, its file, and how to read
/// the file and write its term under a load's key. Each generated table
/// module makes its own.
pub opaque type Entry {
  Entry(
    schema: tbl_file.Schema,
    table: String,
    file: String,
    put: fn(BitArray, Load) -> Result(Nil, tbl_file.FileError),
    ids: fn(Tables) -> List(Int),
  )
}

/// A value a rule reads of the loaded tables, built once when they load, from
/// its key and the function that builds it from the tables.
pub opaque type Derivation {
  Derivation(name: String, put: fn(Tables) -> Nil)
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
/// load and the key's name, and holds the rows `decode` makes, which the key
/// gives back to `row` and `rows`. The key's name is the table's
/// (`schema.table`).
pub fn entry(
  key key: Key(row),
  schema schema: tbl_file.Schema,
  decode decode: fn(BitArray, tbl_file.Strings) ->
    Result(row, tbl_file.RecordError),
  id id: fn(row) -> Int,
) -> Entry {
  Entry(
    schema:,
    table: key.name,
    file: schema.file,
    put: fn(bytes, load) {
      tbl_file.read(bytes:, schema:, decode:, id:)
      |> result.map(fn(table) { put_term(load:, name: key.name, term: table) })
    },
    ids: fn(tables) { list.map(rows(tables:, key:), id) },
  )
}

/// A derived value of the tables under a key of its own, which is not the
/// name of a table of the client. `build` reads the loaded tables once, when
/// they load; `derived` then gives its result.
pub fn derivation(
  key key: Key(value),
  build build: fn(Tables) -> value,
) -> Derivation {
  Derivation(name: key.name, put: fn(tables) {
    put_term(load: tables.load, name: key.name, term: build(tables))
  })
}

/// The value a derivation built when these tables loaded; a key no derivation
/// of the load had stops the caller.
pub fn derived(tables tables: Tables, key key: Key(value)) -> value {
  get_term(tables.load, key.name)
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
/// `key`, checks each requirement, then builds each derivation from the
/// tables. Stops at the first failure and erases the terms it wrote. A key is
/// used by one load.
pub fn load(
  under key: Reference,
  from folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  load_under(load: LoadKey(key), folder:, entries:, requirements:, derivations:)
}

/// `load` under the server's own key. The server loads once at start, and a
/// test that replays a recording loads once in its run; a second load under
/// this key replaces the terms of the first.
pub fn load_for_server(
  from folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  load_under(load: ServerKey, folder:, entries:, requirements:, derivations:)
}

fn load_under(
  load load: Load,
  folder folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  case
    put_each(
      load:,
      folder:,
      entries:,
      written: [],
      hasher: crypto.new_hasher(crypto.Sha256),
    )
  {
    Error(#(error, written)) -> {
      unload(with_derived_names(
        Tables(load:, tables: written, digest: ""),
        derivations,
      ))
      Error(error)
    }
    Ok(#(written, digest)) ->
      check_and_derive(
        tables: with_derived_names(
          Tables(load:, tables: written, digest:),
          derivations,
        ),
        requirements:,
        derivations:,
      )
  }
}

/// Checks the requirements of the written tables and then builds each
/// derivation, or erases everything the load wrote.
fn check_and_derive(
  tables tables: Tables,
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  case first_missing_row(tables, requirements) {
    Ok(Nil) -> {
      list.each(derivations, fn(derivation) { derivation.put(tables) })
      Ok(tables)
    }
    Error(error) -> {
      unload(tables)
      Error(error)
    }
  }
}

/// The tables with the derivations' names among the terms to erase, so a load
/// that fails also erases a derived value an earlier load under the same key
/// left, whose tables it has just replaced or erased.
fn with_derived_names(tables: Tables, derivations: List(Derivation)) -> Tables {
  Tables(
    ..tables,
    tables: list.append(
      list.map(derivations, fn(derivation) { derivation.name }),
      tables.tables,
    ),
  )
}

/// Reads and writes each entry in turn, giving the tables written and the
/// digest of the files read, or the first error with the tables written
/// before it.
fn put_each(
  load load: Load,
  folder folder: String,
  entries entries: List(Entry),
  written written: List(String),
  hasher hasher: crypto.Hasher,
) -> Result(#(List(String), String), #(LoadError, List(String))) {
  case entries {
    [] -> Ok(#(written, bit_array.base16_encode(crypto.digest(hasher))))
    [entry, ..rest] ->
      case put_one(load:, folder:, entry:, hasher:) {
        Ok(hasher) ->
          put_each(load:, folder:, entries: rest, hasher:, written: [
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
  load load: Load,
  folder folder: String,
  entry entry: Entry,
  hasher hasher: crypto.Hasher,
) -> Result(crypto.Hasher, LoadError) {
  use bytes <- result.try(
    simplifile.read_bits(folder <> "/" <> entry.file <> ".tbl")
    |> result.map_error(TableFileUnreadable(entry.file, _)),
  )
  use Nil <- result.map(
    entry.put(bytes, load)
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
  list.each(tables.tables, fn(name) { erase_term(#(tables.load, name)) })
}

/// The row with an id in the table the key names, or an error when it has
/// none.
pub fn row(
  tables tables: Tables,
  key key: Key(row),
  id id: Int,
) -> Result(row, Nil) {
  tbl_file.row(table_of(tables.load, key), id)
}

/// Every row of the table the key names, in id order.
pub fn rows(tables tables: Tables, key key: Key(row)) -> List(row) {
  tbl_file.rows(table_of(tables.load, key))
}

/// The table a key names: the term `entry` wrote from `decode`, whose rows are
/// the key's type.
fn table_of(load: Load, key: Key(row)) -> tbl_file.Table(row) {
  get_term(load, key.name)
}

/// Writes a term, a table or a derived value, under the load and a name.
fn put_term(load load: Load, name name: String, term term: term) -> Nil {
  let _ok = persistent_term_put(#(load, name), term)
  Nil
}

/// OTP's `persistent_term:put/2`, which returns the atom `ok`.
@external(erlang, "persistent_term", "put")
fn persistent_term_put(key: #(Load, String), value: value) -> Atom

/// The term under the load and a name. The callers, `table_of` and `derived`,
/// give it the type `entry` or `derivation` wrote under the name of the key
/// they were given.
fn get_term(load: Load, name: String) -> term {
  persistent_term_get(#(load, name))
}

/// OTP's `persistent_term:get/1`.
@external(erlang, "persistent_term", "get")
fn persistent_term_get(key: #(Load, String)) -> term

/// Erases a term, whether it was written or not.
fn erase_term(key: #(Load, String)) -> Nil {
  let _erased = persistent_term_erase(key)
  Nil
}

/// OTP's `persistent_term:erase/1`, which returns whether a term was erased.
@external(erlang, "persistent_term", "erase")
fn persistent_term_erase(key: #(Load, String)) -> Bool
