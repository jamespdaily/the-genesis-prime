//// A talk to a creature or a use of one on the game connection
//// (genesis_prime/game/objective): the rule decides, and this keeps the quest log it
//// returns, tells the client each objective's progress (0x0361) and a quest's state
//// (0x035C) in the rule's order, and moves the quest deadline timer when the log's
//// earliest deadline moved, since a quest that is achieved no longer runs out
//// (genesis_prime/game/quest_log `next_deadline`). It cannot use
//// genesis_prime/game/connection/effects, which imports the casting this is called from,
//// so the timer is moved here as that module moves it.

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/objective
import genesis_prime/game/quest_log
import genesis_prime/game/world_entry
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, CancelTimer, OwnEffect,
  StartTimer,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

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
              objective.SendState(quest_id:, state:) ->
                connection_frames.quest_state_frame(
                  quest_id:,
                  state:,
                  objective_id: 0,
                )
            })
          }),
          deadline_timer_moved(
            before: quest_log.next_deadline(log: entered.quests),
            after: quest_log.next_deadline(log: advanced.log),
            now_ms: now.monotonic_ms,
          ),
        ),
      )
    }
  }
}

/// What the quest deadline timer needs when the earliest deadline goes from `before`,
/// the one the running timer is set for, to `after`: nothing when it did not move, the
/// timer started or restarted for the new deadline, or only cancelled when none is left.
fn deadline_timer_moved(
  before before: Option(Int),
  after after: Option(Int),
  now_ms now_ms: Int,
) -> List(Effect(ConnectionEffect(Request))) {
  let cancel =
    OwnEffect(CancelTimer(timer: connection_state.quest_deadline_timer))
  let start = fn(deadline_ms) {
    OwnEffect(StartTimer(
      timer: connection_state.quest_deadline_timer,
      after_ms: int.max(0, deadline_ms - now_ms),
    ))
  }
  case before, after {
    None, None -> []
    None, Some(deadline_ms) -> [start(deadline_ms)]
    Some(_), None -> [cancel]
    Some(was), Some(deadline_ms) if was == deadline_ms -> []
    Some(_), Some(deadline_ms) -> [cancel, start(deadline_ms)]
  }
}
