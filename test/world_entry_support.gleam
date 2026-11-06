//// What the world entry tests share: a character's entry through the rule
//// (`genesis_prime/game/world_entry`) on the tables given, with the effects it
//// decided and the player it keeps.

import character_support
import class_resource_support
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/unit_properties
import genesis_prime/game/world_entry
import genesis_prime/message/play_character.{PlayCharacter}
import genesis_prime/step.{ConnectionId}
import genesis_prime/store.{type Character, AccountId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map
import genesis_prime/world_map/player_unit
import gleam/list
import gleam/option.{None}
import map_support
import place_support
import spawn_support
import unit_support

/// What a character's entry decides on these tables: its effects, in order, and
/// the player the connection keeps.
pub fn entry(
  tables tables: table_store.Tables,
  character character: Character,
) -> #(List(world_entry.Effect), world_entry.Entered) {
  let assert Ok(body) = play_character.encode(PlayCharacter(character_id: 42))
    as "a character id fits the message"
  let assert Ok(#(state, _asks)) =
    world_entry.take(account_id: AccountId(7), body:)
    as "the client's request to play decodes"
  let place =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 29.0,
      y: -853.0,
      z: -560.0,
    )
  let assert Ok(world_entry.Join(state:, ..)) =
    world_entry.loaded(
      state:,
      answer: store.CharacterLoaded(
        character:,
        session_epoch: character_support.epoch(1),
        saved_health: None,
      ),
      connection: ConnectionId(1),
      stay: map_support.stay(count: 1),
    )
    as "the store holds the character and its place"
  let unit =
    unit_support.novice_unit(tables:, character:, place:, unit_id: 1, body: [])
  let assert Ok(world_entry.InTheWorld(entered:, effects:)) =
    world_entry.joined(
      state:,
      answer: map.Joined(
        unit: player_unit.create(unit:, realm_id: 1),
        loadout: player_unit.loadout(unit:),
        max_health: player_unit.max_health(unit:),
        incarnation: 1,
        clock_origin_ms: 0,
      ),
      realm_id: 1,
      next_whisper: 1,
      classes: class_resource_support.classes(),
      numbers: spawn_support.numbers,
      defaults: unit_properties.defaults(tables:),
      tables:,
    )
    as "the map's answer to the join is the one world entry asked for"
  #(effects, entered)
}

/// The frames among an entry's effects, in order.
pub fn frames_of(effects effects: List(world_entry.Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      world_entry.Send(frame:) -> Ok(frame)
      world_entry.AskStore(..)
      | world_entry.AskMap(..)
      | world_entry.WatchMap(..)
      | world_entry.Life(..)
      | world_entry.StartPassive(..) -> Error(Nil)
    }
  })
}
