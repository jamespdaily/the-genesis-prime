//// The client's own rows, as the server's tables.
////
//// - **`shared()`** is the server's tables loaded from the rows with the
////   server's own requirements and derivations. Never unload it.
//// - **`changed` and `added`** run a body on a copy of the rows with a row's
////   cells changed, or one row added that starts as a copy of a real row. The
////   copy is unloaded afterwards.
//// - **`root(table, id)`** names a row the rows are guaranteed to hold.

import database_support
import genesis_prime/fixture_rows
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table_rows
import gleam/bool
import gleam/dict.{type Dict}
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/result
import owned_key
import planted_table.{type Cell}
import simplifile

/// The folder the rows are kept in.
pub const folder = fixture_rows.fixture_folder

/// Every table's rows by the table's name: one list of cells per row, in the
/// table's column order.
pub type Rows =
  Dict(String, List(List(Cell)))

/// Why the rows, or an edit of them, were refused.
pub type Refusal {
  /// A table's rows cannot be read.
  Unreadable(table: String, path: String)
  /// A table's text is not rows of the table.
  Malformed(fixture_rows.TextRefusal)
  /// An edit names a table the rows do not include.
  NoTable(table: String)
  /// An edit names a column the table does not have.
  NoColumn(table: String, column: String)
  /// An edit names a row the table does not hold.
  NoRow(table: String, id: Int)
  /// An added row, or an edit of the ID column, names an id the table already
  /// holds.
  RowHeld(table: String, id: Int)
  /// An id that is not a root.
  NotARoot(table: String, id: Int)
}

/// What a refusal says, with the fix where there is one.
pub fn describe(refusal: Refusal) -> String {
  case refusal {
    Unreadable(table:, path:) ->
      "the fixture's file of " <> table <> " cannot be read: " <> path
    Malformed(refusal) -> fixture_rows.describe_text(refusal)
    NoTable(table:) -> "the fixture holds no table " <> table
    NoColumn(table:, column:) ->
      "the table " <> table <> " has no column " <> column
    NoRow(table:, id:) ->
      "the fixture holds no row " <> int.to_string(id) <> " of " <> table
    RowHeld(table:, id:) ->
      "the table "
      <> table
      <> " already holds a row "
      <> int.to_string(id)
      <> ": a row needs an id of its own"
    NotARoot(table:, id:) ->
      table
      <> " "
      <> int.to_string(id)
      <> " is not a root of the fixture: add a line for it to "
      <> folder
      <> "/roots.tsv and run `gleam run -m genesis_prime/fixture_rows`"
  }
}

// ---------------------------------------------------------------- reading

/// The cell a value of the client's table is written back as.
fn planted(cell: table_rows.Cell) -> Cell {
  case cell.value {
    table_rows.Integer32(number) | table_rows.Integer64(number) ->
      planted_table.Integer(number)
    table_rows.Float32(value:, ..) -> planted_table.Float(value)
    table_rows.Boolean(value) -> planted_table.Boolean(value)
    table_rows.Text(text) -> planted_table.Text(text)
  }
}

/// The rows of a table's text, read against the schema's columns.
pub fn parse_table(
  schema schema: tbl_file.Schema,
  text text: String,
) -> Result(List(List(Cell)), Refusal) {
  fixture_rows.parse_table(schema:, text:)
  |> result.map(list.map(_, list.map(_, planted)))
  |> result.map_error(Malformed)
}

/// The rows read from a folder.
pub fn read_folder(folder: String) -> Result(Rows, Refusal) {
  schemas()
  |> list.try_map(fn(schema) {
    let path = folder <> "/" <> schema.file <> ".tsv"
    use text <- result.try(
      simplifile.read(path)
      |> result.replace_error(Unreadable(table: schema.table, path:)),
    )
    use rows <- result.map(parse_table(schema:, text:))
    #(schema.table, rows)
  })
  |> result.map(dict.from_list)
}

/// The schema of each table the server loads, in the order of its entries.
pub fn schemas() -> List(tbl_file.Schema) {
  list.map(server_table.entries(), store.schema)
}

fn schema_of(table: String) -> Result(tbl_file.Schema, Refusal) {
  list.find(schemas(), fn(schema) { schema.table == table })
  |> result.replace_error(NoTable(table:))
}

// ---------------------------------------------------------------- roots

