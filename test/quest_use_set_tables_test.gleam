//// What a use-a-creature objective (QuestObjective type 23) counts, over the client's
//// whole tables. Expected values come from these places.
//// - `QuestObjective.type.23`: `data` names a TargetGroup in 94 of the 96 type 23 rows
////   (`table_rows -- QuestObjective type=23`); rows 8323 and 9393 have data 0 and
////   TargetGroup has no row 0. A use of a unit in that group counts toward the objective
////   (`0x140550c50`, line 142), and the client holds no per-unit record of a type 23
////   objective (`0x1405517a0` makes no type 23 a checklist), so one count
////   for each unit of the group is the server's choice (Jim, 2026-11-11).
//// - Rows 6653, 6657 and 9819 are in no quest: no Quest2 row names them as an objective
////   (`table_rows -- Quest2`), so no log holds them. Rows 6653 and 6657 name Creature2 ids
////   8334, 8335 and 15830, which have no Creature2 row.
//// - Rows 21328, 21329, 21349 and 21350 are the Bon Voyage terminals' choices: their group
////   holds both terminals of the quest and only the terminal the objective is placed at
////   counts (`departures`, tested in `objective_test`).

import client_tables
import genesis_prime/game/objective.{SendProgress, SendState, Used}
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Faction2Id, TargetGroupId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/table/quest_objective
import genesis_prime/table/target_group as target_group_table
import gleam/bool
import gleam/dict
import gleam/int
import gleam/list
import owned_test
import quest_support
import unitest

const use_a_group_type = 23

/// The type 23 rows of the client's QuestObjective table.
fn use_objectives(
  tables tables: table_store.Tables,
) -> List(quest_objective.QuestObjective) {
  list.filter(quest_objective.all(tables), fn(row) {
    row.type_ == use_a_group_type
  })
}

pub fn every_type_23_objective_has_a_group_or_data_0_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let rows = use_objectives(tables:)
  assert list.length(rows) == 96 as "QuestObjective has 96 rows of type 23"
  let without_group =
    list.filter(rows, fn(row) {
      target_group_table.get(tables:, id: TargetGroupId(row.data)) == Error(Nil)
    })
    |> list.map(fn(row) { row.id })
    |> list.sort(by: int.compare)
  assert without_group == [8323, 9393]
    as "only rows 8323 and 9393 have data 0, a TargetGroup the table has no row for; the other 94 name a TargetGroup row"
}

const skipped_for_no_quest = [6653, 6657, 9819]

const skipped_for_a_terminal_choice = [21_328, 21_329, 21_349, 21_350]

pub fn every_creature_a_type_23_group_reaches_counts_once_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let quest_of_objective =
    list.fold(quest2.all(tables), dict.new(), fn(held, quest) {
      list.fold(
        [
          quest.objective0,
          quest.objective01,
          quest.objective02,
          quest.objective03,
          quest.objective04,
          quest.objective05,
        ],
        held,
        fn(held, objective_id) { dict.insert(held, objective_id, quest.id) },
      )
    })
  let rows = use_objectives(tables:)
  let in_a_quest =
    list.filter(rows, fn(row) { dict.has_key(quest_of_objective, row.id) })
  assert list.map(
      list.filter(rows, fn(row) { !dict.has_key(quest_of_objective, row.id) }),
      fn(row) { row.id },
    )
    |> list.sort(by: int.compare)
    == skipped_for_no_quest
    as "the rows no quest holds are exactly the ones this test skips"
  let wanted =
    list.filter(in_a_quest, fn(row) {
      row.data != 0 && !list.contains(skipped_for_a_terminal_choice, row.id)
    })
  assert list.length(wanted) == 87
    as "96 rows, less 2 with data 0, 3 in no quest and 4 terminal choices"
  let second_use_checked =
    list.flat_map(wanted, fn(row) {
      let assert Ok(quest_id) = dict.get(quest_of_objective, row.id)
        as "the objective is in a quest"
      list.filter_map(
        target_group.listed_creatures(tables:, group: row.data),
        fn(creature_id) {
          case creature2.get(tables, Creature2Id(creature_id)) {
            Ok(creature) -> Ok(counts_once(tables:, quest_id:, row:, creature:))
            Error(Nil) -> Error(Nil)
          }
        },
      )
    })
  assert list.length(second_use_checked) == 236
    as "the 87 objectives' groups reach 236 creatures with a Creature2 row"
  assert list.length(list.filter(second_use_checked, fn(checked) { checked }))
    == 170
    as "56 of the 87 objectives count 2 or more, and their groups reach 170 of those creatures"
}

/// Uses the creature as unit 1 on a fresh log of the quest whose earlier objectives are
/// done and whose objective is open, and checks that it counts one. Where the objective
/// counts 2 or more it is still open, and the same unit again must count nothing for it
/// (a count of 1 closes the objective, which refuses a second use for that reason, tested
/// in `objective_test`). Returns whether the second use was checked.
fn counts_once(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  row row: quest_objective.QuestObjective,
  creature creature: creature2.Creature2,
) -> Bool {
  let assert Ok(quest) = quest_log.quest_of(tables:, id: quest_id)
    as "the quest's rows are in the tables"
  let assert Ok(#(index, _)) =
    list.index_map(quest.objectives, fn(objective, index) {
      #(index, objective)
    })
    |> list.find(fn(pair) { { pair.1 }.objective_id == row.id })
    as "the quest holds the objective"
  let slots = list.length(quest.objectives)
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [
        quest_support.active(
          quest_id:,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: earlier_than(index:),
          progress: list.repeat(0, slots),
        ),
      ],
      tables:,
    )
    as "a log of the quest with its earlier objectives done"
  let event =
    Used(
      target: target_group.Unit(
        creature_id: Creature2Id(creature.id),
        faction_id: Faction2Id(0),
        unit_race_id: creature2.unit_race_id(creature),
      ),
      checklist_index: 0,
      unit: quest_support.unit_ref(unit_id: 1),
      by_item: False,
    )
  let first = objective.advance(log:, tables:, event:, now_ms: 0)
  let where = "objective " <> label(row.id) <> " of quest " <> label(quest_id)
  assert list.contains(
    first.effects,
    SendProgress(quest_id:, objective_index: index, progress: 1),
  )
    as {
      "a first use of creature "
      <> label(creature.id)
      <> " counts one for "
      <> where
    }
  use <- bool.guard(when: row.count < 2, return: False)
  let second = objective.advance(log: first.log, tables:, event:, now_ms: 0)
  // A later objective the first use opened may count the unit itself: quest 6251's
  // objective 9944 follows 9943 with a group (3260) that lists the same creature, so the
  // second use is that objective's first.
  assert list.filter(second.effects, fn(effect) {
      case effect {
        SendProgress(objective_index:, ..) -> objective_index == index
        SendState(..) -> False
      }
    })
    == []
    as { "the same unit again counts nothing for " <> where }
  True
}

/// The bits of the objective indexes below `index`.
fn earlier_than(index index: Int) -> Int {
  int.bitwise_shift_left(1, index) - 1
}

fn label(id: Int) -> String {
  int.to_string(id)
}
