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
//// - a column holds another table's id when its name is that table's
////   snake-case name, `_id`, and then the end of the name, a digit or an
////   underscore, as the client's column names read (`spell4IdAttackPrimary00`
////   of Class holds Spell4 ids, `localizedTextIdNameFemale` LocalizedText ids,
////   `attributeMilestoneGroupId00` AttributeMilestoneGroup ids; the table
////   files of `game_table.file`). The planted tables use made-up names in the
////   same shape.

import genesis_prime/table/loader/tbl_file.{type Schema, Column, Schema}
import genesis_prime/table_generator
import genesis_prime/table_generator/difference.{
  type Difference, Changed, Extra, Missing,
}
import genesis_prime/table_generator/module_text
import genesis_prime/table_generator/naming
import genesis_prime/table_generator/reference.{type Table, Table}
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/result
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
  table_generator.generate(tables) |> result.map(fn(made) { made.files })
}

/// The differences between the committed code and what the tables generate.
fn differences(
  folder: String,
  source: String,
) -> Result(List(Difference), table_generator.GenerateError) {
  table_generator.check(folder, against: source)
  |> result.map(fn(checked) { checked.differences })
}

/// The table a column names, among tables given as a list.
fn referenced(column: String, tables: List(Table)) -> Result(Table, Nil) {
  reference.referenced_table(column, reference.index(tables))
}

/// A planted table with only an id.
fn id_only_schema(name: String) -> Schema {
  Schema(table: name, file: name, record_size: 0, columns: [
    Column("ID", tbl_file.Integer32),
  ])
}

/// A planted table whose columns name the ids of other planted tables, in the
/// shape of the client's own column names.
fn planted_owner_schema() -> Schema {
  Schema(table: "PlantedOwner", file: "PlantedOwner", record_size: 0, columns: [
    Column("ID", tbl_file.Integer32),
    Column("plantedSpellId", tbl_file.Integer32),
    Column("plantedSpellBaseId", tbl_file.Integer32),
    Column("plantedSpellIdAttack00", tbl_file.Integer32),
    Column("plantedSpellIdle", tbl_file.Integer32),
    Column("plantedMoonId", tbl_file.Integer32),
    Column("weightKg", tbl_file.Float32),
  ])
}

/// The planted tables of the reader tests: two tables, one named as the
/// other with a word added, and a table that names their ids.
fn reference_tables() -> List(#(String, BitArray)) {
  [
    #("PlantedSpell", planted_file(id_only_schema("PlantedSpell"))),
    #("PlantedSpellBase", planted_file(id_only_schema("PlantedSpellBase"))),
    #("PlantedOwner", planted_file(planted_owner_schema())),
  ]
}

fn module_of(files: dict.Dict(String, String), name: String) -> String {
  let assert Ok(text) =
    dict.get(files, "genesis_prime/table/" <> name <> ".gleam")
    as { "the generated files hold the module " <> name }
  text
}

/// The lines of a module's text that start with `pub `, in order.
fn public_lines(text: String) -> List(String) {
  string.split(text, "\n")
  |> list.filter(string.starts_with(_, "pub "))
}

pub fn a_planted_table_gets_a_module_with_its_row_type_and_the_registry_names_it_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(files) =
    generated([#("PlantedThing", planted_file(planted_schema("PlantedThing")))])
    as "a well-formed planted table is generated"
  assert dict.keys(files) |> list.sort(string.compare)
    == [
      "genesis_prime/table.gleam",
      "genesis_prime/table/id.gleam",
      "genesis_prime/table/planted_thing.gleam",
    ]
    as "one module for the table, in the table folder, the module of the typed ids, and the registry"
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
  let assert Ok(_) = table_generator.write(folder, into: source)
    as "the planted tables are written"
  body(folder, source)
}

pub fn code_checked_right_after_it_is_written_has_no_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder, source <- with_written_code
  assert differences(folder, source) == Ok([])
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
  assert differences(folder, source)
    == Ok([Changed("genesis_prime/table/planted_thing.gleam")])
    as "CLAUDE.md: the codec is generated and never edited by hand; the check names the edited file"
}

