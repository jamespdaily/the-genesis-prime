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
//// - **The client's validity rules** (`0x140485790`, `0x140483d20`): a Creature2
////   row is a creature the client loads only when its modelScale is above 0, its
////   CreationTypeEnum is below 26, its archetype row exists, its difficulty and
////   resist are 0 or have a row, its display group is not 0, its soldier mission
////   and instance portal are 0 or have a row, and its outfit group is 0 or has
////   entries (a 0 is taken to need no row: the training creatures hold 0, and
////   the client's lookup of 0 is not read); a spawn of a
////   row that fails them is refused, since the client would drop the 0x262. A
////   spawn whose point lies outside its circle, whose circle has no row or
////   whose creature has no display entry is refused too. Any refusal fails the
////   load.

import genesis_prime/game/start_place.{type Place, Facing}
import genesis_prime/message/float32
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/creature2_arche_type
import genesis_prime/table/creature2_difficulty
import genesis_prime/table/creature2_display_group_entry
import genesis_prime/table/creature2_display_info
import genesis_prime/table/creature2_outfit_group_entry
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/creature2_resist
import genesis_prime/table/creature2_tier
import genesis_prime/table/creature_level
import genesis_prime/table/id.{
  type Creature2Id, type WorldLocation2Id, Creature2ArcheTypeId,
  Creature2DifficultyId, Creature2DisplayInfoId, Creature2Id, Creature2ResistId,
  Creature2TierId, CreatureLevelId, InstancePortalId, PathMissionId,
  WorldLocation2Id,
}
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_mission
import genesis_prime/table/world_location2.{type WorldLocation2}
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import genesis_prime/world_map/unit_fields
import genesis_prime/world_map/warfare_woods.{type Point}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/result

/// Where a spawn's point comes from.
pub type Source {
  /// A point of Jim's world database, `spawn.tsv` row `row_id`: data the client
  /// lacks, read from a record of the retail game.
  WorldDatabase(row_id: Int)
  /// No record anywhere: the point is the offset of the world-database point
  /// `offset_of_row_id` from the Exile circle's centre, applied to this spawn's
  /// circle, a server's choice.
  NoRecord(offset_of_row_id: Int)
}

