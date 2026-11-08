//// The client's game tables as one plain value: a map of each table by its
//// name, each a tuple of its rows indexed by id, and a map of each derived value
//// by its name. A load reads each table's file, then checks that every row the
//// server requires exists, then builds each derived value. A load also digests
//// the files it read.
////
//// - **`read`** gives the value on the caller's heap, which a test of its own
////   tables and the content load use: nothing is stored, so there is nothing
////   to erase.
//// - **`load`** also stores the value in one persistent term under a key and
////   gives the stored copy, which the literal area holds: a process that holds
////   it holds no copy of its own, and a message that carries it copies nothing.
//// - **A stored value is never erased or replaced while held**, since that
////   copies the whole of it into each process that holds it: a key holds one
////   value for the life of the VM, a second load under it stops the caller, and
////   `unload` refuses.
//// - **An edit** (`edit`) makes the value of a test: each edited table becomes
////   a new tuple on the caller's heap, the others stay the stored tuples, and
////   the derived values are built again from the edited tables, or are missing
////   when none are asked for, so a stale derived value cannot be read.
//// - **A derived value** is built once from the loaded tables, after the
////   requirements hold, and kept in the value beside the tables, so every reader
////   takes it from the tables without building it again.
//// - **The server's key is fixed.** The server's tables are stored under
////   `ServerKey`, a constant the server writes once at start; the content
////   terms of the server are stored under it too. A test that loads under a key
////   takes one made for it.
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
import gleam/option.{type Option, None, Some}
import gleam/result
import simplifile

/// What the terms of a load are stored under.
pub opaque type Key {
  /// The server's own key, the same in every run.
  ServerKey
  /// A key made for one load.
  LoadKey(Reference)
}

/// The server's own key, under which the server's tables and the content tables
/// (genesis_prime/content/term) are stored.
pub fn server_key() -> Key {
  ServerKey
}

/// A key no other load has, for a load of a test or of the content tables.
pub fn new_key() -> Key {
  LoadKey(reference.new())
}

/// The name of a table's rows in a load, and the type of the table's rows:
/// `entry` reads the rows from a decoder of that type, and a read by the key
/// gives that type back.
///
/// The constructor is public because a Gleam constant cannot call a function,
/// so nothing stops a key from claiming a row type its table does not have:
/// the compiler holds the key's type to the decoder's only where `entry` takes
/// both. A key is therefore declared once, as a private constant, in the
/// module that owns its table, and no other module makes one.
pub type TableKey(row) {
  TableKey(name: String)
}

/// The name of a derived value in a load, and the type of the value:
/// `derivation` builds the value from a function of that type, and `derived`
/// gives that type back. It is a type of its own, kept apart from the tables',
/// so a derived value's key neither reads a table nor overwrites one of the
/// same name.
///
/// The constructor is public for the reason `TableKey`'s is, and the same rule
/// holds: a key is declared once, as a private constant, in the module that
/// owns its derivation.
pub type DerivedKey(value) {
  DerivedKey(name: String)
}

/// What is stored under a load's key: the whole value of its tables, or a
/// content table's value for one id.
type TermName {
  TablesTerm
  /// A content table's value for one id (genesis_prime/content/spawn).
  ContentTerm(table: String, id: Int)
}

/// The tables of a load and its derived values, as the value the term holds:
/// a map of each table by its name and a map of each derived value by its name.
type Value

/// The tables of one load. A process that reads a table is started with them,
/// and they hold the digest of the files they were read from.
pub opaque type Tables {
  Tables(
    value: Value,
    digest: String,
    /// The key the value is stored under, when it is stored.
    stored: Option(Key),
  )
}

/// One table the loader reads: the client's name, its file, and how to read
/// the file into a load's value. Each generated table module makes its own.
pub opaque type Entry {
  Entry(
    schema: tbl_file.Schema,
    table: String,
    file: String,
    put: fn(BitArray, Value) -> Result(Value, tbl_file.FileError),
    put_rows: fn(BitArray, Value) -> Result(Value, tbl_file.FileError),
    ids: fn(Tables) -> List(Int),
  )
}

