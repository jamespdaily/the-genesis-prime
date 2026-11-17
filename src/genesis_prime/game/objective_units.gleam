//// Which creatures an objective counts a use or a cast at, and from that the objectives
//// whose units the world holds too few of: the objectives whose unit may count again.
////
//// ```
//// the client's tables ─▶ units_of(quest, index, objective) ─▶ Listed(creatures) | Unlisted | NoUnitEvent
//// the spawn table     ─▶ counts(rows) ─┐
//// every quest's objectives ─▶ reused ──┴▶ the objective ids whose unit counts again
//// ```
////
//// - **The rule** (`objective.advance`): a unit counts once for an objective, per map run,
////   unless the world holds fewer units that objective counts than its count. The client
////   keeps no record of a unit used for any objective that is not a checklist
////   (`0x1405517a0`) and offers a linked creature again until its objective is done
////   (`QuestObjective.type.32.repeat_use`), so the once and the exception are the server's
////   choice.
//// - **Which creatures a kind counts** (`units_of`): type 12 the creature of its data
////   (`0x140550c50`), types 5 and 32 the creatures whose rows link the objective
////   (`Creature2.objective_link`), type 23 the creatures of its TargetGroup (`0x140550c50`;
////   a departures choice objective only its own terminal, as `objective.counts` holds it),
////   and type 11 the creatures of its reward pane, which the client tests for any type
////   (`0x140550c50`). A group or pane that names no creature (a faction, a race, nested
////   groups) and a cast with no pane count any unit, so the world is taken to hold enough
////   of them: a guess, as no client column says how many units such an objective needs.
//// - **The supply** (`reused`): the spawn rows of the creatures `units_of` lists, each
////   creature once, summed over every world, since a unit is remembered across maps. An
////   objective whose count is above 1 and whose supply is below it is reused; a supply of
////   none counts as below. A count of 1 is finished by any unit.

import genesis_prime/game/departures
import genesis_prime/game/objective_kind
import genesis_prime/game/objective_link
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/table/id.{type Creature2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set.{type Set}

/// The creatures an objective counts a use or a cast at.
pub type Units {
  /// These creatures, each once, and no other.
  Listed(creatures: List(Creature2Id))
  /// A unit the server cannot list: a cast with no reward pane, or a TargetGroup that names
  /// no creature.
  Unlisted
  /// The objective counts no use of a unit and no cast at one: a kill, a talk, a
  /// checklist (counted by bits), an item, a visit and the rest.
  NoUnitEvent
}

/// The units the objective at `index` of the quest counts.
pub fn units_of(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
  objective objective: quest_log.Objective,
) -> Units {
  case objective.kind {
    objective_kind.UseCreature(creature2_id:) -> Listed([creature2_id])
    objective_kind.Scripted | objective_kind.CollectVirtualItem(_) ->
      Listed(objective_link.creatures_linked(tables:, quest_id:, index:))
    objective_kind.UseGroup(target_group_id:) ->
      case target_group.creatures_of(tables:, group: target_group_id.value) {
        [] -> Unlisted
        creatures ->
          Listed(only_the_terminals_choice(
            objective_id: objective.objective_id,
            creatures:,
          ))
      }
    objective_kind.CastSpell(_) ->
      case objective.reward_pane {
        0 -> Unlisted
        pane ->
          case target_group.creatures_of(tables:, group: pane) {
            [] -> Unlisted
            creatures -> Listed(list.unique(creatures))
          }
      }
    objective_kind.ChecklistUse(_)
    | objective_kind.ChecklistActivate(_)
    | objective_kind.ChecklistTalk(_)
    | objective_kind.ServerChecklist
    | objective_kind.TalkTo(_)
    | objective_kind.KillCreature(_)
    | objective_kind.KillGroup(_)
    | objective_kind.KillByCluster(_)
    | objective_kind.KillByDifficulty(_)
    | objective_kind.CollectItem(_)
    | objective_kind.CraftItem(_)
    | objective_kind.VisitZone(_)
    | objective_kind.ReachPlace
    | objective_kind.FinishQuest(_)
    | objective_kind.Placeholder
    | objective_kind.Unconditional
    | objective_kind.Unread(_) -> NoUnitEvent
  }
}

/// The creatures of a type 23 group, each once, as `objective.counts` takes them: a
/// departures choice objective counts only its own terminal.
fn only_the_terminals_choice(
  objective_id objective_id: Int,
  creatures creatures: List(Creature2Id),
) -> List(Creature2Id) {
  let unique = list.unique(creatures)
  case departures.choice_terminal(objective_id:) {
    None -> unique
    Some(terminal) -> list.filter(unique, fn(creature) { creature == terminal })
  }
}

/// The QuestObjective ids of the objectives whose count is above 1 and whose listed units
/// have fewer spawn rows in `spawn_counts` (the rows of each Creature2 id) than the count,
/// across every quest of the tables. An objective that two quests share is in the set when
/// it is short in either. A spawn import that adds units takes an objective out of the
/// set.
pub fn reused(
  tables tables: table_store.Tables,
  spawn_counts spawn_counts: Dict(Int, Int),
) -> Set(Int) {
  list.fold(quest2.all(tables), set.new(), fn(reused, row) {
    let quest_id = quest2.id(row).value
    case quest_log.quest_of(tables:, id: quest_id) {
      Ok(quest) ->
        list.index_fold(quest.objectives, reused, fn(reused, objective, index) {
          case is_short(tables:, spawn_counts:, quest_id:, index:, objective:) {
            True -> set.insert(reused, objective.objective_id)
            False -> reused
          }
        })
      Error(quest_log.NoQuestRow) | Error(quest_log.NoObjectiveRow(_)) -> reused
    }
  })
}

/// Whether the objective takes more than one unit and the world holds fewer units of the
/// creatures it counts than that.
fn is_short(
  tables tables: table_store.Tables,
  spawn_counts spawn_counts: Dict(Int, Int),
  quest_id quest_id: Int,
  index index: Int,
  objective objective: quest_log.Objective,
) -> Bool {
  case objective.count > 1, units_of(tables:, quest_id:, index:, objective:) {
    True, Listed(creatures) ->
      supply(spawn_counts:, creatures:) < objective.count
    True, Unlisted | True, NoUnitEvent | False, _ -> False
  }
}

/// The spawn rows of the creatures, each creature once.
fn supply(
  spawn_counts spawn_counts: Dict(Int, Int),
  creatures creatures: List(Creature2Id),
) -> Int {
  list.unique(creatures)
  |> list.map(fn(creature) {
    result.unwrap(dict.get(spawn_counts, creature.value), 0)
  })
  |> int.sum
}
