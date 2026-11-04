//// Prints the rows of one of the client's game tables, read with the server's
//// own table reader (`genesis_prime/table/loader/tbl_file`), for the decoders
//// that need to see what a table holds.
////
//// `gleam run -m genesis_prime/table_rows -- <Table> [<id>... | <column>=<value> |
//// --columns]` reads `<Table>.tbl` from the extracted tables folder
//// (`GENESIS_TABLE_DIR`, else `GENESIS_HOME`/tables, else
//// `~/.genesis-prime/tables`).
////
//// - With no selection it prints every row in id order (`no rows` for a table
////   that has none); with an id, that row; with several ids, each named row in
////   the order given, a row printing again each time its id is repeated; with
////   `column=value`, the rows whose column holds the value.
//// - The table file is read and parsed once however many ids are named. When
////   any id has no row, nothing is printed: the first such id in the order
////   given is refused, so the output is never partial.
//// - A row is one `column = value` line per column in the file's column order,
////   and a blank line stands between rows.
//// - `--columns` prints instead what the file's header says: the table's name,
////   its record size and row count, and each column with its type code, its
////   kind and its offset in the record.
//// - A column's name is matched ignoring case, as the client matches a
////   schema's (`MatchGameTableSchema` 0x1407c19f0). A table is named as its
////   file is, with its case.
////
//// The columns come from the file's own header, so the command serves every
//// table the same way. A localised text id is a 32-bit integer column and
//// prints as the number. How a value prints, and what a filter matches:
////
//// | Column | Printed | A filter matches |
//// |---|---|---|
//// | type 3, 32-bit integer | the signed number; a negative one is followed by its unsigned form, `-1 (u32 0xffffffff)` | the signed number, the unsigned number, or the hex |
//// | type 20, 64-bit integer | the signed number | the number |
//// | type 4, 32-bit float | its value and its bits, `0.10000000149011612 (f32 0x3dcccccd)` | the value, the hex, or a decimal that rounds to the same 32-bit float, such as `0.1` |
//// | type 11, boolean | `true` or `false` | the same |
//// | type 130, string | in double quotes, with `\\`, `\"`, `\n`, `\r` and `\t` escaped | the text unquoted |
////
//// The client's loader copies a type-3 field as 4 bytes and gives it no sign
//// (`game_table.column_type`); each reader of the client decides. The
//// CharacterCustomizationSelection label and value and the LevelUpUnlock
//// level are compared as unsigned (0x1400200e0, 0x1404b0e70), while the data
//// holds signed numbers too (Creature2Difficulty.rankValue -3 to -1,
//// MapZonePOI.pos0 down to -28870) beside hashes and colours that fill all 32
//// bits (SoundEvent.hash, WorldSky.color). A value with the top bit set
//// therefore prints in both forms, and the proof of a fact names the form its
//// column means.
////
//// It exits with status 1 when the table, the column, an id or the file's
//// layout is refused, when no row holds a filter's value, or when the table
//// cannot be read; and with 2 when the arguments are not a table's name with
//// one or more ids, a `column=value` or `--columns`.

import argv
import genesis_prime/dev_exit
import genesis_prime/message/float32
import genesis_prime/table/loader/tbl_file.{type Strings, Column, Field}
import genesis_prime/table_folder
import gleam/bit_array
import gleam/bool
import gleam/float
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// The value of one column of a row, by the column's type. A 32-bit integer is
/// held as its signed reading; its unsigned reading is its value plus 2^32
/// when that is negative.
pub type Value {
  Integer32(Int)
  Integer64(Int)
  /// A 32-bit float: its value, and the 32 bits it is held in.
  Float32(value: Float, bits: Int)
  Boolean(Bool)
  Text(String)
}

/// One column of a row: the column's name in the client and its value.
pub type Cell {
  Cell(column: String, value: Value)
}

/// One row of a table: its id, which is the value of its first column, that
/// column's name, and its other cells in the file's column order.
pub opaque type Row {
  Row(id_column: String, id: Int, others: List(Cell))
}

