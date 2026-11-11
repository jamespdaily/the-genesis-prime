//// The checklist index of each spawn (`genesis_prime/world_map/checklist_index`): the bit
//// the unit stands for in the mask of every checklist objective that counts it. Expected
//// values come from these places.
//// - `opcode.0x262`: the unit's index is one signed byte, the same for every player.
//// - `0x140611680` (`IsLogObjectiveTargetCounted`): the client tests the bit
////   `mask & (1 << index)` and counts an index of 32 or more as never counted, so a
////   checklist needs the indexes of its targets distinct in 0 to 31 to reach its count
////   (`opcode.0x361`: the server's mask has 32 bits).
//// - The world database gives all three spawns of Creature2 73500 (29338 to 29340, the
////   targets of objectives 21294 and 21307, count 3 each) the index 0 and the seven of
////   Creature2 73422 (29186 to 29192, the targets of 21319 and 21378, count 2 each) the
////   index 0: its indexes cannot complete them.
////
//// The client's rows in the fixture (`table_rows -- QuestObjective`):
//// - 21294 (quest 10520) and 21307 (quest 10523): type 14, TargetGroup 14425, which is
////   Creature2 73500, count 3.
//// - 21319 (quest 10525) and 21378 (quest 10526): type 18, TargetGroup 14368, which is
////   Creature2 73422, count 2.

import client_tables
import fixture_tables
import genesis_prime/game/target_group.{type Unit, Unit}
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Faction2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/checklist_index.{Candidate}
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/set
import owned_test
import planted_table.{Integer}
import unitest

/// The unit a spawn of the creature is, read from the creature's row: its faction and
/// race are the row's.
fn unit_of(tables tables: table_store.Tables, creature creature: Int) -> Unit {
  let assert Ok(row) = creature2.get(tables:, id: Creature2Id(creature))
    as "the fixture holds the creature's row"
  Unit(
    creature_id: Creature2Id(creature),
    faction_id: Faction2Id(row.faction_id),
    unit_race_id: creature2.unit_race_id(row),
  )
}

/// A spawn of the creature numbered `number`.
fn spawn_of(
  tables tables: table_store.Tables,
  creature creature: Int,
  number number: Int,
) -> checklist_index.Candidate {
  Candidate(spawn: SpawnId(number), unit: unit_of(tables:, creature:))
}

fn spawns_of(
  tables tables: table_store.Tables,
  creature creature: Int,
  numbers numbers: List(Int),
) -> List(checklist_index.Candidate) {
  list.map(numbers, fn(number) { spawn_of(tables:, creature:, number:) })
}

/// The numbers from `from` to `last`, both included.
fn upto(last: Int, from from: Int) -> List(Int) {
  int.range(from:, to: last + 1, with: [], run: list.prepend) |> list.reverse
}

fn index_of(indexes indexes: Dict(SpawnId, Int), number number: Int) -> Int {
  let assert Ok(index) = dict.get(indexes, SpawnId(number))
    as "every candidate spawn is given an index"
  index
}

fn indexes_of(
  indexes indexes: Dict(SpawnId, Int),
  numbers numbers: List(Int),
) -> List(Int) {
  list.map(numbers, fn(number) { index_of(indexes:, number:) })
}

pub fn each_target_spawn_of_a_checklist_objective_gets_a_distinct_index_test() -> Nil {
  use <- owned_test.run(10_000)
  // Objectives 21294 and 21307 count three of the three spawns of Creature2 73500: the
  // client's mask needs the three bits apart (0x140611680), and the world database's
  // 0, 0 and 0 would leave a mask of one bit.
  let tables = fixture_tables.shared()
  let spawns =
    spawns_of(tables:, creature: 73_500, numbers: [29_338, 29_339, 29_340])
  let indexes = checklist_index.assign(tables:, candidates: spawns)
  assert indexes_of(indexes:, numbers: [29_338, 29_339, 29_340]) == [0, 1, 2]
    as "opcode.0x262: each spawn takes the lowest index no other target of its objectives holds, in spawn order"
  let found =
    checklist_index.checklists(tables:, candidates: spawns)
    |> list.filter(fn(checklist) {
      list.contains([21_294, 21_307], checklist.objective_id)
    })
  assert list.length(found) == 2
    as "both objectives of the creature are checklists with the three spawns as targets"
  assert list.all(found, fn(checklist) {
    list.sort(checklist.targets, fn(a, b) {
      int.compare(spawn_number(a), spawn_number(b))
    })
    == [SpawnId(29_338), SpawnId(29_339), SpawnId(29_340)]
  })
    as "each lists the three spawns of Creature2 73500 as its targets"
}

fn spawn_number(spawn: SpawnId) -> Int {
  let SpawnId(number) = spawn
  number
}

pub fn a_spawn_in_two_objectives_keeps_one_index_distinct_in_both_test() -> Nil {
  use <- owned_test.run(10_000)
  // Objective 21307 (quest 10523) counts the group 14425, which this test gives a second
  // member, Creature2 73422: then Creature2 73422's spawn 1 is a target of 21307 beside
  // the three spawns of 73500 and the spawn 5 of 73422, and of 21319 and 21378 beside
  // the spawn 5. One index per unit has to be apart from the other targets of all three.
  use tables <- fixture_tables.changed(table: "TargetGroup", id: 14_425, with: [
    #("data1", Integer(73_422)),
  ])
  let spawns =
    list.flatten([
      spawns_of(tables:, creature: 73_422, numbers: [1]),
      spawns_of(tables:, creature: 73_500, numbers: [2, 3, 4]),
      spawns_of(tables:, creature: 73_422, numbers: [5]),
    ])
  let indexes = checklist_index.assign(tables:, candidates: spawns)
  let checklists = checklist_index.checklists(tables:, candidates: spawns)
  let of_quest = fn(quest_id) {
    let assert Ok(found) =
      list.find(checklists, fn(checklist) { checklist.quest_id == quest_id })
      as "the quest's checklist is found"
    found
  }
  let distinct = fn(quest_id) {
    let targets = { of_quest(quest_id) }.targets
    let found =
      list.map(targets, fn(spawn) {
        index_of(indexes:, number: spawn_number(spawn))
      })
    #(list.length(targets), set.size(set.from_list(found)))
  }
  assert distinct(10_523) == #(5, 5)
    as "the five targets of 21307 (spawn 1 of 73422, 2, 3 and 4 of 73500 and spawn 5 of 73422) hold five indexes"
  assert distinct(10_525) == #(2, 2)
    as "the two spawns of 73422 that 21319 counts hold two indexes, whichever the other objective's targets hold"
  assert distinct(10_526) == #(2, 2) as "and so do the two that 21378 counts"
}

