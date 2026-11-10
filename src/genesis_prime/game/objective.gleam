//// What a talk to a creature or a use of one does to the open objectives of the
//// player's quest log, and what the client is told. A type 3 objective is a talk and a
//// type 12 objective a use, and the data of both is a Creature2 id
//// (`QuestObjective.type.3`, `0x1404dd4c0.objective_creature`). An objective takes the
//// event only while it is open (`0x1405510d0`, `0x140553790`): its quest is accepted,
//// it is not done and it is reachable. Every objective that is open and names the
//// creature counts once for the event, so a later objective that the event unlocks
//// waits for the next one.
////
//// A rule: the log and the event in, the log and the effects out.

import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/table/loader/store as table_store
import gleam/list
import gleam/result
import gleam/set.{type Set}

/// The objective type of a talk.
const talk_type = 3

/// The objective type of a use.
const use_type = 12

/// What the player did to a creature, by its Creature2 id.
pub type Event {
  TalkedTo(creature_id: Int)
  Used(creature_id: Int)
}

/// What the client is told: one objective's new progress (0x361), and a quest's state
/// (0x35c) once its last open objective is done.
pub type Effect {
  SendProgress(quest_id: Int, objective_index: Int, progress: Int)
  SendState(quest_id: Int, state: Int)
}

/// The log after the event and the effects in order: a quest at a time in quest id
/// order, its progress messages in objective order, then its state when it is achieved.
pub type Advanced {
  Advanced(log: QuestLog, effects: List(Effect))
}

/// The Creature2 ids a talk counts for: those that an open type 3 objective of the log
/// names (`0x140553110`). A quest of the log whose rows the tables lack has no objective
/// to name, as the client's own rows give it none.
pub fn talk_targets(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> Set(Int) {
  list.flat_map(quest_log.active_ids(log:), fn(quest_id) {
    quest_log.quest_of(tables:, id: quest_id)
    |> result.map(fn(quest) {
      quest_log.open_objectives(log:, quest:)
      |> list.filter(fn(open) { { open.1 }.type_ == talk_type })
      |> list.map(fn(open) { { open.1 }.data })
    })
    |> result.unwrap([])
  })
  |> set.from_list
}

/// The log and the messages after the player talked to or used a creature.
pub fn advance(
  log log: QuestLog,
  tables tables: table_store.Tables,
  event event: Event,
) -> Advanced {
  let #(type_, creature_id) = case event {
    TalkedTo(creature_id:) -> #(talk_type, creature_id)
    Used(creature_id:) -> #(use_type, creature_id)
  }
  list.fold(
    quest_log.active_ids(log:),
    Advanced(log:, effects: []),
    fn(so_far, quest_id) {
      quest_log.quest_of(tables:, id: quest_id)
      |> result.map(fn(quest) {
        advance_quest(so_far:, quest:, type_:, creature_id:)
      })
      |> result.unwrap(so_far)
    },
  )
}

/// One quest's objectives that are open, of the type, and name the creature, each
/// counted once.
fn advance_quest(
  so_far so_far: Advanced,
  quest quest: quest_log.Quest,
  type_ type_: Int,
  creature_id creature_id: Int,
) -> Advanced {
  let named =
    quest_log.open_objectives(log: so_far.log, quest:)
    |> list.filter(fn(open) {
      { open.1 }.type_ == type_ && { open.1 }.data == creature_id
    })
  let #(log, progress, achieved) =
    list.fold(named, #(so_far.log, [], False), fn(counted, open) {
      let #(log, progress, _) = counted
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
          progressed.achieved,
        )
        // An achieved quest with an open objective takes no more progress.
        Error(Nil) -> counted
      }
    })
  let state = case achieved {
    True -> [SendState(quest_id: quest.id, state: 2)]
    False -> []
  }
  Advanced(
    log:,
    effects: list.flatten([so_far.effects, list.reverse(progress), state]),
  )
}
