//// The command that prints a game table's rows (`genesis_prime/table_rows`):
//// every row, the row of an id, the rows whose column holds a value, the
//// columns and sizes the header gives, and the refusals of an unknown table,
//// column or id. The tables are planted, so the tests run where there is no
//// client; one test reads the client's real PathLevel table where the client
//// is present.
////
//// Expected values and their sources:
//// - a printed row is the planted row: each column of the file, in the file's
////   order, as `name = value`, a blank line between rows. A 32-bit integer
////   with the top bit set prints as its signed reading and its unsigned one:
////   3,000,000,000 is 0xB2D05E00, which reads as -1,294,967,296 signed (the
////   column has no sign in the client's loader, `game_table.column_type`). A
////   float prints its value and its bits: 0.1 as a 32-bit float is 0x3DCCCCCD,
////   which is 0.10000000149011612; 0.5 is 0x3F000000.
//// - the columns of the planted schema are placed by the client's rule
////   (`game_table.schema`): a 4-byte field at the next multiple of 4, an 8-byte
////   field at the next multiple of 8, so ID 0, level 4, ratio 8, enabled 12,
////   name 16, big 24, record size 32; the type codes are 3, 4, 11, 130 and 20
////   (`game_table.column_type`).
//// - the PathLevel row printed is the row the generated
////   `genesis_prime/table/path_level` module reads from the same file.
//// - the command and the generated decoders read every column type the same
////   way (`game_table.column_type`): the generated modules are the server's
////   readers of the client's tables.

import client_tables
import genesis_prime/table/account_item
import genesis_prime/table/emotes
import genesis_prime/table/item_slot
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file.{
  type Column, type Schema, Column, Schema,
}
import genesis_prime/table/path_level
import genesis_prime/table_rows
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/string
import owned_test
import planted_table.{Boolean, Float, Integer, Text}
import unitest

const planted_schema =
  Schema(
    table: "Planted",
    file: "Planted",
    record_size: 32,
    columns: [
      Column("ID", tbl_file.Integer32),
      Column("level", tbl_file.Integer32),
      Column("ratio", tbl_file.Float32),
      Column("enabled", tbl_file.Boolean32),
      Column("name", tbl_file.Utf16Text),
      Column("big", tbl_file.Integer64),
    ],
  )

fn planted_rows() -> List(List(planted_table.Cell)) {
  [
    planted_table.row(planted_schema, [
      #("ID", Integer(3)),
      #("level", Integer(2)),
      #("name", Text("Alpha")),
    ]),
    planted_table.row(planted_schema, [
      #("ID", Integer(5)),
      #("level", Integer(-3)),
      #("ratio", Float(0.5)),
      #("enabled", Boolean(True)),
      #("name", Text("Rider's \"Reef\"")),
      #("big", Integer(5_000_000_000)),
    ]),
    planted_table.row(planted_schema, [
      #("ID", Integer(9)),
      #("level", Integer(2)),
      #("name", Text("Beta")),
    ]),
    planted_table.row(planted_schema, [
      #("ID", Integer(11)),
      #("level", Integer(3_000_000_000)),
      #("ratio", Float(0.1)),
      #("name", Text("Gamma")),
    ]),
  ]
}

fn with_planted(body: fn(String) -> a) -> a {
  planted_table.in_folder(
    [planted_table.file(planted_schema, planted_rows())],
    body,
  )
}

const row_three =
  "ID = 3
level = 2
ratio = 0.0 (f32 0x00000000)
enabled = false
name = \"Alpha\"
big = 0"

const row_five =
  "ID = 5
level = -3 (u32 0xfffffffd)
ratio = 0.5 (f32 0x3f000000)
enabled = true
name = \"Rider's \\\"Reef\\\"\"
big = 5000000000"

const row_nine =
  "ID = 9
level = 2
ratio = 0.0 (f32 0x00000000)
enabled = false
name = \"Beta\"
big = 0"

const row_eleven =
  "ID = 11
level = -1294967296 (u32 0xb2d05e00)
ratio = 0.10000000149011612 (f32 0x3dcccccd)
enabled = false
name = \"Gamma\"
big = 0"

pub fn the_row_of_an_id_prints_each_column_and_its_value_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "5"], folder:) == Ok(row_five)
    as "the planted row of id 5: a negative integer, a float, a boolean, a string with quotes and a 64-bit integer, each under its column's name"
  assert table_rows.run(arguments: ["Planted", "11"], folder:) == Ok(row_eleven)
    as "the planted row of id 11: a 32-bit integer with the top bit set prints in both readings, and 0.1 as a 32-bit float prints its value and bits"
}