/// The roots: the rows the rows are guaranteed to hold.
pub fn roots() -> List(fixture_rows.Root) {
  let assert Ok(text) = simplifile.read(folder <> "/roots.tsv")
    as "the fixture's roots.tsv cannot be read"
  case fixture_rows.parse_roots(text) {
    Ok(roots) -> roots
    Error(refusal) -> panic as fixture_rows.describe(refusal)
  }
}

/// The id of a root, or why the row is not one.
pub fn check_root(
  roots roots: List(fixture_rows.Root),
  table table: String,
  id id: Int,
) -> Result(Int, Refusal) {
  use <- bool.guard(
    when: !list.any(roots, fn(root) { root.table == table && root.id == id }),
    return: Error(NotARoot(table:, id:)),
  )
  Ok(id)
}

/// The id of a row that is a root, so the rows hold it. A row that is not a
/// root stops the test with the fix.
pub fn root(table table: String, id id: Int) -> Int {
  case check_root(roots: roots(), table:, id:) {
    Ok(id) -> id
    Error(refusal) -> panic as describe(refusal)
  }
}

// ---------------------------------------------------------------- loading

/// Loads the rows as the server's tables under this key, with the server's own
/// requirements and derivations.
pub fn load(
  rows wanted: Rows,
  under key: reference.Reference,
) -> Result(store.Tables, store.LoadError) {
  let committed = rows()
  let files =
    list.zip(schemas(), committed_files())
    |> list.map(fn(held) {
      let #(schema, committed_file) = held
      let table_rows = rows_of(rows: wanted, schema:)
      case table_rows == rows_of(rows: committed, schema:) {
        True -> committed_file
        False -> planted_table.file(schema:, rows: table_rows)
      }
    })
  use folder <- planted_table.in_folder(files)
  server_table.load_under(under: key, from: folder)
}

/// The file of each server table made from the committed rows, in the order of
/// `schemas`, made once: a load that edits one table writes the other tables'
/// files from here instead of making them again.
fn committed_files() -> List(#(String, BitArray)) {
  database_support.once("fixture_tables_files", fn() {
    let committed = rows()
    list.map(schemas(), fn(schema) {
      planted_table.file(schema:, rows: rows_of(rows: committed, schema:))
    })
  })
}

fn loaded(rows: Rows, key: reference.Reference) -> store.Tables {
  case load(rows:, under: key) {
    Ok(tables) -> tables
    Error(error) ->
      panic as { "the fixture's tables did not load: " <> store.describe(error) }
  }
}

/// The key the shared load is stored under.
pub fn shared_key() -> reference.Reference {
  database_support.once("fixture_tables_key", reference.new)
}

/// The server's tables from the rows, loaded once, with the server's own
/// requirements and derivations. Never unload them.
pub fn shared() -> store.Tables {
  database_support.once("fixture_tables", fn() { loaded(rows(), shared_key()) })
}

/// The rows, read once. They are held packed and unpacked at each call, which
/// keeps the test VM's literal area small.
pub fn rows() -> Rows {
  unpack(
    database_support.once("fixture_tables_rows", fn() {
      case read_folder(folder) {
        Ok(rows) -> pack(rows)
        Error(refusal) -> panic as describe(refusal)
      }
    }),
  )
}

@external(erlang, "fixture_tables_ffi", "pack")
fn pack(rows: Rows) -> BitArray

@external(erlang, "fixture_tables_ffi", "unpack")
fn unpack(packed: BitArray) -> Rows

// ---------------------------------------------------------------- edits

