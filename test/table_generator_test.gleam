//// The table-record generator: Gleam names for the client's names, the
//// module written for a table, the refusals, and the check that the committed
//// code is what the generator writes. The tables are planted: small `.tbl`
//// files laid out as the fact file's `game_table.file` says, so every test
//// runs where there is no client. The check against the client's own 384
//// files is the full check's `generated-tables` part.
////
//// Expected values and their sources:
//// - names: a table's module is its client name in snake case and its type the
////   client name; a column's field is its snake-case name, with a trailing
////   underscore for a Gleam keyword (the generator's own naming rule, in
////   `genesis_prime/table_generator/naming`; the names are real client names:
////   Creature2, Spell4Effects, MTXCategory (the table in Redacted.tbl),
////   donutDrawDistance, XSIName, BoneID, reward_xpOverride, preq_quest01,
////   item2CategoryId, and the column `type` of 8 tables).
//// - column 0 of every table is the 32-bit integer ID, named `ID` in 375 tables
////   and `id` in 9 (`game_table.file`).
//// - a record's size is what the placement rule gives
////   (`game_table.schema`); a file whose header says another is refused.

import genesis_prime/table/loader/tbl_file.{type Schema, Column, Schema}
import genesis_prime/table_generator
import genesis_prime/table_generator/difference.{Changed, Extra, Missing}
import genesis_prime/table_generator/module_text
import genesis_prime/table_generator/naming
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import planted_table.{Integer}
import simplifile

pub fn a_table_name_in_camel_case_is_a_snake_case_module_name_test() -> Nil {
  use <- owned_test.run(5000)
  assert naming.module_name("Creature2") == Ok("creature2")
    as "a digit stays with its word"
  assert naming.module_name("Spell4Effects") == Ok("spell4_effects")
    as "a word starts at an upper-case letter after a lower-case letter or digit"
  assert naming.module_name("MTXCategory") == Ok("mtx_category")
    as "an upper-case run ends before the last upper-case letter that a lower-case letter follows"
  assert naming.type_name("MTXCategory") == Ok("MTXCategory")
    as "the type is the client's own name"
}

pub fn a_column_name_is_a_snake_case_field_name_test() -> Nil {
  use <- owned_test.run(5000)
  assert naming.field_name("donutDrawDistance") == Ok("donut_draw_distance")
    as "camel case becomes snake case"
  assert naming.field_name("XSIName") == Ok("xsi_name")
    as "an upper-case run followed by a word"
  assert naming.field_name("BoneID") == Ok("bone_id")
    as "a trailing upper-case run is one word"
  assert naming.field_name("ID") == Ok("id") as "the id column, named ID"
  assert naming.field_name("id") == Ok("id") as "the id column, named id"
  assert naming.field_name("reward_xpOverride") == Ok("reward_xp_override")
    as "an underscore in the client's name is kept"
  assert naming.field_name("preq_quest01") == Ok("preq_quest01")
    as "a name already in snake case is unchanged"
  assert naming.field_name("item2CategoryId") == Ok("item2_category_id")
    as "a digit then an upper-case letter starts a word"
}

pub fn a_column_named_for_a_gleam_keyword_gets_a_trailing_underscore_test() -> Nil {
  use <- owned_test.run(5000)
  assert naming.field_name("type") == Ok("type_")
    as "8 client tables have a column named type, and type is a Gleam keyword"
  assert naming.field_name("case") == Ok("case_") as "case is a Gleam keyword"
}

pub fn a_name_that_is_not_made_of_letters_digits_and_underscores_has_no_gleam_name_test() -> Nil {
  use <- owned_test.run(5000)
  assert naming.field_name("") == Error(naming.NotAName("")) as "an empty name"
  assert naming.field_name("9lives") == Error(naming.NotAName("9lives"))
    as "a Gleam name does not start with a digit"
  assert naming.module_name("has space") == Error(naming.NotAName("has space"))
    as "a space is not a name character"
}

