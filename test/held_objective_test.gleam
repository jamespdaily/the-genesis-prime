//// The held_objective content table (migration 0034, `genesis_prime/content/held_objective`)
//// and the load's check of its rows (`genesis_prime/game/held_objective`): the visible
//// scripted objectives the server leaves open because only an instance run or a PvP match
//// completes them. Expected values come from these places.
//// - A held row must be an objective the server would otherwise complete, so the load
////   refuses one that is not a visible stand-in (`objective.visible_script_broken`): type 5
////   (`QuestObjective.type.5`), flags 0x8 and 0x20 clear (`QuestObjective.flags`), no
////   `worldLocationsIdIndicator` marker, and no creature linking it
////   (`objective_link.is_linked`).
//// - The fixture's rows: objective 1962 (quest 1859, type 5, flags 0, data 0, unmarked,
////   unlinked) is a stand-in; 16132 (quest 6296, flags 8) is hidden; 9659 (type 12) is
////   linked by Creature2 27768; 9658 (type 8, markers 21383 and 21384) is marked.
//// - Migration 0034: 130 rows from the design's measured table, 88 of kind `instance_run`
////   and 42 of kind `pvp_match`, each a `server_choice` with its reason; the other
////   constraints follow migration 0031's pattern.

import character_tables
import content_support
import database_support
import fixture_tables
import genesis_prime/content/held_objective as content_held_objective
import genesis_prime/content/refusal.{type Refusal, RowId}
import genesis_prime/game/held_objective.{Row}
import gleam/list
import gleam/set
import gleam/string
import owned_test
import quest_support

/// The objective of quest 1859 the fixture holds as a visible script.
const stand_in = 1962

pub fn a_row_naming_a_visible_script_is_held_test() -> Nil {
  use <- owned_test.run(60_000)
  assert held_objective.select(
      rows: [Row(objective_id: stand_in)],
      tables: character_tables.shared(),
    )
    == Ok(set.from_list([stand_in]))
    as "QuestObjective 1962 is type 5 with flags 0, data 0, no marker and no link"
}

pub fn the_held_load_refuses_a_missing_objective_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [refusal] = refused(rows: [4_000_000])
    as "one refusal: the row of QuestObjective 4000000, which the client's table lacks"
  assert refusal.table == "held_objective"
  assert refusal.row == RowId(4_000_000)
  assert string.contains(refusal.rule, "QuestObjective table has no row")
}

pub fn the_held_load_refuses_an_objective_that_cannot_be_a_stand_in_test() -> Nil {
  use <- owned_test.run(60_000)
  // 9659 is type 12 and linked by Creature2 27768, which completes it.
  assert_refused(
    edits: [],
    objective: 9659,
    saying: "not 5 (a scripted objective)",
  )
  // 16132 has flag 8.
  assert_refused(edits: [], objective: 16_132, saying: "flag 0x8 hides it")
  // 1962 made optional with flag 0x20.
  assert_refused(
    edits: [#(stand_in, "flags", 32)],
    objective: stand_in,
    saying: "flag 0x20 makes it optional",
  )
  // 9658 made a visible script keeps its two markers.
  assert_refused(
    edits: [#(9658, "type", 5), #(9658, "flags", 0)],
    objective: 9658,
    saying: "worldLocationsIdIndicator marker",
  )
  // 9659 made a visible script keeps the creature that links it.
  assert_refused(
    edits: [#(9659, "type", 5), #(9659, "flags", 0)],
    objective: 9659,
    saying: "a creature links it",
  )
  // A copy of 1962 that no quest lists.
  use tables <- fixture_tables.added(
    table: "QuestObjective",
    copy_of: stand_in,
    id: 99_001,
    with: [],
  )
  let assert Error([refusal]) =
    held_objective.select(rows: [Row(objective_id: 99_001)], tables:)
    as "one refusal: the copy lists in no quest"
  assert refusal.row == RowId(99_001)
  assert string.contains(refusal.rule, "no Quest2 row lists the objective")
}

pub fn the_held_load_names_every_refused_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let refusals = refused(rows: [4_000_000, stand_in, 16_132])
  assert list.map(refusals, fn(refusal) { refusal.row })
    == [RowId(4_000_000), RowId(16_132)]
    as "the sound row passes and each other row is named"
}

/// The refusals of the rows over the fixture's tables.
fn refused(rows rows: List(Int)) -> List(Refusal) {
  let assert Error(refusals) =
    held_objective.select(
      rows: list.map(rows, fn(id) { Row(objective_id: id) }),
      tables: character_tables.shared(),
    )
    as "the rows are refused"
  refusals
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
    held_objective.select(rows: [Row(objective_id:)], tables:)
    as "one refusal for the objective"
  assert refusal.row == RowId(objective_id)
  assert string.contains(refusal.rule, saying)
    as { "the rule says: " <> saying <> "; it said: " <> refusal.rule }
}

pub fn the_held_table_refuses_bad_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  list.each(
    [
      #(
        "insert into held_objective (objective_id, kind, source, reason) values (1, 'instance_run', 'nobody', 'x')",
        "held_objective_source_is_a_content_source",
      ),
      #(
        "insert into held_objective (objective_id, kind, source, reason) values (1, 'instance_run', 'server_choice', '   ')",
        "held_objective_reason_says_something",
      ),
      #(
        "insert into held_objective (objective_id, kind, source) values (1, 'instance_run', 'server_choice')",
        "held_objective_other_source_states_its_reason",
      ),
      #(
        "insert into held_objective (objective_id, kind, source, reason) values (12547, 'instance_run', 'server_choice', 'x')",
        "held_objective_pkey",
      ),
      #(
        "insert into held_objective (objective_id, kind, source, reason) values (0, 'instance_run', 'server_choice', 'x')",
        "held_objective_id_is_positive",
      ),
      #(
        "insert into held_objective (objective_id, kind, source, reason) values (1, 'duel', 'server_choice', 'x')",
        "held_objective_kind_is_known",
      ),
      #(
        "insert into held_objective (objective_id, kind, source, source_row, reason) values (1, 'instance_run', 'server_choice', 5, 'x')",
        "held_objective_world_database_row_has_a_source_row",
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

pub fn the_held_migration_seeds_130_server_choice_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let database = database_support.new_database(on: database_support.shared())
  let assert Ok(rows) =
    content_held_objective.rows(db: content_support.connect(database:))
    as "the query ran"
  assert list.length(rows) == 130
    as "the design's measured table holds 130 rows"
  assert content_support.count(
      database:,
      sql: "select count(*) from held_objective where kind = 'instance_run'",
    )
    == 88
    as "88 instance runs"
  assert content_support.count(
      database:,
      sql: "select count(*) from held_objective where kind = 'pvp_match'",
    )
    == 42
    as "42 PvP matches"
  assert content_support.count(
      database:,
      sql: "select count(*) from held_objective where source = 'server_choice' and reason is not null and source_row is null",
    )
    == 130
    as "each row is the server's choice and states its reason"
}
