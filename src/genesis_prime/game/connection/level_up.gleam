//// The client's request for the fanfare of a level on the game connection
//// (genesis_prime/game/level_up): the rule decides, and this starts the cast of the level's
//// tier of the Level Up spell from the player's own unit, written to the player and told to
//// its viewers as any cast of the cast rule is (genesis_prime/game/connection/casting), or
//// writes a debug line for a level with no fanfare. A refusal ends the connection with the
//// sentence the rule gives.

import genesis_prime/client_connection.{Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/connection/casting as connection_casting
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/level_up
import genesis_prime/game/world_entry
import genesis_prime/step.{type Now, LogDebug}

/// What the 0x07A5 taken from inside 0x038C with the player in the world does.
pub fn take_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case
    level_up.take(
      fanfares: connection_state.level_ups_of(session:),
      player_level: entered.character.level,
      body: inner.body,
    )
  {
    Ok(level_up.NoFanfare(level:)) ->
      Continue(session, [
        connection_state.log(
          session:,
          level: LogDebug,
          text: level_up.describe_no_fanfare(level:),
        ),
      ])
    Ok(level_up.Fanfare(spell:)) -> {
      let #(started, decided) =
        cast.level_up_started(
          cast: entered.cast,
          caster: connection_casting.caster_of(
            tables: session.settings.tables,
            entered:,
          ),
          spell:,
          now:,
        )
      let #(session, written) =
        connection_casting.cast_effects(
          session: connection_casting.with_cast(session:, cast: started),
          now:,
          effects: decided,
        )
      Continue(session, written)
    }
    Error(refusal) ->
      connection_state.end_for(
        session:,
        now:,
        text: level_up.describe(refusal:),
      )
  }
}
