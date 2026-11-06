//// The player's properties on the game connection (genesis_prime/game/connection):
//// its rule (genesis_prime/game/unit_properties) is kept in the player's `Entered`
//// beside its life and its cast, and this module turns what the cast rule decides
//// into the rule's inputs and carries out what changed.
////
//// ```
//// the cast rule's PropertyStarts ─▶ unit_properties.apply  ─┐
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
/// `PropertyStarts`).
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

/// A modifier of the player's own spell ends (genesis_prime/game/cast
/// `PropertyEnds`).
pub fn ended(
  session session: Session,
  now now: Now,
  source source: unit_properties.Source,
) -> #(Session, List(Effect(ConnectionEffect(Request)))) {
  changed(session:, now:, change: unit_properties.remove(properties: _, source:))
}

/// The session with the properties changed by `change`, and for the entries it
/// reports: 0x93a to the player's client, the news to each viewer, and the life's
/// follow-up.
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
      let session =
        connection_state.with_entered(session:, change: fn(entered) {
          world_entry.Entered(..entered, properties:)
        })
      case entries {
        [] -> #(session, [])
        [_, ..] -> {
          let sent = unit_properties.entries(changed: entries)
          let told =
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
              list.map(connection_state.sorted_viewers(entered:), fn(viewer) {
                connection_state.news_to(
                  entered:,
                  viewer:,
                  news: client_connection.PropertiesChanged(properties: sent),
                )
              }),
            ])
          let #(life, life_effects) =
            player_life.properties_changed(life: entered.life, properties:)
          let session =
            connection_state.with_entered(session:, change: fn(entered) {
              world_entry.Entered(..entered, life:)
            })
          let following = case connection_state.entered_of(session.status) {
            Some(entered) ->
              life_effect.life_effects(
                session:,
                now:,
                entered:,
                effects: life_effects,
              )
            None -> []
          }
          #(session, list.append(told, following))
        }
      }
    }
  }
}