pub fn a_deleted_generated_module_is_a_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder, source <- with_written_code
  let assert Ok(Nil) =
    simplifile.delete(source <> "/genesis_prime/table/planted_other.gleam")
    as "the generated module can be deleted"
  assert differences(folder, source)
    == Ok([Missing("genesis_prime/table/planted_other.gleam")])
    as "the generator writes the module and the source has none"
}

pub fn a_generated_module_of_a_table_the_client_lacks_is_a_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder, source <- with_written_code
  let assert Ok(Nil) = simplifile.delete(folder <> "/PlantedOther.tbl")
    as "the planted table can be removed from the client's folder"
  assert differences(folder, source)
    == Ok([
      Changed("genesis_prime/table.gleam"),
      Changed("genesis_prime/table/id.gleam"),
      Extra("genesis_prime/table/planted_other.gleam"),
    ])
    as "the registry no longer lists the table, the id module still holds its id, and its module is left over"
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

pub fn the_id_module_holds_one_typed_id_for_each_table_and_nothing_else_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(files) = generated(reference_tables())
    as "the planted tables are generated"
  let id_module = module_of(files, "id")
  assert string.starts_with(id_module, difference.generated_marker)
    as "the id module starts with the marker the check recognises"
  assert public_lines(id_module)
    == [
      "pub type PlantedOwnerId {",
      "pub type PlantedSpellId {",
      "pub type PlantedSpellBaseId {",
    ]
    as "one public type for each of the three tables, in file-name order, and no function or constant"
  assert string.contains(id_module, "PlantedSpellId(value: Int)")
    as "a typed id wraps the table's integer id"
  assert !string.contains(id_module, "import ")
    as "the id module imports nothing, so no table module can make an import cycle with it"
}

pub fn the_committed_id_module_holds_one_typed_id_for_each_table_of_the_registry_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(registry) = simplifile.read("src/genesis_prime/table.gleam")
    as "the committed registry reads"
  let assert Ok(id_module) = simplifile.read("src/genesis_prime/table/id.gleam")
    as "the committed id module reads"
  let entries =
    string.split(registry, "\n")
    |> list.filter(string.ends_with(_, ".entry(),"))
    |> list.length
  assert entries > 0 as "the registry lists entries"
  assert list.length(public_lines(id_module)) == entries
    as "the registry has an entry for each table the client has, and the id module a type for each"
  assert list.all(public_lines(id_module), string.starts_with(_, "pub type "))
    as "nothing but typed ids"
}

pub fn a_column_named_for_another_tables_id_gets_a_reader_of_that_tables_typed_id_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(files) = generated(reference_tables())
    as "the planted tables are generated"
  let owner = module_of(files, "planted_owner")
  list.each(
    [
      "pub fn planted_spell_id(row: PlantedOwner) -> PlantedSpellId {",
      "pub fn planted_spell_base_id(row: PlantedOwner) -> PlantedSpellBaseId {",
      "pub fn planted_spell_id_attack00(row: PlantedOwner) -> PlantedSpellId {",
    ],
    fn(reader) {
      assert string.contains(owner, reader)
        as { "a reader of the shape `" <> reader <> "`" }
    },
  )
  assert string.contains(
    owner,
    "pub fn planted_spell_base_id(row: PlantedOwner) -> PlantedSpellBaseId {\n  PlantedSpellBaseId(row.planted_spell_base_id)",
  )
    as "the reader wraps the row's integer field"
}

pub fn a_table_gets_a_reader_of_its_own_typed_id_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(files) = generated(reference_tables())
    as "the planted tables are generated"
  assert string.contains(
    module_of(files, "planted_owner"),
    "pub fn id(row: PlantedOwner) -> PlantedOwnerId {\n  PlantedOwnerId(row.id)",
  )
    as "column 0 of every table is its id (game_table.file)"
}

pub fn a_column_that_names_no_loaded_table_stays_an_int_with_no_reader_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(files) = generated(reference_tables())
    as "the planted tables are generated"
  let owner = module_of(files, "planted_owner")
  assert string.contains(owner, "planted_moon_id: Int")
    as "no table is named PlantedMoon, so the field is an Int"
  assert !string.contains(owner, "pub fn planted_moon_id(")
    as "a column of no table has no reader"
  assert !string.contains(owner, "pub fn planted_spell_idle(")
    as "plantedSpellIdle is not the id of PlantedSpell: its name goes on after `_id` with a letter"
  assert !string.contains(owner, "pub fn weight_kg(")
    as "a float column has no reader"
}

