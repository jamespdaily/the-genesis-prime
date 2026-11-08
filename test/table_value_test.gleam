//// The server's game tables as one plain value (`genesis_prime/table/loader/store`).
//// Expected values come from these places.
//// - A table the loader reads holds the rows of its file, each at the slot of its
////   id, and a slot with no row reads as no row (GameTableRecordById 0x1407c10d0:
////   an id whose lookup entry is 0xffffffff has no record). The planted rows are the
////   input of each test, so a row's expected cell is the one the test planted.
//// - A test edit builds the changed table anew on the test's own heap and every
////   other table is the loaded one (store `edit`); a table the load lacks is the
////   rows the edit puts, and a derived value an edit does not rebuild is not there.
//// - A refusal on an edited value says what a refusal on a load says: a requirement
////   names the missing row of its table (`character_state.requirements`: the server's
////   playable classes are Class rows 1, 2, 3, 4, 5 and 7), and the plan's derivation
////   names the Spell4 row an ability's tree of casts names
////   (`spell_plan.describe`).
//// - The literal area holds what the shared loads and the server's start put there
////   once. A stored value is held for the life of the VM, and erasing or replacing it
////   would copy the whole of it into every process that holds it, so the tests of
////   what the area holds run in a node of their own (`fresh_node`), where nothing
////   else has stored a term, and compare the area's persistent terms before and after.

import ask_support
import character_tables
import fixture_tables
import fresh_node
import genesis_prime/game/appearance
import genesis_prime/game/character_state
import genesis_prime/game/rating
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan
import genesis_prime/game/top_zone
import genesis_prime/table/class
import genesis_prime/table/creature2
import genesis_prime/table/id
import genesis_prime/table/loader/server_table
import genesis_prime/table/loader/store
import genesis_prime/table/localized_text
import genesis_prime/table/spell4
import genesis_prime/table/world
import gleam/list
import gleam/result
import literal_area
import owned_test
import planted_table.{Integer}

