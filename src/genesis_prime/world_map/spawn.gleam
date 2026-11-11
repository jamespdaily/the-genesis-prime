//// The spawns a map stands creatures at: one spawn is one place a creature of the
//// client's Creature2 table stands at, with the values its 0x262 carries. The rows
//// come from the server's `spawn` table (genesis_prime/content/spawn), which holds
//// every place the world database records; this module is the pure part: the
//// client's checks of a row, the selection of the rows that start as fight
//// creatures, and the shape a world's spawns are kept in.
////
//// ```
//// the spawn table (one query, at start) ─▶ Row ─▶ load checks (the client's validity rules)
////                                                 ─▶ selection (who a player can attack or talk to)
////                                                 ─▶ Spawn, one WorldSpawns term for each world
//// a map's start    ─▶ reads its world's WorldSpawns: no copy, no query
//// a player's move  ─▶ spawn_cell.near ─▶ exact sight ─▶ the spawns it sees
//// ```
////
//// - **What starts.** A row of entity type 0 (NonPlayer, the unit type of message
////   0x262: `world_data.entity_type`, `0x140649e20`) with a faction, whose health
////   stat is not 0, and either whose Creature2 row gives or receives a quest, or
////   that is not Friendly to both player factions and whose Creature2 row has no
////   trainer, station, taxi, bind or portal link; a row with no stats is kept. The
////   client marks a creature's quest kinds from its own Creature2 row
////   (`0x140479560.quest_kinds`, `0x1405a8d40`), so a quest creature stands
////   whatever else it links to. The client lets a player attack a Hostile or a
////   Neutral unit and not a Friendly one (`0x1403ad540`), and a faction's level to
////   a player faction walks the faction's parents (`0x140787760`, `0x140717560`,
////   Faction2Relationship). Every other row is counted for the coverage measure.
//// - **Static objects.** A row of entity type 4, 8, 10, 11, 12, 13, 14 or 32 is a
////   static object (genesis_prime/world_map/static_object), checked as a
////   NonPlayer row is and kept whatever its faction. Types 4, 8, 10, 11, 12 and
////   14 carry the stats the row records and no other, since the client never
////   creates them dead (`0x140457bc5`); types 13 and 32 take a creature's level
////   and health by the rule below, and one with health 0 is left out and counted,
////   since the client would create it dead (`0x140457bc5`, opcode.0x262.simple).
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
import genesis_prime/game/faction_level
import genesis_prime/game/hit
import genesis_prime/game/hit_radius
import genesis_prime/game/objective_link
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/rating.{type Formulas}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/target_group
import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/game/vendor.{type Vendors}
import genesis_prime/message/damage_type
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
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type Creature2Id, type PrerequisiteId, type UnitProperty2Id,
  Creature2ArcheTypeId, Creature2DifficultyId, Creature2DisplayInfoId,
  Creature2Id, Creature2ResistId, Creature2TierId, CreatureLevelId, Faction2Id,
  InstancePortalId, PathMissionId, UnitProperty2Id,
}
import genesis_prime/table/instance_portal
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_mission
import genesis_prime/table/spell4
import genesis_prime/table/unit_property2
import genesis_prime/table/world
import genesis_prime/world_map/checklist_index
import genesis_prime/world_map/creature_attack
import genesis_prime/world_map/creature_columns
import genesis_prime/world_map/creature_faction.{type Factions}
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
    /// What working `combat` out again from changed properties needs besides them
    /// (`values_of`).
    context: CombatContext,
    /// Whether the creature sells (`vendor` content table): its 0x262 carries the vendor
    /// create flag, which shows the client its bag icon.
    vendor: Bool,
    /// The creature's `prerequisiteIdVisibility`, `None` for 0: the player sees the
    /// creature only while this prerequisite does not fail for them
    /// (genesis_prime/game/visibility).
    visibility: Option(PrerequisiteId),
    /// The unit's bit in the mask of each checklist objective that counts it, 0 to 31
    /// (genesis_prime/world_map/checklist_index): the 0x262 sends it.
    checklist_index: Int,
  )
}

/// The loaded formulas and scaling inputs a creature's combat values are worked out
/// with from its properties, so a change of a property needs no table at run time:
/// the rating formulas, the creature damage scaling (GameFormula 712, `0x140565600`),
/// each damage effect of its attack with its formula, and its display's
/// Creature2DisplayInfo.runLand.
pub type CombatContext {
  CombatContext(
    formulas: Formulas,
    scaling: damage.CreatureScaling,
    attack: List(AttackEffect),
    run_land: Float,
  )
}

/// One damage effect of a creature's attack: its blow as the load worked it out, and
/// the formula its damage comes from.
pub type AttackEffect {
  AttackEffect(blow: hit.Blow, formula: damage.Formula)
}

/// A creature's values that its properties set: what it brings to a fight, and its
/// maximum health.
pub type CreatureValues {
  CreatureValues(combat: Combat, max_health: Int)
}