/// A table file read: what its header says, its rows by id, and the same rows
/// in id order.
pub type TableRows {
  TableRows(
    description: tbl_file.Description,
    table: tbl_file.Table(Row),
    rows: List(Row),
  )
}

/// What the command is asked to print of a table.
type Request {
  /// What the header says: the record size, the row count and the columns.
  Columns
  /// Some of the rows.
  Rows(Selection)
}

/// Which rows to print.
type Selection {
  AllRows
  /// The rows of these ids, in the order given; a repeated id repeats its row.
  RowsOfIds(ids: List(Int))
  /// The rows whose column, as the person typed its name, holds the value.
  RowsHolding(column: String, value: String)
}

/// Why the rows could not be printed.
pub type RowsError {
  /// Not a table name, or a table name and one selection.
  Usage
  /// The selection is not an id, a `column=value` or `--columns`.
  BadSelection(selection: String)
  /// One of several selections is not an id; several selections are all ids.
  NotAnId(selection: String)
  /// The folder cannot be read.
  UnreadableFolder(folder: String)
  /// The folder holds no file `<table>.tbl`.
  UnknownTable(table: String, folder: String)
  /// The file cannot be read.
  UnreadableFile(path: String)
  /// The file is not accepted as a table.
  NotATable(table: String, error: tbl_file.FileError)
  /// The table's first column is not a 32-bit integer named `id`.
  NoIdColumn(table: String)
  /// The table has no column of that name.
  UnknownColumn(table: String, column: String)
  /// The table has no row of that id.
  NoRowOfId(table: String, id: Int)
  /// No row of the table holds the value in the column.
  NoRowHolds(table: String, column: String, value: String)
}

/// The text to print for the arguments after the command: the table's name and
/// an optional selection, read from the table file in `folder`.
pub fn run(
  arguments arguments: List(String),
  folder folder: String,
) -> Result(String, RowsError) {
  use #(table, request) <- result.try(parse(arguments))
  use files <- result.try(
    simplifile.read_directory(folder)
    |> result.replace_error(UnreadableFolder(folder)),
  )
  let file = table <> ".tbl"
  use <- bool.guard(
    when: !list.contains(files, file),
    return: Error(UnknownTable(table:, folder:)),
  )
  let path = folder <> "/" <> file
  use bytes <- result.try(
    simplifile.read_bits(path) |> result.replace_error(UnreadableFile(path)),
  )
  case request {
    Columns -> {
      use #(description, fields) <- result.map(place(bytes:, table:))
      render_columns(description, fields)
    }
    Rows(selection) -> {
      use TableRows(description:, table: lookup, rows:) <- result.try(read(
        bytes:,
        table:,
      ))
      use chosen <- result.map(choose(
        lookup:,
        rows:,
        columns: description.columns,
        selection:,
        table:,
      ))
      case chosen {
        [] -> "no rows"
        _ -> chosen |> list.map(render_row) |> string.join("\n\n")
      }
    }
  }
}

