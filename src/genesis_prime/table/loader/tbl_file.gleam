//// A game table file of the client (`DB/<name>.tbl`): its header, column
//// table, records, string data and id lookup, read as the client's loader
//// reads them (fact file, `game_table.file`), and turned into rows by the
//// decoder that is generated for each table. Column types are the client's
//// type codes (`game_table.column_type`) and a table is only accepted when it
//// equals the schema generated from its own header (`game_table.schema`).

import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string

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
  /// The table's name or a column's name is not UTF-16 text.
  NotText(part: Part)
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

const signature = 0x4454424C

const column_entry_size = 24

const no_row = 0xFFFFFFFF

/// The header's numbers, all counted from the end of the header.
type Header {
  Header(
    name_length: Int,
    name_offset: Int,
    record_size: Int,
    column_count: Int,
    column_offset: Int,
    record_count: Int,
    block_size: Int,
    block_offset: Int,
    lookup_count: Int,
    lookup_offset: Int,
  )
}

/// A file whose header and columns are read: the header, the bytes after it
/// that its offsets count from, and what it says about its table.
type Parsed {
  Parsed(header: Header, body: BitArray, description: Description)
}

/// Reads the header and column table of a file, without checking it against a
/// schema; the generator reads every table this way.
pub fn describe(bytes: BitArray) -> Result(Description, FileError) {
  use parsed <- result.map(parse(bytes))
  parsed.description
}

fn parse(bytes: BitArray) -> Result(Parsed, FileError) {
  case bytes {
    <<found:size(32)-little, _:bits>> if found != signature ->
      Error(BadSignature)
    <<
      _:size(32),
      _:size(32),
      name_length:size(64)-little,
      name_offset:size(64)-little,
      record_size:size(64)-little,
      column_count:size(64)-little,
      column_offset:size(64)-little,
      record_count:size(64)-little,
      block_size:size(64)-little,
      block_offset:size(64)-little,
      lookup_count:size(64)-little,
      lookup_offset:size(64)-little,
      _:size(64),
      body:bits,
    >> -> {
      let header =
        Header(
          name_length:,
          name_offset:,
          record_size:,
          column_count:,
          column_offset:,
          record_count:,
          block_size:,
          block_offset:,
          lookup_count:,
          lookup_offset:,
        )
      use table <- result.try(read_name(
        body:,
        at: header.name_offset,
        length: header.name_length,
        part: TableName,
      ))
      use columns <- result.try(read_columns(body, header))
      Ok(Parsed(
        header:,
        body:,
        description: Description(table:, record_size:, record_count:, columns:),
      ))
    }
    _ -> Error(TooShort)
  }
}

/// A part of the body: `length` bytes at `offset`.
fn slice(
  body body: BitArray,
  at offset: Int,
  length length: Int,
  part part: Part,
) -> Result(BitArray, FileError) {
  bit_array.slice(body, offset, length)
  |> result.replace_error(OutsideFile(part))
}

/// UTF-16 text of `length` characters, with its ending zero character, at
/// `offset` in the body; a length of 0 is an absent name.
fn read_name(
  body body: BitArray,
  at offset: Int,
  length length: Int,
  part part: Part,
) -> Result(String, FileError) {
  case length {
    0 -> Ok("")
    _ -> {
      use bytes <- result.try(slice(
        body:,
        at: offset,
        length: 2 * length,
        part:,
      ))
      utf16_text(bytes) |> result.replace_error(NotText(part))
    }
  }
}

fn read_columns(
  body: BitArray,
  header: Header,
) -> Result(List(Column), FileError) {
  use table <- result.try(slice(
    body:,
    at: header.column_offset,
    length: column_entry_size * header.column_count,
    part: ColumnTable,
  ))
  let names_start =
    header.column_offset + round_up(column_entry_size * header.column_count, 16)
  read_column_entries(
    body:,
    entries: table,
    names_start:,
    position: 0,
    columns: [],
  )
}

fn read_column_entries(
  body body: BitArray,
  entries entries: BitArray,
  names_start names_start: Int,
  position position: Int,
  columns columns: List(Column),
) -> Result(List(Column), FileError) {
  case entries {
    <<
      name_length:size(32)-little,
      _:size(32),
      name_offset:size(64)-little,
      type_code:size(16)-little,
      _:size(16),
      _:size(32),
      rest:bits,
    >> -> {
      use name <- result.try(read_name(
        body:,
        at: names_start + name_offset,
        length: name_length,
        part: ColumnName(position),
      ))
      case column_type_of(type_code) {
        Ok(column_type) ->
          read_column_entries(
            body:,
            entries: rest,
            names_start:,
            position: position + 1,
            columns: [Column(name:, column_type:), ..columns],
          )
        Error(Nil) -> Error(UnknownColumnType(column: name, code: type_code))
      }
    }
    _ -> Ok(list.reverse(columns))
  }
}

fn column_type_of(code: Int) -> Result(ColumnType, Nil) {
  case code {
    3 -> Ok(Integer32)
    4 -> Ok(Float32)
    11 -> Ok(Boolean32)
    20 -> Ok(Integer64)
    130 -> Ok(Utf16Text)
    _ -> Error(Nil)
  }
}