/// A change to a table of a load, which `edit` makes on the caller's heap.
pub opaque type Edit {
  Edit(table: String, apply: fn(Value) -> Result(Value, tbl_file.FileError))
}

/// A value a rule reads of the loaded tables, built once when they load, from
/// its key and the function that builds it from the tables.
pub opaque type Derivation {
  Derivation(name: String, put: fn(Tables) -> Result(Tables, LoadError))
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
  /// A derived value could not be built from the loaded tables, for the reason
  /// its build gave.
  DerivationFailed(name: String, reason: String)
}

/// Why `unload` did nothing.
pub type UnloadRefused {
  /// The value is stored under its key, and erasing it would copy the whole of
  /// it into every process that holds it.
  ValueIsHeld
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
    DerivationFailed(name:, reason:) ->
      "the value " <> name <> " could not be built from the tables: " <> reason
  }
}

/// An entry for a generated table module. A table is read into the load's
/// value under the key's name, which is the table's (`schema.table`), and holds
/// the rows `decode` makes, which the key gives back to `row` and `rows`.
pub fn entry(
  key key: TableKey(row),
  schema schema: tbl_file.Schema,
  decode decode: fn(BitArray, tbl_file.Strings) ->
    Result(row, tbl_file.RecordError),
  id id: fn(row) -> Int,
) -> Entry {
  Entry(
    schema:,
    table: key.name,
    file: schema.file,
    put: fn(bytes, value) {
      tbl_file.read(bytes:, schema:, decode:, id:)
      |> result.map(put_table(value:, name: key.name, table: _))
    },
    put_rows: fn(bytes, value) {
      tbl_file.read_rows(bytes:, schema:, decode:, id:)
      |> result.map(fn(puts) {
        let table = case has_table(value:, name: key.name) {
          True -> tbl_file.patch(table_named(value:, name: key.name), puts, [])
          False -> tbl_file.from_rows(puts)
        }
        put_table(value:, name: key.name, table:)
      })
    },
    ids: fn(tables) { list.map(rows(tables:, key:), id) },
  )
}

/// A change that puts the rows of a table file into the table of the entry,
/// each replacing the row of its id or adding one; a table the load lacks
/// becomes the rows of the file. The file is checked as a load checks it.
pub fn put_rows(entry entry: Entry, bytes bytes: BitArray) -> Edit {
  Edit(table: entry.table, apply: entry.put_rows(bytes, _))
}

/// A change that replaces the table of the entry with the rows of a table file,
/// as a load reads it; the old table is not changed.
pub fn replace_rows(entry entry: Entry, bytes bytes: BitArray) -> Edit {
  Edit(table: entry.table, apply: entry.put(bytes, _))
}

/// A change that leaves the ids without a row in the table of the entry.
pub fn remove_rows(entry entry: Entry, ids ids: List(Int)) -> Edit {
  Edit(table: entry.table, apply: fn(value) {
    case has_table(value:, name: entry.table) {
      True ->
        Ok(put_table(
          value:,
          name: entry.table,
          table: tbl_file.patch(table_named(value:, name: entry.table), [], ids),
        ))
      False -> Ok(value)
    }
  })
}

/// A derived value of the tables under a key of its own, which is not the
/// name of a table of the client. `build` reads the loaded tables once, when
/// they load, and gives the value or the reason it cannot be built, which fails
/// the load; `derived` then gives the value.
pub fn derivation(
  key key: DerivedKey(value),
  build build: fn(Tables) -> Result(value, String),
) -> Derivation {
  Derivation(name: key.name, put: fn(tables) {
    case build(tables) {
      Ok(built) ->
        Ok(
          Tables(
            ..tables,
            value: put_derived(value: tables.value, name: key.name, built:),
          ),
        )
      Error(reason) -> Error(DerivationFailed(name: key.name, reason:))
    }
  })
}

