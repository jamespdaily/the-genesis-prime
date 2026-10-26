//// Loading the client's game tables. The real-client tests read the extracted
//// files and are skipped where `GENESIS_NO_CLIENT=1`; the planted tests write
//// small `.tbl` files laid out as the fact file's `game_table.file` says and
//// run everywhere.
////
//// Expected values and their sources:
//// - the client has 384 game tables, 2,116,954 records in all, each file's
////   record count in its header at 0x30, lookup count at 0x48 and lookup
////   offset at 0x50 (counted from 0x60): `game_tables.ClientData`,
////   `game_table.file`.
//// - a lookup holds, for each id from 0, the row index of the record with that
////   id or 0xFFFFFFFF, and the lookup entry of every row equals its index
////   (`game_table.file`: "lookup[ID] equals the row index for every row"); the
////   client rejects an entry at or past the record count when a record is
////   fetched (0x1407c1115 `cmp edx, [r8 + 0x30]`).
//// - every string field points past the records into the string data, at
////   UTF-16 text ending in a zero character (`game_table.file`, parsing all
////   384 files).
//// - a type-11 column holds 0 or 1 in every file (`game_table.column_type`).
//// - the client loads a file only when its table name, record size, column
////   count and every column's name and type equal the schema's, and otherwise
////   logs "Your Tbl file does not match the Header file"
////   (`game_table.schema`, `MatchGameTableSchema` 0x1407c19f0).
//// - a missing row fails the load: CLAUDE.md, "Game tables load once at start
////   into named records; a missing row fails the load".

import client_tables
import environment
import genesis_prime/table
import genesis_prime/table/creature2
import genesis_prime/table/loader/store
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/localized_text
import gleam/bit_array
import gleam/erlang/reference
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import owned_test
import planted_table.{Integer, Text, TextAt}
import simplifile
import unitest

fn client_present() -> Bool {
  environment.get("GENESIS_NO_CLIENT") != Ok("1")
}

/// Every table file of the client, as the file's name without `.tbl`.
fn the_clients_table_files() -> List(String) {
  client_tables.files()
}

/// The header's record count (u64 at 0x30) and the ids the lookup array names,
/// read from the file's bytes without the code under test.
fn counted_by_the_file(file: String) -> #(Int, List(Int)) {
  let bytes = client_tables.read(file)
  let assert <<
    _:bytes-size(0x30),
    record_count:size(64)-little,
    _:bytes-size(16),
    lookup_count:size(64)-little,
    lookup_offset:size(64)-little,
    _:bits,
  >> = bytes
    as "the client's table file is shorter than its header"
  let assert Ok(lookup) =
    bit_array.slice(bytes, 0x60 + lookup_offset, lookup_count * 4)
    as "the lookup lies outside the file"
  #(record_count, ids_of_lookup(lookup:, id: 0, found: []))
}

fn ids_of_lookup(
  lookup lookup: BitArray,
  id id: Int,
  found found: List(Int),
) -> List(Int) {
  case lookup {
    <<0xFFFFFFFF:size(32)-little, rest:bits>> ->
      ids_of_lookup(lookup: rest, id: id + 1, found:)
    <<_:size(32)-little, rest:bits>> ->
      ids_of_lookup(lookup: rest, id: id + 1, found: [id, ..found])
    _ -> list.reverse(found)
  }
}

pub fn every_client_table_loads_and_holds_the_rows_its_header_and_lookup_name_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_present())
  let entries = table.entries()
  assert list.length(entries) == 384
    as "game_tables.ClientData: 384 game tables in ClientData"
  assert list.map(entries, store.file) == the_clients_table_files()
    as "one entry per table file, in file-name order"
  let assert Ok(tables) =
    table.load(under: reference.new(), from: client_tables.folder())
    as "the client's 384 tables did not all load"
  let counted =
    list.map(entries, fn(entry) {
      let #(record_count, lookup_ids) = counted_by_the_file(store.file(entry))
      let ids = store.ids(entry, tables)
      assert list.length(ids) == record_count
        as { store.file(entry) <> ".tbl: the header's record count at 0x30" }
      assert ids == lookup_ids
        as {
          store.file(entry)
          <> ".tbl: the ids with a row are the ids the lookup array names"
        }
      record_count
    })
  assert int.sum(counted) == 2_116_954
    as "game_tables.ClientData: 2,116,954 records in all"
  store.unload(tables)
}

