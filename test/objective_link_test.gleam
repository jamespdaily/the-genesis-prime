//// The creatures whose rows link a quest objective (`genesis_prime/game/objective_link`),
//// as the tables' load derives them. Expected values come from these places.
//// - `Creature2.objective_link`: `questAnimStateId` and `questAnimObjectiveIndex` name a
////   quest and the objective's index in it, and `prerequisiteIdAnimState` names a
////   Prerequisite whose type 43 conditions name more (`Prerequisite.prerequisiteTypeId.43`,
////   `.11` for the nested rows); the client reads both columns the same way.
//// - The client's rows in the fixture (`table_rows -- Creature2 12919 12321 19277`):
////   Creature2 12919 names quest 3741, objective index 0 by its questAnim columns;
////   Creature2 12321 has prerequisiteIdAnimState 12379 (type 43 on quest 3655 index 0);
////   Creature2 19277 has prerequisiteIdAnimState 7341, whose type 11 condition names
////   Prerequisite 7340 (type 43 on quest 4975 index 0).
//// - A row that names the same objective by both columns, or two rows that name one
////   objective, are the cases the table has no row for, so the test changes rows
////   (`fixture_tables.change`), each change named where it is made.

import fixture_tables
import genesis_prime/game/objective_link
import genesis_prime/table/loader/store as table_store
import gleam/list
import owned_test
import planted_table.{Integer}
import quest_support

/// The Creature2 ids that link the objective.
fn linked(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
) -> List(Int) {
  list.map(
    objective_link.creatures_linked(tables:, quest_id:, index:),
    fn(creature) { creature.value },
  )
}

pub fn creatures_linked_names_the_creatures_of_each_link_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_objectives(edits: [])
  assert linked(tables:, quest_id: 3741, index: 0) == [12_919]
    as "a questAnim column names its objective"
  assert linked(tables:, quest_id: 3655, index: 0) == [12_321]
    as "a prerequisite column's type 43 condition names its objective"
  assert linked(tables:, quest_id: 4975, index: 0) == [19_277]
    as "a nested prerequisite row's type 43 condition names its objective too"
  assert linked(tables:, quest_id: 1854, index: 0) == []
    as "an objective no creature's row names has no creature"
  assert objective_link.is_linked(tables:, quest_id: 3741, index: 0)
    as "and a linked objective is linked"
  assert !objective_link.is_linked(tables:, quest_id: 1854, index: 0)
    as "an unlinked one is not"
}

pub fn a_creature_naming_an_objective_twice_and_two_creatures_naming_it_are_listed_once_each_test() -> Nil {
  use <- owned_test.run(60_000)
  // Creature2 12321 also names quest 3655 index 0 by its questAnim columns, beside its
  // prerequisite column (so `links` holds the pair twice), and Creature2 12919 is changed
  // from quest 3741 to name quest 3655 index 0 as well.
  let rows = {
    let changed =
      fixture_tables.change(
        rows: fixture_tables.rows(),
        table: "Creature2",
        id: 12_321,
        with: [
          #("questAnimStateId", Integer(3655)),
          #("questAnimObjectiveIndex", Integer(0)),
        ],
      )
    let assert Ok(changed) = changed as "the fixture holds Creature2 12321"
    let again =
      fixture_tables.change(
        rows: changed,
        table: "Creature2",
        id: 12_919,
        with: [
          #("questAnimStateId", Integer(3655)),
          #("questAnimObjectiveIndex", Integer(0)),
        ],
      )
    let assert Ok(again) = again as "the fixture holds Creature2 12919"
    again
  }
  use tables <- fixture_tables.on_rows(rows:, reaching: [])
  assert linked(tables:, quest_id: 3655, index: 0) == [12_321, 12_919]
    as "each creature is listed once, in Creature2 id order"
  assert linked(tables:, quest_id: 3741, index: 0) == []
    as "and the objective Creature2 12919 no longer names has none"
}
