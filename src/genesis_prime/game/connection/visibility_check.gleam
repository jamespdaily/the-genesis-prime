//// The end-of-step check of the visibility prerequisites that fail for the
//// connection's player (genesis_prime/game/visibility): after a step that may have
//// changed the quest log, a cast on the player or its faction, or the items the player
//// holds (a type 13, 14 or 246 condition reads them), the hidden set is
//// worked out again from the cast rule's subject (`cast.subject_of`), and a set
//// that differs from the one the entered player holds (`Entered.hidden`) is kept
//// there and told to the map once (`TellVisibilityChanged`, the map's
//// `VisibilityChanged`). A step that leaves the set as it was tells nothing. A move
//// is checked as well as the steps that change the log, a cast or the faction: a
//// move can change the zone the player stands in, and a type 26 condition reads the
//// zones. A step that ends the connection (`Done`) is not checked: no map is left to
//// tell.
////
//// ```
//// a step's Handled(session) ─▶ rechecked ─▶ hidden(world's prerequisites, subject)
////                                           same as Entered.hidden: the Handled as it was
////                                           different: Entered.hidden kept,
////                                                      Tell(map, TellVisibilityChanged(c, hidden))
//// ```

import genesis_prime/client_connection.{Continue, Done}
import genesis_prime/game/cast
import genesis_prime/game/connection/casting as connection_casting
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/visibility
import genesis_prime/game/world_entry
import genesis_prime/step
import gleam/bool
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result

/// The step's outcome with the hidden set checked: unchanged when the set is
/// the one held, else with the new set kept in the session and one tell of it to
/// the player's map. A step that asks (`Asking`) or ends the connection (`Done`), or of
/// a connection with no player in the world, is as it was: the next input checks it.
pub fn rechecked(
  handled handled: client_connection.Handled(Session),
) -> client_connection.Handled(Session) {
  case handled {
    Continue(session:, effects:) ->
      case checked(session:) {
        Some(#(session, tell)) ->
          Continue(session, list.append(effects, [tell]))
        None -> handled
      }
    Done(..) | client_connection.Asking(..) -> handled
  }
}

/// The session with the new hidden set kept and the tell of it to the map, when the
/// set the player's subject gives differs from the one held.
fn checked(
  session session: Session,
) -> option.Option(
  #(Session, step.Effect(step.ConnectionEffect(client_connection.Request))),
) {
  use #(_, entered) <- option.then(connection_state.held_in_the_world(
    session.status,
  ))
  let prerequisites =
    dict.get(session.settings.visibility, entered.map.world_id)
    |> result.unwrap([])
  use <- bool.guard(when: prerequisites == [], return: None)
  let hidden =
    visibility.hidden(
      prerequisites:,
      subject: cast.subject_of(
        cast: entered.cast,
        caster: connection_casting.caster_of(
          tables: session.settings.tables,
          entered:,
        ),
      ),
    )
  use <- bool.guard(when: hidden == entered.hidden, return: None)
  Some(#(
    connection_state.with_entered(session:, change: fn(held) {
      world_entry.Entered(..held, hidden:)
    }),
    connection_state.tells_the_map(
      entered:,
      request: client_connection.TellVisibilityChanged(
        connection: client_connection.connection(session.link),
        hidden:,
      ),
    ),
  ))
}
