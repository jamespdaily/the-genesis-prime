//// The client's own rows, as the server's tables.
////
//// - **`shared()`** is the server's tables read from the rows with the
////   server's own requirements and derivations, stored for the run.
//// - **Content tables** are the tables only the content load reads. The rows
////   hold them whole or by their roots, `shared()` and `load` leave them out,
////   and `file` makes their file from the committed rows. Only the server's
////   tables can be edited: an edit of a content table is refused.
//// - **`changed` and `added`** run a body on the shared tables with a row's
////   cells changed, or one row added that starts as a copy of a real row. The
////   edit is built on the body's heap and gone with it.
//// - **`root(table, id)`** names a row the rows are guaranteed to hold.

import database_support
import genesis_prime/fixture_rows
import genesis_prime/message/float32
import genesis_prime/table/loader/derivation
import genesis_prime/table/loader/requirement
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table_rows
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set.{type Set}
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
  /// An edit names a table only the content load reads, so the edit would
  /// reach no load.
  ContentTable(table: String)
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
    ContentTable(table:) ->
      "the table "
      <> table
      <> " is read by the content load from the committed rows, so an edit of it would reach no load"
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

/// The schema of each table the server loads, in the order of its entries.
pub fn server_schemas() -> List(tbl_file.Schema) {
  list.map(server_table.entries(), store.schema)
}

/// The schema of each table the fixture holds: the server's, then the tables
/// only the content load reads (`server_table.content_entries`).
pub fn schemas() -> List(tbl_file.Schema) {
  list.append(
    server_schemas(),
    list.map(server_table.content_entries(), store.schema),
  )
}

fn schema_of(table: String) -> Result(tbl_file.Schema, Refusal) {
  list.find(schemas(), fn(schema) { schema.table == table })
  |> result.replace_error(NoTable(table:))
}

/// The schema of a table an edit reaches: one the server loads. A table only
/// the content load reads is refused, since the edit would reach no load.
fn editable_schema_of(table: String) -> Result(tbl_file.Schema, Refusal) {
  use schema <- result.try(schema_of(table))
  case list.any(server_schemas(), fn(held) { held.table == table }) {
    True -> Ok(schema)
    False -> Error(ContentTable(table:))
  }
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

/// The rows of one table the server loads, read once and alone: a test that
/// needs a few tables does not read the others.
pub fn table(table: String) -> Result(List(List(Cell)), Refusal) {
  use schema <- result.map(schema_of(table))
  database_support.once("fixture_table_" <> table, fn() {
    let path = folder <> "/" <> schema.file <> ".tsv"
    let read = {
      use text <- result.try(
        simplifile.read(path)
        |> result.replace_error(Unreadable(table: schema.table, path:)),
      )
      parse_table(schema:, text:)
    }
    case read {
      Ok(rows) -> rows
      Error(refusal) -> panic as describe(refusal)
    }
  })
}

/// The committed rows of the table `schema` describes, read once by `table`.
pub fn committed_rows(schema: tbl_file.Schema) -> List(List(Cell)) {
  let assert Ok(rows) = table(schema.table) as "the fixture holds the table"
  rows
}

/// The planted-folder file of the table `schema` describes, made of the
/// committed rows: for a folder that takes the table from the client whole.
pub fn file(schema: tbl_file.Schema) -> #(String, BitArray) {
  planted_table.file(schema, committed_rows(schema))
}

/// The `file` of every table the server loads, for a folder the server's load
/// reads.
pub fn server_files() -> List(#(String, BitArray)) {
  list.map(server_schemas(), file)
}

/// Every table's rows, each read once by `table`. The dict is built on the
/// caller's heap at each call and holds the stored rows themselves; storing it
/// as a persistent term would copy every table's rows into the literal area a
/// second time.
pub fn rows() -> Rows {
  list.map(schemas(), fn(schema) {
    let assert Ok(rows) = table(schema.table)
      as "a table the server loads is one the fixture holds"
    #(schema.table, rows)
  })
  |> dict.from_list
}

