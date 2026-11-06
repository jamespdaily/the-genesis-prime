//// The player's movement on the game connection (genesis_prime/game/connection):
//// 0x637 of the body and of the ghost and the other movement messages taken
//// from inside 0x038C, the tells to the map and to the creatures that fight the
//// player, and the move sent to the players who see it.
////
//// - **A refused message** (a command the client's own code never sends, a move
////   speed setting above 2, or a body the client's reader would refuse) ends the
////   connection: an error line, the last good place saved, nothing written.

import genesis_prime/client_connection.{
  type Request, Continue, TellMoved, TellPeer,
}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/chat
import genesis_prime/game/connection/chat as connection_chat
import genesis_prime/game/connection/state.{type Session, InWorld, Session} as connection_state
import genesis_prime/game/movement
import genesis_prime/game/player_life
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/top_zone
import genesis_prime/game/world_entry
import genesis_prime/hand_off.{type Holder}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/step.{
  type ConnectionEffect, type ConnectionId, type Effect, type Now, LogInfo,
  OwnEffect,
}
import genesis_prime/world_map/map
import gleam/dict
import gleam/int
import gleam/list
import gleam/set

/// What the player's movement messages do, taken from inside 0x038C, in the
/// world (genesis_prime/game/movement): the movement keeps the place or
/// refuses, and a refusal ends the connection.
pub fn movement_message(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: movement.Message,
) -> client_connection.Handled(Session) {
  case message, player_life.state(life: entered.life), entered.readiness {
    movement.PlayerMoved, player_life.Dead, _
    | movement.PlayerMoved, player_life.Alive, world_entry.GhostLoading
    -> ghost_moving(session:, now:, entered:, body: inner.body)
    movement.PlayerMoved, player_life.Alive, world_entry.ClientLoading
    | movement.PlayerMoved, player_life.Alive, world_entry.ClientReady
    | movement.ZoneChanged, _, _
    | movement.IntervalAnswered, _, _
    | movement.SpeedChosen, _, _
    | movement.TerrainReady, _, _
    | movement.Fell, _, _
    | movement.FellBelowFloor, _, _
    -> body_moving(session:, now:, holder:, entered:, inner:, message:)
  }
}

/// A movement message of the player's body, taken by the movement rule.
fn body_moving(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  inner inner: Frame,
  message message: movement.Message,
) -> client_connection.Handled(Session) {
  case movement.take(entered.movement, message, inner.body) {
    Ok(movement.Kept(state:)) ->
      Continue(moving(session:, holder:, entered:, state:), [])
    Ok(movement.Reported(state:, world_zone_id:, by:)) -> {
      let session = moving(session:, holder:, entered:, state:)
      let top_zones = top_zone.top_zones(session.settings.tables)
      let #(session, ready) = case by, entered.readiness {
        movement.ReportedByTerrainReady, world_entry.ClientLoading
        | movement.ReportedByTerrainReady, world_entry.GhostLoading
        -> tells_the_map_ready(session:, entered:)
        movement.ReportedByTerrainReady, world_entry.ClientReady
        | movement.ReportedByZoneChanged, _
        -> #(session, [])
      }
      let #(updated, effects) = case by {
        movement.ReportedByTerrainReady ->
          chat.terrain_ready(chat: entered.chat, world_zone_id:, top_zones:)
        movement.ReportedByZoneChanged ->
          chat.world_zone_reported(
            chat: entered.chat,
            world_zone_id:,
            top_zones:,
          )
      }
      let #(session, written) =
        connection_chat.chat_effects(
          session: connection_chat.with_chat(session:, chat: updated),
          effects:,
        )
      Continue(session, list.append(ready, written))
    }
    Ok(movement.Relayed(state:, place:, commands:, unrelayed:)) -> {
      let new_kinds =
        list.filter(unrelayed, fn(kind) {
          !set.contains(session.unrelayed_logged, kind)
        })
      let move_seq = case commands {
        [] -> session.move_seq
        [_, ..] -> session.move_seq + 1
      }
      let session =
        Session(
          ..moving(session:, holder:, entered:, state:),
          move_seq:,
          unrelayed_logged: list.fold(
            new_kinds,
            session.unrelayed_logged,
            set.insert,
          ),
        )
      let connection = client_connection.connection(session.link)
      Continue(
        session,
        list.flatten([
          list.map(new_kinds, fn(kind) {
            connection_state.log(
              session:,
              level: LogInfo,
              text: "kind "
                <> int.to_string(kind)
                <> " of 0x0637 is not relayed to the players who see this one",
            )
          }),
          case commands {
            [] -> []
            [_, ..] ->
              list.flatten([
                [
                  // The player's connection, the place the movement now keeps and the
                  // move's sequence number, for the map to decide who sees whom and
                  // whose ring the player stands in.
                  connection_state.tells_the_map(
                    entered:,
                    request: TellMoved(connection:, place:, seq: move_seq),
                  ),
                ],
                sends_the_move_to_the_viewers(entered:, now:, commands:),
                list.map(player_life.fighters(life: entered.life), fn(fighter) {
                  tells_a_fighter_the_place(
                    connection:,
                    entered:,
                    fighter:,
                    place:,
                    seq: move_seq,
                  )
                }),
              ])
          },
        ]),
      )
    }
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: movement.describe(refusal))
  }
}

