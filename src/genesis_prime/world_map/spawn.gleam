//// The spawns a map stands creatures at: one spawn is one place a creature of the
//// client's Creature2 table stands at, with the values its 0x262 carries. The rows
//// come from the server's `spawn` table (genesis_prime/content/spawn), which holds
//// every place the world database records; this module is the pure part: the
//// client's checks of a row, the selection of the rows that start as fight
//// creatures, and the shape a world's spawns are kept in.
////
//// ```
//// the spawn table (one query, at start) ─▶ Row ─▶ load checks (the client's validity rules)
////                                                 ─▶ selection (who a player can attack)
////                                                 ─▶ Spawn, one WorldSpawns term for each world
//// a map's start    ─▶ reads its world's WorldSpawns: no copy, no query
//// a player's move  ─▶ spawn_cell.near ─▶ exact sight ─▶ the spawns it sees
//// ```
////
//// - **What starts.** A row of entity type 0 (NonPlayer, the unit type of message
////   0x262: `world_data.entity_type`, `0x140649e20`) with a faction, that is not
////   Friendly to both player factions, whose Creature2 row has no quest, trainer,
////   station, taxi, bind or portal link, and whose health stat is not 0; a row
////   with no stats is kept. The client lets a player attack a Hostile or a Neutral
////   unit and not a Friendly one (`0x1403ad540`), and a faction's level to a
////   player faction walks the faction's parents (`0x140787760`, `0x140717560`,
////   Faction2Relationship). Every other row is counted for the coverage measure.
//// - **What fails the load.** A row whose creature has no Creature2 row, or fails
////   the client's validity rules (`0x140485790`, `0x140483d20`), or whose display
////   is not in its creature's display group or has no Creature2DisplayInfo row:
////   the client would drop the 0x262 or show no model.
//// - **The creature's values.** Health is stat 0, truncated, and level is stat 10;
////   a row with no stats takes the creature's `minLevel` and Base Health by the
////   client's formula (`0x1404585c0`). Faction, base faction, display and outfit are
////   the row's own (`opcode.0x262.creature`): the client's weighted display pick
////   runs only for the spawns it makes itself (`0x1404846c0`).
//// - **A level outside its row's range** is kept and listed in an info line.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/start_place.{type Place}
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
  type Creature2Id, Creature2ArcheTypeId, Creature2DifficultyId,
  Creature2DisplayInfoId, Creature2Id, Creature2ResistId, Creature2TierId,
  CreatureLevelId, InstancePortalId, PathMissionId,
}
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_mission
import genesis_prime/world_map/spawn_cell.{type Cells}
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import genesis_prime/world_map/unit_fields
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// One row of the spawn table as the load reads it: the values of the row, and
/// its health and level stats when it has them. Positions and rotations are
/// 32-bit floats.
pub type Row {
  Row(
    id: SpawnId,
    entity_type: Int,
    creature_id: Int,
    world_id: Int,
    area_id: Int,
    x: Float,
    y: Float,
    z: Float,
    rotation_x: Float,
    rotation_y: Float,
    rotation_z: Float,
    display_info_id: Int,
    outfit_info_id: Int,
    faction_id: Int,
    base_faction_id: Int,
    health: Option(Float),
    level: Option(Float),
  )
}

/// One creature's place and values, as its 0x262 carries them, so the 0x262
/// needs no table at run time.
pub type Spawn {
  Spawn(
    /// The spawn table's id, the spawn's number for the run.
    id: SpawnId,
    /// The creature's Creature2 row.
    creature_id: Creature2Id,
    /// Where the creature stands and faces, in the row's world and area.
    place: Place,
    /// Stat 10.
    level: Int,
    /// Stat 0, truncated.
    health: Int,
    /// The faction the 0x262 sends (the row's `faction_id`).
    faction_id: Int,
    /// The base faction the 0x262 sends.
    base_faction_id: Int,
    /// The Creature2DisplayInfo the 0x262 sends.
    display_info_id: Int,
    /// The Creature2OutfitInfo the 0x262 sends, 0 for none.
    outfit_info_id: Int,
  )
}

/// The spawns that start in one world, as the persistent term of the world holds
/// them (genesis_prime/content/spawn): by id, for a creature's start, and by
/// cell, for a player's move. A map and a creature read it and keep no copy.
pub type WorldSpawns {
  WorldSpawns(by_id: Dict(SpawnId, Spawn), cells: Cells)
}

/// A world with no spawn.
pub fn no_spawns() -> WorldSpawns {
  WorldSpawns(by_id: dict.new(), cells: spawn_cell.empty())
}

/// What the selection found: the spawns that start, in a `WorldSpawns` for each
/// world that has any, the rows the load refuses, the spawns whose level lies
/// outside their row's range, and the coverage of each world.
pub type Selection {
  Selection(
    worlds: Dict(Int, WorldSpawns),
    refusals: List(Refusal),
    out_of_range_levels: List(SpawnId),
    coverage: List(WorldCoverage),
  )
}

