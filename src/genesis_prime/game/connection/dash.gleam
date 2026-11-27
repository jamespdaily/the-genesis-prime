//// The player's dash on the game connection (genesis_prime/game/dash): the rule decides, and
//// this pays the dash from the dash energy through the connection's resource step, which
//// writes 0x935 of stat 9 to the player's own client only, or drops the dash with a log
//// line and writes the true energy again, or ends the connection with the sentence the
//// rule gives. The client moves itself and reports the move in 0x637, so no viewer is
//// told here.

import genesis_prime/client_connection.{Continue}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/resource as connection_resource
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/dash
import genesis_prime/game/player_life
import genesis_prime/game/world_entry
import genesis_prime/shared/class_resource
import genesis_prime/step.{type Now, LogWarning}

/// What the 0x015C taken from inside 0x038C with the player in the world does.
pub fn take_message(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case
    dash.take(
      dashes: dash.dashes(tables: session.settings.tables),
      life: player_life.state(life: entered.life),
      resources: entered.resources,
      body: inner.body,
    )
  {
    Ok(dash.Pays(payments:)) -> {
      let #(session, written) = connection_resource.paid(session:, payments:)
      Continue(session, written)
    }
    Ok(dash.Dropped(reason:)) ->
      Continue(session, [
        connection_state.log(
          session:,
          level: LogWarning,
          text: dash.describe_dropped(reason:),
        ),
        connection_state.to_client(
          session,
          connection_frames.resource_frame(
            unit_id: entered.unit_id,
            slot: class_resource.dash_slot,
            value: class_resource.value(
              resources: entered.resources,
              slot: class_resource.dash_slot,
            ),
          ),
        ),
      ])
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: dash.describe(refusal:))
  }
}