pub fn without_a_selection_every_row_prints_in_id_order_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted"], folder:)
    == Ok(string.join([row_three, row_five, row_nine, row_eleven], "\n\n"))
    as "the four planted rows in id order, a blank line between them"
}

pub fn a_filter_on_a_column_prints_only_the_rows_that_hold_the_value_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "level=2"], folder:)
    == Ok(string.join([row_three, row_nine], "\n\n"))
    as "ids 3 and 9 hold level 2; ids 5 and 11 do not"
  assert table_rows.run(arguments: ["Planted", "name=Beta"], folder:)
    == Ok(row_nine)
    as "a string column matches the text unquoted"
  assert table_rows.run(arguments: ["Planted", "LEVEL=-3"], folder:)
    == Ok(row_five)
    as "a column's name is matched ignoring case, as the client matches a schema's (MatchGameTableSchema 0x1407c19f0)"
  assert table_rows.run(arguments: ["Planted", "enabled=true"], folder:)
    == Ok(row_five)
    as "a boolean column matches true or false"
}

pub fn a_filter_matches_a_32_bit_integer_by_its_signed_unsigned_or_hex_form_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "level=-1294967296"], folder:)
    == Ok(row_eleven)
    as "the signed reading of 0xB2D05E00"
  assert table_rows.run(arguments: ["Planted", "level=3000000000"], folder:)
    == Ok(row_eleven)
    as "the unsigned reading: 3,000,000,000"
  assert table_rows.run(arguments: ["Planted", "level=0xB2D05E00"], folder:)
    == Ok(row_eleven)
    as "the hex of the 32 bits, in either case"
  assert table_rows.run(arguments: ["Planted", "level=0xfffffffd"], folder:)
    == Ok(row_five)
    as "-3 held in 32 bits is 0xFFFFFFFD"
}

pub fn a_filter_matches_a_32_bit_float_by_its_value_its_bits_or_a_decimal_that_rounds_to_it_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(
      arguments: ["Planted", "ratio=0.10000000149011612"],
      folder:,
    )
    == Ok(row_eleven)
    as "the value of the 32-bit float 0x3DCCCCCD"
  assert table_rows.run(arguments: ["Planted", "ratio=0x3dcccccd"], folder:)
    == Ok(row_eleven)
    as "the bits"
  assert table_rows.run(arguments: ["Planted", "ratio=0.1"], folder:)
    == Ok(row_eleven)
    as "0.1 rounds to the nearest 32-bit float, 0x3DCCCCCD"
  assert table_rows.run(arguments: ["Planted", "ratio=0.5"], folder:)
    == Ok(row_five)
    as "0.5 is exactly 0x3F000000"
}

pub fn a_filter_that_matches_no_row_fails_naming_the_column_and_value_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  let error = table_rows.run(arguments: ["Planted", "level=99"], folder:)
  assert error
    == Error(table_rows.NoRowHolds(
      table: "Planted",
      column: "level",
      value: "99",
    ))
    as "no planted row holds level 99"
  let assert Error(found) = error
  assert string.contains(table_rows.describe(found), "level")
    as "the message names the column"
  assert string.contains(table_rows.describe(found), "99")
    as "the message names the value"
}

pub fn an_id_with_no_row_fails_naming_the_id_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  let error = table_rows.run(arguments: ["Planted", "4"], folder:)
  assert error == Error(table_rows.NoRowOfId(table: "Planted", id: 4))
    as "the planted ids are 3, 5, 9 and 11"
  let assert Error(found) = error
  assert string.contains(table_rows.describe(found), "4")
    as "the message names the id"
}

pub fn several_ids_print_each_row_in_the_order_given_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "11", "3", "9"], folder:)
    == Ok(string.join([row_eleven, row_three, row_nine], "\n\n"))
    as "ids 11, 3 and 9 print in that order, not in id order, a blank line between rows"
}

pub fn a_repeated_id_prints_its_row_each_time_it_is_named_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "5", "3", "5"], folder:)
    == Ok(string.join([row_five, row_three, row_five], "\n\n"))
    as "id 5 is named twice and prints twice"
}

