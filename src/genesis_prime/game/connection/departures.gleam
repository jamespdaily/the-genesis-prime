//// The start of a departures terminal's move on the game connection
//// (genesis_prime/game/departures): the 0 ms timer the terminal's `Activated` started
//// fires after the cast's frames (0x7fe, 0x361) are carried out, and the player leaves
//// the tutorial map and joins the landing's, as the Holocrypt's leave and join do
//// (`connection/life.leaving_for_the_holocrypt`, `connection/world.joining_at`).
////
//// ```
//// timer ─▶ due ─ in the world, alive, departing = Some(place)
////                  ─▶ world_left; map run: Leave(connection)   (LeavingMap, JoinAt(place, health))
////           Left ─▶ the map's watch dropped; the landing's map: Join(.., health)
////           Joined ─▶ 0xad, 0x262, .. 0x61, with no 0x25e and no 0x35f (`InWorldEntry`)
////      └ otherwise ─▶ nothing
//// ```
////
//// - **The player is kept as it is**: `JoinAt` carries the player's saved health
////   (`player_life.saved_health`), where the Holocrypt's join gives a full one, and the quest
////   log, vendor buyback, items and currencies come with the earlier stay's `Entered`
////   (`world_entry.rejoining`).
//// - **A timer that finds no departure does nothing** (the failure table of
////   genesis_prime/game/departures): the player has camped or left the world, is dead, or
////   `departing` was cleared; the timer is dropped with no leave and no join.
//// - **The statuses that hold the shell** (a vendor purchase, a save) keep the timer waiting:
////   `due` acts only on `InWorld`.

import genesis_prime/client_connection
import genesis_prime/game/connection/state.{type Session}
import genesis_prime/step.{type Now}

/// The departure timer fired: the leave of the tutorial map begins when the player is in
/// the world, alive, with a landing kept in `Entered.departing`, and the landing is cleared
/// either way.
pub fn due(
  session _session: Session,
  now _now: Now,
) -> client_connection.Handled(Session) {
  panic as "shape: departures.due starts world_left and leaving_the_map with JoinAt(place, health)"
}