fn localized_text_file(rows: List(#(Int, Int))) -> BitArray {
  planted_table.bytes(planted_table.table(
    localized_text.schema,
    list.map(rows, fn(row) {
      planted_table.row(localized_text.schema, [
        #("ID", Integer(row.0)),
        #("version", Integer(row.1)),
      ])
    }),
  ))
}

fn creature2_file(rows: List(#(Int, Int))) -> BitArray {
  planted_table.bytes(planted_table.table(
    creature2.schema,
    list.map(rows, fn(row) {
      planted_table.row(creature2.schema, [
        #("ID", Integer(row.0)),
        #("localizedTextIdName", Integer(row.1)),
      ])
    }),
  ))
}

const ids_key: store.DerivedKey(List(Int)) = store.DerivedKey("LocalizedTextIds")

fn ids_derivation() -> store.Derivation {
  store.derivation(key: ids_key, build: fn(tables) {
    Ok(store.ids(localized_text.entry(), tables))
  })
}

/// The planted LocalizedText rows every test below starts from: ids 1, 3 and 5,
/// with versions 7, 9 and 11.
fn base_rows() -> List(#(Int, Int)) {
  [#(1, 7), #(3, 9), #(5, 11)]
}

/// Runs the body on the base value read from planted files, with the ids derived.
fn with_base(body: fn(store.Tables) -> a) -> a {
  use folder <- planted_table.in_folder([
    #("LocalizedText", localized_text_file(base_rows())),
  ])
  let assert Ok(tables) =
    store.read(
      from: folder,
      entries: [localized_text.entry()],
      requirements: [],
      derivations: [ids_derivation()],
    )
    as "the planted rows load"
  body(tables)
}

fn version_of(tables: store.Tables, row_id: Int) -> Result(Int, Nil) {
  localized_text.get(tables, id.LocalizedTextId(row_id))
  |> result.map(fn(row) { row.version })
}

fn ids_of(tables tables: store.Tables) -> List(Int) {
  list.map(localized_text.all(tables), fn(row) { row.id })
}

fn edit(
  tables tables: store.Tables,
  with edits: List(store.Edit),
  derivations derivations: List(store.Derivation),
) -> store.Tables {
  let assert Ok(edited) =
    store.edit(tables:, with: edits, requirements: [], derivations:)
    as "the edit gives a value"
  edited
}

pub fn a_value_load_reads_every_row_and_derived_value_the_files_hold_test() -> Nil {
  use <- owned_test.run(5000)
  use tables <- with_base
  assert list.map(base_rows(), fn(row) { version_of(tables, row.0) })
    == [Ok(7), Ok(9), Ok(11)]
    as "each planted row reads back at its id with the version planted"
  assert ids_of(tables: tables) == [1, 3, 5]
    as "rows lists the planted ids in order"
  assert store.derived(tables:, key: ids_key) == [1, 3, 5]
    as "the derived value is built from the loaded rows"
  assert version_of(tables, 2) == Error(Nil)
    as "GameTableRecordById 0x1407c10d0: an id the file has no row for has no record"
}

pub fn a_changed_row_reads_back_changed_and_every_other_row_reads_from_the_base_test() -> Nil {
  use <- owned_test.run(5000)
  use tables <- with_base
  let edited =
    edit(
      tables:,
      with: [
        store.put_rows(localized_text.entry(), localized_text_file([#(3, 99)])),
      ],
      derivations: [],
    )
  assert version_of(edited, 3) == Ok(99) as "the changed row reads the new cell"
  assert version_of(edited, 1) == Ok(7) as "an unchanged row reads as it was"
  assert version_of(edited, 5) == Ok(11) as "an unchanged row reads as it was"
  assert ids_of(tables: edited) == [1, 3, 5] as "a changed row adds no id"
  assert version_of(tables, 3) == Ok(9)
    as "the base value still holds the row it loaded: the edit is a new value"
}

pub fn an_added_row_reads_back_and_a_removed_row_is_not_a_row_test() -> Nil {
  use <- owned_test.run(5000)
  use tables <- with_base
  let added =
    edit(
      tables:,
      with: [
        store.put_rows(localized_text.entry(), localized_text_file([#(4, 21)])),
      ],
      derivations: [],
    )
  assert version_of(added, 4) == Ok(21) as "the added row reads back"
  assert ids_of(tables: added) == [1, 3, 4, 5]
    as "rows lists the added id in order"
  let removed =
    edit(
      tables:,
      with: [store.remove_rows(localized_text.entry(), ids: [3])],
      derivations: [],
    )
  assert version_of(removed, 3) == Error(Nil)
    as "a removed row has no record, as an id the file has no row for has none"
  assert ids_of(tables: removed) == [1, 5]
    as "rows does not list the removed id"
  assert ids_of(tables: tables) == [1, 3, 5]
    as "the base value still holds the removed row"
}

pub fn a_table_the_base_lacks_reads_only_the_rows_the_edit_puts_test() -> Nil {
  use <- owned_test.run(5000)
  use tables <- with_base
  let edited =
    edit(
      tables:,
      with: [
        store.put_rows(creature2.entry(), creature2_file([#(8, 1), #(2, 3)])),
      ],
      derivations: [],
    )
  assert list.map(creature2.all(edited), fn(row) { row.id }) == [2, 8]
    as "the new table holds exactly the rows put, in id order"
  assert version_of(edited, 5) == Ok(11)
    as "the tables the base has are read as before"
}

pub fn an_edit_without_derivations_makes_a_derived_value_crash_the_reader_test() -> Nil {
  use <- owned_test.run(5000)
  use tables <- with_base
  let edited =
    edit(
      tables:,
      with: [
        store.put_rows(localized_text.entry(), localized_text_file([#(4, 21)])),
      ],
      derivations: [],
    )
  let ended =
    ask_support.ended_running(fn() {
      let _ids: List(Int) = store.derived(tables: edited, key: ids_key)
      Nil
    })
  assert ask_support.panic_message(ask_support.raised(ended))
    == "no derived value LocalizedTextIds in the tables"
    as "a derived value the edit did not rebuild is not there: the reader panics naming it, never reads the base's stale one"
  let rebuilt =
    edit(
      tables:,
      with: [
        store.put_rows(localized_text.entry(), localized_text_file([#(4, 21)])),
      ],
      derivations: [ids_derivation()],
    )
  assert store.derived(tables: rebuilt, key: ids_key) == [1, 3, 4, 5]
    as "a derivation given to the edit is built from the edited rows"
}

pub fn a_requirement_refused_on_an_edited_value_gives_the_text_a_load_gives_test() -> Nil {
  use <- owned_test.run(60_000)
  let refused =
    store.edit(
      tables: fixture_tables.shared(),
      with: [store.remove_rows(class.entry(), ids: [2])],
      requirements: character_state.requirements(),
      derivations: [],
    )
  assert refused
    == Error(store.RowMissing(
      from_table: "the server's playable classes",
      column: "Class id",
      to_table: "Class",
      id: 2,
    ))
    as "the Engineer's Class row 2 is removed, and the playable classes' requirement names it"
  let assert Error(error) = refused
  assert store.describe(error)
    == "the table the server's playable classes column Class id names id 2, which the table Class has no row for"
    as "the sentence the server stops with"
  assert store.edit(
      tables: fixture_tables.shared(),
      with: [],
      requirements: character_state.requirements(),
      derivations: [],
    )
    |> result.is_ok
    as "the same requirement holds of the fixture's rows themselves"
}

pub fn a_derivation_refused_on_an_edited_value_gives_the_text_a_load_gives_test() -> Nil {
  use <- owned_test.run(60_000)
  assert store.edit(
      tables: fixture_tables.shared(),
      with: [],
      requirements: [],
      derivations: [spell_plan.derivation()],
    )
    |> result.is_ok
    as "the plans build from the fixture's own rows"
  let refused =
    store.edit(
      tables: fixture_tables.shared(),
      with: [store.remove_rows(spell4.entry(), ids: [30_900])],
      requirements: [],
      derivations: [spell_plan.derivation()],
    )
  assert refused
    == Error(store.DerivationFailed(
      name: "SpellPlans",
      reason: "the table Spell4 has no row 30900, which an ability's tree of casts names",
    ))
    as "Telekinetic Strike's Proxy 62204 starts the Spell4 row 30900 (Spell4Effects.targetFlags 4); without the row the plan fails with the sentence spell_plan.describe gives"
}

/// Writes the planted server files and the content files into one folder, for
/// the body, and gives the folder.
fn with_server_files(body: fn(String) -> a) -> a {
  planted_table.in_folder(
    list.append(character_tables.files(), character_tables.content_files()),
    body,
  )
}

/// The persistent terms a node holds: how many and how many bytes they take.
fn terms_held() -> #(Int, Int) {
  #(literal_area.persistent_term_count(), literal_area.persistent_term_memory())
}

fn class_row(tables: store.Tables, row_id: Int) -> Result(Nil, Nil) {
  class.get(tables, id.ClassId(row_id)) |> result.replace(Nil)
}

/// The server's start in a node of its own: the tables load once under the
/// server's key, then the content tables are read beside them. It is no test
/// itself, as a stored value is held for the life of the VM.
pub fn the_content_tables_are_read_beside_the_stored_tables() -> Nil {
  use folder <- with_server_files
  let assert Ok(stored) = server_table.load(folder)
    as "the planted files load as the server's tables"
  let before = terms_held()
  let assert Ok(with_content) =
    server_table.load_content_tables(over: stored, from: folder)
    as "the planted content files load beside the server's tables"
  assert world.all(with_content) != []
    as "the content tables are read: the planted Worlds are there"
  assert terms_held() == before
    as "reading the content tables puts no persistent term and erases none"
  Nil
}

pub fn the_servers_start_reads_the_content_tables_without_a_put_or_an_erase_test() -> Nil {
  use <- owned_test.run(60_000)
  fresh_node.must_return_function(
    the_content_tables_are_read_beside_the_stored_tables,
  )
}

/// A test edit of the stored tables in a node of its own.
pub fn an_edit_is_built_beside_the_stored_tables() -> Nil {
  use folder <- with_server_files
  let assert Ok(stored) = server_table.load(folder)
    as "the planted files load as the server's tables"
  let before = terms_held()
  let planted_class =
    planted_table.file(schema: class.schema, rows: [
      planted_table.row(class.schema, [#("ID", Integer(9))]),
    ])
  let assert Ok(edited) =
    store.edit(
      tables: stored,
      with: [
        store.remove_rows(class.entry(), ids: [2]),
        store.put_rows(class.entry(), planted_class.1),
      ],
      requirements: [],
      derivations: [],
    )
    as "the edit gives a value"
  assert terms_held() == before
    as "an edit puts no persistent term and erases none: it is built on the heap"
  assert result.is_ok(class_row(edited, 9))
    && class_row(edited, 2) == Error(Nil)
    as "the edit holds its change"
  assert class_row(stored, 2) |> result.is_ok
    as "the stored value holds the row the edit removed"
  assert terms_held() == before
    as "reading the stored value after the edit puts and erases nothing either"
  Nil
}

pub fn a_test_edit_leaves_the_literal_area_unchanged_test() -> Nil {
  use <- owned_test.run(60_000)
  fresh_node.must_return_function(an_edit_is_built_beside_the_stored_tables)
}

/// A test edit of the stored tables, copied into ETS and read back, in a node of
/// its own.
pub fn an_edit_read_back_from_ets_keeps_its_edit_and_the_stored_rows() -> Nil {
  use folder <- with_server_files
  let assert Ok(stored) = server_table.load(folder)
    as "the planted files load as the server's tables"
  let planted_class =
    planted_table.file(schema: class.schema, rows: [
      planted_table.row(class.schema, [#("ID", Integer(9))]),
    ])
  let assert Ok(edited) =
    store.edit(
      tables: stored,
      with: [
        store.remove_rows(class.entry(), ids: [2]),
        store.put_rows(class.entry(), planted_class.1),
      ],
      requirements: [],
      derivations: [],
    )
    as "the edit gives a value"
  let back = literal_area.through_ets(edited)
  assert result.is_ok(class_row(back, 9)) && class_row(back, 2) == Error(Nil)
    as "the copy from ETS reads the edit: the added row is there and the removed row is not"
  assert result.is_ok(class_row(back, 1))
    as "the copy reads a row of the edited table that the edit left"
  assert creature2.all(back) == creature2.all(stored)
    as "the copy reads the rows of a table the edit left from the stored value"
  assert store.digest(back) == store.digest(stored)
    as "the copy holds the digest of the files the tables were read from"
  Nil
}

pub fn an_edit_copied_into_ets_still_reads_its_edit_and_the_stored_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  fresh_node.must_return_function(
    an_edit_read_back_from_ets_keeps_its_edit_and_the_stored_rows,
  )
}

/// The unload of a stored value and of one on a heap, in a node of its own.
pub fn a_stored_value_is_refused_its_unload() -> Nil {
  use folder <- with_server_files
  let assert Ok(stored) = server_table.load(folder)
    as "the planted files load as the server's tables"
  let assert Ok(read) = server_table.read(folder) as "a read of the same files"
  let before = terms_held()
  assert store.unload(stored) == Error(store.ValueIsHeld)
    as "a stored value is refused its unload: erasing it copies the whole of it into each holder"
  assert store.unload(read) == Ok(Nil)
    as "a value on a heap holds no term, so it has nothing to unload"
  assert terms_held() == before as "the refused unload erased nothing"
  Nil
}

pub fn the_unload_of_a_stored_value_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  fresh_node.must_return_function(a_stored_value_is_refused_its_unload)
}

/// The server's load of the planted files, and a read of the same files.
pub fn the_stored_value_equals_a_read_of_the_same_files() -> Nil {
  use folder <- with_server_files
  let assert Ok(stored) = server_table.load(folder) as "the server's load"
  let assert Ok(read) = server_table.read(folder) as "a read of the same folder"
  assert same_tables(stored, read)
    as "the stored value is the value a read of the same files makes, row for row and derived value for derived value"
  Nil
}

/// Whether two values hold the same digest, the same ids in each table of the
/// server and the same derived values, whatever heap or term each is on.
fn same_tables(first: store.Tables, second: store.Tables) -> Bool {
  store.digest(first) == store.digest(second)
  && list.all(server_table.entries(), fn(entry) {
    store.ids(entry, first) == store.ids(entry, second)
  })
  && class.all(first) == class.all(second)
  && creature2.all(first) == creature2.all(second)
  && spell4.all(first) == spell4.all(second)
  && spell_plan.plans(first) == spell_plan.plans(second)
  && spell_area.areas(first) == spell_area.areas(second)
  && top_zone.top_zones(first) == top_zone.top_zones(second)
  && appearance.index(first) == appearance.index(second)
  && rating.formulas(first) == rating.formulas(second)
}

pub fn a_stored_value_equals_a_read_of_the_same_files_test() -> Nil {
  use <- owned_test.run(60_000)
  fresh_node.must_return_function(
    the_stored_value_equals_a_read_of_the_same_files,
  )
}
