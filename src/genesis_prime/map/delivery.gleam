//// What a map tells the connection of each player on it: another player's
//// unit came into range or went out of it. The connection turns each into
//// the client's messages (0x262 to create the unit, 0x355 to remove it).

import genesis_prime/map/unit.{type PlayerUnit}

/// What happened to a unit that a player's connection is told about.
pub type Delivery {
  /// A player's unit joined the map in range of this player.
  Appeared(unit: PlayerUnit)
  /// A unit left the map, or went out of range of this player.
  Disappeared(unit_id: Int)
}
