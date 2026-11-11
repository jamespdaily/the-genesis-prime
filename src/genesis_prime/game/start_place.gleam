//// Where a new character starts: the WorldLocation2 row of each start of
//// each race and faction, and the way the row faces. The client holds every
//// start place as a WorldLocation2 row, but no client table, code or Lua links
//// a start to its row (CharacterCreation.characterCreationStartEnum), so the
//// rows are chosen by the client's own tutorial text, and the place is always
//// the client's row: its world, zone, position and facing.
////
//// - Novice (characterCreationStartEnum 4, PreTutorial), every race and
////   faction: row 51596, World 3460 (Map\NewPlayerExperience, the training
////   simulation of World.3460). No table names it: it stands 15.7 units from
////   the first quest circle (row 51735) and faces it (Quest2.10513, a guess).
//// - Veteran (3, Nexus): the row the last quest of that simulation, 'Bon
////   Voyage', links in its completion text for each landing. Exile Human and
////   Granok 42074 (Landing Site, Northern Wilds); Aurin and Mordesh 41641
////   (Greenleaf Glade, Everstar Grove), the race groups being those of the
////   quest's text (Quest2.10528, Quest2.10528.links). Dominion 42148
////   (Stormcaller Landing, Levian Bay) and 8223 (Mondo's Beachhead, Crimson
////   Isle) (Quest2.10530, Quest2.10530.links, WorldLocation2.8223). The client
////   does not say which Dominion races go to which landing; that is a retail
////   record (wildstaronline-archive, read through the Wayback Machine, 2020
////   snapshots; the page "Destiny",
////   https://wildstaronline-archive.fandom.com/wiki/Destiny: "The Chua and the
////   Draken are expected to go to Crimson Isle and the Cassian and Mechari are
////   generally sent to Levian Bay", and the page "Levian Bay",
////   https://wildstaronline-archive.fandom.com/wiki/Levian_Bay: "default
////   starter zone for Cassian and Mechari players"): Cassian and Mechari
////   42148, Draken and Chua 8223.
////
//// Level 50 (5) has no place: every Level 50 CharacterCreation row costs
//// account currency, which a create refuses first (`CostsCurrency`).
////
//// A row's facing0 to facing3 is a quaternion (WorldLocation2.facing0), which
//// the place turns into yaw, pitch and roll as the client's own
//// QuaternionToEulerAngles does (`facing_of_quaternion`). The client never
//// applies a row's facing to a unit, so that a character given this yaw faces
//// the way the row means is read from the data (WorldLocation2.facing0).
////
//// A start, race or faction that no row above names has no place, so a
//// create for it is refused (genesis_prime/game/character_creation). The
//// table load fails when a row above is not a WorldLocation2 row
//// (`requirement`).

import genesis_prime/message/float32
import genesis_prime/table/id.{type RaceId, RaceId, WorldLocation2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/world_location2
import gleam/float
import gleam/list
import gleam/result
import gleam_community/maths

/// The way a character faces: yaw, pitch and roll in radians, as the movement
/// command of kind 14 carries them (0x140715350). A float here is always
/// finite: the VM holds no infinity and no NaN.
pub type Facing {
  Facing(yaw: Float, pitch: Float, roll: Float)
}

/// The facing of a character that has never turned: 0, 0, 0, which is what a
/// character's row holds until its first save.
pub const unturned = Facing(yaw: 0.0, pitch: 0.0, roll: 0.0)

/// RotationMatrixToEulerAngles' threshold on the matrix's m21: a value beyond
/// it, either way, gives a pitch of a quarter turn (0x1401b2ed0, the bytes at
/// 0x140b79ecc, the 32-bit float 0.99999).
const pole = 0.9999899864196777

/// The same threshold below zero (the bytes at 0x140b7a238).
const negative_pole = -0.9999899864196777

/// The yaw, pitch and roll that the client's QuaternionToEulerAngles
/// (0x1401b2fe0) makes of the rotation quaternion x, y, z, w, which is what a
/// WorldLocation2 row's facing0 to facing3 hold. It builds the quaternion's
/// rotation matrix and turns it as RotationMatrixToEulerAngles (0x1401b2ed0)
/// does: yaw atan2(m20, m22), pitch asin(-m21) and roll atan2(m01, m11); when
/// m21 is beyond `pole` either way, the pitch is a quarter turn (up for m21
/// below -0.99999), the roll 0 and the yaw atan2(-m02, m00).
///
/// The client computes in 32-bit floats, so each angle is the nearest 32-bit
/// float, which is also what a save and a load give back, and m21 is compared
/// with `pole` as a 32-bit float. The arithmetic is done in the VM's own floats
/// and gives the client's value to the bit, the sign of a zero included (a
/// pitch of -0.0 for a turn about y alone), for each of the five start rows.
pub fn facing_of_quaternion(
  x x: Float,
  y y: Float,
  z z: Float,
  w w: Float,
) -> Facing {
  let m00 = 1.0 -. 2.0 *. y *. y -. 2.0 *. z *. z
  let m01 = 2.0 *. { x *. y +. w *. z }
  let m02 = 2.0 *. { x *. z -. w *. y }
  let m11 = 1.0 -. 2.0 *. x *. x -. 2.0 *. z *. z
  let m20 = 2.0 *. { x *. z +. w *. y }
  let m21 = 2.0 *. { y *. z -. w *. x }
  let m22 = 1.0 -. 2.0 *. x *. x -. 2.0 *. y *. y
  let quarter_turn = maths.pi() /. 2.0
  let held_m21 = float32.rounded(m21)
  let #(yaw, pitch, roll) = case held_m21 {
    _ if held_m21 <. negative_pole -> #(
      maths.atan2(float.negate(m02), m00),
      quarter_turn,
      0.0,
    )
    _ if held_m21 >. pole -> #(
      maths.atan2(float.negate(m02), m00),
      float.negate(quarter_turn),
      0.0,
    )
    _ -> {
      let assert Ok(pitch) =
        maths.asin(float.clamp(float.negate(m21), min: -1.0, max: 1.0))
        as "the clamp to -1 and 1, as the client does, keeps asin's argument in its range"
      #(maths.atan2(m20, m22), pitch, maths.atan2(m01, m11))
    }
  }
  Facing(
    yaw: float32.rounded(yaw),
    pitch: float32.rounded(pitch),
    roll: float32.rounded(roll),
  )
}

