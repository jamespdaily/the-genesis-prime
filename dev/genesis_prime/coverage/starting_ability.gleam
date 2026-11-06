//// The types the starting abilities use: the effect types, the prerequisite
//// types and the innate cost EMM ids of the spells the 18 level-1 abilities' trees
//// and the class innates held at level 1 reach, which the coverage measure shows
//// beside each type's weight in the whole game, and the parts of those trees it
//// leaves out, each with why.
////
//// ```
//// plans (genesis_prime/game/spell_plan) ─▶ every spell of every tree, once each,
////   a stage included, a Proxy's child included unless its gate cannot open for a
////   level-1 character (genesis_prime/coverage/level_one_gate)
////   ─▶ its Spell4Effects rows ─▶ their effect types
////   ─▶ the Prerequisite ids of the Spell4 row's columns but the runner columns,
////      of each effect's columns and of each Proxy's dataBits06
////      ─▶ each kept condition's type
//// ```
////
//// - **Runner columns:** `prerequisiteIdRunner00` and `prerequisiteIdRunner01` of
////   Spell4 are read by the client only to show a prompt on the ability button
////   (`Spell4.prerequisiteIdRunner00`, `0x1405c8600`), so a Prerequisite only they
////   name is not counted.
//// - **A gate a level-1 character cannot open** leaves out the Proxy's child and
////   every spell below it, whatever that child's own rows hold.
//// - **The class innates** are in the plans (genesis_prime/game/innate: slot 0 of each
////   Class row, active and passive), so the walk counts them as it counts the
////   abilities. A class's slots 1 and 2 are left out when their gate is a condition a
////   level-1 character fails (`InnateSlotClosed`, by `level_one_gate.row_closed`, the
////   rule the Proxies' gates use), as the client unlocks a slot only when its gate
////   passes (`0x1405e73e0`); a slot with no gate or an open one is not listed.
//// - A prerequisite reached by several columns counts once; a type counts once for
////   each condition that holds it (`0x1404a5190`: the conditions before the first of
////   type 0). A row a tree names that its table lacks is an error, never a type
////   left out.
//// - **A nested prerequisite** (type 11) is followed: the Prerequisite its objectId
////   names is evaluated whole by the client, so its conditions are counted too, each
////   row once however many conditions nest it (`Prerequisite.prerequisiteTypeId.11`).
////   A nested id whose row the table lacks names nothing to count: the client's
////   evaluator fails it (`0x1404a1ca0`).

import genesis_prime/coverage/level_one_gate
import genesis_prime/game/effect_kind
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell}
import genesis_prime/table/class
import genesis_prime/table/id.{PrerequisiteId, Spell4Id}
import genesis_prime/table/loader/store
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4.{type Spell4}
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string

/// A row a spell of a starting ability's tree names that the client's table does
/// not hold: the measure cannot go on without it.
pub type MissingRow {
  MissingRow(table: String, id: Int, named_by: String)
}

