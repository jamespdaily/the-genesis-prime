//// The creatures a map stands: each spawn is one place a creature of the client's
//// Creature2 table stands at, with the values the creature's 0x262 carries,
//// read from the client's tables when they load. A spawn names the circle of the
//// client's WorldLocation2 table it stands inside and where its point comes
//// from, so no point is taken for the client's.
////
//// ```
//// the tables load ─▶ derivation: the points of this module, each checked against the
////                    client's Creature2 rules and its circle ─▶ the spawns, kept once
//// the server starts ─▶ World.spawns = all(tables) ─▶ each map is given of_map(spawns, map)
//// a map's Started   ─▶ one StartCreature per spawn of its map
//// ```
////
//// - **Which creatures stand.** The Novice training simulation (World 3460) in
////   Warfare Woods (zone 5967): Virtual Battle Beast (Creature2 73464) for the
////   Exile fight and Virtual Defense Dagun (Creature2 73465) for the Dominion
////   fight (Quest2.10518, Quest2.10524). Both stand in the map, and every player
////   in sight of one sees it. The Sim-Turrets (faction 219) are left out.
//// - **Where.** The 27 Battle Beasts stand at the 27 points of Jim's world
////   database (`spawn.tsv`, rows 29113 to 29139), each marked
////   `WorldDatabase(row)`, since the client holds no spawn point; all lie inside
////   the client's objective circle (WorldLocation2 51739, radius 55). The 27
////   Daguns have no record anywhere: each stands at the offset of one of those
////   points from that circle's centre, applied to the Dagun circle's centre
////   (WorldLocation2 52898, radius 55), marked `NoRecord(row)`; their heights
////   are checked live. A point's facing is the world database's rotation.
//// - **The creature's values**, from the client's own formulas, kept in the
////   spawn so the 0x262 needs no table at run time: the level is Creature2's
////   minLevel (equal to maxLevel for both), Base Health is
////   CreatureLevel[level] × the Creature2ArcheType, Creature2Difficulty and
////   Creature2Tier multipliers for UnitProperty2 7, truncated (`0x1404585c0`),
////   the faction is Creature2.factionId (the client keeps the message's two
////   fields in place of the row's), and the display is the entry of the
////   creature's Creature2DisplayGroupEntry group with the greatest weight, the
////   lowest display id on a tie: the client's own weighted pick runs only for
////   spawns it makes itself (`0x1404846c0`), so the server's pick is a choice.
//// - **The client's validity rules** (`0x140485790`): a Creature2 row is a
////   creature the client loads only when its modelScale is above 0, its
////   CreationTypeEnum is below 26, its archetype row exists, its difficulty and
////   resist are 0 or have a row, and its display group is not 0; a spawn of a
////   row that fails them is refused, since the client would drop the 0x262. A
////   spawn whose point lies outside its circle, whose circle has no row or
////   whose creature has no display entry is refused too. Any refusal fails the
////   load.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/table/id.{
  type Creature2Id, type WorldLocation2Id, Creature2Id, WorldLocation2Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import gleam/int
import gleam/list
import gleam/result

/// Where a spawn's point comes from.
pub type Source {
  /// A point of Jim's world database, `spawn.tsv` row `row_id`: data the client
  /// lacks, read from a record of the retail game.
  WorldDatabase(row_id: Int)
  /// No record anywhere: the point is the offset of the world-database point
  /// `row_id` from its circle's centre, applied to this spawn's circle, a
  /// server's choice.
  NoRecord(offset_of_row_id: Int)
}

/// One creature's place and values.
pub type Spawn {
  Spawn(
    id: SpawnId,
    /// The creature's Creature2 row.
    creature_id: Creature2Id,
    /// Where the creature stands and faces: in World 3460, zone 5967.
    place: Place,
    /// The WorldLocation2 circle of the client the point lies inside.
    area: WorldLocation2Id,
    source: Source,
    /// Stat 10: the row's level.
    level: Int,
    /// Stat 0: Base Health by the client's creature formula, truncated.
    health: Int,
    /// Creature2.factionId, sent in both faction fields.
    faction_id: Int,
    /// The Creature2DisplayInfo the 0x262 sends.
    display_info_id: Int,
  )
}