pub fn a_spawn_that_is_no_checklist_target_gets_index_0_test() -> Nil {
  use <- owned_test.run(10_000)
  // The Virtual Battle Beast (Creature2 73464) is the target of no checklist objective in
  // the fixture, so its spawn takes no bit even beside spawns that do: the client reads
  // the index 0 of a unit that no objective counts and offers nothing for it.
  let tables = fixture_tables.shared()
  let spawns =
    list.flatten([
      spawns_of(tables:, creature: 73_500, numbers: [29_338, 29_339, 29_340]),
      spawns_of(tables:, creature: 73_464, numbers: [1, 29_339_000]),
    ])
  let indexes = checklist_index.assign(tables:, candidates: spawns)
  assert indexes_of(indexes:, numbers: [1, 29_339_000]) == [0, 0]
    as "opcode.0x262: a spawn that no checklist counts has the index 0, before and after the targets in spawn order"
  assert indexes_of(indexes:, numbers: [29_338, 29_339, 29_340]) == [0, 1, 2]
    as "and it takes no index from the targets"
}

pub fn an_objective_with_more_than_32_targets_still_completes_on_distinct_targets_test() -> Nil {
  use <- owned_test.run(10_000)
  // Objective 21307 with its count at 32 and forty spawns of 73500: the mask has 32
  // bits (opcode.0x361), so each of its 32 bits is one of the targets' indexes and the
  // objective completes on 32 distinct targets, with the other eight sharing a bit.
  use tables <- fixture_tables.changed(
    table: "QuestObjective",
    id: 21_307,
    with: [#("count", Integer(32))],
  )
  let numbers = upto(40, from: 1)
  let spawns = spawns_of(tables:, creature: 73_500, numbers:)
  let indexes = checklist_index.assign(tables:, candidates: spawns)
  let found = indexes_of(indexes:, numbers:)
  assert set.from_list(found) == set.from_list(upto(31, from: 0))
    as "the forty spawns use every index from 0 to 31 and none above"
  assert list.take(found, 32) == upto(31, from: 0)
    as "the first 32 spawns hold 32 distinct indexes, in order"
}

/// How many spawns each target creature gets in the whole-table test: as many as a
/// 32-bit mask has bits, the most an objective can count.
const spawns_each = 32

pub fn every_checklist_objective_in_a_quest_has_distinct_indexes_for_its_count_test() -> Nil {
  use <- owned_test.run(600_000)
  use <- unitest.guard(client_tables.present())
  // The client's whole tables, with a creature of the Creature2 table first given one
  // spawn to find the creatures any checklist objective counts, then 32 spawns each. Each
  // type 14, 18 and 28 objective of a quest has at least min(count, 32) distinct indexes
  // among its targets, or is listed with its gap: no creature that it counts, or a
  // count above 32, which a 32-bit mask cannot reach (`opcode.0x361`).
  let tables = client_tables.shared()
  let units =
    creature2.all(tables)
    |> list.map(fn(row) {
      Unit(
        creature_id: creature2.id(row),
        faction_id: Faction2Id(row.faction_id),
        unit_race_id: creature2.unit_race_id(row),
      )
    })
  let counted =
    list.map(units, fn(unit) {
      Candidate(spawn: SpawnId(unit.creature_id.value), unit:)
    })
    |> fn(candidates) { checklist_index.checklists(tables:, candidates:) }
    |> list.flat_map(fn(checklist) { checklist.targets })
    |> list.map(spawn_number)
    |> set.from_list
  let candidates =
    list.filter(units, fn(unit) {
      set.contains(counted, unit.creature_id.value)
    })
    |> list.flat_map(fn(unit) {
      list.map(upto(spawns_each - 1, from: 0), fn(at) {
        Candidate(spawn: SpawnId(unit.creature_id.value * 100 + at), unit:)
      })
    })
  let indexes = checklist_index.assign(tables:, candidates:)
  let outcomes =
    checklist_index.checklists(tables:, candidates:)
    |> list.map(fn(checklist) {
      let distinct =
        list.filter_map(checklist.targets, dict.get(indexes, _))
        |> set.from_list
        |> set.size
      case
        checklist.targets,
        checklist.count > 32,
        distinct >= checklist.count
      {
        _, True, _ -> "count above 32"
        [], False, _ -> "no creature counted"
        _, False, True -> "distinct"
        _, False, False -> "shared"
      }
    })
  let count_of = fn(outcome) {
    list.count(outcomes, fn(found) { found == outcome })
  }
  assert #(
      count_of("distinct"),
      count_of("no creature counted"),
      count_of("count above 32"),
      count_of("shared"),
    )
    == #(432, 20, 2, 0)
    as "objectives by outcome: distinct, listed with no creature counted, listed with a count above 32 (7207 and 7355), sharing indexes"
}
