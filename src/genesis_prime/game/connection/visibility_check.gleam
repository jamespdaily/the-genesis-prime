//// The end-of-step check of the visibility prerequisites that fail for the
//// connection's player (genesis_prime/game/visibility): after a step that may have
//// changed the quest log, a cast on the player or its faction, the hidden set is
//// worked out again from the cast rule's subject (`cast.subject_of`), and a set
//// that differs from the one the entered player holds (`Entered.hidden`) is kept
//// there and told to the map once (`TellVisibilityChanged`, the map's
//// `VisibilityChanged`). A step that leaves the set as it was, a move included, tells
//// nothing.
////
//// ```
//// a step's Handled(session) ─▶ rechecked ─▶ hidden(world's prerequisites, subject)
////                                           same as Entered.hidden: the Handled as it was
////                                           different: Entered.hidden kept,
////                                                      Tell(map, TellVisibilityChanged(c, hidden))
//// ```

import genesis_prime/client_connection
import genesis_prime/game/connection/state.{type Session}

/// The step's outcome with the hidden set checked: unchanged when the set is
/// the one held, else with the new set kept in the session and one tell of it to
/// the player's map.
pub fn rechecked(
  handled _handled: client_connection.Handled(Session),
) -> client_connection.Handled(Session) {
  panic as "shape: #601 the end-of-step check of the hidden set"
}
