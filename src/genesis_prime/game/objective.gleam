//// What a talk to a creature, a use of one or a kill does to the open objectives of the
//// player's quest log, and what the client is told. A type 3 objective is a talk and a
//// type 12 objective a use, and the data of both is a Creature2 id
//// (`QuestObjective.type.3`, `0x1404dd4c0.objective_creature`). A checklist objective
//// counts each unit once, by the unit's checklist index: type 14 is a use and type 18 a
//// talk of a unit in the TargetGroup of its data, type 28 a use of the creature of the
//// PathSoldierActivate row of its data (when that row makes it a checklist,
//// `quest_log.is_checklist`); the use or talk sets the bit of the unit's index in the
//// objective's mask, and a unit whose bit is set counts for nothing
//// (`opcode.0x361`, `0x140611680`). A kill counts for the
//// objectives of `0x140550c50`: type 2 for a unit of the Creature2 id in its data,
//// types 8 and 16 for a unit in the TargetGroup of its data, and, for a kill objective
//// of any of these types or of types 15 and 46, a unit in the objective's reward pane
//// TargetGroup (the pane counts whatever the type, but only a kill is wanted here:
//// the other types' own tests are not kills). Types 15 and 46 count by a cluster value
//// and a rank the server has no unit data for, so they take a kill only by the pane
//// (a gap, the issue "Kill objectives count by cluster, rank and a unit's tagged
//// value"). A type 5 objective (`QuestObjective.type.5`, a scripted objective) takes
//// none of these events: nothing completes it (a gap, the issue "Quests, zones and
//// prerequisites work on the real client"), so a timed one runs out
//// (`quest_log.expire`). An objective takes the event only while it is open (`0x1405510d0`,
//// `0x140553790`): its quest is in the active list, Accepted or Achieved (`0x1405510d0`
//// tests only for state 3), it is not done and it is reachable. Every objective that is
//// open and counts the event counts once for it, so a later objective that the event
//// unlocks waits for the next one.
////
//// A rule: the log and the event in, the log and the effects out.

