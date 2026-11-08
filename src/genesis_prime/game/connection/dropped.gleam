//// The reports and requests the game connection takes and drops
//// (genesis_prime/game/dropped): the rule's feature checks the body, and the
//// connection goes on with no log line and nothing written. A refusal ends the
//// connection with the sentence the feature gives.

import genesis_prime/client_connection.{Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/dropped
import genesis_prime/step.{type Now}

/// What a dropped message does, taken from inside 0x038C or, for 0x0241, on its
/// own: the connection goes on unchanged, and a body or value the client never
/// sends ends it.
pub fn dropped_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
  message message: dropped.Message,
) -> client_connection.Handled(Session) {
  case
    dropped.take(message:, body: inner.body, tables: session.settings.tables)
  {
    Ok(Nil) -> Continue(session, [])
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: dropped.describe(refusal:))
  }
}
