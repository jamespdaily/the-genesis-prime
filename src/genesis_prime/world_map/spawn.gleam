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
//// - **Static objects.** A row of entity type 10, 11 or 32 is a static object
////   (genesis_prime/world_map/static_object), checked as a NonPlayer row is and
////   kept whatever its faction. Types 10 and 11 carry the stats the row records
////   and no other, since the client never creates them dead (the trace's field
////   table); type 32 takes a creature's level and health by the rule below, and
////   one with health 0 is left out and counted, since the client would create it
////   dead (`0x140457a53`, opcode.0x262.simple).
//// - **What fails the load.** A NonPlayer or static object row whose creature has no Creature2 row,
////   or fails the client's validity rules (`0x140485790`, `0x140483d20`), or whose
////   display is not in its creature's display group or has no Creature2DisplayInfo
////   row, or whose outfit has no Creature2OutfitInfo row: the client would drop the
////   0x262 or show no model.
//// - **The creature's values.** Level is the row's stat 10, or the creature's
////   `minLevel` for a row with none. Health, stat 0 and the maximum, is the row's
////   recorded stat 0 truncated, sent as stat 0 and as property 7, Base Health, so
////   the client's bar agrees (`opcode.0x262.creature`: the property list sets
////   property 7, the client's own number being only the default). The recorded value
////   is a retail record, used where the client lacks the number of each spawn's
////   health (`world_data.spawn_health`: it differs from the client's formula for
////   nearly every spawn). A row with no recorded health has the client's Base Health
////   at that level (`0x1404585c0`, which reads the message's stat 10:
////   `opcode.0x262.creature_level`), which a 0x262 leaves to the client. A creature
////   stands, and comes back, at that value. Faction, base faction, display and outfit are
////   the row's own (`opcode.0x262.creature`): the client's weighted display pick
////   runs only for the spawns it makes itself (`0x1404846c0`).
//// - **A level outside its row's range** is kept and listed in an info line.
//// - **What a creature brings to a fight** (`Combat`) is worked out here with the rest of
////   its values: the hit radius of its display (Creature2DisplayInfo.hitRadius), whom it
////   may be attacked by (a faction level toward each player faction of 7 or less,
////   `0x1403ad540`) and its defence: deflect, critical deflect, glance and mitigation
////   from its CreatureLevel rows and its archetype, difficulty and tier multipliers
////   (`0x1404585c0`, `Creature2.73464.crit_deflect_glance`,
////   `Creature2.73464.mitigation`) through the rating formulas
////   (genesis_prime/game/rating). It also holds whom the creature fights on sight (a
////   faction level of 0 to 2 toward each player faction) and its own attack, from its
////   kind's spell (genesis_prime/world_map/creature_kind,
////   genesis_prime/world_map/creature_life `Attack`).

import genesis_prime/content/refusal.{type Refusal}
import genesis_prime/game/damage
import genesis_prime/game/hit
import genesis_prime/game/hit_radius
import genesis_prime/game/rating.{type Formulas}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/float32
import genesis_prime/table/creature2.{type Creature2}
import genesis_prime/table/creature2_arche_type
import genesis_prime/table/creature2_difficulty.{type Creature2Difficulty}
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
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type Creature2Id, type UnitProperty2Id, Creature2ArcheTypeId,
  Creature2DifficultyId, Creature2DisplayInfoId, Creature2Id, Creature2ResistId,
  Creature2TierId, CreatureLevelId, InstancePortalId, PathMissionId,
}
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_mission
import genesis_prime/table/spell4
import genesis_prime/table/world
import genesis_prime/world_map/creature_attack
import genesis_prime/world_map/creature_kind.{type Kind, type Kinds}
import genesis_prime/world_map/creature_life.{
  type Attack, type Combat, Attackable, Combat, Hostile,
}
import genesis_prime/world_map/spawn_cell.{type Cells}
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import genesis_prime/world_map/spawn_source.{type Summoned, Summoned}
import genesis_prime/world_map/static_object.{type StaticObject}
import genesis_prime/world_map/unit_fields.{
  type HealthSource, ClientDefault, Recorded,
}
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
    checklist_index: Int,
    world_object_id: Int,
    world_socket_id: Int,
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
    /// Stat 10: the row's recorded level, or the creature's `minLevel`.
    level: Int,
    /// Stat 0, and the creature's maximum health: the row's recorded health, or
    /// else its Base Health at `level` (`base_health`). A creature stands, and
    /// comes back, at full health.
    health: Int,
    /// Where `health` comes from, and so whether the 0x262 sends it as property 7.
    health_source: HealthSource,
    /// The faction the 0x262 sends (the row's `faction_id`).
    faction_id: Int,
    /// The base faction the 0x262 sends.
    base_faction_id: Int,
    /// The Creature2DisplayInfo the 0x262 sends.
    display_info_id: Int,
    /// The Creature2OutfitInfo the 0x262 sends, 0 for none.
    outfit_info_id: Int,
    /// What the creature brings to a fight.
    combat: Combat,
    /// The base of each UnitProperty2 id for the creature at `level`, which its
    /// properties start from at each life (genesis_prime/game/unit_properties
    /// `of_creature`).
    bases: List(#(UnitProperty2Id, Float)),
  )
}

/// The spawns that start in one world, as the persistent term of the world holds
/// them (genesis_prime/content/spawn): the creatures by id, for a creature's
/// start, the static objects by id, and both by cell, for a player's move, so one
/// `spawn_cell.near` finds the two. A map and a creature read it and keep no copy.
pub type WorldSpawns {
  WorldSpawns(
    by_id: Dict(SpawnId, Spawn),
    objects: Dict(SpawnId, StaticObject),
    cells: Cells,
  )
}

