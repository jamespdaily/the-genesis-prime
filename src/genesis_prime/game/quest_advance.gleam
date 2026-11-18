//// A spell's QuestAdvanceObjective effect applied to the player's quest log: the rule that
//// turns the advances a go (or the timer of a delayed row) hands the connection into
//// progress, a quest's state and its completion.
////
//// ```
//// advances (quest, index, amount) + the cast's own use or cast ─▶ advance(log) ─▶ Advanced(log, effects)
//// ```
////
//// - **The amount** is `dataBits02`, added to the stored progress and capped at the
////   objective's needed count (`quest_log.progressed`, `0x140551840`); for a percent kind of
////   kill objective the amount counts kills and the stored progress is thousandths
////   (`0x1405515c0`) (`Spell4Effects.effectType.42`).
//// - **An objective that takes no progress** gets none and tells nothing: a quest that is not
////   in the log, an objective that is done or closed behind another, an index past the quest's
////   objectives (`quest_log.progressed`, `0x1405510d0`, `0x140553790`), and a checklist, whose
////   stored value is a mask of units and has no unit to set a bit for (a server choice).
//// - **One count per cast** (a server choice): an objective that the cast's own use or cast
////   counts (`objective.counts`) is skipped, so a creature's activate spell that also holds a
////   row for the objective its use counts does not count it twice. A use does not count a
////   kill objective, so the row advances it.
//// - **The effects** are those of `objective.advance`, one quest at a time in quest id order:
////   its progress messages in objective order, then its state 2 and the server's completion
////   when the advance made it Achieved.
////
//// A rule: the log, the advances and the cast's own event in, the log and the effects out.

import genesis_prime/game/objective.{type Advanced, Advanced}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// One row of a spell's QuestAdvanceObjective effect: `amount` added to the progress of the
/// objective at `objective_index` of the quest `quest_id`.
pub type Advance {
  Advance(quest_id: Int, objective_index: Int, amount: Int)
}

/// The log and the messages after a cast advanced these objectives, `with` the event of the
/// cast's own use or cast, when it made one (`objective.Event`), which counts for the
/// objectives it names itself.
pub fn advance(
  log log: QuestLog,
  tables tables: table_store.Tables,
  advances advances: List(Advance),
  with with: Option(objective.Event),
  now_ms now_ms: Int,
) -> Advanced {
  list.fold(
    quest_log.active_ids(log:),
    Advanced(log:, effects: []),
    fn(so_far, quest_id) {
      let named =
        list.filter(advances, fn(one) { one.quest_id == quest_id })
        |> list.sort(fn(a, b) {
          int.compare(a.objective_index, b.objective_index)
        })
      case named {
        [] -> so_far
        [_, ..] -> {
          let assert Ok(quest) = quest_log.quest_of(tables:, id: quest_id)
            as "a quest of the player's log has its rows in the tables"
          quest_advanced(
            so_far:,
            tables:,
            quest:,
            advances: named,
            with:,
            now_ms:,
          )
        }
      }
    },
  )
}

/// One quest's advances applied in the order given, each to its objective when it takes
/// progress, and the quest's state and completion after them when one made it Achieved.
fn quest_advanced(
  so_far so_far: Advanced,
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
  advances advances: List(Advance),
  with with: Option(objective.Event),
  now_ms now_ms: Int,
) -> Advanced {
  let #(log, progress, became_achieved) =
    list.fold(advances, #(so_far.log, [], False), fn(pass, one) {
      let #(log, progress, became_achieved) = pass
      case takes_the_advance(tables:, quest:, one:, with:) {
        False -> pass
        True ->
          case
            quest_log.progressed(
              log:,
              quest:,
              index: one.objective_index,
              amount: one.amount,
              now_ms:,
            )
          {
            Ok(progressed) -> #(
              progressed.log,
              [
                objective.SendProgress(
                  quest_id: quest.id,
                  objective_index: one.objective_index,
                  progress: progressed.progress,
                ),
                ..progress
              ],
              became_achieved || progressed.became_achieved,
            )
            Error(Nil) -> pass
          }
      }
    })
  let state = case became_achieved {
    True -> objective.achieved(tables:, quest_id: quest.id)
    False -> []
  }
  Advanced(
    log:,
    effects: list.flatten([so_far.effects, list.reverse(progress), state]),
  )
}

/// Whether the advance goes on to the quest's objective: it exists, is no checklist and is not
/// one the cast's own event counts.
fn takes_the_advance(
  tables tables: table_store.Tables,
  quest quest: quest_log.Quest,
  one one: Advance,
  with with: Option(objective.Event),
) -> Bool {
  case list.drop(quest.objectives, one.objective_index), one.objective_index {
    [objective, ..], index if index >= 0 ->
      !objective.checklist
      && case with {
        Some(event) ->
          !objective.counts(
            tables:,
            event:,
            quest_id: quest.id,
            index:,
            objective:,
          )
        None -> True
      }
    _, _ -> False
  }
}
