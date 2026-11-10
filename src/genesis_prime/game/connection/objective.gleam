//// A talk to a creature, a use of one or a kill of one on the game connection
//// (genesis_prime/game/objective): the rule decides, and this keeps the quest log it
//// returns, tells the client each objective's progress (0x0361) and a quest's state
//// (0x035C) in the rule's order, and moves the quest deadline timer when the log's
//// earliest deadline moved, since a quest that is achieved no longer runs out
//// (genesis_prime/game/quest_log `next_deadline`, `deadline_moved`).

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/experience
import genesis_prime/game/objective
import genesis_prime/game/quest_log
import genesis_prime/game/shown
import genesis_prime/game/target_group
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/table/creature2
import gleam/dict
import gleam/list
import gleam/option.{None, Some}

/// The state number of an Achieved quest in 0x035C (`opcode.0x35c`).
const achieved_state = 2

/// The session and what is written after the player's blow killed the creature of
/// the credit. The unit is what the client's picture holds of it: its faction (which a
/// type 3 TargetGroup tests) is known only while the creature is shown, and a creature
/// that has left the picture counts by its Creature2 id and race alone.
pub fn killed(
  session session: Session,
  now now: Now,
  credit credit: experience.Credit,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) -> {
      let #(creature_id, faction_id) = case
        dict.get(entered.shown, credit.unit_id)
      {
        Ok(shown.ShownCreature(creature_id:, faction_id:, ..)) -> #(
          creature_id,
          Some(faction_id),
        )
        Ok(shown.ShownPlayer) | Ok(shown.ShownObject(..)) | Error(Nil) -> #(
          credit.creature_id,
          None,
        )
      }
      // The experience rule has just read this creature's row.
      let assert Ok(row) =
        creature2.get(tables: session.settings.tables, id: creature_id)
      counted(
        session:,
        now:,
        event: objective.Killed(target_group.Unit(
          creature_id:,
          faction_id:,
          unit_race_id: creature2.unit_race_id(row),
        )),
      )
    }
  }
}

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
