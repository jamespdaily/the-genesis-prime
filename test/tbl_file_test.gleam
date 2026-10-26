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
import environment
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
  use <- unitest.guard(environment.get("GENESIS_NO_CLIENT") != Ok("1"))
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
