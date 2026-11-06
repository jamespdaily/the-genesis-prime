//// The types the starting abilities use: the effect types, the prerequisite
//// types and the innate cost EMM ids of the spells the 18 level-1 abilities' trees
//// reach, which the coverage measure shows beside each type's weight in the whole
//// game.
////
//// ```
//// plans (genesis_prime/game/spell_plan) ─▶ every spell of every tree, once each,
////   a Proxy's child behind a gate and a stage included
////   ─▶ its Spell4Effects rows ─▶ their effect types
////   ─▶ the Prerequisite ids of the Spell4 row's columns, of each effect's
////      columns and of each Proxy's dataBits06 ─▶ each kept condition's type
//// ```
////
//// A prerequisite reached by several columns counts once; a type counts once for
//// each condition that holds it (`0x1404a5190`: the conditions before the first of
//// type 0). A row a tree names that its table lacks is an error, never a type
//// left out.

import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/table/id.{PrerequisiteId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4.{type Spell4}
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/dict
import gleam/int
import gleam/list
import gleam/result

/// A row a spell of a starting ability's tree names that the client's table does
/// not hold: the measure cannot go on without it.
pub type MissingRow {
  MissingRow(table: String, id: Int, named_by: String)
}

/// A sentence for the measure's refusal.
pub fn describe(missing missing: MissingRow) -> String {
  missing.table
  <> " "
  <> int.to_string(missing.id)
  <> ", named by "
  <> missing.named_by
  <> ", is not in the client's tables"
}

/// The effect type of each Spell4Effects row of the spells the starting abilities'
/// trees reach, one value for each row.
pub fn effect_types(
  tables: store.Tables,
) -> Result(List(Int), List(MissingRow)) {
  Ok(
    effects_of(tables:, spells: spells(tables:))
    |> list.map(fn(effect) { effect.effect_type }),
  )
}

/// The innate cost EMM id of each cost of the spells the starting abilities' trees
/// reach, one value for each Spell4 column that holds one.
pub fn spend_ids(tables: store.Tables) -> Result(List(Int), List(MissingRow)) {
  case spell4_rows(tables:, spells: spells(tables:)) {
    #(rows, []) ->
      Ok(list.flat_map(rows, fn(row) { spell_plan.spent_emm_ids(row:) }))
    #(_, missing) -> Error(missing)
  }
}

/// The Spell4 row of each of these spells, and a `MissingRow` for each the table
/// lacks.
fn spell4_rows(
  tables tables: store.Tables,
  spells spells: List(Spell),
) -> #(List(Spell4), List(MissingRow)) {
  list.map(spells, fn(spell) {
    let id = spell.spell4_id.value
    spell4.get(tables:, id: Spell4Id(id))
    |> result.replace_error(MissingRow(
      table: "Spell4",
      id:,
      named_by: "a spell of a starting ability's tree",
    ))
  })
  |> result.partition
}

/// The type of each condition of the prerequisites the starting abilities' trees
/// reach, one value for each condition.
pub fn prerequisite_types(
  tables: store.Tables,
) -> Result(List(Int), List(MissingRow)) {
  prerequisite_types_of(tables:, spells: spells(tables:))
}