/// A 0x637 while the player is dead moves its ghost, the client's controlled
/// unit: it is decoded, checked as the body's and dropped (`movement.ghost_moved`),
/// so the body's place, the map, the viewers and the fighters are told nothing and
/// the move sequence number does not grow. A body the client's reader refuses, or
/// a command its code never sends, ends the connection.
fn ghost_moving(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  body body: BitArray,
) -> client_connection.Handled(Session) {
  case movement.ghost_moved(state: entered.movement, body:) {
    Ok(Nil) -> Continue(session, [])
    Error(refusal) ->
      connection_state.end_for(session:, now:, text: movement.describe(refusal))
  }
}

/// The session with the player's movement replaced.
fn moving(
  session session: Session,
  holder holder: Holder,
  entered entered: world_entry.Entered,
  state state: movement.State,
) -> Session {
  Session(
    ..session,
    status: InWorld(
      holder:,
      entered: world_entry.Entered(..entered, movement: state),
    ),
  )
}

/// The tell to a creature that holds the player on its threat list of the place the
/// player stands at and the move's sequence number, through the creature registry
/// with no watch.
pub fn tells_a_fighter_the_place(
  connection connection: ConnectionId,
  entered entered: world_entry.Entered,
  fighter fighter: #(Int, Int),
  place place: Place,
  seq seq: Int,
) -> Effect(ConnectionEffect(Request)) {
  OwnEffect(step.Tell(
    to: step.Creature(
      map: entered.map,
      incarnation: entered.incarnation,
      unit_id: fighter.0,
      life: fighter.1,
    ),
    request: client_connection.TellTargetMoved(
      connection:,
      place:,
      seq:,
      stay: entered.stay,
    ),
  ))
}

/// The stay's first 0xF2: the player is ready, and its map is told `Ready`, so a
/// creature may fight it from now on.
fn tells_the_map_ready(
  session session: Session,
  entered entered: world_entry.Entered,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  #(
    connection_state.with_entered(session:, change: fn(entered) {
      world_entry.Entered(..entered, readiness: world_entry.ClientReady)
    }),
    [
      connection_state.tells_the_map(
        entered:,
        request: client_connection.TellReady(
          connection: client_connection.connection(session.link),
          seq: session.move_seq,
        ),
      ),
    ],
  )
}

/// The move sent to each connection that sees the player, as news of 0x638s of
/// at most 31 relayed commands each, in order, stamped with the map's clock at the
/// time of the input (`map.server_time`, from the origin `Joined` carried): a send
/// through the registry that the shell makes with no answer. None when no
/// player sees this one.
fn sends_the_move_to_the_viewers(
  entered entered: world_entry.Entered,
  now now: Now,
  commands commands: List(RelayedMovement),
) -> List(Effect(ConnectionEffect(Request))) {
  let server_time_ms =
    map.server_time(
      origin_ms: entered.clock_origin_ms,
      monotonic_ms: now.monotonic_ms,
    )
  let moves =
    client_connection.peer_moves(
      unit_id: entered.unit_id,
      server_time_ms:,
      commands:,
    )
  list.flat_map(dict.to_list(entered.viewers), fn(viewer) {
    list.map(moves, fn(news) {
      OwnEffect(step.Tell(
        to: step.Connection(viewer.0),
        request: TellPeer(stay: viewer.1, news:),
      ))
    })
  })
}