pub fn a_table_file_that_is_missing_fails_the_load_naming_the_file_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- planted_table.in_folder([])
  assert store.load(
      under: reference.new(),
      from: folder,
      entries: [localized_text.entry()],
      requirements: [],
    )
    == Error(store.TableFileUnreadable("LocalizedText", simplifile.Enoent))
    as "LocalizedText.tbl is not in the folder, so reading it fails with enoent"
}

pub fn localized_text_file(rows: List(List(planted_table.Cell))) -> BitArray {
  planted_table.bytes(planted_table.table(localized_text.schema, rows))
}

pub fn localized_text_row(id: Int, version: Int) -> List(planted_table.Cell) {
  planted_table.row(localized_text.schema, [
    #("ID", Integer(id)),
    #("version", Integer(version)),
  ])
}

pub fn a_planted_table_loads_and_gives_each_row_by_id_and_nothing_for_a_gap_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    localized_text_file([localized_text_row(1, 7), localized_text_row(3, 9)])
  use folder <- planted_table.in_folder([#("LocalizedText", file)])
  let key = reference.new()
  let assert Ok(tables) =
    store.load(
      under: key,
      from: folder,
      entries: [localized_text.entry()],
      requirements: [],
    )
    as "a planted table with two rows loads"
  let assert Ok(one) = localized_text.get(tables, 1)
    as "id 1 has a record: lookup entry 0"
  assert one.version == 7 as "the planted version of id 1"
  let assert Ok(three) = localized_text.get(tables, 3)
    as "id 3 has a record: lookup entry 1"
  assert three.version == 9 as "the planted version of id 3"
  assert localized_text.get(tables, 2) == Error(Nil)
    as "GameTableRecordById 0x1407c10d0: an id whose lookup entry is 0xffffffff has no record"
  assert localized_text.get(tables, 0) == Error(Nil)
    as "id 0 has lookup entry 0xffffffff"
  assert localized_text.get(tables, 4) == Error(Nil)
    as "0x1407c1108 cmp edi, [r8 + 0x48]: an id at or past the lookup count (4) has no record"
  assert list.map(localized_text.all(tables), fn(row) { row.id }) == [1, 3]
    as "the rows in id order"
  assert planted_table.persistent_terms_under(key) == 1
    as "one persistent term per table"
  store.unload(tables)
  assert planted_table.persistent_terms_under(key) == 0
    as "unload erases the table's term"
}

pub fn a_failed_load_leaves_no_persistent_term_behind_test() -> Nil {
  use <- owned_test.run(5000)
  let file = localized_text_file([localized_text_row(1, 7)])
  use folder <- planted_table.in_folder([#("LocalizedText", file)])
  let key = reference.new()
  let loaded =
    store.load(
      under: key,
      from: folder,
      entries: [localized_text.entry(), creature2.entry()],
      requirements: [],
    )
  assert result.is_error(loaded)
    as "Creature2.tbl is not in the folder, so the load fails"
  assert planted_table.persistent_terms_under(key) == 0
    as "the load erased LocalizedText's term, written before Creature2 failed"
}

pub fn creature2_file(
  localized_text_id_name: Int,
  more: List(#(String, planted_table.Cell)),
) -> BitArray {
  planted_table.bytes(
    planted_table.table(creature2.schema, [
      planted_table.row(creature2.schema, [
        #("ID", Integer(1)),
        #("localizedTextIdName", Integer(localized_text_id_name)),
        ..more
      ]),
    ]),
  )
}

/// The rule that Creature2's `localizedTextIdName` names a LocalizedText row,
/// as a requirement written with the generated modules.
pub fn creature2_names_a_localized_text() -> store.Requirement {
  store.Requirement(
    from_table: "Creature2",
    column: "localizedTextIdName",
    to_table: "LocalizedText",
    missing: fn(tables) {
      creature2.all(tables)
      |> list.map(fn(row) { row.localized_text_id_name })
      |> list.filter(fn(id) { result.is_error(localized_text.get(tables, id)) })
    },
  )
}

pub fn a_row_another_table_requires_that_is_missing_fails_the_load_naming_both_tables_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- planted_table.in_folder([
    #("Creature2", creature2_file(14_610, [])),
    #("LocalizedText", localized_text_file([localized_text_row(1, 7)])),
  ])
  let key = reference.new()
  assert store.load(
      under: key,
      from: folder,
      entries: [creature2.entry(), localized_text.entry()],
      requirements: [creature2_names_a_localized_text()],
    )
    == Error(store.RowMissing(
      from_table: "Creature2",
      column: "localizedTextIdName",
      to_table: "LocalizedText",
      id: 14_610,
    ))
    as "CLAUDE.md: a missing row fails the load; Creature2 row 1 names LocalizedText id 14610, which the planted LocalizedText lacks"
  assert planted_table.persistent_terms_under(key) == 0
    as "a load that fails on a missing row erases its terms"
}

pub fn a_row_another_table_requires_that_is_present_loads_test() -> Nil {
  use <- owned_test.run(5000)
  use folder <- planted_table.in_folder([
    #("Creature2", creature2_file(14_610, [])),
    #(
      "LocalizedText",
      localized_text_file([
        localized_text_row(1, 7),
        localized_text_row(14_610, 3),
      ]),
    ),
  ])
  let assert Ok(tables) =
    store.load(
      under: reference.new(),
      from: folder,
      entries: [creature2.entry(), localized_text.entry()],
      requirements: [creature2_names_a_localized_text()],
    )
    as "the required LocalizedText row 14610 is present, so the load succeeds"
  store.unload(tables)
}

pub fn a_file_whose_table_name_differs_from_the_schema_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let other = tbl_file.Schema(..localized_text.schema, table: "SomethingElse")
  assert load_planted_localized_text(other, [localized_text_row(1, 7)])
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.TableNameDiffers(
        expected: "LocalizedText",
        found: "SomethingElse",
      ),
    ))
    as "MatchGameTableSchema 0x1407c19f0 compares the table name with the schema's"
}