/// The type of each condition of the prerequisites these spells reach, one value
/// for each condition; the Spell4 and Prerequisite rows they name and the tables
/// lack are the error, each with the row and column that names it.
pub fn prerequisite_types_of(
  tables tables: store.Tables,
  spells spells: List(Spell),
) -> Result(List(Int), List(MissingRow)) {
  let #(rows, spells_missing) = spell4_rows(tables:, spells:)
  let from_spells =
    list.map(rows, fn(row) {
      named(table: "Spell4", id: row.id, columns: [
        #("prerequisiteIdRunner00", row.prerequisite_id_runner00),
        #("prerequisiteIdRunner01", row.prerequisite_id_runner01),
        #("prerequisiteIdCasterCast", row.prerequisite_id_caster_cast),
        #("prerequisiteIdTargetCast", row.prerequisite_id_target_cast),
        #(
          "prerequisiteIdCasterPersistence",
          row.prerequisite_id_caster_persistence,
        ),
        #(
          "prerequisiteIdTargetPersistence",
          row.prerequisite_id_target_persistence,
        ),
        #("prerequisiteIdAoeTarget", row.prerequisite_id_aoe_target),
        #(
          "prerequisiteIdAoePreferredTarget",
          row.prerequisite_id_aoe_preferred_target,
        ),
      ])
    })
  let from_effects =
    list.flat_map(effects_of(tables:, spells:), fn(effect) {
      let gate = case effect_kind.kind_of(effect.effect_type) {
        effect_kind.Proxy -> [#("dataBits06", effect.data_bits06)]
        effect_kind.Damage
        | effect_kind.VitalModifier
        | effect_kind.Fluff
        | effect_kind.ForceRemove
        | effect_kind.CrowdControl
        | effect_kind.PropertyModifier
        | effect_kind.ForcedMove
        | effect_kind.CooldownModifier
        | effect_kind.Unread(..) -> []
      }
      named(table: "Spell4Effects", id: effect.id, columns: [
        #("prerequisiteIdCasterApply", effect.prerequisite_id_caster_apply),
        #("prerequisiteIdTargetApply", effect.prerequisite_id_target_apply),
        #(
          "prerequisiteIdCasterPersistence",
          effect.prerequisite_id_caster_persistence,
        ),
        #(
          "prerequisiteIdTargetPersistence",
          effect.prerequisite_id_target_persistence,
        ),
        #("prerequisiteIdTargetSuspend", effect.prerequisite_id_target_suspend),
        ..gate
      ])
    })
  let #(types, prerequisites_missing) =
    list.append(list.flatten(from_spells), from_effects)
    |> list.fold(dict.new(), fn(found, named) {
      case dict.has_key(found, named.0) {
        True -> found
        False -> dict.insert(found, named.0, named.1)
      }
    })
    |> dict.to_list
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.map(fn(named) {
      prerequisite_table.get(tables:, id: PrerequisiteId(named.0))
      |> result.map(fn(row) { prerequisite.condition_types(row:) })
      |> result.replace_error(MissingRow(
        table: "Prerequisite",
        id: named.0,
        named_by: named.1,
      ))
    })
    |> result.partition
  case list.append(spells_missing, prerequisites_missing) {
    [] -> Ok(list.flatten(types))
    missing -> Error(missing)
  }
}

/// The Prerequisite ids the columns of a row hold, each with the row and column
/// that name it; a column holding 0 names none.
fn named(
  table table: String,
  id id: Int,
  columns columns: List(#(String, Int)),
) -> List(#(Int, String)) {
  list.filter_map(columns, fn(column) {
    case column.1 {
      0 -> Error(Nil)
      prerequisite_id ->
        Ok(#(
          prerequisite_id,
          table <> " " <> int.to_string(id) <> " column " <> column.0,
        ))
    }
  })
}

/// The Spell4Effects rows of these spells, in no order.
fn effects_of(
  tables tables: store.Tables,
  spells spells: List(Spell),
) -> List(Spell4Effects) {
  let by_spell = spell_plan.effects_by_spell(tables:)
  list.flat_map(spells, fn(spell) {
    dict.get(by_spell, spell.spell4_id.value) |> result.unwrap([])
  })
}

/// Every spell of every starting ability's tree, once each: the ability, the
/// spells of its stages and the child of each Proxy, whatever the Proxy's gate.
pub fn spells(tables tables: store.Tables) -> List(Spell) {
  dict.values(spell_plan.plans(tables:))
  |> list.flat_map(fn(ability) {
    spell_plan.tree(spell: ability, started: fn(_) { True })
  })
  |> list.fold(dict.new(), fn(found, spell) {
    dict.insert(found, spell.spell4_id.value, spell)
  })
  |> dict.values
}
