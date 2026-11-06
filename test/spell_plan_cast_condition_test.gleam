//// The four prerequisite columns of a Spell4 row in the plan
//// (`genesis_prime/game/spell_plan` `CasterCast`, `target_cast`, `caster_persistence`,
//// `target_persistence`). The client's tables are read for the spells the trace
//// reached; what the plan refuses is tested on rows in memory, since each planted load
//// puts 4 MiB of terms into the run. Expected values come from these places:
//// - `Class.spell4IdInnateAbilityActive00.cast_prerequisites`: the cast prerequisite
////   of each reached spell and the rows they name (`gleam run -m
////   genesis_prime/table_rows -- Prerequisite 29568 903 39321 12939 29484 20117
////   36425 19750`): Warrior 46867 has 29568, Esper 58586 has 903, Stalker 46073 has
////   39321 (type 11 of 12939), Spellslinger 47273 has 29484 (type 11 of 20117), and
////   the buff 47439 has CasterPersistence 36425; Engineer 47866 and Medic 69450 have
////   none; Rampage 58524 has 19750, which only waives its caster requirement.
//// - `0x1403ace00` and `0x1403b1780`: the waiver is a CasterCast of a spell whose
////   propertyFlags has bit 2 (0x4) and whose casterInnateRequirement0,
////   casterInnateRequirement1 or targetBeginInnateRequirement is not 0; with no such
////   block bit 2 changes nothing and the prerequisite is a gate (Spell4 offsets 52,
////   56 and 76, the block `0x1403ace00` tests).
//// - The server's load rule (the plan's doc): a column naming a row the table lacks
////   fails the load.

import client_tables
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type Spell, CastGate, NoCasterCast, NoRow, RequirementWaiver,
}
import genesis_prime/table/id.{Spell4BaseId}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support as support
import unitest

/// The ability of a Spell4Base in the client's plans.
fn real(base base: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_plan.plans(client_tables.shared()),
      base: Spell4BaseId(base),
    )
    as { "the plans hold Spell4Base " <> int.to_string(base) }
  spell
}

/// The spell of the Spell4 id among the spells the ability's tree reaches.
fn in_tree(base base: Int, spell4_id spell4_id: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.tree(spell: real(base:), started: fn(_) { True })
    |> list.find(fn(member) { member.spell4_id.value == spell4_id })
    as { "the tree holds Spell4 " <> int.to_string(spell4_id) }
  spell
}