/// The value a derivation built when these tables loaded; a key no derivation
/// of the load had stops the caller.
pub fn derived(tables tables: Tables, key key: DerivedKey(value)) -> value {
  derived_named(value: tables.value, name: key.name)
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

/// Reads every entry's file from the folder into one value on the caller's
/// heap, checks each requirement, then builds each derivation from the
/// tables. Stops at the first failure. Nothing is stored, so there is nothing
/// to unload.
pub fn read(
  from folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  use #(value, digest) <- result.try(read_value(folder:, entries:))
  check_and_derive(
    tables: Tables(value:, digest:, stored: None),
    requirements:,
    derivations:,
  )
}

/// `read`, then stores the value under `key` and gives the stored copy. A key
/// holds one load, and holds it for the life of the VM; a second load under it
/// stops the caller.
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
/// test that replays a recording loads once in its run, in a node of its own.
pub fn load_for_server(
  from folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  load_under(load: ServerKey, folder:, entries:, requirements:, derivations:)
}

fn load_under(
  load load: Key,
  folder folder: String,
  entries entries: List(Entry),
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  use tables <- result.map(read(
    from: folder,
    entries:,
    requirements:,
    derivations:,
  ))
  Tables(
    ..tables,
    value: keep(key: #(load, TablesTerm), value: tables.value),
    stored: Some(load),
  )
}

/// The tables of `tables` with more tables read from `folder`, each entry's
/// file, on the caller's heap: the tables a load reads that the rest of the
/// server does not (genesis_prime/content) are read this way, beside the ones
/// already loaded, and a read of any of them finds each. The stored value is
/// not touched.
pub fn read_more(
  over tables: Tables,
  from folder: String,
  entries entries: List(Entry),
) -> Result(Tables, LoadError) {
  use more <- result.map(
    read(from: folder, entries:, requirements: [], derivations: []),
  )
  merge(tables:, more:)
}

/// The tables of `tables` with the tables of `more` added, a table `more` holds
/// replacing the one of `tables`, on the caller's heap: no table is copied, so
/// a value stored apart from the other is read beside it without holding the
/// other's tables twice. The derived values and the digest are `tables`'s.
pub fn merge(tables tables: Tables, more more: Tables) -> Tables {
  Tables(
    ..tables,
    value: merge_tables(value: tables.value, more: more.value),
    stored: None,
  )
}

/// A new load of the tables with the changes made: each changed table is a new
/// tuple on the caller's heap, the other tables stay as they are, then each
/// requirement is checked and each derivation built from the changed tables.
/// The derived values of `tables` are not kept, so a value no derivation here
/// builds stops the caller that reads it. The stored value is not touched.
pub fn edit(
  tables tables: Tables,
  with edits: List(Edit),
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  use value <- result.try(
    list.try_fold(edits, tables.value, fn(value, edit) {
      edit.apply(value)
      |> result.map_error(TableFileInvalid(edit.table, _))
    }),
  )
  check_and_derive(
    tables: Tables(..tables, value: forget_derived(value), stored: None),
    requirements:,
    derivations:,
  )
}

/// Checks the requirements of the tables and then builds each derivation, in
/// the order given: a derivation that reads another's value comes after it.
fn check_and_derive(
  tables tables: Tables,
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  use Nil <- result.try(first_missing_row(tables, requirements))
  list.try_fold(derivations, tables, fn(tables, derivation) {
    derivation.put(tables)
  })
}

/// Reads each entry in turn into one value, giving it and the digest of the
/// files read, or the first error.
fn read_value(
  folder folder: String,
  entries entries: List(Entry),
) -> Result(#(Value, String), LoadError) {
  use #(value, hasher) <- result.map(
    list.try_fold(
      entries,
      #(empty(), crypto.new_hasher(crypto.Sha256)),
      fn(state, entry) { read_one(folder:, entry:, state:) },
    ),
  )
  #(value, bit_array.base16_encode(crypto.digest(hasher)))
}

/// Reads one entry's file and puts its table in the value, giving the hasher
/// with the file's name and bytes added.
fn read_one(
  folder folder: String,
  entry entry: Entry,
  state state: #(Value, crypto.Hasher),
) -> Result(#(Value, crypto.Hasher), LoadError) {
  use bytes <- result.try(
    simplifile.read_bits(folder <> "/" <> entry.file <> ".tbl")
    |> result.map_error(TableFileUnreadable(entry.file, _)),
  )
  use value <- result.map(
    entry.put(bytes, state.0)
    |> result.map_error(TableFileInvalid(entry.table, _)),
  )
  #(
    value,
    state.1
      |> crypto.hash_chunk(<<entry.file:utf8, 0>>)
      |> crypto.hash_chunk(bytes),
  )
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

/// Refuses to erase a stored value: erasing it would copy the whole of it into
/// every process that holds it. A value that is not stored has nothing to erase.
pub fn unload(tables: Tables) -> Result(Nil, UnloadRefused) {
  case tables.stored {
    Some(_) -> Error(ValueIsHeld)
    None -> Ok(Nil)
  }
}

/// The row with an id in the table the key names, or an error when it has
/// none.
pub fn row(
  tables tables: Tables,
  key key: TableKey(row),
  id id: Int,
) -> Result(row, Nil) {
  tbl_file.row(table_named(value: tables.value, name: key.name), id)
}

/// Every row of the table the key names, in id order.
pub fn rows(tables tables: Tables, key key: TableKey(row)) -> List(row) {
  tbl_file.rows(table_named(value: tables.value, name: key.name))
}

/// Writes a content table's value for one id (a world) under the key, once; a
/// content table keeps one value for each id, read by the maps and creatures of
/// the world and never queried during play (genesis_prime/content). Its module
/// gives `value` the type its reads expect.
pub fn put_content(
  key key: Key,
  table table: String,
  id id: Int,
  value value: value,
) -> Nil {
  let _ok = persistent_term_put(#(key, ContentTerm(table:, id:)), value)
  Nil
}

/// The value written under the key for the table's id. A reader of an id the
/// load wrote no value for crashes, never gets an empty one.
pub fn content(key key: Key, table table: String, id id: Int) -> value {
  persistent_term_get(#(key, ContentTerm(table:, id:)))
}

/// An empty value, with no table and no derived value.
@external(erlang, "genesis_prime_store_ffi", "empty")
fn empty() -> Value

@external(erlang, "genesis_prime_store_ffi", "put_table")
fn put_table_in(name: String, table: tbl_file.Table(row), value: Value) -> Value

fn put_table(
  value value: Value,
  name name: String,
  table table: tbl_file.Table(row),
) -> Value {
  put_table_in(name, table, value)
}

@external(erlang, "genesis_prime_store_ffi", "put_derived")
fn put_derived_in(name: String, built: built, value: Value) -> Value

fn put_derived(
  value value: Value,
  name name: String,
  built built: built,
) -> Value {
  put_derived_in(name, built, value)
}

@external(erlang, "genesis_prime_store_ffi", "has_table")
fn has_table_in(name: String, value: Value) -> Bool

fn has_table(value value: Value, name name: String) -> Bool {
  has_table_in(name, value)
}

/// The table a name gives: the table `entry` read from `decode`, whose rows are
/// the key's type. The callers give it the type of the key they were given.
@external(erlang, "genesis_prime_store_ffi", "table")
fn table_in(name: String, value: Value) -> tbl_file.Table(row)

fn table_named(value value: Value, name name: String) -> tbl_file.Table(row) {
  table_in(name, value)
}

@external(erlang, "genesis_prime_store_ffi", "derived")
fn derived_in(name: String, value: Value) -> built

fn derived_named(value value: Value, name name: String) -> built {
  derived_in(name, value)
}

@external(erlang, "genesis_prime_store_ffi", "forget_derived")
fn forget_derived(value: Value) -> Value

@external(erlang, "genesis_prime_store_ffi", "merge_tables")
fn merge_tables_of(value: Value, more: Value) -> Value

fn merge_tables(value value: Value, more more: Value) -> Value {
  merge_tables_of(value, more)
}

/// Stores the value under the key and gives the stored copy.
@external(erlang, "genesis_prime_store_ffi", "keep")
fn keep(key key: #(Key, TermName), value value: Value) -> Value

/// OTP's `persistent_term:put/2`, which returns the atom `ok`.
@external(erlang, "persistent_term", "put")
fn persistent_term_put(key: #(Key, TermName), value: value) -> Atom

/// OTP's `persistent_term:get/1`.
@external(erlang, "persistent_term", "get")
fn persistent_term_get(key: #(Key, TermName)) -> term
