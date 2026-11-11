//// A talk to a creature, a use of one or a kill of one on the game connection
//// (genesis_prime/game/objective): the rule decides, and this keeps the quest log it
//// returns, tells the client each objective's progress (0x0361) and a quest's state
//// (0x035C) in the rule's order, and moves the quest deadline timer when the log's
//// earliest deadline moved, since a quest that is achieved no longer runs out
//// (genesis_prime/game/quest_log `next_deadline`, `deadline_moved`).

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/prerequisite_player
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/experience
import genesis_prime/game/movement
import genesis_prime/game/objective
import genesis_prime/game/quest_log
import genesis_prime/game/target_group
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/table/creature2
import gleam/list
import gleam/option.{None, Some}

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

/// The session and what is written after the player did this to a creature, and then
/// after what that opened is counted as well (`settled`). A connection with no player
/// in the world counts nothing.
pub fn counted(
  session session: Session,
  now now: Now,
  event event: objective.Event,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) -> {
      let tables = session.settings.tables
      let advanced =
        objective.advance(
          log: entered.quests,
          tables:,
          event:,
          now_ms: now.monotonic_ms,
        )
      let settled = settle(session:, entered:, log: advanced.log, now:)
      told(
        session:,
        now:,
        before: entered.quests,
        advanced: objective.Advanced(
          log: settled.log,
          effects: list.append(advanced.effects, settled.effects),
        ),
      )
    }
  }
}

/// The session and what is written after what the player holds or the zone they stand
/// in changed: a pickup, a drop, a purchase, a sale, a move out of the counted
/// locations, a quest taken or a zone entered (`objective.settle`). A connection with no
/// player in the world counts nothing.
pub fn settled(
  session session: Session,
  now now: Now,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) ->
      told(
        session:,
        now:,
        before: entered.quests,
        advanced: settle(session:, entered:, log: entered.quests, now:),
      )
  }
}

/// `objective.settle` for the items the player holds and the zones they stand in.
fn settle(
  session session: Session,
  entered entered: world_entry.Entered,
  log log: quest_log.QuestLog,
  now now: Now,
) -> objective.Advanced {
  let tables = session.settings.tables
  objective.settle(
    log:,
    tables:,
    items: entered.items,
    zones: prerequisite_player.of(tables:, entered:).zones,
    place: movement.place(state: entered.movement),
    shown: entered.shown,
    numbers: session.settings.numbers,
    unix_ms: step.unix_milliseconds(now:),
    now_ms: now.monotonic_ms,
  )
}

/// The session keeping the log the rule returned and what is written for it: its
/// messages in the rule's order, then the quest deadline timer's move when the log's
/// earliest deadline moved.
fn told(
  session session: Session,
  now now: Now,
  before before: quest_log.QuestLog,
  advanced advanced: objective.Advanced,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
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
      list.map(
        quest_log.deadline_moved(
          before: quest_log.next_deadline(log: before),
          after: quest_log.next_deadline(log: advanced.log),
          now_ms: now.monotonic_ms,
        ),
        connection_state.quest_deadline_timer_move,
      ),
    ),
  )
}