import genesis_prime/game/quest as quest_rules
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/target_group
import genesis_prime/store.{type HeldItem}
import genesis_prime/table/creature2
import genesis_prime/table/id.{
  type Creature2Id, type Item2Id, Creature2Id, Item2Id, PathSoldierActivateId,
  TradeskillSchematic2Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_soldier_activate
import genesis_prime/table/tradeskill_schematic2
import gleam/int
import gleam/list

/// The objective type of a talk.
const talk_type = 3

/// The objective type of a use.
const use_type = 12

/// The objective type of a checklist use: a unit of the TargetGroup in its data.
const checklist_use_type = 14

/// The objective type of a checklist talk: a unit of the TargetGroup in its data.
const checklist_talk_type = 18

/// The objective type of a checklist use of a PathSoldierActivate creature.
const path_soldier_type = 28

/// The objective type of a quest collectible: a use of a creature whose Creature2 row
/// names the quest and the objective's index (`0x1405a8b30`; a guess, see
/// `names_the_objective`).
const collectible_type = 32

/// The objective type of a held item: the Item2 id in its data.
const held_type = 4

/// The objective type of a made item: a TradeskillSchematic2 id in its data, counted
/// by the schematic's output item.
const made_type = 33

/// The objective type of a visit: a WorldZone id in its data.
const visit_type = 17

/// The state number of an Achieved quest in 0x035C.
const achieved_state = 2

/// The objective types of a kill (`0x140550c50` sets its kill result for these).
const kill_types = [2, 8, 15, 16, 46]

/// What the player did to a creature: talked to it, used it or killed it (the unit as
/// the client's group test reads it), with the unit's checklist index for the first two
/// (the bit the unit stands for in a checklist objective's mask).
pub type Event {
  TalkedTo(target: target_group.Unit, checklist_index: Int)
  Used(target: target_group.Unit, checklist_index: Int)
  Killed(target: target_group.Unit)
}

/// What the client is told: one objective's new progress (0x361), and a quest's new
/// state (0x35c): 2 (Achieved) once its last open objective is done, 1 (Accepted) when
/// a count fell and an objective is not done again (`0x1405fb830`, `0x1405fbdc0`).
pub type Effect {
  SendProgress(quest_id: Int, objective_index: Int, progress: Int)
  SendState(quest_id: Int, state: Int)
}

/// The log after the event and the effects in order: a quest at a time in quest id
/// order, its progress messages in objective order, then its state when the event moved
/// it. A quest that was Achieved already is not told again.
pub type Advanced {
  Advanced(log: QuestLog, effects: List(Effect))
}

/// Whether a talk to the unit, of the checklist index, counts for an open objective of
/// the log: a type 3 objective that names its Creature2 id (`0x140553110`), or a type 18
/// objective whose TargetGroup holds it while its bit is not yet set (`0x140611680`: the
/// client marks the unit only then). Every quest of the log has its rows in the tables.
pub fn talk_targets(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> fn(target_group.Unit, Int) -> Bool {
  counted_by(log:, tables:, event_of: fn(unit, checklist_index) {
    TalkedTo(target: unit, checklist_index:)
  })
}

/// Whether a use of the unit, of the checklist index, counts for an open objective of the
/// log: the objectives a `Used` event counts for (`counts`) while the unit's bit is not
/// yet set, as a talk's is (`talk_targets`). A unit no open objective counts a use of is
/// offered no use by the server.
pub fn use_targets(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> fn(target_group.Unit, Int) -> Bool {
  counted_by(log:, tables:, event_of: fn(unit, checklist_index) {
    Used(target: unit, checklist_index:)
  })
}

fn counted_by(
  log log: QuestLog,
  tables tables: table_store.Tables,
  event_of event_of: fn(target_group.Unit, Int) -> Event,
) -> fn(target_group.Unit, Int) -> Bool {
  let open =
    list.flat_map(quest_log.active_ids(log:), fn(quest_id) {
      let quest = quest_of(tables:, quest_id:)
      quest_log.open_objectives(log:, quest:)
      |> list.map(fn(open) { #(quest, open.0, open.1) })
    })
  fn(unit, checklist_index) {
    let event = event_of(unit, checklist_index)
    list.any(open, fn(found) {
      let #(quest, index, objective) = found
      counts(tables:, event:, quest_id: quest.id, index:, objective:)
      && !quest_log.is_marked(log:, quest:, index:, bit: checklist_index)
    })
  }
}

fn quest_of(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
) -> quest_log.Quest {
  let assert Ok(quest) = quest_log.quest_of(tables:, id: quest_id)
    as {
      "quest "
      <> int.to_string(quest_id)
      <> " of the player's log has its rows in the tables"
    }
  quest
}

/// The log and the messages after the player talked to or used a creature.
pub fn advance(
  log log: QuestLog,
  tables tables: table_store.Tables,
  event event: Event,
  now_ms now_ms: Int,
) -> Advanced {
  list.fold(
    quest_log.active_ids(log:),
    Advanced(log:, effects: []),
    fn(so_far, quest_id) {
      advance_quest(
        so_far:,
        quest: quest_of(tables:, quest_id:),
        now_ms:,
        counts: fn(index, objective) {
          counts(tables:, event:, quest_id:, index:, objective:)
        },
        checklist_index: case event {
          TalkedTo(checklist_index:, ..) | Used(checklist_index:, ..) ->
            checklist_index
          Killed(..) -> -1
        },
      )
    },
  )
}

/// Whether the event counts for the objective at `index` of the quest (`0x140550c50`).
fn counts(
  tables tables: table_store.Tables,
  event event: Event,
  quest_id quest_id: Int,
  index index: Int,
  objective objective: quest_log.Objective,
) -> Bool {
  case event {
    TalkedTo(target:, ..) ->
      {
        objective.type_ == talk_type
        && Creature2Id(objective.data) == target.creature_id
      }
      || {
        objective.type_ == checklist_talk_type
        && target_group.contains(tables:, group: objective.data, unit: target)
      }
    Used(target:, ..) ->
      {
        objective.type_ == use_type
        && Creature2Id(objective.data) == target.creature_id
      }
      || {
        objective.type_ == checklist_use_type
        && target_group.contains(tables:, group: objective.data, unit: target)
      }
      || {
        objective.type_ == path_soldier_type
        && objective.checklist
        && activates_creature(
          tables:,
          path_soldier_activate: objective.data,
          creature_id: target.creature_id,
        )
      }
      || {
        objective.type_ == collectible_type
        && names_the_objective(
          tables:,
          creature_id: target.creature_id,
          quest_id:,
          index:,
        )
      }
    Killed(target:) -> {
      let by_data = case objective.type_ {
        2 -> Creature2Id(objective.data) == target.creature_id
        8 | 16 ->
          target_group.contains(tables:, group: objective.data, unit: target)
        _ -> False
      }
      let is_kill = list.contains(kill_types, objective.type_)
      by_data
      || {
        is_kill
        && objective.reward_pane != 0
        && target_group.contains(
          tables:,
          group: objective.reward_pane,
          unit: target,
        )
      }
    }
  }
}

/// One quest's objectives that are open and that the event counts for, each counted
/// once. An Achieved quest still has its objectives with flag 0x20 open.
fn advance_quest(
  so_far so_far: Advanced,
  quest quest: quest_log.Quest,
  now_ms now_ms: Int,
  counts counts: fn(Int, quest_log.Objective) -> Bool,
  checklist_index checklist_index: Int,
) -> Advanced {
  let named =
    quest_log.open_objectives(log: so_far.log, quest:)
    |> list.filter(fn(open) { counts(open.0, open.1) })
  let #(log, progress, became_achieved) =
    list.fold(named, #(so_far.log, [], False), fn(counted, open) {
      let #(log, progress, became_achieved) = counted
      case { open.1 }.checklist {
        True ->
          case
            quest_log.marked(
              log:,
              quest:,
              index: open.0,
              bit: checklist_index,
              now_ms:,
            )
          {
            // A unit whose bit is set counts for nothing and tells nothing.
            Ok(marked) if marked.changed -> #(
              marked.log,
              [
                SendProgress(
                  quest_id: quest.id,
                  objective_index: open.0,
                  progress: marked.progress,
                ),
                ..progress
              ],
              became_achieved || marked.moved == quest_log.BecameAchieved,
            )
            Ok(_) | Error(Nil) -> counted
          }
        False ->
          case
            quest_log.progressed(
              log:,
              quest:,
              index: open.0,
              amount: 1,
              now_ms:,
            )
          {
            Ok(progressed) -> #(
              progressed.log,
              [
                SendProgress(
                  quest_id: quest.id,
                  objective_index: open.0,
                  progress: progressed.progress,
                ),
                ..progress
              ],
              became_achieved || progressed.became_achieved,
            )
            // An open objective takes progress, so this does not happen.
            Error(Nil) -> counted
          }
      }
    })
  let state = case became_achieved {
    True -> [SendState(quest_id: quest.id, state: achieved_state)]
    False -> []
  }
  Advanced(
    log:,
    effects: list.flatten([so_far.effects, list.reverse(progress), state]),
  )
}

/// Whether the PathSoldierActivate row is the activation of the creature.
fn activates_creature(
  tables tables: table_store.Tables,
  path_soldier_activate path_soldier_activate_id: Int,
  creature_id creature_id: Creature2Id,
) -> Bool {
  case
    path_soldier_activate.get(
      tables:,
      id: PathSoldierActivateId(path_soldier_activate_id),
    )
  {
    Ok(row) -> Creature2Id(row.creature2_id) == creature_id
    Error(Nil) -> False
  }
}

/// Whether the creature's row names this objective of this quest as a collectible
/// (`quest_anim_state_id` is the quest, `quest_anim_objective_index` the objective's
/// index; `0x1405a8b30`). The client counts nothing for type 32 itself: the server
/// sends the value. That a finished activate cast is the count is a guess, graded so in
/// the client facts, which a retail recording of such a creature would settle.
fn names_the_objective(
  tables tables: table_store.Tables,
  creature_id creature_id: Creature2Id,
  quest_id quest_id: Int,
  index index: Int,
) -> Bool {
  case creature2.get(tables:, id: creature_id) {
    Ok(row) ->
      row.quest_anim_state_id == quest_id
      && row.quest_anim_objective_index == index
    Error(Nil) -> False
  }
}

/// The log and the messages after what the player holds and the zones they stand in
/// changed (`zones` is the player's zone and its parents, which a visit names one of;
/// empty when the player is nowhere yet, as at login).
///
/// The client counts nothing for objective types 4, 33 and 17: it stores the value the
/// server sends and the objective is done once the value reaches its count
/// (`0x140575a80`, `0x14079d700`, `0x1406115a0`). So the server sets each type 4
/// objective to the number of its Item2 held in the locations the accept check counts
/// (`quest.held_count`), a type 33 objective to that of its schematic's output item,
/// and a type 17 objective to done while its zone is among `zones`. A count that falls
/// takes the done bit away, and an Achieved quest with an objective not done is Accepted
/// again. A held count is set whether or not its objective is reachable; a visit counts
/// only once it is open (`0x140553790`), so a visit that an earlier count opens counts
/// in the same pass. A quest at a time in id order, its progress messages in objective
/// order for each objective that changed, then one state message when the quest's state
/// is not what it was.
pub fn settle(
  log log: QuestLog,
  tables tables: table_store.Tables,
  items items: List(HeldItem),
  zones zones: List(Int),
  now_ms now_ms: Int,
) -> Advanced {
  list.fold(
    quest_log.active_ids(log:),
    Advanced(log:, effects: []),
    fn(so_far, quest_id) {
      let quest = quest_of(tables:, quest_id:)
      let before = quest_log.stored_state(log: so_far.log, quest_id:)
      let held =
        list.index_fold(
          quest.objectives,
          Settling(log: so_far.log, progress: []),
          fn(settling, objective, index) {
            case held_item(tables:, objective:) {
              Ok(item2_id) ->
                set_count(
                  settling:,
                  quest:,
                  index:,
                  value: quest_rules.held_count(items:, item2_id:),
                  now_ms:,
                )
              Error(Nil) -> settling
            }
          },
        )
      let settling = visits(settling: held, quest:, zones:, now_ms:)
      let after = quest_log.stored_state(log: settling.log, quest_id:)
      let state = case after != before {
        True -> [SendState(quest_id:, state: after)]
        False -> []
      }
      Advanced(
        log: settling.log,
        effects: list.flatten([
          so_far.effects,
          list.reverse(settling.progress),
          state,
        ]),
      )
    },
  )
}

/// A quest's log while it is settled and the progress messages so far, latest first.
type Settling {
  Settling(log: QuestLog, progress: List(Effect))
}

/// The Item2 whose held count a type 4 or type 33 objective takes as its progress, or
/// `Error(Nil)` for an objective of another type. A type 33 objective's schematic is a
/// row of the table (the tables test checks every one a quest names), so a missing row
/// ends the process.
fn held_item(
  tables tables: table_store.Tables,
  objective objective: quest_log.Objective,
) -> Result(Item2Id, Nil) {
  case objective.type_ == held_type, objective.type_ == made_type {
    True, _ -> Ok(Item2Id(objective.data))
    _, True -> {
      let assert Ok(schematic) =
        tradeskill_schematic2.get(
          tables:,
          id: TradeskillSchematic2Id(objective.data),
        )
        as "a type 33 objective names a TradeskillSchematic2 row"
      Ok(tradeskill_schematic2.item2_id_output(schematic))
    }
    _, _ -> Error(Nil)
  }
}

/// The objective at `index` set to `value`, with its progress message when its progress
/// changed. Only a quest in the active list is settled and `index` is one of its
/// objectives, so the count is always taken.
fn set_count(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  index index: Int,
  value value: Int,
  now_ms now_ms: Int,
) -> Settling {
  let assert Ok(counted) =
    quest_log.counted(log: settling.log, quest:, index:, value:, now_ms:)
    as "a settled quest is in the active list and the index is one of its objectives"
  Settling(log: counted.log, progress: case counted.changed {
    True -> [
      SendProgress(
        quest_id: quest.id,
        objective_index: index,
        progress: counted.progress,
      ),
      ..settling.progress
    ]
    False -> settling.progress
  })
}

/// Every open visit of the quest whose zone is among `zones` done, again while a visit
/// that the last one opened is not (`0x140553790`). Data 0 names no zone, though the
/// chain of zone 0 holds it. A done visit is not counted again, which ends the loop.
fn visits(
  settling settling: Settling,
  quest quest: quest_log.Quest,
  zones zones: List(Int),
  now_ms now_ms: Int,
) -> Settling {
  let waiting =
    quest_log.open_objectives(log: settling.log, quest:)
    |> list.filter(fn(open) {
      let #(index, objective) = open
      objective.type_ == visit_type
      && objective.data != 0
      && list.contains(zones, objective.data)
      && quest_log.objective_progress(log: settling.log, quest:, index:)
      < objective.count
    })
  case waiting {
    [] -> settling
    _ ->
      list.fold(waiting, settling, fn(settling, open) {
        set_count(
          settling:,
          quest:,
          index: open.0,
          value: { open.1 }.count,
          now_ms:,
        )
      })
      |> visits(quest:, zones:, now_ms:)
  }
}