/// The spawns as a world's term holds them: the creatures and the static objects
/// by id, and both by cell.
pub fn world_spawns(
  spawns spawns: List(Spawn),
  objects objects: List(StaticObject),
) -> WorldSpawns {
  WorldSpawns(
    by_id: dict.from_list(list.map(spawns, fn(spawn) { #(spawn.id, spawn) })),
    objects: dict.from_list(
      list.map(objects, fn(object) { #(object.id, object) }),
    ),
    cells: spawn_cell.index(list.append(
      list.map(spawns, fn(spawn) {
        #(spawn.id, start_place.x(spawn.place), start_place.z(spawn.place))
      }),
      list.map(objects, fn(object) {
        #(object.id, start_place.x(object.place), start_place.z(object.place))
      }),
    )),
  )
}

/// A world with no spawn.
pub fn no_spawns() -> WorldSpawns {
  WorldSpawns(by_id: dict.new(), objects: dict.new(), cells: spawn_cell.empty())
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
/// many start, how many NonPlayer rows are left out and why, how many static
/// objects are sent, by type, and how many are left out because the client
/// would create them dead, and how many rows there are of every other entity
/// type, by type.
pub type WorldCoverage {
  WorldCoverage(
    world_id: Int,
    started: Int,
    left_out: List(#(LeftOut, Int)),
    objects_sent: List(#(static_object.UnitType, Int)),
    objects_dead: Int,
    other_types: List(#(Int, Int)),
  )
}

/// Why a row fails the load.
pub type SpawnError {
  /// The creature has no Creature2 row.
  NoCreatureRow(creature_id: Creature2Id)
  /// The client would not load the creature's row (`0x140485790`).
  NotLoadedByTheClient(creature_id: Creature2Id, rule: ValidityRule)
  /// A row a creature's Base Health or defence reads is missing: the table and the id.
  NoPropertyRow(creature_id: Creature2Id, table: String, id: Int)
  /// A property the load is asked for is not one it builds.
  PropertyNotBuilt(creature_id: Creature2Id, property: Int)
  /// The row's display is not in its creature's display group.
  DisplayNotInGroup(creature_id: Creature2Id, display_info_id: Int)
  /// The row's display has no Creature2DisplayInfo row, so the creature has no
  /// model.
  NoDisplayRow(display_info_id: Int)
  /// The row's outfit is not 0 and has no Creature2OutfitInfo row.
  NoOutfitRow(outfit_info_id: Int)
  /// The row's world has no row in the client's World table (world 0 has none).
  InNoWorld(world_id: Int)
  /// A damage effect of the creature's attack spell has a caster prerequisite the
  /// server does not evaluate (genesis_prime/world_map/creature_attack).
  AttackNotEvaluated(
    creature_id: Creature2Id,
    unevaluated: creature_attack.Unevaluated,
  )
  /// A damage effect of the creature's attack names a parameter the creature formula
  /// does not read (genesis_prime/game/damage `creature_unread`).
  AttackFormulaNotRead(
    creature_id: Creature2Id,
    spell4_effects_id: Int,
    parameter_kind: Int,
  )
  /// A damage effect of the creature's attack has a multiplier, dataBits00 read as a
  /// 32-bit float, that is not finite (genesis_prime/game/damage `formula_of`).
  AttackMultiplierNotFinite(
    creature_id: Creature2Id,
    spell4_effects_id: Int,
    bits: Int,
  )
}

/// The client's rule a creature's row fails (`0x140485790`).
pub type ValidityRule {
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
/// ids of each display group, the first display and the first outfit of each
/// group, the ids of the outfits that have a Creature2OutfitInfo row, each
/// faction's parent, and the level of each pair of factions that has a
/// relationship, filed under both orders as the client files it. Creature2OutfitInfo
/// is a table only the content load reads, so the checks of a summon read the ids
/// and not the table.
type Catalog {
  Catalog(
    tables: table_store.Tables,
    overrides: Dict(#(Int, Int), Float),
    display_groups: Dict(Int, Set(Int)),
    first_displays: Dict(Int, Int),
    first_outfits: Dict(Int, Int),
    outfits: Set(Int),
    parents: Dict(Int, Int),
    levels: Dict(#(Int, Int), Int),
    worlds: Set(Int),
  )
}

/// The Exile and Dominion player factions, children of faction 165
/// (`0x140787760`).
pub const exile_faction = 167

pub const dominion_faction = 166

/// The highest level the client calls Neutral; a level above it is Friendly
/// (FactionDispositionFromLevel: 0 to 2 Hostile, 3 to 7 Neutral, 8 to 10
/// Friendly, `world_data.creature_disposition`).
const highest_neutral_level = 7

/// The highest level the client calls Hostile (FactionDispositionFromLevel,
/// `world_data.creature_disposition`).
const highest_hostile_level = 2

/// The rows of the spawn table in, the selection out: every NonPlayer row and
/// every static object row is checked (a row that fails is a refusal, and fails
/// the load), then the NonPlayer rows that start are chosen by the rule above and
/// the rest counted, and the static objects are kept but for a type 32 one the
/// client would create dead, for each world; every other entity type is counted.
/// Pure: the client's tables are the only other input, and `tables` holds the
/// faction tables as well as the creature ones.
pub fn select(
  rows rows: List(Row),
  tables tables: table_store.Tables,
  formulas formulas: Formulas,
  kinds kinds: Kinds,
) -> Selection {
  let catalog = catalog(tables:)
  let refused = fn(row: Row, error) {
    let SpawnId(number) = row.id
    Refused(refusal.Refusal(
      table: "spawn",
      row: refusal.RowId(number),
      rule: describe(error:),
    ))
  }
  let #(_shared, judged) =
    list.map_fold(rows, dict.new(), fn(shared, row) {
      case
        row.entity_type == non_player,
        static_object.unit_type_of(entity_type: row.entity_type)
      {
        True, _ ->
          case load_checks(catalog:, formulas:, kinds:, shared:, row:) {
            Error(error) -> #(shared, refused(row, error))
            Ok(#(checked, shared)) -> #(
              shared,
              case left_out_of(catalog:, checked:) {
                Ok(reason) -> Excluded(row:, reason:)
                Error(Nil) -> Started(checked:)
              },
            )
          }
        False, Ok(unit_type) -> #(
          shared,
          case object_checks(catalog:, row:, unit_type:) {
            Error(error) -> refused(row, error)
            Ok(object) ->
              case created_dead(object) {
                True -> ObjectDead(row:)
                False -> ObjectSent(row:, object:)
              }
          },
        )
        False, Error(Nil) -> #(shared, Other(row:))
      }
    })
  let started =
    list.filter_map(judged, fn(one) {
      case one {
        Started(checked:) -> Ok(checked)
        Other(..)
        | Excluded(..)
        | Refused(..)
        | ObjectSent(..)
        | ObjectDead(..) -> Error(Nil)
      }
    })
  let objects =
    list.filter_map(judged, fn(one) {
      case one {
        ObjectSent(object:, ..) -> Ok(object)
        Started(..) | Other(..) | Excluded(..) | Refused(..) | ObjectDead(..) ->
          Error(Nil)
      }
    })
  Selection(
    worlds: worlds_of(started:, objects:, worlds: catalog.worlds),
    refusals: list.filter_map(judged, fn(one) {
      case one {
        Refused(refusal) -> Ok(refusal)
        Other(..)
        | Excluded(..)
        | Started(..)
        | ObjectSent(..)
        | ObjectDead(..) -> Error(Nil)
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

/// What a summon of a creature is checked with, built once at the content load
/// from the same tables, formulas and kinds the stored spawns are checked with,
/// and put in a term beside them (genesis_prime/content/spawn `put_summon_checks`):
/// the map reads it to answer a summon and the creature's start to build the
/// spawn again.
pub opaque type SummonChecks {
  SummonChecks(catalog: Catalog, formulas: Formulas, kinds: Kinds)
}

/// The checks a summon is made with.
pub fn summon_checks(
  tables tables: table_store.Tables,
  formulas formulas: Formulas,
  kinds kinds: Kinds,
) -> SummonChecks {
  SummonChecks(catalog: catalog(tables:), formulas:, kinds:)
}

/// Why a summon makes no spawn.
pub type SummonRefusal {
  /// The summon names a level the CreatureLevel table has no row for, so no
  /// level, health or defence follows from it.
  NoCreatureLevelRow(level: Int)
  /// The summon names the last CreatureLevel row, which holds the values of the
  /// properties 100 and above for every level (`last_creature_level`) and is no
  /// level of a creature.
  NotACreatureLevel(level: Int)
  /// The row the summon would make fails the client's checks of a spawn
  /// (`client_checks`) or the load's (`load_checks`).
  FailsTheChecks(error: SpawnError)
  /// The row passes them, but a stored spawn of it would not start
  /// (`left_out_of`): a creature with no faction, one friendly to both player
  /// factions, an NPC with a link, or one with no health. A summon is refused
  /// for the same reason, a server choice, so it starts only what a spawn
  /// starts.
  WouldNotStart(creature_id: Creature2Id, reason: LeftOut)
}

/// The run-only spawn of a summon, checked as a spawn is: a row of entity type 0
/// (NonPlayer) for the creature at the summoned place and facing, with the
/// display, outfit and factions the creature's Creature2 row gives, through
/// `load_checks` and `left_out_of`. The row's own health is none, and its level
/// is the summon's when it names one (stat 10, so the health and the defence
/// follow the CreatureLevel row of that level) and else none, so the creature
/// stands at its `minLevel` with its Base Health (`creature_vitals`). The
/// display and the outfit are the first entry of the creature's groups, a server choice: the client's weighted pick runs only for
/// spawns it makes itself (`0x1404846c0`, `opcode.0x262.creature`), and both
/// factions are `Creature2.factionId`, as the world database sends them
/// (`opcode.0x262.creature`).
pub fn summoned(
  checks checks: SummonChecks,
  summoned summoned: Summoned,
) -> Result(Spawn, SummonRefusal) {
  let SummonChecks(catalog:, formulas:, kinds:) = checks
  let Summoned(id:, creature_id:, level:, place:) = summoned
  use creature <- result.try(
    valid_creature(catalog:, creature_id:)
    |> result.map_error(FailsTheChecks),
  )
  use row_level <- result.try(case level {
    None -> Ok(None)
    Some(number) if number == last_creature_level ->
      Error(NotACreatureLevel(level: number))
    Some(number) ->
      case creature_level.get(catalog.tables, CreatureLevelId(number)) {
        Ok(_) -> Ok(Some(int.to_float(number)))
        Error(Nil) -> Error(NoCreatureLevelRow(level: number))
      }
  })
  let facing = start_place.facing(place)
  let row =
    Row(
      id:,
      entity_type: non_player,
      creature_id: creature_id.value,
      world_id: start_place.world_id(place),
      area_id: start_place.world_zone_id(place),
      x: start_place.x(place),
      y: start_place.y(place),
      z: start_place.z(place),
      rotation_x: facing.yaw,
      rotation_y: facing.pitch,
      rotation_z: facing.roll,
      display_info_id: dict.get(
        catalog.first_displays,
        creature.creature2_display_group_id,
      )
        |> result.unwrap(0),
      outfit_info_id: dict.get(
        catalog.first_outfits,
        creature.creature2_outfit_group_id,
      )
        |> result.unwrap(0),
      faction_id: creature.faction_id,
      base_faction_id: creature.faction_id,
      checklist_index: 0,
      world_object_id: 0,
      world_socket_id: 0,
      health: None,
      level: row_level,
    )
  use #(checked, _shared) <- result.try(
    load_checks(catalog:, formulas:, kinds:, shared: dict.new(), row:)
    |> result.map_error(FailsTheChecks),
  )
  case left_out_of(catalog:, checked:) {
    Ok(reason) -> Error(WouldNotStart(creature_id:, reason:))
    Error(Nil) -> Ok(checked.spawn)
  }
}

/// A sentence that says why a summon makes no spawn, which the player's system
/// chat line carries.
pub fn describe_refusal(refusal refusal: SummonRefusal) -> String {
  case refusal {
    NoCreatureLevelRow(level:) ->
      "CreatureLevel " <> int.to_string(level) <> " has no row"
    NotACreatureLevel(level:) ->
      "CreatureLevel "
      <> int.to_string(level)
      <> " holds the values of the properties from 100 up, and is no level"
    FailsTheChecks(error:) -> describe(error:)
    WouldNotStart(creature_id: Creature2Id(creature_id), reason:) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> " would not start as a spawn: "
      <> describe_left_out(reason)
  }
}

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
  /// A static object row that passed the client's checks: the object is sent.
  ObjectSent(row: Row, object: StaticObject)
  /// A static object row the client would create dead, left out.
  ObjectDead(row: Row)
}

/// Whether the client would create the object dead: a type 32 object with health
/// 0 (`0x140457a53`: types 10 and 11 are in the set never created dead, 32 is
/// not, opcode.0x262.simple).
fn created_dead(object: StaticObject) -> Bool {
  case object.unit_type {
    static_object.SimpleCollidable ->
      option.map(object.health, fn(health) { health.value })
      |> option.unwrap(0)
      == 0
    static_object.Simple | static_object.Platform -> False
  }
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
        dict.insert(
          found,
          #(override.creature2_id, override.unit_property_index),
          override.unit_property_value,
        )
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
    first_displays: list.fold(
      creature2_display_group_entry.all(tables),
      dict.new(),
      fn(found, entry) {
        first_kept(
          found:,
          group: entry.creature2_display_group_id,
          entry: entry.creature2_display_info_id,
        )
      },
    ),
    first_outfits: list.fold(
      creature2_outfit_group_entry.all(tables),
      dict.new(),
      fn(found, entry) {
        first_kept(
          found:,
          group: entry.creature2_outfit_group_id,
          entry: entry.creature2_outfit_info_id,
        )
      },
    ),
    outfits: set.from_list(
      list.map(creature2_outfit_info.all(tables), fn(row) { row.id }),
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

/// The entries of a group by group, with the first one met kept: the tables'
/// rows come in id order, so it is the entry of the lowest id.
fn first_kept(
  found found: Dict(Int, Int),
  group group: Int,
  entry entry: Int,
) -> Dict(Int, Int) {
  dict.upsert(found, group, option.unwrap(_, entry))
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

/// The combat values already worked out in a load, by creature, level, display and
/// faction: the spawns that share them hold one term, so the load's term is small.
type SharedCombats =
  Dict(#(Int, Int, Int, Int), Combat)

/// The CreatureLevel row of properties 100 and above, one for every level
/// (`CreatureLevel.101`).
const last_creature_level = 101

/// What the creature brings to a fight: its display's hit radius, whom it may be
/// attacked by, and its defence. Each chance is a rating formula's result from the
/// creature's base and rating properties at its level (`0x140463340` deflect,
/// `0x140463ac0` critical deflect, `0x140461a30` glance chance, `0x1404615f0` glance
/// amount); a mitigation is the formula of GameFormula 1234 from Armor plus the
/// resist of its damage type and the two offsets (`0x140464240`). Its Interrupt Armor
/// is its property 44 (`UnitProperty2.InterruptArmor_Threshold`).
fn combat_of(
  catalog catalog: Catalog,
  formulas formulas: Formulas,
  kind kind: Kind,
  creature creature: Creature2,
  level level: Int,
  display_info_id display_info_id: Int,
  faction_id faction_id: Int,
) -> Result(Combat, SpawnError) {
  let creature_id = Creature2Id(creature.id)
  let missing = fn(table, id) { NoPropertyRow(creature_id:, table:, id:) }
  use display <- result.try(
    creature2_display_info.get(
      catalog.tables,
      Creature2DisplayInfoId(display_info_id),
    )
    |> result.replace_error(missing("Creature2DisplayInfo", display_info_id)),
  )
  let property = fn(number) {
    creature_property(catalog:, row: creature, level:, property: number)
  }
  use deflect_base <- result.try(property(101))
  use deflect_rating <- result.try(property(33))
  use crit_deflect_base <- result.try(property(105))
  use crit_deflect_rating <- result.try(property(43))
  use glance_base <- result.try(property(164))
  use glance_rating <- result.try(property(58))
  use glance_amount_base <- result.try(property(195))
  use glance_amount_rating <- result.try(property(61))
  use offset <- result.try(property(103))
  use armor <- result.try(property(42))
  use physical_offset <- result.try(property(144))
  use tech_offset <- result.try(property(145))
  use magic_offset <- result.try(property(146))
  use physical_resist <- result.try(property(26))
  use tech_resist <- result.try(property(27))
  use magic_resist <- result.try(property(28))
  use armor_maximum <- result.try(property(44))
  use attack <- result.try(attack_of(
    catalog:,
    formulas:,
    kind:,
    creature:,
    level:,
    display:,
  ))
  let mitigation = fn(offset_of_type, resist) {
    rating.mitigation_fraction(
      formulas:,
      level:,
      base: offset +. offset_of_type,
      rating: armor +. resist,
    )
  }
  Ok(Combat(
    hit_radius: hit_radius.of_creature(display:),
    attackable: Attackable(
      exile: attackable_by(catalog:, player: exile_faction, unit: faction_id),
      dominion: attackable_by(
        catalog:,
        player: dominion_faction,
        unit: faction_id,
      ),
    ),
    hostile_to: Hostile(
      exile: hostile_to(catalog:, player: exile_faction, unit: faction_id),
      dominion: hostile_to(catalog:, player: dominion_faction, unit: faction_id),
    ),
    defence: hit.Defence(
      deflect_chance: rating.to_fraction(
        formula: formulas.deflect_chance,
        level:,
        base: deflect_base,
        rating: deflect_rating,
      ),
      crit_deflect_chance: rating.to_fraction(
        formula: formulas.crit_deflect,
        level:,
        base: crit_deflect_base,
        rating: crit_deflect_rating,
      ),
      glance_chance: rating.to_fraction(
        formula: formulas.glance_chance,
        level:,
        base: glance_base,
        rating: glance_rating,
      ),
      glance_amount: rating.to_fraction(
        formula: formulas.glance_amount,
        level:,
        base: glance_amount_base,
        rating: glance_amount_rating,
      ),
      physical_mitigation: mitigation(physical_offset, physical_resist),
      tech_mitigation: mitigation(tech_offset, tech_resist),
      magic_mitigation: mitigation(magic_offset, magic_resist),
      shield_mitigation_max: 0.0,
      physical_taken: hit.as_dealt,
      tech_taken: hit.as_dealt,
      magic_taken: hit.as_dealt,
    ),
    attack:,
    interrupt_armor: creature_life.interrupt_armor_of(maximum: armor_maximum),
  ))
}

/// The creature's own attack (genesis_prime/world_map/creature_life `Attack`): its
/// kind's spell, the damage effect its difficulty chooses by the effect's caster
/// prerequisite (type 179, `0x14049eeb0`), its blow by the creature formula
/// (`0x140565600`, GameFormula 712), its critical hit chance, severity and
/// strikethrough from its properties, its run speed (Creature2DisplayInfo.runLand
/// times property 100, `0x1405b45e0`) and its reach (the spell's `targetMaxRange`
/// plus `hit_radius`).
fn attack_of(
  catalog catalog: Catalog,
  formulas formulas: Formulas,
  kind kind: Kind,
  creature creature: Creature2,
  level level: Int,
  display display: creature2_display_info.Creature2DisplayInfo,
) -> Result(Attack, SpawnError) {
  let creature_id = Creature2Id(creature.id)
  let property = fn(number) {
    creature_property(catalog:, row: creature, level:, property: number)
  }
  use spell <- result.try(
    spell4.get(catalog.tables, kind.attack_spell4_id)
    |> result.replace_error(NoPropertyRow(
      creature_id:,
      table: "Spell4",
      id: kind.attack_spell4_id.value,
    )),
  )
  use scaling <- result.try(
    game_formula.get(catalog.tables, id.GameFormulaId(creature_scaling_formula))
    |> result.replace_error(NoPropertyRow(
      creature_id:,
      table: "GameFormula",
      id: creature_scaling_formula,
    )),
  )
  use effects <- result.try(
    creature_attack.applying(
      tables: catalog.tables,
      spell4_id: kind.attack_spell4_id.value,
      difficulty: creature.creature2_difficulty_id,
    )
    |> result.map_error(fn(unevaluated) {
      AttackNotEvaluated(creature_id:, unevaluated:)
    }),
  )
  use strength <- result.try(property(0))
  use assault_rating <- result.try(property(35))
  use move_speed <- result.try(property(100))
  use crit_chance_base <- result.try(property(102))
  use strikethrough_base <- result.try(property(104))
  use crit_severity_base <- result.try(property(127))
  let caster =
    damage.Creature(
      level:,
      strength:,
      assault_power: damage.power_of(rating: assault_rating),
    )
  use blows <- result.try(
    list.try_map(effects, fn(effect) {
      use formula <- result.try(
        damage.formula_of(effect:)
        |> result.replace_error(AttackMultiplierNotFinite(
          creature_id:,
          spell4_effects_id: effect.id,
          bits: effect.data_bits00,
        )),
      )
      case damage.creature_unread(formula:) {
        Some(damage.Unread(parameter_kind:)) ->
          Error(AttackFormulaNotRead(
            creature_id:,
            spell4_effects_id: effect.id,
            parameter_kind:,
          ))
        None ->
          Ok(hit.Blow(
            spell4_effects_id: effect.id,
            damage_type: effect.damage_type,
            damage: float.round(damage.creature_value(
              formula:,
              creature: caster,
              scaling: damage.CreatureScaling(
                per_level: scaling.datafloat0,
                base: scaling.datafloat01,
                overflow: scaling.datafloat02,
                divisor: scaling.datafloat03,
              ),
            )),
            delay_ms: effect.delay_time,
            threat_multiplier: effect.threat_multiplier,
          ))
      }
    }),
  )
  Ok(creature_life.Attack(
    spell4_id: kind.attack_spell4_id,
    offence: hit.Offence(
      blows:,
      crit_chance: rating.to_fraction(
        formula: formulas.crit_chance,
        level:,
        base: crit_chance_base,
        rating: 0.0,
      ),
      crit_severity: rating.to_fraction(
        formula: formulas.crit_severity,
        level:,
        base: crit_severity_base,
        rating: 0.0,
      ),
      strikethrough: rating.to_fraction(
        formula: formulas.strikethrough,
        level:,
        base: strikethrough_base,
        rating: 0.0,
      ),
    ),
    run_speed: display.run_land *. move_speed,
    reach: spell.target_max_range +. hit_radius.of_creature(display:),
  ))
}

/// The GameFormula row whose values scale a creature caster's damage
/// (`0x140565600`).
const creature_scaling_formula = 712

/// A creature's property: the CreatureLevel value times the archetype, difficulty and
/// tier multipliers, each product held as a 32-bit float, or the creature's own
/// override. Properties below 100 are read from the row of `level`, the others from
/// the last row (`CreatureLevel.101`) at the column of the property minus 100
/// (`0x1404585c0`). Only the properties Base Health and a fight read are built;
/// UnitProperty2's flags, which would stop the multipliers, are read for none of them
/// but 101, 102, 105 and 164 (`Creature2.73464.crit_deflect_glance`), and any other
/// property is not built.
fn creature_property(
  catalog catalog: Catalog,
  row row: Creature2,
  level level_number: Int,
  property property: Int,
) -> Result(Float, SpawnError) {
  let creature_id = Creature2Id(row.id)
  case dict.get(catalog.overrides, #(row.id, property)) {
    Ok(value) -> Ok(value)
    Error(Nil) -> {
      let missing = fn(table, id) { NoPropertyRow(creature_id:, table:, id:) }
      let level_id = case property < 100 {
        True -> level_number
        False -> last_creature_level
      }
      use level <- result.try(
        creature_level.get(catalog.tables, CreatureLevelId(level_id))
        |> result.replace_error(missing("CreatureLevel", level_id)),
      )
      use tier <- result.try(
        creature2_tier.get(
          catalog.tables,
          Creature2TierId(row.creature2_tier_id),
        )
        |> result.replace_error(missing("Creature2Tier", row.creature2_tier_id)),
      )
      use arche <- result.try(
        creature2_arche_type.get(
          catalog.tables,
          Creature2ArcheTypeId(row.creature2_arche_type_id),
        )
        |> result.replace_error(missing(
          "Creature2ArcheType",
          row.creature2_arche_type_id,
        )),
      )
      let difficulty =
        creature2_difficulty.get(
          catalog.tables,
          Creature2DifficultyId(row.creature2_difficulty_id),
        )
      case property {
        0 ->
          scaled(
            value: level.unit_property_value00,
            archetype: arche.unit_property_multiplier000,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier000
            }),
            tier: tier.unit_property_multiplier000,
          )
        35 ->
          scaled(
            value: level.unit_property_value35,
            archetype: arche.unit_property_multiplier035,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier035
            }),
            tier: tier.unit_property_multiplier035,
          )
        100 ->
          scaled(
            value: level.unit_property_value00,
            archetype: arche.unit_property_multiplier100,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier100
            }),
            tier: tier.unit_property_multiplier100,
          )
        102 ->
          scaled(
            value: level.unit_property_value02,
            archetype: arche.unit_property_multiplier102,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier102
            }),
            tier: tier.unit_property_multiplier102,
          )
        104 ->
          scaled(
            value: level.unit_property_value04,
            archetype: arche.unit_property_multiplier104,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier104
            }),
            tier: tier.unit_property_multiplier104,
          )
        127 ->
          scaled(
            value: level.unit_property_value27,
            archetype: arche.unit_property_multiplier127,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier127
            }),
            tier: tier.unit_property_multiplier127,
          )
        7 ->
          scaled(
            value: level.unit_property_value07,
            archetype: arche.unit_property_multiplier007,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier007
            }),
            tier: tier.unit_property_multiplier007,
          )
        26 ->
          scaled(
            value: level.unit_property_value26,
            archetype: arche.unit_property_multiplier026,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier026
            }),
            tier: tier.unit_property_multiplier026,
          )
        27 ->
          scaled(
            value: level.unit_property_value27,
            archetype: arche.unit_property_multiplier027,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier027
            }),
            tier: tier.unit_property_multiplier027,
          )
        28 ->
          scaled(
            value: level.unit_property_value28,
            archetype: arche.unit_property_multiplier028,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier028
            }),
            tier: tier.unit_property_multiplier028,
          )
        33 ->
          scaled(
            value: level.unit_property_value33,
            archetype: arche.unit_property_multiplier033,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier033
            }),
            tier: tier.unit_property_multiplier033,
          )
        42 ->
          scaled(
            value: level.unit_property_value42,
            archetype: arche.unit_property_multiplier042,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier042
            }),
            tier: tier.unit_property_multiplier042,
          )
        43 ->
          scaled(
            value: level.unit_property_value43,
            archetype: arche.unit_property_multiplier043,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier043
            }),
            tier: tier.unit_property_multiplier043,
          )
        58 ->
          scaled(
            value: level.unit_property_value58,
            archetype: arche.unit_property_multiplier058,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier058
            }),
            tier: tier.unit_property_multiplier058,
          )
        44 ->
          scaled(
            value: level.unit_property_value44,
            archetype: arche.unit_property_multiplier044,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier044
            }),
            tier: tier.unit_property_multiplier044,
          )
        61 ->
          scaled(
            value: level.unit_property_value61,
            archetype: arche.unit_property_multiplier061,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier061
            }),
            tier: tier.unit_property_multiplier061,
          )
        101 ->
          scaled(
            value: level.unit_property_value01,
            archetype: arche.unit_property_multiplier101,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier101
            }),
            tier: tier.unit_property_multiplier101,
          )
        103 ->
          scaled(
            value: level.unit_property_value03,
            archetype: arche.unit_property_multiplier103,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier103
            }),
            tier: tier.unit_property_multiplier103,
          )
        105 ->
          scaled(
            value: level.unit_property_value05,
            archetype: arche.unit_property_multiplier105,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier105
            }),
            tier: tier.unit_property_multiplier105,
          )
        144 ->
          scaled(
            value: level.unit_property_value44,
            archetype: arche.unit_property_multiplier144,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier144
            }),
            tier: tier.unit_property_multiplier144,
          )
        145 ->
          scaled(
            value: level.unit_property_value45,
            archetype: arche.unit_property_multiplier145,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier145
            }),
            tier: tier.unit_property_multiplier145,
          )
        146 ->
          scaled(
            value: level.unit_property_value46,
            archetype: arche.unit_property_multiplier146,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier146
            }),
            tier: tier.unit_property_multiplier146,
          )
        164 ->
          scaled(
            value: level.unit_property_value64,
            archetype: arche.unit_property_multiplier164,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier164
            }),
            tier: tier.unit_property_multiplier164,
          )
        195 ->
          scaled(
            value: level.unit_property_value95,
            archetype: arche.unit_property_multiplier195,
            difficulty: through(difficulty:, column: fn(difficulty) {
              difficulty.unit_property_multiplier195
            }),
            tier: tier.unit_property_multiplier195,
          )
        _ -> Error(PropertyNotBuilt(creature_id:, property:))
      }
    }
  }
}