/// Why the spawns cannot be built.
type SpawnError {
  /// The creature has no Creature2 row.
  NoCreatureRow(creature_id: Creature2Id)
  /// The client would not load the creature's row (`0x140485790`).
  NotLoadedByTheClient(creature_id: Creature2Id, rule: ValidityRule)
  /// The circle has no WorldLocation2 row.
  NoAreaRow(area: WorldLocation2Id)
  /// The spawn's point lies outside its circle.
  OutsideArea(spawn: SpawnId, area: WorldLocation2Id)
  /// The creature's display group has no entry to send.
  NoDisplay(creature_id: Creature2Id)
}

/// The client's rule a creature's row fails (`0x140485790`).
type ValidityRule {
  ModelScaleNotAbove0
  CreationTypeNotBelow26
  NoArcheTypeRow
  NoDifficultyRow
  NoResistRow
  NoDisplayGroup
}

/// The spawns of the client's tables: each point of this module checked against
/// the rules above, or the first refusal, in the order of the points.
fn build(
  tables _tables: table_store.Tables,
) -> Result(List(Spawn), SpawnError) {
  Ok([])
}

/// The spawns as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`); a refusal fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: spawns_key, build: fn(tables) {
    build(tables:) |> result.map_error(describe)
  })
}

/// The key of the spawns in the tables' store.
const spawns_key: table_store.DerivedKey(List(Spawn)) =
  table_store.DerivedKey("Spawns")

/// The spawns the tables' load built.
pub fn all(tables tables: table_store.Tables) -> List(Spawn) {
  table_store.derived(tables:, key: spawns_key)
}

/// The spawns of one map: those in its world.
pub fn of_map(spawns spawns: List(Spawn), map map: MapId) -> List(Spawn) {
  list.filter(spawns, fn(spawn) {
    start_place.world_id(spawn.place) == map.world_id
  })
}

/// The spawn with this id, or `Error(Nil)` for none.
pub fn find(
  spawns spawns: List(Spawn),
  spawn id: SpawnId,
) -> Result(Spawn, Nil) {
  list.find(spawns, fn(spawn) { spawn.id == id })
}

/// A sentence that says why the spawns cannot be built, for the message the
/// server stops with.
fn describe(error error: SpawnError) -> String {
  case error {
    NoCreatureRow(creature_id: Creature2Id(creature_id)) ->
      "Creature2 " <> int.to_string(creature_id) <> " has no row"
    NotLoadedByTheClient(creature_id: Creature2Id(creature_id), rule:) ->
      "the client would not load Creature2 "
      <> int.to_string(creature_id)
      <> ": "
      <> describe_rule(rule)
    NoAreaRow(area: WorldLocation2Id(area)) ->
      "WorldLocation2 " <> int.to_string(area) <> " has no row"
    OutsideArea(spawn: SpawnId(spawn), area: WorldLocation2Id(area)) ->
      "spawn "
      <> int.to_string(spawn)
      <> " lies outside WorldLocation2 "
      <> int.to_string(area)
    NoDisplay(creature_id: Creature2Id(creature_id)) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> " has no display in its display group"
  }
}

/// The client's rule a creature's row fails, in words.
fn describe_rule(rule: ValidityRule) -> String {
  case rule {
    ModelScaleNotAbove0 -> "its modelScale is not above 0"
    CreationTypeNotBelow26 -> "its CreationTypeEnum is not below 26"
    NoArcheTypeRow -> "its Creature2ArcheType row does not exist"
    NoDifficultyRow -> "its Creature2Difficulty row does not exist"
    NoResistRow -> "its Creature2Resist row does not exist"
    NoDisplayGroup -> "its display group is 0"
  }
}
