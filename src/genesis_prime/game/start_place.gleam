//// Where a new character starts: the WorldLocation2 row of each start of
//// each race and faction. The client holds every start place as a
//// WorldLocation2 row, but no client table links a start to its row
//// (CharacterCreation.characterCreationStartEnum, WorldLocation2.50230). The
//// links are Jim's world database's (wildstar-knowledge,
//// world-data/start_location.tsv, its 24 rows; Jim's go, 2026-10-28): each of
//// its places is a WorldLocation2 row's to the unit, except Draken and Chua
//// Veteran, 3.4 units from row 8223, which is used. The place itself, world,
//// zone and position, is always the client's row.
////
//// - Novice (characterCreationStartEnum 4, PreTutorial), every race and
////   faction: row 51596, World 3460 (Map\NewPlayerExperience).
//// - Veteran (3, Nexus): Exile Human and Granok 1594, Aurin and Mordesh 37015;
////   Dominion Cassian and Mechari 18987, Draken and Chua 8223.
//// - Level 50 (5): Exile 53050, Dominion 53051.

import genesis_prime/store.{type RaceId}
import genesis_prime/table/loader/store as table_store

/// A character's place in the world: the World row, the WorldZone row and the
/// position, as the client's WorldLocation2 row gives them.
pub type Place {
  Place(world_id: Int, world_zone_id: Int, x: Float, y: Float, z: Float)
}

/// The place a character of this faction and race starts at for a
/// CharacterCreation row's start, from the client's WorldLocation2 row.
/// `Error(Nil)` for a start, race or faction with no row above.
pub fn of(
  tables tables: table_store.Tables,
  faction_id faction_id: Int,
  race_id race_id: RaceId,
  start start: Int,
) -> Result(Place, Nil) {
  todo as "built in the build"
}

/// The load's check that every row above is a WorldLocation2 row, so a client
/// without one fails the server's start.
pub fn requirement() -> table_store.Requirement {
  todo as "built in the build"
}
