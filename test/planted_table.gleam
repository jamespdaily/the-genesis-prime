//// Plants a game table file for tests: the bytes of a `.tbl` file written as
//// the fact file's `game_table.file` describes (a 0x60-byte header, the
//// column table, the column names, the record block of records then string
//// data, and the id lookup array), from a schema and rows of cells. A fault is
//// planted by giving the lookup or a string offset directly.

import genesis_prime/table/tbl_file.{type Column, type Schema}
import gleam/bit_array
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import simplifile

/// The value of one field of a planted record.
pub type Cell {
  Integer(Int)
  Float(Float)
  Boolean(Bool)
  /// A string, written into the string data.
  Text(String)
  /// A string field holding this offset, whatever the string data holds.
  TextAt(offset: Int)
}

/// A table to write: the schema it is laid out by, one list of cells per
/// record in column order, and the faults to plant.
pub type Planted {
  Planted(
    schema: Schema,
    rows: List(List(Cell)),
    /// The lookup entries for ids 0 and up; None writes the right lookup.
    lookup: Option(List(Int)),
    /// The record size the header states; None writes the schema's.
    header_record_size: Option(Int),
  )
}

const signature = 0x4454424C

const header_size = 0x60

/// A table with the right lookup and header.
pub fn table(schema: Schema, rows: List(List(Cell))) -> Planted {
  Planted(schema:, rows:, lookup: None, header_record_size: None)
}

/// A record of the schema with a zero, a false or an empty string in every
/// column, except the columns named, which take the cell given.
pub fn row(schema: Schema, with changes: List(#(String, Cell))) -> List(Cell) {
  list.map(schema.columns, fn(column) {
    case list.key_find(changes, column.name) {
      Ok(cell) -> cell
      Error(Nil) -> zero(column)
    }
  })
}

fn zero(column: Column) -> Cell {
  case column.column_type {
    tbl_file.Integer32 | tbl_file.Integer64 -> Integer(0)
    tbl_file.Float32 -> Float(0.0)
    tbl_file.Boolean32 -> Boolean(False)
    tbl_file.Utf16Text -> Text("")
  }
}

/// The bytes of the planted file.
pub fn bytes(planted: Planted) -> BitArray {
  let schema = planted.schema
  let #(fields, record_size) = tbl_file.layout(schema.columns)
  let count = list.length(schema.columns)
  let table_name = text_with_end(schema.table)
  let column_table_offset = round_up(bit_array.byte_size(table_name), 16)
  let names_offset = column_table_offset + round_up(24 * count, 16)
  let #(name_entries, names) = column_names(schema.columns)
  let column_entries =
    list.map2(schema.columns, name_entries, fn(column, entry) {
      let #(length, offset) = entry
      <<
        length:size(32)-little,
        0:size(32)-little,
        offset:size(64)-little,
        type_code(column):size(16)-little,
        0:size(16)-little,
        0:size(32)-little,
      >>
    })
    |> bit_array.concat
  let records_size = record_size * list.length(planted.rows)
  let #(records, strings) =
    write_records(planted.rows, fields, record_size, records_size)
  let block = bit_array.append(records, strings)
  let block_offset = round_up(names_offset + bit_array.byte_size(names), 16)
  let lookup = lookup_entries(planted)
  let lookup_offset = round_up(block_offset + bit_array.byte_size(block), 4)
  let header_record_size =
    option.unwrap(planted.header_record_size, record_size)
  let header = <<
    signature:size(32)-little,
    0:size(32)-little,
    { bit_array.byte_size(table_name) / 2 }:size(64)-little,
    0:size(64)-little,
    header_record_size:size(64)-little,
    count:size(64)-little,
    column_table_offset:size(64)-little,
    list.length(planted.rows):size(64)-little,
    bit_array.byte_size(block):size(64)-little,
    block_offset:size(64)-little,
    { list.length(lookup) }:size(64)-little,
    lookup_offset:size(64)-little,
    0:size(64)-little,
  >>
  assert bit_array.byte_size(header) == header_size
    as "the planted header is 0x60 bytes"
  [
    header,
    pad_to(table_name, column_table_offset),
    pad_to(column_entries, names_offset - column_table_offset),
    pad_to(names, block_offset - names_offset),
    pad_to(block, lookup_offset - block_offset),
    lookup
      |> list.map(fn(entry) { <<entry:size(32)-little>> })
      |> bit_array.concat,
  ]
  |> bit_array.concat
}

fn round_up(value: Int, multiple: Int) -> Int {
  { value + multiple - 1 } / multiple * multiple
}

fn pad_to(bytes: BitArray, length: Int) -> BitArray {
  let missing = length - bit_array.byte_size(bytes)
  assert missing >= 0 as "the planted part is longer than its room"
  bit_array.append(bytes, <<0:size({ missing * 8 })>>)
}

/// UTF-16 little-endian text and its ending zero character.
fn text_with_end(text: String) -> BitArray {
  bit_array.append(utf16(text), <<0:size(16)>>)
}

@external(erlang, "planted_table_ffi", "utf16")
fn utf16(text: String) -> BitArray

/// Each column's name length in characters with the ending zero and its
/// offset from the names' start, and all the names.
fn column_names(columns: List(Column)) -> #(List(#(Int, Int)), BitArray) {
  let #(names, entries) =
    list.fold(columns, #(<<>>, []), fn(state, column) {
      let #(names, entries) = state
      let name = text_with_end(column.name)
      #(bit_array.append(names, name), [
        #(bit_array.byte_size(name) / 2, bit_array.byte_size(names)),
        ..entries
      ])
    })
  #(list.reverse(entries), names)
}