/// What the rows reach, worked out once and only by the tests that select rows
/// (`closure`, `reached`): the rows of a load alone do not need it.
fn reach() -> fixture_rows.Reach {
  database_support.once("fixture_tables_reach", fn() {
    let whole_path = folder <> "/" <> fixture_rows.whole_file <> ".tsv"
    let whole =
      simplifile.read(whole_path)
      |> result.map_error(fn(error) {
        fixture_rows.FileFailed(
          path: whole_path,
          reason: simplifile.describe_error(error),
        )
      })
      |> result.try(fixture_rows.parse_whole)
    let whole = case whole {
      Ok(whole) -> whole
      Error(refusal) -> panic as fixture_rows.describe(refusal)
    }
    let held =
      dict.map_values(rows(), fn(table, rows) {
        let assert Ok(schema) = list.find(schemas(), fn(s) { s.table == table })
          as "a fixture table is one the server loads"
        list.map(rows, client_cells(schema:, row: _))
      })
    case fixture_rows.reach_of(rows: held, whole:) {
      Ok(reach) -> reach
      Error(refusal) -> panic as fixture_rows.describe(refusal)
    }
  })
}

/// The rows of `rows` a load of them holds: the rows the roots reach, each row
/// the files do not hold as it is, the rows those reach, and the tables that go
/// in whole. A table the server does not load is kept whole.
pub fn reached(rows rows: Rows, roots roots: List(#(String, Int))) -> Rows {
  select(rows:, roots:, with: fixture_rows.reached)
}

/// The rows `reached` keeps, with the fixture's roots, the rows the server's
/// load reads, and the rows those reach.
pub fn closure(rows rows: Rows, roots given: List(#(String, Int))) -> Rows {
  let fixture_roots = list.map(roots(), fn(root) { #(root.table, root.id) })
  select(
    rows:,
    roots: list.append(given, fixture_roots),
    with: fixture_rows.closure_of,
  )
}

fn select(
  rows chosen: Rows,
  roots roots: List(#(String, Int)),
  with walk: fn(fixture_rows.Reach, List(#(String, Int))) ->
    Result(Dict(String, Set(Int)), fixture_rows.Refusal),
) -> Rows {
  let held = rows()
  let #(reach, edited) =
    list.fold(schemas(), #(reach(), []), fn(state, schema) {
      let #(reach, edited) = state
      let given = rows_of(rows: chosen, schema:)
      let kept = rows_of(rows: held, schema:)
      case given == kept {
        True -> state
        False -> #(
          fixture_rows.with_rows(
            reach:,
            table: schema.table,
            rows: list.map(given, client_cells(schema:, row: _)),
          ),
          list.append(edited, edited_ids(schema:, given:, kept:)),
        )
      }
    })
  let selected = case walk(reach, list.append(roots, edited)) {
    Ok(selected) -> selected
    Error(refusal) -> panic as fixture_rows.describe(refusal)
  }
  let loaded = list.map(schemas(), fn(schema) { schema.table })
  dict.map_values(chosen, fn(table, table_rows) {
    case list.contains(loaded, table), dict.get(selected, table) {
      False, _ -> table_rows
      True, Ok(ids) ->
        list.filter(table_rows, fn(row) { set.contains(ids, id_of(row:)) })
      True, Error(Nil) -> []
    }
  })
}

/// The ids of the rows of `given` that `kept` does not hold as they are.
fn edited_ids(
  schema schema: tbl_file.Schema,
  given given: List(List(Cell)),
  kept kept: List(List(Cell)),
) -> List(#(String, Int)) {
  let by_id = dict.from_list(list.map(kept, fn(row) { #(id_of(row:), row) }))
  list.filter_map(given, fn(row) {
    let id = id_of(row:)
    case dict.get(by_id, id) == Ok(row) {
      True -> Error(Nil)
      False -> Ok(#(schema.table, id))
    }
  })
}

/// A row as the client's table holds it.
fn client_cells(
  schema schema: tbl_file.Schema,
  row row: List(Cell),
) -> List(table_rows.Cell) {
  list.map2(schema.columns, row, fn(column, cell) {
    table_rows.Cell(column: column.name, value: case column.column_type, cell {
      tbl_file.Integer64, planted_table.Integer(number) ->
        table_rows.Integer64(number)
      _, planted_table.Integer(number) -> table_rows.Integer32(number)
      _, planted_table.Float(value) ->
        table_rows.Float32(value:, bits: float32.to_bits(value:))
      _, planted_table.Boolean(value) -> table_rows.Boolean(value)
      _, planted_table.Text(text) -> table_rows.Text(text)
      _, planted_table.TextAt(..) -> table_rows.Text("")
    })
  })
}

/// The server's tables read from the rows on the caller's heap, with the
/// server's own requirements and derivations. Nothing is stored.
pub fn read(rows rows: Rows) -> Result(store.Tables, store.LoadError) {
  let files =
    list.map(server_schemas(), fn(schema) {
      planted_table.file(schema:, rows: rows_of(rows:, schema:))
    })
  use folder <- planted_table.in_folder(files)
  server_table.read(from: folder)
}

/// The server's tables from the rows, read once and stored for the run, with the
/// server's own requirements and derivations. A test that needs other rows edits
/// them (`on_rows`, `changed`, `added`) on its own heap.
pub fn shared() -> store.Tables {
  database_support.once("fixture_tables", fn() {
    case read(rows: rows()) {
      Ok(tables) -> store.store_under(tables:)
      Error(error) ->
        panic as {
          "the fixture's tables did not load: " <> store.describe(error)
        }
    }
  })
}

/// The edits that turn the shared tables into the tables of `wanted`, for each
/// of these entries: the rows of `wanted` that differ from the fixture's are
/// put, the fixture's rows `wanted` lacks are removed, and a table the shared
/// tables lack is put whole, empty or not.
pub fn edits_to(
  rows wanted: Rows,
  entries entries: List(store.Entry),
) -> List(store.Edit) {
  let held = rows()
  let shared_tables = list.map(server_schemas(), fn(schema) { schema.table })
  list.flat_map(entries, fn(entry) {
    let schema = store.schema(entry)
    let wanted_rows = rows_of(rows: wanted, schema:)
    let kept_rows = rows_of(rows: held, schema:)
    let kept_by_id = by_id(kept_rows)
    let wanted_by_id = by_id(wanted_rows)
    let puts =
      list.filter(wanted_rows, fn(row) {
        dict.get(kept_by_id, id_of(row:)) != Ok(row)
      })
    let removes =
      list.filter_map(kept_rows, fn(row) {
        let id = id_of(row:)
        case dict.has_key(wanted_by_id, id) {
          True -> Error(Nil)
          False -> Ok(id)
        }
      })
    let lacks = !list.contains(shared_tables, schema.table)
    list.flatten([
      case puts, lacks {
        [], False -> []
        _, _ -> [
          store.put_rows(entry, { planted_table.file(schema:, rows: puts) }.1),
        ]
      },
      case removes {
        [] -> []
        _ -> [store.remove_rows(entry, ids: removes)]
      },
    ])
  })
}

fn by_id(rows: List(List(Cell))) -> Dict(Int, List(Cell)) {
  dict.from_list(list.map(rows, fn(row) { #(id_of(row:), row) }))
}

/// The shared tables edited into the tables of `wanted` (`edits_to`) for these
/// entries, then checked and derived from as given. The edit is built on the
/// caller's heap; the shared tables are not touched.
pub fn edited(
  rows wanted: Rows,
  entries entries: List(store.Entry),
  requirements requirements: List(store.Requirement),
  derivations derivations: List(store.Derivation),
) -> Result(store.Tables, store.LoadError) {
  store.edit(
    tables: shared(),
    with: edits_to(rows: wanted, entries:),
    requirements:,
    derivations:,
  )
}

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

/// The name of the table's id column, its first.
fn id_column(schema schema: tbl_file.Schema) -> String {
  case schema.columns {
    [first, ..] -> first.name
    [] -> panic as "a table holds its id column"
  }
}

fn id_of(row row: List(Cell)) -> Int {
  case row {
    [planted_table.Integer(id), ..] -> id
    _ -> panic as "a fixture row holds its id first"
  }
}

/// The ids of the committed rows of the table `schema` describes, in file
/// order.
pub fn committed_ids(schema: tbl_file.Schema) -> List(Int) {
  list.map(committed_rows(schema), fn(row) { id_of(row:) })
}

/// The row with the cells of the named columns replaced.
pub fn with_cells(
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
  use schema <- result.try(editable_schema_of(table))
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
  use schema <- result.try(editable_schema_of(table))
  use row <- result.try(row_of(rows:, schema:, id: copy_of))
  use <- bool.guard(
    when: result.is_ok(row_of(rows:, schema:, id:)),
    return: Error(RowHeld(table:, id:)),
  )
  use new_row <- result.map(
    with_cells(schema:, row:, with: [
      #(id_column(schema:), planted_table.Integer(id)),
      ..changes
    ]),
  )
  dict.insert(rows, table, list.append(rows_of(rows:, schema:), [new_row]))
}

/// The rows without the row `id` of the table, for a load that lacks a row the
/// server reads (the load's refusal, not a `changed` body, is the subject).
pub fn remove(
  rows rows: Rows,
  table table: String,
  id id: Int,
) -> Result(Rows, Refusal) {
  use schema <- result.try(editable_schema_of(table))
  use _ <- result.map(row_of(rows:, schema:, id:))
  dict.insert(
    rows,
    table,
    list.filter(rows_of(rows:, schema:), fn(held) { id_of(row: held) != id }),
  )
}

/// The shared tables edited into the tables of these rows, with every table
/// the server loads and its own requirements and derivations: the load's result,
/// for a case whose subject is a refusal of the rows (`on_rows` stops the test
/// on one).
pub fn load(rows rows: Rows) -> Result(store.Tables, store.LoadError) {
  edited(
    rows:,
    entries: server_table.entries(),
    requirements: requirement.all(),
    derivations: derivation.all(),
  )
}

/// Runs the body on the `closure` of these rows and roots, as an edit of the
/// shared tables on the body's heap, for a case that needs more than one edit
/// (`change` and `add` make them); the shared tables are not touched.
pub fn on_rows(
  rows rows: Rows,
  reaching roots: List(#(String, Int)),
  body body: fn(store.Tables) -> a,
) -> a {
  case load(rows: closure(rows:, roots:)) {
    Ok(tables) -> body(tables)
    Error(error) ->
      panic as { "the fixture's tables did not load: " <> store.describe(error) }
  }
}

/// Runs the body on the tables with the cells of one row changed, built on the
/// body's heap; the shared tables are not touched.
/// Stops the test when the table, id or column is not one, or when an edit of
/// the ID column gives the row an id the table holds.
pub fn changed(
  table table: String,
  id id: Int,
  with changes: List(#(String, Cell)),
  body body: fn(store.Tables) -> a,
) -> a {
  case change(rows: rows(), table:, id:, with: changes) {
    Ok(rows) -> on_rows(rows:, reaching: [], body:)
    Error(refusal) -> panic as describe(refusal)
  }
}

/// Runs the body on the tables with one row added, a copy of a row with the
/// cells named replaced, built on the body's heap.
/// Stops the test when the table, row or column is not one, or the id is held.
pub fn added(
  table table: String,
  copy_of copy_of: Int,
  id id: Int,
  with changes: List(#(String, Cell)),
  body body: fn(store.Tables) -> a,
) -> a {
  case add(rows: rows(), table:, copy_of:, id:, with: changes) {
    Ok(rows) -> on_rows(rows:, reaching: [], body:)
    Error(refusal) -> panic as describe(refusal)
  }
}
