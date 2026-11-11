//// The collect and visit objectives of every quest of the client's tables
//// (`genesis_prime/game/objective`). Expected values come from these places.
//// - `QuestObjective.type.4`, `.type.33`, `.type.17` and `.type.32`: the data of an
////   objective of type 4 is an Item2 id, of type 33 a TradeskillSchematic2 id whose
////   `item2IdOutput` is the item the objective counts, of type 17 a WorldZone id and
////   of type 32 a VirtualItem id. The server counts a collect objective from the
////   Item2 the data names and matches a visit against the zone chain, so a quest's
////   objective whose data names no row would never be counted.
//// - The rows that name none, from `table_rows QuestObjective type=17` and
////   `QuestObjective.id=6375`, `6389`: objective 6375 is type 17 with data 0 and is
////   in quest 4647 (the server refuses data 0 for a visit, because the chain of zone
////   0 is [0]); objective 6389 is type 17 with data 967, a zone the table lacks, and
////   is in no quest.

import client_tables
import genesis_prime/game/target_group as target_group_rule
import genesis_prime/table/creature2
import genesis_prime/table/id.{
  Item2Id, Quest2Id, QuestObjectiveId, TargetGroupId, TradeskillSchematic2Id,
  VirtualItemId, WorldZoneId,
}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/table/quest_objective
import genesis_prime/table/target_group
import genesis_prime/table/tradeskill_schematic2
import genesis_prime/table/virtual_item
import genesis_prime/table/world_zone
import gleam/int
import gleam/list
import gleam/result
import owned_test
import unitest

/// The objective rows of a quest's six slots, empty slots left out.
fn objectives_of(
  tables tables: table_store.Tables,
  quest quest: Quest2,
) -> List(quest_objective.QuestObjective) {
  [
    quest.objective0,
    quest.objective01,
    quest.objective02,
    quest.objective03,
    quest.objective04,
    quest.objective05,
  ]
  |> list.filter(fn(objective_id) { objective_id != 0 })
  |> list.map(fn(objective_id) {
    let assert Ok(row) =
      quest_objective.get(tables:, id: QuestObjectiveId(objective_id))
      as {
        "quest "
        <> int.to_string(quest2.id(quest).value)
        <> " names QuestObjective "
        <> int.to_string(objective_id)
        <> ", a row of the table"
      }
    row
  })
}

/// The in-quest type 4 objectives whose data is no Item2 row, from
/// `table_rows QuestObjective type=4` joined to `table_rows Quest2` and
/// `table_rows Item2`: ten of them name item 0, the rest name an item the Item2 table
/// lacks (quests 1854 to 1856, 2138 to 2141, 2347, 2914, 3730 and 6629 among them). The
/// server counts such an objective from the held items as any other, and no item can
/// be held for it. No client table gives these items to a player either, so the client
/// itself cannot finish those quests by collecting: the coordinator's review looked in
/// Quest2's pushed items and preq_item, Quest2Reward, TradeskillSchematic2's outputs
/// and materials, and Spell4Effects' data, and found none of them.
const type_4_without_an_item = [
  1957, 1959, 1960, 2337, 2345, 2350, 2351, 2352, 2356, 2357, 2358, 2364, 2709,
  2710, 2711, 3680, 4066, 4569, 4694, 4795, 5874, 6062, 6079, 6210, 6226, 6248,
  6267, 6629,
]