/// The value times the archetype, difficulty and tier multipliers in the order the
/// client reads them, each product held as a 32-bit float.
fn scaled(
  value value: Float,
  archetype archetype: Float,
  difficulty difficulty: Float,
  tier tier: Float,
) -> Result(Float, SpawnError) {
  Ok(
    value
    |> float32.product(right: archetype)
    |> float32.product(right: difficulty)
    |> float32.product(right: tier),
  )
}

/// The difficulty's multiplier, or 1.0 for a difficulty with no row.
fn through(
  difficulty difficulty: Result(Creature2Difficulty, Nil),
  column column: fn(Creature2Difficulty) -> Float,
) -> Float {
  case difficulty {
    Ok(difficulty) -> column(difficulty)
    Error(Nil) -> 1.0
  }
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

/// Whether a unit of the faction fights a player of the other on sight: its level
/// toward the player's faction is Hostile, 0 to 2 (`world_data.creature_disposition`).
fn hostile_to(
  catalog catalog: Catalog,
  player player: Int,
  unit unit: Int,
) -> Bool {
  faction_level(catalog:, from: player, to: unit) <= highest_hostile_level
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

/// The started spawns and the static objects by world, each world's with its
/// cell index, and an empty `WorldSpawns` for every other world of the client's
/// World table.
fn worlds_of(
  started started: List(Checked),
  objects objects: List(StaticObject),
  worlds worlds: Set(Int),
) -> Dict(Int, WorldSpawns) {
  let started_by_world =
    list.group(started, fn(checked) {
      start_place.world_id(checked.spawn.place)
    })
  let objects_by_world =
    list.group(objects, fn(object) { start_place.world_id(object.place) })
  set.union(
    set.from_list(dict.keys(started_by_world)),
    set.from_list(dict.keys(objects_by_world)),
  )
  |> set.fold(
    set.fold(worlds, dict.new(), fn(found, world_id) {
      dict.insert(found, world_id, no_spawns())
    }),
    fn(found, world_id) {
      dict.insert(
        found,
        world_id,
        world_spawns(
          spawns: dict.get(started_by_world, world_id)
            |> result.unwrap([])
            |> list.map(fn(one) { one.spawn }),
          objects: dict.get(objects_by_world, world_id) |> result.unwrap([]),
        ),
      )
    },
  )
}

/// The static object types in the coverage's order.
pub const object_types = [
  static_object.Simple,
  static_object.Platform,
  static_object.SimpleCollidable,
]

/// The coverage of each world that has a row, in world order: how many rows
/// start, how many NonPlayer rows are left out and why, how many static objects
/// are sent, by type, and left out dead, and how many rows each other entity type
/// has. A refused row fails the load and is counted in no world.
fn coverage_of(judged: List(Judged)) -> List(WorldCoverage) {
  let by_world =
    list.group(judged, fn(one) {
      case one {
        Other(row:)
        | Excluded(row:, ..)
        | ObjectSent(row:, ..)
        | ObjectDead(row:) -> row.world_id
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
          Other(..)
          | Excluded(..)
          | Refused(..)
          | ObjectSent(..)
          | ObjectDead(..) -> False
        }
      }),
      left_out: list.map([NoFaction, FriendlyToBoth, NpcLink, Dead], fn(reason) {
        #(
          reason,
          list.count(ones, fn(one) {
            case one {
              Excluded(reason: held, ..) -> held == reason
              Other(..)
              | Started(..)
              | Refused(..)
              | ObjectSent(..)
              | ObjectDead(..) -> False
            }
          }),
        )
      }),
      objects_sent: list.map(object_types, fn(unit_type) {
        #(
          unit_type,
          list.count(ones, fn(one) {
            case one {
              ObjectSent(object:, ..) -> object.unit_type == unit_type
              Other(..)
              | Started(..)
              | Refused(..)
              | Excluded(..)
              | ObjectDead(..) -> False
            }
          }),
        )
      }),
      objects_dead: list.count(ones, fn(one) {
        case one {
          ObjectDead(..) -> True
          Other(..)
          | Started(..)
          | Refused(..)
          | Excluded(..)
          | ObjectSent(..) -> False
        }
      }),
      other_types: list.filter_map(ones, fn(one) {
        case one {
          Other(row:) -> Ok(row.entity_type)
          Excluded(..)
          | Started(..)
          | Refused(..)
          | ObjectSent(..)
          | ObjectDead(..) -> Error(Nil)
        }
      })
        |> list.group(fn(entity_type) { entity_type })
        |> dict.map_values(fn(_type, found) { list.length(found) })
        |> dict.to_list
        |> list.sort(fn(first, second) { int.compare(first.0, second.0) }),
    )
  })
}