/// A planted table with one column of each type, a column named for a
/// keyword, a 64-bit integer that forces 8-byte alignment, and its id first.
fn planted_schema(name: String) -> Schema {
  Schema(table: name, file: name, record_size: 0, columns: [
    Column("ID", tbl_file.Integer32),
    Column("weightKg", tbl_file.Float32),
    Column("description", tbl_file.Utf16Text),
    Column("isActive", tbl_file.Boolean32),
    Column("bigNumber", tbl_file.Integer64),
    Column("type", tbl_file.Integer32),
  ])
}

fn planted_file(schema: Schema) -> BitArray {
  planted_table.bytes(
    planted_table.table(schema, [
      planted_table.row(schema, [#("ID", Integer(1))]),
    ]),
  )
}

fn generated(
  tables: List(#(String, BitArray)),
) -> Result(dict.Dict(String, String), table_generator.GenerateError) {
  table_generator.generate(tables)
}

pub fn a_planted_table_gets_a_module_with_its_row_type_and_the_registry_names_it_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(files) =
    generated([#("PlantedThing", planted_file(planted_schema("PlantedThing")))])
    as "a well-formed planted table is generated"
  assert dict.keys(files) |> list.sort(string.compare)
    == [
      "genesis_prime/table.gleam",
      "genesis_prime/table/planted_thing.gleam",
    ]
    as "one module for the table, in the table folder, and the registry"
  let assert Ok(module) =
    dict.get(files, "genesis_prime/table/planted_thing.gleam")
    as "the table's module is among the files"
  assert string.starts_with(module, difference.generated_marker)
    as "every generated file starts with the marker the check recognises"
  list.each(
    [
      "pub type PlantedThing {",
      "id: Int",
      "weight_kg: Float",
      "description: String",
      "is_active: Bool",
      "big_number: Int",
      "type_: Int",
    ],
    fn(text) {
      assert string.contains(module, text)
        as {
          "the row type holds a field `" <> text <> "`, one per column in order"
        }
    },
  )
  let assert Ok(registry) = dict.get(files, "genesis_prime/table.gleam")
    as "the registry is among the files"
  assert string.starts_with(registry, difference.generated_marker)
    as "the registry starts with the marker"
  assert string.contains(registry, "planted_thing.entry()")
    as "the registry lists the table's entry"
}

pub fn a_file_that_is_not_a_table_file_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  assert generated([#("Broken", <<1, 2, 3>>)])
    == Error(table_generator.UnreadableTable("Broken"))
    as "bytes shorter than a header are not a table file"
}

pub fn a_table_whose_first_column_is_not_the_id_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let schema =
    Schema(..planted_schema("PlantedThing"), columns: [
      Column("serial", tbl_file.Integer32),
    ])
  assert generated([#("PlantedThing", planted_file(schema))])
    == Error(table_generator.BadTable(
      "PlantedThing",
      module_text.NoIdColumn("PlantedThing"),
    ))
    as "game_table.file: column 0 is the 32-bit integer ID in every file, so a table without it has no id to index its rows by"
}

pub fn two_columns_with_one_field_name_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let schema =
    Schema(..planted_schema("PlantedThing"), columns: [
      Column("ID", tbl_file.Integer32),
      Column("weightKg", tbl_file.Float32),
      Column("weight_kg", tbl_file.Float32),
    ])
  assert generated([#("PlantedThing", planted_file(schema))])
    == Error(table_generator.BadTable(
      "PlantedThing",
      module_text.DuplicateField("PlantedThing", "weight_kg"),
    ))
    as "weightKg and weight_kg are both the field weight_kg"
}

pub fn a_header_record_size_that_the_placement_rule_does_not_give_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let planted =
    planted_table.Planted(
      ..planted_table.table(planted_schema("PlantedThing"), [
        planted_table.row(planted_schema("PlantedThing"), [
          #("ID", Integer(1)),
        ]),
      ]),
      header_record_size: Some(48),
    )
  assert generated([#("PlantedThing", planted_table.bytes(planted))])
    == Error(table_generator.BadTable(
      "PlantedThing",
      module_text.LayoutDiffers("PlantedThing", placed: 40, header: 48),
    ))
    as "game_table.schema: the placement rule gives 40 bytes (id at 0, weight at 4, string offset at 8, flag at 16, 64-bit integer at 24, type at 32, end 36 rounded up to 8); the planted header says 48"
}

pub fn two_files_holding_tables_of_one_module_name_are_refused_test() -> Nil {
  use <- owned_test.run(5000)
  let file = planted_file(planted_schema("PlantedThing"))
  assert generated([#("First", file), #("Second", file)])
    == Error(table_generator.DuplicateModule(
      module: "planted_thing",
      first: "First",
      second: "Second",
    ))
    as "both files hold the table PlantedThing, so both would be the module planted_thing"
}

/// Writes two planted tables into a source folder and runs `body` with the
/// folder that holds the tables and the source folder.
fn with_written_code(body: fn(String, String) -> a) -> a {
  let tables = [
    #("PlantedThing", planted_file(planted_schema("PlantedThing"))),
    #("PlantedOther", planted_file(planted_schema("PlantedOther"))),
  ]
  use folder <- planted_table.in_folder(tables)
  use source <- planted_table.in_folder([])
  let assert Ok(Nil) = table_generator.write(folder, into: source)
    as "the planted tables are written"
  body(folder, source)
}

pub fn code_checked_right_after_it_is_written_has_no_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder, source <- with_written_code
  assert table_generator.check(folder, against: source) == Ok([])
    as "the check regenerates the same formatted code"
}

pub fn a_hand_edit_of_a_generated_module_is_a_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder, source <- with_written_code
  let assert Ok(Nil) =
    simplifile.append(
      source <> "/genesis_prime/table/planted_thing.gleam",
      "\npub const edited_by_hand = 1\n",
    )
    as "the generated module can be edited"
  assert table_generator.check(folder, against: source)
    == Ok([Changed("genesis_prime/table/planted_thing.gleam")])
    as "CLAUDE.md: the codec is generated and never edited by hand; the check names the edited file"
}

pub fn a_deleted_generated_module_is_a_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder, source <- with_written_code
  let assert Ok(Nil) =
    simplifile.delete(source <> "/genesis_prime/table/planted_other.gleam")
    as "the generated module can be deleted"
  assert table_generator.check(folder, against: source)
    == Ok([Missing("genesis_prime/table/planted_other.gleam")])
    as "the generator writes the module and the source has none"
}

pub fn a_generated_module_of_a_table_the_client_lacks_is_a_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder, source <- with_written_code
  let assert Ok(Nil) = simplifile.delete(folder <> "/PlantedOther.tbl")
    as "the planted table can be removed from the client's folder"
  assert table_generator.check(folder, against: source)
    == Ok([
      Changed("genesis_prime/table.gleam"),
      Extra("genesis_prime/table/planted_other.gleam"),
    ])
    as "the registry no longer lists the table and its module is left over"
}

pub fn a_file_the_repository_wrote_by_hand_is_not_a_difference_test() -> Nil {
  use <- owned_test.run(5000)
  let text = difference.generated_marker <> "\n"
  let generated = dict.from_list([#("genesis_prime/table/a.gleam", text)])
  let committed =
    dict.from_list([
      #("genesis_prime/table/a.gleam", text),
      #("genesis_prime/table/loader/store.gleam", "//// Reads the tables.\n"),
    ])
  assert difference.between(generated:, committed:) == []
    as "a committed file without the marker is the repository's own"
}

pub fn changed_missing_and_extra_files_are_each_named_in_path_order_test() -> Nil {
  use <- owned_test.run(5000)
  let marker = difference.generated_marker
  let generated =
    dict.from_list([
      #("b.gleam", marker <> "\n// new"),
      #("a.gleam", marker <> "\n// same"),
      #("c.gleam", marker <> "\n// only generated"),
    ])
  let committed =
    dict.from_list([
      #("a.gleam", marker <> "\n// same"),
      #("b.gleam", marker <> "\n// old"),
      #("d.gleam", marker <> "\n// only committed"),
    ])
  assert difference.between(generated:, committed:)
    == [Changed("b.gleam"), Missing("c.gleam"), Extra("d.gleam")]
    as "b differs, c is not committed, d is not generated; a is the same"
}