/// The index of a column of the table.
fn column_index(
  schema schema: tbl_file.Schema,
  column column: String,
) -> Result(Int, Refusal) {
  list.index_map(schema.columns, fn(held, index) { #(held.name, index) })
  |> list.key_find(column)
  |> result.replace_error(NoColumn(table: schema.table, column:))
}

fn id_of(row row: List(Cell)) -> Int {
  case row {
    [planted_table.Integer(id), ..] -> id
    _ -> panic as "a fixture row holds its id first"
  }
}

/// The row with the cells of the named columns replaced.
fn with_cells(
  schema schema: tbl_file.Schema,
  row row: List(Cell),
  with changes: List(#(String, Cell)),
) -> Result(List(Cell), Refusal) {
  use indexed <- result.map(
    list.try_map(changes, fn(change) {
      column_index(schema:, column: change.0)
      |> result.map(fn(index) { #(index, change.1) })
    }),
  )
  list.index_map(row, fn(cell, index) {
    case list.key_find(indexed, index) {
      Ok(replacement) -> replacement
      Error(Nil) -> cell
    }
  })
}

fn rows_of(
  rows rows: Rows,
  schema schema: tbl_file.Schema,
) -> List(List(Cell)) {
  result.unwrap(dict.get(rows, schema.table), [])
}

fn row_of(
  rows rows: Rows,
  schema schema: tbl_file.Schema,
  id id: Int,
) -> Result(List(Cell), Refusal) {
  list.find(rows_of(rows:, schema:), fn(row) { id_of(row:) == id })
  |> result.replace_error(NoRow(table: schema.table, id:))
}

/// The rows with the cells of one row replaced: the names of the columns and
/// their new cells.
pub fn change(
  rows rows: Rows,
  table table: String,
  id id: Int,
  with changes: List(#(String, Cell)),
) -> Result(Rows, Refusal) {
  use schema <- result.try(schema_of(table))
  use row <- result.try(row_of(rows:, schema:, id:))
  use changed_row <- result.try(with_cells(schema:, row:, with: changes))
  let new_id = id_of(row: changed_row)
  use <- bool.guard(
    when: new_id != id && result.is_ok(row_of(rows:, schema:, id: new_id)),
    return: Error(RowHeld(table:, id: new_id)),
  )
  Ok(dict.insert(
    rows,
    table,
    list.map(rows_of(rows:, schema:), fn(held) {
      case id_of(row: held) == id {
        True -> changed_row
        False -> held
      }
    }),
  ))
}

/// The rows with one more row, `id`, which starts as a copy of `copy_of`
/// with the cells of the named columns replaced.
pub fn add(
  rows rows: Rows,
  table table: String,
  copy_of copy_of: Int,
  id id: Int,
  with changes: List(#(String, Cell)),
) -> Result(Rows, Refusal) {
  use schema <- result.try(schema_of(table))
  use row <- result.try(row_of(rows:, schema:, id: copy_of))
  use <- bool.guard(
    when: result.is_ok(row_of(rows:, schema:, id:)),
    return: Error(RowHeld(table:, id:)),
  )
  use new_row <- result.map(
    with_cells(schema:, row:, with: [
      #("ID", planted_table.Integer(id)),
      ..changes
    ]),
  )
  dict.insert(rows, table, list.append(rows_of(rows:, schema:), [new_row]))
}

/// Runs the body on these rows loaded under a key of their own and unloaded
/// afterwards, for a case that needs more than one edit (`change` and `add`
/// make them); the shared load is not touched.
pub fn on_rows(rows rows: Rows, body body: fn(store.Tables) -> a) -> a {
  on_rows_under(rows:, key: owned_key.new(), body:)
}

/// `on_rows` under a key the caller made. The tables are unloaded also when the
/// body crashes, so the failure that shows is the body's.
pub fn on_rows_under(
  rows rows: Rows,
  key key: reference.Reference,
  body body: fn(store.Tables) -> a,
) -> a {
  let tables = loaded(rows, key)
  after_body(fn() { body(tables) }, fn() { store.unload(tables) })
}

/// Runs the body, then the cleanup, also when the body crashes.
@external(erlang, "fixture_tables_ffi", "after_body")
fn after_body(body: fn() -> a, cleanup: fn() -> Nil) -> a

/// Runs the body on the tables with the cells of one row changed. Loaded under
/// a key of its own and unloaded afterwards; the shared load is not touched.
/// Stops the test when the table, id or column is not one, or when an edit of
/// the ID column gives the row an id the table holds.
pub fn changed(
  table table: String,
  id id: Int,
  with changes: List(#(String, Cell)),
  body body: fn(store.Tables) -> a,
) -> a {
  case change(rows: rows(), table:, id:, with: changes) {
    Ok(rows) -> on_rows(rows:, body:)
    Error(refusal) -> panic as describe(refusal)
  }
}

/// Runs the body on the tables with one row added, a copy of a row with the
/// cells named replaced. Loaded under a key of its own and unloaded afterwards.
/// Stops the test when the table, row or column is not one, or the id is held.
pub fn added(
  table table: String,
  copy_of copy_of: Int,
  id id: Int,
  with changes: List(#(String, Cell)),
  body body: fn(store.Tables) -> a,
) -> a {
  case add(rows: rows(), table:, copy_of:, id:, with: changes) {
    Ok(rows) -> on_rows(rows:, body:)
    Error(refusal) -> panic as describe(refusal)
  }
}
