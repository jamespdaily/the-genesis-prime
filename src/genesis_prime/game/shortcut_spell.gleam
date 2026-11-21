//// The spells of the cast-a-spell objectives (`QuestObjective.type.11`) and the spells an item
//// casts on its user: the button the client shows for an open objective and the plan the
//// server casts when it is pressed or the item is used.
////
//// ```
//// each type 11 objective's data ─▶ Spell4 row ─▶ Spell4Base ─▶ Spell4TargetMechanics.targetType
////   a Caster kind (0, 2, 6, 7) ─▶ Planned(spell)    the press casts it on the caster
////   any other kind             ─▶ Aimed(spell, ..) the press names a unit, which its cast group,
////                                                 valid targets and conditions judge
////   no Spell4 row              ─▶ NoSpell4Row      the client refuses the press (22)
////   a tree that cannot plan    ─▶ CannotBePlanned
//// ```
////
//// - **The target** of a shortcut cast is the caster for targetType 0, 2, 6 and 7, and the
////   player's target for 1, 3, 5 and 8 (`0x14055bdc0`, fact `opcode.0x9d`).
//// - **The plans** are built once when the tables load, as `spell_plan.spell_alone` plans a
////   spell that no ability roots.
//// - **An item's spell** (ItemSpecial.spell4IdOnActivate) of a Caster kind is planned with the
////   objectives' spells, and an item's use plays it only when every row of its tree is
////   played (`effect_row_read.first_unplayed`) and its plan holds; else the use is refused,
////   with the reason in `item_refusals`. An item's spell of any other kind stays with the
////   creature's activate cast (genesis_prime/game/activate).

