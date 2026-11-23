//// The activate cast of a creature the player right-clicks, a collectible such as the
//// Seaspine Mollusk: which spell it casts, how far the player may stand from it, and
//// the plans the cast runs from.
////
//// ```
//// Creature2 row ─▶ creature_of ─▶ pick(columns, check) ─▶ Picked(spell) | NoActivateSpell | Unread
//// the spell's Spell4 row and Activate effects ─▶ Planned (built once when the tables load)
//// range_of(creature, planned, caster body, target body) ─▶ Within | TooClose | TooFar | TooHigh
//// ```
////
//// - **The spell** is the first of the creature's four activate columns whose prerequisite
////   is 0 or passes for the player with the creature as the second unit, even when that
////   column's spell is 0; when none passes it is GameFormula 414's dataint0 (8)
////   (`0x14046c580`). Spell 0 is refused with result 100.
//// - **The range** is edge to edge, in three dimensions, with no margin: the distance is
////   that between the two units' places less both hit radii, never below 0
////   (`opcode.0x97.range`, `0x1403b2240`). A spell among the creature's columns is held to
////   the creature's own limits (a max of 0 falls back to the spell's), any other spell to
////   the Spell4 row's (`0x1403ad860`, `0x1403ad8f0`).
//// - **The plans** hold each activate spell's Spell4 row, plan and Activate effects, and
////   the Prerequisite rows the columns name; the Creature2 rows are read from the tables
////   when an activation arrives (the derivation stores none of the 8,463 creatures that
////   have an activate column).
//// - **An item's spell** (ItemSpecial.spell4IdOnActivate) with an Activate effect or a
////   QuestAdvanceObjective effect is planned too, for the cast of an item (`cast.use_item`):
////   its use at a unit counts that unit as an activate cast does when the spell has an Activate
////   effect, and a QuestAdvanceObjective row advances the player's objective
////   (genesis_prime/game/quest_advance). Item spells with neither are not planned.
//// - **The cast group** of a spell cast at a creature is checked as the client does
////   (`passes_cast_group`): a member of the group passes, and so does any creature when the
////   spell has no group and Creature2.flags bit 0 is clear; otherwise only the creature's
////   own activate spell passes, and the rest are refused 89.
//// - A spell with an effect the strike would apply, aimed at the target or an area, is
////   refused with result 285 and logged once, since the activate cast strikes no unit; a
////   heal, RavelSignal, DespawnUnit or UnitStateSet row aimed there is dropped instead
////   (`activate_rows_of`).
//// - **The target's life** is judged before the range: the spell's target row says a dead
////   creature is refused 106 or a living one 107 (`CheckCastUnitTargetRange`,
////   `0x1403b2240`). A unit hostile to the player or in combat is offered no use at all
////   (`Withheld`, result 100).
//// - **Not modelled** (`planned`): the client's per-unit vertical offset, the creature
////   words 0x6c and 0x148 that make the client pick no spell, the target row's
////   crowd-control and fight-state conditions and the unit word 0xc4 that bit 5 reads.

import genesis_prime/game/effect_kind
import genesis_prime/game/item_property
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/spell_plan.{type Limits, type Spell, Limits}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/gap
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/table/creature2
import genesis_prime/table/game_formula
import genesis_prime/table/id.{
  type Spell4EffectsId, GameFormulaId, PrerequisiteId, Spell4ConditionsId,
  Spell4EffectsId, Spell4Id,
}
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import genesis_prime/world_map/creature_path
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set.{type Set}

/// The GameFormula row whose dataint0 is the spell a creature casts when none of its
/// columns passes (`0x14046c580`).
const default_spell_formula = 414

/// One of a creature's four activate columns.
pub type Column {
  Column(prerequisite_id: Int, spell4_id: Int)
}

/// What a Creature2 row says of its activate cast.
pub type Creature {
  Creature(
    columns: List(Column),
    /// Creature2.activateSpellCastTime: the cast time of an activate cast of a spell among
    /// the creature's columns when it is not 0; any other spell casts with its own
    /// (`0x1407a1680`, `0x14054e340`; see `cast_time_for`).
    cast_time_ms: Int,
    /// Creature2.activateSpellMinRange and activateSpellMaxRange.
    min_range: Float,
    max_range: Float,
    /// Creature2.flags: bit 0 marks a creature only its own activate spell, or a spell
    /// whose cast group names it, may be cast at (`passes_cast_group`).
    flags: Int,
  )
}

