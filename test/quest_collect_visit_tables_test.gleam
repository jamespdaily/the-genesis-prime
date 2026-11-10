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
import genesis_prime/table/id.{
  Item2Id, QuestObjectiveId, TradeskillSchematic2Id, VirtualItemId, WorldZoneId,
}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/table/quest_objective
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