import genesis_prime/game/activate
import genesis_prime/game/effect_row_read
import genesis_prime/game/item_property
import genesis_prime/game/objective_kind
import genesis_prime/game/spell_effect
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/game/target_mechanic
import genesis_prime/table/id.{
  Spell4ConditionsId, Spell4Id, Spell4ValidTargetsId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_target_mechanics
import genesis_prime/table/spell4_valid_targets
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import gleam/result

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

/// The plans of the spells the cast-a-spell objectives name and the Caster-kind spells items
/// cast, by Spell4 id.
pub type Shortcuts {
  Shortcuts(
    spells: Dict(Int, Planned),
    /// For a Caster-kind spell an item casts, the reason an item's use of it is refused, in
    /// words: its plan cannot be built, or the first row of its tree no item's cast plays.
    /// A spell with no entry is played, or not an item's to play.
    item_refusals: Dict(Int, String),
  )
}

/// What an item's use of its spell comes to.
pub type ItemSpell {
  /// The spell is cast on the user and every row of it is played.
  PlayedOnUser(spell: Spell)
  /// The spell is cast on the user and the server does not play it: the reason in words.
  NotBuilt(why: String)
  /// The spell is cast at a unit or a place: the creature's activate cast has it.
  OnAUnit
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

/// What an item's use of the spell comes to: refused when `item_refusals` holds a reason,
/// else played when the spell is planned for its user, else the creature's activate cast's.
pub fn item_spell_of(
  shortcuts shortcuts: Shortcuts,
  spell4_id spell4_id: Int,
) -> ItemSpell {
  case
    item_refusal_of(shortcuts:, spell4_id:),
    planned_of(shortcuts:, spell4_id:)
  {
    Ok(why), _ -> NotBuilt(why:)
    Error(Nil), Ok(Planned(spell:)) -> PlayedOnUser(spell:)
    Error(Nil), Ok(Aimed(..))
    | Error(Nil), Ok(NoSpell4Row)
    | Error(Nil), Ok(CannotBePlanned(..))
    | Error(Nil), Error(Nil)
    -> OnAUnit
  }
}

/// The reason an item's use of a Caster-kind spell is refused, or none when the spell is
/// played or is not an item's to play.
pub fn item_refusal_of(
  shortcuts shortcuts: Shortcuts,
  spell4_id spell4_id: Int,
) -> Result(String, Nil) {
  dict.get(shortcuts.item_refusals, spell4_id)
}

fn build(tables tables: table_store.Tables) -> Shortcuts {
  let sources = spell_plan.sources_of(tables:)
  let objective_ids =
    quest_objective.all(tables)
    |> list.filter_map(fn(row) {
      case objective_kind.cast_spell(objective_kind.of_row(row)) {
        Ok(spell4_id) if spell4_id.value != 0 -> Ok(spell4_id.value)
        Ok(_) | Error(Nil) -> Error(Nil)
      }
    })
  let item_ids = item_spells_on_the_user(tables:)
  let spells =
    list.append(objective_ids, item_ids)
    |> list.unique
    |> list.map(fn(spell4_id) {
      #(spell4_id, planned(tables:, sources:, spell4_id:))
    })
    |> dict.from_list
  let place_of =
    effect_row_read.places(tables:, effects: spell4_effects.all(tables))
  Shortcuts(
    spells:,
    item_refusals: list.filter_map(item_ids, fn(spell4_id) {
      case dict.get(spells, spell4_id) {
        Ok(planned) ->
          item_refusal(tables:, sources:, place_of:, planned:)
          |> result.map(fn(why) { #(spell4_id, why) })
        Error(Nil) -> Error(Nil)
      }
    })
      |> dict.from_list,
  )
}

/// The Spell4 ids items cast (ItemSpecial.spell4IdOnActivate) whose Spell4, Spell4Base and
/// Spell4TargetMechanics rows are in the tables and are of a Caster kind.
fn item_spells_on_the_user(tables tables: table_store.Tables) -> List(Int) {
  item_property.spells_on_activate(tables:)
  |> list.filter(fn(spell4_id) {
    case spell4.get(tables:, id: Spell4Id(spell4_id)) {
      Error(Nil) -> False
      Ok(row) ->
        case mechanics_of(tables:, row:) {
          Error(..) -> False
          Ok(#(_, mechanics)) ->
            target_mechanic.takes_caster(target_mechanic.of_row(mechanics))
        }
    }
  })
}

/// Why an item's use of a planned Caster-kind spell is refused, or `Error(Nil)` when it
/// plays every row.
fn item_refusal(
  tables tables: table_store.Tables,
  sources sources: spell_plan.Sources,
  place_of place_of: fn(Int) -> spell_plan.RowPlace,
  planned planned: Planned,
) -> Result(String, Nil) {
  case planned {
    CannotBePlanned(why:) -> Ok("cannot be planned: " <> why)
    Planned(spell:) ->
      case
        effect_row_read.first_unplayed(tables:, sources:, place_of:, spell:)
      {
        Some(why) -> Ok("holds a row the server does not play: " <> why)
        None -> Error(Nil)
      }
    Aimed(..) | NoSpell4Row -> Error(Nil)
  }
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
              case target_mechanic.takes_caster(aim.target_mechanic) {
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
    /// The kind of the spell's Spell4TargetMechanics row; an aimed spell is not a
    /// `Caster` kind.
    target_mechanic: target_mechanic.Kind,
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
  target_mechanic.rows_of_base(
    tables:,
    base_id: spell4.spell4_base_id_base_spell(row),
  )
  |> result.map_error(fn(missing) {
    case missing {
      target_mechanic.NoBaseRow(..) -> NoBaseRow
      target_mechanic.NoTargetMechanicsRow(..) -> NoTargetMechanicsRow
    }
  })
}

/// The targetType of the spell's Spell4TargetMechanics row, or `Error(Nil)` when its
/// Spell4Base or Spell4TargetMechanics row is not in the tables. It is the number, not the
/// decoded kind, because its caller tells an item on item (6) from the other Caster kinds.
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
    target_mechanic: target_mechanic.of_row(mechanics),
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
    spell_effect.has_flag(flags: conditions.condition_mask, bit: 2),
    spell_effect.has_flag(flags: conditions.condition_value, bit: 2)
  {
    False, _ -> Ok(CombatAllowed)
    True, False -> Ok(OutOfCombatOnly)
    True, True -> Error(AsksForTargetInCombat)
  }
}