/// A character's place in the world: the World row, the WorldZone row, the
/// position and the way it faces. It is always in a world: `place` refuses
/// world 0, which is no World row (opcode.0xad), so a zone, a position and a
/// facing with no world cannot be held. Moving or turning a place keeps its
/// world and zone, so a moved place is never in another world; only `in_zone`
/// changes the zone.
pub opaque type Place {
  Place(
    world_id: Int,
    world_zone_id: Int,
    x: Float,
    y: Float,
    z: Float,
    facing: Facing,
  )
}

/// The place in the World row `world_id`, `Error(Nil)` for world 0.
pub fn place(
  world_id world_id: Int,
  world_zone_id world_zone_id: Int,
  x x: Float,
  y y: Float,
  z z: Float,
  facing facing: Facing,
) -> Result(Place, Nil) {
  case world_id {
    0 -> Error(Nil)
    _ -> Ok(Place(world_id:, world_zone_id:, x:, y:, z:, facing:))
  }
}

/// The place's World row, never 0.
pub fn world_id(place: Place) -> Int {
  place.world_id
}

/// The place's WorldZone row.
pub fn world_zone_id(place: Place) -> Int {
  place.world_zone_id
}

/// The place's position on the x axis.
pub fn x(place: Place) -> Float {
  place.x
}

/// The place's position on the y axis.
pub fn y(place: Place) -> Float {
  place.y
}

/// The place's position on the z axis.
pub fn z(place: Place) -> Float {
  place.z
}

/// The way the place faces.
pub fn facing(place: Place) -> Facing {
  place.facing
}

/// The place with its position inside the box the client bounds a unit's
/// position to: x and z from -32768 to 32768, y from -2048 to 2048
/// (WorldPositionBounds, 0x1405b5070). It is the position the server writes to
/// the client for a place, which the client's world load keeps as sent
/// (opcode.0xad.position); the place itself, as the character is saved, is
/// never bounded. The choice to bound what is sent is the server's.
pub fn within_the_worlds_box(place place: Place) -> Place {
  Place(
    ..place,
    x: float.clamp(place.x, min: -32_768.0, max: 32_768.0),
    y: float.clamp(place.y, min: -2048.0, max: 2048.0),
    z: float.clamp(place.z, min: -32_768.0, max: 32_768.0),
  )
}

/// The place's world and zone, standing at the position `x`, `y`, `z`.
pub fn moved(place place: Place, x x: Float, y y: Float, z z: Float) -> Place {
  Place(..place, x:, y:, z:)
}

/// The place's world and position, in the zone `world_zone_id`. The zone is
/// kept as given: it is the zone the client reports, which it does not check
/// against its WorldZone table (0x14036d040).
pub fn in_zone(place place: Place, world_zone_id world_zone_id: Int) -> Place {
  Place(..place, world_zone_id:)
}

/// The place's world, zone and position, facing `facing`.
pub fn turned(place place: Place, facing facing: Facing) -> Place {
  Place(..place, facing:)
}

/// The Dominion faction's Faction2 id, as the CharacterCreation rows hold it.
const dominion = 166

/// The Exile faction's Faction2 id, as the CharacterCreation rows hold it.
const exile = 167

/// A start of a new character, as CharacterCreation's characterCreationStartEnum
/// gives it. The enum's other values (the Arkship start 0 among them) are
/// `OtherStart`, which has no start place.
pub type Start {
  /// The Veteran start, in Nexus (characterCreationStartEnum 3).
  Veteran
  /// The Novice start, PreTutorial (characterCreationStartEnum 4).
  Novice
  /// The Level 50 start (characterCreationStartEnum 5).
  Level50
  /// Any other value of the enum.
  OtherStart(enum_value: Int)
}

