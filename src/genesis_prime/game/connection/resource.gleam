//// The player's class resource on the game connection
//// (genesis_prime/game/connection): its rule (genesis_prime/game/class_resource)
//// is kept in the player's `Entered` beside its life, and this module turns what
//// reaches the connection into the rule's inputs and carries out its effects.
////
//// ```
//// the cast rule's Pay (an accepted press)          ─▶ class_resource.pay
//// a timer class_resource.owns                     ─▶ class_resource.timer_fired
//// player_life's step: alive ─▶ dead                ─▶ class_resource.died
////                     dead ─▶ alive                ─▶ class_resource.came_back
////                     the combat flag set or clear ─▶ class_resource.combat_changed
//// the stay left (camp, Holocrypt)                 ─▶ class_resource.left
//// Changed(slot, value) ─▶ 0x935 to the player's own client only (the server's
//// choice: a viewer's client shows no other unit's class resource)
//// StartTimer, CancelTimer ─▶ the connection's own timers, as the cast rule's are
//// ```

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/game/class_resource
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/player_life.{type Life}
import genesis_prime/game/world_entry
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type TimerId, CancelTimer, OwnEffect,
  StartTimer,
}
import gleam/list
import gleam/option.{None, Some}

/// The session with the player's resources changed by the rule's step `change`,
/// and the connection's effects for what the step decided. With no player in the
/// world nothing changes.
fn stepped(
  session session: Session,
  change change: fn(class_resource.Resources) ->
    #(class_resource.Resources, List(class_resource.Effect)),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) -> {
      let #(resources, effects) = change(entered.resources)
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, resources:)
        })
      #(session, carried(session:, entered:, effects:))
    }
  }
}

/// The rule's effects as the connection's: a change as 0x935 of the player's own
/// unit to its own client, and its timers.
fn carried(
  session session: Session,
  entered entered: world_entry.Entered,
  effects effects: List(class_resource.Effect),
) -> List(Effect(ConnectionEffect(Request))) {
  list.map(effects, fn(effect) {
    case effect {
      class_resource.Changed(slot:, value:) ->
        connection_state.to_client(
          session,
          connection_frames.resource_frame(
            unit_id: entered.unit_id,
            slot:,
            value:,
          ),
        )
      class_resource.StartTimer(timer:, after_ms:) ->
        OwnEffect(StartTimer(timer:, after_ms:))
      class_resource.CancelTimer(timer:) -> OwnEffect(CancelTimer(timer:))
    }
  })
}

/// The costs an accepted press pays (genesis_prime/game/cast `Pay`).
pub fn paid(
  session session: Session,
  payments payments: List(class_resource.Payment),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  stepped(session:, change: class_resource.pay(resources: _, payments:))
}

/// A timer of the rule fired. With no player in the world to take it, it is
/// dropped.
pub fn resource_due(
  session session: Session,
  timer timer: TimerId,
) -> client_connection.Handled(Session) {
  let #(session, effects) =
    stepped(session:, change: class_resource.timer_fired(resources: _, timer:))
  Continue(session, effects)
}

/// What a step of the player's life did to the resource, from the life before it
/// to the life the session holds now: a death, a coming back, or the combat flag
/// set or cleared.
pub fn life_changed(
  session session: Session,
  before before: Life,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.entered_of(session.status) {
    None -> #(session, [])
    Some(entered) -> {
      let after = entered.life
      case player_life.state(life: before), player_life.state(life: after) {
        player_life.Alive, player_life.Dead ->
          stepped(session:, change: fn(resources) {
            class_resource.died(resources:)
          })
        player_life.Dead, player_life.Alive ->
          stepped(session:, change: fn(resources) {
            class_resource.came_back(resources:)
          })
        player_life.Alive, player_life.Alive
        | player_life.Dead, player_life.Dead
        ->
          case
            player_life.in_combat(life: before)
            == player_life.in_combat(life: after)
          {
            True -> #(session, [])
            False ->
              stepped(session:, change: class_resource.combat_changed(
                resources: _,
                in_combat: player_life.in_combat(life: after),
              ))
          }
      }
    }
  }
}

/// The player leaves its stay in the world: the rule's timers are cancelled.
pub fn left(
  session session: Session,
  entered entered: world_entry.Entered,
) -> List(Effect(ConnectionEffect(Request))) {
  carried(
    session:,
    entered:,
    effects: class_resource.left(resources: entered.resources).1,
  )
}
