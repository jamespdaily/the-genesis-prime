//// The client's rows as the server's tables: loading, editing and making them
//// again.

import client_tables
import fixture_tables
import genesis_prime/fixture_rows
import genesis_prime/table/creature2
import genesis_prime/table/creature2_outfit_info
import genesis_prime/table/faction2
import genesis_prime/table/faction2_relationship
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import genesis_prime/table/world
import genesis_prime/table_rows
import gleam/dict
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import literal_area
import owned_test
import planted_table
import simplifile
import unitest

fn the_spell(id: Int) -> spell4.Spell4 {
  let assert Ok(row) =
    spell4.get(tables: fixture_tables.shared(), id: Spell4Id(id))
    as { "Spell4 " <> string.inspect(id) <> " is not in the fixture" }
  row
}

// 1
pub fn the_committed_rows_load_with_the_servers_requirements_and_derivations_test() -> Nil {
  use <- owned_test.run(20_000)
  // `server_table.read` adds `requirement.all()` and `derivation.all()`; a table
  // that fails one makes `shared()` crash with the load's own error.
  let tables = fixture_tables.shared()
  assert spell4.all(tables) != []
    as "the fixture holds Spell4 rows once it loads"
}

// 2
pub fn a_file_whose_header_differs_from_the_schema_names_the_table_and_the_first_column_test() -> Nil {
  use <- owned_test.run(5000)
  // The second column of the client's Spell4 table is `description`
  // (`spell4.schema`, from the client file's header).
  assert fixture_tables.parse_table(
      schema: spell4.schema,
      text: "ID\tdescribed\n",
    )
    == Error(
      fixture_tables.Malformed(fixture_rows.HeaderDiffers(
        table: "Spell4",
        position: 2,
        expected: "description",
        found: "described",
      )),
    )
  // A header that ends early differs where the schema goes on.
  assert fixture_tables.parse_table(schema: spell4.schema, text: "ID\n")
    == Error(
      fixture_tables.Malformed(fixture_rows.HeaderDiffers(
        table: "Spell4",
        position: 2,
        expected: "description",
        found: "",
      )),
    )
}

// 3
// The generator reads the client's whole tables, so the test runs alone in the
// client-suite part of `./check` (tag `client_rows`).
pub fn the_committed_files_are_what_the_generator_makes_from_the_client_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.tag("client_rows")
  use <- unitest.guard(client_tables.present())
  let assert Ok(fixture) =
    fixture_rows.generate(
      roots: fixture_tables.roots(),
      folder: client_tables.folder(),
    )
  let read = fn(file) {
    let assert Ok(text) =
      simplifile.read(fixture_tables.folder <> "/" <> file <> ".tsv")
    text
  }
  let differences =
    list.append(
      list.flat_map(fixture_rows.files(), fn(pair) {
        let #(table, file) = pair
        let assert Ok(regenerated) = dict.get(fixture.tables, table)
        fixture_rows.differences(
          file:,
          committed: read(file),
          regenerated:,
          key_columns: 1,
        )
      }),
      list.append(
        fixture_rows.differences(
          file: fixture_rows.stale_file,
          committed: read(fixture_rows.stale_file),
          regenerated: fixture.stale,
          key_columns: 4,
        ),
        fixture_rows.differences(
          file: fixture_rows.whole_file,
          committed: read(fixture_rows.whole_file),
          regenerated: fixture.whole,
          key_columns: 1,
        ),
      ),
    )
  assert differences == []
    as string.join(
      list.map(differences, fixture_rows.describe_difference),
      "\n",
    )
}

pub fn a_difference_names_the_file_the_row_and_whether_it_was_added_removed_or_changed_test() -> Nil {
  use <- owned_test.run(5000)
  assert fixture_rows.differences(
      file: "Spell4",
      committed: "ID\tx\n1\ta\n2\tb\n",
      regenerated: "ID\tx\n2\tc\n3\td\n",
      key_columns: 1,
    )
    == [
      fixture_rows.Difference("Spell4", "1", fixture_rows.Removed),
      fixture_rows.Difference("Spell4", "2", fixture_rows.Changed),
      fixture_rows.Difference("Spell4", "3", fixture_rows.Added),
    ]
  assert fixture_rows.differences(
      file: "Spell4",
      committed: "ID\tx\n1\ta\n",
      regenerated: "ID\ty\n1\ta\n",
      key_columns: 1,
    )
    == [fixture_rows.Difference("Spell4", "header", fixture_rows.Changed)]
}

// 4
pub fn every_reference_of_a_committed_row_reaches_a_committed_row_or_one_the_client_lacks_test() -> Nil {
  use <- owned_test.run(20_000)
  let assert Ok(rows) = fixture_rows_of_folder()
  let assert Ok(stale) = fixture_rows.stale_in(rows)
  let assert Ok(recorded) =
    simplifile.read(
      fixture_tables.folder <> "/" <> fixture_rows.stale_file <> ".tsv",
    )
  // `stale.tsv` holds what the generator found the client has no row for, from
  // the client's whole tables: a reference left over here is a row the closure
  // should have brought in.
  assert fixture_rows.differences(
      file: fixture_rows.stale_file,
      committed: recorded,
      regenerated: fixture_rows.stale_text(stale),
      key_columns: 4,
    )
    == []
}

// T3c-1 test 1
pub fn the_content_tables_are_committed_and_each_root_reaches_a_committed_row_test() -> Nil {
  use <- owned_test.run(20_000)
  // `server_table.content_entries` are the tables only the content load reads:
  // the client's Faction2 holds 1189 rows and Faction2Relationship 1964, kept
  // whole (`the_whole_content_tables_hold_every_row_the_client_holds_test`), and
  // World is the rows the committed rows name.
  assert list.length(fixture_tables.committed_ids(faction2.schema)) == 1189
    as "Faction2 is whole"
  assert list.length(fixture_tables.committed_ids(faction2_relationship.schema))
    == 1964
    as "Faction2Relationship is whole"
  assert fixture_tables.committed_ids(world.schema)
    == [
      22,
      51,
      426,
      625,
      870,
      930,
      983,
      990,
      1061,
      1068,
      1138,
      1149,
      1181,
      1229,
      1232,
      1233,
      1263,
      1319,
      1323,
      1333,
      1387,
      1393,
      1421,
      1437,
      1463,
      1537,
      1606,
      1627,
      1629,
      1634,
      1658,
      1833,
      1892,
      1894,
      1895,
      1901,
      1982,
      2161,
      2166,
      2173,
      2188,
      2189,
      2352,
      2967,
      2979,
      2988,
      2997,
      3009,
      3023,
      3045,
      3094,
      3173,
      3176,
      3180,
      3335,
      3404,
      3406,
      3460,
    ]
    as "the Worlds the tests' maps run in"
  assert fixture_tables.committed_ids(creature2_outfit_info.schema)
    == [
      7475, 7912, 8009, 8201, 8563, 8599, 8612, 8632, 8775, 8952, 8979, 9003,
      9024, 9029, 9052, 9064, 9065, 9074, 9080, 9152, 9350, 9351, 9659, 9739,
      9777, 9796, 9824,
    ]
    as "Creature2OutfitInfo holds the rows the outfit group roots 8170, 10355 and 10359 point to, the one Creature2 11467's group 9675 points to, the one Creature2 12909's group 8607 points to, the one Creature2 74812's group points to, the one Creature2 28739's group 9725 points to, the one the vendors 24491, 27039, 27230 and 50889's group 10505 points to, the one Creature2 57050's group 9766 points to, the one Creature2 11063, 12959 and 16622's group 9756 points to, the one Creature2 11066's group 9757 points to, the one Creature2 74861's group 9772 points to, the two Creature2 73492 and 73567's group 10539 points to (9739 and 9824), the one Creature2 73473 and 73566's group 10572 points to (9796), the one Creature2 53445's group 8704 points to (8009), and none for 8181's 7486, which the client lacks, and the one each creature of the type 23 objectives' groups points to: Creature2 52900 to 52905 (9258, 9470, 9307, 9327, 8896 and 9294, the captives of quest 9122's group 8374), 16645 to 16647 (9024, group 9720), 24310 (9003, group 9699), and 30826 and 30827 (9659, group 10408), and the one each creature of the cast objectives' groups points to: Creature2 34081 (9052, group 9747) and 41604 (9152, group 9839)"
  list.each(
    [
      #(creature2.schema, 73_464),
      #(creature2.schema, 73_465),
      #(spell4.schema, 5649),
      #(world.schema, 22),
    ],
    fn(root) {
      let #(schema, id) = root
      assert fixture_tables.root(table: schema.table, id:) == id
        as "the row is a root"
      assert list.contains(fixture_tables.committed_ids(schema), id)
        as { schema.table <> " " <> int.to_string(id) <> " is committed" }
    },
  )
}

// T3c-1 test 1
// Reads the client's own tables, so the test runs alone in the client-suite part
// of `./check` (tag `client_rows`).
pub fn the_whole_content_tables_hold_every_row_the_client_holds_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.tag("client_rows")
  use <- unitest.guard(client_tables.present())
  list.each(
    [
      #(faction2.schema, 1189),
      #(faction2_relationship.schema, 1964),
      #(world.schema, 2729),
    ],
    fn(entry) {
      let #(schema, expected) = entry
      let client_ids = client_ids(schema)
      assert list.length(client_ids) == expected
        as { "the client's " <> schema.table <> " row count" }
      case schema.table {
        "World" ->
          // The client's World holds 2729 rows and the tests' maps run in 7 of
          // them, so the fixture keeps those 7 and no more.
          list.each(fixture_tables.committed_ids(schema), fn(id) {
            assert list.contains(client_ids, id)
              as { "the client's World holds row " <> int.to_string(id) }
          })
        _ -> {
          assert fixture_tables.committed_ids(schema) == client_ids
            as {
              schema.table <> " holds every row of the client's, in id order"
            }
          Nil
        }
      }
    },
  )
}

/// The ids of the client's own rows of a table, in the client's order.
fn client_ids(schema: tbl_file.Schema) -> List(Int) {
  let assert Ok(client) =
    table_rows.read(bytes: client_tables.read(schema.file), table: schema.table)
    as { "the client's " <> schema.table <> " reads" }
  list.map(client.rows, fn(row) {
    let assert [table_rows.Cell(_, table_rows.Integer32(id)), ..] =
      table_rows.cells(row)
      as "a client row holds its id first"
    id
  })
}

/// The rows read from the kept files.
fn fixture_rows_of_folder() -> Result(
  dict.Dict(String, List(List(table_rows.Cell))),
  fixture_rows.TextRefusal,
) {
  list.try_map(fixture_tables.schemas(), fn(schema) {
    let assert Ok(text) =
      simplifile.read(fixture_tables.folder <> "/" <> schema.file <> ".tsv")
    fixture_rows.parse_table(schema:, text:)
    |> result.map(fn(rows) { #(schema.table, rows) })
  })
  |> result.map(dict.from_list)
}

// 5
pub fn a_row_that_is_not_a_root_fails_with_the_fix_test() -> Nil {
  use <- owned_test.run(5000)
  let roots = fixture_tables.roots()
  assert fixture_tables.check_root(roots:, table: "Spell4", id: 1)
    == Error(fixture_tables.NotARoot(table: "Spell4", id: 1))
  let text =
    fixture_tables.describe(fixture_tables.NotARoot(table: "Spell4", id: 1))
  assert string.contains(text, "roots.tsv")
    as "the text says which file to add the root to"
  assert string.contains(text, "genesis_prime/fixture_rows")
    as "the text says which command makes the rows"
  assert fixture_tables.check_root(roots:, table: "Spell4", id: 41_276)
    == Ok(41_276)
}

// 6
pub fn a_float_cells_bits_are_written_back_unchanged_test() -> Nil {
  use <- owned_test.run(20_000)
  // Spectral Form's effect 178144 (Spell4Effects, spell 58586) holds the Assault
  // Power coefficient 2.531 in parameterValue00: f32 0x4021fbe7 in the client's
  // table (`gleam run -m genesis_prime/table_rows -- Spell4Effects 178144`).
  let expected = <<0x4021fbe7:size(32)>>
  let id = Spell4EffectsId(178_144)
  let spell = fixture_tables.root("Spell4", 58_586)
  let assert Ok(effect) =
    spell4_effects.get(tables: fixture_tables.shared(), id:)
  assert effect.spell_id == spell as "the effect is a row of the root's spell"
  assert <<effect.parameter_value00:float-size(32)>> == expected
    as "the loaded float has the client's 32 bits"
}

// 7
pub fn changed_and_added_edit_on_their_own_heap_and_leave_the_shared_tables_alone_test() -> Nil {
  use <- owned_test.run(30_000)
  let id = fixture_tables.root("Spell4", 41_276)
  let before = the_spell(id).cast_time
  let edited = before + 1
  // The edit is the point of the test: a value the client's row does not hold.
  fixture_tables.changed(
    table: "Spell4",
    id:,
    with: [#("castTime", planted_table.Integer(edited))],
    body: fn(tables) {
      let assert Ok(row) = spell4.get(tables:, id: Spell4Id(id))
      assert row.cast_time == edited as "the changed row holds the new cell"
      assert spell4_effects.get(tables:, id: Spell4EffectsId(178_144))
        == spell4_effects.get(
          tables: fixture_tables.shared(),
          id: Spell4EffectsId(178_144),
        )
        as "a table the edit left alone loads the client's rows"
    },
  )
  // An id below the table's highest: a loaded table is a tuple as long as its
  // highest id, so an id above it makes the load larger. The fixture holds no
  // Spell4 row 1 (`added` refuses an id the table holds).
  let new_id = 1
  fixture_tables.added(
    table: "Spell4",
    copy_of: id,
    id: new_id,
    with: [#("castTime", planted_table.Integer(edited))],
    body: fn(tables) {
      let assert Ok(row) = spell4.get(tables:, id: Spell4Id(new_id))
      assert row.cast_time == edited as "the added row holds the new cell"
      assert row.spell_duration == the_spell(id).spell_duration
        as "the added row keeps the cells of the row it copies"
    },
  )
  assert the_spell(id).cast_time == before
    as "the shared load is unchanged by an edit"
  assert spell4.get(tables: fixture_tables.shared(), id: Spell4Id(new_id))
    == Error(Nil)
    as "the shared load holds no row an edit added"
}

pub fn an_edit_of_an_unknown_table_row_or_column_is_refused_test() -> Nil {
  use <- owned_test.run(20_000)
  let rows = fixture_tables.rows()
  let id = fixture_tables.root("Spell4", 41_276)
  let cell = planted_table.Integer(1)
  assert fixture_tables.change(rows:, table: "NoSuchTable", id:, with: [
      #("castTime", cell),
    ])
    == Error(fixture_tables.NoTable(table: "NoSuchTable"))
  assert fixture_tables.change(rows:, table: "Spell4", id: 2_000_000_002, with: [
      #("castTime", cell),
    ])
    == Error(fixture_tables.NoRow(table: "Spell4", id: 2_000_000_002))
  assert fixture_tables.change(rows:, table: "Spell4", id:, with: [
      #("noSuchColumn", cell),
    ])
    == Error(fixture_tables.NoColumn(table: "Spell4", column: "noSuchColumn"))
  assert fixture_tables.add(
      rows:,
      table: "NoSuchTable",
      copy_of: id,
      id: 2_000_000_003,
      with: [],
    )
    == Error(fixture_tables.NoTable(table: "NoSuchTable"))
  assert fixture_tables.add(
      rows:,
      table: "Spell4",
      copy_of: 2_000_000_002,
      id: 2_000_000_003,
      with: [],
    )
    == Error(fixture_tables.NoRow(table: "Spell4", id: 2_000_000_002))
  assert fixture_tables.add(
      rows:,
      table: "Spell4",
      copy_of: id,
      id: 2_000_000_003,
      with: [#("noSuchColumn", cell)],
    )
    == Error(fixture_tables.NoColumn(table: "Spell4", column: "noSuchColumn"))
}

pub fn an_edit_of_a_content_table_is_refused_naming_the_table_test() -> Nil {
  use <- owned_test.run(20_000)
  let rows = fixture_tables.rows()
  let world = fixture_tables.ContentTable(table: "World")
  assert fixture_tables.change(rows:, table: "World", id: 22, with: [
      #("flags", planted_table.Integer(1)),
    ])
    == Error(world)
    as "a change of a content row is refused, not dropped"
  assert fixture_tables.add(
      rows:,
      table: "World",
      copy_of: 22,
      id: 2_000_000_004,
      with: [],
    )
    == Error(world)
    as "an added content row is refused, not dropped"
  assert fixture_tables.remove(rows:, table: "World", id: 22) == Error(world)
    as "a removed content row is refused, not dropped"
  assert string.contains(fixture_tables.describe(world), "World")
    as "the refusal names the table"
}

pub fn a_removed_row_is_gone_and_an_unknown_table_or_row_is_refused_test() -> Nil {
  use <- owned_test.run(20_000)
  let rows = fixture_tables.rows()
  let id = fixture_tables.root("Spell4", 41_276)
  let assert Ok(without) = fixture_tables.remove(rows:, table: "Spell4", id:)
    as "the fixture holds the row"
  let assert Ok(before) = dict.get(rows, "Spell4")
  let assert Ok(after) = dict.get(without, "Spell4")
  assert list.length(after) == list.length(before) - 1
    as "one row is gone and no other"
  assert fixture_tables.remove(rows: without, table: "Spell4", id:)
    == Error(fixture_tables.NoRow(table: "Spell4", id:))
    as "a row already removed is not held"
  assert fixture_tables.remove(rows:, table: "NoSuchTable", id:)
    == Error(fixture_tables.NoTable(table: "NoSuchTable"))
  assert spell4.get(tables: fixture_tables.shared(), id: Spell4Id(id))
    != Error(Nil)
    as "the shared load still holds the row"
}

pub fn a_row_added_under_an_id_the_table_holds_is_refused_test() -> Nil {
  use <- owned_test.run(20_000)
  let id = fixture_tables.root("Spell4", 41_276)
  assert fixture_tables.add(
      rows: fixture_tables.rows(),
      table: "Spell4",
      copy_of: id,
      id:,
      with: [],
    )
    == Error(fixture_tables.RowHeld(table: "Spell4", id:))
}

pub fn a_row_changed_to_an_id_the_table_holds_is_refused_test() -> Nil {
  use <- owned_test.run(20_000)
  let id = fixture_tables.root("Spell4", 41_276)
  let held = fixture_tables.root("Spell4", 42_276)
  let rows = fixture_tables.rows()
  assert fixture_tables.change(rows:, table: "Spell4", id:, with: [
      #("ID", planted_table.Integer(held)),
    ])
    == Error(fixture_tables.RowHeld(table: "Spell4", id: held))
    as "an edit of the ID column to an id the table holds would hold the id twice"
  let free = 2_000_000_004
  let assert Ok(changed) =
    fixture_tables.change(rows:, table: "Spell4", id:, with: [
      #("ID", planted_table.Integer(free)),
    ])
    as "an edit of the ID column to an id the table does not hold is allowed"
  let assert Ok(spell4_rows) = dict.get(changed, "Spell4")
  assert list.any(spell4_rows, fn(row) {
    row == [planted_table.Integer(free), ..list.drop(row, 1)]
  })
    as "the changed row holds the new id"
}

// 11
pub fn the_fixture_is_read_once_and_every_call_gives_the_same_tables_test() -> Nil {
  use <- owned_test.run(20_000)
  let first = fixture_tables.shared()
  assert fixture_tables.shared() == first
    as "a second call to shared() returns the same tables"
  assert spell4.all(first) != []
    as "the shared tables hold the fixture's Spell4 rows"
}

/// A Prerequisite row of id 1 with every cell zero, empty or false except the
/// columns given.
fn prerequisite_row(changes: List(#(String, Int))) -> List(table_rows.Cell) {
  let assert Ok(schema) =
    list.find(fixture_tables.schemas(), fn(schema) {
      schema.table == "Prerequisite"
    })
  list.map(schema.columns, fn(column) {
    let given = list.key_find(changes, column.name)
    let value = case column.column_type, given {
      tbl_file.Integer32, Ok(number) -> table_rows.Integer32(number)
      tbl_file.Integer32, Error(Nil) -> table_rows.Integer32(0)
      tbl_file.Integer64, Ok(number) -> table_rows.Integer64(number)
      tbl_file.Integer64, Error(Nil) -> table_rows.Integer64(0)
      tbl_file.Float32, _ -> table_rows.Float32(value: 0.0, bits: 0)
      tbl_file.Boolean32, _ -> table_rows.Boolean(False)
      tbl_file.Utf16Text, _ -> table_rows.Text("")
    }
    table_rows.Cell(column.name, value)
  })
  |> list.map(fn(cell) {
    case cell.column == "ID" {
      True -> table_rows.Cell("ID", table_rows.Integer32(1))
      False -> cell
    }
  })
}

/// The references a Prerequisite row makes to rows the table lacks.
fn stale_of_prerequisite(changes: List(#(String, Int))) -> List(String) {
  let assert Ok(stale) =
    fixture_rows.stale_in(
      dict.from_list([#("Prerequisite", [prerequisite_row(changes)])]),
    )
  list.map(stale, fn(entry) {
    entry.target_table <> " " <> int.to_string(entry.target_id)
  })
}

pub fn a_type_11_condition_after_a_condition_of_type_0_is_not_followed_test() -> Nil {
  use <- owned_test.run(5000)
  // The client keeps a row's conditions only up to the first of type 0
  // (`prerequisite.kept_conditions`, 0x1404a5190), so a type 11 condition behind
  // it names no row the server reads.
  assert stale_of_prerequisite([
      #("prerequisiteTypeId1", 11),
      #("objectId1", 999),
    ])
    == []
    as "slot 1 holds type 11 behind a type 0 in slot 0"
  assert stale_of_prerequisite([
      #("prerequisiteTypeId0", 5),
      #("prerequisiteTypeId2", 11),
      #("objectId2", 999),
    ])
    == []
    as "slot 2 holds type 11 behind a type 0 in slot 1"
  // The control: the same condition in a kept slot is followed.
  assert stale_of_prerequisite([
      #("prerequisiteTypeId0", 5),
      #("prerequisiteTypeId1", 11),
      #("objectId1", 999),
    ])
    == ["Prerequisite 999"]
    as "slot 1 holds type 11 after a kept slot 0"
  assert stale_of_prerequisite([
      #("prerequisiteTypeId0", 11),
      #("objectId0", 999),
    ])
    == ["Prerequisite 999"]
    as "slot 0 holds type 11"
}

pub fn one_table_is_read_alone_and_a_table_the_fixture_lacks_is_refused_by_name_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(rows) = fixture_tables.table("XpPerLevel")
    as "XpPerLevel is a table the fixture holds"
  assert rows != [] as "the fixture holds XpPerLevel rows"
  assert dict.get(fixture_tables.rows(), "XpPerLevel") == Ok(rows)
    as "the rows of all tables are the rows of each table read alone"
  assert fixture_tables.table("NoSuchTable")
    == Error(fixture_tables.NoTable(table: "NoSuchTable"))
    as "a table the server does not load is refused by its name, not read as empty"
}

pub fn every_table_of_the_rows_is_the_term_the_table_was_stored_as_not_a_second_copy_test() -> Nil {
  use <- owned_test.run(20_000)
  // A persistent term is copied whole when it is put again, rows included, so
  // the rows of a table stand in the literal area once only when `rows()` holds
  // the very terms `table()` stored.
  let rows = fixture_tables.rows()
  assert dict.size(rows) == list.length(fixture_tables.schemas())
    as "rows() holds every table the server loads"
  list.each(fixture_tables.schemas(), fn(schema) {
    let assert Ok(stored) = fixture_tables.table(schema.table)
      as "the fixture holds the table"
    let assert Ok(held) = dict.get(rows, schema.table)
      as "rows() holds the table"
    assert literal_area.same_term(held, stored)
      as { schema.table <> " in rows() is a copy of the stored table" }
  })
}

pub fn the_escapes_of_a_text_cell_are_read_back_as_they_are_written_test() -> Nil {
  use <- owned_test.run(5000)
  let schema =
    tbl_file.Schema(table: "T", file: "T", record_size: 16, columns: [
      tbl_file.Column("ID", tbl_file.Integer32),
      tbl_file.Column("text", tbl_file.Utf16Text),
    ])
  // A backslash before a letter, a backslash before an escape, a tab, a line
  // break and a carriage return, and a backslash before a combining mark, which
  // is one grapheme with it.
  let texts = [
    "a\\tb", "\\\\n", "x\ty\nz\r", "\\", "plain", "", "e\u{301}t ✓",
    "a\\\u{301}b",
  ]
  list.each(texts, fn(text) {
    let line = "1\t" <> table_rows.escaped(text)
    assert fixture_rows.parse_table(schema:, text: "ID\ttext\n" <> line <> "\n")
      == Ok([
        [
          table_rows.Cell("ID", table_rows.Integer32(1)),
          table_rows.Cell("text", table_rows.Text(text)),
        ],
      ])
      as { "the text " <> string.inspect(text) <> " is read back" }
  })
  // A backslash that starts no escape is refused with the cell it is in.
  assert fixture_rows.parse_table(schema:, text: "ID\ttext\n1\ta\\x\n")
    == Error(fixture_rows.BadCell(
      table: "T",
      line: 2,
      column: "text",
      reason: fixture_rows.BadEscape,
    ))
  assert fixture_rows.parse_table(schema:, text: "ID\ttext\n1\ta\\\n")
    == Error(fixture_rows.BadCell(
      table: "T",
      line: 2,
      column: "text",
      reason: fixture_rows.BadEscape,
    ))
}
