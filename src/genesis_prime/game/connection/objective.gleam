//// A talk to a creature or a use of one on the game connection
//// (genesis_prime/game/objective): the rule decides, and this keeps the quest log it
//// returns, tells the client each objective's progress (0x0361) and a quest's state
//// (0x035C) in the rule's order, and moves the quest deadline timer when the log's
//// earliest deadline moved, since a quest that is achieved no longer runs out
//// (genesis_prime/game/quest_log `next_deadline`, `deadline_moved`).

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/objective
import genesis_prime/game/quest_log
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import gleam/list
import gleam/option.{None, Some}

/// The state number of an Achieved quest in 0x035C (`opcode.0x35c`).
const achieved_state = 2

/// The session and what is written after the player did this to a creature. A
/// connection with no player in the world counts nothing.
pub fn counted(
  session session: Session,
  now now: Now,
  event event: objective.Event,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) -> {
      let advanced =
        objective.advance(
          log: entered.quests,
          tables: session.settings.tables,
          event:,
        )
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, quests: advanced.log)
        })
      #(
        session,
        list.append(
          list.map(advanced.effects, fn(effect) {
            connection_state.to_client(session, case effect {
              objective.SendProgress(quest_id:, objective_index:, progress:) ->
                connection_frames.quest_objective_progress_frame(
                  quest_id:,
                  objective_index:,
                  progress:,
                )
              objective.SendAchieved(quest_id:) ->
                connection_frames.quest_state_frame(
                  quest_id:,
                  state: achieved_state,
                  objective_id: 0,
                )
            })
          }),
          list.map(
            quest_log.deadline_moved(
              before: quest_log.next_deadline(log: entered.quests),
              after: quest_log.next_deadline(log: advanced.log),
              now_ms: now.monotonic_ms,
            ),
            connection_state.quest_deadline_timer_move,
          ),
        ),
      )
    }
  }
}
