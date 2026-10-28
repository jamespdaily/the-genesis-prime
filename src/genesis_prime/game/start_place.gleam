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
////
//// A start, race or faction that no row above names has no place, so a
//// create for it is refused (genesis_prime/game/character_creation). The
//// table load fails when a row above is not a WorldLocation2 row
//// (`requirement`).

import genesis_prime/table/id.{type RaceId, WorldLocation2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/world_location2
import gleam/list
import gleam/result

/// A character's place in the world: the World row, the WorldZone row and the
/// position, as the client's WorldLocation2 row gives them.
pub type Place {
  Place(world_id: Int, world_zone_id: Int, x: Float, y: Float, z: Float)
}

/// The Dominion faction's Faction2 id, as the CharacterCreation rows hold it.
const dominion = 166

/// The Exile faction's Faction2 id, as the CharacterCreation rows hold it.
const exile = 167

/// The characterCreationStartEnum of the Veteran start (Nexus).
const veteran = 3

/// The characterCreationStartEnum of the Novice start (PreTutorial).
const novice = 4

/// The characterCreationStartEnum of the Level 50 start.
const level_50 = 5

/// The Exile races: Human 1, Granok 3, Aurin 4 and Mordesh 16.
const exile_races = [1, 3, 4, 16]

/// The Dominion races: Cassian 1, Draken 5, Mechari 12 and Chua 13.
const dominion_races = [1, 5, 12, 13]

/// The places of the starts: for a start and faction, each group of races and
/// the WorldLocation2 row they begin at.
type Start {
  Start(start: Int, faction_id: Int, race_ids: List(Int), location_id: Int)
}

const starts = [
  Start(
    start: novice,
    faction_id: exile,
    race_ids: exile_races,
    location_id: 51_596,
  ),
  Start(
    start: novice,
    faction_id: dominion,
    race_ids: dominion_races,
    location_id: 51_596,
  ),
  Start(start: veteran, faction_id: exile, race_ids: [1, 3], location_id: 1594),
  Start(
    start: veteran,
    faction_id: exile,
    race_ids: [4, 16],
    location_id: 37_015,
  ),
  Start(
    start: veteran,
    faction_id: dominion,
    race_ids: [1, 12],
    location_id: 18_987,
  ),
  Start(
    start: veteran,
    faction_id: dominion,
    race_ids: [5, 13],
    location_id: 8223,
  ),
  Start(
    start: level_50,
    faction_id: exile,
    race_ids: exile_races,
    location_id: 53_050,
  ),
  Start(
    start: level_50,
    faction_id: dominion,
    race_ids: dominion_races,
    location_id: 53_051,
  ),
]

/// The place a character of this faction and race starts at for a
/// CharacterCreation row's start, from the client's WorldLocation2 row.
/// `Error(Nil)` for a start, race or faction with no row above.
pub fn of(
  tables tables: table_store.Tables,
  faction_id faction_id: Int,
  race_id race_id: RaceId,
  start start: Int,
) -> Result(Place, Nil) {
  use found <- result.try(
    list.find(starts, fn(candidate) {
      candidate.start == start
      && candidate.faction_id == faction_id
      && list.contains(candidate.race_ids, race_id.value)
    }),
  )
  use row <- result.map(world_location2.get(
    tables:,
    id: WorldLocation2Id(found.location_id),
  ))
  Place(
    world_id: row.world_id,
    world_zone_id: row.world_zone_id,
    x: row.position0,
    y: row.position1,
    z: row.position2,
  )
}

/// The load's check that every row above is a WorldLocation2 row, so a client
/// without one fails the server's start.
pub fn requirement() -> table_store.Requirement {
  table_store.Requirement(
    from_table: "the server's start places",
    column: "WorldLocation2 id",
    to_table: "WorldLocation2",
    missing: fn(tables) {
      list.map(starts, fn(start) { start.location_id })
      |> list.unique
      |> list.filter(fn(location_id) {
        result.is_error(world_location2.get(
          tables:,
          id: WorldLocation2Id(location_id),
        ))
      })
    },
  )
}