/// What the client's checks of a row find, a NonPlayer row's or a static object
/// row's: the creature's row and the place.
type Drawn {
  Drawn(creature: Creature2, place: Place)
}

/// The checks the client makes of one row, of any type it draws from a Creature2
/// row: its creature loads, its world is one, and its display is one of the
/// creature's and has a row and its outfit has one.
fn client_checks(
  catalog catalog: Catalog,
  row row: Row,
) -> Result(Drawn, SpawnError) {
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
  use _in_group <- result.try(display_in_group(
    catalog:,
    creature:,
    display_info_id: row.display_info_id,
  ))
  use _outfit <- result.try(outfit_exists(
    catalog:,
    outfit_info_id: row.outfit_info_id,
  ))
  Ok(Drawn(creature:, place:))
}

/// A creature's level and health and where the health comes from: the row's
/// stats, truncated, or the creature's own `minLevel` and its Base Health at the
/// level for a row with none.
fn creature_vitals(
  catalog catalog: Catalog,
  creature creature: Creature2,
  row row: Row,
) -> Result(#(Int, Int, HealthSource), SpawnError) {
  let level = case row.level {
    Some(stat) -> float.truncate(stat)
    None -> creature.min_level
  }
  case row.health {
    Some(stat) -> Ok(#(level, float.truncate(stat), Recorded))
    None ->
      base_health(catalog:, row: creature, level:)
      |> result.map(fn(health) { #(level, health, ClientDefault) })
  }
}

/// A static object row through the client's checks (`client_checks`): the
/// object its 0x262 shows. Types 10 and 11 carry the stats the row records; type
/// 32 the creature's level and health (`creature_vitals`).
fn object_checks(
  catalog catalog: Catalog,
  row row: Row,
  unit_type unit_type: static_object.UnitType,
) -> Result(StaticObject, SpawnError) {
  use Drawn(creature:, place:) <- result.try(client_checks(catalog:, row:))
  use #(level, health) <- result.try(case unit_type {
    static_object.Simple | static_object.Platform ->
      Ok(#(
        option.map(row.level, float.truncate),
        option.map(row.health, fn(stat) {
          static_object.Health(value: float.truncate(stat), source: Recorded)
        }),
      ))
    static_object.SimpleCollidable ->
      creature_vitals(catalog:, creature:, row:)
      |> result.map(fn(vitals) {
        let #(level, value, source) = vitals
        #(Some(level), Some(static_object.Health(value:, source:)))
      })
  })
  Ok(static_object.StaticObject(
    id: row.id,
    unit_type:,
    creature_id: Creature2Id(row.creature_id),
    place:,
    level:,
    health:,
    faction_id: row.faction_id,
    base_faction_id: row.base_faction_id,
    display_info_id: row.display_info_id,
    outfit_info_id: row.outfit_info_id,
    checklist_index: row.checklist_index,
    world_object_id: row.world_object_id,
    world_socket_id: row.world_socket_id,
  ))
}

