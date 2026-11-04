//// What the tests that need a player's unit share: a loadout that holds nothing
//// (so a test of the unit's place, body or level reads no table) and the unit of
//// a character with the loadout the tables give its class and faction.

import genesis_prime/game/item_property.{ItemProperties}
import genesis_prime/game/loadout.{type Loadout, Loadout}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/store.{type Character}
import genesis_prime/table/id.{Item2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/player_unit.{type PlayerUnit}
import gleam/option.{None}

/// A loadout of no armor, no ability, no drawn piece and gear that gives
/// nothing, with a weapon in the weapon slot.
pub fn bare_loadout() -> Loadout {
  Loadout(
    weapon: Item2Id(1),
    weapon_slot: 16,
    armor: [],
    visuals: [],
    abilities: [],
    properties: ItemProperties(
      base_health: 0.0,
      assault_rating: 0.0,
      support_rating: 0.0,
      armor: 0.0,
      shield: None,
    ),
  )
}

/// The health of a unit made with `bare_loadout`: the client's level-1 creature
/// Base Health (`vector.opcode.0x262.health`), which the tests that read the
/// unit's bytes against the client's own need.
pub const bare_health = 136

/// The unit of the character with `bare_loadout` and `bare_health`.
pub fn bare_unit(
  character character: Character,
  place place: Place,
  unit_id unit_id: Int,
  body body: List(ItemVisual),
) -> PlayerUnit {
  player_unit.new(
    character:,
    place:,
    unit_id:,
    body:,
    loadout: bare_loadout(),
    max_health: bare_health,
  )
}

/// The unit of the character with the loadout of its class and faction and the
/// health that gives at its level, from the tables.
pub fn novice_unit(
  tables tables: table_store.Tables,
  character character: Character,
  place place: Place,
  unit_id unit_id: Int,
  body body: List(ItemVisual),
) -> PlayerUnit {
  let assert Ok(loadout) =
    loadout.of(
      tables:,
      class_id: character.class_id,
      faction_id: character.faction_id,
    )
    as "the tables hold a Novice set for the class and faction"
  let assert Ok(max_health) =
    loadout.max_health(tables:, loadout:, level: character.level)
    as "the tables hold a CreatureLevel row for the level"
  player_unit.new(character:, place:, unit_id:, body:, loadout:, max_health:)
}
