//// The shapes of the three client game tables the benchmark measures: the
//// three largest by file size (Creature2, Spell4 and Spline2Node), with the
//// row count, the column types and the string data size the client's files
//// have. Values are synthetic; only the shape is the client's.

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
/// column types is read from the column table of Creature2.tbl, whose counts
/// are 165 of type 3, 7 of type 4 and 1 of type 130.
pub const creature2 =
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
/// column types is read from the column table of Spell4.tbl, whose counts are
/// 100 of type 3, 3 of type 4 and 1 of type 130.
pub const spell4 =
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
/// column types is read from the column table of Spline2Node.tbl, whose
/// counts are 4 of type 3 and 10 of type 4.
pub const spline2node =
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
pub fn at(per_table: PerTable(value), index index: Int) -> value {
  todo as "body in the build commit"
}

/// Applies `change` to each table's value, in table order.
pub fn map(
  per_table: PerTable(value),
  change change: fn(value) -> other,
) -> PerTable(other) {
  todo as "body in the build commit"
}

/// The values in table order, as a list.
pub fn to_list(per_table: PerTable(value)) -> List(value) {
  todo as "body in the build commit"
}

/// The column types of one row, one entry per column, in file order.
pub fn kinds(table: ClientTable) -> List(ColumnKind) {
  todo as "body in the build commit"
}

/// How many columns hold a string.
pub fn text_column_count(table: ClientTable) -> Int {
  todo as "body in the build commit"
}

/// The bytes of one synthetic string: the table's string data size over its
/// rows and its string columns, rounded to the nearest even number so the text
/// is whole UTF-16 characters. 0 for a table with no string column.
pub fn average_text_bytes(table: ClientTable) -> Int {
  todo as "body in the build commit"
}