pub fn a_column_that_names_an_id_of_no_loaded_table_is_listed_with_the_generated_files_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(made) = table_generator.generate(reference_tables())
    as "the planted tables are generated"
  assert made.unmatched
    == [table_generator.IdColumn("PlantedOwner", "plantedMoonId")]
    as "plantedMoonId has the word id and no table is named PlantedMoon; plantedSpellIdle has no id word; the ones that match tables are not listed"
}

pub fn the_longest_table_name_that_matches_a_column_wins_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = Table(snake: "planted_spell", type_name: "PlantedSpell")
  let base = Table(snake: "planted_spell_base", type_name: "PlantedSpellBase")
  let key = Table(snake: "planted_key", type_name: "PlantedKey")
  let key_id = Table(snake: "planted_key_id", type_name: "PlantedKeyId")
  let tables = [spell, base, key, key_id]
  assert referenced("planted_spell_id", tables) == Ok(spell)
    as "the name, `_id` and the end of the column"
  assert referenced("planted_spell_base_id", tables) == Ok(base)
    as "planted_spell_base_id is the id of PlantedSpellBase, not of PlantedSpell, whose `_id` it does not follow"
  assert referenced("planted_spell_base_id01", tables) == Ok(base)
    as "a digit may follow the id, as in the client's spell4IdAttackPrimary00"
  assert referenced("planted_spell_id_attack00", tables) == Ok(spell)
    as "an underscore may follow the id"
  assert referenced("planted_key_id_id", tables) == Ok(key_id)
    as "planted_key_id_id follows both planted_key_id and planted_key_id_id, and the longer name is the table it names"
  assert referenced("planted_key_id_owner", tables) == Ok(key)
    as "the shorter name when only it matches"
}

pub fn a_column_whose_name_goes_on_with_a_letter_after_id_names_no_table_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = Table(snake: "planted_spell", type_name: "PlantedSpell")
  assert referenced("planted_spell_idle", [spell]) == Error(Nil)
    as "`idle` is a word of its own, not the id word"
  assert referenced("planted_spell", [spell]) == Error(Nil)
    as "a column of the table's name with no `_id` is not its id"
  assert referenced("planted_moon_id", [spell]) == Error(Nil)
    as "no loaded table is named planted_moon"
}

pub fn a_get_takes_the_typed_id_of_its_table_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(files) = generated(reference_tables())
    as "the planted tables are generated"
  let spell = module_of(files, "planted_spell")
  assert string.contains(spell, "id id: PlantedSpellId,")
    as "get takes the id of its own table"
  assert string.contains(spell, "store.row(tables, schema.table, id.value)")
    as "and looks the row up by the integer inside"
  assert !string.contains(spell, "id id: Int") as "no get takes a bare Int"
}

pub fn a_table_whose_module_would_be_the_id_module_is_refused_test() -> Nil {
  use <- owned_test.run(5000)
  assert generated([#("Id", planted_file(id_only_schema("Id")))])
    == Error(table_generator.ReservedModule(module: "id", file: "Id"))
    as "genesis_prime/table/id is the module of the typed ids"
}

pub fn a_hand_edit_of_the_id_module_is_a_difference_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder, source <- with_written_code
  let assert Ok(Nil) =
    simplifile.append(
      source <> "/genesis_prime/table/id.gleam",
      "\npub const edited_by_hand = 1\n",
    )
    as "the id module can be edited"
  assert differences(folder, source)
    == Ok([Changed("genesis_prime/table/id.gleam")])
    as "CLAUDE.md: generated code is never edited by hand; the check names the edited file"
}

pub fn write_and_check_give_the_columns_that_name_no_loaded_table_with_one_read_test() -> Nil {
  use <- owned_test.run(60_000)
  use folder <- planted_table.in_folder(reference_tables())
  use source <- planted_table.in_folder([])
  let expected = [table_generator.IdColumn("PlantedOwner", "plantedMoonId")]
  assert table_generator.write(folder, into: source) == Ok(expected)
    as "write gives the list from the same generation that wrote the files"
  let assert Ok(checked) = table_generator.check(folder, against: source)
    as "the check runs"
  assert checked.differences == []
    as "the check regenerates the same formatted code"
  assert checked.unmatched == expected as "the check gives the same list"
}
