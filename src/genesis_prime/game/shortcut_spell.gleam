//// The spells of the cast-a-spell objectives (`QuestObjective.type.11`): the button the
//// client shows for an open one and the plan the server casts when it is pressed.
////
//// ```
//// each type 11 objective's data ─▶ Spell4 row ─▶ Spell4Base ─▶ Spell4TargetMechanics.targetType
////   self-aimed (0, 2, 6, 7) ─▶ Planned(spell)    the press casts it on the caster
////   any other targetType     ─▶ Aimed(spell, ..) the press names a unit, which its cast group,
////                                                valid targets and conditions judge
////   no Spell4 row            ─▶ NoSpell4Row      the client refuses the press (22)
////   a tree that cannot plan  ─▶ CannotBePlanned
//// ```
////
//// - **The target** of a shortcut cast is the caster for targetType 0, 2, 6 and 7, and the
////   player's target for 1, 3, 5 and 8 (`0x14055bdc0`, fact `opcode.0x9d`).
//// - **The plans** are built once when the tables load, as `spell_plan.spell_alone` plans a
////   spell that no ability roots.

import genesis_prime/game/activate
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/table/id.{
  Spell4ConditionsId, Spell4Id, Spell4TargetMechanicsId, Spell4ValidTargetsId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_target_mechanics
import genesis_prime/table/spell4_valid_targets
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

/// QuestObjective.type of a cast-a-spell objective.
pub const cast_type = 11

/// What the plans hold of an objective's spell.
pub type Planned {
  /// A spell aimed at the caster, with its plan.
  Planned(spell: Spell)
  /// A spell that takes a unit the press names, with its plan and what the client tests
  /// of the unit before it sends the press.
  Aimed(spell: Spell, aim: Aim)
  /// The Spell4 table has no row for the spell: the client refuses its press (22).
  NoSpell4Row
  /// The spell's tree cannot be planned: the reason in words.
  CannotBePlanned(why: String)
}

/// What the client tests of the target's combat before it sends a cast (`0x1403b2240`).
pub type TargetCombat {
  /// No test: the target may be in combat.
  CombatAllowed
  /// A target in combat is refused 108.
  OutOfCombatOnly
}

/// The plans of the spells the cast-a-spell objectives name, by Spell4 id.
pub type Shortcuts {
  Shortcuts(spells: Dict(Int, Planned))
}

const shortcuts_key: table_store.DerivedKey(Shortcuts) =
  table_store.DerivedKey("Shortcuts")

/// The shortcuts as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`), after the ability trees.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: shortcuts_key, build: fn(tables) {
    Ok(build(tables:))
  })
}

/// The shortcuts the tables' load built.
pub fn shortcuts(tables tables: table_store.Tables) -> Shortcuts {
  table_store.derived(tables:, key: shortcuts_key)
}

/// The plan of a spell an objective names, or none when no objective names it.
pub fn planned_of(
  shortcuts shortcuts: Shortcuts,
  spell4_id spell4_id: Int,
) -> Result(Planned, Nil) {
  dict.get(shortcuts.spells, spell4_id)
}

/// The targetTypes that take the caster, whatever the player has targeted
/// (`0x14055bdc0`).
const self_aimed = [0, 2, 6, 7]

fn build(tables tables: table_store.Tables) -> Shortcuts {
  let sources = spell_plan.sources_of(tables:)
  let spell_ids =
    quest_objective.all(tables)
    |> list.filter(fn(row) { row.type_ == cast_type && row.data != 0 })
    |> list.map(fn(row) { row.data })
    |> list.unique
  Shortcuts(
    spells: list.map(spell_ids, fn(spell4_id) {
      #(spell4_id, planned(tables:, sources:, spell4_id:))
    })
    |> dict.from_list,
  )
}

fn planned(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  spell4_id spell4_id: Int,
) -> Planned {
  case spell4.get(tables:, id: Spell4Id(spell4_id)) {
    Error(Nil) -> NoSpell4Row
    Ok(row) ->
      case aim_of(tables:, row:) {
        Error(error) -> CannotBePlanned(why: describe(error:))
        Ok(aim) ->
          case
            spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: [])
          {
            Error(error) -> CannotBePlanned(why: spell_plan.describe(error:))
            Ok(spell) ->
              case list.contains(self_aimed, aim.target_type) {
                True -> Planned(spell:)
                False -> Aimed(spell:, aim:)
              }
          }
      }
  }
}