fn round_up(value: Int, multiple: Int) -> Int {
  { value + multiple - 1 } / multiple * multiple
}

fn field_size(column_type: ColumnType) -> Int {
  case column_type {
    Integer64 | Utf16Text -> 8
    Integer32 | Float32 | Boolean32 -> 4
  }
}

/// Places each column in the record and gives the record size: the end of the
/// last field, rounded up to 8 when the record holds an 8-byte field, else to 4.
pub fn layout(columns: List(Column)) -> #(List(Field), Int) {
  let #(fields, end, has_wide_field) =
    list.fold(columns, #([], 0, False), fn(state, column) {
      let #(fields, end, has_wide_field) = state
      let size = field_size(column.column_type)
      let offset = round_up(end, size)
      #(
        [Field(column:, offset:), ..fields],
        offset + size,
        has_wide_field || size == 8,
      )
    })
  let record_size = case has_wide_field {
    True -> round_up(end, 8)
    False -> round_up(end, 4)
  }
  #(list.reverse(fields), record_size)
}

/// The first difference between what the file says and the schema: the table's
/// name and each column's name ignoring case (`MatchGameTableSchema`
/// 0x1407c19f0), the column count, each column's type and the record size.
fn check_schema(found: Description, schema: Schema) -> Result(Nil, FileError) {
  let expected_count = list.length(schema.columns)
  let found_count = list.length(found.columns)
  case string.lowercase(found.table) == string.lowercase(schema.table) {
    False -> Error(TableNameDiffers(expected: schema.table, found: found.table))
    True ->
      case expected_count == found_count {
        False ->
          Error(ColumnCountDiffers(expected: expected_count, found: found_count))
        True -> {
          use _ <- result.try(check_columns(
            expected: schema.columns,
            found: found.columns,
            position: 0,
          ))
          case found.record_size == schema.record_size {
            True -> Ok(Nil)
            False ->
              Error(RecordSizeDiffers(
                expected: schema.record_size,
                found: found.record_size,
              ))
          }
        }
      }
  }
}

fn check_columns(
  expected expected: List(Column),
  found found: List(Column),
  position position: Int,
) -> Result(Nil, FileError) {
  case expected, found {
    [first_expected, ..more_expected], [first_found, ..more_found] ->
      case
        string.lowercase(first_expected.name)
        == string.lowercase(first_found.name)
        && first_expected.column_type == first_found.column_type
      {
        True ->
          check_columns(
            expected: more_expected,
            found: more_found,
            position: position + 1,
          )
        False ->
          Error(ColumnDiffers(
            position:,
            expected: first_expected,
            found: first_found,
          ))
      }
    [], _ | _, [] -> Ok(Nil)
  }
}

/// What the walk over the lookup needs.
type Reader(row) {
  Reader(
    records: BitArray,
    strings: Strings,
    record_size: Int,
    record_count: Int,
    decode: fn(BitArray, Strings) -> Result(row, RecordError),
    id: fn(row) -> Int,
  )
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
  use parsed <- result.try(parse(bytes))
  use _ <- result.try(check_schema(parsed.description, schema))
  let header = parsed.header
  let records_size = header.record_count * header.record_size
  use block <- result.try(slice(
    body: parsed.body,
    at: header.block_offset,
    length: header.block_size,
    part: RecordBlock,
  ))
  use records <- result.try(slice(
    body: block,
    at: 0,
    length: records_size,
    part: RecordBlock,
  ))
  use string_data <- result.try(slice(
    body: block,
    at: records_size,
    length: header.block_size - records_size,
    part: RecordBlock,
  ))
  use lookup <- result.try(slice(
    body: parsed.body,
    at: header.lookup_offset,
    length: 4 * header.lookup_count,
    part: Lookup,
  ))
  let reader =
    Reader(
      records:,
      strings: Strings(bytes: string_data, first_offset: records_size),
      record_size: header.record_size,
      record_count: header.record_count,
      decode:,
      id:,
    )
  use #(found, rows) <- result.try(
    walk(reader:, lookup:, id: 0, found: 0, rows: []),
  )
  case found == header.record_count {
    True -> Ok(table_of(list.reverse(rows)))
    False ->
      Error(RecordsNotInLookup(expected: header.record_count, found: found))
  }
}

