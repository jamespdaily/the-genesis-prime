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
////   gives a handle to it: the `Tables` holds the key and the digest, never the
////   value, so a copy of it (a message that is not local, an ETS insert, a
////   process started with it as an argument, Ranch's protocol options) copies a
////   few words however large the tables are. A read takes the value from the
////   term, and the literal area holds it once.
//// - **A stored value is never erased or replaced while held**, since that
////   copies the whole of it into each process that holds it: a key holds one
////   value for the life of the VM, a second load under it stops the caller, and
////   `unload` refuses.
//// - **An edit** (`edit`) makes the value of a test: each edited table becomes
////   a new tuple in the edits the `Tables` holds on the caller's heap, the
////   others are still read from the stored value, and the derived values are
////   built again into the edits from the edited tables, or are missing when none
////   are asked for, so a stale derived value cannot be read.
//// - **A read** takes a table or a derived value from the edits when they hold
////   it, then from the stored value.
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

/// The term a stored value is under: the key of its load, and the name of what
/// the term holds.
type StoredKey =
  #(Key, TermName)

/// The tables of one load. A process that reads a table is started with them,
/// and they hold the digest of the files they were read from.
///
/// A load of the server or of a test's files stores its value and the `Tables`
/// is a handle: the term's key and no value of its own, so that a copy of it is
/// a few words. Tables read but not stored, and the edits of a test, hold their
/// value on the caller's heap in `edits`.
pub opaque type Tables {
  Tables(
    /// The stored values the tables are read from, in order, after the edits.
    stored: List(StoredKey),
    /// The stored values the derived values are read from, in order, after the
    /// edits.
    stored_derived: List(StoredKey),
    /// The tables and derived values that are not in a stored value.
    edits: Value,
    digest: String,
  )
}

/// One table the loader reads: the client's name, its file, and how to read
/// the file into a load's value. Each generated table module makes its own.
pub opaque type Entry {
  Entry(
    schema: tbl_file.Schema,
    table: String,
    file: String,
    put: fn(BitArray, Tables) -> Result(Tables, tbl_file.FileError),
    put_rows: fn(BitArray, Tables) -> Result(Tables, tbl_file.FileError),
    ids: fn(Tables) -> List(Int),
  )
}

/// A change to a table of a load, which `edit` makes on the caller's heap.
pub opaque type Edit {
  Edit(table: String, apply: fn(Tables) -> Result(Tables, tbl_file.FileError))
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
    put: fn(bytes, tables) {
      tbl_file.read(bytes:, schema:, decode:, id:)
      |> result.map(put_table(tables:, name: key.name, table: _))
    },
    put_rows: fn(bytes, tables) {
      tbl_file.read_rows(bytes:, schema:, decode:, id:)
      |> result.map(fn(puts) {
        let base = case find_table(tables:, name: key.name) {
          Ok(table) -> table
          Error(Nil) -> tbl_file.table_of([])
        }
        put_table(
          tables:,
          name: key.name,
          table: tbl_file.patch(base, puts, []),
        )
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
  Edit(table: entry.table, apply: fn(tables) {
    case find_table(tables:, name: entry.table) {
      Ok(table) ->
        Ok(put_table(
          tables:,
          name: entry.table,
          table: tbl_file.patch(table, [], ids),
        ))
      Error(Nil) -> Ok(tables)
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
            edits: put_derived(value: tables.edits, name: key.name, built:),
          ),
        )
      Error(reason) -> Error(DerivationFailed(name: key.name, reason:))
    }
  })
}

/// The value a derivation built when these tables loaded; a key no derivation
/// of the load had stops the caller.
pub fn derived(tables tables: Tables, key key: DerivedKey(value)) -> value {
  case find_derived_in(key.name, tables.stored_derived, tables.edits) {
    Ok(built) -> built
    Error(Nil) ->
      panic as { "no derived value " <> key.name <> " in the tables" }
  }
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
  use tables <- result.try(read_value(folder:, entries:))
  check_and_derive(tables:, requirements:, derivations:)
}

/// `read`, then stores the value under `key` and gives the handle to it. A key
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
  store_tables(tables:, load:)
}

/// The tables with the tables and derived values of their edits stored under
/// `key`, which gives the handle to them in place of the edits: the tables a
/// test builds once for the run (a read, a merge or an edit of the loaded
/// tables) are stored so that every test that gets them holds a handle. The
/// stored values the tables already read from are still read, after the ones
/// stored now. The key is new, and holds the value for the life of the VM.
pub fn store_under(tables tables: Tables) -> Tables {
  store_tables(tables:, load: new_key())
}