/// The row `id` as the client's table holds it, with the rows it nests, for the
/// prerequisite the plan should hold.
fn client_rows() -> List(prerequisite_table.Prerequisite) {
  [
    support.row(id: 29_568, flags: 0, conditions: [
      #(15, 2, 0, 35_458),
      #(15, 2, 0, 35_703),
    ]),
    support.row(id: 903, flags: 0, conditions: [#(28, 1, 0, 0)]),
    support.row(id: 39_321, flags: 0, conditions: [#(11, 1, 12_939, 0)]),
    support.row(id: 12_939, flags: 0, conditions: [#(129, 2, 313, 0)]),
    support.row(id: 29_484, flags: 1, conditions: [
      #(64, 4, 4, 25),
      #(11, 1, 20_117, 47_439),
    ]),
    support.row(id: 20_117, flags: 0, conditions: [#(15, 1, 0, 47_439)]),
    support.row(id: 36_425, flags: 0, conditions: [#(64, 4, 4, 25)]),
    support.row(id: 19_750, flags: 0, conditions: [#(15, 1, 0, 42_908)]),
  ]
}

fn expected(id id: Int) -> prerequisite.Prerequisite {
  support.loaded(id:, rows: client_rows())
}

pub fn the_four_innates_that_hold_a_cast_condition_gate_their_press_on_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assert real(base: 30_828).caster_cast
    == CastGate(prerequisite: expected(id: 29_568))
    as "Warrior Stance: Onslaught 46867: CasterCast 29568"
  assert real(base: 38_012).caster_cast
    == CastGate(prerequisite: expected(id: 903))
    as "Esper Spectral Form 58586: 903, in combat"
  assert real(base: 30_075).caster_cast
    == CastGate(prerequisite: expected(id: 39_321))
    as "Stalker Stealth 46073: 39321, which nests 12939"
  assert real(base: 31_213).caster_cast
    == CastGate(prerequisite: expected(id: 29_484))
    as "Spellslinger Spell Surge 47273: 29484, which nests 20117"
}

pub fn rampages_cast_prerequisite_is_a_waiver_and_no_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assert real(base: 37_968).caster_cast
    == RequirementWaiver(prerequisite: expected(id: 19_750))
    as "Rampage 58524: propertyFlags 0x4100006 has bit 2 and casterInnateRequirement0 is 6"
}

pub fn the_spell_surge_buffs_caster_persistence_is_its_row_36425_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let buff = in_tree(base: 31_213, spell4_id: 47_439)
  assert buff.caster_persistence == Some(expected(id: 36_425))
    as "Spell4.47439: prerequisiteIdCasterPersistence 36425, slot 4 at least 25"
  assert buff.caster_cast == NoCasterCast && buff.target_cast == None
    as "47439 has no cast prerequisite"
}

pub fn the_engineers_and_the_medics_innates_hold_no_cast_condition_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  list.each([31_779, 46_615], fn(base) {
    let spell = real(base:)
    assert spell.caster_cast == NoCasterCast
      && spell.target_cast == None
      && spell.caster_persistence == None
      && spell.target_persistence == None
      as {
        "Engineer 47866 and Medic 69450 have none: Spell4Base "
        <> int.to_string(base)
      }
  })
}

// ---- what the plan makes of a column, on rows in memory ----

fn rows() -> fn(id.PrerequisiteId) ->
  Result(prerequisite_table.Prerequisite, Nil) {
  fn(wanted: id.PrerequisiteId) {
    list.find(client_rows(), fn(row) { row.id == wanted.value })
  }
}

pub fn bit_2_with_no_requirement_block_makes_the_cast_condition_a_gate_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.caster_cast_of(
      prerequisite_id: 903,
      property_flags: 4,
      requirement_block: #(0, 0, 0),
      rows: rows(),
      arcs: support.no_arcs(),
    )
    == Ok(CastGate(prerequisite: expected(id: 903)))
    as "0x1403ace00 skips the gate only for a spell with the block as well as bit 2"
}

pub fn bit_2_with_any_one_of_the_three_block_columns_makes_it_a_waiver_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([#(6, 0, 0), #(0, 6, 0), #(0, 0, 6)], fn(block) {
    assert spell_plan.caster_cast_of(
        prerequisite_id: 19_750,
        property_flags: 4,
        requirement_block: block,
        rows: rows(),
        arcs: support.no_arcs(),
      )
      == Ok(RequirementWaiver(prerequisite: expected(id: 19_750)))
      as "casterInnateRequirement0, casterInnateRequirement1 or targetBeginInnateRequirement alone makes the block"
  })
}

pub fn a_block_without_bit_2_leaves_the_cast_condition_a_gate_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.caster_cast_of(
      prerequisite_id: 903,
      property_flags: 0x4100002,
      requirement_block: #(6, 0, 0),
      rows: rows(),
      arcs: support.no_arcs(),
    )
    == Ok(CastGate(prerequisite: expected(id: 903)))
    as "propertyFlags 0x4100002 lacks bit 2 (0x4)"
}

pub fn no_prerequisite_id_is_no_cast_condition_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.caster_cast_of(
      prerequisite_id: 0,
      property_flags: 4,
      requirement_block: #(6, 0, 0),
      rows: rows(),
      arcs: support.no_arcs(),
    )
    == Ok(NoCasterCast)
  assert spell_plan.column_of(id: 0, rows: rows(), arcs: support.no_arcs())
    == Ok(None)
    as "a column holding 0 names no row"
}

pub fn a_column_naming_no_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.column_of(id: 77_777, rows: rows(), arcs: support.no_arcs())
    == Error(NoRow(table: "Prerequisite", id: 77_777))
  assert spell_plan.caster_cast_of(
      prerequisite_id: 77_777,
      property_flags: 0,
      requirement_block: #(0, 0, 0),
      rows: rows(),
      arcs: support.no_arcs(),
    )
    == Error(NoRow(table: "Prerequisite", id: 77_777))
    as "the same for the cast condition, waiver or gate"
}

pub fn a_column_whose_rows_nest_each_other_fails_the_load_naming_the_ids_test() -> Nil {
  use <- owned_test.run(5000)
  let looping = [
    support.row(id: 10, flags: 0, conditions: [#(11, 1, 20, 0)]),
    support.row(id: 20, flags: 0, conditions: [#(11, 1, 10, 0)]),
  ]
  assert spell_plan.column_of(
      id: 10,
      rows: fn(wanted: id.PrerequisiteId) {
        list.find(looping, fn(row) { row.id == wanted.value })
      },
      arcs: support.no_arcs(),
    )
    == Error(spell_plan.PrerequisiteCycle(path: [10, 20, 10]))
    as "a cycle fails the load, as the module's doc says"
}