/// The creature's activate columns in order, with its cast time, range and flags.
pub fn creature_of(row row: creature2.Creature2) -> Creature {
  Creature(
    columns: [
      Column(row.prerequisite_id_activate_spell00, row.spell4_id_activate00),
      Column(row.prerequisite_id_activate_spell01, row.spell4_id_activate01),
      Column(row.prerequisite_id_activate_spell02, row.spell4_id_activate02),
      Column(row.prerequisite_id_activate_spell03, row.spell4_id_activate03),
    ],
    cast_time_ms: row.activate_spell_cast_time,
    min_range: row.activate_spell_min_range,
    max_range: row.activate_spell_max_range,
    flags: row.flags,
  )
}

/// The Creature2.activationFlags bit that keeps the client from offering the Spell kind
/// (`0x140479560`).
const no_spell_offer_flag = 0x800

/// The Creature2.uiFlags bit that locks a creature's clicks to the path kinds unless its
/// quest link is open (`0x14046c6a0`).
const path_lock_flag = 0x80

/// Whether the client can offer a click on the creature by its own activate spell, from its
/// row alone: a column names a spell, activationFlags bit 0x800 is clear, the datacube and
/// the datacube volume are 0 (`0x140479560`, kind Spell 50), and uiFlags bit 0x80 is clear.
/// A creature with that bit is locked to the path kinds and offers no click while its quest
/// link is closed (`0x14046c6a0`, `0x14046c4d0`); the row cannot tell whether a link is open
/// now, so such a creature is taken as offering none. Whether a column's prerequisite passes
/// for a player, and the client words 0x6c and 0x148 that make the pick 0, are not read
/// (`pick`).
pub fn offers_click(row row: creature2.Creature2) -> Bool {
  list.any(creature_of(row:).columns, fn(column) { column.spell4_id != 0 })
  && int.bitwise_and(row.activation_flags, no_spell_offer_flag) == 0
  && row.datacube_id == 0
  && row.datacube_volume_id == 0
  && int.bitwise_and(row.ui_flags, path_lock_flag) == 0
}

/// Which spell a creature casts for a player.
pub type Pick {
  /// The Spell4 id of the spell, never 0.
  Picked(spell4_id: Int)
  /// The creature has no activate spell for the player: result 100.
  NoActivateSpell
  /// A column's prerequisite holds a condition the server does not read, so the
  /// client's pick cannot be told.
  Unread(prerequisite_type: Int)
}

/// The spell the creature casts: the first column whose prerequisite is 0 or whose
/// `check` passes, else `default_spell`; spell 0 is no activate spell.
pub fn pick(
  creature creature: Creature,
  default_spell default_spell: Int,
  check check: fn(Int) -> prerequisite.Verdict,
) -> Pick {
  let chosen =
    list.try_fold(creature.columns, default_spell, fn(default, column) {
      case column.prerequisite_id {
        0 -> Error(Ok(column.spell4_id))
        prerequisite_id ->
          case check(prerequisite_id) {
            prerequisite.Passes -> Error(Ok(column.spell4_id))
            prerequisite.Fails -> Ok(default)
            prerequisite.NotRead(prerequisite_type:) ->
              Error(Error(prerequisite_type))
          }
      }
    })
  case chosen {
    Ok(spell4_id) | Error(Ok(spell4_id)) ->
      case spell4_id {
        0 -> NoActivateSpell
        _ -> Picked(spell4_id:)
      }
    Error(Error(prerequisite_type)) -> Unread(prerequisite_type:)
  }
}

/// What the client's cast check against a spell's cast group says of a creature target.
pub type CastGroup {
  /// The check passes.
  InCastGroup
  /// The check refuses the cast: result 89 (TargetGroup).
  OutsideCastGroup
  /// The creature's own pick rests on a prerequisite the server does not read, and one
  /// of its columns names the spell, so whether the spell is its activate spell cannot
  /// be told.
  CastGroupUnread(prerequisite_type: Int)
}

