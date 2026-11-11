//// The spells of the cast-a-spell objectives (`QuestObjective.type.11`): the button the
//// client shows for an open one and the plan the server casts when it is pressed.
////
//// ```
//// each type 11 objective's data ─▶ Spell4 row ─▶ Spell4Base ─▶ Spell4TargetMechanics.targetType
////   self-aimed (0, 2, 6, 7) ─▶ Planned(spell)    the press casts it on the caster
////   any other targetType     ─▶ Targeted         the press needs a target (step B, #728)
////   no Spell4 row            ─▶ NoSpell4Row      the client refuses the press (22)
////   a tree that cannot plan  ─▶ CannotBePlanned
//// ```
////
//// - **The target** of a shortcut cast is the caster for targetType 0, 2, 6 and 7, and the
////   player's target for 1, 3, 5 and 8 (`0x14055bdc0`, fact `opcode.0x9d`).
//// - **The plans** are built once when the tables load, as `spell_plan.spell_alone` plans a
////   spell that no ability roots.

import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/table/id.{Spell4Id, Spell4TargetMechanicsId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest_objective
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_target_mechanics
import gleam/dict.{type Dict}
import gleam/list
import gleam/result

/// QuestObjective.type of a cast-a-spell objective.
pub const cast_type = 11

/// What the plans hold of an objective's spell.
pub type Planned {
  /// A spell aimed at the caster, with its plan.
  Planned(spell: Spell)
  /// A spell that takes the player's target: the press reads the target from the message,
  /// a later step (#728).
  Targeted(target_type: Int)
  /// The Spell4 table has no row for the spell: the client refuses its press (22).
  NoSpell4Row
  /// The spell's tree cannot be planned: the reason in words.
  CannotBePlanned(why: String)
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
      case target_type_of(tables:, row:) {
        Error(NoBaseRow) ->
          CannotBePlanned(why: "its Spell4Base row is not in the tables")
        Error(NoMechanicsRow) ->
          CannotBePlanned(
            why: "its Spell4TargetMechanics row is not in the tables",
          )
        Ok(target_type) ->
          case list.contains(self_aimed, target_type) {
            False -> Targeted(target_type:)
            True ->
              case
                spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: [])
              {
                Error(error) ->
                  CannotBePlanned(why: spell_plan.describe(error:))
                Ok(spell) -> Planned(spell:)
              }
          }
      }
  }
}

/// Which table row a spell's targetType could not be read from.
pub type NoTargetType {
  NoBaseRow
  NoMechanicsRow
}

/// The targetType of the spell's Spell4TargetMechanics row, or the row it lacks.
pub fn target_type_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(Int, NoTargetType) {
  spell4_base.get(tables:, id: spell4.spell4_base_id_base_spell(row))
  |> result.replace_error(NoBaseRow)
  |> result.try(fn(base) {
    spell4_target_mechanics.get(
      tables:,
      id: Spell4TargetMechanicsId(base.spell4_target_mechanic_id),
    )
    |> result.replace_error(NoMechanicsRow)
    |> result.map(fn(mechanics) { mechanics.target_type })
  })
}