/// The creature's combat values and maximum health from its current `properties`, by
/// the formulas `combat_of` and `attack_of` use at the load: defence, offence, run
/// speed, Interrupt Armor's maximum and maximum health. The values no property sets
/// (hit radius, whom it fights, its attack's spell and reach) are the spawn's own.
pub fn values_of(
  spawn spawn: Spawn,
  properties properties: Properties,
) -> CreatureValues {
  let value = fn(number) {
    unit_properties.value(properties:, property: UnitProperty2Id(number))
  }
  let CombatContext(formulas:, scaling:, attack: effects, run_land:) =
    spawn.context
  let combat = spawn.combat
  let blows =
    list.map(effects, fn(effect) {
      hit.Blow(
        ..effect.blow,
        damage: blow_damage(
          formula: effect.formula,
          damage_type: effect.blow.damage_type,
          level: spawn.level,
          scaling:,
          value:,
        ),
      )
    })
  CreatureValues(
    combat: Combat(
      ..combat,
      defence: defence_of(formulas:, level: spawn.level, value:),
      attack: creature_life.Attack(
        ..combat.attack,
        offence: offence_of(formulas:, level: spawn.level, blows:, value:),
        run_speed: run_speed_of(run_land:, value:),
      ),
      interrupt_armor: interrupt_armor_in(value:),
    ),
    max_health: int.max(
      1,
      float.truncate(value(unit_properties.base_health.value)),
    ),
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
    /// The loaded prerequisites of each world's started spawns and sent objects
    /// that have a visibility prerequisite, each distinct one once, in id order, for
    /// each world that has any (`visibility_index`).
    visibility: Dict(Int, List(Prerequisite)),
  )
}

