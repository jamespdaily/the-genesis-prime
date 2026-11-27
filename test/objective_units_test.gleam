//// The creatures an objective counts a use or a cast at, and the objectives whose unit may
//// count again (`genesis_prime/game/objective_units`). Expected values come from these
//// places.
//// - `0x140550c50`: the client counts a unit for type 12 by the Creature2 id in the data,
////   for type 23 by the TargetGroup in the data, and, for any type, by the objective's
////   reward pane; types 5 and 32 have no case there and are fed through the creature's
////   questAnim and prerequisite columns (`Creature2.objective_link`,
////   `QuestObjective.type.32.sources`).
//// - `TargetGroup.type.1`: a group of that type names Creature2 ids; the other types name
////   factions, races, classes or nest groups, so the server cannot list their units.
//// - The server's rule (`objective_units`): an objective with a count above 1 whose listed
////   creatures have fewer spawn rows than the count counts the same unit again, a supply of
////   none included, and the spawn counts are planted here as the rule's input.
//// - The client's rows in the fixture (`table_rows -- QuestObjective <id>`):
////   - 4470, quest 3480: type 12, Creature2 11070, count 3.
////   - 17932, quest 9207: type 12, Creature2 58487, count 1.
////   - 4813, quest 3741: type 32, linked by Creature2 12919, count 6.
////   - 15980, quest 4975: type 5, linked by Creature2 19277 through a nested
////     prerequisite, count 3.
////   - 10383, quest 6723: type 23, TargetGroup 3568 of Creature2 30826 and 30827, count 15.
////   - 8323, quest 5568: type 23 with data 0, which TargetGroup has no row for.
////   - 21328 and 21329, quest 10528: the Bon Voyage choices (type 23, flags 33), whose
////     group holds both terminals and of which only the terminal each is placed at counts.
////   - 4098, quest 3145: type 11, Spell4 7103, reward pane 0, count 10.
////   - 15119, quest 8539 index 1: type 11, Spell4 41218, reward pane 8784 of Creature2
////     39073, count 1.
////   - 14295, quest 7757: type 11, Spell4 69507, reward pane 8954, count 8.
////   - 1961 (kill), 12889 (talk), 21294 (type 14), 7647 (type 28) and 1959 (type 4):
////     objectives that count no use of a unit.

import character_tables
import genesis_prime/game/objective_units.{Listed, NoUnitEvent, Unlisted}
import genesis_prime/shared/quest_row
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/table/loader/store as table_store
import gleam/dict
import gleam/list
import gleam/set
import owned_test

/// The units the objective at `index` of the quest counts.
fn units(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
) -> objective_units.Units {
  let assert Ok(quest) = quest_row.quest_of(tables:, id: quest_id)
    as "the fixture holds the quest's rows"
  let assert [objective, ..] = list.drop(quest.objectives, index)
    as "the quest holds the objective's slot"
  objective_units.units_of(tables:, quest_id:, index:, objective:)
}

fn creatures(ids ids: List(Int)) -> objective_units.Units {
  Listed(list.map(ids, Creature2Id))
}

pub fn units_of_names_the_creatures_each_kind_counts_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  assert units(tables:, quest_id: 3480, index: 0) == creatures(ids: [11_070])
    as "a type 12 objective counts the creature in its data"
  assert units(tables:, quest_id: 3741, index: 0) == creatures(ids: [12_919])
    as "a type 32 objective counts the creatures whose questAnim column links it"
  assert units(tables:, quest_id: 4975, index: 0) == creatures(ids: [19_277])
    as "a type 5 objective counts the creature a nested prerequisite links to it"
  assert units(tables:, quest_id: 6723, index: 0)
    == creatures(ids: [30_826, 30_827])
    as "a type 23 objective counts the creatures of its type 1 group"
  assert units(tables:, quest_id: 10_528, index: 2) == creatures(ids: [73_606])
    as "the Northern Wilds choice counts its own terminal, not the group's other"
  assert units(tables:, quest_id: 10_528, index: 3) == creatures(ids: [73_605])
    as "the Everstar Grove choice counts its own terminal"
  assert units(tables:, quest_id: 8539, index: 1) == creatures(ids: [39_073])
    as "a type 11 objective counts the creatures of its reward pane"
  assert units(tables:, quest_id: 5568, index: 0) == Unlisted
    as "a type 23 objective with no group names no creature"
  assert units(tables:, quest_id: 3145, index: 0) == Unlisted
    as "a cast with no reward pane counts any unit"
  assert units(tables:, quest_id: 1857, index: 0) == NoUnitEvent
    as "a kill counts no use"
  assert units(tables:, quest_id: 6961, index: 0) == NoUnitEvent
    as "a talk counts no use"
  assert units(tables:, quest_id: 10_520, index: 0) == NoUnitEvent
    as "a type 14 checklist counts by bit"
  assert units(tables:, quest_id: 5261, index: 0) == NoUnitEvent
    as "a type 28 checklist counts by bit"
  assert units(tables:, quest_id: 1854, index: 0) == NoUnitEvent
    as "a collect objective counts no use"
  assert units(tables:, quest_id: 7757, index: 0) == Unlisted
    as "a pane that is a group of groups (TargetGroup 8954) names no creature itself, so it counts any unit"
}

/// The supply the tests plant: each creature's spawn rows.
fn spawns(counts counts: List(#(Int, Int))) -> dict.Dict(Int, Int) {
  dict.from_list(counts)
}

pub fn reused_holds_an_objective_with_fewer_units_than_its_count_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let reused =
    objective_units.reused(
      tables:,
      spawn_counts: spawns(counts: [
        #(11_070, 2),
        #(12_919, 5),
        #(19_277, 2),
        #(30_826, 7),
        #(30_827, 7),
        #(39_073, 0),
      ]),
    )
  assert set.contains(reused, 4470)
    as "type 12: 2 spawns of Creature2 11070 for a count of 3"
  assert set.contains(reused, 4813) as "type 32: 5 crates for a count of 6"
  assert set.contains(reused, 15_980) as "type 5: 2 units for a count of 3"
  assert set.contains(reused, 10_383)
    as "type 23: 14 units of the group for a count of 15"
  let none = objective_units.reused(tables:, spawn_counts: dict.new())
  assert set.contains(none, 4813) && set.contains(none, 15_980)
    as "a supply of none is short"
}

pub fn reused_leaves_out_an_objective_with_enough_units_a_count_of_one_and_an_unlisted_one_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let reused =
    objective_units.reused(
      tables:,
      spawn_counts: spawns(counts: [
        #(11_070, 3),
        #(12_919, 6),
        #(19_277, 3),
        #(30_826, 8),
        #(30_827, 7),
      ]),
    )
  assert !set.contains(reused, 4470)
    as "type 12: 3 spawns for a count of 3 are enough"
  assert !set.contains(reused, 4813)
    as "type 32: 6 crates for a count of 6 are enough"
  assert !set.contains(reused, 15_980)
    as "type 5: 3 units for a count of 3 are enough"
  assert !set.contains(reused, 10_383)
    as "type 23: 15 units across the group for a count of 15 are enough"
  assert !set.contains(reused, 17_932)
    as "an objective of count 1 is finished by any unit, though no creature of it has a spawn"
  assert !set.contains(reused, 4098)
    as "a cast with no reward pane counts any unit, so the world is taken to hold enough"
  assert !set.contains(reused, 8323)
    as "a type 23 objective with no group is taken to hold enough as well"
  assert !set.contains(reused, 21_294)
    as "a checklist counts by bit and is never reused"
}
