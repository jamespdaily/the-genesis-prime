//// A game table file of the client (`DB/<name>.tbl`): its header, column
//// table, records, string data and id lookup, read as the client's loader
//// reads them (fact file, `game_table.file`), and turned into rows by the
//// decoder that is generated for each table. Column types are the client's
//// type codes (`game_table.column_type`) and a table is only accepted when it
//// equals the schema generated from its own header (`game_table.schema`).

/// The type of a column, by the client's type code.
pub type ColumnType {
  /// Type code 3: a 32-bit integer.
  Integer32
  /// Type code 4: a 32-bit IEEE float.
  Float32
  /// Type code 11: a boolean held in 4 bytes, 0 or 1.
  Boolean32
  /// Type code 20: a 64-bit integer.
  Integer64
  /// Type code 130: a string, held as an 8-byte offset to UTF-16 text.
  Utf16Text
}

/// A column: its name in the client and its type.
pub type Column {
  Column(name: String, column_type: ColumnType)
}

/// What a generated table module expects of its file: the table's name in the
/// client, the name of the file that holds it, the record size and each
/// column, in order.
pub type Schema {
  Schema(table: String, file: String, record_size: Int, columns: List(Column))
}

/// What a file's header and column table say about its table.
pub type Description {
  Description(
    table: String,
    record_size: Int,
    record_count: Int,
    columns: List(Column),
  )
}

/// A column placed in the record: a 4-byte field at the next multiple of 4, an
/// 8-byte field (a 64-bit integer or a string offset) at the next multiple of 8.
pub type Field {
  Field(column: Column, offset: Int)
}

/// A part of the file that must lie inside it.
pub type Part {
  TableName
  ColumnTable
  ColumnName(column: Int)
  RecordBlock
  Lookup
}

/// Why a file is not accepted as a table.
pub type FileError {
  /// The bytes end inside the 0x60-byte header.
  TooShort
  /// The first 4 bytes are not the signature 0x4454424C.
  BadSignature
  /// A part's range lies outside the file.
  OutsideFile(part: Part)
  /// A column's type code is not one the client's tables use.
  UnknownColumnType(column: String, code: Int)
  /// The file holds another table than the schema's.
  TableNameDiffers(expected: String, found: String)
  /// The file's record size is not the schema's.
  RecordSizeDiffers(expected: Int, found: Int)
  /// The file has another number of columns than the schema.
  ColumnCountDiffers(expected: Int, found: Int)
  /// The column at a position has another name or type than the schema's.
  ColumnDiffers(position: Int, expected: Column, found: Column)
  /// The lookup entry of an id names a row past the record count.
  LookupPointsOutside(id: Int, row: Int)
  /// The record the lookup names for an id holds another id.
  LookupDisagrees(id: Int, found: Int)
  /// The lookup names fewer records than the header counts.
  RecordsNotInLookup(expected: Int, found: Int)
  /// A record could not be decoded.
  BadRecord(row: Int, error: RecordError)
}

/// Why one record could not be decoded.
pub type RecordError {
  /// The record is shorter than its fields, or a float is not a number.
  NotARecord
  /// A string's offset is not inside the string data.
  TextOutsideStrings(column: String, offset: Int)
  /// A string's bytes are not UTF-16 text ending in a zero character.
  TextNotUtf16(column: String)
  /// A boolean column holds a value other than 0 or 1.
  NotABoolean(column: String, value: Int)
}

/// The string data of a file: the bytes after its records, which a string
/// column's offset points into.
pub opaque type Strings {
  Strings(bytes: BitArray, first_offset: Int)
}

/// A table's rows in one tuple, the row of id `n` at element `n + 1`, and
/// `nil` at an id that has no row.
pub type Table(row)

/// Reads the header and column table of a file, without checking it against a
/// schema; the generator reads every table this way.
pub fn describe(bytes: BitArray) -> Result(Description, FileError) {
  todo
}

/// Places each column in the record and gives the record size: the end of the
/// last field, rounded up to 8 when the record holds an 8-byte field, else to 4.
pub fn layout(columns: List(Column)) -> #(List(Field), Int) {
  todo
}

/// Checks the file against the schema, then decodes every record the lookup
/// names with `decode`, and checks that each record holds the id the lookup
/// gives it. `id` reads a row's id.
pub fn read(
  bytes bytes: BitArray,
  schema schema: Schema,
  decode decode: fn(BitArray, Strings) -> Result(row, RecordError),
  id id: fn(row) -> Int,
) -> Result(Table(row), FileError) {
  todo
}

/// The text a string column's offset points to, as UTF-8.
pub fn text(
  strings: Strings,
  offset: Int,
  column: String,
) -> Result(String, RecordError) {
  todo
}

/// A boolean column's value: 0 or 1.
pub fn boolean(value: Int, column: String) -> Result(Bool, RecordError) {
  todo
}

/// The row of an id, or an error when the id has no row.
pub fn row(table: Table(row), id: Int) -> Result(row, Nil) {
  todo
}

/// Every row, in id order.
pub fn rows(table: Table(row)) -> List(row) {
  todo
}
