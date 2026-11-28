//// The credit for a kill, which the map relays from the creature to the connection of the
//// player whose blow killed it (genesis_prime/game/experience turns it into experience).

import genesis_prime/table/id.{type Creature2Id, type Faction2Id}

/// The credit for a kill a creature tells the connection of the player whose blow
/// killed it: the creature's unit, its Creature2 row, its Faction2 (the one its 0x262
/// sends) and its level, the level its 0x262 sends as stat 10.
pub type Credit {
  Credit(
    unit_id: Int,
    creature_id: Creature2Id,
    faction_id: Faction2Id,
    level: Int,
  )
}
