//// What a talk to a creature, a use of one or a kill does to the open objectives of the
//// player's quest log, and what the client is told. A type 3 objective is a talk and a
//// type 12 objective a use, and the data of both is a Creature2 id
//// (`QuestObjective.type.3`, `0x1404dd4c0.objective_creature`). A kill counts for the
//// objectives of `0x140550c50`: type 2 for a unit of the Creature2 id in its data,
//// types 8 and 16 for a unit in the TargetGroup of its data, and, for a kill objective
//// of any of these types or of types 15 and 46, a unit in the objective's reward pane
//// TargetGroup (the pane counts whatever the type, but only a kill is wanted here:
//// the other types' own tests are not kills). Types 15 and 46 count by a cluster value
//// and a rank the server has no unit data for, so they take a kill only by the pane
//// (a gap, the issue "Kill objectives count by cluster, rank and a unit's tagged
//// value"). An objective takes the event only while it is open (`0x1405510d0`,
//// `0x140553790`): its quest is in the active list, Accepted or Achieved (`0x1405510d0`
//// tests only for state 3), it is not done and it is reachable. Every objective that is
//// open and counts the event counts once for it, so a later objective that the event
//// unlocks waits for the next one.
////
//// A rule: the log and the event in, the log and the effects out.

import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/target_group
import genesis_prime/table/id.{type Creature2Id, Creature2Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/set.{type Set}

/// The objective type of a talk.
const talk_type = 3

/// The objective type of a use.
const use_type = 12

/// The objective types of a kill (`0x140550c50` sets its kill result for these).
const kill_types = [2, 8, 15, 16, 46]

/// What the player did to a creature: talked to it, used it or killed it (the unit as
/// the client's group test reads it).
pub type Event {
  TalkedTo(creature_id: Creature2Id)
  Used(creature_id: Creature2Id)
  Killed(target: target_group.Unit)
}

/// What the client is told: one objective's new progress (0x361), and that a quest is
/// Achieved (0x35c, state 2) once its last open objective is done.
pub type Effect {
  SendProgress(quest_id: Int, objective_index: Int, progress: Int)
  SendAchieved(quest_id: Int)
}

/// The log after the event and the effects in order: a quest at a time in quest id
/// order, its progress messages in objective order, then Achieved when the event made it
/// so. A quest that was Achieved already is not told again.
pub type Advanced {
  Advanced(log: QuestLog, effects: List(Effect))
}

/// The Creature2 ids a talk counts for: those that an open type 3 objective of the log
/// names (`0x140553110`). Every quest of the log has its rows in the tables.
pub fn talk_targets(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> Set(Creature2Id) {
  list.flat_map(quest_log.active_ids(log:), fn(quest_id) {
    let quest = quest_of(tables:, quest_id:)
    quest_log.open_objectives(log:, quest:)
    |> list.filter(fn(open) { { open.1 }.type_ == talk_type })
    |> list.map(fn(open) { Creature2Id({ open.1 }.data) })
  })
  |> set.from_list
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
) -> Advanced {
  let counts = fn(objective) { counts(tables:, event:, objective:) }
  list.fold(
    quest_log.active_ids(log:),
    Advanced(log:, effects: []),
    fn(so_far, quest_id) {
      advance_quest(so_far:, quest: quest_of(tables:, quest_id:), counts:)
    },
  )
}

/// Whether the event counts for the objective (`0x140550c50`).
fn counts(
  tables tables: table_store.Tables,
  event event: Event,
  objective objective: quest_log.Objective,
) -> Bool {
  case event {
    TalkedTo(creature_id:) ->
      objective.type_ == talk_type && Creature2Id(objective.data) == creature_id
    Used(creature_id:) ->
      objective.type_ == use_type && Creature2Id(objective.data) == creature_id
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
  counts counts: fn(quest_log.Objective) -> Bool,
) -> Advanced {
  let named =
    quest_log.open_objectives(log: so_far.log, quest:)
    |> list.filter(fn(open) { counts(open.1) })
  let #(log, progress, became_achieved) =
    list.fold(named, #(so_far.log, [], False), fn(counted, open) {
      let #(log, progress, became_achieved) = counted
      case quest_log.progressed(log:, quest:, index: open.0, amount: 1) {
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
    })
  let state = case became_achieved {
    True -> [SendAchieved(quest_id: quest.id)]
    False -> []
  }
  Advanced(
    log:,
    effects: list.flatten([so_far.effects, list.reverse(progress), state]),
  )
}