fn type_code(column: Column) -> Int {
  case column.column_type {
    tbl_file.Integer32 -> 3
    tbl_file.Float32 -> 4
    tbl_file.Boolean32 -> 11
    tbl_file.Integer64 -> 20
    tbl_file.Utf16Text -> 130
  }
}

/// The records, and the string data after them. A string field holds its
/// offset from the record block's start.
fn write_records(
  rows: List(List(Cell)),
  fields: List(tbl_file.Field),
  record_size: Int,
  records_size: Int,
) -> #(BitArray, BitArray) {
  let #(records, strings) =
    list.fold(rows, #([], <<>>), fn(state, cells) {
      let #(records, strings) = state
      let #(record, strings) =
        write_record(cells, fields, record_size, records_size, strings)
      #([record, ..records], strings)
    })
  #(bit_array.concat(list.reverse(records)), strings)
}

fn write_record(
  cells: List(Cell),
  fields: List(tbl_file.Field),
  record_size: Int,
  records_size: Int,
  strings: BitArray,
) -> #(BitArray, BitArray) {
  let #(bytes, strings) =
    list.fold(list.zip(fields, cells), #(<<>>, strings), fn(state, pair) {
      let #(bytes, strings) = state
      let #(field, cell) = pair
      let padded = pad_to(bytes, field.offset)
      case cell {
        Integer(value) ->
          case field.column.column_type {
            tbl_file.Integer64 -> #(
              bit_array.append(padded, <<value:size(64)-little>>),
              strings,
            )
            _ -> #(bit_array.append(padded, <<value:size(32)-little>>), strings)
          }
        Float(value) -> #(
          bit_array.append(padded, <<value:float-size(32)-little>>),
          strings,
        )
        Boolean(value) -> #(
          bit_array.append(padded, <<bool_value(value):size(32)-little>>),
          strings,
        )
        TextAt(offset) -> #(
          bit_array.append(padded, <<offset:size(64)-little>>),
          strings,
        )
        Text(text) -> {
          let offset = records_size + bit_array.byte_size(strings)
          #(
            bit_array.append(padded, <<offset:size(64)-little>>),
            bit_array.append(strings, text_with_end(text)),
          )
        }
      }
    })
  #(pad_to(bytes, record_size), strings)
}

fn bool_value(value: Bool) -> Int {
  case value {
    True -> 1
    False -> 0
  }
}

/// The lookup: the row index of each id from 0 to the highest, or
/// 0xFFFFFFFF where no record has the id.
fn lookup_entries(planted: Planted) -> List(Int) {
  case planted.lookup {
    Some(entries) -> entries
    None -> {
      let ids =
        list.index_map(planted.rows, fn(cells, row) {
          let assert [Integer(id), ..] = cells
            as "the first cell of a planted record is its id"
          #(id, row)
        })
      let highest =
        list.fold(ids, -1, fn(highest, pair) { int.max(highest, pair.0) })
      int.range(from: highest, to: -1, with: [], run: fn(entries, id) {
        let entry = case list.key_find(ids, id) {
          Ok(row) -> row
          Error(Nil) -> 0xFFFFFFFF
        }
        [entry, ..entries]
      })
    }
  }
}

/// Makes a folder of its own, writes each file into it as `<name>.tbl`, runs
/// the body with the folder's path, and removes the folder afterwards.
pub fn in_folder(files: List(#(String, BitArray)), body: fn(String) -> a) -> a {
  with_folder(fn(folder) {
    list.each(files, fn(file) {
      let assert Ok(Nil) =
        simplifile.write_bits(folder <> "/" <> file.0 <> ".tbl", file.1)
        as "the planted file could not be written"
    })
    body(folder)
  })
}

@external(erlang, "planted_table_ffi", "with_folder")
fn with_folder(body: fn(String) -> a) -> a

/// How many persistent terms are stored under a load's key.
@external(erlang, "planted_table_ffi", "persistent_terms_under")
pub fn persistent_terms_under(key: Reference) -> Int
