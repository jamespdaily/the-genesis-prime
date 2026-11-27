//// The quest objectives whose action the client's own data names: a spell effect that
//// advances the objective, and an item that needs it open.
////
//// ```
//// Spell4Effects effectType 42 (quest, index) ──┐
//// Item2 quest2IdActivationRequired + index ────┴▶ derivation ─▶ named / by_effect / by_item
//// ```
////
//// - **A spell effect** is `QuestAdvanceObjective` (`Spell4Effects.effectType.42`):
////   `dataBits00` is a Quest2 id, `dataBits01` the objective's index in that quest and
////   `dataBits02` the amount. A row that names a quest or an index the tables lack is kept
////   and matches no objective.
//// - **An item** names an objective when its `quest2IdActivationRequired` is a quest and its
////   `questObjectiveActivationRequired` is not negative (`0x140398cc0`: the client
////   refuses the item's cast unless that objective is open). An item that names a quest
////   alone names no objective.
////
//// The sets are built once when the tables load, from every Spell4Effects and Item2 row.
//// An objective in either set is one a cast does, so `objective.script_of` leaves a marked
//// scripted one of them open until the cast counts for it.

import genesis_prime/shared/effect_kind
import genesis_prime/table/item2
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/set.{type Set}

/// The (quest id, objective index) pairs of each source, kept apart so that each can be
/// told from the other.
type Named {
  Named(by_effect: Set(#(Int, Int)), by_item: Set(#(Int, Int)))
}

const named_key: table_store.DerivedKey(Named) =
  table_store.DerivedKey("NamedObjectives")

/// The objectives a spell effect or an item names, as a value the tables' load builds once
/// under the tables' key.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: named_key, build: fn(tables) {
    Ok(Named(
      by_effect: spell4_effects.all(tables)
        |> list.filter(fn(row) {
          effect_kind.kind_of(effect_type: row.effect_type)
          == effect_kind.QuestAdvance
        })
        |> list.map(fn(row) { #(row.data_bits00, row.data_bits01) })
        |> set.from_list,
      by_item: item2.all(tables)
        |> list.filter(fn(row) {
          row.quest2_id_activation_required != 0
          && row.quest_objective_activation_required >= 0
        })
        |> list.map(fn(row) {
          #(
            row.quest2_id_activation_required,
            row.quest_objective_activation_required,
          )
        })
        |> set.from_list,
    ))
  })
}

/// Whether a spell effect advances the quest's objective at `index`.
pub fn by_effect(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
) -> Bool {
  set.contains(table_store.derived(tables:, key: named_key).by_effect, #(
    quest_id,
    index,
  ))
}

/// Whether an item needs the quest's objective at `index` open.
pub fn by_item(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
) -> Bool {
  set.contains(table_store.derived(tables:, key: named_key).by_item, #(
    quest_id,
    index,
  ))
}

/// Whether a spell effect or an item names the quest's objective at `index`.
pub fn named(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
) -> Bool {
  by_effect(tables:, quest_id:, index:) || by_item(tables:, quest_id:, index:)
}
