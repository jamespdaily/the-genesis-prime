//// Which used creatures the objective release rule takes out of sight. Expected values
//// come from these places.
//// - A creature that gives or receives a quest none of whose objectives counts it stays:
////   Creature2's questIdGiven00 to 24 and questIdReceive00 to 24 name them
////   (`spawn.quest_ids`), and no client code makes a person vanish when an objective
////   counts it (the server's choice). A creature that gives and receives only quests whose
////   objectives count it is those quests' own object and is released as before (the
////   coordinator, 2026-11-21); the rescue cage 38508 gives 7732 and 7733 and both count it.
//// - Creature2 73491 is the tutorial's Dorian, who gives 10525 (Creature2 questIdGiven00
////   of row 73491 on the fixture's rows) and whom 10529's use objective counts.
//// - Creature2 12919 gives and receives no quest and is counted by quest 3741's use
////   objective, so it is released.

import client_tables
import content_support
import genesis_prime/game/click_objective
import genesis_prime/game/objective.{
  type Advanced, ReleaseUnit, SendProgress, Used,
}
import genesis_prime/game/objective_kind
import genesis_prime/game/objective_units
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/shared/quest_row
import genesis_prime/table/creature2
import genesis_prime/table/id.{Creature2Id, Faction2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_soldier_activate
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

const cage = 38_508

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
  scripts scripts: objective.ScriptRows,
) -> Advanced {
  objective.advance(
    reused: set.new(),
    log:,
    tables:,
    event: a_use(tables:, creature: creature_id),
    now_ms: 0,
    scripts:,
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
      scripts: objective.no_rows(),
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
      scripts: objective.no_rows(),
    )
  assert release_of(collectible_used) == [collectible]
    as "a creature that gives and receives no quest is released when counted"
}

pub fn a_rescue_cage_that_gives_both_factions_copies_of_its_quest_is_released_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let scripts = click_scripts()
  let assert Ok(row) = creature2.get(tables, Creature2Id(cage))
    as "the cage's row is in the tables"
  assert list.filter(spawn.given_quest_ids(row), fn(id) { id != 0 })
    |> list.sort(int.compare)
    == [7732, 7733]
    as "Creature2 38508 gives Explorer Extraction and Blown Cover"
  assert list.map([7732, 7733], fn(quest_id) {
      list.filter(counted_cases(tables:, scripts:), fn(case_) {
        case_.0 == quest_id && case_.2 == cage
      })
      |> list.length
    })
    == [1, 1]
    as "each of the two quests counts a use of the cage once"
  assert list.map([7732, 7733], fn(quest_id) {
      let assert [case_] =
        list.filter(counted_cases(tables:, scripts:), fn(case_) {
          case_.0 == quest_id && case_.2 == cage
        })
        as "one case of the quest counts the cage"
      is_released(tables:, scripts:, case_:)
    })
    == [True, True]
    as "a use of the cage that either quest counts releases it, the other faction's quest being one that counts it too"
}

