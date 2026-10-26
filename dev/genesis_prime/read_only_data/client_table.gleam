//// The shapes of the three client game tables the benchmark measures: the
//// three largest by file size (Creature2, Spell4 and Spline2Node), with the
//// row count, the column types and the string data size the client's files
//// have. Values are synthetic; only the shape is the client's.

import gleam/float
import gleam/int
import gleam/list

/// The type of one column, as the client's column table gives it.
pub type ColumnKind {
  /// Type 3, a 32-bit integer.
  Integer32
  /// Type 4, a 32-bit float.
  Float32
  /// Type 11, a boolean held in 4 bytes.
  Boolean32
  /// Type 20, a 64-bit integer.
  Integer64
  /// Type 130, a string: an offset to UTF-16 text in the string data.
  Utf16Text
}

/// `count` columns in a row, all of one type.
pub type ColumnRun {
  ColumnRun(kind: ColumnKind, count: Int)
}

/// The shape of one game table.
pub type ClientTable {
  ClientTable(
    /// The table's name in the client.
    name: String,
    /// Its record count.
    rows: Int,
    /// Its columns in file order, as runs of the same type; column 0 is the id.
    columns: List(ColumnRun),
    /// The bytes of string data after the records, whole table. Every string
    /// ends in a zero character, and an empty string is the zero character
    /// alone.
    string_data_bytes: Int,
  )
}

/// One value for each of the three measured tables, in the order of
/// `measured`.
pub type PerTable(value) {
  PerTable(creature2: value, spell4: value, spline2node: value)
}

/// Creature2: 56,369 records of 173 columns. Row and column counts and string
/// data size are the fact file's `game_tables.ClientData`; the order of the
/// column types is read from the column table of
/// ClientData/DB/Creature2.tbl, whose counts
/// are 165 of type 3, 7 of type 4 and 1 of type 130.
const creature2 =
  ClientTable(
    name: "Creature2",
    rows: 56_369,
    columns: [
      ColumnRun(Integer32, 2),
      ColumnRun(Utf16Text, 1),
      ColumnRun(Integer32, 10),
      ColumnRun(Float32, 1),
      ColumnRun(Integer32, 9),
      ColumnRun(Float32, 2),
      ColumnRun(Integer32, 61),
      ColumnRun(Float32, 3),
      ColumnRun(Integer32, 77),
      ColumnRun(Float32, 1),
      ColumnRun(Integer32, 6),
    ],
    string_data_bytes: 5_819_088,
  )

/// Spell4: 66,591 records of 104 columns. Row and column counts and string
/// data size are the fact file's `game_tables.ClientData`; the order of the
/// column types is read from the column table of
/// ClientData/DB/Spell4.tbl, whose counts are
/// 100 of type 3, 3 of type 4 and 1 of type 130.
const spell4 =
  ClientTable(
    name: "Spell4",
    rows: 66_591,
    columns: [
      ColumnRun(Integer32, 1),
      ColumnRun(Utf16Text, 1),
      ColumnRun(Integer32, 6),
      ColumnRun(Float32, 3),
      ColumnRun(Integer32, 93),
    ],
    string_data_bytes: 7_179_390,
  )

/// Spline2Node: 380,576 records of 14 columns and no strings. Row and column
/// counts are the fact file's `game_tables.ClientData`; the order of the
/// column types is read from the column table of
/// ClientData/DB/Spline2Node.tbl, whose
/// counts are 4 of type 3 and 10 of type 4.
const spline2node =
  ClientTable(
    name: "Spline2Node",
    rows: 380_576,
    columns: [
      ColumnRun(Integer32, 3),
      ColumnRun(Float32, 7),
      ColumnRun(Integer32, 1),
      ColumnRun(Float32, 3),
    ],
    string_data_bytes: 0,
  )

/// The three measured tables, in the order every `PerTable` and every table
/// index of the benchmark uses.
pub fn measured() -> PerTable(ClientTable) {
  PerTable(creature2:, spell4:, spline2node:)
}

/// The value for the table at `index` (0 Creature2, 1 Spell4, 2 Spline2Node).
/// Any other index is a bug in the benchmark and crashes it.
pub fn at(per_table per_table: PerTable(value), index index: Int) -> value {
  case index {
    0 -> per_table.creature2
    1 -> per_table.spell4
    2 -> per_table.spline2node
    _ -> panic as "a table index is 0, 1 or 2"
  }
}

/// Applies `change` to each table's value, in table order.
pub fn map(
  per_table: PerTable(value),
  change change: fn(value) -> other,
) -> PerTable(other) {
  PerTable(
    creature2: change(per_table.creature2),
    spell4: change(per_table.spell4),
    spline2node: change(per_table.spline2node),
  )
}

/// The values in table order, as a list.
pub fn to_list(per_table: PerTable(value)) -> List(value) {
  [per_table.creature2, per_table.spell4, per_table.spline2node]
}

/// The column types of one row, one entry per column, in file order.
pub fn kinds(table: ClientTable) -> List(ColumnKind) {
  list.flat_map(table.columns, fn(run) { list.repeat(run.kind, run.count) })
}

/// How many columns hold a string.
fn text_column_count(table: ClientTable) -> Int {
  list.fold(table.columns, 0, fn(count, run) {
    case run.kind {
      Utf16Text -> count + run.count
      Integer32 | Float32 | Boolean32 | Integer64 -> count
    }
  })
}

/// The bytes of one synthetic string: the table's string data size over its
/// rows and its string columns, rounded to the nearest even number so the text
/// is whole UTF-16 characters. 0 for a table with no string column.
pub fn average_text_bytes(table: ClientTable) -> Int {
  case text_column_count(table) {
    0 -> 0
    strings -> {
      let per_string =
        int.to_float(table.string_data_bytes)
        /. int.to_float(table.rows * strings)
      2 * float.round(per_string /. 2.0)
    }
  }
}
