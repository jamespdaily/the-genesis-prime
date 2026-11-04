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
//// - **What fails the load.** A NonPlayer row whose creature has no Creature2 row,
////   or fails the client's validity rules (`0x140485790`, `0x140483d20`), or whose
////   display is not in its creature's display group or has no Creature2DisplayInfo
////   row, or whose outfit has no Creature2OutfitInfo row: the client would drop the
////   0x262 or show no model.
//// - **The creature's values.** Health is stat 0, truncated, and level is stat 10;
////   a row with no stats takes the creature's `minLevel` and Base Health by the
////   client's formula (`0x1404585c0`). Faction, base faction, display and outfit are
////   the row's own (`opcode.0x262.creature`): the client's weighted display pick
////   runs only for the spawns it makes itself (`0x1404846c0`).
//// - **A level outside its row's range** is kept and listed in an info line.
//// - **The creature's body** (`body_of`) is what a fight reads of it: its health, the
////   hit radius of its display (Creature2DisplayInfo.hitRadius), its faction levels
////   toward the two player factions (`faction_levels`), its deflect chance
////   (`0x140463340`, from its CreatureLevel row and its archetype, difficulty and tier
////   multipliers, `Creature2.73464.crit_deflect_glance`) and its kind's respawn time.

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/float32
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/creature2_arche_type
import genesis_prime/table/creature2_difficulty
import genesis_prime/table/creature2_display_group_entry
import genesis_prime/table/creature2_display_info
import genesis_prime/table/creature2_outfit_group_entry
import genesis_prime/table/creature2_outfit_info
import genesis_prime/table/creature2_override_properties
import genesis_prime/table/creature2_resist
import genesis_prime/table/creature2_tier
import genesis_prime/table/creature_level
import genesis_prime/table/faction2
import genesis_prime/table/faction2_relationship
import genesis_prime/table/id.{
  type Creature2Id, Creature2ArcheTypeId, Creature2DifficultyId,
  Creature2DisplayInfoId, Creature2Id, Creature2OutfitInfoId, Creature2ResistId,
  Creature2TierId, CreatureLevelId, InstancePortalId, PathMissionId,
}
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_mission
import genesis_prime/table/world
import genesis_prime/world_map/creature_kind.{type Kind}
import genesis_prime/world_map/creature_life.{type Body}
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
import gleam/set.{type Set}
import gleam/string

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