/// The start a CharacterCreation row's characterCreationStartEnum names.
pub fn start(enum_value enum_value: Int) -> Start {
  case enum_value {
    3 -> Veteran
    4 -> Novice
    5 -> Level50
    other -> OtherStart(enum_value: other)
  }
}

/// The Exile races: Human 1, Granok 3, Aurin 4 and Mordesh 16.
const exile_races = [RaceId(1), RaceId(3), RaceId(4), RaceId(16)]

/// The Dominion races: Cassian 1, Draken 5, Mechari 12 and Chua 13.
const dominion_races = [RaceId(1), RaceId(5), RaceId(12), RaceId(13)]

/// The races a player can create: those with a start place, each once.
pub fn playable_races() -> List(RaceId) {
  list.flat_map(starts, fn(group) { group.race_ids }) |> list.unique
}

/// The places of the starts: for a start and faction, each group of races and
/// the WorldLocation2 row they begin at.
type StartGroup {
  StartGroup(
    start: Start,
    faction_id: Int,
    race_ids: List(RaceId),
    location_id: Int,
  )
}

const starts = [
  StartGroup(
    start: Novice,
    faction_id: exile,
    race_ids: exile_races,
    location_id: 51_596,
  ),
  StartGroup(
    start: Novice,
    faction_id: dominion,
    race_ids: dominion_races,
    location_id: 51_596,
  ),
  StartGroup(
    start: Veteran,
    faction_id: exile,
    race_ids: [RaceId(1), RaceId(3)],
    location_id: 42_074,
  ),
  StartGroup(
    start: Veteran,
    faction_id: exile,
    race_ids: [RaceId(4), RaceId(16)],
    location_id: 41_641,
  ),
  StartGroup(
    start: Veteran,
    faction_id: dominion,
    race_ids: [RaceId(1), RaceId(12)],
    location_id: 42_148,
  ),
  StartGroup(
    start: Veteran,
    faction_id: dominion,
    race_ids: [RaceId(5), RaceId(13)],
    location_id: 8223,
  ),
]

/// The place a character of this faction and race starts at for a
/// CharacterCreation row's start, from the client's WorldLocation2 row: its
/// world, zone, position and facing. `Error(Nil)` for a start, race or faction
/// with no row above, and for a row in world 0.
pub fn of(
  tables tables: table_store.Tables,
  faction_id faction_id: Int,
  race_id race_id: RaceId,
  start start: Start,
) -> Result(Place, Nil) {
  use found <- result.try(
    list.find(starts, fn(candidate) {
      candidate.start == start
      && of_race_and_faction(candidate:, faction_id:, race_id:)
    }),
  )
  place_of_row(tables:, location_id: found.location_id)
}

/// Whether the start above is one of characters of this faction and race.
fn of_race_and_faction(
  candidate candidate: StartGroup,
  faction_id faction_id: Int,
  race_id race_id: RaceId,
) -> Bool {
  candidate.faction_id == faction_id
  && list.contains(candidate.race_ids, race_id)
}

/// The place of a WorldLocation2 row: its world, zone, position and facing.
/// `Error(Nil)` for a row the tables lack or one in world 0.
fn place_of_row(
  tables tables: table_store.Tables,
  location_id location_id: Int,
) -> Result(Place, Nil) {
  use row <- result.try(world_location2.get(
    tables:,
    id: WorldLocation2Id(location_id),
  ))
  of_row(row:)
}

/// The place of a WorldLocation2 row: its world, zone, position and facing.
/// `Error(Nil)` for a row in world 0.
pub fn of_row(row row: world_location2.WorldLocation2) -> Result(Place, Nil) {
  place(
    world_id: row.world_id,
    world_zone_id: row.world_zone_id,
    x: row.position0,
    y: row.position1,
    z: row.position2,
    facing: facing_of_quaternion(
      x: row.facing0,
      y: row.facing1,
      z: row.facing2,
      w: row.facing3,
    ),
  )
}

/// The place a dead character of this faction and race comes back at when it
/// chooses the Holocrypt in the world `world_id`: the start of its race and
/// faction above whose row is in that world. The server's choice: neither the
/// client nor a retail record holds a Holocrypt's place (`death.server_choices`).
/// `Error(Nil)` when no start of the race and faction is in that world.
pub fn holocrypt(
  tables tables: table_store.Tables,
  faction_id faction_id: Int,
  race_id race_id: RaceId,
  world_id world_id: Int,
) -> Result(Place, Nil) {
  starts
  |> list.filter(fn(candidate) {
    of_race_and_faction(candidate:, faction_id:, race_id:)
  })
  |> list.filter_map(fn(candidate) {
    place_of_row(tables:, location_id: candidate.location_id)
  })
  |> list.find(fn(found) { found.world_id == world_id })
}

/// The load's check that every row above is a WorldLocation2 row, so a client
/// without one fails the server's start.
pub fn requirement() -> table_store.Requirement {
  table_store.Requirement(
    from_table: "the server's start places",
    column: "WorldLocation2 id",
    to_table: "WorldLocation2",
    missing: fn(tables) {
      list.map(starts, fn(group) { group.location_id })
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