/// A NonPlayer row through the client's checks (`client_checks`), with what the
/// creature brings to a fight, shared by the spawns of one creature, level,
/// display and faction.
fn load_checks(
  catalog catalog: Catalog,
  formulas formulas: Formulas,
  kinds kinds: Kinds,
  shared shared: SharedCombats,
  row row: Row,
) -> Result(#(Checked, SharedCombats), SpawnError) {
  let creature_id = Creature2Id(row.creature_id)
  use Drawn(creature:, place:) <- result.try(client_checks(catalog:, row:))
  use #(level, health, health_source) <- result.try(creature_vitals(
    catalog:,
    creature:,
    row:,
  ))
  let key = #(row.creature_id, level, row.display_info_id, row.faction_id)
  use #(combat, shared) <- result.try(case dict.get(shared, key) {
    Ok(combat) -> Ok(#(combat, shared))
    Error(Nil) ->
      combat_of(
        catalog:,
        formulas:,
        kind: creature_kind.kind_of(kinds:, creature2_id: row.creature_id),
        creature:,
        level:,
        display_info_id: row.display_info_id,
        faction_id: row.faction_id,
      )
      |> result.map(fn(combat) { #(combat, dict.insert(shared, key, combat)) })
  })
  Ok(#(
    Checked(
      row:,
      creature:,
      spawn: Spawn(
        id: row.id,
        creature_id:,
        place:,
        level:,
        health:,
        health_source:,
        faction_id: row.faction_id,
        base_faction_id: row.base_faction_id,
        display_info_id: row.display_info_id,
        outfit_info_id: row.outfit_info_id,
        combat:,
        // Gap: no base is built yet, so a creature's properties hold none; #464
        // builds every UnitProperty2 row by `creature_property`.
        bases: [],
      ),
    ),
    shared,
  ))
}

