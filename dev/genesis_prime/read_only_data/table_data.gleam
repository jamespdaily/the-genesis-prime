//// Synthetic rows in the shape of a client table, and the Erlang terms the
//// variants keep them in. A row is a tuple with one element per column, the
//// id in element 1; ids run from 1 to the row count with no gap. Integers,
//// floats and booleans are synthetic values of the column's type, and a string
//// is a binary of the table's average string length, different for every row.

import genesis_prime/read_only_data/client_table.{
  type ClientTable, type ColumnKind, type PerTable,
}

/// One row: a tuple of its columns, the id first.
pub type Row

/// A table's rows in one tuple: the row with id `n` is element `n`.
pub type Table

/// A table's rows in a map from id to row.
pub type RowMap

/// The rows of the three tables as the loader holds them before they are put
/// anywhere: a list for each table, in id order.
pub type Source =
  PerTable(List(Row))

/// Builds the rows of all three measured tables.
pub fn build_source() -> Source {
  client_table.map(client_table.measured(), build_rows)
}

/// Builds the synthetic rows of one table, ids 1 to its row count in order.
fn build_rows(table: ClientTable) -> List(Row) {
  build(
    client_table.kinds(table),
    client_table.average_text_bytes(table),
    table.rows,
  )
}

/// Puts a table's rows, ids from 1 with no gap, in one tuple.
@external(erlang, "read_only_data_ffi", "table_of")
pub fn table_of(rows: List(Row)) -> Table

/// Puts a table's rows in a map keyed by id.
@external(erlang, "read_only_data_ffi", "map_of")
pub fn map_of(rows: List(Row)) -> RowMap

/// The row with `id` in a tuple of rows. Crashes for an id outside the table.
@external(erlang, "read_only_data_ffi", "row_at")
pub fn row_at(table: Table, id: Int) -> Row

/// The row with `id` in a map of rows. Crashes for an id outside the table.
@external(erlang, "read_only_data_ffi", "row_in")
pub fn row_in(map: RowMap, id: Int) -> Row

/// The id of a row, its first element.
@external(erlang, "read_only_data_ffi", "id_of")
pub fn id_of(row: Row) -> Int

/// The Erlang helper that builds the rows: `kinds` are the column types in
/// order and `text_bytes` the bytes of every string.
@external(erlang, "read_only_data_ffi", "build_rows")
fn build(kinds: List(ColumnKind), text_bytes: Int, count: Int) -> List(Row)
