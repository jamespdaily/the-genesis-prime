//// The ability builder's save on the game connection (genesis_prime/game/limited_action_set):
//// the rule judges the client's 0xB1 against the player's level, book, life and combat, and
//// this writes the frames it answers with, in order, and keeps the bar it leaves in
//// `Entered`, which the next place save carries to the store and a map or Holocrypt rejoin
//// sends again. Nothing waits on the store. A body the client's reader refuses ends the
//// connection with the sentence the rule gives.

import genesis_prime/client_connection.{Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/ability_book
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/limited_action_set
import genesis_prime/game/player_life
import genesis_prime/game/world_entry
import genesis_prime/step.{type Now}

/// What the 0xB1 taken from inside 0x038C with the player in the world does.
pub fn take_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let level = entered.character.level
  let player =
    limited_action_set.Player(
      level:,
      book: ability_book.book(
        tables: session.settings.tables,
        loadout: entered.loadout,
        level:,
      ),
      dead: player_life.state(life: entered.life) == player_life.Dead,
      in_combat: player_life.in_combat(life: entered.life),
    )
  case
    limited_action_set.take(
      unlocks: limited_action_set.unlocks(tables: session.settings.tables),
      player:,
      saved: entered.action_sets,
      class_bar: entered.loadout.abilities,
      body: inner.body,
    )
  {
    Ok(#(saved, effects)) ->
      Continue(
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, action_sets: saved)
        }),
        connection_state.told_effects(session:, effects:, told: fn(effect) {
          case effect {
            limited_action_set.Send(frame:) -> connection_state.Sent(frame:)
            limited_action_set.Log(level:, text:) ->
              connection_state.Logged(level:, text:)
          }
        }),
      )
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: limited_action_set.describe(refusal:),
      )
  }
}