/// The spawns as a world's term holds them: by id and by cell.
pub fn world_spawns(spawns spawns: List(Spawn)) -> WorldSpawns {
  WorldSpawns(
    by_id: dict.from_list(list.map(spawns, fn(spawn) { #(spawn.id, spawn) })),
    cells: spawn_cell.index(
      list.map(spawns, fn(spawn) {
        #(spawn.id, start_place.x(spawn.place), start_place.z(spawn.place))
      }),
    ),
  )
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
  /// The row's outfit is not 0 and has no Creature2OutfitInfo row.
  NoOutfitRow(outfit_info_id: Int)
  /// The row's world has no row in the client's World table (world 0 has none).
  InNoWorld(world_id: Int)
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

/// What the checks and the selection read of the client's tables by something
/// other than a row's id, built once for a load so no check scans a table for
/// each of the 77,794 rows: each creature's override of Base Health, the display
/// ids of each display group, the outfit groups that have entries, each
/// faction's parent, and the level of each pair of factions that has a
/// relationship, filed under both orders as the client files it.
type Catalog {
  Catalog(
    tables: table_store.Tables,
    overrides: Dict(Int, Float),
    display_groups: Dict(Int, Set(Int)),
    outfit_groups: Set(Int),
    parents: Dict(Int, Int),
    levels: Dict(#(Int, Int), Int),
    worlds: Set(Int),
  )
}

/// The Exile and Dominion player factions, children of faction 165
/// (`0x140787760`).
const exile_faction = 167

const dominion_faction = 166

/// The highest level the client calls Neutral; a level above it is Friendly
/// (FactionDispositionFromLevel: 0 to 2 Hostile, 3 to 7 Neutral, 8 to 10
/// Friendly, `world_data.creature_disposition`).
const highest_neutral_level = 7

/// The rows of the spawn table in, the selection out: every NonPlayer row is
/// checked (a row that fails is a refusal, and fails the load), then the rows that
/// start are chosen by the rule above and the rest counted, for each world; every
/// other entity type is counted. Pure: the client's tables are the only other
/// input, and `tables` holds the faction tables as well as the creature ones.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
) -> Selection {
  let catalog = catalog(tables:)
  let judged =
    list.map(rows, fn(row) {
      case row.entity_type == non_player {
        False -> Other(row:)
        True ->
          case load_checks(catalog:, row:) {
            Error(error) -> {
              let SpawnId(number) = row.id
              Refused(refusal.Refusal(
                table: "spawn",
                id: number,
                rule: describe(error:),
              ))
            }
            Ok(checked) ->
              case left_out_of(catalog:, checked:) {
                Ok(reason) -> Excluded(row:, reason:)
                Error(Nil) -> Started(checked:)
              }
          }
      }
    })
  let started =
    list.filter_map(judged, fn(one) {
      case one {
        Started(checked:) -> Ok(checked)
        Other(..) | Excluded(..) | Refused(..) -> Error(Nil)
      }
    })
  Selection(
    worlds: worlds_of(started, catalog.worlds),
    refusals: list.filter_map(judged, fn(one) {
      case one {
        Refused(refusal) -> Ok(refusal)
        Other(..) | Excluded(..) | Started(..) -> Error(Nil)
      }
    }),
    out_of_range_levels: list.filter_map(started, fn(checked) {
      case
        checked.spawn.level < checked.creature.min_level
        || checked.spawn.level > checked.creature.max_level
      {
        True -> Ok(checked.spawn.id)
        False -> Error(Nil)
      }
    }),
    coverage: coverage_of(judged),
  )
}

/// Message 0x262's unit type of a NonPlayer unit (`0x140649e20`).
const non_player = 0

/// What the selection found of one row.
type Judged {
  /// A row of another entity type, counted and nothing else.
  Other(row: Row)
  /// A NonPlayer row the load refuses.
  Refused(Refusal)
  /// A NonPlayer row left out, for a reason.
  Excluded(row: Row, reason: LeftOut)
  /// A NonPlayer row that starts.
  Started(checked: Checked)
}

/// The tables' lookups by something other than an id, built once.
fn catalog(tables tables: table_store.Tables) -> Catalog {
  let relationships = faction2_relationship.all(tables)
  Catalog(
    tables:,
    overrides: list.fold(
      creature2_override_properties.all(tables),
      dict.new(),
      fn(found, override) {
        case override.unit_property_index == unit_fields.base_health_property {
          True ->
            dict.insert(
              found,
              override.creature2_id,
              override.unit_property_value,
            )
          False -> found
        }
      },
    ),
    display_groups: list.fold(
      creature2_display_group_entry.all(tables),
      dict.new(),
      fn(found, entry) {
        dict.upsert(found, entry.creature2_display_group_id, fn(held) {
          set.insert(
            option.unwrap(held, set.new()),
            entry.creature2_display_info_id,
          )
        })
      },
    ),
    outfit_groups: list.fold(
      creature2_outfit_group_entry.all(tables),
      set.new(),
      fn(found, entry) { set.insert(found, entry.creature2_outfit_group_id) },
    ),
    parents: list.fold(faction2.all(tables), dict.new(), fn(found, faction) {
      dict.insert(found, faction.id, faction.faction2_id_parent)
    }),
    worlds: set.from_list(list.map(world.all(tables), fn(row) { row.id })),
    levels: list.fold(relationships, dict.new(), fn(found, relationship) {
      found
      |> dict.insert(
        #(relationship.faction_id0, relationship.faction_id1),
        relationship.faction_level,
      )
      |> dict.insert(
        #(relationship.faction_id1, relationship.faction_id0),
        relationship.faction_level,
      )
    }),
  )
}

/// A faction and its parents, nearest first: the chain the client walks
/// (`0x140717560`). A faction with no parent, a parent that is 0 and a parent
/// already met end it, so a cycle cannot loop.
fn lineage(catalog catalog: Catalog, faction faction: Int) -> List(Int) {
  lineage_loop(catalog:, faction:, met: [])
}

fn lineage_loop(
  catalog catalog: Catalog,
  faction faction: Int,
  met met: List(Int),
) -> List(Int) {
  case faction == 0 || list.contains(met, faction) {
    True -> list.reverse(met)
    False ->
      lineage_loop(
        catalog:,
        faction: dict.get(catalog.parents, faction) |> result.unwrap(0),
        met: [faction, ..met],
      )
  }
}

/// A faction's level, 0 to 10, toward another (GetFactionLevelTo `0x140787760`,
/// the reputation a player's faction may carry aside): for the other faction and
/// then each of its parents, the first relationship it has with this faction or,
/// failing that, with any of this faction's parents in turn; with none, 10 when
/// the other is this faction and 5 otherwise.
fn faction_level(
  catalog catalog: Catalog,
  from this: Int,
  to other: Int,
) -> Int {
  let own = lineage(catalog:, faction: this)
  let found =
    list.find_map(lineage(catalog:, faction: other), fn(candidate) {
      list.find_map(own, fn(relative) {
        dict.get(catalog.levels, #(relative, candidate))
      })
    })
  case found {
    Ok(level) -> level
    Error(Nil) ->
      case this == other {
        True -> 10
        False -> 5
      }
  }
}

/// A faction's level toward the Exile player faction and toward the Dominion one,
/// as the client gives them (`faction_level`): 0 to 2 Hostile, 3 to 7 Neutral, 8 to
/// 10 Friendly. The levels a row's selection and the planted-rows guard assert.
pub fn faction_levels(
  tables tables: table_store.Tables,
  faction faction: Int,
) -> #(Int, Int) {
  let catalog = catalog(tables:)
  #(
    faction_level(catalog:, from: exile_faction, to: faction),
    faction_level(catalog:, from: dominion_faction, to: faction),
  )
}

/// Why a creature's body cannot be worked out.
pub type BodyError {
  /// A table row the body names is missing: the table, and the id.
  NoBodyRow(table: String, id: Int)
}

/// The creature's body at `spawn` with its kind's respawn time, from the loaded
/// tables: the spawn's health, the hit radius of its display, its faction levels and
/// its deflect chance.
pub fn body_of(
  tables tables: table_store.Tables,
  spawn spawn: Spawn,
  kind kind: Kind,
) -> Result(Body, BodyError) {
  unbuilt(inputs: #(tables, spawn, kind))
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}

/// Whether a player of the faction may attack a unit of the other: the unit is
/// not Friendly to it (`0x1403ad540`: a Friendly target is refused, a Hostile or a
/// Neutral one is not).
fn attackable_by(
  catalog catalog: Catalog,
  player player: Int,
  unit unit: Int,
) -> Bool {
  faction_level(catalog:, from: player, to: unit) <= highest_neutral_level
}

/// The reason a row that passed the load checks does not start, or `Error(Nil)`
/// for a row that does, in the order of the decode: no faction, Friendly to both
/// player factions, an NPC link, health 0.
fn left_out_of(
  catalog catalog: Catalog,
  checked checked: Checked,
) -> Result(LeftOut, Nil) {
  let row = checked.row
  case
    row.faction_id == 0,
    attackable_by(catalog:, player: exile_faction, unit: row.faction_id)
    || attackable_by(catalog:, player: dominion_faction, unit: row.faction_id),
    has_npc_link(checked.creature),
    checked.spawn.health == 0
  {
    True, _, _, _ -> Ok(NoFaction)
    False, False, _, _ -> Ok(FriendlyToBoth)
    False, True, True, _ -> Ok(NpcLink)
    False, True, False, True -> Ok(Dead)
    False, True, False, False -> Error(Nil)
  }
}

/// Whether the creature gives or receives a quest, trains a class or a
/// tradeskill, is a tradeskill station, or links to a taxi, a bind point or an
/// instance portal: the columns the client reads for a unit's services, which wait
/// for their own systems.
fn has_npc_link(row: Creature2) -> Bool {
  list.any(
    [
      row.trainer_class_id_mask,
      row.trade_skill_id_trainer,
      row.trade_skill_id_station,
      row.taxi_node_id,
      row.bind_point_id,
      row.instance_portal_id,
      row.quest_id_given00,
      row.quest_id_given01,
      row.quest_id_given02,
      row.quest_id_given03,
      row.quest_id_given04,
      row.quest_id_given05,
      row.quest_id_given06,
      row.quest_id_given07,
      row.quest_id_given08,
      row.quest_id_given09,
      row.quest_id_given10,
      row.quest_id_given11,
      row.quest_id_given12,
      row.quest_id_given13,
      row.quest_id_given14,
      row.quest_id_given15,
      row.quest_id_given16,
      row.quest_id_given17,
      row.quest_id_given18,
      row.quest_id_given19,
      row.quest_id_given20,
      row.quest_id_given21,
      row.quest_id_given22,
      row.quest_id_given23,
      row.quest_id_given24,
      row.quest_id_receive00,
      row.quest_id_receive01,
      row.quest_id_receive02,
      row.quest_id_receive03,
      row.quest_id_receive04,
      row.quest_id_receive05,
      row.quest_id_receive06,
      row.quest_id_receive07,
      row.quest_id_receive08,
      row.quest_id_receive09,
      row.quest_id_receive10,
      row.quest_id_receive11,
      row.quest_id_receive12,
      row.quest_id_receive13,
      row.quest_id_receive14,
      row.quest_id_receive15,
      row.quest_id_receive16,
      row.quest_id_receive17,
      row.quest_id_receive18,
      row.quest_id_receive19,
      row.quest_id_receive20,
      row.quest_id_receive21,
      row.quest_id_receive22,
      row.quest_id_receive23,
      row.quest_id_receive24,
    ],
    fn(column) { column != 0 },
  )
}

/// The started spawns by world, each world's with its cell index, and an empty
/// `WorldSpawns` for every other world of the client's World table.
fn worlds_of(
  started: List(Checked),
  worlds: Set(Int),
) -> Dict(Int, WorldSpawns) {
  let started_worlds =
    list.group(started, fn(checked) {
      start_place.world_id(checked.spawn.place)
    })
    |> dict.map_values(fn(_world, checked) {
      world_spawns(spawns: list.map(checked, fn(one) { one.spawn }))
    })
  set.fold(worlds, dict.new(), fn(found, world_id) {
    dict.insert(found, world_id, no_spawns())
  })
  |> dict.merge(started_worlds)
}

/// The coverage of each world that has a row, in world order: how many rows
/// start, how many NonPlayer rows are left out and why, how many are refused, and
/// how many rows each other entity type has.
fn coverage_of(judged: List(Judged)) -> List(WorldCoverage) {
  let by_world =
    list.group(judged, fn(one) {
      case one {
        Other(row:) | Excluded(row:, ..) -> row.world_id
        Started(checked:) -> checked.row.world_id
        Refused(..) -> 0
      }
    })
  dict.to_list(by_world)
  |> list.filter(fn(entry) { entry.0 != 0 })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(entry) {
    let #(world_id, ones) = entry
    WorldCoverage(
      world_id:,
      started: list.count(ones, fn(one) {
        case one {
          Started(..) -> True
          Other(..) | Excluded(..) | Refused(..) -> False
        }
      }),
      left_out: list.map([NoFaction, FriendlyToBoth, NpcLink, Dead], fn(reason) {
        #(
          reason,
          list.count(ones, fn(one) {
            case one {
              Excluded(reason: held, ..) -> held == reason
              Other(..) | Started(..) | Refused(..) -> False
            }
          }),
        )
      }),
      other_types: list.filter_map(ones, fn(one) {
        case one {
          Other(row:) -> Ok(row.entity_type)
          Excluded(..) | Started(..) | Refused(..) -> Error(Nil)
        }
      })
        |> list.group(fn(entity_type) { entity_type })
        |> dict.map_values(fn(_type, found) { list.length(found) })
        |> dict.to_list
        |> list.sort(fn(first, second) { int.compare(first.0, second.0) }),
    )
  })
}

/// The checks the client makes of one row: its creature loads and its display
/// is one of the creature's, and its health and level are the stats' or the
/// creature's own.
fn load_checks(
  catalog catalog: Catalog,
  row row: Row,
) -> Result(Checked, SpawnError) {
  let creature_id = Creature2Id(row.creature_id)
  use creature <- result.try(valid_creature(catalog:, creature_id:))
  use <- bool.guard(
    when: !set.contains(catalog.worlds, row.world_id),
    return: Error(InNoWorld(world_id: row.world_id)),
  )
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
    |> result.replace_error(InNoWorld(world_id: row.world_id)),
  )
  use health <- result.try(case row.health {
    Some(stat) -> Ok(float.truncate(stat))
    None -> base_health(catalog:, row: creature)
  })
  let level = case row.level {
    Some(stat) -> float.truncate(stat)
    None -> creature.min_level
  }
  use _in_group <- result.try(display_in_group(
    catalog:,
    creature:,
    display_info_id: row.display_info_id,
  ))
  use _outfit <- result.try(outfit_exists(
    catalog:,
    outfit_info_id: row.outfit_info_id,
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

/// The row's outfit is 0, or has a Creature2OutfitInfo row.
fn outfit_exists(
  catalog catalog: Catalog,
  outfit_info_id outfit_info_id: Int,
) -> Result(Nil, SpawnError) {
  use <- bool.guard(when: outfit_info_id == 0, return: Ok(Nil))
  creature2_outfit_info.get(
    catalog.tables,
    Creature2OutfitInfoId(outfit_info_id),
  )
  |> result.replace(Nil)
  |> result.replace_error(NoOutfitRow(outfit_info_id:))
}

/// The row's display is an entry of the creature's display group and has a
/// Creature2DisplayInfo row.
fn display_in_group(
  catalog catalog: Catalog,
  creature creature: Creature2,
  display_info_id display_info_id: Int,
) -> Result(Nil, SpawnError) {
  let in_group =
    dict.get(catalog.display_groups, creature.creature2_display_group_id)
    |> result.map(set.contains(_, display_info_id))
    |> result.unwrap(False)
  use <- bool.guard(
    when: !in_group,
    return: Error(DisplayNotInGroup(
      creature_id: Creature2Id(creature.id),
      display_info_id:,
    )),
  )
  creature2_display_info.get(
    catalog.tables,
    Creature2DisplayInfoId(display_info_id),
  )
  |> result.replace(Nil)
  |> result.replace_error(NoDisplayRow(display_info_id:))
}

/// The creature's row, when the client would load it (`0x140485790`).
fn valid_creature(
  catalog catalog: Catalog,
  creature_id creature_id: Creature2Id,
) -> Result(Creature2, SpawnError) {
  let tables = catalog.tables
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
        || set.contains(catalog.outfit_groups, row.creature2_outfit_group_id),
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
  catalog catalog: Catalog,
  row row: Creature2,
) -> Result(Int, SpawnError) {
  let tables = catalog.tables
  let creature_id = Creature2Id(row.id)
  case dict.get(catalog.overrides, row.id) {
    Ok(value) -> Ok(float.truncate(value))
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

/// One line of the coverage of a world, for the log at start and for the coverage
/// tool: how many spawns start, how many NonPlayer rows are left out and why, and
/// how many rows each other entity type has.
pub fn describe_coverage(coverage coverage: WorldCoverage) -> String {
  "world "
  <> int.to_string(coverage.world_id)
  <> ": "
  <> int.to_string(coverage.started)
  <> " spawns start; left out: "
  <> string.join(
    list.map(coverage.left_out, fn(entry) {
      describe_left_out(entry.0) <> " " <> int.to_string(entry.1)
    }),
    ", ",
  )
  <> "; other entity types: "
  <> case coverage.other_types {
    [] -> "none"
    types ->
      string.join(
        list.map(types, fn(entry) {
          "type " <> int.to_string(entry.0) <> " " <> int.to_string(entry.1)
        }),
        ", ",
      )
  }
}

fn describe_left_out(reason: LeftOut) -> String {
  case reason {
    NoFaction -> "no faction"
    FriendlyToBoth -> "friendly to both"
    NpcLink -> "an NPC link"
    Dead -> "health 0"
  }
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
    NoOutfitRow(outfit_info_id:) ->
      "Creature2OutfitInfo " <> int.to_string(outfit_info_id) <> " has no row"
    InNoWorld(world_id:) -> "World " <> int.to_string(world_id) <> " has no row"
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