pub fn a_file_whose_column_count_differs_from_the_schema_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let other =
    tbl_file.Schema(
      ..localized_text.schema,
      columns: list.take(localized_text.schema.columns, 6),
    )
  assert load_planted_localized_text(other, [localized_text_row_for(other)])
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.ColumnCountDiffers(expected: 7, found: 6),
    ))
    as "0x1407c1a30 cmp ebp, [rbx + 0x18]: the column count must equal the schema's"
}

pub fn a_file_whose_column_name_differs_from_the_schema_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let renamed =
    list.map(localized_text.schema.columns, fn(column) {
      case column.name {
        "version" -> tbl_file.Column(..column, name: "revision")
        _ -> column
      }
    })
  let other = tbl_file.Schema(..localized_text.schema, columns: renamed)
  assert load_planted_localized_text(other, [localized_text_row_for(other)])
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.ColumnDiffers(
        position: 3,
        expected: tbl_file.Column("version", tbl_file.Integer32),
        found: tbl_file.Column("revision", tbl_file.Integer32),
      ),
    ))
    as "0x1407c1a68 compares each column's name with the schema's"
}

pub fn a_file_whose_column_type_differs_from_the_schema_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let retyped =
    list.map(localized_text.schema.columns, fn(column) {
      case column.name {
        "version" -> tbl_file.Column(..column, column_type: tbl_file.Float32)
        _ -> column
      }
    })
  let other = tbl_file.Schema(..localized_text.schema, columns: retyped)
  assert load_planted_localized_text(other, [localized_text_row_for(other)])
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.ColumnDiffers(
        position: 3,
        expected: tbl_file.Column("version", tbl_file.Integer32),
        found: tbl_file.Column("version", tbl_file.Float32),
      ),
    ))
    as "0x1407c1a74 compares each column's type with the schema's"
}

pub fn a_file_whose_record_size_differs_from_the_schema_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted_table.Planted(
      ..planted_table.table(localized_text.schema, [localized_text_row(1, 7)]),
      header_record_size: Some(32),
    )
    |> planted_table.bytes
  assert load_file("LocalizedText", file)
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.RecordSizeDiffers(expected: 28, found: 32),
    ))
    as "0x1407c1a23 cmp [rdi + 0x8], eax: the record size must equal the schema's; LocalizedText's is 28 (game_tables.ClientData)"
}

/// A planted LocalizedText file laid out by `schema`, loaded as the real one.
fn load_planted_localized_text(
  schema: tbl_file.Schema,
  rows: List(List(planted_table.Cell)),
) -> Result(store.Tables, store.LoadError) {
  load_file(
    "LocalizedText",
    planted_table.bytes(planted_table.table(schema, rows)),
  )
}