/// One creature's place and values.
pub type Spawn {
  Spawn(
    id: SpawnId,
    /// The creature's Creature2 row.
    creature_id: Creature2Id,
    /// Where the creature stands and faces: in the world and zone of its circle.
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
  /// The creature's tier or level has no row, so its Base Health has no formula.
  NoHealthRow(creature_id: Creature2Id)
  /// The circle has no WorldLocation2 row.
  NoAreaRow(area: WorldLocation2Id)
  /// The circle is in world 0, which is no World row.
  AreaInNoWorld(area: WorldLocation2Id)
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
  NoSoldierMissionRow
  NoInstancePortalRow
  NoOutfitEntries
}

/// What a creature kind stands for: the creature, the circle of its objective,
/// and whether its points are the world database's or offsets from it.
type Kind {
  Kind(creature_id: Creature2Id, area: WorldLocation2Id, recorded: Bool)
}

/// The Exile objective circle (WorldLocation2 51739), whose centre the
/// world-database points are measured from.
const exile_circle = WorldLocation2Id(51_739)

/// The creatures that stand, in the order of their spawns: the Virtual Battle
/// Beast at the world database's points, in the Exile circle, and the Virtual
/// Defense Dagun at the offsets of the same points, in the Dominion circle
/// (WorldLocation2 52898).
const kinds = [
  Kind(
    creature_id: Creature2Id(73_464),
    area: WorldLocation2Id(51_739),
    recorded: True,
  ),
  Kind(
    creature_id: Creature2Id(73_465),
    area: WorldLocation2Id(52_898),
    recorded: False,
  ),
]

/// The spawns of the client's tables: each point of `warfare_woods` for each
/// creature kind, checked against the rules above, or the first refusal, in the
/// order of the spawns.
fn build(tables tables: table_store.Tables) -> Result(List(Spawn), SpawnError) {
  use exile <- result.try(circle(tables:, area: exile_circle))
  use built <- result.try(
    list.try_fold(kinds, [], fn(built, kind) {
      use spawns <- result.map(of_kind(
        tables:,
        kind:,
        exile:,
        first_id: list.length(built) + 1,
      ))
      list.append(built, spawns)
    }),
  )
  Ok(built)
}

/// The spawns of one kind: one for each point.
fn of_kind(
  tables tables: table_store.Tables,
  kind kind: Kind,
  exile exile: WorldLocation2,
  first_id first_id: Int,
) -> Result(List(Spawn), SpawnError) {
  use row <- result.try(valid_creature(tables:, creature_id: kind.creature_id))
  use health <- result.try(base_health(tables:, row:))
  use display_info_id <- result.try(display(tables:, row:))
  use area <- result.try(circle(tables:, area: kind.area))
  warfare_woods.battle_beast_points
  |> list.index_map(fn(point, index) { #(point, SpawnId(first_id + index)) })
  |> list.try_map(fn(entry) {
    let #(point, id) = entry
    use place <- result.try(place_of(point:, kind:, area:, exile:))
    let spawn =
      Spawn(
        id:,
        creature_id: kind.creature_id,
        place:,
        area: kind.area,
        source: case kind.recorded {
          True -> WorldDatabase(row_id: point.row_id)
          False -> NoRecord(offset_of_row_id: point.row_id)
        },
        level: row.min_level,
        health:,
        faction_id: row.faction_id,
        display_info_id:,
      )
    case inside(place:, area:) {
      True -> Ok(spawn)
      False -> Error(OutsideArea(spawn: id, area: kind.area))
    }
  })
}

/// The place of a point: the world database's own for a recorded kind, else the
/// point's offset from the Exile circle's centre applied to the kind's circle.
fn place_of(
  point point: Point,
  kind kind: Kind,
  area area: WorldLocation2,
  exile exile: WorldLocation2,
) -> Result(Place, SpawnError) {
  let #(x, y, z) = case kind.recorded {
    True -> #(point.x, point.y, point.z)
    False -> #(
      area.position0 +. { point.x -. exile.position0 },
      area.position1 +. { point.y -. exile.position1 },
      area.position2 +. { point.z -. exile.position2 },
    )
  }
  start_place.place(
    world_id: area.world_id,
    world_zone_id: area.world_zone_id,
    x:,
    y:,
    z:,
    facing: Facing(yaw: point.yaw, pitch: point.pitch, roll: point.roll),
  )
  |> result.replace_error(AreaInNoWorld(area: WorldLocation2Id(area.id)))
}

/// Whether the place lies within the circle's radius of its centre.
fn inside(place place: Place, area area: WorldLocation2) -> Bool {
  let dx = start_place.x(place) -. area.position0
  let dy = start_place.y(place) -. area.position1
  let dz = start_place.z(place) -. area.position2
  dx *. dx +. dy *. dy +. dz *. dz <=. area.radius *. area.radius
}

fn circle(
  tables tables: table_store.Tables,
  area area: WorldLocation2Id,
) -> Result(WorldLocation2, SpawnError) {
  world_location2.get(tables, area) |> result.replace_error(NoAreaRow(area:))
}

/// The creature's row, when the client would load it (`0x140485790`).
fn valid_creature(
  tables tables: table_store.Tables,
  creature_id creature_id: Creature2Id,
) -> Result(Creature2, SpawnError) {
  use row <- result.try(
    creature2.get(tables, creature_id)
    |> result.replace_error(NoCreatureRow(creature_id:)),
  )
  let exists = fn(found: Result(a, Nil), id: Int) {
    id == 0 || result.is_ok(found)
  }
  let rules = [
    #(row.model_scale >. 0.0, ModelScaleNotAbove0),
    #(row.creation_type_enum < 26, CreationTypeNotBelow26),
    #(
      result.is_ok(creature2_arche_type.get(
        tables,
        Creature2ArcheTypeId(row.creature2_arche_type_id),
      )),
      NoArcheTypeRow,
    ),
    #(
      exists(
        creature2_difficulty.get(
          tables,
          Creature2DifficultyId(row.creature2_difficulty_id),
        ),
        row.creature2_difficulty_id,
      ),
      NoDifficultyRow,
    ),
    #(
      exists(
        creature2_resist.get(tables, Creature2ResistId(row.creature2_resist_id)),
        row.creature2_resist_id,
      ),
      NoResistRow,
    ),
    #(row.creature2_display_group_id != 0, NoDisplayGroup),
    // FillCreatureInfo (0x140483d20) fails the record for a soldier mission or an
    // instance portal with no row, and for an outfit group with no entries.
    #(
      exists(
        path_mission.get(tables, PathMissionId(row.path_mission_id_soldier)),
        row.path_mission_id_soldier,
      ),
      NoSoldierMissionRow,
    ),
    #(
      exists(
        instance_portal.get(tables, InstancePortalId(row.instance_portal_id)),
        row.instance_portal_id,
      ),
      NoInstancePortalRow,
    ),
    #(
      row.creature2_outfit_group_id == 0
        || list.any(creature2_outfit_group_entry.all(tables), fn(entry) {
        entry.creature2_outfit_group_id == row.creature2_outfit_group_id
      }),
      NoOutfitEntries,
    ),
  ]
  case list.find(rules, fn(rule) { !rule.0 }) {
    Ok(#(_, rule)) -> Error(NotLoadedByTheClient(creature_id:, rule:))
    Error(Nil) -> Ok(row)
  }
}

