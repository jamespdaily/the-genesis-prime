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
////      └ fired in a wait whose answer returns the player to the world (a purchase, a sale,
////        a save of the place, a claim made again) ─▶ held by the connection and taken here
////        once the answer is in (`connection.timer_fired`)
////      └ fired while the player leaves, camps or waits to claim, with a landing kept
////        ─▶ the timer again after `retry_ms`
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
//// - **A connection that holds the player but is not standing in the world, in a wait that
////   does not return it there** (the leave or camp's save, the leave of the map, the wait
////   for the account's claim) starts the timer again after `retry_ms`, while a landing is
////   kept; `due` leaves only for a player in the world. A wait that does return it (a
////   vendor purchase or sale, an item move, a summon, a quest turn-in, the place's save,
////   the claim made again) holds the firing instead, and `due` takes it once the answer
////   has returned the player.

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/game/connection/effects as connection_effects
import genesis_prime/game/connection/state.{
  type Session, Busy, Greeting, JoinAt, Present, Selecting,
} as connection_state
import genesis_prime/game/connection/world as connection_world
import genesis_prime/game/departures
import genesis_prime/game/player_life
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type Now, OwnEffect, StartTimer,
}
import gleam/option.{None, Some}

/// The departure timer fired: the leave of the tutorial map begins when the player is in
/// the world, alive, with a landing kept in `Entered.departing`, and the landing is cleared
/// either way. A connection that holds the player but is leaving the map, camping or waiting
/// to claim its account, with a landing kept, starts the timer again instead (the other
/// waits hold the firing before it comes here).
pub fn due(
  session session: Session,
  now now: Now,
) -> client_connection.Handled(Session) {
  case connection_state.standing(session.status) {
    Present(holder:, entered:) -> leaving(session:, now:, holder:, entered:)
    Busy(..) -> Continue(session, again(session:))
    Greeting | Selecting(..) -> Continue(session, [])
  }
}

/// How long the timer waits before it asks again while the connection leaves, camps or
/// waits to claim.
const retry_ms = 100

/// The timer started again for a connection that holds a player with a landing kept and does
/// not stand in the world, and nothing for one that holds none.
fn again(session session: Session) -> List(Effect(ConnectionEffect(Request))) {
  case connection_state.entered_of(session.status) {
    Some(world_entry.Entered(departing: Some(_), ..)) -> [
      OwnEffect(StartTimer(timer: departures.timer, after_ms: retry_ms)),
    ]
    Some(_) | None -> []
  }
}

/// The leave of the tutorial map for a player in the world, or nothing for a player that
/// is dead or has no landing kept.
fn leaving(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
) -> client_connection.Handled(Session) {
  let cleared = world_entry.Entered(..entered, departing: None)
  let session =
    connection_state.with_entered(session:, change: fn(_) { cleared })
  case entered.departing, player_life.state(life: entered.life) {
    None, _ | _, player_life.Dead -> Continue(session, [])
    Some(place), player_life.Alive -> {
      let #(session, left_behind) =
        connection_effects.world_left(session:, now:, entered: cleared)
      connection_world.leaving_the_map(
        session:,
        now:,
        holder:,
        entered: cleared,
        before: left_behind,
        then: JoinAt(
          place:,
          health: Some(player_life.saved_health(life: entered.life)),
        ),
      )
    }
  }
}