/// The client's check of a spell cast at a creature against the spell's cast group
/// (`CheckCastActivateSpell` `0x1403b44b0`, run by `CheckCastUnitTargetRange`
/// `0x1403b2240` before a cast at a unit is sent). A spell with a cast group
/// (`cast_group_id`, Spell4Base.targetGroupIdCastGroup, 0 for none) passes a member
/// (`in_cast_group`), and a spell with none passes a creature whose Creature2.flags
/// has bit 0 clear; both pass whatever the creature's pick is. Any other cast passes
/// only when the spell is the creature's own activate spell, else it is refused 89.
pub fn passes_cast_group(
  spell4_id spell4_id: Int,
  cast_group_id cast_group_id: Int,
  creature creature: Creature,
  picked picked: Pick,
  in_cast_group in_cast_group: fn(Int) -> Bool,
) -> CastGroup {
  let passes_at_once = case cast_group_id {
    0 -> int.bitwise_and(creature.flags, 1) == 0
    group -> in_cast_group(group)
  }
  case passes_at_once, picked {
    True, _ -> InCastGroup
    False, Picked(spell4_id: own) if own == spell4_id -> InCastGroup
    False, Picked(..) | False, NoActivateSpell -> OutsideCastGroup
    False, Unread(prerequisite_type:) ->
      case
        list.any(creature.columns, fn(column) { column.spell4_id == spell4_id })
      {
        True -> CastGroupUnread(prerequisite_type:)
        False -> OutsideCastGroup
      }
  }
}

/// An Activate effect of a spell: its row, the delay the go lists it with and the phases
/// it is listed in (Spell4Effects.phaseFlags: bit n is phase n, every bit for -1).
pub type ActivateEffect {
  ActivateEffect(effect_id: Spell4EffectsId, delay_ms: Int, phase_flags: Int)
}

/// What the plans hold of an activate spell.
pub type Planned {
  /// The spell's plan, its Activate effects in row order, the RavelSignal and DespawnUnit
  /// rows aimed at the target that the activate cast drops (`Dropped`), its Spell4 limits and its cast group
  /// (Spell4Base.targetGroupIdCastGroup, 0 for none; `passes_cast_group` tests it). A
  /// spell of a method the cast rule does not
  /// build is held too: the press is refused as an ability's is (`cast_press.verdict`).
  Planned(
    spell: Spell,
    effects: List(ActivateEffect),
    dropped: Dropped,
    limits: Limits,
    cast_group_id: Int,
  )
  /// The Spell4 table has no row for the spell: result 4.
  NoSpell4Row
  /// The spell's tree cannot be planned: the reason in words.
  CannotBePlanned(why: String)
}

/// The activate spells' plans and the Prerequisite rows of the columns and of the items,
/// as the load built them. A link column's prerequisite whose row the table lacks is not
/// held (47 creatures name 33 such ids): the client fails a prerequisite it cannot find
/// (`Prerequisite.flags`), so the link is closed (`objective_link.of`).
pub type Activations {
  Activations(
    /// Each Prerequisite a creature's activate column, a creature's link or an item names,
    /// by id.
    prerequisites: Dict(Int, Prerequisite),
    /// Each spell an activate column names, and the default spell, by Spell4 id.
    spells: Dict(Int, Planned),
    /// GameFormula 414's dataint0.
    default_spell: Int,
  )
}

const activations_key: table_store.DerivedKey(Activations) =
  table_store.DerivedKey("Activations")

/// The activations as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`), after the ability trees: a missing
/// GameFormula or Prerequisite row, or a cycle in the Prerequisite rows, fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: activations_key, build: fn(tables) {
    build(tables:)
    |> result.map_error(fn(error) {
      case error {
        NoDefaultSpellFormula ->
          "the table GameFormula has no row "
          <> int.to_string(default_spell_formula)
        PrerequisiteNotLoaded(error:) -> spell_plan.describe(error:)
        LinkOrItemPrerequisiteNotLoaded(error:) ->
          prerequisite.describe_load_error(error:)
      }
    })
  })
}

/// Why the activations cannot be built from the tables.
type BuildError {
  NoDefaultSpellFormula
  PrerequisiteNotLoaded(error: spell_plan.PlanError)
  LinkOrItemPrerequisiteNotLoaded(error: prerequisite.LoadError)
}

/// The activations the tables' load built.
pub fn activations(tables tables: table_store.Tables) -> Activations {
  table_store.derived(tables:, key: activations_key)
}

