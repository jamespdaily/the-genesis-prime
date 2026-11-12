//// The move of a player a tutorial projector's cast makes on the game connection
//// (genesis_prime/game/projector): at the cast's go the connection asks for the landing
//// the projector names for the player's faction, and a landing the link allows is written
//// as the client's placement (genesis_prime/game/in_world_move) and told to the player's map.
////
//// ```
//// cast's go ─▶ link read (before the count) ─▶ the use counted ─▶ moved
////   moved ─ landing ─▶ 0x83c, 0x639, 0x638, 0x636(echo); Tell(map, TellMoved(place, seq: echo))
////         └ no landing ─▶ nothing
//// ```
////
//// - **The echo is the next move number**: the 0x636 carries `move_seq + 1`, the map is told the
////   move with that number, and the connection keeps it, so a later move of the client's
////   own is numbered after it.
//// - **The link is read before the count** because the count can close the objective the
////   link opens, and the move is of the press that was offered.

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/activate.{type Link}
import genesis_prime/game/connection/state.{type Session, Session} as connection_state
import genesis_prime/game/in_world_move
import genesis_prime/game/projector
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import genesis_prime/table/id.{type Creature2Id}
import gleam/list
import gleam/option.{None, Some}

/// The session and what is written after the cast of the creature `creature_id` went, with
/// the link its objective had at the press (`link`): the player placed at the creature's
/// landing for the player's faction when the projector is offered, or the session as it is.
pub fn moved(
  session session: Session,
  now now: Now,
  creature_id creature_id: Creature2Id,
  link link: Link,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) ->
      case
        projector.landing(
          landings: session.settings.projector_landings,
          creature_id:,
          faction_id: entered.unit.tail.faction_id,
          link:,
        )
      {
        Error(projector.NotAProjector) | Error(projector.NotOffered(..)) -> #(
          session,
          [],
        )
        Ok(place) -> {
          let echo_value = session.move_seq + 1
          let #(placed, frames) =
            in_world_move.begin(entered:, place:, echo_value:, now:)
          let session =
            Session(
              ..connection_state.with_entered(session:, change: fn(_) { placed }),
              move_seq: echo_value,
            )
          let connection = client_connection.connection(session.link)
          #(
            session,
            list.append(
              list.map(frames, fn(inner) {
                connection_state.to_client(session:, inner:)
              }),
              [
                connection_state.tells_the_map(
                  entered: placed,
                  request: client_connection.TellMoved(
                    connection:,
                    place:,
                    seq: echo_value,
                  ),
                ),
              ],
            ),
          )
        }
      }
  }
}