fn localized_text_row_for(schema: tbl_file.Schema) -> List(planted_table.Cell) {
  planted_table.row(schema, [#("ID", Integer(1))])
}

fn load_file(
  file: String,
  bytes: BitArray,
) -> Result(store.Tables, store.LoadError) {
  use folder <- planted_table.in_folder([#(file, bytes)])
  store.load(
    under: reference.new(),
    from: folder,
    entries: [localized_text.entry()],
    requirements: [],
  )
}

pub fn a_lookup_that_names_a_record_of_another_id_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted_table.Planted(
      ..planted_table.table(localized_text.schema, [
        localized_text_row(1, 7),
        localized_text_row(2, 9),
      ]),
      lookup: Some([0xFFFFFFFF, 1, 0]),
    )
    |> planted_table.bytes
  assert load_file("LocalizedText", file)
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.LookupDisagrees(id: 1, found: 2),
    ))
    as "game_table.file: lookup[ID] equals the row index for every row; the planted lookup sends id 1 to row 1, which holds id 2"
}

pub fn a_lookup_entry_past_the_record_count_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted_table.Planted(
      ..planted_table.table(localized_text.schema, [
        localized_text_row(1, 7),
        localized_text_row(2, 9),
      ]),
      lookup: Some([0xFFFFFFFF, 5, 1]),
    )
    |> planted_table.bytes
  assert load_file("LocalizedText", file)
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.LookupPointsOutside(id: 1, row: 5),
    ))
    as "0x1407c1115 cmp edx, [r8 + 0x30]: a lookup entry at or past the record count (2) is no record"
}

pub fn a_record_the_lookup_never_names_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let file =
    planted_table.Planted(
      ..planted_table.table(localized_text.schema, [
        localized_text_row(1, 7),
        localized_text_row(2, 9),
      ]),
      lookup: Some([0xFFFFFFFF, 0, 0xFFFFFFFF]),
    )
    |> planted_table.bytes
  assert load_file("LocalizedText", file)
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.RecordsNotInLookup(expected: 2, found: 1),
    ))
    as "game_table.file: the lookup names every record; the header counts 2 records and the planted lookup names 1"
}

fn creature2_with(
  changes: List(#(String, planted_table.Cell)),
) -> Result(store.Tables, store.LoadError) {
  let file =
    planted_table.bytes(
      planted_table.table(creature2.schema, [
        planted_table.row(creature2.schema, [#("ID", Integer(1)), ..changes]),
      ]),
    )
  use folder <- planted_table.in_folder([#("Creature2", file)])
  store.load(
    under: reference.new(),
    from: folder,
    entries: [creature2.entry()],
    requirements: [],
  )
}

pub fn a_string_offset_into_the_records_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  assert creature2_with([#("description", TextAt(offset: 0))])
    == Error(store.TableFileInvalid(
      "Creature2",
      tbl_file.BadRecord(
        row: 0,
        error: tbl_file.TextOutsideStrings(column: "description", offset: 0),
      ),
    ))
    as "game_table.file: every string points past the records into the string data; offset 0 is the first record"
}

pub fn a_string_offset_past_the_end_of_the_string_data_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  assert creature2_with([#("description", TextAt(offset: 1_000_000))])
    == Error(store.TableFileInvalid(
      "Creature2",
      tbl_file.BadRecord(
        row: 0,
        error: tbl_file.TextOutsideStrings(
          column: "description",
          offset: 1_000_000,
        ),
      ),
    ))
    as "game_table.file: every string ends inside the string data; the planted block is under 1000000 bytes"
}

pub fn a_string_in_the_string_data_loads_with_its_text_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(tables) =
    creature2_with([#("description", Text("Planted Creature"))])
    as "a string written into the string data resolves"
  let assert Ok(row) = creature2.get(tables, 1) as "id 1 has a record"
  assert row.description == "Planted Creature"
    as "the UTF-16 text the planted string data holds"
  store.unload(tables)
}

fn cut_off(bytes: BitArray, last count: Int) -> BitArray {
  let assert Ok(kept) =
    bit_array.slice(bytes, 0, bit_array.byte_size(bytes) - count)
    as "the planted file is longer than the cut"
  kept
}

pub fn a_file_that_ends_inside_its_record_block_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let file = cut_off(localized_text_file([localized_text_row(1, 7)]), last: 18)
  assert load_file("LocalizedText", file)
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.OutsideFile(tbl_file.RecordBlock),
    ))
    as "ResolveGameTableHeader 0x1407c1f00: the record block (header 0x40 offset, 0x38 size) must lie inside the file; this one loses 10 bytes of its 28-byte record and the 8-byte lookup"
}

pub fn a_file_that_ends_inside_its_lookup_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let file = cut_off(localized_text_file([localized_text_row(1, 7)]), last: 4)
  assert load_file("LocalizedText", file)
    == Error(store.TableFileInvalid(
      "LocalizedText",
      tbl_file.OutsideFile(tbl_file.Lookup),
    ))
    as "0x1407c1f9a..0x1407c1fc6: the lookup (header 0x50 offset, 0x48 count of 4-byte entries) must lie inside the file; this one loses its last entry"
}
