//// The player's accept of a quest and retry of a botched one on the game connection
//// (genesis_prime/game/quest): the rule decides, and this carries out its effects in
//// order, a log line or the 0x035C that tells the client the quest's new state, and
//// keeps the log the rule returns, which the next save writes. A body the client's own
//// reader would refuse ends the connection with the sentence the rule gives.

import genesis_prime/client_connection.{Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/prerequisite_player
import genesis_prime/game/connection/state.{type Session, Session} as connection_state
import genesis_prime/game/interaction
import genesis_prime/game/movement
import genesis_prime/game/prerequisite.{Factions}
import genesis_prime/game/quest
import genesis_prime/game/shown
import genesis_prime/game/world_entry
import genesis_prime/step.{type Now}
import gleam/list

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
      asker: quest.Asker(
        player: prerequisite_player.of(tables:, entered:),
        factions: Factions(
          current: entered.unit.tail.faction_id,
          base: entered.unit.tail.base_faction_id,
        ),
        log: entered.quests,
        items: entered.items,
      ),
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
      )
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: quest.describe_refusal(refusal:),
      )
  }
}
