//// A player's unit on a map: the facts of the character that observers of the
//// unit need to create it (message 0x262, a unit of type 20), and where it
//// stands. A map holds one unit for each character that joined.

import genesis_prime/map/position.{type Position}

/// A player character's unit. `id` is the unit id the map gave it, the
/// 32-bit number the client's unit messages name it by (message 0x262's
/// unit id). The rest is the character's own: its id, name, race, class,
/// gender, path and faction as the character list gives them.
pub type PlayerUnit {
  PlayerUnit(
    id: Int,
    character_id: Int,
    name: String,
    race_id: Int,
    class_id: Int,
    gender: Int,
    path: Int,
    faction_id: Int,
    position: Position,
  )
}

/// A character that joins a map, before the map gives its unit an id.
pub type Newcomer {
  Newcomer(
    character_id: Int,
    name: String,
    race_id: Int,
    class_id: Int,
    gender: Int,
    path: Int,
    faction_id: Int,
    position: Position,
  )
}
