//// The player's properties on the game connection (genesis_prime/game/connection):
//// its rule (genesis_prime/game/unit_properties) is kept in the player's `Entered`
//// beside its life and its cast, and this module turns what the cast rule decides
//// into the rule's inputs and carries out what changed.
////
//// ```
//// the cast rule's CasterChangeStarts ─▶ unit_properties.apply  ─┐
//// the cast rule's PropertyEnds   ─▶ unit_properties.remove ─┤ changed entries
////                                                           ├─▶ 0x93a to the player's client
////                                                           ├─▶ PropertiesChanged to each viewer
////                                                           └─▶ player_life.properties_changed:
////                                                               maxima, regeneration, 0x92f, 0x938
//// ```
////
//// - **The player and its viewers are told the same entries**, the base and the value
////   of each property whose value changed, in one 0x93a each (`opcode.0x93a`); a
////   viewer's client shows the unit when its news arrives and drops it otherwise
////   (genesis_prime/game/connection/viewers). A viewer that arrives later is created
////   with the current values in its 0x262 (`frames.appearance_at`).
//// - **An Interrupt Armor row** starts as any modifier does, on property 44, and then
////   raises the armor (`armor_started`: 0x938 of stat 21 to the player and the news to each
////   viewer); its end tells the armor first and the maximum after (`ended`). The client
////   clamps the armor it is sent to the maximum it holds, and keeps an armor above a lowered
////   maximum until the next 0x938 (`opcode.0x938.interrupt_armor`).
//// - **A change that moves nothing** is not told: a modifier that leaves a value as it
////   was, a source already held, and an end of a source that is not held.
//// - **The life follows the properties**: BaseHealth and ShieldCapacityMax are the
////   maxima, HealthRegenMultiplier and ShieldTickTime the regeneration's numbers; the
////   health and shield are kept and capped at a lowered maximum, which the player's
////   client and its viewers are told (`player_life.properties_changed`).
//// - **A player not held in the world** (a save, a leave) takes no change: its
////   properties go with its `Entered`.

import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/frames as connection_frames
import genesis_prime/game/connection/life_effect
import genesis_prime/game/connection/state.{type Session} as connection_state
import genesis_prime/game/player_life
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/step.{type ConnectionEffect, type Effect, type Now}
import gleam/list
import gleam/option.{None, Some}

/// A modifier of the player's own spell starts (genesis_prime/game/cast
/// `CasterChangeStarts`).
pub fn started(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
  modifier modifier: unit_properties.Modifier,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  changed(session:, now:, change: unit_properties.apply(
    properties: _,
    source:,
    modifier:,
  ))
}

/// An Interrupt Armor row of the player's own spell starts (genesis_prime/game/cast
/// `Armor`): the maximum, property 44, rises by `points` and is told first, then the
/// armor rises by them. The client clamps the armor it is sent to the maximum it holds, so
/// the other order would show 0 (`opcode.0x938.interrupt_armor`).
pub fn armor_started(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
  points points: Int,
  takes_back takes_back: Bool,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let #(session, raised) =
    started(
      session:,
      now:,
      source:,
      modifier: unit_properties.interrupt_armor_modifier(points:),
    )
  let #(session, given) =
    armor_changed(session:, now:, change: fn(entered) {
      player_life.armor_given(life: entered.life, source:, points:, takes_back:)
    })
  #(session, list.append(raised, given))
}

/// A modifier of the player's own spell ends (genesis_prime/game/cast
/// `PropertyEnds`). An Interrupt Armor row's end takes its armor back first, when its row
/// says so, and then lowers the maximum, which clamps what armor is left: the client
/// clamps the armor to the maximum it holds only when a 0x938 arrives, so the armor is
/// told before the maximum falls (`opcode.0x938.interrupt_armor`).
pub fn ended(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  let #(session, taken) =
    armor_changed(session:, now:, change: fn(entered) {
      let #(without, _) =
        unit_properties.remove(properties: entered.properties, source:)
      player_life.armor_ended(life: entered.life, source:, properties: without)
    })
  let #(session, lowered) =
    changed(session:, now:, change: unit_properties.remove(
      properties: _,
      source:,
    ))
  #(session, list.append(taken, lowered))
}

/// The session with the player's life changed by `change`, which reads the player as it
/// stands, and what the life decided
/// written to the player's client and told to its viewers. With no player in the world it
/// is dropped.
fn armor_changed(
  session session: Session,
  now now: Now,
  change change: fn(world_entry.Entered) ->
    #(player_life.Life, List(player_life.Effect)),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.held_in_the_world(session.status) {
    None -> #(session, [])
    Some(#(_, entered)) -> {
      let #(life, effects) = change(entered)
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, life:)
        })
      #(session, life_effect.life_effects(session:, now:, entered:, effects:))
    }
  }
}

/// The session with the properties changed by `change`, and for the entries it
/// reports: the life taken to the new values, 0x93a to the player's client and the news
/// to each viewer, then what the life writes. The player's `Entered` is updated once.
fn changed(
  session session: Session,
  now now: Now,
  change change: fn(unit_properties.Properties) ->
    #(unit_properties.Properties, List(unit_properties.Changed)),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case connection_state.held_in_the_world(session.status) {
    None -> #(session, [])
    Some(#(_, entered)) -> {
      let #(properties, entries) = change(entered.properties)
      changed_to(session:, now:, entered:, properties:, entries:)
    }
  }
}

/// The player's `entered` with its properties now `properties`, which changed the
/// `entries`: held as they are when none changed, else the life taken to the new values
/// and everything told.
fn changed_to(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  properties properties: unit_properties.Properties,
  entries entries: List(unit_properties.Changed),
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  case entries {
    [] -> #(
      connection_state.with_entered(session:, change: fn(entered) {
        world_entry.Entered(..entered, properties:)
      }),
      [],
    )
    [_, ..] -> {
      let #(life, life_effects) =
        player_life.properties_changed(life: entered.life, properties:)
      let updated = world_entry.Entered(..entered, properties:, life:)
      let session =
        connection_state.with_entered(session:, change: fn(_) { updated })
      #(
        session,
        told(session:, now:, entered: updated, entries:, life_effects:),
      )
    }
  }
}

/// 0x93a to the player's client and the news to each viewer, the same entries, then what
/// the life writes for its new maxima and regeneration.
fn told(
  session session: Session,
  now now: Now,
  entered entered: world_entry.Entered,
  entries entries: List(unit_properties.Changed),
  life_effects life_effects: List(player_life.Effect),
) -> List(Effect(ConnectionEffect(Request))) {
  let sent = unit_properties.entries(changed: entries)
  list.flatten([
    [
      connection_state.to_client(
        session,
        connection_frames.properties_changed_frame(
          unit_id: entered.unit_id,
          properties: sent,
        ),
      ),
    ],
    connection_state.news_to_viewers(
      entered:,
      news: client_connection.PropertiesChanged(properties: sent),
    ),
    life_effect.life_effects(session:, now:, entered:, effects: life_effects),
  ])
}
