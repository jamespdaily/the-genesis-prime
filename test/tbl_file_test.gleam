//// The layout of a game table file and of its records: the placement rule, a
//// boolean column's values and the header and column table. Expected values
//// and their sources:
//// - placement: the fact file's `game_table.schema`: fields lie in column
////   order, a 4-byte field at the next multiple of 4, an 8-byte field (a
////   64-bit integer or a string offset) at the next multiple of 8, and the
////   record size is the end rounded up to 8 when the record holds an 8-byte
////   field, else to 4. The Creature2 schema is 696 bytes with 173 columns and
////   its column 'description' at offset 8 (bytes at 0x140a61ca0 and
////   0x140a4ef70); the other four record sizes are `game_tables.ClientData`
////   (Spell4 424, Item2 208, Spline2Node 56, LocalizedText 28).
//// - a boolean column holds 0 or 1 (`game_table.column_type`: every type-11
////   field in the files is 0 or 1).
//// - the header: signature 0x4454424C checked first (0x1407c16d4, else
////   'Corrupt Tbl File'), the header 0x60 bytes, the name, the column table of
////   24-byte entries and the column names, each a range that must lie inside
////   the file (`game_table.file`).

import client_tables
import envoy
import genesis_prime/table/creature2
import genesis_prime/table/item2
import genesis_prime/table/loader/tbl_file.{Column, Description, Field}
import genesis_prime/table/localized_text
import genesis_prime/table/spell4
import genesis_prime/table/spline2_node
import gleam/bit_array
import gleam/list
import owned_test
import planted_table.{Integer}
import unitest

fn column(name: String, column_type: tbl_file.ColumnType) -> tbl_file.Column {
  Column(name:, column_type:)
}

pub fn a_4_byte_field_follows_the_last_and_an_8_byte_field_aligns_to_8_test() -> Nil {
  use <- owned_test.run(5000)
  let columns = [
    column("a", tbl_file.Integer32),
    column("b", tbl_file.Utf16Text),
    column("c", tbl_file.Integer32),
  ]
  assert tbl_file.layout(columns)
    == #(
      [
        Field(column("a", tbl_file.Integer32), offset: 0),
        Field(column("b", tbl_file.Utf16Text), offset: 8),
        Field(column("c", tbl_file.Integer32), offset: 16),
      ],
      24,
    )
    as "game_table.schema: a string offset at the next multiple of 8 (8), a 4-byte field after it (16); the end, 20, rounds up to 8 for a record with an 8-byte field"
}

pub fn a_record_of_4_byte_fields_is_sized_to_a_multiple_of_4_test() -> Nil {
  use <- owned_test.run(5000)
  let columns = [
    column("a", tbl_file.Integer32),
    column("b", tbl_file.Float32),
    column("c", tbl_file.Boolean32),
  ]
  assert tbl_file.layout(columns)
    == #(
      [
        Field(column("a", tbl_file.Integer32), offset: 0),
        Field(column("b", tbl_file.Float32), offset: 4),
        Field(column("c", tbl_file.Boolean32), offset: 8),
      ],
      12,
    )
    as "game_table.schema: 4-byte fields one after another; the end, 12, is already a multiple of 4 and the record holds no 8-byte field"
}

pub fn a_64_bit_integer_aligns_to_8_test() -> Nil {
  use <- owned_test.run(5000)
  let columns = [
    column("a", tbl_file.Integer32),
    column("b", tbl_file.Integer64),
  ]
  assert tbl_file.layout(columns)
    == #(
      [
        Field(column("a", tbl_file.Integer32), offset: 0),
        Field(column("b", tbl_file.Integer64), offset: 8),
      ],
      16,
    )
    as "game_table.schema: an 8-byte field (a 64-bit integer, type 20) at the next multiple of 8"
}

pub fn the_placement_rule_gives_each_clients_record_size_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.map(
      [
        creature2.schema,
        spell4.schema,
        item2.schema,
        spline2_node.schema,
        localized_text.schema,
      ],
      fn(schema) { #(schema.table, tbl_file.layout(schema.columns).1) },
    )
    == [
      #("Creature2", 696),
      #("Spell4", 424),
      #("Item2", 208),
      #("Spline2Node", 56),
      #("LocalizedText", 28),
    ]
    as "record sizes: Creature2 696 (0x140a61ca0), the others from game_tables.ClientData"
}

pub fn creature2_places_its_description_at_offset_8_test() -> Nil {
  use <- owned_test.run(5000)
  let #(fields, _size) = tbl_file.layout(creature2.schema.columns)
  assert list.length(fields) == 173 as "Creature2 has 173 columns (0x140a61ca0)"
  let assert Ok(description) =
    list.find(fields, fn(field) { field.column.name == "description" })
    as "Creature2 has a column named description"
  assert description.offset == 8
    as "bytes at 0x140a4ef70: 'description' type 0x82, offset 8"
  let assert Ok(first) = list.first(fields) as "Creature2 has columns"
  assert first == Field(column("ID", tbl_file.Integer32), offset: 0)
    as "bytes at 0x140a4ef20: column 0 'id' type 3 offset 0"
}

