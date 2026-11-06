//// The player's class resource on the game connection
//// (genesis_prime/game/connection): its rule (genesis_prime/game/class_resource)
//// is kept in the player's `Entered` beside its life, and this module turns what
//// reaches the connection into the rule's inputs and carries out its effects.
////
//// ```
//// the cast rule's Pay (an accepted press)          ─▶ class_resource.pay
//// the cast rule's Gain (a go's gains)              ─▶ class_resource.gain
//// a timer class_resource.owns                     ─▶ class_resource.timer_fired
//// player_life's effects: 0x88c dead                ─▶ class_resource.died
////                        0x88c alive               ─▶ class_resource.came_back
////                        0x89a, the combat flag    ─▶ class_resource.combat_changed
//// the stay left (camp, Holocrypt)                 ─▶ class_resource.left
//// Changed(slot, value) ─▶ 0x935 to the player's own client only (the server's
//// choice: a viewer's client shows no other unit's class resource)
//// StartTimer, CancelTimer ─▶ the connection's own timers, as the cast rule's are
//// ```

import genesis_prime/client_connection.{type Request, Continue}
import genesis_prime/game/class_resource
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/player_life
import genesis_prime/game/world_entry
import genesis_prime/step.{
  type ConnectionEffect, type Effect, type TimerId, CancelTimer, OwnEffect,
  StartTimer,
}
import gleam/list
import gleam/option.{None, Some}

/// The session with the player's resources changed by the rule's step `change`,
/// and the connection's effects for what the step decided. With no player the
/// client holds in the world (a save and a leave take no send) nothing changes.
fn stepped(
  session session: Session,
  change change: fn(class_resource.Resources) ->
    #(class_resource.Resources, List(class_resource.Effect)),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.held_in_the_world(session.status) {
    None -> #(session, [])
    Some(#(_, entered)) -> {
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

/// The gains a go gives (genesis_prime/game/cast `Gain`).
pub fn gained(
  session session: Session,
  gains gains: List(class_resource.Gain),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  stepped(session:, change: class_resource.gain(resources: _, gains:))
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

/// What the effects of a step of the player's life did to the resource, in the
/// order player_life gave them: the death and the coming back (0x88c) and the
/// combat flag (0x89a) the player's own client is written.
pub fn life_effects(
  session session: Session,
  effects effects: List(player_life.Effect),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  list.fold(effects, #(session, []), fn(so_far, effect) {
    let #(session, written) = so_far
    let apply = fn(change) {
      let #(session, more) = stepped(session:, change:)
      #(session, list.append(written, more))
    }
    case effect {
      player_life.ToClient(written:) ->
        case written {
          player_life.OwnDeathState(dead: True) ->
            apply(fn(resources) { class_resource.died(resources:) })
          player_life.OwnDeathState(dead: False) ->
            apply(fn(resources) { class_resource.came_back(resources:) })
          player_life.OwnCombatState(in_combat:) ->
            apply(class_resource.combat_changed(resources: _, in_combat:))
          player_life.OwnShield(..)
          | player_life.OwnHealth(..)
          | player_life.OwnDeathLogged
          | player_life.OwnCameBackLogged
          | player_life.GhostCreated(..)
          | player_life.OwnResurrectionWindow(..)
          | player_life.GhostRemoved
          | player_life.ControlGiven(..) -> so_far
        }
      player_life.ToViewers(..)
      | player_life.Answer(..)
      | player_life.StreamTo(..)
      | player_life.DamageTaken
      | player_life.EndCasts
      | player_life.GoToHolocrypt
      | player_life.TellMap(..)
      | player_life.StartTimer(..)
      | player_life.CancelTimer(..) -> so_far
    }
  })
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