/// Base Health: the creature's own override of property 7 when it has one, else
/// CreatureLevel[level] times the archetype, difficulty and tier multipliers,
/// each product held as a 32-bit float, truncated. The client looks the three
/// multipliers up by the creature's words 4, 5 and 6, which are the archetype,
/// difficulty and tier (`0x1404585c0`, `0x1404852b0`); the order of the products is
/// that order, a reading, since the order of the multiplications is not read.
/// UnitProperty2 7's flags bit 0, which would stop the multipliers, is clear.
///
/// A difficulty id of 0 multiplies by 1.0. The client's lookup of difficulty 0
/// (`0x1401f64e0`) is not read; reading what it returns for an id with no row, and
/// whether the creature's property code skips it, would settle it. The training
/// creatures have difficulty 1.
fn base_health(
  tables tables: table_store.Tables,
  row row: Creature2,
) -> Result(Int, SpawnError) {
  let creature_id = Creature2Id(row.id)
  let overrides =
    creature2_override_properties.all(tables)
    |> list.find(fn(override) {
      override.creature2_id == row.id
      && override.unit_property_index == unit_fields.base_health_property
    })
  case overrides {
    Ok(override) -> Ok(float.truncate(override.unit_property_value))
    Error(Nil) -> {
      let found = {
        use level <- result.try(creature_level.get(
          tables,
          CreatureLevelId(row.min_level),
        ))
        use tier <- result.try(creature2_tier.get(
          tables,
          Creature2TierId(row.creature2_tier_id),
        ))
        use arche <- result.try(creature2_arche_type.get(
          tables,
          Creature2ArcheTypeId(row.creature2_arche_type_id),
        ))
        let difficulty =
          creature2_difficulty.get(
            tables,
            Creature2DifficultyId(row.creature2_difficulty_id),
          )
        let difficulty_multiplier = case difficulty {
          Ok(difficulty) -> difficulty.unit_property_multiplier007
          Error(Nil) -> 1.0
        }
        Ok(
          level.unit_property_value07
          |> times(arche.unit_property_multiplier007)
          |> times(difficulty_multiplier)
          |> times(tier.unit_property_multiplier007),
        )
      }
      case found {
        Ok(health) -> Ok(float.truncate(health))
        Error(Nil) -> Error(NoHealthRow(creature_id:))
      }
    }
  }
}

/// The product as a 32-bit float.
fn times(left: Float, right: Float) -> Float {
  float32.rounded(left *. right)
}

/// The display the 0x262 sends: the entry of the creature's display group with
/// the greatest weight and an existing Creature2DisplayInfo, the lowest display
/// id on a tie.
fn display(
  tables tables: table_store.Tables,
  row row: Creature2,
) -> Result(Int, SpawnError) {
  creature2_display_group_entry.all(tables)
  |> list.filter(fn(entry) {
    entry.creature2_display_group_id == row.creature2_display_group_id
    && result.is_ok(creature2_display_info.get(
      tables,
      Creature2DisplayInfoId(entry.creature2_display_info_id),
    ))
  })
  |> list.sort(fn(first, second) {
    int.compare(second.weight, first.weight)
    |> order.break_tie(int.compare(
      first.creature2_display_info_id,
      second.creature2_display_info_id,
    ))
  })
  |> list.first
  |> result.map(fn(entry) { entry.creature2_display_info_id })
  |> result.replace_error(NoDisplay(creature_id: Creature2Id(row.id)))
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

/// The spawns by their id, for a lookup that is made for each creature started.
pub fn index(spawns spawns: List(Spawn)) -> Dict(SpawnId, Spawn) {
  list.map(spawns, fn(spawn) { #(spawn.id, spawn) }) |> dict.from_list
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
    NoHealthRow(creature_id: Creature2Id(creature_id)) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> " has no CreatureLevel or Creature2Tier row for its Base Health"
    NoAreaRow(area: WorldLocation2Id(area)) ->
      "WorldLocation2 " <> int.to_string(area) <> " has no row"
    AreaInNoWorld(area: WorldLocation2Id(area)) ->
      "WorldLocation2 " <> int.to_string(area) <> " is in world 0"
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
    NoSoldierMissionRow -> "its pathMissionIdSoldier row does not exist"
    NoInstancePortalRow -> "its instancePortalId row does not exist"
    NoOutfitEntries -> "its outfit group has no entries"
  }
}
