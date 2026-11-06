//// A class's level-1 innate: the active spell its innate button casts and the
//// passive spell beside it, from the first slot of its Class row. The client holds
//// no innate in any table of what a character holds (no SpellLevel row names one),
//// so the server reads the Class row itself, as the client's own code does
//// (`InitClassInnates`, `0x1405e7330`).
////
//// ```
//// Class (spell4IdInnateAbilityActive00, Passive00, prerequisiteIdInnateAbility00) ─▶ Spell4 ─▶ Spell4Base
//// all classes, on demand ─▶ held(tables) ─▶ the loadout (genesis_prime/game/loadout) and the plans
////                                           (genesis_prime/game/spell_plan) read each class's innate
//// ```
////
//// - **Slot 0 only.** The client takes a class's innate slots in order and stops at the
////   first with no active spell (`0x1405e7330`), and it unlocks a slot only when the
////   slot's gate passes (`0x1405e73e0`). Slots 1 and 2 are gated by a level condition (6
////   and 10), which a level-1 character fails, so the server holds slot 0, whose gate
////   no row has (`Class.spell4IdInnateAbilityActive00`).
//// - **What fails the load:** a gate on slot 0, which the server does not check; a
////   Spell4 row the Class row names that the table lacks; and an innate whose
////   Spell4Base is also a level-1 SpellLevel ability of its class, which would hold
////   one base twice in the ability bag (`not_an_ability`, which the loadout checks).
//// - **The passive** is never cast by the client, which shows no buff for it
////   (`Class.spell4IdInnateAbilityPassive00`), so the server starts it itself at each
////   join (genesis_prime/game/cast).

import genesis_prime/table/class
import genesis_prime/table/id.{
  type Spell4BaseId, type Spell4Id, Spell4BaseId, Spell4Id,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The innate a class holds at level 1: its active spell, with the Spell4Base the
/// ability bag holds it as (`lua.ActionBarFrame.ActionBarInnate`), and its passive.
pub type Innate {
  Innate(active: Spell4Id, active_base: Spell4BaseId, passive: Option(Passive))
}

/// An innate's passive spell and its Spell4Base, the key of its plan.
pub type Passive {
  Passive(spell4_id: Spell4Id, spell4_base_id: Spell4BaseId)
}

/// Why a class's innate cannot be held, each a row of the client's tables the
/// server does not read.
pub type InnateError {
  /// Slot 0 of a Class row names a gate prerequisite.
  SlotZeroGated(class_id: Int, prerequisite_id: Int)
  /// A Class row names a Spell4 row the table lacks.
  NoSpell(class_id: Int, spell4_id: Int)
  /// A class's innate has the Spell4Base of one of its level-1 abilities.
  InnateAlsoAnAbility(class_id: Int, spell4_base_id: Int)
}

/// The slot-0 innate of every class whose Class row has one, by class id; the first
/// row that cannot be held is the error.
pub fn held(
  tables tables: table_store.Tables,
) -> Result(Dict(Int, Innate), InnateError) {
  list.try_fold(class.all(tables), dict.new(), fn(held, row) {
    use slot <- result.map(
      of_slot_zero(
        class_id: row.id,
        active: row.spell4_id_innate_ability_active00,
        passive: row.spell4_id_innate_ability_passive00,
        gate: row.prerequisite_id_innate_ability00,
        base_of: fn(spell4_id) {
          spell4.get(tables:, id: spell4_id)
          |> result.map(fn(spell) {
            Spell4BaseId(spell.spell4_base_id_base_spell)
          })
        },
      ),
    )
    case slot {
      Some(innate) -> dict.insert(held, row.id, innate)
      None -> held
    }
  })
}

/// The innate in the first slot of a Class row, from the row's three columns of that
/// slot (0 for none), with `base_of` giving the Spell4Base of a Spell4 row or no
/// row: none when the slot has no active spell, as the client stops there.
pub fn of_slot_zero(
  class_id class_id: Int,
  active active: Int,
  passive passive: Int,
  gate gate: Int,
  base_of base_of: fn(Spell4Id) -> Result(Spell4BaseId, Nil),
) -> Result(Option(Innate), InnateError) {
  use <- bool.guard(active == 0, Ok(None))
  use <- bool.guard(
    gate != 0,
    Error(SlotZeroGated(class_id:, prerequisite_id: gate)),
  )
  let base = fn(spell4_id) {
    base_of(Spell4Id(spell4_id))
    |> result.replace_error(NoSpell(class_id:, spell4_id:))
  }
  use active_base <- result.try(base(active))
  use passive <- result.map(case passive {
    0 -> Ok(None)
    _ ->
      base(passive)
      |> result.map(fn(spell4_base_id) {
        Some(Passive(spell4_id: Spell4Id(passive), spell4_base_id:))
      })
  })
  Some(Innate(active: Spell4Id(active), active_base:, passive:))
}

/// Whether the innate's Spell4Base differs from every level-1 ability of the class: the
/// ability bag holds one item of a base, which the client finds the spell by
/// (`0x14077dfa0`).
pub fn not_an_ability(
  class_id class_id: Int,
  innate innate: Innate,
  abilities abilities: List(Spell4BaseId),
) -> Result(Nil, InnateError) {
  use <- bool.guard(!list.contains(abilities, innate.active_base), Ok(Nil))
  Error(InnateAlsoAnAbility(class_id:, spell4_base_id: innate.active_base.value))
}

/// A sentence that says why, naming the table and the row, for the message the
/// server stops with.
pub fn describe(error error: InnateError) -> String {
  case error {
    SlotZeroGated(class_id:, prerequisite_id:) ->
      "Class row "
      <> int.to_string(class_id)
      <> " names the gate Prerequisite "
      <> int.to_string(prerequisite_id)
      <> " on its first innate, which the server does not check: the client unlocks a slot only when its gate passes"
    NoSpell(class_id:, spell4_id:) ->
      "the table Spell4 has no row "
      <> int.to_string(spell4_id)
      <> ", which Class row "
      <> int.to_string(class_id)
      <> " names as an innate spell"
    InnateAlsoAnAbility(class_id:, spell4_base_id:) ->
      "the innate of Class row "
      <> int.to_string(class_id)
      <> " has Spell4Base "
      <> int.to_string(spell4_base_id)
      <> ", which is also one of its level-1 SpellLevel abilities, so the ability bag would hold it twice"
  }
}
