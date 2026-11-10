//// The player's accept of a quest, retry of a botched one, abandon, mention, track and
//// ignore on the game connection (genesis_prime/game/quest): the rule decides, and this
//// carries out its effects in order, a log line or the 0x035C that tells the client the
//// quest's new state, and keeps the log the rule returns, which the next save writes. A
//// body the client's own reader would refuse ends the connection with the sentence the
//// rule gives.

import genesis_prime/client_connection.{Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/prerequisite_player
import genesis_prime/game/connection/state.{type Session, Session} as connection_state
import genesis_prime/game/interaction
import genesis_prime/game/movement
import genesis_prime/game/prerequisite.{Factions}
import genesis_prime/game/quest
import genesis_prime/game/quest_log
import genesis_prime/game/shown
import genesis_prime/game/world_entry
import genesis_prime/step.{type Now, CancelTimer, OwnEffect, StartTimer}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// What the quest checks read of the player in the world.
pub fn asker(
  session session: Session,
  entered entered: world_entry.Entered,
) -> quest.Asker {
  quest.Asker(
    player: prerequisite_player.of(tables: session.settings.tables, entered:),
    factions: Factions(
      current: entered.unit.tail.faction_id,
      base: entered.unit.tail.base_faction_id,
    ),
    log: entered.quests,
    items: entered.items,
  )
}

/// What the quest deadline timer needs when the earliest deadline of the log goes from
/// `before` to `after` (milliseconds on the monotonic clock): nothing when it did not
/// move, the timer started when none ran, and the running one cancelled and started
/// again for the new deadline, or only cancelled when none is left.
fn deadline_timer_moved(
  before before: Option(Int),
  after after: Option(Int),
  now_ms now_ms: Int,
) -> List(step.Effect(step.ConnectionEffect(client_connection.Request))) {
  let start = fn(deadline_ms) {
    OwnEffect(StartTimer(
      timer: connection_state.quest_deadline_timer,
      after_ms: int.max(0, deadline_ms - now_ms),
    ))
  }
  let cancel =
    OwnEffect(CancelTimer(timer: connection_state.quest_deadline_timer))
  case before, after {
    _, _ if before == after -> []
    None, Some(deadline_ms) -> [start(deadline_ms)]
    Some(_), Some(deadline_ms) -> [cancel, start(deadline_ms)]
    Some(_), None -> [cancel]
    None, None -> []
  }
}

/// What a message of the quest feature does, taken from inside 0x038C with the player
/// in the world.
pub fn quest_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: quest.Message,
) -> client_connection.Handled(Session) {
  let assert Ok(faction) = shown.faction_of(entered.unit.tail.faction_id)
    as "a character's faction is Exile or Dominion (start_place)"
  let tables = session.settings.tables
  case
    quest.take(
      message:,
      body: inner.body,
      asker: asker(session:, entered:),
      standing: interaction.Player(
        race_id: entered.character.race_id,
        faction:,
        place: movement.place(state: entered.movement),
      ),
      picture: entered.shown,
      tables:,
      now_ms: now.monotonic_ms,
      logged: session.interaction_logged,
    )
  {
    Ok(taken) ->
      Continue(
        connection_state.with_entered(
          session: Session(..session, interaction_logged: taken.logged),
          change: fn(entered) {
            world_entry.Entered(..entered, quests: taken.log)
          },
        ),
        list.append(
          list.map(taken.effects, fn(effect) {
            case effect {
              quest.Log(level:, text:) ->
                connection_state.log(session:, level:, text:)
              quest.SendState(quest_id:, state:, objective_id:) ->
                connection_state.to_client(
                  session,
                  connection_frames.quest_state_frame(
                    quest_id:,
                    state:,
                    objective_id:,
                  ),
                )
            }
          }),
          deadline_timer_moved(
            before: quest_log.next_deadline(log: entered.quests),
            after: quest_log.next_deadline(log: taken.log),
            now_ms: now.monotonic_ms,
          ),
        ),
      )
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: quest.describe_refusal(refusal:),
      )
  }
}
