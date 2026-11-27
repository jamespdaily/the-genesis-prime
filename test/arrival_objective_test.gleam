//// The arrival_objective content table (migration 0038,
//// `genesis_prime/content/objective_set`) and the load's check of its rows
//// (`genesis_prime/game/arrival_objective`): the visible scripted objectives whose text
//// asks only to reach a place. Expected values come from these places.
//// - A row must be a place a position can complete: a visible, required type 5 objective
////   (`QuestObjective.type.5`, `QuestObjective.flags`) that no creature links
////   (`objective_link.is_linked`), with a marker whose WorldLocation2 row exists
////   (`0x140485fa0` tests a position against that row), that no spell effect or item names
////   (`Spell4Effects.effectType.42`, `0x140398cc0`).
//// - The fixture's rows: objective 4770 (quest 3667, type 5, flags 0x10, marker
////   WorldLocation2 7778) is a place; 4849 (quest 3769) is named by Spell4Effects 89873;
////   6589 (quest 4748) by Item2 12448; 9659 (quest 6296, type 12) is linked by Creature2
////   27768; 16132 (quest 6296, flags 8) is hidden; 1962 (quest 1859, no marker) is a script
////   with no marker.
//// - Migration 0038: 42 rows, each a `server_choice`.

import character_tables
import content_support
import database_support
import fixture_tables
import genesis_prime/content/objective_set
import genesis_prime/content/refusal.{type Refusal, RowId}
import genesis_prime/game/arrival_objective
import gleam/list
import gleam/set
import gleam/string
import owned_test
import quest_support

/// The objective of quest 3667 the fixture holds as a place.
const tower = 4770

pub fn a_row_naming_a_visible_marked_unlinked_script_is_a_place_test() -> Nil {
  use <- owned_test.run(60_000)
  assert arrival_objective.select(
      ids: [tower],
      tables: character_tables.shared(),
    )
    == Ok(set.from_list([tower]))
    as "QuestObjective 4770 is type 5, visible, required, marked at an existing row, linked by no creature and named by no cast"
}

pub fn the_load_refuses_a_row_that_is_not_a_visible_marked_unlinked_script_test() -> Nil {
  use <- owned_test.run(60_000)
  // 4849 is marked and visible, and Spell4Effects 89873 advances it by a cast.
  assert_refused(
    edits: [],
    objective: 4849,
    saying: "a spell effect or an item names it",
  )
  // 6589 is named by an item only.
  assert_refused(
    edits: [],
    objective: 6589,
    saying: "a spell effect or an item names it",
  )
  // 1962 has no marker.
  assert_refused(
    edits: [],
    objective: 1962,
    saying: "none of its worldLocationsIdIndicator markers names a WorldLocation2 row",
  )
  // The Tower's objective with a marker naming no row.
  assert_refused(
    edits: [
      #(tower, "worldLocationsIdIndicator00", 4_000_000),
    ],
    objective: tower,
    saying: "none of its worldLocationsIdIndicator markers names a WorldLocation2 row",
  )
  // 9659 is type 12 and linked.
  assert_refused(
    edits: [],
    objective: 9659,
    saying: "not 5 (a scripted objective)",
  )
  // 16132 has flag 8.
  assert_refused(edits: [], objective: 16_132, saying: "flag 0x8 hides it")
  // The Tower's objective made optional with flag 0x20.
  assert_refused(
    edits: [#(tower, "flags", 0x20)],
    objective: tower,
    saying: "flag 0x20 makes it optional",
  )
  // 9659 made a marked visible script keeps the creature that links it.
  assert_refused(
    edits: [
      #(9659, "type", 5),
      #(9659, "flags", 0),
      #(9659, "worldLocationsIdIndicator00", 21_383),
    ],
    objective: 9659,
    saying: "a creature links it",
  )
  // A copy of the Tower's objective that no quest lists, and one the table lacks.
  use tables <- fixture_tables.added(
    table: "QuestObjective",
    copy_of: tower,
    id: 99_001,
    with: [],
  )
  let assert Error([refusal]) = arrival_objective.select(ids: [99_001], tables:)
    as "one refusal: the copy lists in no quest"
  assert refusal.row == RowId(99_001)
  assert string.contains(refusal.rule, "no Quest2 row lists the objective")
  let assert Error([missing]) =
    arrival_objective.select(
      ids: [4_000_000],
      tables: character_tables.shared(),
    )
    as "one refusal: the table lacks the row"
  assert string.contains(missing.rule, "QuestObjective table has no row")
}

pub fn the_load_names_every_refused_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error(refusals) =
    arrival_objective.select(
      ids: [4_000_000, tower, 4849],
      tables: character_tables.shared(),
    )
    as "two rows are refused"
  assert list.map(refusals, fn(refusal: Refusal) { refusal.row })
    == [RowId(4_000_000), RowId(4849)]
    as "the sound row passes and each other row is named"
}

/// The one refusal the objective gets over the tables with these QuestObjective cells
/// edited, and that its rule says this.
fn assert_refused(
  edits edits: List(#(Int, String, Int)),
  objective objective_id: Int,
  saying saying: String,
) -> Nil {
  use tables <- quest_support.with_objectives(edits:)
  let assert Error([refusal]) =
    arrival_objective.select(ids: [objective_id], tables:)
    as "one refusal for the objective"
  assert refusal.row == RowId(objective_id)
  assert string.contains(refusal.rule, saying)
    as { "the rule says: " <> saying <> "; it said: " <> refusal.rule }
}

pub fn the_arrival_table_refuses_bad_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  list.each(
    [
      #(
        "insert into arrival_objective (objective_id, source) values (1, 'nobody')",
        "arrival_objective_source_is_a_content_source",
      ),
      #(
        "insert into arrival_objective (objective_id, source) values (4770, 'server_choice')",
        "arrival_objective_pkey",
      ),
      #(
        "insert into arrival_objective (objective_id, source) values (0, 'server_choice')",
        "arrival_objective_id_is_positive",
      ),
      #(
        "insert into arrival_objective (objective_id, source, source_row) values (1, 'server_choice', 5)",
        "arrival_objective_world_database_row_has_a_source_row",
      ),
    ],
    fn(bad) {
      let assert Error(failed) =
        database_support.psql(
          with: database_support.settings(),
          database:,
          arguments: ["-c", bad.0],
        )
        as "the database refuses the row"
      assert string.contains(failed.output, bad.1)
        as "the refusal names its constraint"
    },
  )
}

pub fn the_arrival_migrations_seed_50_server_choice_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    objective_set.rows(db: content_support.connect(database:))
    as "the query ran"
  assert list.length(objective_set.ids(rows:, table: arrival_objective.table))
    == 50
    as "migration 0038 seeds 42 rows and migration 0043 adds 8"
  assert content_support.count(
      database:,
      sql: "select count(*) from arrival_objective where source = 'server_choice' and source_row is null",
    )
    == 50
    as "each row is the server's choice"
}