pub fn an_id_with_no_row_among_good_ones_fails_naming_it_and_prints_no_row_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  let error = table_rows.run(arguments: ["Planted", "3", "4", "5"], folder:)
  assert error == Error(table_rows.NoRowOfId(table: "Planted", id: 4))
    as "the planted ids are 3, 5, 9 and 11: only 4 has no row, and the rows of 3 and 5 are not printed"
  let assert Error(found) = error
  assert string.contains(table_rows.describe(found), "4")
    as "the message names the id"
  assert table_rows.run(arguments: ["Planted", "3", "8", "4"], folder:)
    == Error(table_rows.NoRowOfId(table: "Planted", id: 8))
    as "of two ids with no row, the first one named is refused"
}

pub fn a_selection_among_several_that_is_not_an_id_fails_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "3", "five", "5"], folder:)
    == Error(table_rows.NotAnId("five"))
    as "five is not an id"
  assert table_rows.run(arguments: ["Planted", "3", "--columns"], folder:)
    == Error(table_rows.NotAnId("--columns"))
    as "--columns is a valid selection alone, but not among ids"
  assert table_rows.run(arguments: ["Planted", "level=2", "3"], folder:)
    == Error(table_rows.NotAnId("level=2"))
    as "a column=value is a valid selection alone, but not among ids"
  let assert Error(found) =
    table_rows.run(arguments: ["Planted", "3", "--columns"], folder:)
  assert string.contains(
    table_rows.describe(found),
    "'--columns' is not an id; several selections must all be ids",
  )
    as "the message says why the selection is refused, not that it is neither an id nor a column=value"
}

pub fn an_unknown_table_fails_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  let error = table_rows.run(arguments: ["Nowhere"], folder:)
  assert error
    == Error(table_rows.UnknownTable(table: "Nowhere", folder: folder))
    as "the folder holds only Planted.tbl"
  let assert Error(found) = error
  assert string.contains(table_rows.describe(found), "Nowhere")
    as "the message names the table"
  assert table_rows.run(arguments: ["planted"], folder:)
    == Error(table_rows.UnknownTable(table: "planted", folder: folder))
    as "a table is named as its file is, with its case"
}

pub fn an_unknown_column_fails_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  let error = table_rows.run(arguments: ["Planted", "colour=2"], folder:)
  assert error
    == Error(table_rows.UnknownColumn(table: "Planted", column: "colour"))
    as "the planted table has no column colour"
  let assert Error(found) = error
  assert string.contains(table_rows.describe(found), "colour")
    as "the message names the column"
  assert string.contains(table_rows.describe(found), "Planted")
    as "the message names the table"
}

pub fn a_selection_that_is_neither_an_id_nor_a_column_and_value_fails_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "five"], folder:)
    == Error(table_rows.BadSelection("five"))
    as "five is not an id and has no ="
}

const planted_columns =
  "column ID = type 3, 32-bit integer, offset 0
column level = type 3, 32-bit integer, offset 4
column ratio = type 4, 32-bit float, offset 8
column enabled = type 11, boolean in 4 bytes, offset 12
column name = type 130, string, offset 16
column big = type 20, 64-bit integer, offset 24"

pub fn the_columns_option_prints_the_header_the_columns_and_their_offsets_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "--columns"], folder:)
    == Ok(
      "table = Planted\nrecord size = 32\nrow count = 4\n" <> planted_columns,
    )
    as "game_table.schema and game_table.column_type: the planted file's four rows and six columns, placed by the client's rule"
}

pub fn a_table_with_no_rows_prints_no_rows_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- planted_table.in_folder([planted_table.file(planted_schema, [])])
  assert table_rows.run(arguments: ["Planted"], folder:) == Ok("no rows")
    as "the planted table has no record (the client has such tables: game_tables.ClientData names seven)"
  assert table_rows.run(arguments: ["Planted", "level=2"], folder:)
    == Ok("no rows")
    as "a filter on a table with no rows has none to match"
  assert table_rows.run(arguments: ["Planted", "colour=2"], folder:)
    == Error(table_rows.UnknownColumn(table: "Planted", column: "colour"))
    as "an unknown column is refused whether or not the table has rows"
  assert table_rows.run(arguments: ["Planted", "--columns"], folder:)
    == Ok(
      "table = Planted\nrecord size = 32\nrow count = 0\n" <> planted_columns,
    )
    as "the columns are the header's whatever the row count"
}

pub fn a_real_table_row_prints_the_values_the_generated_module_reads_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.guard(client_tables.present())
  let assert Ok(row) =
    list.find(path_level.all(client_tables.every_table()), fn(row) {
      row.id == 7
    })
    as "PathLevel has a row of id 7"
  assert table_rows.run(
      arguments: ["PathLevel", "7"],
      folder: client_tables.folder(),
    )
    == Ok(
      "ID = "
      <> int.to_string(row.id)
      <> "\npathTypeEnum = "
      <> int.to_string(row.path_type_enum)
      <> "\npathLevel = "
      <> int.to_string(row.path_level)
      <> "\npathXP = "
      <> int.to_string(row.path_xp),
    )
    as "the row the generated module reads from PathLevel.tbl by the client's layout (game_table.schema)"
}