/// Why a NonPlayer row does not start.
pub type LeftOut {
  /// Faction 0: the client sees no faction, and a 0x262 with none fails
  /// (`opcode.0x262`).
  NoFaction
  /// Friendly to both player factions.
  FriendlyToBoth
  /// The creature's row has a quest, trainer, station, taxi, bind or portal link.
  NpcLink
  /// Health stat 0: the client creates the unit dead (`opcode.0x262.creature`).
  Dead
}

/// What one world has of the client's tables' spawns, the coverage measure: how
/// many start, how many NonPlayer rows are left out and why, and how many rows
/// there are of every other entity type, by type.
pub type WorldCoverage {
  WorldCoverage(
    world_id: Int,
    started: Int,
    left_out: List(#(LeftOut, Int)),
    other_types: List(#(Int, Int)),
  )
}

/// Why a row fails the load.
type SpawnError {
  /// The creature has no Creature2 row.
  NoCreatureRow(creature_id: Creature2Id)
  /// The client would not load the creature's row (`0x140485790`).
  NotLoadedByTheClient(creature_id: Creature2Id, rule: ValidityRule)
  /// The creature's tier or level has no row, so its Base Health has no formula.
  NoHealthRow(creature_id: Creature2Id)
  /// The row's display is not in its creature's display group.
  DisplayNotInGroup(creature_id: Creature2Id, display_info_id: Int)
  /// The row's display has no Creature2DisplayInfo row, so the creature has no
  /// model.
  NoDisplayRow(display_info_id: Int)
  /// The row's world is 0, which is no World row.
  InNoWorld
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

/// A row that passed the load checks, with the creature's values.
type Checked {
  Checked(row: Row, spawn: Spawn, creature: Creature2)
}

/// The rows of the spawn table in, the selection out: every row is checked
/// (a row that fails is a refusal, and fails the load), then the NonPlayer rows
/// that start are chosen by the rule above and the rest counted. Pure: the
/// client's tables are the only other input.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Selection {
  let checked =
    list.map(rows, fn(row) {
      load_checks(tables:, row:)
      |> result.map_error(fn(error) {
        let SpawnId(number) = row.id
        refusal.Refusal(table: "spawn", id: number, rule: describe(error:))
      })
    })
  let _checked = result.partition(checked)
  panic as "the selection rule is built after the shape's review"
}

/// The checks the client makes of one row: its creature loads and its display
/// is one of the creature's, and its health and level are the stats' or the
/// creature's own.
fn load_checks(
  tables tables: table_store.Tables,
  row row: Row,
) -> Result(Checked, SpawnError) {
  let creature_id = Creature2Id(row.creature_id)
  use creature <- result.try(valid_creature(tables:, creature_id:))
  use place <- result.try(
    start_place.place(
      world_id: row.world_id,
      world_zone_id: row.area_id,
      x: row.x,
      y: row.y,
      z: row.z,
      facing: start_place.Facing(
        yaw: row.rotation_x,
        pitch: row.rotation_y,
        roll: row.rotation_z,
      ),
    )
    |> result.replace_error(InNoWorld),
  )
  use health <- result.try(case row.health {
    Some(stat) -> Ok(float.truncate(stat))
    None -> base_health(tables:, row: creature)
  })
  let level = case row.level {
    Some(stat) -> float.truncate(stat)
    None -> creature.min_level
  }
  use _in_group <- result.try(display_in_group(
    tables:,
    creature:,
    display_info_id: row.display_info_id,
  ))
  Ok(Checked(
    row:,
    creature:,
    spawn: Spawn(
      id: row.id,
      creature_id:,
      place:,
      level:,
      health:,
      faction_id: row.faction_id,
      base_faction_id: row.base_faction_id,
      display_info_id: row.display_info_id,
      outfit_info_id: row.outfit_info_id,
    ),
  ))
}

/// The row's display is an entry of the creature's display group and has a
/// Creature2DisplayInfo row.
fn display_in_group(
  tables tables: table_store.Tables,
  creature creature: Creature2,
  display_info_id display_info_id: Int,
) -> Result(Nil, SpawnError) {
  let in_group =
    list.any(creature2_display_group_entry.all(tables), fn(entry) {
      entry.creature2_display_group_id == creature.creature2_display_group_id
      && entry.creature2_display_info_id == display_info_id
    })
  use <- bool.guard(
    when: !in_group,
    return: Error(DisplayNotInGroup(
      creature_id: Creature2Id(creature.id),
      display_info_id:,
    )),
  )
  creature2_display_info.get(tables, Creature2DisplayInfoId(display_info_id))
  |> result.replace(Nil)
  |> result.replace_error(NoDisplayRow(display_info_id:))
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

/// A sentence that says why a row fails the load, for the log and the message the
/// start stops with.
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
    DisplayNotInGroup(creature_id: Creature2Id(creature_id), display_info_id:) ->
      "display "
      <> int.to_string(display_info_id)
      <> " is not in the display group of Creature2 "
      <> int.to_string(creature_id)
    NoDisplayRow(display_info_id:) ->
      "Creature2DisplayInfo " <> int.to_string(display_info_id) <> " has no row"
    InNoWorld -> "its world is 0, which is no World row"
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
