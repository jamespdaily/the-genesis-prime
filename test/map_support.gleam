//// What the tests of the map's rule share: the map's realm, a map with no
//// players and a character of a known look.

import character_support
import character_tables
import genesis_prime/store.{type Character, Character}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/map_id.{MapId}

/// The map's realm: not 1, so a unit built with a fixed realm fails.
pub const realm_id = 7

/// A map of the World table's row 3460 with no players, run as `incarnation`.
pub fn empty(incarnation incarnation: Int) -> State {
  map.new(map.Settings(
    map: MapId(world_id: 3460, instance: 0),
    incarnation:,
    realm_id:,
    tables: character_tables.shared(),
  ))
}

/// A Dominion human male whose id is `number`, with the look of
/// CharacterCustomization row 10. Its saved place is not the place a Join
/// carries, which is the place the unit is made at.
pub fn character(number number: Int) -> Character {
  Character(
    ..character_support.character(number:),
    look: character_tables.row_10_look(),
  )
}