pub fn a_boolean_column_holds_0_or_1_test() -> Nil {
  use <- owned_test.run(5000)
  assert tbl_file.boolean(0, "flag") == Ok(False)
    as "game_table.column_type: type 11 holds 0 (false) in the files"
  assert tbl_file.boolean(1, "flag") == Ok(True)
    as "game_table.column_type: type 11 holds 1 (true) in the files"
  assert tbl_file.boolean(2, "flag")
    == Error(tbl_file.NotABoolean(column: "flag", value: 2))
    as "no file holds another value in a type-11 column, so another value is not a boolean"
}

fn planted_localized_text() -> BitArray {
  planted_table.bytes(
    planted_table.table(localized_text.schema, [
      planted_table.row(localized_text.schema, [#("ID", Integer(1))]),
    ]),
  )
}

pub fn the_header_and_columns_of_a_planted_file_are_described_test() -> Nil {
  use <- owned_test.run(5000)
  assert tbl_file.describe(planted_localized_text())
    == Ok(Description(
      table: "LocalizedText",
      record_size: 28,
      record_count: 1,
      columns: localized_text.schema.columns,
    ))
    as "game_table.file: the name, record size at 0x18, the column table and the record count at 0x30 of the planted header"
}

pub fn bytes_shorter_than_the_header_are_too_short_test() -> Nil {
  use <- owned_test.run(5000)
  assert tbl_file.describe(<<1, 2, 3>>) == Error(tbl_file.TooShort)
    as "game_table.file: the header is 0x60 bytes"
}

pub fn a_file_without_the_signature_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let assert <<_:size(32), rest:bits>> = planted_localized_text()
    as "the planted file starts with a 4-byte signature"
  assert tbl_file.describe(bit_array.append(<<"NOPE":utf8>>, rest))
    == Error(tbl_file.BadSignature)
    as "0x1407c16d4 compares the first dword with 0x4454424c, else 'Corrupt Tbl File'"
}

pub fn a_file_that_ends_inside_its_column_table_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(cut) = bit_array.slice(planted_localized_text(), 0, 0x60 + 48)
    as "the planted file is longer than its header and name"
  assert tbl_file.describe(cut)
    == Error(tbl_file.OutsideFile(tbl_file.ColumnTable))
    as "ResolveGameTableColumns 0x1407c1e40: the column table of 7 entries of 24 bytes must lie inside the file"
}

pub fn the_clients_creature2_file_is_described_by_its_header_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(envoy.get("GENESIS_NO_CLIENT") != Ok("1"))
  let assert Ok(description) =
    tbl_file.describe(client_tables.read("Creature2"))
    as "Creature2.tbl has a readable header"
  assert description.table == "Creature2"
    as "the table name in the file, 'Creature2' (0x140a7c5f0)"
  assert description.record_size == 696 as "0x140a61ca0: record size 0x2b8"
  assert description.record_count == 56_369
    as "game_tables.ClientData: Creature2 has 56,369 records"
  assert list.length(description.columns) == 173 as "0x140a61ca0: 0xad columns"
  assert list.take(description.columns, 3)
    == [
      column("ID", tbl_file.Integer32),
      column("CreationTypeEnum", tbl_file.Integer32),
      column("description", tbl_file.Utf16Text),
    ]
    as "Creature2.tbl column table: ID type 3, CreationTypeEnum type 3, description type 130 (0x82, 0x140a4ef70)"
}

pub fn a_table_has_an_id_column_when_its_first_column_is_a_32_bit_integer_named_id_test() -> Nil {
  use <- owned_test.run(5000)
  assert tbl_file.has_id_column([
    column("ID", tbl_file.Integer32),
    column("name", tbl_file.Utf16Text),
  ])
    as "column 0 of 375 tables is the 32-bit integer ID (fact file, game_table.file)"
  assert tbl_file.has_id_column([column("id", tbl_file.Integer32)])
    as "and of 9 tables it is named id"
  assert !tbl_file.has_id_column([column("ID", tbl_file.Float32)])
    as "a float named ID is not an id"
  assert !tbl_file.has_id_column([column("ID", tbl_file.Integer64)])
    as "a 64-bit integer named ID is not an id"
  assert !tbl_file.has_id_column([
    column("level", tbl_file.Integer32),
    column("ID", tbl_file.Integer32),
  ])
    as "the id is the first column"
  assert !tbl_file.has_id_column([])
    as "a table with no column has no id column"
}

pub fn a_file_is_placed_only_when_its_record_size_is_the_one_the_placement_rule_gives_test() -> Nil {
  use <- owned_test.run(5000)
  let columns = [
    column("a", tbl_file.Integer32),
    column("b", tbl_file.Utf16Text),
    column("c", tbl_file.Integer32),
  ]
  let described = fn(record_size) {
    Description(table: "Planted", record_size:, record_count: 0, columns:)
  }
  assert tbl_file.place(described(24))
    == Ok([
      Field(column("a", tbl_file.Integer32), offset: 0),
      Field(column("b", tbl_file.Utf16Text), offset: 8),
      Field(column("c", tbl_file.Integer32), offset: 16),
    ])
    as "game_table.schema: the string offset at 8, the last field at 16, the end 20 rounded up to 24"
  assert tbl_file.place(described(32))
    == Error(tbl_file.RecordSizeNotPlaced(placed: 24, header: 32))
    as "a header that says 32 is not the 24 the rule gives"
}