/// Decodes the record each lookup entry names, for ids from `id`, collecting
/// the rows in reverse with a gap at each id that has none.
fn walk(
  reader reader: Reader(row),
  lookup lookup: BitArray,
  id id: Int,
  found found: Int,
  rows rows: List(row),
) -> Result(#(Int, List(row)), FileError) {
  case lookup {
    <<entry:size(32)-little, rest:bits>> if entry == no_row ->
      walk(reader:, lookup: rest, id: id + 1, found:, rows: [gap(), ..rows])
    <<entry:size(32)-little, rest:bits>> ->
      case read_row(reader:, entry:, id:) {
        Ok(row) ->
          walk(reader:, lookup: rest, id: id + 1, found: found + 1, rows: [
            row,
            ..rows
          ])
        Error(error) -> Error(error)
      }
    _ -> Ok(#(found, rows))
  }
}

/// The row of the record a lookup entry names, which must hold the id the
/// lookup gives it.
fn read_row(
  reader reader: Reader(row),
  entry entry: Int,
  id id: Int,
) -> Result(row, FileError) {
  use <- bool.guard(
    when: entry >= reader.record_count,
    return: Error(LookupPointsOutside(id:, row: entry)),
  )
  use record <- result.try(
    bit_array.slice(
      reader.records,
      entry * reader.record_size,
      reader.record_size,
    )
    |> result.replace_error(OutsideFile(RecordBlock)),
  )
  use row <- result.try(
    reader.decode(record, reader.strings)
    |> result.map_error(fn(error) { BadRecord(row: entry, error:) }),
  )
  case reader.id(row) == id {
    True -> Ok(row)
    False -> Error(LookupDisagrees(id:, found: reader.id(row)))
  }
}

/// The text a string column's offset points to, as UTF-8.
pub fn text(
  strings strings: Strings,
  at offset: Int,
  column column: String,
) -> Result(String, RecordError) {
  let relative = offset - strings.first_offset
  let size = bit_array.byte_size(strings.bytes)
  case relative < 0 || relative >= size {
    True -> Error(TextOutsideStrings(column:, offset:))
    False ->
      case bit_array.slice(strings.bytes, relative, size - relative) {
        Ok(rest) ->
          utf16_text(rest) |> result.replace_error(TextNotUtf16(column:))
        Error(Nil) -> Error(TextOutsideStrings(column:, offset:))
      }
  }
}

/// A boolean column's value: 0 or 1.
pub fn boolean(
  value value: Int,
  column column: String,
) -> Result(Bool, RecordError) {
  case value {
    0 -> Ok(False)
    1 -> Ok(True)
    _ -> Error(NotABoolean(column:, value:))
  }
}

/// The row of an id, or an error when the id has no row.
@external(erlang, "tbl_file_ffi", "row")
pub fn row(table: Table(row), id: Int) -> Result(row, Nil)

/// Every row, in id order.
@external(erlang, "tbl_file_ffi", "rows")
pub fn rows(table: Table(row)) -> List(row)

/// The UTF-8 form of the UTF-16 little-endian text at the start of the bytes,
/// up to its first zero character; an error when there is none or the text is
/// not valid UTF-16.
@external(erlang, "tbl_file_ffi", "utf16_text")
fn utf16_text(bytes: BitArray) -> Result(String, Nil)

/// What stands in a table's tuple where an id has no row.
@external(erlang, "tbl_file_ffi", "gap")
fn gap() -> row

/// Puts the rows, and the gaps among them, in one tuple.
@external(erlang, "tbl_file_ffi", "table_of")
fn table_of(rows: List(row)) -> Table(row)

/// A sentence that says why a file is not accepted as its table, for the
/// message the server stops with.
pub fn describe_error(error: FileError) -> String {
  case error {
    TooShort -> "it ends inside the header"
    BadSignature -> "it does not start with the table signature"
    OutsideFile(part:) -> "the " <> describe_part(part) <> " lies outside it"
    NotText(part:) -> "the " <> describe_part(part) <> " is not UTF-16 text"
    UnknownColumnType(column:, code:) ->
      "column "
      <> column
      <> " has the unknown type code "
      <> int.to_string(code)
    TableNameDiffers(expected:, found:) ->
      "it holds the table " <> found <> ", not " <> expected
    RecordSizeDiffers(expected:, found:) ->
      "its record size is "
      <> int.to_string(found)
      <> ", not "
      <> int.to_string(expected)
    ColumnCountDiffers(expected:, found:) ->
      "it has "
      <> int.to_string(found)
      <> " columns, not "
      <> int.to_string(expected)
    ColumnDiffers(position:, expected:, found:) ->
      "its column "
      <> int.to_string(position)
      <> " is "
      <> found.name
      <> ", not "
      <> expected.name
      <> ", or has another type"
    LookupPointsOutside(id:, row:) ->
      "the lookup of id "
      <> int.to_string(id)
      <> " names row "
      <> int.to_string(row)
      <> ", which is past the records"
    LookupDisagrees(id:, found:) ->
      "the lookup of id "
      <> int.to_string(id)
      <> " names a record that holds id "
      <> int.to_string(found)
    RecordsNotInLookup(expected:, found:) ->
      "the lookup names "
      <> int.to_string(found)
      <> " records, not "
      <> int.to_string(expected)
    BadRecord(row:, error: _) ->
      "record " <> int.to_string(row) <> " cannot be decoded"
  }
}

fn describe_part(part: Part) -> String {
  case part {
    TableName -> "table name"
    ColumnTable -> "column table"
    ColumnName(column:) -> "name of column " <> int.to_string(column)
    RecordBlock -> "record block"
    Lookup -> "lookup"
  }
}