/// The row's outfit is 0, or has a Creature2OutfitInfo row.
fn outfit_exists(
  catalog catalog: Catalog,
  outfit_info_id outfit_info_id: Int,
) -> Result(Nil, SpawnError) {
  use <- bool.guard(when: outfit_info_id == 0, return: Ok(Nil))
  case set.contains(catalog.outfits, outfit_info_id) {
    True -> Ok(Nil)
    False -> Error(NoOutfitRow(outfit_info_id:))
  }
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
        || dict.has_key(catalog.first_outfits, row.creature2_outfit_group_id),
      NoOutfitEntries,
    ),
  ]
  case list.find(rules, fn(rule) { !rule.0 }) {
    Ok(#(_, rule)) -> Error(NotLoadedByTheClient(creature_id:, rule:))
    Error(Nil) -> Ok(row)
  }
}

/// Base Health: property 7 at `level`, truncated: its own
/// override when it has one, else CreatureLevel[level] times the archetype, difficulty
/// and tier multipliers (`creature_property`). The client looks the three multipliers
/// up by the creature's words 4, 5 and 6, which are the archetype, difficulty and
/// tier (`0x1404585c0`, `0x1404852b0`); the order of the products is that order, a
/// reading, since the order of the multiplications is not read. UnitProperty2 7's
/// flags bit 0, which would stop the multipliers, is clear.
///
/// A difficulty id of 0 multiplies by 1.0. The client's lookup of difficulty 0
/// (`0x1401f64e0`) is not read; reading what it returns for an id with no row, and
/// whether the creature's property code skips it, would settle it. The training
/// creatures have difficulty 1.
fn base_health(
  catalog catalog: Catalog,
  row row: Creature2,
  level level: Int,
) -> Result(Int, SpawnError) {
  creature_property(
    catalog:,
    row:,
    level:,
    property: unit_fields.base_health_property,
  )
  |> result.map(float.truncate)
}

