//// The command that prints a game table's rows (`genesis_prime/table_rows`):
//// every row, the row of an id, the rows whose column holds a value, and the
//// refusals of an unknown table, column or id. The tables are planted, so the
//// tests run where there is no client; one test reads the client's real
//// PathLevel table where the client is present.
////
//// Expected values and their sources:
//// - a printed row is the planted row: each column of the file, in the file's
////   order, as `name = value` (integers in decimal, a float as the 32-bit
////   float's value, a boolean as `true` or `false`, a string in quotes), a
////   blank line between rows.
//// - PathLevel row 7 is pathTypeEnum 0, pathLevel 2, pathXP 30 (the fact file's
////   record for the path level table, read from PathLevel.tbl; the table has
////   columns ID, pathTypeEnum, pathLevel, pathXP).

import client_tables
import genesis_prime/table/loader/tbl_file.{Column, Schema}
import genesis_prime/table_rows
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
ratio = 0.0
enabled = false
name = \"Alpha\"
big = 0"

const row_five =
  "ID = 5
level = -3
ratio = 0.5
enabled = true
name = \"Rider's \\\"Reef\\\"\"
big = 5000000000"

const row_nine =
  "ID = 9
level = 2
ratio = 0.0
enabled = false
name = \"Beta\"
big = 0"

pub fn the_row_of_an_id_prints_each_column_and_its_value_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "5"], folder:) == Ok(row_five)
    as "the planted row of id 5: a negative integer, a float, a boolean, a string with quotes and a 64-bit integer, each under its column's name"
}

pub fn without_a_selection_every_row_prints_in_id_order_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted"], folder:)
    == Ok(string.join([row_three, row_five, row_nine], "\n\n"))
    as "the three planted rows in id order, a blank line between them"
}

pub fn a_filter_on_a_column_prints_only_the_rows_that_hold_the_value_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- with_planted
  assert table_rows.run(arguments: ["Planted", "level=2"], folder:)
    == Ok(string.join([row_three, row_nine], "\n\n"))
    as "ids 3 and 9 hold level 2; id 5 holds -3"
  assert table_rows.run(arguments: ["Planted", "name=Beta"], folder:)
    == Ok(row_nine)
    as "a string column matches the text unquoted"
  assert table_rows.run(arguments: ["Planted", "LEVEL=-3"], folder:)
    == Ok(row_five)
    as "a column's name is matched ignoring case, as the client matches a schema's (MatchGameTableSchema 0x1407c19f0)"
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
    as "the planted ids are 3, 5 and 9"
  let assert Error(found) = error
  assert string.contains(table_rows.describe(found), "4")
    as "the message names the id"
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

pub fn a_real_table_row_prints_the_values_the_client_holds_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.guard(client_tables.present())
  assert table_rows.run(
      arguments: ["PathLevel", "7"],
      folder: client_tables.folder(),
    )
    == Ok("ID = 7\npathTypeEnum = 0\npathLevel = 2\npathXP = 30")
    as "PathLevel row 7 (the fact file: rows 6 to 9 are (0, 1, 0), (0, 2, 30), (0, 3, 120), (0, 4, 270) as pathTypeEnum, pathLevel, pathXP)"
}