/// A part of the starting abilities' trees the measure does not count, with why.
pub type LeftOut {
  /// A Prerequisite that only runner columns name.
  RunnerColumnsOnly(
    prerequisite_id: Int,
    conditions: Int,
    named_by: List(String),
  )
  /// A Proxy's child and what is below it, behind a gate that cannot open.
  ProxyGateClosed(
    proxy_effect_id: Int,
    parent: Int,
    child: Int,
    gate: Int,
    why: level_one_gate.Closed,
    spells: List(Int),
    effects: List(#(Int, Int)),
  )
  /// A Proc effect of a reached spell whose kind the plan does not read
  /// (genesis_prime/game/spell_plan `proc_read`): the row is not handled, and the spell
  /// it casts is not counted.
  ProcKindNotRead(spell4_id: Int, effect_id: Int, kind: Int, casts: Int)
  /// A class innate slot (1 or 2) behind a gate a level-1 character cannot open: the
  /// slot's active and passive spells are not counted.
  InnateSlotClosed(
    class_id: Int,
    slot: Int,
    active: Int,
    passive: Int,
    gate: Int,
    why: level_one_gate.Closed,
  )
}

/// Every part of the starting abilities' trees the measure leaves out, each with
/// why: the Proxies behind a gate a level-1 character cannot open, by the spell they
/// are in, then the Prerequisites only a runner column names, by id.
pub fn left_out(
  tables tables: store.Tables,
) -> Result(List(LeftOut), List(MissingRow)) {
  use gates <- result.try(amp_gates(tables:))
  let reached = reached_spells(tables:, gates:)
  let reached_ids = set.from_list(list.map(reached, spell_id))
  let #(rows, _) = spell4_rows(tables:, spells: reached)
  let closed =
    list.flat_map(reached, fn(spell) {
      list.filter_map(spell.proxies, fn(proxy) {
        level_one_gate.closed_by(gates:, tables:, proxy:)
        |> result.map(closed_proxy(
          tables:,
          reached_ids:,
          parent: spell,
          proxy:,
          closed: _,
        ))
      })
    })
  use slots <- result.map(closed_innate_slots(tables:, gates:))
  list.flatten([
    closed,
    procs_not_read(tables:, spells: reached),
    slots,
    runner_columns_only(tables:, spells: reached, rows:),
  ])
}

/// The Proc effects of the reached spells whose kind the plan does not read, in effect id
/// order, each with the spell it would cast.
fn procs_not_read(
  tables tables: store.Tables,
  spells spells: List(Spell),
) -> List(LeftOut) {
  let by_spell = spell_plan.effects_by_spell(tables:)
  list.flat_map(spells, fn(spell) {
    dict.get(by_spell, spell_id(spell))
    |> result.unwrap([])
    |> list.filter_map(fn(effect) {
      case
        effect_kind.kind_of(effect.effect_type),
        spell_plan.proc_read(spell4_id: spell_id(spell), effect:)
      {
        effect_kind.Proc, Error(spell_plan.ProcKindNotRead(kind:, ..)) ->
          Ok(#(
            effect.id,
            ProcKindNotRead(
              spell4_id: spell_id(spell),
              effect_id: effect.id,
              kind:,
              casts: effect.data_bits01,
            ),
          ))
        _, _ -> Error(Nil)
      }
    })
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(found) { found.1 })
}

/// The innate slots 1 and 2 of every Class row whose gate a level-1 character cannot
/// pass, in class and slot order; a gate Prerequisite the table lacks is a missing row.
fn closed_innate_slots(
  tables tables: store.Tables,
  gates gates: level_one_gate.Gates,
) -> Result(List(LeftOut), List(MissingRow)) {
  let #(verdicts, missing) =
    list.sort(class.all(tables), fn(first, second) {
      int.compare(first.id, second.id)
    })
    |> list.flat_map(fn(row) {
      [
        #(
          1,
          row.spell4_id_innate_ability_active01,
          row.spell4_id_innate_ability_passive01,
          row.prerequisite_id_innate_ability01,
        ),
        #(
          2,
          row.spell4_id_innate_ability_active02,
          row.spell4_id_innate_ability_passive02,
          row.prerequisite_id_innate_ability02,
        ),
      ]
      |> list.filter(fn(slot) { slot.1 != 0 && slot.3 != 0 })
      |> list.map(fn(slot) {
        slot_verdict(tables:, gates:, class_id: row.id, slot:)
      })
    })
    |> result.partition
  case missing {
    [] -> Ok(result.values(list.reverse(verdicts)))
    [_, ..] -> Error(missing)
  }
}

/// One innate slot of a Class row, as the slot number, its active and passive spell and
/// its gate: closed with why, or an error for a gate Prerequisite the table lacks.
fn slot_verdict(
  tables tables: store.Tables,
  gates gates: level_one_gate.Gates,
  class_id class_id: Int,
  slot slot: #(Int, Int, Int, Int),
) -> Result(Result(LeftOut, Nil), MissingRow) {
  let #(number, active, passive, gate) = slot
  use gate_row <- result.map(
    prerequisite_table.get(tables:, id: PrerequisiteId(gate))
    |> result.replace_error(MissingRow(
      table: "Prerequisite",
      id: gate,
      named_by: "Class "
        <> int.to_string(class_id)
        <> " column prerequisiteIdInnateAbility0"
        <> int.to_string(number),
    )),
  )
  level_one_gate.row_closed(gates:, row: gate_row)
  |> result.map(fn(why) {
    InnateSlotClosed(class_id:, slot: number, active:, passive:, gate:, why:)
  })
}