pub fn a_files_fields_are_given_only_with_an_id_first_and_the_record_size_the_rule_gives_test() -> Nil {
  use <- owned_test.run(5000)
  let described = fn(columns, record_size) {
    Description(table: "Planted", record_size:, record_count: 0, columns:)
  }
  let with_id = [
    column("ID", tbl_file.Integer32),
    column("b", tbl_file.Utf16Text),
    column("c", tbl_file.Integer32),
  ]
  assert tbl_file.fields(described(with_id, 24))
    == Ok([
      Field(column("ID", tbl_file.Integer32), offset: 0),
      Field(column("b", tbl_file.Utf16Text), offset: 8),
      Field(column("c", tbl_file.Integer32), offset: 16),
    ])
    as "game_table.schema: the string offset at 8, the last field at 16, the end 20 rounded up to 24"
  assert tbl_file.fields(described(with_id, 32))
    == Error(
      tbl_file.NotPlaced(tbl_file.RecordSizeNotPlaced(placed: 24, header: 32)),
    )
    as "a header that says 32 is not the 24 the rule gives"
  assert tbl_file.fields(described(
      [column("a", tbl_file.Integer32), column("b", tbl_file.Utf16Text)],
      16,
    ))
    == Error(tbl_file.NoIdColumn)
    as "a first column not named id has no id, whatever the record size; a record size of 16 is the right one for these two columns, so only the id is wrong"
}

pub fn a_column_type_has_the_clients_type_code_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.map(
      [
        tbl_file.Integer32,
        tbl_file.Float32,
        tbl_file.Boolean32,
        tbl_file.Integer64,
        tbl_file.Utf16Text,
      ],
      tbl_file.type_code,
    )
    == [3, 4, 11, 20, 130]
    as "game_table.column_type: 3 a 32-bit integer, 4 a 32-bit float, 11 a boolean, 20 a 64-bit integer, 130 a string"
}

pub fn a_files_record_block_is_its_records_back_to_back_test() -> Nil {
  use <- owned_test.run(5000)
  let schema =
    tbl_file.Schema(
      table: "PlantedRecords",
      file: "PlantedRecords",
      record_size: 0,
      columns: [
        column("ID", tbl_file.Integer32),
        column("name", tbl_file.Utf16Text),
        column("count", tbl_file.Integer32),
      ],
    )
  let bytes =
    planted_table.bytes(
      planted_table.table(schema, [
        planted_table.row(schema, [
          #("ID", Integer(1)),
          #("name", planted_table.Text("one")),
          #("count", Integer(0xB2D05E00)),
        ]),
        planted_table.row(schema, [#("ID", Integer(2))]),
        planted_table.row(schema, [#("ID", Integer(3))]),
      ]),
    )
  let assert Ok(tbl_file.Records(description:, bytes: records)) =
    tbl_file.records(bytes)
    as "a planted file's record block is read"
  assert description.table == "PlantedRecords"
  assert description.record_size == 24
    as "game_table.schema: the string offset at 8, the count at 16, the end 20 rounded up to 24"
  assert bit_array.byte_size(records) == 3 * 24
    as "three records of 24 bytes and none of the string data that follows them"
  assert bit_array.slice(records, 0, 4) == Ok(<<1:size(32)-little>>)
    as "the first record starts with its id"
  assert bit_array.slice(records, 16, 4) == Ok(<<0xB2D05E00:size(32)-little>>)
    as "the first record's count is at offset 16"
  assert bit_array.slice(records, 24, 4) == Ok(<<2:size(32)-little>>)
    as "the second record follows at 24"
  assert bit_array.slice(records, 48, 4) == Ok(<<3:size(32)-little>>)
    as "the third record follows at 48"
}

pub fn a_file_cut_inside_its_record_block_has_no_record_block_test() -> Nil {
  use <- owned_test.run(5000)
  let schema = localized_text.schema
  let bytes =
    planted_table.bytes(
      planted_table.table(schema, [
        planted_table.row(schema, [#("ID", Integer(1))]),
        planted_table.row(schema, [#("ID", Integer(2))]),
      ]),
    )
  // The lookup follows the record block and holds 3 entries of 4 bytes (ids 0
  // to 2), so a cut of 20 bytes ends 8 bytes inside the block's last record.
  let assert Ok(cut) =
    bit_array.slice(bytes, 0, bit_array.byte_size(bytes) - 20)
    as "the planted file is longer than the cut"
  assert tbl_file.records(cut)
    == Error(tbl_file.OutsideFile(tbl_file.RecordBlock))
    as "the header says the block holds more bytes than the file has"
}