/// Builds the activations from the loaded tables, or why they cannot be built: the
/// derivation's body.
fn build(tables tables: table_store.Tables) -> Result(Activations, BuildError) {
  use default_spell <- result.try(
    game_formula.get(tables:, id: GameFormulaId(default_spell_formula))
    |> result.map(fn(row) { row.dataint0 })
    |> result.replace_error(NoDefaultSpellFormula),
  )
  let columns =
    creature2.all(tables)
    |> list.flat_map(fn(row) { creature_of(row:).columns })
  let prerequisite_ids =
    list.map(columns, fn(column) { column.prerequisite_id })
    |> list.filter(fn(prerequisite_id) { prerequisite_id != 0 })
    |> list.unique
  let rows = prerequisite.table_rows(tables:)
  let arcs = prerequisite.table_arcs(tables:)
  let quests = prerequisite.table_quests(tables:)
  use prerequisites <- result.try(
    list.try_map(prerequisite_ids, fn(prerequisite_id) {
      spell_plan.column_of(id: prerequisite_id, rows:, arcs:, quests:)
      |> result.map(fn(loaded) { #(prerequisite_id, loaded) })
    })
    |> result.map_error(PrerequisiteNotLoaded),
  )
  use anim_prerequisites <- result.try(
    list.try_fold(
      list.append(
        anim_prerequisite_ids(tables:),
        item_prerequisite_ids(tables:),
      )
        |> list.unique,
      [],
      fn(loaded, prerequisite_id) {
        case
          prerequisite.load(
            id: PrerequisiteId(prerequisite_id),
            rows:,
            arcs:,
            quests:,
          )
        {
          Ok(held) -> Ok([#(prerequisite_id, held), ..loaded])
          // The client fails a prerequisite it has no row for (`Prerequisite.flags`), so
          // such a link is closed; the tables name rows they lack (see `Activations`).
          Error(prerequisite.NoPrerequisiteRow(..)) -> Ok(loaded)
          Error(error) -> Error(LinkOrItemPrerequisiteNotLoaded(error:))
        }
      },
    ),
  )
  let sources = spell_plan.sources_of(tables:)
  let spell_ids = set.to_list(activated_spell_ids(tables:, sources:))
  Ok(Activations(
    prerequisites: list.filter_map(prerequisites, fn(entry) {
      option.to_result(entry.1, Nil)
      |> result.map(fn(loaded) { #(entry.0, loaded) })
    })
      |> list.append(anim_prerequisites)
      |> dict.from_list,
    spells: list.map(spell_ids, fn(spell4_id) {
      #(spell4_id, planned(tables:, sources:, spell4_id:))
    })
      |> dict.from_list,
    default_spell:,
  ))
}

/// The spells an activate cast can name: the default spell (when the tables hold its
/// GameFormula row), the spells in a creature's activate columns and the spells an item
/// casts when used that hold an Activate or a QuestAdvanceObjective row. These are the spells `planned_rows` reads
/// and whose despawn rows the activate cast drops (`drops_despawn`).
pub fn activated_spell_ids(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
) -> Set(Int) {
  let default_spell =
    game_formula.get(tables:, id: GameFormulaId(default_spell_formula))
    |> result.map(fn(row) { row.dataint0 })
    |> result.unwrap(0)
  [
    default_spell,
    ..list.append(
      list.flat_map(creature2.all(tables), fn(row) {
        list.map(creature_of(row:).columns, fn(column) { column.spell4_id })
      }),
      item_spell_ids(tables:, sources:),
    )
  ]
  |> list.filter(fn(spell4_id) { spell4_id != 0 })
  |> set.from_list
}

/// The spells an item casts when used (ItemSpecial.spell4IdOnActivate) that have an
/// Activate or a QuestAdvanceObjective effect: an item's use counts an objective through the
/// first and a cast advances one through the second, and the other item spells are the cast
/// rule's to refuse as unbuilt.
fn item_spell_ids(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
) -> List(Int) {
  item_property.spells_on_activate(tables:)
  |> list.filter(fn(spell4_id) {
    list.any(spell_plan.effects_of(sources:, spell4_id:), fn(effect) {
      let kind = effect_kind.kind_of(effect_type: effect.effect_type)
      kind == effect_kind.Activate || kind == effect_kind.QuestAdvance
    })
  })
}

/// The ids of the Prerequisite rows the creatures' link columns name
/// (`Creature2.prerequisiteIdAnimState`).
fn anim_prerequisite_ids(tables tables: table_store.Tables) -> List(Int) {
  creature2.all(tables)
  |> list.map(fn(row) { row.prerequisite_id_anim_state })
  |> list.filter(fn(prerequisite_id) { prerequisite_id != 0 })
  |> list.unique
}

/// The ids of the Prerequisite rows the items name (`Item2.prerequisiteId`), which UseItem
/// evaluates before it starts the item's cast (`0x1403998e0`).
fn item_prerequisite_ids(tables tables: table_store.Tables) -> List(Int) {
  item2.all(tables)
  |> list.map(fn(row) { row.prerequisite_id })
  |> list.filter(fn(prerequisite_id) { prerequisite_id != 0 })
  |> list.unique
}

fn planned(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  spell4_id spell4_id: Int,
) -> Planned {
  case spell4.get(tables:, id: Spell4Id(spell4_id)) {
    Error(Nil) -> NoSpell4Row
    Ok(row) ->
      case spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: []) {
        Error(error) -> CannotBePlanned(why: spell_plan.describe(error:))
        Ok(spell) ->
          case
            unread_target_bits(
              tables:,
              conditions_id: row.spell4_conditions_id_target,
            )
          {
            Some(#(mask, unread)) ->
              CannotBePlanned(
                why: "the spell "
                <> int.to_string(spell4_id)
                <> " tests the bits "
                <> int.to_string(unread)
                <> " of its target conditions row "
                <> int.to_string(row.spell4_conditions_id_target)
                <> " (mask "
                <> int.to_string(mask)
                <> "), which the activate cast does not read",
              )
            None -> planned_rows(tables:, spell:, sources:, spell4_id:, row:)
          }
      }
  }
}

/// What the activate cast does not check of a target, strike or pick.
pub fn gaps() -> List(gap.Entry) {
  [
    "An activate cast does not test the target's crowd-control state, fight state or creature word 0x1e4 against the Spell4Conditions mask of its spell, and passes bit 5 of the mask without testing it, because the meaning of the unit word 0xc4 that bit reads is not decoded.",
    "An activate cast strikes no unit: it carries out the effects of its spell that reach the caster and its Activate effects, and a spell with any other effect the strike would apply to the target or an area is refused.",
    "An activate cast drops a Heal, RavelSignal, DespawnUnit or UnitStateSet effect aimed at the target or an area, the last three with one log line for the spell, so a spell with such an effect stays usable without it.",
    "An activate cast of a QuestAdvanceObjective effect aimed at the primary target alone advances nothing, because the unit the cast names is not the caster.",
    "The client's per-unit vertical offset of an activate cast is not modelled.",
    "The creature words 0x6c and 0x148, which make the client pick no spell for a creature, are not read.",
  ]
  |> list.map(fn(missing) { gap.Entry(area: "Casting", missing:) })
}

/// The mask of a Spell4Conditions row of a target and its bits that the activate cast
/// does not read (`spell_plan.target_mask_read`), when it has any.
///
/// The client also tests the unit's crowd-control state, its fight state and the
/// creature word 0x1e4 against such a row, and the meaning of the unit word 0xc4 that
/// bit 5 tests is not decoded, so bit 5 passes; no activate spell of the tables
/// tests a bit outside the ones read, so the spell that does is not planned.
fn unread_target_bits(
  tables tables: table_store.Tables,
  conditions_id conditions_id: Int,
) -> Option(#(Int, Int)) {
  case conditions_id {
    0 -> None
    id ->
      case spell4_conditions.get(tables:, id: Spell4ConditionsId(id)) {
        Error(Nil) -> None
        Ok(row) ->
          case
            int.bitwise_and(
              row.condition_mask,
              int.bitwise_not(spell_plan.target_mask_read),
            )
          {
            0 -> None
            unread -> Some(#(row.condition_mask, unread))
          }
      }
  }
}

fn planned_rows(
  tables tables: table_store.Tables,
  spell spell: Spell,
  sources sources: spell_plan.Sources,
  spell4_id spell4_id: Int,
  row row: spell4.Spell4,
) -> Planned {
  case activate_rows_of(sources:, spell4_id:) {
    Error(AimedAtTarget(effect_id:)) ->
      CannotBePlanned(
        why: "the effect "
        <> int.to_string(effect_id)
        <> " of the spell "
        <> int.to_string(spell4_id)
        <> " aims at the target or an area, and the activate cast strikes no one",
      )
    Ok(ActivateRows(effects:, dropped:)) ->
      Planned(
        spell:,
        effects:,
        dropped:,
        limits: spell_plan.limits_of(row:),
        cast_group_id: case
          spell4_base.get(tables:, id: spell4.spell4_base_id_base_spell(row))
        {
          Ok(base) -> base.target_group_id_cast_group
          Error(Nil) -> 0
        },
      )
  }
}

/// An effect of an activate spell that aims at the target or an area and that the strike
/// would apply.
type AimedAtTarget {
  AimedAtTarget(effect_id: Int)
}

/// What an activate spell's rows leave for the activate cast.
type ActivateRows {
  ActivateRows(effects: List(ActivateEffect), dropped: Dropped)
}

/// The rows of an activate spell that the activate cast drops, aimed at the target or an
/// area, in row order: RavelSignal rows, which start a script the server does not have,
/// DespawnUnit rows, which remove a creature the activate cast has no strike to name, and
/// UnitStateSet rows, which hold a state on a creature the same way (`activate_rows_of`).
pub type Dropped {
  Dropped(
    signals: List(Spell4EffectsId),
    despawns: List(Spell4EffectsId),
    unit_states: List(Spell4EffectsId),
  )
}

/// Whether a row's effect reaches a unit past the caster: its aim names the primary target or
/// the area, or its flags are one no aim reads (which a row of a kind the plan reads then
/// refuses itself).
fn reaches_past_caster(effect effect: Spell4Effects) -> Bool {
  case spell_plan.aim_of(target_flags: effect.target_flags) {
    Ok(aim) -> spell_plan.reaches_past_caster(aim:)
    Error(Nil) -> True
  }
}

/// The Activate rows of the spell and the RavelSignal rows it drops, or the first effect
/// that aims at the target or an area and that the strike would apply.
///
/// The activate cast carries out the caster's effects and the Activate rows and
/// strikes no unit, so a spell with such an effect would lose it without a word; it is
/// refused instead. An effect is one the strike applies when `effect_kind.is_row_read`
/// holds for its type and aim: the strike lists a Fluff or Scale row as a life on each
/// struck unit (genesis_prime/game/cast `aimed_at`) and starts a Proxy's spell at it. A
/// row of a type no rule reads is dropped by every cast, so it does not refuse the spell.
///
/// A QuestAdvanceObjective row aimed at the target does not refuse the spell either: the
/// plan keeps it, and the go applies it by `spell_plan.quest_advance_lands_on_the_caster`
/// (genesis_prime/game/cast `quest_advances_armed`), so a row aimed at the primary target alone,
/// which is the unit the activate cast names and not the caster, advances nothing (a guess:
/// `Spell4Effects.targetFlags` has no reader). Such a spell (40061, rows 88719 and 88720)
/// activates as before.
///
/// A Heal row aimed at the target or an area does not refuse the spell either, and the
/// activate cast drops it: the server restores only the caster's own vitals, so a heal
/// aimed at a creature lands nothing in any cast (`cast_heal.healed_on`), and the activate
/// cast strikes no one. Six activate spells of the tables hold one (Spell4 34519, 39299,
/// 39536, 54204, 66484 and 66599); refusing them would make a creature's use, which a
/// quest objective counts, unreachable.
///
/// A RavelSignal row aimed at the target does not refuse the spell, and the activate cast
/// drops it: the row starts a script on the server (`Spell4Effects.effectType.81`), and
/// the server has no script to start;
/// the client holds no script for it, so what it shows is not lost. The tutorial mine's
/// activate spell 85452 holds two such rows. They are returned, and the cast logs them
/// once when it drops them (`cast.activation_started`).
///
/// A UnitStateSet row aimed at the target or an area is dropped the same way, since the
/// activate cast strikes no creature to hold the state: no client row of the type sits in an
/// activated spell, so no activation of the client's data is affected.
///
/// A DespawnUnit row aimed at the target or an area is dropped the same way: it removes the
/// creatures a strike hits and the activate cast strikes none, and the unit a player
/// activates may be a static object, which the map retires. 218 rows of the tables are
/// in spells that hold an Activate row, more in other spells a creature's activate column
/// names, and refusing them would make a quest object that activates today unusable. The rows are logged once per spell when the cast starts (`cast.activation_started`).
fn activate_rows_of(
  sources sources: spell_plan.Sources,
  spell4_id spell4_id: Int,
) -> Result(ActivateRows, AimedAtTarget) {
  let #(activates, others) =
    spell_plan.effects_of(sources:, spell4_id:)
    |> list.partition(fn(effect) {
      effect_kind.kind_of(effect_type: effect.effect_type)
      == effect_kind.Activate
    })
  let #(signals, others) =
    list.partition(others, fn(effect) {
      reaches_past_caster(effect:)
      && effect_kind.kind_of(effect_type: effect.effect_type)
      == effect_kind.RavelSignal
    })
  let #(despawns, others) = list.partition(others, drops_despawn)
  let #(unit_states, others) = list.partition(others, drops_unit_state)
  case
    list.find(others, fn(effect) {
      reaches_past_caster(effect:)
      && !is_heal(effect_type: effect.effect_type)
      && !is_quest_advance(effect_type: effect.effect_type)
      && effect_kind.is_row_read(
        effect_type: effect.effect_type,
        target_flags: effect.target_flags,
      )
    })
  {
    Ok(effect) -> Error(AimedAtTarget(effect_id: effect.id))
    Error(Nil) ->
      Ok(ActivateRows(
        effects: list.map(activates, fn(effect) {
          ActivateEffect(
            effect_id: Spell4EffectsId(effect.id),
            delay_ms: effect.delay_time,
            phase_flags: effect.phase_flags,
          )
        }),
        dropped: Dropped(
          signals: list.map(signals, fn(effect) { Spell4EffectsId(effect.id) }),
          despawns: list.map(despawns, fn(effect) { Spell4EffectsId(effect.id) }),
          unit_states: list.map(unit_states, fn(effect) {
            Spell4EffectsId(effect.id)
          }),
        ),
      ))
  }
}

/// Whether the activate cast drops this effect of its spell: a DespawnUnit row that reaches a
/// unit past the caster. The activate cast strikes no unit, so there is no creature for the
/// row to remove, in whatever spell a creature's activate column names.
pub fn drops_despawn(effect effect: Spell4Effects) -> Bool {
  effect_kind.kind_of(effect_type: effect.effect_type) == effect_kind.Despawn
  && reaches_past_caster(effect:)
}

/// Whether the activate cast drops this effect of its spell: a UnitStateSet row that reaches a
/// unit past the caster. The activate cast strikes no creature, so there is none to hold the
/// state.
fn drops_unit_state(effect effect: Spell4Effects) -> Bool {
  effect_kind.kind_of(effect_type: effect.effect_type) == effect_kind.UnitState
  && reaches_past_caster(effect:)
}

/// Whether the effect type is a QuestAdvanceObjective: its row advances the caster's own
/// objective, so a row aimed past the caster stays in the plan and the go does not apply it
/// (`drops_quest_advance`).
fn is_quest_advance(effect_type effect_type: Int) -> Bool {
  effect_kind.kind_of(effect_type:) == effect_kind.QuestAdvance
}

/// Whether the activate cast advances nothing for this effect: a QuestAdvanceObjective row
/// that does not land on the caster when the primary target is the unit it activates
/// (`spell_plan.quest_advance_lands_on_the_caster`, the rule the cast's go applies), which is a row aimed
/// at the primary target alone.
pub fn drops_quest_advance(effect effect: Spell4Effects) -> Bool {
  is_quest_advance(effect_type: effect.effect_type)
  && !spell_plan.quest_advance_lands_on_the_caster(
    aim: spell_plan.quest_advance_aim_of(target_flags: effect.target_flags),
    primary_target_is_caster: False,
  )
}

/// Whether the effect type is a heal of health or of shield.
fn is_heal(effect_type effect_type: Int) -> Bool {
  let kind = effect_kind.kind_of(effect_type:)
  kind == effect_kind.Heal(vital: effect_kind.Health)
  || kind == effect_kind.Heal(vital: effect_kind.Shield)
}

/// The prerequisite check of the pick for one subject: a column's prerequisite, by id,
/// with the player as the first unit and the creature as the second. One the plans do
/// not hold is not read (type 0), which no column of the tables names, since the load
/// holds each column's prerequisite.
pub fn checker(
  activations activations: Activations,
  subject subject: prerequisite.Subject,
) -> fn(Int) -> prerequisite.Verdict {
  fn(prerequisite_id) {
    case dict.get(activations.prerequisites, prerequisite_id) {
      Ok(held) -> prerequisite.check(prerequisite: held, subject:)
      Error(Nil) -> prerequisite.NotRead(prerequisite_type: 0)
    }
  }
}

/// What the unit a right-click names is, as the player's connection knows it.
pub type Target {
  /// The unit is not in the player's picture.
  Unseen
  /// Another player's unit.
  AnotherPlayer
  /// A creature or static object the player can see: the id of its Creature2 row, what
  /// the row says of its activate cast, the checklist index its 0x262 carried (the bit a
  /// type 94 condition of its activate pick reads), whether the player's quest log opens
  /// the creature's link to an objective, where it stands now (a creature that walks a
  /// path stands where its path puts it at the press), whether it lives, and why the
  /// client offers no use of it, if it does not.
  Usable(
    creature_id: Int,
    creature: Creature,
    checklist_index: Int,
    link: Link,
    body: Body,
    alive: Bool,
    /// Whether the creature is in combat, which a cast's target conditions may test (bit 1
    /// of the target row's mask).
    in_combat: Bool,
    /// The crowd-control states the creature holds as the player's client was told, which
    /// the cast's target conditions refuse (Spell4CCConditions `ccStateMask`).
    held: List(CrowdControlState),
    /// The unit states the creature holds as the player's picture shows them, by number
    /// (genesis_prime/game/unit_state), which a hostile or beneficial press is refused for.
    unit_states: List(Int),
    withheld: Option(Withheld),
  )
}

/// Why the client offers a unit no use of it (`PickInteractionKind`, `0x14047a060`): the
/// press is refused with result 100.
pub type Withheld {
  /// The unit is hostile to the player: the client skips the interaction kinds of a use.
  HostileToPlayer
  /// The unit is in combat: the client gives it no click at all.
  InCombat
}

/// Whether the player's quest log opens a creature's link to an objective, which the
/// client's offer of the creature's activation waits for (`0x14046c4d0`).
pub type Link {
  /// The creature has no quest animation column and no animation prerequisite: nothing
  /// holds its activation back.
  NoLink
  /// The creature's link is open: the client offers its activation.
  OpenLink
  /// The creature's link is closed: the client offers it nothing at all, and the server
  /// takes no activation of it.
  ClosedLink
  /// The creature's animation prerequisite has a condition of this PrerequisiteType that
  /// the server does not read, so the client's offer cannot be told: the server takes no
  /// activation of it.
  UnreadLink(prerequisite_type: Int)
}

/// The range of the client's use of a unit whose creature has no activate spell (0xb3):
/// the interaction entry of kind 39 holds range 0.0, which ClickInteraction replaces by
/// 5.0 (`0x14039d2c0`, `0x140c48c48`), tested edge to edge in three dimensions with no
/// height limit (`0x1403ebe80`).
pub const use_limits = Limits(min: 0.0, max: 5.0, vertical: -1.0)

/// A unit's body for the range test: where it stands (y is up) and its hit radius.
pub type Body {
  Body(place: Place, radius: Float)
}

/// How far the caster stands from the target.
pub type Range {
  Within
  /// Result 104.
  TooClose
  /// Result 105.
  TooFar
  /// Result 183.
  TooHigh
}

/// Whether `spell4_id` is one of the creature's four activate columns.
fn among_columns(
  creature creature: Creature,
  spell4_id spell4_id: Int,
) -> Bool {
  list.any(creature.columns, fn(column) { column.spell4_id == spell4_id })
}

/// The creature's own cast time for an activate cast of `spell4_id`: its
/// `activateSpellCastTime` for a spell among its columns, 0 (the spell's own castTime)
/// for any other, such as the default spell (`0x1407a1680`, `0x14054e340`).
pub fn cast_time_for(
  creature creature: Creature,
  spell4_id spell4_id: Int,
) -> Int {
  use <- bool.guard(when: !among_columns(creature:, spell4_id:), return: 0)
  creature.cast_time_ms
}

/// The limits the cast of `spell4_id` at the creature is held to: the creature's own for
/// a spell among its columns, the spell's for any other (`0x1403ad860`, `0x1403ad8f0`).
pub fn limits_for(
  creature creature: Creature,
  spell4_id spell4_id: Int,
  spell spell: Limits,
) -> Limits {
  use <- bool.guard(when: !among_columns(creature:, spell4_id:), return: spell)
  Limits(
    min: creature.min_range,
    max: case creature.max_range == 0.0 {
      True -> spell.max
      False -> creature.max_range
    },
    vertical: spell.vertical,
  )
}

/// The distance between two bodies: that between their places less both radii, never
/// below 0 (`0x1403b2240`).
fn gap(from from: Body, to to: Body) -> Float {
  float.max(
    creature_path.distance(from: from.place, to: to.place)
      -. from.radius
      -. to.radius,
    0.0,
  )
}

/// Whether the caster stands where `limits` allow its activate cast at the target, as
/// the client tests it before it sends the cast (`0x1403b2240`): the minimum, then the
/// maximum, then the height.
pub fn range_of(
  limits limits: Limits,
  caster caster: Body,
  target target: Body,
) -> Range {
  let gap = gap(from: caster, to: target)
  let height =
    float.absolute_value(
      start_place.y(target.place) -. start_place.y(caster.place),
    )
    -. caster.radius
    -. target.radius
  case
    gap <. limits.min,
    gap >. limits.max,
    limits.vertical >. -1.0 && height >. limits.vertical
  {
    True, _, _ -> TooClose
    False, True, _ -> TooFar
    False, False, True -> TooHigh
    False, False, False -> Within
  }
}

/// The plan of the spell, or `Error(Nil)` for one the plans do not hold.
pub fn planned_of(
  activations activations: Activations,
  spell4_id spell4_id: Int,
) -> Result(Planned, Nil) {
  dict.get(activations.spells, spell4_id)
}