/// A Proxy the measure leaves out: its child and the spells below it that no open
/// route reaches, with their effect rows.
fn closed_proxy(
  tables tables: store.Tables,
  reached_ids reached_ids: set.Set(Int),
  parent parent: Spell,
  proxy proxy: spell_plan.Proxy,
  closed closed: #(Int, level_one_gate.Closed),
) -> LeftOut {
  let below =
    spell_plan.tree(spell: proxy.spell, started: fn(_) { True })
    |> list.filter(fn(spell) { !set.contains(reached_ids, spell_id(spell)) })
    |> list.map(fn(spell) { #(spell_id(spell), spell) })
    |> dict.from_list
    |> dict.values
    |> list.sort(fn(first, second) {
      int.compare(spell_id(first), spell_id(second))
    })
  ProxyGateClosed(
    proxy_effect_id: proxy.effect_id.value,
    parent: spell_id(parent),
    child: spell_id(proxy.spell),
    gate: closed.0,
    why: closed.1,
    spells: list.map(below, spell_id),
    effects: effects_of(tables:, spells: below)
      |> list.map(fn(effect) { #(effect.id, effect.effect_type) })
      |> list.sort(fn(first, second) { int.compare(first.0, second.0) }),
  )
}

/// The Prerequisites that the runner columns of these Spell4 rows name and no column
/// the measure reads names, each with the columns, by id.
fn runner_columns_only(
  tables tables: store.Tables,
  spells spells: List(Spell),
  rows rows: List(Spell4),
) -> List(LeftOut) {
  let counted = set.from_list(dict.keys(counted_ids(tables:, spells:, rows:)))
  list.flat_map(rows, fn(row) {
    named(table: "Spell4", id: row.id, columns: [
      #("prerequisiteIdRunner00", row.prerequisite_id_runner00),
      #("prerequisiteIdRunner01", row.prerequisite_id_runner01),
    ])
  })
  |> list.filter(fn(named) { !set.contains(counted, named.0) })
  |> list.group(fn(named) { named.0 })
  |> dict.to_list
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.filter_map(fn(group) {
    use row <- result.map(prerequisite_table.get(
      tables:,
      id: PrerequisiteId(group.0),
    ))
    RunnerColumnsOnly(
      prerequisite_id: group.0,
      conditions: list.length(prerequisite.kept_conditions(row:)),
      named_by: list.map(group.1, fn(named) { named.1 })
        |> list.unique
        |> list.sort(string.compare),
    )
  })
}

/// A sentence for a part left out.
pub fn describe_left_out(left_out left_out: LeftOut) -> String {
  case left_out {
    RunnerColumnsOnly(prerequisite_id:, conditions:, named_by:) ->
      "Prerequisite "
      <> int.to_string(prerequisite_id)
      <> " ("
      <> int.to_string(conditions)
      <> case conditions {
        1 -> " condition"
        _ -> " conditions"
      }
      <> ") is named only by "
      <> string.join(named_by, ", ")
      <> ": the client reads a runner column only to show a prompt on the ability button (Spell4.prerequisiteIdRunner00)"
    ProxyGateClosed(
      proxy_effect_id:,
      parent:,
      child:,
      gate:,
      why:,
      spells:,
      effects:,
    ) ->
      "Proxy effect "
      <> int.to_string(proxy_effect_id)
      <> " of Spell4 "
      <> int.to_string(parent)
      <> " starts Spell4 "
      <> int.to_string(child)
      <> ", which is not counted with its tree (Spell4 "
      <> string.join(list.map(spells, int.to_string), ", ")
      <> "; Spell4Effects rows "
      <> string.join(
        list.map(effects, fn(effect) {
          int.to_string(effect.0) <> " (type " <> int.to_string(effect.1) <> ")"
        }),
        ", ",
      )
      <> "): "
      <> level_one_gate.describe(gate:, closed: why)
    ProcKindNotRead(spell4_id:, effect_id:, kind:, casts:) ->
      "Proc effect "
      <> int.to_string(effect_id)
      <> " of Spell4 "
      <> int.to_string(spell4_id)
      <> " is of kind "
      <> int.to_string(kind)
      <> ", which the plan does not read, so the Spell4 "
      <> int.to_string(casts)
      <> " it casts is not counted"
    InnateSlotClosed(class_id:, slot:, active:, passive:, gate:, why:) ->
      "Class "
      <> int.to_string(class_id)
      <> " innate slot "
      <> int.to_string(slot)
      <> " (Spell4 "
      <> int.to_string(active)
      <> ", passive "
      <> int.to_string(passive)
      <> ") is not counted: "
      <> level_one_gate.describe(gate:, closed: why)
  }
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
  use spells <- result.map(spells(tables:))
  effects_of(tables:, spells:)
  |> list.map(fn(effect) { effect.effect_type })
}

/// How many Spell4Effects rows of the type, among the spells the starting abilities' trees
/// reach, the plan does not read (genesis_prime/game/spell_plan `effect_row_read`): a Proc
/// row of a kind it skips is one. The starting abilities' column counts them as not handled.
pub fn unread_effect_rows(
  tables tables: store.Tables,
  type_number type_number: Int,
) -> Int {
  level_one_gate.load(tables:)
  |> result.map(fn(gates) {
    effects_of(tables:, spells: reached_spells(tables:, gates:))
    |> list.count(fn(effect) {
      effect.effect_type == type_number && !spell_plan.effect_row_read(effect:)
    })
  })
  |> result.unwrap(0)
}

/// The innate cost EMM id of each cost of the spells the starting abilities' trees
/// reach, one value for each Spell4 column that holds one.
pub fn spend_ids(tables: store.Tables) -> Result(List(Int), List(MissingRow)) {
  use spells <- result.try(spells(tables:))
  case spell4_rows(tables:, spells:) {
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
  use spells <- result.try(spells(tables:))
  prerequisite_types_of(tables:, spells:)
}

/// The type of each condition of the prerequisites these spells reach, one value
/// for each condition; the Spell4 and Prerequisite rows they name and the tables
/// lack are the error, each with the row and column that names it.
pub fn prerequisite_types_of(
  tables tables: store.Tables,
  spells spells: List(Spell),
) -> Result(List(Int), List(MissingRow)) {
  let #(rows, spells_missing) = spell4_rows(tables:, spells:)
  let #(types, prerequisites_missing) =
    counted_ids(tables:, spells:, rows:)
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

/// The Prerequisite ids the measure counts for these spells, each once, with the
/// first row and column that name it, and the rows they nest followed (`followed`).
fn counted_ids(
  tables tables: store.Tables,
  spells spells: List(Spell),
  rows rows: List(Spell4),
) -> Dict(Int, String) {
  let named =
    list.fold(counted_namings(tables:, spells:, rows:), dict.new(), named_once)
  followed(tables:, found: named, pending: dict.keys(named))
}

/// The ids found with this one added, named by the first row and column that named it.
fn named_once(
  found found: Dict(Int, String),
  named named: #(Int, String),
) -> Dict(Int, String) {
  use <- bool.guard(when: dict.has_key(found, named.0), return: found)
  dict.insert(found, named.0, named.1)
}

/// The ids with the rows they nest (type 11) added, each named by the nesting row, until
/// no row nests one not yet found. A nested id whose row the table lacks is left out.
fn followed(
  tables tables: store.Tables,
  found found: Dict(Int, String),
  pending pending: List(Int),
) -> Dict(Int, String) {
  let nested =
    list.flat_map(pending, fn(id) {
      case prerequisite_table.get(tables:, id: PrerequisiteId(id)) {
        Ok(row) ->
          prerequisite.kept_conditions(row:)
          |> list.filter(fn(condition) {
            condition.0 == prerequisite.nested_type
          })
          |> list.map(fn(condition) {
            #(
              condition.2,
              "Prerequisite "
                <> int.to_string(id)
                <> " nested by a type 11 condition",
            )
          })
        Error(Nil) -> []
      }
    })
    |> list.filter(fn(named) {
      !dict.has_key(found, named.0)
      && result.is_ok(prerequisite_table.get(
        tables:,
        id: PrerequisiteId(named.0),
      ))
    })
  case nested {
    [] -> found
    [_, ..] -> {
      let found = list.fold(nested, found, named_once)
      followed(
        tables:,
        found:,
        pending: list.unique(list.map(nested, fn(named) { named.0 })),
      )
    }
  }
}

/// The Prerequisite ids the columns name, each with the row and
/// column that name it: the columns of the Spell4 rows but the runner columns, and
/// the columns of each effect, a Proxy's dataBits06 included.
fn counted_namings(
  tables tables: store.Tables,
  spells spells: List(Spell),
  rows rows: List(Spell4),
) -> List(#(Int, String)) {
  let from_spells =
    list.map(rows, fn(row) {
      named(table: "Spell4", id: row.id, columns: [
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
        | effect_kind.Stealth
        | effect_kind.RemoveStealth
        | effect_kind.Proc
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
  list.append(list.flatten(from_spells), from_effects)
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
/// spells of its stages and the child of each Proxy whose gate can open for a level-1
/// character. An error when the tables lack the AMP unlock row the gates read.
pub fn spells(
  tables tables: store.Tables,
) -> Result(List(Spell), List(MissingRow)) {
  use gates <- result.map(amp_gates(tables:))
  reached_spells(tables:, gates:)
}

/// The AMP gates the tree walk reads, or the AMP unlock row the table lacks.
fn amp_gates(
  tables tables: store.Tables,
) -> Result(level_one_gate.Gates, List(MissingRow)) {
  level_one_gate.load(tables:)
  |> result.replace_error([
    MissingRow(
      table: "LevelUpUnlock",
      id: level_one_gate.amp_unlock_id,
      named_by: "the AMP unlock the measure reads the level of an AMP spell from",
    ),
  ])
}

/// The spells of the trees, each once, walking only the Proxies whose gate can open.
fn reached_spells(
  tables tables: store.Tables,
  gates gates: level_one_gate.Gates,
) -> List(Spell) {
  let started = fn(proxy) {
    result.is_error(level_one_gate.closed_by(gates:, tables:, proxy:))
  }
  dict.values(spell_plan.plans(tables:))
  |> list.flat_map(fn(ability) { spell_plan.tree(spell: ability, started:) })
  |> list.fold(dict.new(), fn(found, spell) {
    dict.insert(found, spell.spell4_id.value, spell)
  })
  |> dict.values
}

fn spell_id(spell: Spell) -> Int {
  spell.spell4_id.value
}
