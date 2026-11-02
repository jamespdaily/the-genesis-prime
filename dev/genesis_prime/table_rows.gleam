//// Prints the rows of one of the client's game tables, read with the server's
//// own table reader (`genesis_prime/table/loader/tbl_file`), for the decoders
//// that need to see what a table holds.
////
//// `gleam run -m genesis_prime/table_rows -- <Table> [<id> | <column>=<value>]`
//// reads `<Table>.tbl` from the extracted tables folder (`GENESIS_TABLE_DIR`,
//// else `GENESIS_HOME`/tables, else `~/.genesis-prime/tables`) and prints each
//// row as one `column = value` line per column, in the file's column order,
//// with a blank line between rows. With no selection it prints every row in id
//// order; with an id it prints that row; with `column=value` it prints the rows
//// whose column holds the value as it is printed. A column's name is matched
//// ignoring case, as the client matches a schema's (`MatchGameTableSchema`
//// 0x1407c19f0); a table is named as its file is.
////
//// The columns come from the file's own header, so the command serves every
//// table the same way. Integers print in decimal, a float as the value of the
//// 32-bit float, a boolean as `true` or `false`, and a string in double quotes
//// with `\\`, `\"`, `\n`, `\r` and `\t` escaped (a filter takes the text
//// unquoted). A localised text id is a 32-bit integer column and prints as the
//// number. It exits with status 1 when the table, the column, the id or the
//// file's layout is refused, and with 2 when the arguments are not a table's
//// name with an id or a `column=value`.

import argv
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

/// The value of one column of a row, by the column's type.
type Value {
  Integer(Int)
  Float(Float)
  Boolean(Bool)
  Text(String)
}

/// One column of a row: the column's name in the client and its value.
type Cell {
  Cell(column: String, value: Value)
}

/// One row of a table: its id, which is its first column, and its cells in the
/// file's column order.
type Row {
  Row(id: Int, cells: List(Cell))
}

/// Which rows to print.
type Selection {
  AllRows
  RowOfId(id: Int)
  RowsHolding(column: String, value: String)
}

/// Why the rows could not be printed.
pub type RowsError {
  /// Not a table name, or a table name and one selection.
  Usage
  /// The selection is not an id and has no `=`.
  BadSelection(selection: String)
  /// The folder cannot be read.
  UnreadableFolder(folder: String)
  /// The folder holds no file `<table>.tbl`.
  UnknownTable(table: String, folder: String)
  /// The file cannot be read.
  UnreadableFile(path: String)
  /// The file is not accepted as a table.
  NotATable(table: String, error: tbl_file.FileError)
  /// The table's first column is not a 32-bit integer, the id.
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
  use #(table, selection) <- result.try(parse(arguments))
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
  use description <- result.try(
    tbl_file.describe(bytes) |> result.map_error(NotATable(table, _)),
  )
  use <- bool.guard(
    when: !has_id_column(description.columns),
    return: Error(NoIdColumn(table)),
  )
  use selection <- result.try(check_column(selection:, description:, table:))
  let #(fields, record_size) = tbl_file.layout(description.columns)
  let schema =
    tbl_file.Schema(
      table: description.table,
      file: table,
      record_size:,
      columns: description.columns,
    )
  use rows <- result.try(
    tbl_file.read(
      bytes:,
      schema:,
      decode: fn(record, strings) { decode_record(fields:, record:, strings:) },
      id: fn(row: Row) { row.id },
    )
    |> result.map_error(NotATable(table, _)),
  )
  use chosen <- result.map(choose(rows:, selection:, table:))
  chosen |> list.map(render_row) |> string.join("\n\n")
}

