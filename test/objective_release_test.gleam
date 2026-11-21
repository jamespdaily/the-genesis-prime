//// Which used creatures the objective release rule takes out of sight. Expected values
//// come from these places.
//// - A creature that gives or receives a quest other than the quests whose objectives
////   count it stays: Creature2's questIdGiven00 to 24 and questIdReceive00 to 24 name
////   them (`spawn.quest_ids`), and no client code makes a person vanish when an objective
////   counts it (Jim, 2026-11-21). A creature that gives only the quest that counts it is
////   that quest's own object and is released as before (the coordinator, 2026-11-21).
//// - Creature2 73491 is the tutorial's Dorian, who gives 10525 (Creature2 questIdGiven00
////   of row 73491 on the fixture's rows) and whom 10529's use objective counts.
//// - Creature2 12919 gives and receives no quest and is counted by quest 3741's use
////   objective, so it is released.

import client_tables
import genesis_prime/game/objective.{
  type Advanced, ReleaseUnit, SendProgress, Used,
}
import genesis_prime/game/objective_units
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Faction2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/world_map/spawn
import gleam/int
import gleam/list
import gleam/set
import owned_test
import quest_support
import unitest

const dorian = 73_491

const collectible = 12_919

/// The used unit's id: the creature's own, so each creature is its own unit.
fn a_use(
  tables tables: table_store.Tables,
  creature creature_id: Int,
) -> objective.Event {
  let assert Ok(creature) = creature2.get(tables, Creature2Id(creature_id))
    as "the creature's row is in the tables"
  Used(
    target: target_group.Unit(
      creature_id: Creature2Id(creature_id),
      faction_id: Faction2Id(0),
      unit_race_id: creature2.unit_race_id(creature),
    ),
    checklist_index: 0,
    unit: quest_support.unit_ref(unit_id: creature_id),
    by_item: False,
  )
}

fn used(
  tables tables: table_store.Tables,
  log log: quest_log.QuestLog,
  creature creature_id: Int,
) -> Advanced {
  objective.advance(
    reused: set.new(),
    log:,
    tables:,
    event: a_use(tables:, creature: creature_id),
    now_ms: 0,
    scripts: objective.no_rows(),
  )
}

pub fn a_quest_giver_counted_by_a_use_is_not_released_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- quest_support.with_objectives(edits: [])
  let assert Ok(row) = creature2.get(tables, Creature2Id(dorian))
    as "Dorian's row is in the tables"
  assert list.contains(spawn.given_quest_ids(row), 10_525)
    as "Creature2 73491 gives quest 10525"

  let giver_used =
    used(
      tables:,
      log: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: 10_529, progress: [0]),
      ]),
      creature: dorian,
    )
  assert list.contains(
    giver_used.effects,
    SendProgress(quest_id: 10_529, objective_index: 0, progress: 1),
  )
    as "the use of the giver counts for 10529"
  assert release_of(giver_used) == [] as "the giver counted by the use stays"

  let collectible_used =
    used(
      tables:,
      log: quest_support.log_of(rows: [
        quest_support.accepted(quest_id: 3741, progress: [0]),
      ]),
      creature: collectible,
    )
  assert release_of(collectible_used) == [collectible]
    as "a creature that gives and receives no quest is released when counted"
}

pub fn every_creature_a_quest_names_as_giver_or_receiver_is_kept_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let counted =
    list.flat_map(quest2.all(tables), fn(quest) {
      let assert Ok(of_quest) = quest_log.quest_of(tables:, id: quest.id)
        as "the quest's rows are in the tables"
      list.index_map(of_quest.objectives, fn(objective, index) {
        case
          objective_units.units_of(
            tables:,
            quest_id: quest.id,
            index:,
            objective:,
          )
        {
          objective_units.Listed(creatures:) ->
            list.filter_map(creatures, fn(creature_id) {
              case creature2.get(tables, creature_id) {
                Ok(row) ->
                  case list.any(spawn.quest_ids(row), fn(id) { id != 0 }) {
                    True -> Ok(#(quest.id, index, creature_id.value))
                    False -> Error(Nil)
                  }
                Error(Nil) -> Error(Nil)
              }
            })
          objective_units.Unlisted | objective_units.NoUnitEvent -> []
        }
      })
      |> list.flatten
    })
  let released =
    list.filter(counted, fn(case_) {
      let #(quest_id, index, creature_id) = case_
      let assert Ok(of_quest) = quest_log.quest_of(tables:, id: quest_id)
        as "the quest's rows are in the tables"
      let assert Ok(log) =
        quest_log.from_rows(
          rows: [
            quest_support.active(
              quest_id:,
              state: 1,
              placeholder: 0,
              tracked: False,
              done_mask: int.bitwise_shift_left(1, index) - 1,
              progress: list.repeat(0, list.length(of_quest.objectives)),
            ),
          ],
          tables:,
        )
        as "a log of the quest with its earlier objectives done"
      release_of(used(tables:, log:, creature: creature_id)) != []
    })
  assert list.length(counted) == 21
    as "21 objective cases count a use of a creature that gives or receives a quest"
  assert released == quest_objects
    as "the cases released are exactly the 14 whose creature gives only the quest that counts it; the 7 others (Dorian Walker, Artemis Zin, 4369's three, 6353, 4359) stay"
}

/// The (quest, objective index, creature) cases whose creature gives only the quest whose
/// objective counts it, in quest and index order: the quest's own objects (Stolen Draken
/// Bone, Dominion Research Equipment, three Bore Drills, Slush Still, Deadstar Dagun
/// Cage, Munitions Cache, Fuel Drum, Summoning Dust, Holding Pen, Unstable Accelerite,
/// Voreth Weapon Rack, Cage Door), read from Creature2's questIdGiven columns.
const quest_objects = [
  #(3655, 0, 12_321),
  #(3786, 0, 16_680),
  #(4109, 1, 14_514),
  #(4109, 2, 14_622),
  #(4109, 3, 14_623),
  #(4711, 0, 17_232),
  #(4948, 0, 18_899),
  #(5021, 0, 19_755),
  #(6052, 0, 26_525),
  #(6404, 0, 28_524),
  #(6429, 1, 28_840),
  #(6485, 0, 29_576),
  #(6707, 0, 30_757),
  #(8177, 0, 42_463),
]

/// The unit ids the advance releases.
fn release_of(advanced: Advanced) -> List(Int) {
  list.filter_map(advanced.effects, fn(effect) {
    case effect {
      ReleaseUnit(unit_id:) -> Ok(unit_id)
      objective.SendProgress(..)
      | objective.SendState(..)
      | objective.CompleteByServer(..) -> Error(Nil)
    }
  })
}