fn store_tables(tables tables: Tables, load load: Key) -> Tables {
  let stored = #(load, TablesTerm)
  put_stored(key: stored, value: tables.edits)
  Tables(
    stored: [stored, ..tables.stored],
    stored_derived: [stored, ..tables.stored_derived],
    edits: empty(),
    digest: tables.digest,
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
/// other's tables twice. The derived values and the digest are `tables`'s. A
/// table `tables` holds in its edits stays over one `more` stores.
pub fn merge(tables tables: Tables, more more: Tables) -> Tables {
  Tables(
    ..tables,
    stored: list.append(more.stored, tables.stored),
    edits: merge_tables(value: tables.edits, more: more.edits),
  )
}

/// A new load of the tables with the changes made: each changed table is a new
/// tuple in the edits on the caller's heap, the other tables stay as they are, then each
/// requirement is checked and each derivation built from the changed tables.
/// The derived values of `tables` are not kept, so a value no derivation here
/// builds stops the caller that reads it. The stored value is not touched.
pub fn edit(
  tables tables: Tables,
  with edits: List(Edit),
  requirements requirements: List(Requirement),
  derivations derivations: List(Derivation),
) -> Result(Tables, LoadError) {
  use edited <- result.try(
    list.try_fold(edits, tables, fn(tables, edit) {
      edit.apply(tables)
      |> result.map_error(TableFileInvalid(edit.table, _))
    }),
  )
  check_and_derive(
    tables: Tables(
      ..edited,
      stored_derived: [],
      edits: forget_derived(edited.edits),
    ),
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

/// Reads each entry in turn into tables of edits only, with the digest of the
/// files read, or the first error.
fn read_value(
  folder folder: String,
  entries entries: List(Entry),
) -> Result(Tables, LoadError) {
  use #(tables, hasher) <- result.map(
    list.try_fold(
      entries,
      #(
        Tables(stored: [], stored_derived: [], edits: empty(), digest: ""),
        crypto.new_hasher(crypto.Sha256),
      ),
      fn(state, entry) { read_one(folder:, entry:, state:) },
    ),
  )
  Tables(..tables, digest: bit_array.base16_encode(crypto.digest(hasher)))
}

/// Reads one entry's file and puts its table in the tables, giving the hasher
/// with the file's name and bytes added.
fn read_one(
  folder folder: String,
  entry entry: Entry,
  state state: #(Tables, crypto.Hasher),
) -> Result(#(Tables, crypto.Hasher), LoadError) {
  use bytes <- result.try(
    simplifile.read_bits(folder <> "/" <> entry.file <> ".tbl")
    |> result.map_error(TableFileUnreadable(entry.file, _)),
  )
  use tables <- result.map(
    entry.put(bytes, state.0)
    |> result.map_error(TableFileInvalid(entry.table, _)),
  )
  #(
    tables,
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
/// every process that holds it. Tables that read nothing from a stored value
/// have nothing to erase.
pub fn unload(tables: Tables) -> Result(Nil, UnloadRefused) {
  case tables.stored {
    [] -> Ok(Nil)
    [_, ..] -> Error(ValueIsHeld)
  }
}

/// The row with an id in the table the key names, or an error when it has
/// none.
pub fn row(
  tables tables: Tables,
  key key: TableKey(row),
  id id: Int,
) -> Result(row, Nil) {
  tbl_file.row(table_named(tables:, name: key.name), id)
}

/// Every row of the table the key names, in id order.
pub fn rows(tables tables: Tables, key key: TableKey(row)) -> List(row) {
  tbl_file.rows(table_named(tables:, name: key.name))
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

/// The tables with the table put in their edits, over any the stored values
/// hold of the name.
fn put_table(
  tables tables: Tables,
  name name: String,
  table table: tbl_file.Table(row),
) -> Tables {
  Tables(..tables, edits: put_table_in(name, table, tables.edits))
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

/// The table of a name: the edits' first, then each stored value's in order.
@external(erlang, "genesis_prime_store_ffi", "find_table")
fn find_table_in(
  name: String,
  stored: List(StoredKey),
  edits: Value,
) -> Result(tbl_file.Table(row), Nil)

fn find_table(
  tables tables: Tables,
  name name: String,
) -> Result(tbl_file.Table(row), Nil) {
  find_table_in(name, tables.stored, tables.edits)
}

/// The table `entry` read from `decode`, whose rows are the key's type. The
/// callers give it the type of the key they were given; a name the load has no
/// table for stops the caller.
fn table_named(
  tables tables: Tables,
  name name: String,
) -> tbl_file.Table(row) {
  case find_table(tables:, name:) {
    Ok(table) -> table
    Error(Nil) -> panic as { "no table " <> name <> " in the tables" }
  }
}

/// The derived value of a name: the edits' first, then each stored value's in
/// order.
@external(erlang, "genesis_prime_store_ffi", "find_derived")
fn find_derived_in(
  name: String,
  stored: List(StoredKey),
  edits: Value,
) -> Result(built, Nil)

@external(erlang, "genesis_prime_store_ffi", "forget_derived")
fn forget_derived(value: Value) -> Value

@external(erlang, "genesis_prime_store_ffi", "merge_tables")
fn merge_tables_of(value: Value, more: Value) -> Value

fn merge_tables(value value: Value, more more: Value) -> Value {
  merge_tables_of(value, more)
}

/// Stores the value under the key, once.
@external(erlang, "genesis_prime_store_ffi", "keep")
fn put_stored(key key: StoredKey, value value: Value) -> Nil

/// OTP's `persistent_term:put/2`, which returns the atom `ok`.
@external(erlang, "persistent_term", "put")
fn persistent_term_put(key: #(Key, TermName), value: value) -> Atom

/// OTP's `persistent_term:get/1`.
@external(erlang, "persistent_term", "get")
fn persistent_term_get(key: #(Key, TermName)) -> term