/// Reads a table file's header and checks the record size it states against
/// the placement rule, as the generator does: the description and the columns
/// placed in the record.
fn place(
  bytes bytes: BitArray,
  table table: String,
) -> Result(#(tbl_file.Description, List(tbl_file.Field)), RowsError) {
  use description <- result.try(
    tbl_file.describe(bytes) |> result.map_error(NotATable(table, _)),
  )
  tbl_file.fields(description)
  |> result.map(fn(fields) { #(description, fields) })
  |> result.map_error(fn(error) {
    case error {
      tbl_file.NoIdColumn -> NoIdColumn(table)
      tbl_file.NotPlaced(tbl_file.RecordSizeNotPlaced(placed:, header:)) ->
        NotATable(
          table,
          tbl_file.RecordSizeDiffers(expected: placed, found: header),
        )
    }
  })
}

/// Reads every row of a table file with the server's reader, which checks the
/// file against the schema its own header gives and each record against the
/// lookup. `table` is the name the errors give.
pub fn read(
  bytes bytes: BitArray,
  table table: String,
) -> Result(TableRows, RowsError) {
  use #(description, fields) <- result.try(place(bytes:, table:))
  let schema =
    tbl_file.Schema(
      table: description.table,
      file: table,
      record_size: description.record_size,
      columns: description.columns,
    )
  use rows <- result.map(
    tbl_file.read(
      bytes:,
      schema:,
      decode: fn(record, strings) { decode_record(fields:, record:, strings:) },
      id: fn(row: Row) { row.id },
    )
    |> result.map_error(NotATable(table, _)),
  )
  TableRows(description:, table: rows, rows: tbl_file.rows(rows))
}

/// The cells of a row, the id's first, in the file's column order.
pub fn cells(row: Row) -> List(Cell) {
  [Cell(row.id_column, Integer32(row.id)), ..row.others]
}

fn parse(arguments: List(String)) -> Result(#(String, Request), RowsError) {
  case arguments {
    [table] -> Ok(#(table, Rows(AllRows)))
    [table, "--columns"] -> Ok(#(table, Columns))
    [table, selection] ->
      case string.split_once(selection, "=") {
        Ok(#("", _)) -> Error(BadSelection(selection))
        Ok(#(column, value)) -> Ok(#(table, Rows(RowsHolding(column:, value:))))
        Error(Nil) ->
          int.parse(selection)
          |> result.map(fn(id) { #(table, Rows(RowsOfIds([id]))) })
          |> result.replace_error(BadSelection(selection))
      }
    [table, _, _, ..] -> parse_ids(table, list.drop(arguments, 1))
    _ -> Error(Usage)
  }
}

/// A table's rows by several ids named, each selection an id; the first that
/// is not one is refused.
fn parse_ids(
  table: String,
  selections: List(String),
) -> Result(#(String, Request), RowsError) {
  use ids <- result.map(
    list.try_map(selections, fn(selection) {
      int.parse(selection) |> result.replace_error(NotAnId(selection))
    }),
  )
  #(table, Rows(RowsOfIds(ids)))
}

fn choose(
  lookup lookup: tbl_file.Table(Row),
  rows rows: List(Row),
  columns columns: List(tbl_file.Column),
  selection selection: Selection,
  table table: String,
) -> Result(List(Row), RowsError) {
  case selection {
    AllRows -> Ok(rows)
    RowsOfIds(ids:) ->
      list.try_map(ids, fn(id) {
        tbl_file.row(lookup, id) |> result.replace_error(NoRowOfId(table:, id:))
      })
    RowsHolding(column: typed, value:) ->
      rows_holding(rows:, columns:, typed:, value:, table:)
  }
}

/// The rows whose column holds the value; the column is named as the person
/// typed it, and is found among the table's columns whether or not the table
/// has rows.
fn rows_holding(
  rows rows: List(Row),
  columns columns: List(tbl_file.Column),
  typed typed: String,
  value value: String,
  table table: String,
) -> Result(List(Row), RowsError) {
  use Column(name: column, ..) <- result.try(
    list.find(columns, fn(found) {
      string.lowercase(found.name) == string.lowercase(typed)
    })
    |> result.replace_error(UnknownColumn(table:, column: typed)),
  )
  use <- bool.guard(when: rows == [], return: Ok([]))
  case
    list.filter(rows, fn(row) {
      list.any(cells(row), fn(cell) {
        cell.column == column && matches(cell.value, value)
      })
    })
  {
    [] -> Error(NoRowHolds(table:, column:, value:))
    found -> Ok(found)
  }
}

/// A record as a row: each field of the layout read at its offset.
fn decode_record(
  fields fields: List(tbl_file.Field),
  record record: BitArray,
  strings strings: Strings,
) -> Result(Row, tbl_file.RecordError) {
  use cells <- result.try(
    list.try_map(fields, fn(field) { read_cell(record:, strings:, field:) }),
  )
  case cells {
    [Cell(column:, value: Integer32(id)), ..others] ->
      Ok(Row(id_column: column, id:, others:))
    _ -> Error(tbl_file.NotARecord)
  }
}

fn read_cell(
  record record: BitArray,
  strings strings: Strings,
  field field: tbl_file.Field,
) -> Result(Cell, tbl_file.RecordError) {
  let Field(column:, offset:) = field
  use rest <- result.try(
    bit_array.slice(record, offset, bit_array.byte_size(record) - offset)
    |> result.replace_error(tbl_file.NotARecord),
  )
  use value <- result.map(case column.column_type {
    tbl_file.Integer32 ->
      case rest {
        <<value:size(32)-little-signed, _:bits>> -> Ok(Integer32(value))
        _ -> Error(tbl_file.NotARecord)
      }
    tbl_file.Float32 ->
      case rest {
        <<bits:size(32)-little, _:bits>> -> float_of_bits(bits)
        _ -> Error(tbl_file.NotARecord)
      }
    tbl_file.Boolean32 ->
      case rest {
        <<value:size(32)-little, _:bits>> ->
          tbl_file.boolean(value, column.name) |> result.map(Boolean)
        _ -> Error(tbl_file.NotARecord)
      }
    tbl_file.Integer64 ->
      case rest {
        <<value:size(64)-little-signed, _:bits>> -> Ok(Integer64(value))
        _ -> Error(tbl_file.NotARecord)
      }
    tbl_file.Utf16Text ->
      case rest {
        <<value:size(64)-little, _:bits>> ->
          tbl_file.text(strings, value, column.name) |> result.map(Text)
        _ -> Error(tbl_file.NotARecord)
      }
  })
  Cell(column: column.name, value:)
}

/// The float held in 32 bits, which is not a number when its exponent is all
/// ones.
fn float_of_bits(bits: Int) -> Result(Value, tbl_file.RecordError) {
  use held <- result.try(
    float32.bits(number: bits) |> result.replace_error(tbl_file.NotARecord),
  )
  use value <- result.map(
    float32.value(bits: held) |> result.replace_error(tbl_file.NotARecord),
  )
  Float32(value:, bits:)
}

fn render_row(row: Row) -> String {
  cells(row)
  |> list.map(fn(cell) { cell.column <> " = " <> shown(cell.value) })
  |> string.join("\n")
}

fn render_columns(
  description: tbl_file.Description,
  fields: List(tbl_file.Field),
) -> String {
  [
    "table = " <> description.table,
    "record size = " <> int.to_string(description.record_size),
    "row count = " <> int.to_string(description.record_count),
    ..list.map(fields, fn(field) {
      let column_type = field.column.column_type
      "column "
      <> field.column.name
      <> " = type "
      <> int.to_string(tbl_file.type_code(column_type))
      <> ", "
      <> kind(column_type)
      <> ", offset "
      <> int.to_string(field.offset)
    })
  ]
  |> string.join("\n")
}

fn kind(column_type: tbl_file.ColumnType) -> String {
  case column_type {
    tbl_file.Integer32 -> "32-bit integer"
    tbl_file.Float32 -> "32-bit float"
    tbl_file.Boolean32 -> "boolean in 4 bytes"
    tbl_file.Integer64 -> "64-bit integer"
    tbl_file.Utf16Text -> "string"
  }
}

/// A value as a line shows it.
fn shown(value: Value) -> String {
  case value {
    Integer32(number) if number < 0 ->
      int.to_string(number) <> " (u32 " <> hex(unsigned(number)) <> ")"
    Integer32(number) -> int.to_string(number)
    Integer64(number) -> int.to_string(number)
    Float32(value:, bits:) ->
      float.to_string(value) <> " (f32 " <> hex(bits) <> ")"
    Boolean(True) -> "true"
    Boolean(False) -> "false"
    Text(text) ->
      "\""
      <> {
        text
        |> string.replace("\\", "\\\\")
        |> string.replace("\"", "\\\"")
        |> string.replace("\n", "\\n")
        |> string.replace("\r", "\\r")
        |> string.replace("\t", "\\t")
      }
      <> "\""
  }
}

const two_to_32 = 4_294_967_296

/// The unsigned reading of a 32-bit integer's signed one.
fn unsigned(number: Int) -> Int {
  use <- bool.guard(when: number >= 0, return: number)
  number + two_to_32
}

/// A 32-bit number as `0x` and eight lower-case hex digits.
fn hex(number: Int) -> String {
  "0x" <> string.pad_start(string.lowercase(int.to_base16(number)), 8, "0")
}

/// Whether a filter's text names the value: any of the forms the value prints
/// in (see the module's table).
fn matches(value: Value, wanted: String) -> Bool {
  case value {
    Integer32(number) ->
      wanted == int.to_string(number)
      || wanted == int.to_string(unsigned(number))
      || string.lowercase(wanted) == hex(unsigned(number))
    Integer64(number) -> wanted == int.to_string(number)
    Float32(value: number, bits:) ->
      wanted == float.to_string(number)
      || string.lowercase(wanted) == hex(bits)
      || nearest_bits(wanted) == Ok(bits)
    Boolean(flag) -> wanted == shown(Boolean(flag))
    Text(text) -> wanted == text
  }
}

/// The bits of the 32-bit float nearest to a decimal the filter gives, when it
/// is in the range of a 32-bit float.
fn nearest_bits(wanted: String) -> Result(Int, Nil) {
  use number <- result.try(case float.parse(wanted) {
    Ok(number) -> Ok(number)
    Error(Nil) -> int.parse(wanted) |> result.map(int.to_float)
  })
  case float.absolute_value(number) <=. largest_float32 {
    True ->
      case <<number:float-size(32)>> {
        <<bits:size(32)>> -> Ok(bits)
        _ -> Error(Nil)
      }
    False -> Error(Nil)
  }
}

/// The largest finite 32-bit float: (2 - 2^-23) * 2^127.
const largest_float32 = 3.4028234663852886e38

/// A sentence that says why the rows were not printed, with the usage for a
/// wrong call.
pub fn describe(error: RowsError) -> String {
  case error {
    Usage ->
      "usage: gleam run -m genesis_prime/table_rows -- <Table> [<id>... | <column>=<value> | --columns]"
    BadSelection(selection:) ->
      "'"
      <> selection
      <> "' is neither an id, a column=value nor --columns; "
      <> describe(Usage)
    NotAnId(selection:) ->
      "'"
      <> selection
      <> "' is not an id; several selections must all be ids; "
      <> describe(Usage)
    UnreadableFolder(folder:) ->
      "the tables folder "
      <> folder
      <> " cannot be read; run python3.13 -I setup_check/extract_tables.py"
    UnknownTable(table:, folder:) ->
      "no table named " <> table <> " in " <> folder
    UnreadableFile(path:) -> "the table file " <> path <> " cannot be read"
    NotATable(table:, error:) ->
      "the file of table "
      <> table
      <> " is not accepted: "
      <> tbl_file.describe_error(error)
    NoIdColumn(table:) ->
      "table " <> table <> " has no 32-bit integer named id as its first column"
    UnknownColumn(table:, column:) ->
      "table " <> table <> " has no column named " <> column
    NoRowOfId(table:, id:) ->
      "table " <> table <> " has no row of id " <> int.to_string(id)
    NoRowHolds(table:, column:, value:) ->
      "no row of table " <> table <> " holds " <> column <> " = " <> value
  }
}

/// Prints the rows the command line asks for, or why it cannot.
pub fn main() -> Nil {
  case run(arguments: argv.load().arguments, folder: table_folder.path()) {
    Ok(text) -> io.println(text)
    Error(error) -> {
      io.println_error(describe(error))
      case error {
        Usage | BadSelection(_) | NotAnId(_) -> dev_exit.halt(2)
        UnreadableFolder(_)
        | UnknownTable(_, _)
        | UnreadableFile(_)
        | NotATable(_, _)
        | NoIdColumn(_)
        | UnknownColumn(_, _)
        | NoRowOfId(_, _)
        | NoRowHolds(_, _, _) -> dev_exit.halt(1)
      }
    }
  }
}