/// What a spell's rows say of whom it is cast at.
pub type Aim {
  Aim(
    /// Spell4TargetMechanics.targetType: 1, 3, 5 or 8.
    target_type: Int,
    /// Spell4Base.targetGroupIdCastGroup, 0 for none.
    cast_group_id: Int,
    /// Spell4TargetMechanics.flags: bit 1 lets the caster be its own target.
    mechanics_flags: Int,
    /// Spell4ValidTargets.targetBitmask, 0 when the spell names no row: bit 0 refuses a
    /// player.
    valid_targets: Int,
    /// What the target's Spell4Conditions row says of its combat.
    target_combat: TargetCombat,
    /// The Spell4 row's range limits.
    limits: activate.Limits,
  )
}

/// What keeps an aim from being read.
type AimError {
  NoBaseRow
  NoTargetMechanicsRow
  NoValidTargetsRow
  NoTargetConditionsRow
  /// The target's condition row asks for a target in combat.
  AsksForTargetInCombat
}

fn describe(error error: AimError) -> String {
  case error {
    NoBaseRow -> "its Spell4Base row is not in the tables"
    NoTargetMechanicsRow -> "its Spell4TargetMechanics row is not in the tables"
    NoValidTargetsRow -> "its Spell4ValidTargets row is not in the tables"
    NoTargetConditionsRow ->
      "its target Spell4Conditions row is not in the tables"
    AsksForTargetInCombat ->
      "its target Spell4Conditions row asks for a target in combat, which the server does not judge"
  }
}

/// The Spell4Base and Spell4TargetMechanics rows of a spell, or the one the tables lack.
fn mechanics_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(
  #(spell4_base.Spell4Base, spell4_target_mechanics.Spell4TargetMechanics),
  AimError,
) {
  use base <- result.try(
    spell4_base.get(tables:, id: spell4.spell4_base_id_base_spell(row))
    |> result.replace_error(NoBaseRow),
  )
  spell4_target_mechanics.get(
    tables:,
    id: Spell4TargetMechanicsId(base.spell4_target_mechanic_id),
  )
  |> result.replace_error(NoTargetMechanicsRow)
  |> result.map(fn(mechanics) { #(base, mechanics) })
}

/// The targetType of the spell's Spell4TargetMechanics row, or `Error(Nil)` when its
/// Spell4Base or Spell4TargetMechanics row is not in the tables.
pub fn target_type_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(Int, Nil) {
  mechanics_of(tables:, row:)
  |> result.map(fn(rows) { { rows.1 }.target_type })
  |> result.replace_error(Nil)
}

/// The spell's aim from its Spell4Base, Spell4TargetMechanics, Spell4ValidTargets and
/// target Spell4Conditions rows, or what keeps one from being read.
fn aim_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(Aim, AimError) {
  use #(base, mechanics) <- result.try(mechanics_of(tables:, row:))
  use valid_targets <- result.try(case base.spell4_valid_target_id {
    0 -> Ok(0)
    valid_id ->
      spell4_valid_targets.get(tables:, id: Spell4ValidTargetsId(valid_id))
      |> result.map(fn(valid) { valid.target_bitmask })
      |> result.replace_error(NoValidTargetsRow)
  })
  use target_combat <- result.map(case row.spell4_conditions_id_target {
    0 -> Ok(CombatAllowed)
    conditions_id ->
      spell4_conditions.get(tables:, id: Spell4ConditionsId(conditions_id))
      |> result.replace_error(NoTargetConditionsRow)
      |> result.try(fn(conditions) { combat_of(conditions:) })
  })
  Aim(
    target_type: mechanics.target_type,
    cast_group_id: base.target_group_id_cast_group,
    mechanics_flags: mechanics.flags,
    valid_targets:,
    target_combat:,
    limits: activate.Limits(
      min: row.target_min_range,
      max: row.target_max_range,
      vertical: row.target_vertical_range,
    ),
  )
}

/// Bit 1 of a target condition row's mask (value 2) tests the target's combat
/// (`spell_plan.target_mask_read`). With the value's bit clear the target must be out of
/// combat (108). A row that asks for the target in combat is not read.
fn combat_of(
  conditions conditions: spell4_conditions.Spell4Conditions,
) -> Result(TargetCombat, AimError) {
  case
    spell_plan.has_flag(flags: conditions.condition_mask, bit: 2),
    spell_plan.has_flag(flags: conditions.condition_value, bit: 2)
  {
    False, _ -> Ok(CombatAllowed)
    True, False -> Ok(OutOfCombatOnly)
    True, True -> Error(AsksForTargetInCombat)
  }
}