fn parse(arguments: List(String)) -> Result(#(String, Selection), RowsError) {
  case arguments {
    [table] -> Ok(#(table, AllRows))
    [table, selection] ->
      case string.split_once(selection, "=") {
        Ok(#("", _)) -> Error(BadSelection(selection))
        Ok(#(column, value)) -> Ok(#(table, RowsHolding(column:, value:)))
        Error(Nil) ->
          case int.parse(selection) {
            Ok(id) -> Ok(#(table, RowOfId(id)))
            Error(Nil) -> Error(BadSelection(selection))
          }
      }
    _ -> Error(Usage)
  }
}

fn has_id_column(columns: List(tbl_file.Column)) -> Bool {
  case columns {
    [Column(column_type: tbl_file.Integer32, ..), ..] -> True
    _ -> False
  }
}

/// A filter's column, spelt as the file spells it, or the error that the table
/// has none.
fn check_column(
  selection selection: Selection,
  description description: tbl_file.Description,
  table table: String,
) -> Result(Selection, RowsError) {
  case selection {
    AllRows | RowOfId(_) -> Ok(selection)
    RowsHolding(column:, value:) ->
      list.find(description.columns, fn(found) {
        string.lowercase(found.name) == string.lowercase(column)
      })
      |> result.map(fn(found) { RowsHolding(column: found.name, value:) })
      |> result.replace_error(UnknownColumn(table:, column:))
  }
}

fn choose(
  rows rows: tbl_file.Table(Row),
  selection selection: Selection,
  table table: String,
) -> Result(List(Row), RowsError) {
  case selection {
    AllRows -> Ok(tbl_file.rows(rows))
    RowOfId(id:) ->
      tbl_file.row(rows, id)
      |> result.map(list.wrap)
      |> result.replace_error(NoRowOfId(table:, id:))
    RowsHolding(column:, value:) ->
      case
        list.filter(tbl_file.rows(rows), fn(row) {
          list.any(row.cells, fn(cell) {
            cell.column == column && value_text(cell.value) == value
          })
        })
      {
        [] -> Error(NoRowHolds(table:, column:, value:))
        found -> Ok(found)
      }
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
    [Cell(value: Integer(id), ..), ..] -> Ok(Row(id:, cells:))
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
        <<value:size(32)-little-signed, _:bits>> -> Ok(Integer(value))
        _ -> Error(tbl_file.NotARecord)
      }
    tbl_file.Float32 ->
      case rest {
        <<value:size(32)-little-float, _:bits>> -> Ok(Float(value))
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
        <<value:size(64)-little-signed, _:bits>> -> Ok(Integer(value))
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

fn render_row(row: Row) -> String {
  row.cells
  |> list.map(fn(cell) { cell.column <> " = " <> shown(cell.value) })
  |> string.join("\n")
}

/// A value as a line shows it: a string in quotes.
fn shown(value: Value) -> String {
  case value {
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
    Integer(_) | Float(_) | Boolean(_) -> value_text(value)
  }
}

/// A value as a filter writes it: a string without quotes.
fn value_text(value: Value) -> String {
  case value {
    Integer(number) -> int.to_string(number)
    Float(number) -> float.to_string(number)
    Boolean(True) -> "true"
    Boolean(False) -> "false"
    Text(text) -> text
  }
}

/// A sentence that says why the rows were not printed, with the usage for a
/// wrong call.
pub fn describe(error: RowsError) -> String {
  case error {
    Usage ->
      "usage: gleam run -m genesis_prime/table_rows -- <Table> [<id> | <column>=<value>]"
    BadSelection(selection:) ->
      "'"
      <> selection
      <> "' is neither an id nor a column=value; "
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
      "table " <> table <> " has no 32-bit integer id as its first column"
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
        Usage | BadSelection(_) -> halt(2)
        UnreadableFolder(_)
        | UnknownTable(_, _)
        | UnreadableFile(_)
        | NotATable(_, _)
        | NoIdColumn(_)
        | UnknownColumn(_, _)
        | NoRowOfId(_, _)
        | NoRowHolds(_, _, _) -> halt(1)
      }
    }
  }
}

@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil
