//// The client's rows the tests read, committed under
//// `test/fixture/client_tables/`, and what loads, edits and regenerates them.

import client_tables
import fixture_tables
import genesis_prime/fixture_rows
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import genesis_prime/table_rows
import gleam/dict
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
  use <- owned_test.run(120_000)
  // `load_under` adds `requirement.all()` and `derivation.all()`; a table that
  // fails one makes `shared()` crash with the load's own error.
  let tables = fixture_tables.shared()
  assert spell4.all(tables) != []
    as "the fixture holds Spell4 rows once it loads"
}

// 2
pub fn a_file_whose_header_differs_from_the_schema_names_the_table_and_the_first_column_test() -> Nil {
  use <- owned_test.run(120_000)
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
pub fn the_committed_files_are_what_the_generator_makes_from_the_client_test() -> Nil {
  use <- owned_test.run(300_000)
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
      fixture_rows.differences(
        file: fixture_rows.stale_file,
        committed: read(fixture_rows.stale_file),
        regenerated: fixture.stale,
        key_columns: 4,
      ),
    )
  assert differences == []
    as string.join(
      list.map(differences, fixture_rows.describe_difference),
      "\n",
    )
}

pub fn a_difference_names_the_file_the_row_and_whether_it_was_added_removed_or_changed_test() -> Nil {
  use <- owned_test.run(60_000)
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
  use <- owned_test.run(120_000)
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

/// The committed rows as the generator reads the client's.
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
  use <- owned_test.run(120_000)
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
  use <- owned_test.run(120_000)
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
pub fn changed_and_added_load_under_their_own_key_and_leave_the_shared_load_alone_test() -> Nil {
  use <- owned_test.run(300_000)
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
  use <- owned_test.run(120_000)
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

pub fn a_row_added_under_an_id_the_table_holds_is_refused_test() -> Nil {
  use <- owned_test.run(120_000)
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

// 11
pub fn the_fixture_is_loaded_once_and_no_client_table_is_held_twice_test() -> Nil {
  use <- owned_test.run(120_000)
  let key = fixture_tables.shared_key()
  let first = fixture_tables.shared()
  let held = planted_table.persistent_terms_under(key)
  assert held > 0 as "the shared load stores its tables under its key"
  assert fixture_tables.shared() == first
    as "a second call to shared() returns the same tables"
  assert planted_table.persistent_terms_under(key) == held
    as "a second call to shared() stores nothing more"
  assert literal_area.tables_held_twice() == []
    as "no table is held twice in the literal area"
}