pub fn every_quest_collect_and_visit_objective_names_a_row_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let in_quests =
    quest2.all(tables)
    |> list.flat_map(fn(quest) {
      list.map(objectives_of(tables:, quest:), fn(row) { #(quest, row) })
    })
  let of_type = fn(type_) {
    list.filter(in_quests, fn(pair) { { pair.1 }.type_ == type_ })
  }
  let ids = fn(pairs: List(#(Quest2, quest_objective.QuestObjective))) {
    list.map(pairs, fn(pair) { { pair.1 }.id })
    |> list.unique
    |> list.sort(int.compare)
  }

  assert of_type(4) != [] as "the client's quests hold collect objectives"
  assert ids(
      list.filter(of_type(4), fn(pair) {
        item2.get(tables:, id: Item2Id({ pair.1 }.data)) |> result.is_error
      }),
    )
    == type_4_without_an_item
    as {
      "every type 4 objective of a quest names an Item2, but the listed ones, "
      <> "whose items no client table holds or gives (Quest2 pushed items and "
      <> "preq_item, Quest2Reward, TradeskillSchematic2 outputs and materials, "
      <> "Spell4Effects data), so the client cannot finish those quests by collecting"
    }

  // A count that falls takes an Achieved quest back to Accepted, and a timed counted
  // objective then runs against the deadline it started with
  // (`quest_log.store_progress`); the client's tables hold two such objectives, from
  // `table_rows QuestObjective type=4` and `type=17` with maxTimeAllowedMS above 0.
  assert ids(
      list.filter(in_quests, fn(pair) {
        { pair.1 }.max_time_allowed_ms > 0
        && list.contains([4, 17, 32, 33], { pair.1 }.type_)
      }),
    )
    == [5219, 10_030]
    as "the only timed objectives of type 4, 17, 32 or 33 are the collect objective 5219 and the visit objective 10030"

  assert of_type(33) != [] as "the client's quests hold type 33 objectives"
  assert ids(
      list.filter(of_type(33), fn(pair) {
        case
          tradeskill_schematic2.get(
            tables:,
            id: TradeskillSchematic2Id({ pair.1 }.data),
          )
        {
          Ok(schematic) ->
            item2.get(
              tables:,
              id: tradeskill_schematic2.item2_id_output(schematic),
            )
            |> result.is_error
          Error(Nil) -> True
        }
      }),
    )
    == []
    as "every type 33 objective of a quest names a schematic whose output is an Item2"

  // Objective 6375 (quest 4647) names zone 0, which is no zone.
  assert of_type(17) != [] as "the client's quests hold visit objectives"
  assert ids(
      list.filter(of_type(17), fn(pair) {
        world_zone.get(tables:, id: WorldZoneId({ pair.1 }.data))
        |> result.is_error
      }),
    )
    == [6375]
    as "every type 17 objective of a quest names a WorldZone, but 6375"
  assert list.any(of_type(17), fn(pair) {
    { pair.1 }.id == 6375
    && { pair.1 }.data == 0
    && quest2.id(pair.0).value == 4647
  })
    as "objective 6375 is in quest 4647 and names zone 0"
  assert !list.any(in_quests, fn(pair) { { pair.1 }.id == 6389 })
    as "objective 6389 (type 17, data 967, a zone the table lacks) is in no quest"

  assert of_type(32) != [] as "the client's quests hold type 32 objectives"
  assert ids(
      list.filter(of_type(32), fn(pair) {
        virtual_item.get(tables:, id: VirtualItemId({ pair.1 }.data))
        |> result.is_error
      }),
    )
    == []
    as "every type 32 objective of a quest names a VirtualItem"
}

/// The type 24 objective that no quest holds (`table_rows QuestObjective type=24`
/// joined to the Quest2 objective slots, fact `QuestObjective.type.24`).
const finish_objective_in_no_quest = 6704

pub fn every_finish_quest_objective_names_a_quest2_row_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let finishes =
    quest_objective.all(tables)
    |> list.filter(fn(row) { row.type_ == 24 })
  assert list.length(finishes) == 39
    as "the client's QuestObjective table holds 39 rows of type 24 (fact QuestObjective.type.24)"
  assert list.filter(finishes, fn(row) {
      quest2.get(tables:, id: Quest2Id(row.data)) |> result.is_error
    })
    == []
    as "the data of every type 24 objective is the id of a Quest2 row"
  assert list.filter(finishes, fn(row) { row.count != 1 }) == []
    as "every type 24 objective has count 1, so one completion finishes it"
  assert !list.any(quest2.all(tables), fn(quest) {
    list.any(objectives_of(tables:, quest:), fn(row) {
      row.id == finish_objective_in_no_quest
    })
  })
    as "objective 6704 is in no quest, so no log ever holds it"
}

pub fn every_named_group_objective_with_a_pane_has_count_1_and_a_creature_list_pane_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let with_pane =
    quest_objective.all(tables)
    |> list.filter(fn(row) {
      row.type_ == 15 && row.target_group_id_reward_pane != 0
    })
  assert list.map(with_pane, fn(row) { row.id })
    == [6182, 7396, 7750, 8354, 8908, 14_233]
    as "the type 15 objectives with a reward pane are 6182, 7396, 7750, 8354, 8908 and 14233 (table_rows QuestObjective type=15)"
  assert list.filter(with_pane, fn(row) { row.count != 1 }) == []
    as "each has count 1, so the client's progress is needed 1 and the server sends 0 or 1 (0x140551840 gives a percent only when the count is above 1), and a pane of seven fits a 7-bit mask"
  assert list.filter(with_pane, fn(row) {
      case
        target_group.get(
          tables:,
          id: TargetGroupId(row.target_group_id_reward_pane),
        )
      {
        Ok(group) -> group.type_ != 1
        Error(Nil) -> True
      }
    })
    == []
    as "each pane is a TargetGroup row of type 1, a list of Creature2 ids (fact TargetGroup.type.1)"
  assert list.filter(with_pane, fn(row) {
      let members =
        target_group_rule.creatures_of(
          tables:,
          group: row.target_group_id_reward_pane,
        )
      members == []
      || list.length(members) > 7
      || list.any(members, fn(member) {
        creature2.get(tables:, id: member) |> result.is_error
      })
    })
    == []
    as "each pane lists one to seven Creature2 ids, every one a row of the Creature2 table"
}
