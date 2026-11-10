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
import genesis_prime/game/target_group
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/table/creature2
import gleam/list
import gleam/option.{None, Some}

/// The state number of an Achieved quest in 0x035C (`opcode.0x35c`).
const achieved_state = 2

/// The session and what is written after the player's blow killed the creature of
/// the credit. The unit is the creature as the credit names it: its Creature2 row, the
/// Faction2 its spawn gave it (which a type 3 TargetGroup tests) and the race of its row.
pub fn killed(
  session session: Session,
  now now: Now,
  credit credit: experience.Credit,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let assert Ok(row) =
    creature2.get(tables: session.settings.tables, id: credit.creature_id)
    as "the kill's creature row was read by the experience rule a moment ago"
  counted(
    session:,
    now:,
    event: objective.Killed(target_group.Unit(
      creature_id: credit.creature_id,
      faction_id: credit.faction_id,
      unit_race_id: creature2.unit_race_id(row),
    )),
  )
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