/// Why a NonPlayer row does not start.
pub type LeftOut {
  /// Faction 0: the client sees no faction, and a 0x262 with none fails
  /// (`opcode.0x262`).
  NoFaction
  /// Friendly to both player factions, and the creature gives and receives no quest and
  /// has no link to an objective.
  FriendlyToBoth
  /// The creature's row has a trainer, station, taxi, bind or portal link and
  /// no quest.
  ServiceLink
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
  /// A row a creature's properties read is missing: the table and the id.
  NoPropertyRow(creature_id: Creature2Id, table: String, id: Int)
  /// The row's display is not in its creature's display group.
  DisplayNotInGroup(creature_id: Creature2Id, display_info_id: Int)
  /// The row's display has no Creature2DisplayInfo row, so the creature has no
  /// model.
  NoDisplayRow(display_info_id: Int)
  /// The row's outfit is not 0 and has no Creature2OutfitInfo row.
  NoOutfitRow(outfit_info_id: Int)
  /// The row's world has no row in the client's World table (world 0 has none).
  InNoWorld(world_id: Int)
  /// A started spawn or a sent object names a visibility prerequisite the
  /// Prerequisite table has no row for, or one that does not load
  /// (genesis_prime/game/prerequisite `load`).
  NoVisibilityRow(
    creature_id: Creature2Id,
    prerequisite_id: PrerequisiteId,
    reason: prerequisite.LoadError,
  )
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
/// group, the ids of the outfits that have a Creature2OutfitInfo row, the
/// factions' levels (genesis_prime/game/faction_level) and each
/// UnitProperty2 row's default and flags. Creature2OutfitInfo
/// is a table only the content load reads, so the checks of a summon read the ids
/// and not the table.
type Catalog {
  Catalog(
    tables: table_store.Tables,
    overrides: Dict(#(Int, Int), Float),
    display_groups: Dict(Int, Set(Int)),
    looks: Looks,
    outfits: Set(Int),
    factions: faction_level.Levels,
    worlds: Set(Int),
    property_rows: Dict(Int, #(Float, Int)),
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
  factions factions: Factions,
  vendors vendors: Vendors,
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
  let #(_shared, judged_by_checks) =
    list.map_fold(rows, dict.new(), fn(shared, row) {
      case
        row.entity_type == non_player,
        static_object.unit_type_of(entity_type: row.entity_type)
      {
        True, _ ->
          case
            load_checks(
              catalog:,
              formulas:,
              kinds:,
              vendors:,
              shared:,
              row: with_chosen_faction(factions:, row:),
            )
          {
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
  let #(judged, loaded) =
    visibility_judged(tables:, judged: judged_by_checks, refused:)
  let indexes = checklist_indexes(tables:, judged:)
  let started =
    list.filter_map(judged, fn(one) {
      case one {
        Started(checked:) ->
          Ok(
            Checked(
              ..checked,
              spawn: Spawn(
                ..checked.spawn,
                checklist_index: index_of(indexes, checked.spawn.id),
              ),
            ),
          )
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
        ObjectSent(object:, ..) ->
          Ok(
            static_object.StaticObject(
              ..object,
              checklist_index: index_of(indexes, object.id),
            ),
          )
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
    visibility: visibility_index(
      loaded:,
      started: list.map(started, fn(checked) { checked.spawn }),
      objects:,
    ),
  )
}

/// The checklist index of each spawn and object the load keeps, in the order the
/// rows came (`checklist_index.assign`).
fn checklist_indexes(
  tables tables: table_store.Tables,
  judged judged: List(Judged),
) -> Dict(SpawnId, Int) {
  let candidate = fn(spawn_id, creature_id: Creature2Id, faction_id) {
    creature2.get(tables, creature_id)
    |> result.map(fn(creature) {
      checklist_index.Candidate(
        spawn: spawn_id,
        unit: target_group.Unit(
          creature_id:,
          faction_id: Faction2Id(faction_id),
          unit_race_id: creature2.unit_race_id(creature),
        ),
      )
    })
  }
  list.filter_map(judged, fn(one) {
    case one {
      Started(checked:) ->
        candidate(
          checked.spawn.id,
          checked.spawn.creature_id,
          checked.spawn.faction_id,
        )
      ObjectSent(object:, ..) ->
        candidate(object.id, object.creature_id, object.faction_id)
      Other(..) | Excluded(..) | Refused(..) | ObjectDead(..) -> Error(Nil)
    }
  })
  |> fn(candidates) { checklist_index.assign(tables:, candidates:) }
}

fn index_of(indexes: Dict(SpawnId, Int), spawn_id: SpawnId) -> Int {
  dict.get(indexes, spawn_id) |> result.unwrap(0)
}

/// Message 0x262's unit type of a NonPlayer unit (`0x140649e20`).
pub const non_player = 0

/// What a summon of a creature is checked with, built once at the content load
/// from the same tables, formulas, kinds and chosen factions the stored spawns are checked with,
/// and put in a term beside them (genesis_prime/content/spawn `put_summon_checks`):
/// the map reads it to answer a summon and the creature's start to build the
/// spawn again.
pub opaque type SummonChecks {
  SummonChecks(
    catalog: Catalog,
    formulas: Formulas,
    kinds: Kinds,
    factions: Factions,
    vendors: Vendors,
  )
}

/// The checks a summon is made with.
pub fn summon_checks(
  tables tables: table_store.Tables,
  formulas formulas: Formulas,
  kinds kinds: Kinds,
  factions factions: Factions,
  vendors vendors: Vendors,
) -> SummonChecks {
  SummonChecks(
    catalog: catalog(tables:),
    formulas:,
    kinds:,
    factions:,
    vendors:,
  )
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
  /// factions, one with only a service link, or one with no health (a creature
  /// with a quest is none of the middle two, one with an objective link is not the
  /// first of them). A summon is refused
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
  let SummonChecks(catalog:, formulas:, kinds:, factions:, vendors:) = checks
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
  let row =
    creature_row(
      looks: catalog.looks,
      factions:,
      id:,
      creature:,
      place:,
      level: row_level,
    )
  use #(checked, _shared) <- result.try(
    load_checks(catalog:, formulas:, kinds:, vendors:, shared: dict.new(), row:)
    |> result.map_error(FailsTheChecks),
  )
  case left_out_of(catalog:, checked:) {
    Ok(reason) -> Error(WouldNotStart(creature_id:, reason:))
    // A summon is a development one, outside the load's index of visibility
    // prerequisites, so it is shown to every player.
    Error(Nil) -> Ok(Spawn(..checked.spawn, visibility: None))
  }
}

/// The row of a NonPlayer unit of a creature standing at a place: the world,
/// zone, position and facing of the place, the display and the outfit that
/// `Looks` gives the creature's groups, and for both factions the creature's chosen
/// faction when the table has one (`creature_faction`), else `Creature2.factionId`,
/// as the world database sends them (`opcode.0x262.creature`). The
/// row's health is none; its level is `level`, none for the creature's `minLevel`.
pub fn creature_row(
  looks looks: Looks,
  factions factions: Factions,
  id id: SpawnId,
  creature creature: Creature2,
  place place: Place,
  level level: Option(Float),
) -> Row {
  let facing = start_place.facing(place)
  let chosen =
    creature_faction.chosen_of(factions:, creature2_id: creature.id)
    |> result.unwrap(creature.faction_id)
  Row(
    id:,
    entity_type: non_player,
    creature_id: creature.id,
    world_id: start_place.world_id(place),
    area_id: start_place.world_zone_id(place),
    x: start_place.x(place),
    y: start_place.y(place),
    z: start_place.z(place),
    rotation_x: facing.yaw,
    rotation_y: facing.pitch,
    rotation_z: facing.roll,
    display_info_id: dict.get(
      looks.first_displays,
      creature.creature2_display_group_id,
    )
      |> result.unwrap(0),
    outfit_info_id: dict.get(
      looks.first_outfits,
      creature.creature2_outfit_group_id,
    )
      |> result.unwrap(0),
    faction_id: chosen,
    base_faction_id: chosen,
    world_object_id: 0,
    world_socket_id: 0,
    health: None,
    level:,
  )
}

/// The NonPlayer row with the creature's chosen faction as both its faction and its
/// base faction, when the creature_faction table has a row for the creature, whatever
/// its row held; a row of a creature without one is unchanged. It runs before `left_out_of`, so a creature
/// whose own faction is Friendly to both player factions starts when its chosen one
/// is not.
fn with_chosen_faction(factions factions: Factions, row row: Row) -> Row {
  case creature_faction.chosen_of(factions:, creature2_id: row.creature_id) {
    Ok(chosen) -> Row(..row, faction_id: chosen, base_faction_id: chosen)
    Error(Nil) -> row
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

/// Whether the client would create the object dead: a type 13 or 32 object with
/// health 0 (`0x140457bc5`: types 4, 8, 10, 11, 12 and 14 are in the set never
/// created dead, 13 and 32 are not, opcode.0x262.simple).
fn created_dead(object: StaticObject) -> Bool {
  case object.unit_type {
    static_object.Turret | static_object.SimpleCollidable ->
      option.map(object.health, fn(health) { health.value })
      |> option.unwrap(0)
      == 0
    static_object.Door
    | static_object.Collectible
    | static_object.Simple
    | static_object.Platform
    | static_object.Mailbox
    | static_object.InstancePortal -> False
  }
}

/// The display and the outfit a creature of each group stands with: the first
/// entry of each group, a server choice, since the client's weighted pick runs
/// only for spawns it makes itself (`0x1404846c0`, `opcode.0x262.creature`).
pub opaque type Looks {
  Looks(first_displays: Dict(Int, Int), first_outfits: Dict(Int, Int))
}

/// The looks of the groups of the tables.
pub fn looks(tables tables: table_store.Tables) -> Looks {
  Looks(
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
  )
}

/// The tables' lookups by something other than an id, built once.
fn catalog(tables tables: table_store.Tables) -> Catalog {
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
    looks: looks(tables:),
    outfits: set.from_list(
      list.map(creature2_outfit_info.all(tables), fn(row) { row.id }),
    ),
    factions: faction_level.build(tables:),
    worlds: set.from_list(list.map(world.all(tables), fn(row) { row.id })),
    property_rows: list.fold(
      unit_property2.all(tables),
      dict.new(),
      fn(found, row) {
        dict.insert(found, row.id, #(row.default_value, row.flags))
      },
    ),
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

/// A faction's level toward the Exile player faction and toward the Dominion one,
/// as the client gives them (`faction_level.level`): 0 to 2 Hostile, 3 to 7 Neutral, 8 to
/// 10 Friendly. The levels a row's selection and the planted-rows guard assert.
pub fn faction_levels(
  tables tables: table_store.Tables,
  faction faction: Int,
) -> #(Int, Int) {
  let levels = faction_level.build(tables:)
  #(
    faction_level.level(levels:, from: exile_faction, to: faction),
    faction_level.level(levels:, from: dominion_faction, to: faction),
  )
}

/// The combat values and their context already worked out in a load, with the
/// creature's bases, by creature, level, display and faction: the spawns that share
/// them hold one term, so the load's term is small (a persistent term keeps the
/// sharing).
type SharedCombats =
  Dict(#(Int, Int, Int, Int), #(Combat, CombatContext, Bases))

/// A creature's base of each UnitProperty2 id, 0 to 199 in id order.
type Bases =
  List(#(UnitProperty2Id, Float))

/// The CreatureLevel row of properties 100 and above, one for every level
/// (`CreatureLevel.101`).
const last_creature_level = 101

/// What the creature brings to a fight: its display's hit radius, whom it may be
/// attacked by, and its defence. With it, the context that works its defence, offence
/// and run speed out again from changed properties (`values_of`).
fn combat_of(
  catalog catalog: Catalog,
  formulas formulas: Formulas,
  kind kind: Kind,
  creature creature: Creature2,
  level level: Int,
  bases bases: Bases,
  display_info_id display_info_id: Int,
  faction_id faction_id: Int,
) -> Result(#(Combat, CombatContext), SpawnError) {
  let creature_id = Creature2Id(creature.id)
  use display <- result.try(
    creature2_display_info.get(
      catalog.tables,
      Creature2DisplayInfoId(display_info_id),
    )
    |> result.replace_error(NoPropertyRow(
      creature_id:,
      table: "Creature2DisplayInfo",
      id: display_info_id,
    )),
  )
  let value = value_in(bases:)
  use #(attack, scaling, attack_effects) <- result.try(attack_of(
    catalog:,
    formulas:,
    kind:,
    creature:,
    level:,
    display:,
    value:,
  ))
  let context =
    CombatContext(
      formulas:,
      scaling:,
      attack: attack_effects,
      run_land: display.run_land,
    )
  let combat =
    Combat(
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
        dominion: hostile_to(
          catalog:,
          player: dominion_faction,
          unit: faction_id,
        ),
      ),
      defence: defence_of(formulas:, level:, value:),
      attack:,
      interrupt_armor: interrupt_armor_in(value:),
    )
  Ok(#(combat, context))
}

/// A creature's number for a UnitProperty2 id, from its bases or from its properties.
type Value =
  fn(Int) -> Float

/// The number of each id in `bases`, which hold every id 0 to 199.
fn value_in(bases bases: Bases) -> Value {
  let numbers =
    list.map(bases, fn(entry) { #({ entry.0 }.value, entry.1) })
    |> dict.from_list
  fn(number) {
    let assert Ok(found) = dict.get(numbers, number)
      as "bases_of builds every UnitProperty2 id 0 to 199"
    found
  }
}

/// The creature's Interrupt Armor: its property 44 is the maximum
/// (`UnitProperty2.InterruptArmor_Threshold`).
fn interrupt_armor_in(value value: Value) -> creature_life.InterruptArmor {
  creature_life.interrupt_armor_of(maximum: value(
    unit_properties.interrupt_armor_threshold.value,
  ))
}

/// The creature's defence from its properties. Each chance is a rating formula's
/// result from the creature's base and rating properties at its level (`0x140463340`
/// deflect, `0x140463ac0` critical deflect, `0x140461a30` glance chance, `0x1404615f0`
/// glance amount); a mitigation is the formula of GameFormula 1234 from Armor plus the
/// resist of its damage type and the two offsets (`0x140464240`). The damage taken of
/// each type is its multiplier and offset properties
/// (`UnitProperty2.damage_heal_multipliers`).
fn defence_of(
  formulas formulas: Formulas,
  level level: Int,
  value value: Value,
) -> hit.Defence {
  let mitigation = fn(offset_of_type, resist) {
    rating.mitigation_fraction(
      formulas:,
      level:,
      // 103 DamageMitigationPctOffset, and the offset of the type (144 to 146).
      base: value(103) +. value(offset_of_type),
      // Armor plus the resist of the type (26 to 28).
      rating: value(unit_properties.armor.value) +. value(resist),
    )
  }
  let taken = fn(type_index) {
    hit.DamageTaken(
      multiplier: value(
        unit_properties.damage_taken_multiplier_physical.value + type_index,
      ),
      offset: value(
        unit_properties.damage_taken_offset_physical.value + type_index,
      ),
    )
  }
  hit.Defence(
    // 101 BaseAvoidChance and 33 Rating_AvoidIncrease.
    deflect_chance: rating.to_fraction(
      formula: formulas.deflect_chance,
      level:,
      base: value(101),
      rating: value(33),
    ),
    // 105 BaseAvoidCritChance and 43 Rating_CritChanceDecrease.
    crit_deflect_chance: rating.to_fraction(
      formula: formulas.crit_deflect,
      level:,
      base: value(105),
      rating: value(43),
    ),
    // 164 BaseGlanceChance and 58 RatingGlanceChance.
    glance_chance: rating.to_fraction(
      formula: formulas.glance_chance,
      level:,
      base: value(164),
      rating: value(58),
    ),
    // 195 BaseGlanceAmount and 61 RatingGlanceAmount.
    glance_amount: rating.to_fraction(
      formula: formulas.glance_amount,
      level:,
      base: value(195),
      rating: value(61),
    ),
    physical_mitigation: mitigation(144, 26),
    tech_mitigation: mitigation(145, 27),
    magic_mitigation: mitigation(146, 28),
    shield_mitigation_max: 0.0,
    physical_taken: taken(0),
    tech_taken: taken(1),
    magic_taken: taken(2),
  )
}

/// The creature's own attack (genesis_prime/world_map/creature_life `Attack`): its
/// kind's spell, the damage effect its difficulty chooses by the effect's caster
/// prerequisite (type 179, `0x14049eeb0`), its blow by the creature formula
/// (`0x140565600`, GameFormula 712), its critical hit chance, severity and
/// strikethrough from its properties, its run speed (Creature2DisplayInfo.runLand
/// times property 100, `0x1405b45e0`) and its reach (the spell's `targetMaxRange`
/// plus `hit_radius`). With it, the creature scaling and each damage effect with its
/// formula, which work the blows out again from changed properties.
fn attack_of(
  catalog catalog: Catalog,
  formulas formulas: Formulas,
  kind kind: Kind,
  creature creature: Creature2,
  level level: Int,
  display display: creature2_display_info.Creature2DisplayInfo,
  value value: Value,
) -> Result(#(Attack, damage.CreatureScaling, List(AttackEffect)), SpawnError) {
  let creature_id = Creature2Id(creature.id)
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
  let creature_scaling =
    damage.CreatureScaling(
      per_level: scaling.datafloat0,
      base: scaling.datafloat01,
      overflow: scaling.datafloat02,
      divisor: scaling.datafloat03,
    )
  use attack_effects <- result.try(
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
          Ok(AttackEffect(
            blow: hit.Blow(
              spell4_effects_id: effect.id,
              damage_type: effect.damage_type,
              damage: blow_damage(
                formula:,
                damage_type: effect.damage_type,
                level:,
                scaling: creature_scaling,
                value:,
              ),
              delay_ms: effect.delay_time,
              threat_multiplier: effect.threat_multiplier,
            ),
            formula:,
          ))
      }
    }),
  )
  let attack =
    creature_life.Attack(
      spell4_id: kind.attack_spell4_id,
      offence: offence_of(
        formulas:,
        level:,
        blows: list.map(attack_effects, fn(effect) { effect.blow }),
        value:,
      ),
      run_speed: run_speed_of(run_land: display.run_land, value:),
      reach: spell.target_max_range +. hit_radius.of_creature(display:),
      area: None,
    )
  Ok(#(attack, creature_scaling, attack_effects))
}

/// One effect's damage from the creature's properties: the creature formula
/// (`0x140565600`) from its Strength (0) and Assault Rating (35), times its
/// DamageDealtMultiplier of the effect's damage type (140 + type) for the types
/// physical, tech and magic. Any other type has no multiplier, which is a choice: the
/// client's tooltip takes the larger of the property and a floor of 1 or 0
/// (`UnitProperty2.damage_heal_multipliers`).
fn blow_damage(
  formula formula: damage.Formula,
  damage_type damage_type: Int,
  level level: Int,
  scaling scaling: damage.CreatureScaling,
  value value: Value,
) -> Int {
  let multiplier = case damage_type.from_value(damage_type) {
    damage_type.Physical | damage_type.Tech | damage_type.Magic ->
      value(unit_properties.damage_dealt_multiplier_spell.value + damage_type)
    damage_type.Heal
    | damage_type.HealShields
    | damage_type.Fall
    | damage_type.Suffocate
    | damage_type.Other(..) -> 1.0
  }
  float.round(damage.creature_value(
    formula:,
    creature: damage.Creature(
      level:,
      strength: value(0),
      assault_power: damage.power_of(rating: value(
        unit_properties.assault_rating.value,
      )),
    ),
    scaling:,
    multiplier:,
  ))
}

/// The creature's offence: `blows`, and its critical hit chance, severity and
/// strikethrough from the base properties 102, 127 and 104 with no rating.
fn offence_of(
  formulas formulas: Formulas,
  level level: Int,
  blows blows: List(hit.Blow),
  value value: Value,
) -> hit.Offence {
  hit.Offence(
    blows:,
    crit_chance: rating.to_fraction(
      formula: formulas.crit_chance,
      level:,
      base: value(unit_properties.base_crit_chance.value),
      rating: 0.0,
    ),
    crit_severity: rating.to_fraction(
      formula: formulas.crit_severity,
      level:,
      base: value(unit_properties.critical_hit_severity_multiplier.value),
      rating: 0.0,
    ),
    strikethrough: rating.to_fraction(
      formula: formulas.strikethrough,
      level:,
      base: value(unit_properties.base_avoid_reduce_chance.value),
      rating: 0.0,
    ),
  )
}

/// The creature's run speed: its display's runLand times property 100
/// (`0x1405b45e0`).
fn run_speed_of(run_land run_land: Float, value value: Value) -> Float {
  run_land *. value(unit_properties.move_speed_multiplier.value)
}

/// The GameFormula row whose values scale a creature caster's damage
/// (`0x140565600`).
const creature_scaling_formula = 712

/// A creature's base of every UnitProperty2 id 0 to 199 at `level` (the client's
/// `GetCreatureProperty`, `0x1404585c0`): the creature's own override of the id when
/// it has one (Creature2OverrideProperties); else the id's default when the row's
/// flags bit 0 is set; else the CreatureLevel value times the archetype, difficulty
/// and tier multipliers of the id, each product held as a 32-bit float. An id below 100
/// reads the CreatureLevel row of `level`, the others the last row
/// (`CreatureLevel.101`) at the column of the id minus 100. A difficulty with no row
/// multiplies by 1.0. A creature whose level, tier or archetype has no row, or an id
/// with no UnitProperty2 row, fails the load.
fn bases_of(
  catalog catalog: Catalog,
  row row: Creature2,
  level level: Int,
) -> Result(Bases, SpawnError) {
  let creature_id = Creature2Id(row.id)
  let missing = fn(table, id) { NoPropertyRow(creature_id:, table:, id:) }
  use own <- result.try(
    creature_level.get(catalog.tables, CreatureLevelId(level))
    |> result.replace_error(missing("CreatureLevel", level)),
  )
  use last <- result.try(
    creature_level.get(catalog.tables, CreatureLevelId(last_creature_level))
    |> result.replace_error(missing("CreatureLevel", last_creature_level)),
  )
  use tier <- result.try(
    creature2_tier.get(catalog.tables, Creature2TierId(row.creature2_tier_id))
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
  let difficulty = case
    creature2_difficulty.get(
      catalog.tables,
      Creature2DifficultyId(row.creature2_difficulty_id),
    )
  {
    Ok(difficulty) -> creature_columns.difficulty_multipliers(row: difficulty)
    Error(Nil) -> list.repeat(1.0, 200)
  }
  list.zip(
    list.append(
      creature_columns.level_values(row: own),
      creature_columns.level_values(row: last),
    ),
    list.zip(
      creature_columns.archetype_multipliers(row: arche),
      list.zip(difficulty, creature_columns.tier_multipliers(row: tier)),
    ),
  )
  |> list.index_map(fn(columns, index) { #(index, columns) })
  |> list.try_map(fn(entry) {
    let #(index, #(value, #(archetype, #(difficulty, tier)))) = entry
    use #(default, flags) <- result.map(
      dict.get(catalog.property_rows, index)
      |> result.replace_error(missing("UnitProperty2", index)),
    )
    let base = case dict.get(catalog.overrides, #(row.id, index)) {
      Ok(override) -> override
      Error(Nil) ->
        case int.bitwise_and(flags, 1) {
          0 ->
            value
            |> float32.product(right: archetype)
            |> float32.product(right: difficulty)
            |> float32.product(right: tier)
          _ -> default
        }
    }
    #(UnitProperty2Id(index), base)
  })
}

/// Whether a player of the faction may attack a unit of the other: the unit is
/// not Friendly to it (`0x1403ad540`: a Friendly target is refused, a Hostile or a
/// Neutral one is not).
fn attackable_by(
  catalog catalog: Catalog,
  player player: Int,
  unit unit: Int,
) -> Bool {
  faction_level.level(levels: catalog.factions, from: player, to: unit)
  <= highest_neutral_level
}

/// Whether a unit of the faction fights a player of the other on sight: its level
/// toward the player's faction is Hostile, 0 to 2 (`world_data.creature_disposition`).
fn hostile_to(
  catalog catalog: Catalog,
  player player: Int,
  unit unit: Int,
) -> Bool {
  faction_level.hostile(levels: catalog.factions, from: player, to: unit)
}

/// The reason a row that passed the load checks does not start, or `Error(Nil)`
/// for a row that does, in the order of the decode: no faction, Friendly to both
/// player factions and no quest and no objective link, a service link and no quest,
/// health 0. A creature that gives or receives a quest passes the second and third, and
/// one with an objective link passes the second: the client marks
/// its quest kinds from its own Creature2 row (`0x1405a8d40`), and a Friendly
/// giver is no target (`0x1403ad540`).
fn left_out_of(
  catalog catalog: Catalog,
  checked checked: Checked,
) -> Result(LeftOut, Nil) {
  let row = checked.row
  case
    row.faction_id == 0,
    attackable_by(catalog:, player: exile_faction, unit: row.faction_id)
    || attackable_by(catalog:, player: dominion_faction, unit: row.faction_id),
    list.any(quest_ids(checked.creature), fn(id) { id != 0 }),
    has_service_link(checked.creature),
    checked.spawn.health == 0,
    objective_link.has_link(row: checked.creature)
  {
    True, _, _, _, _, _ -> Ok(NoFaction)
    False, False, False, _, _, False -> Ok(FriendlyToBoth)
    False, _, False, True, _, _ -> Ok(ServiceLink)
    False, _, _, _, True, _ -> Ok(Dead)
    False, _, _, _, False, _ -> Error(Nil)
  }
}

/// The quests the creature gives and receives, by quest id, in the order of its
/// Creature2 columns questIdGiven00 to 24 and questIdReceive00 to 24; 0 is an empty
/// column.
pub fn quest_ids(row: Creature2) -> List(Int) {
  list.append(given_quest_ids(row), received_quest_ids(row))
}

/// The quests the creature gives, by quest id, in the order of its Creature2
/// columns questIdGiven00 to 24; 0 is an empty column.
pub fn given_quest_ids(row: Creature2) -> List(Int) {
  [
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
  ]
}

/// The quests the creature receives, by quest id, in the order of its Creature2
/// columns questIdReceive00 to 24; 0 is an empty column.
pub fn received_quest_ids(row: Creature2) -> List(Int) {
  [
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
  ]
}

/// Whether the creature trains a class or a tradeskill, is a tradeskill station,
/// or links to a taxi, a bind point or an instance portal: the columns the client
/// reads for a unit's services, which wait for their own systems.
fn has_service_link(row: Creature2) -> Bool {
  list.any(
    [
      row.trainer_class_id_mask,
      row.trade_skill_id_trainer,
      row.trade_skill_id_station,
      row.taxi_node_id,
      row.bind_point_id,
      row.instance_portal_id,
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

/// The static object types in the coverage's order, by the type's number.
pub const object_types = [
  static_object.Door,
  static_object.Collectible,
  static_object.Simple,
  static_object.Platform,
  static_object.Mailbox,
  static_object.Turret,
  static_object.InstancePortal,
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
      left_out: list.map(
        [NoFaction, FriendlyToBoth, ServiceLink, Dead],
        fn(reason) {
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
        },
      ),
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
/// object its 0x262 shows. Types 4, 8, 10, 11, 12 and 14 carry the stats the row
/// records; types 13 and 32 the creature's level and health (`creature_vitals`).
fn object_checks(
  catalog catalog: Catalog,
  row row: Row,
  unit_type unit_type: static_object.UnitType,
) -> Result(StaticObject, SpawnError) {
  use Drawn(creature:, place:) <- result.try(client_checks(catalog:, row:))
  use #(level, health) <- result.try(case unit_type {
    static_object.Door
    | static_object.Collectible
    | static_object.Simple
    | static_object.Platform
    | static_object.Mailbox
    | static_object.InstancePortal ->
      Ok(#(
        option.map(row.level, float.truncate),
        option.map(row.health, fn(stat) {
          static_object.Health(value: float.truncate(stat), source: Recorded)
        }),
      ))
    static_object.Turret | static_object.SimpleCollidable ->
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
    checklist_index: 0,
    world_object_id: row.world_object_id,
    world_socket_id: row.world_socket_id,
    visibility: visibility_of(creature:),
  ))
}

/// A NonPlayer row through the client's checks (`client_checks`), with what the
/// creature brings to a fight, shared by the spawns of one creature, level,
/// display and faction.
fn load_checks(
  catalog catalog: Catalog,
  formulas formulas: Formulas,
  kinds kinds: Kinds,
  vendors vendors: Vendors,
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
  use #(#(combat, context, bases), shared) <- result.try(
    case dict.get(shared, key) {
      Ok(worked) -> Ok(#(worked, shared))
      Error(Nil) -> {
        use bases <- result.try(bases_of(catalog:, row: creature, level:))
        combat_of(
          catalog:,
          formulas:,
          kind: creature_kind.kind_of(kinds:, creature2_id: row.creature_id),
          creature:,
          level:,
          bases:,
          display_info_id: row.display_info_id,
          faction_id: row.faction_id,
        )
        |> result.map(fn(worked) {
          let worked = #(worked.0, worked.1, bases)
          #(worked, dict.insert(shared, key, worked))
        })
      }
    },
  )
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
        bases:,
        context:,
        vendor: vendor.is_vendor(vendors:, creature_id:),
        visibility: visibility_of(creature:),
        checklist_index: 0,
      ),
    ),
    shared,
  ))
}

/// The creature's visibility prerequisite, `None` for 0, which the client reads
/// as no prerequisite.
fn visibility_of(creature creature: Creature2) -> Option(PrerequisiteId) {
  let prerequisite_id = creature2.prerequisite_id_visibility(creature)
  use <- bool.guard(when: prerequisite_id.value == 0, return: None)
  Some(prerequisite_id)
}

/// Each started spawn and sent object whose visibility prerequisite does not load is
/// refused as a row of the load (the client never tests the column, so the server
/// keeps the prerequisite and every one a started spawn names must load), and the
/// prerequisites that load, each once, by number. A row the load leaves out names
/// none, so a prerequisite only a left-out creature holds is neither loaded nor
/// required.
fn visibility_judged(
  tables tables: table_store.Tables,
  judged judged: List(Judged),
  refused refused: fn(Row, SpawnError) -> Judged,
) -> #(List(Judged), Dict(Int, Prerequisite)) {
  let #(cache, rows) =
    list.map_fold(judged, dict.new(), fn(cache, one) {
      let named = case one {
        Started(checked:) ->
          Some(#(
            checked.row,
            checked.spawn.creature_id,
            checked.spawn.visibility,
          ))
        ObjectSent(row:, object:) ->
          Some(#(row, object.creature_id, object.visibility))
        Other(..) | Excluded(..) | Refused(..) | ObjectDead(..) -> None
      }
      case named {
        Some(#(row, creature_id, Some(prerequisite_id))) -> {
          let #(cache, found) =
            loaded_prerequisite(tables:, cache:, prerequisite_id:)
          case found {
            Ok(_) -> #(cache, one)
            Error(reason) -> #(
              cache,
              refused(
                row,
                NoVisibilityRow(creature_id:, prerequisite_id:, reason:),
              ),
            )
          }
        }
        Some(#(_, _, None)) | None -> #(cache, one)
      }
    })
  #(
    rows,
    dict.to_list(cache)
      |> list.filter_map(fn(one) {
        result.map(one.1, fn(prerequisite) { #(one.0, prerequisite) })
      })
      |> dict.from_list,
  )
}

/// The prerequisite loaded from the tables, kept in the cache by number.
fn loaded_prerequisite(
  tables tables: table_store.Tables,
  cache cache: Dict(Int, Result(Prerequisite, prerequisite.LoadError)),
  prerequisite_id prerequisite_id: PrerequisiteId,
) -> #(
  Dict(Int, Result(Prerequisite, prerequisite.LoadError)),
  Result(Prerequisite, prerequisite.LoadError),
) {
  case dict.get(cache, prerequisite_id.value) {
    Ok(found) -> #(cache, found)
    Error(Nil) -> {
      let found =
        prerequisite.load(
          id: prerequisite_id,
          rows: prerequisite.table_rows(tables:),
          arcs: prerequisite.table_arcs(tables:),
          quests: prerequisite.table_quests(tables:),
        )
      #(dict.insert(cache, prerequisite_id.value, found), found)
    }
  }
}

/// The loaded visibility prerequisites of a load's started spawns and sent objects,
/// by world: each distinct prerequisite of a world once, in id order.
fn visibility_index(
  loaded loaded: Dict(Int, Prerequisite),
  started started: List(Spawn),
  objects objects: List(StaticObject),
) -> Dict(Int, List(Prerequisite)) {
  let named =
    list.append(
      list.map(started, fn(spawn) {
        #(start_place.world_id(spawn.place), spawn.visibility)
      }),
      list.map(objects, fn(object) {
        #(start_place.world_id(object.place), object.visibility)
      }),
    )
  list.filter_map(named, fn(one) {
    case one {
      #(world_id, Some(prerequisite_id)) ->
        Ok(#(world_id, prerequisite_id.value))
      #(_, None) -> Error(Nil)
    }
  })
  |> list.unique
  |> list.group(fn(one) { one.0 })
  |> dict.map_values(fn(_world_id, ones) {
    ones
    |> list.map(fn(one) { one.1 })
    |> list.sort(int.compare)
    |> list.filter_map(fn(number) { dict.get(loaded, number) })
  })
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
        || dict.has_key(
        catalog.looks.first_outfits,
        row.creature2_outfit_group_id,
      ),
      NoOutfitEntries,
    ),
  ]
  case list.find(rules, fn(rule) { !rule.0 }) {
    Ok(#(_, rule)) -> Error(NotLoadedByTheClient(creature_id:, rule:))
    Error(Nil) -> Ok(row)
  }
}

/// Base Health: property 7 at `level`, truncated (`bases_of`). The client looks the
/// three multipliers up by the creature's words 4, 5 and 6, which are the archetype,
/// difficulty and tier (`0x1404585c0`, `0x1404852b0`).
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
  use bases <- result.map(bases_of(catalog:, row:, level:))
  let assert Ok(health) = list.key_find(bases, unit_properties.base_health)
    as "bases_of builds every UnitProperty2 id 0 to 199"
  float.truncate(health)
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
    ServiceLink -> "a service link"
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
      <> " for its properties"
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
    NoVisibilityRow(
      creature_id: Creature2Id(creature_id),
      prerequisite_id:,
      reason:,
    ) ->
      "Creature2 "
      <> int.to_string(creature_id)
      <> " has visibility prerequisite "
      <> int.to_string(prerequisite_id.value)
      <> ", which does not load: "
      <> prerequisite.describe_load_error(error: reason)
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