/// One line of the coverage of a world, for the log at start and for the coverage
/// tool: how many spawns start, how many NonPlayer rows are left out and why, how
/// many static objects are sent, by unit type, and left out dead, and how many
/// rows each other entity type has.
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
  <> "; static objects sent: "
  <> string.join(
    list.map(coverage.objects_sent, fn(entry) {
      "type "
      <> int.to_string(static_object.type_number(unit_type: entry.0))
      <> " "
      <> int.to_string(entry.1)
    }),
    ", ",
  )
  <> ", left out dead "
  <> int.to_string(coverage.objects_dead)
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
    NoPropertyRow(creature_id: Creature2Id(creature_id), table:, id:) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> " has no "
      <> table
      <> " row "
      <> int.to_string(id)
      <> " for its Base Health or defence"
    PropertyNotBuilt(creature_id: Creature2Id(creature_id), property:) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> " is asked for property "
      <> int.to_string(property)
      <> ", which the load does not build"
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
    AttackNotEvaluated(creature_id: Creature2Id(creature_id), unevaluated:) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> "'s attack: "
      <> creature_attack.describe(unevaluated:)
    AttackFormulaNotRead(
      creature_id: Creature2Id(creature_id),
      spell4_effects_id:,
      parameter_kind:,
    ) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> "'s attack effect "
      <> int.to_string(spell4_effects_id)
      <> " reads parameter type "
      <> int.to_string(parameter_kind)
      <> ", which the creature formula does not read"
    AttackMultiplierNotFinite(
      creature_id: Creature2Id(creature_id),
      spell4_effects_id:,
      bits:,
    ) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> "'s attack effect "
      <> int.to_string(spell4_effects_id)
      <> " has a multiplier, dataBits00 "
      <> int.to_string(bits)
      <> ", that is not a finite 32-bit float"
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