pub fn every_creature_a_quest_names_as_giver_or_receiver_is_kept_test() -> Nil {
  use <- owned_test.run(300_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.every_table()
  let scripts = click_scripts()
  let counted = counted_cases(tables:, scripts:)
  let #(released, kept) =
    list.partition(counted, fn(case_) { is_released(tables:, scripts:, case_:) })
  assert list.length(counted) == 29
    as "29 objective cases count a use of a creature that gives or receives a quest"
  assert released == quest_objects
    as "the 22 cases released are those whose creature gives and receives only quests whose objectives count it; the 7 others stay"
  assert kept == people
    as "the cases kept are Dorian Walker, Artemis Zin, 4369's three, 6353 and 4359"
}

/// The (quest, objective index, creature) cases whose creature gives and receives only
/// quests whose objectives count it, in quest and index order: the quests' own objects
/// (Stolen Draken Bone, Dominion Research Equipment, three Bore Drills, Slush Still,
/// Deadstar Dagun Cage, Munitions Cache, Fuel Drum, Summoning Dust, Holding Pen, Unstable
/// Accelerite, Voreth Weapon Rack, Cage Door, and the checklist objects of 3771, 5265 and
/// 5697), read from Creature2's questIdGiven columns. Creature2 38508 gives 7732 and
/// 7733, and each counts it.
const quest_objects = [
  #(3655, 0, 12_321),
  #(3771, 0, 13_096),
  #(3786, 0, 16_680),
  #(4109, 0, 14_514),
  #(4109, 0, 14_622),
  #(4109, 0, 14_623),
  #(4109, 1, 14_514),
  #(4109, 2, 14_622),
  #(4109, 3, 14_623),
  #(4711, 0, 17_232),
  #(4948, 0, 18_899),
  #(5021, 0, 19_755),
  #(5265, 0, 21_627),
  #(5697, 0, 25_036),
  #(6052, 0, 26_525),
  #(6404, 0, 28_524),
  #(6429, 1, 28_840),
  #(6485, 0, 29_576),
  #(6707, 0, 30_757),
  #(7732, 0, 38_508),
  #(7733, 0, 38_508),
  #(8177, 0, 42_463),
]

/// The cases whose creature gives or receives a quest none of whose objectives counts it:
/// 10529 and 10533 count Dorian Walker and Artemis Zin, who give 10525 and 10526 among
/// others; 4369's three and 6353 and 4359 count a creature that receives or gives another
/// quest.
const people = [
  #(4359, 0, 15_883),
  #(4369, 0, 15_790),
  #(4369, 1, 15_784),
  #(4369, 2, 15_782),
  #(6353, 0, 1),
  #(10_529, 0, 73_491),
  #(10_533, 0, 74_861),
]

/// Whether a use of the case's creature, counted by the case's objective, releases it.
fn is_released(
  tables tables: table_store.Tables,
  scripts scripts: objective.ScriptRows,
  case_ case_: #(Int, Int, Int),
) -> Bool {
  let #(quest_id, index, creature_id) = case_
  let assert Ok(of_quest) = quest_row.quest_of(tables:, id: quest_id)
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
  release_of(used(tables:, log:, creature: creature_id, scripts:)) != []
}

/// The click table's rows, which count a use of a creature of their reward pane.
fn click_scripts() -> objective.ScriptRows {
  objective.ScriptRows(
    ..objective.no_rows(),
    clicks: content_support.objective_ids(table: click_objective.table),
  )
}

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

/// The (quest, objective index, creature) cases whose objective counts a use of a creature
/// that gives or receives a quest, over every quest of the tables, in quest and index
/// order. The creatures tried for an objective are those its kind names: its creature or
/// the creatures linked to it, the creatures of its TargetGroup (a use or a checklist use),
/// the creature of its soldier activate row, and the creatures of its reward pane when it
/// is a click row. `objective.counts` decides which of them it counts. A group that names
/// no creature (a faction or a race) is not tried.
fn counted_cases(
  tables tables: table_store.Tables,
  scripts scripts: objective.ScriptRows,
) -> List(#(Int, Int, Int)) {
  list.flat_map(quest2.all(tables), fn(quest) {
    let assert Ok(of_quest) = quest_row.quest_of(tables:, id: quest.id)
      as "the quest's rows are in the tables"
    list.index_map(of_quest.objectives, fn(objective, index) {
      tried_creatures(tables:, scripts:, quest_id: quest.id, index:, objective:)
      |> list.filter(fn(creature_id) {
        names_a_quest(tables:, creature_id:)
        && objective.counts(
          tables:,
          event: a_use(tables:, creature: creature_id.value),
          quest_id: quest.id,
          index:,
          objective:,
          scripts:,
        )
      })
      |> list.map(fn(creature_id) { #(quest.id, index, creature_id.value) })
    })
    |> list.flatten
  })
}

fn tried_creatures(
  tables tables: table_store.Tables,
  scripts scripts: objective.ScriptRows,
  quest_id quest_id: Int,
  index index: Int,
  objective objective: quest_row.Objective,
) -> List(id.Creature2Id) {
  let listed = case
    objective_units.units_of(tables:, quest_id:, index:, objective:)
  {
    objective_units.Listed(creatures:) -> creatures
    objective_units.Unlisted | objective_units.NoUnitEvent -> []
  }
  let checklist_use = case objective_kind.used_checklist_group(objective.kind) {
    Ok(group) -> target_group.creatures_of(tables:, group: group.value)
    Error(Nil) -> []
  }
  let soldier = case objective_kind.checklist_target(objective.kind) {
    Ok(objective_kind.UnitOfSoldier(path_soldier_activate_id:)) ->
      case path_soldier_activate.get(tables:, id: path_soldier_activate_id) {
        Ok(row) -> [Creature2Id(row.creature2_id)]
        Error(Nil) -> []
      }
    Ok(objective_kind.UnitsOfGroup(_)) | Error(Nil) -> []
  }
  let clicked = case
    objective.kind == objective_kind.Scripted
    && set.contains(scripts.clicks, objective.objective_id)
  {
    True -> target_group.creatures_of(tables:, group: objective.reward_pane)
    False -> []
  }
  list.flatten([listed, checklist_use, soldier, clicked]) |> list.unique
}

fn names_a_quest(
  tables tables: table_store.Tables,
  creature_id creature_id: id.Creature2Id,
) -> Bool {
  case creature2.get(tables, creature_id) {
    Ok(row) -> list.any(spawn.quest_ids(row), fn(id) { id != 0 })
    Error(Nil) -> False
  }
}