/// A planted value for a column, from the column's position and its row's
/// number, that tells the readers apart: a 32-bit integer at an odd position
/// has its top bit set, a 64-bit integer is negative at an odd position, and a
/// float is never a whole number.
fn planted_cell(
  column column: Column,
  position position: Int,
  number number: Int,
) -> planted_table.Cell {
  let odd = int.is_odd(position)
  case column.column_type {
    tbl_file.Integer32 ->
      case position {
        0 -> Integer(number)
        _ if odd -> Integer(4_000_000_000 + position + number)
        _ -> Integer(position * 1_000_003 + number)
      }
    tbl_file.Integer64 ->
      case odd {
        True -> Integer(-5_000_000_000 - position - number)
        False -> Integer(5_000_000_000 + position + number)
      }
    tbl_file.Float32 -> Float(0.1 *. int.to_float(position + number) +. 0.25)
    tbl_file.Boolean32 -> Boolean(odd)
    tbl_file.Utf16Text -> Text("Ünï " <> int.to_string(position + number))
  }
}

/// Plants the schema's table with three rows, loads it with the generated
/// module's entry, and gives each generated row's fields beside the cells the
/// command reads from the same bytes.
fn read_both_ways(
  schema schema: Schema,
  entry entry: store.Entry,
  generated generated: fn(store.Tables) -> List(row),
) -> List(#(List(Dynamic), List(table_rows.Cell))) {
  let rows =
    list.map([1, 2, 3], fn(number) {
      planted_table.row(
        schema,
        list.index_map(schema.columns, fn(column, position) {
          #(column.name, planted_cell(column:, position:, number:))
        }),
      )
    })
  let bytes = planted_table.bytes(planted_table.table(schema:, rows:))
  let assert Ok(read) = table_rows.read(bytes:, table: schema.table)
    as "the command reads the planted table"
  use folder <- planted_table.in_folder([#(schema.file, bytes)])
  let assert Ok(tables) =
    store.load(
      under: reference.new(),
      from: folder,
      entries: [entry],
      requirements: [],
      derivations: [],
    )
    as "the generated module loads the planted table"
  let fields = list.map(generated(tables), record_fields)
  store.unload(tables)
  list.zip(fields, list.map(read.rows, table_rows.cells))
}

@external(erlang, "table_rows_test_ffi", "record_fields")
fn record_fields(row: row) -> List(Dynamic)

fn same_value(field: Dynamic, value: table_rows.Value) -> Bool {
  case value {
    table_rows.Integer32(number) | table_rows.Integer64(number) ->
      decode.run(field, decode.int) == Ok(number)
    table_rows.Float32(value: number, bits: _) ->
      decode.run(field, decode.float) == Ok(number)
    table_rows.Boolean(flag) -> decode.run(field, decode.bool) == Ok(flag)
    table_rows.Text(text) -> decode.run(field, decode.string) == Ok(text)
  }
}

fn assert_read_the_same(
  pairs: List(#(List(Dynamic), List(table_rows.Cell))),
) -> Nil {
  assert list.length(pairs) == 3 as "three rows were planted"
  list.each(pairs, fn(pair) {
    let #(fields, cells) = pair
    assert list.length(fields) == list.length(cells)
      as "a generated row has a field for every column"
    list.each(list.zip(fields, cells), fn(both) {
      let #(field, cell) = both
      assert same_value(field, cell.value)
        as { "the column " <> cell.column <> " reads differently" }
    })
  })
}

pub fn the_command_and_the_generated_decoder_read_32_bit_integers_text_and_booleans_alike_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_read_the_same(read_both_ways(
    schema: emotes.schema,
    entry: emotes.entry(),
    generated: emotes.all,
  ))
}

pub fn the_command_and_the_generated_decoder_read_64_bit_integers_alike_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_read_the_same(read_both_ways(
    schema: account_item.schema,
    entry: account_item.entry(),
    generated: account_item.all,
  ))
}

pub fn the_command_and_the_generated_decoder_read_32_bit_floats_alike_test() -> Nil {
  use <- owned_test.run(10_000)
  assert_read_the_same(read_both_ways(
    schema: item_slot.schema,
    entry: item_slot.entry(),
    generated: item_slot.all,
  ))
}
