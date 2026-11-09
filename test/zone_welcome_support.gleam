//// What the tests that hold the zones' welcomes share: the set with none in it, which a
//// connection made for another test is given, the rows of the welcomes the landing zones
//// reach, and the set those rows select to over the client's committed rows.

import character_tables
import genesis_prime/game/zone_welcome.{type ZoneWelcomes, Row}

/// A set with no welcome in it: the rows of an empty table select to it.
pub fn none() -> ZoneWelcomes {
  let assert Ok(none) =
    zone_welcome.select(rows: [], tables: character_tables.content_tables())
    as "no rows select"
  none
}

/// The rows of the welcomes the four landings and the Settler's Reach walk reach, each a
/// zone of the client's WorldZone table with the Tutorial row whose first page title
/// names it, as the seed of the zone_welcome table states in each row's reason: zone 35
/// and the zones 590 and 596 below it show Tutorial 332 (the Northern Wilds), zone 593
/// shows 233 (Settler's Reach), 1414 shows 331 (Everstar Grove), 1304 shows 330 (Levian
/// Bay) and 622 shows 329 (Crimson Isle).
pub fn rows() -> List(zone_welcome.Row) {
  [
    Row(world_zone_id: 35, tutorial_id: 332),
    Row(world_zone_id: 590, tutorial_id: 332),
    Row(world_zone_id: 596, tutorial_id: 332),
    Row(world_zone_id: 593, tutorial_id: 233),
    Row(world_zone_id: 1414, tutorial_id: 331),
    Row(world_zone_id: 1304, tutorial_id: 330),
    Row(world_zone_id: 622, tutorial_id: 329),
  ]
}

/// The set of those rows over the client's committed tables.
pub fn landings() -> ZoneWelcomes {
  let assert Ok(welcomes) =
    zone_welcome.select(rows: rows(), tables: character_tables.content_tables())
    as "each row names a WorldZone and a Tutorial row of category 29 in the committed tables"
  welcomes
}
