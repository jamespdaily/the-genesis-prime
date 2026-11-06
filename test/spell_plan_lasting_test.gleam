//// The lasting effects of the plan (`genesis_prime/game/spell_plan` `Lasting`,
//// `ForceRemove`, a spell's groups and stack). Expected values come from these
//// places:
//// - `Spell4Effects.effectType.17`: a Fluff row gives its spell a life on the unit its
////   targetFlags aim at, from its delayTime, durationTime and flags bit 2; Power Charge
////   42569's row 96819 aims at the caster and lasts until removed.
//// - `Spell4Effects.effectType.80`: dataBits00 picks the selector (1 a spell group, 2 a
////   Spell4, 3 a Spell4Base) by dataBits01, dataBits03 and 04 are the count; 80383's
////   row 212836 removes 3 stacks of Spell4 42569, and Quick Draw's 196521 is gated by
////   prerequisite 17302.
//// - `Spell4.propertyFlags`: bit 0x2000 is the spell record's flag 0x10000000.
//// - `Spell4StackGroup.stackCap` and `Spell4.spell4GroupListId`: a spell's stack group
////   and spell groups; Power Charge is in stack group 1450 (cap 2), Charged Shot and
////   80383 in group 2 (cap 0).
//// - The load's rules: a reachable type 80 row with a selector other than 1 to 3, one
////   that names no group, Spell4 or Spell4Base, one whose two counts differ, and a
////   Fluff or type 80 row with an aim that is not read, fail the load.

import client_tables
import genesis_prime/game/crowd_control
import genesis_prime/game/lasting.{Group, LastingRow, Spell, Stack}
import genesis_prime/game/spell_plan.{
  type Spell as PlannedSpell, Always, GatedOnCaster, GatedOnTarget,
}
import genesis_prime/game/spend
import genesis_prime/message/crowd_control_state
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, Spell4Id,
}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_group_list
import genesis_prime/table/spell4_stack_group
import gleam/list
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables
import unitest

/// Telekinetic Strike's Spell4 and base, whose tree the planted rows hold
/// (`spell_tables`).
const strike = 32_893

const strike_base = 19_102

/// A Spell4Effects row of a planted spell with these columns beside its id, spell,
/// type and aim, in every phase.
fn effect(
  id id: Int,
  type_ type_: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  planted_table.row(spell4_effects.schema, [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(type_)),
    #("targetFlags", Integer(target_flags)),
    #("phaseFlags", Integer(-1)),
    #("orderIndex", Integer(9)),
    ..columns
  ])
}

fn rows_with(effect effect: List(Cell)) -> spell_tables.Rows {
  let rows = spell_tables.rows()
  spell_tables.Rows(
    ..rows,
    spell4_effects: spell_tables.sorted_by_id([effect, ..rows.spell4_effects]),
  )
}

fn planned(
  rows rows: spell_tables.Rows,
) -> Result(PlannedSpell, spell_plan.PlanError) {
  spell_tables.with_loaded(rows:, body: fn(tables) {
    case spell_plan.build(tables:) {
      Ok(plans) -> {
        let assert Ok(spell) =
          spell_plan.in_plans(plans:, base: Spell4BaseId(strike_base))
          as "the plans hold Telekinetic Strike"
        Ok(spell)
      }
      Error(error) -> Error(error)
    }
  })
}

/// The planted Spell4 row with one column set.
fn with_column(
  row row: List(Cell),
  name name: String,
  cell cell: Cell,
) -> List(Cell) {
  list.zip(spell4.schema.columns, row)
  |> list.map(fn(pair) {
    case pair.0.name == name {
      True -> cell
      False -> pair.1
    }
  })
}

fn plan_error(rows rows: spell_tables.Rows) -> spell_plan.PlanError {
  let assert Error(error) = planned(rows:) as "the build fails"
  error
}

// ---- the Fluff rows ----

pub fn a_fluff_row_aimed_at_the_caster_that_lasts_until_removed_is_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // Power Charge's 96819: targetFlags 1, flags 2.
  let assert Ok(spell) =
    planned(
      rows: rows_with(
        effect: effect(id: 96_819, type_: 17, target_flags: 1, columns: [
          #("flags", Integer(2)),
        ]),
      ),
    )
  assert spell.lasting
    == [
      spell_plan.Lasting(
        effect_id: Spell4EffectsId(96_819),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "the row's emmComparison 0 and emmValue 0 (Spell4Effects.emmComparison)"
}

pub fn a_fluff_row_reads_its_delay_and_duration_test() -> Nil {
  use <- owned_test.run(60_000)
  // Mental Overflow's 200468: 8 s, aimed at the caster.
  let assert Ok(spell) =
    planned(
      rows: rows_with(
        effect: effect(id: 200_468, type_: 17, target_flags: 1, columns: [
          #("durationTime", Integer(8000)),
          #("delayTime", Integer(100)),
        ]),
      ),
    )
  let assert [lasting] = spell.lasting
  assert lasting.row
    == LastingRow(delay_ms: 100, duration_ms: 8000, until_removed: False)
}

pub fn a_spell_with_propertyflags_bit_0x2000_takes_the_larger_of_delay_and_duration_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let assert Ok(without) = planned(rows:)
  assert without.longer_of_delay_and_duration == False
  let with_flag =
    spell_tables.Rows(
      ..rows,
      spell4: list.map(rows.spell4, fn(row) {
        case row {
          [planted_table.Integer(32_893), ..] ->
            with_column(row:, name: "propertyFlags", cell: Integer(0x4002002))
          other -> other
        }
      }),
    )
  let assert Ok(spell) = planned(rows: with_flag)
  assert spell.longer_of_delay_and_duration
    as "Spell4.propertyFlags 0x2000 is the record's flag 0x10000000 (0x140568540)"
}

pub fn a_fluff_row_aimed_by_flags_that_are_not_read_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      rows: rows_with(
        effect: effect(id: 99_010, type_: 17, target_flags: 3, columns: []),
      ),
    )
    == spell_plan.LastingAimNotRead(
      spell4_id: strike,
      effect_id: 99_010,
      target_flags: 3,
    )
}

pub fn a_fluff_row_behind_a_caster_prerequisite_is_gated_on_the_caster_and_behind_a_target_one_is_not_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let with_gate = fn(columns) {
    spell_tables.Rows(
      ..rows,
      spell4_effects: spell_tables.sorted_by_id([
        effect(id: 99_011, type_: 17, target_flags: 1, columns:),
        ..rows.spell4_effects
      ]),
    )
  }
  let assert Ok(caster) =
    planned(rows: with_gate([#("prerequisiteIdCasterApply", Integer(17_302))]))
  let assert [row] = caster.lasting
  let assert GatedOnCaster(gates: [_]) = row.condition
  let assert Ok(target) =
    planned(rows: with_gate([#("prerequisiteIdTargetApply", Integer(5))]))
  let assert [row] = target.lasting
  assert row.condition == GatedOnTarget(prerequisite_id: PrerequisiteId(5))
}

// ---- the type 80 rows ----

fn removal(
  selector selector: Int,
  named named: Int,
  counts counts: #(Int, Int),
) -> List(Cell) {
  effect(id: 99_020, type_: 80, target_flags: 1, columns: [
    #("dataBits00", Integer(selector)),
    #("dataBits01", Integer(named)),
    #("dataBits03", Integer(counts.0)),
    #("dataBits04", Integer(counts.1)),
  ])
}

pub fn a_removal_of_a_spell4_is_read_with_its_count_test() -> Nil {
  use <- owned_test.run(60_000)
  // Telekinetic Strike's own tree holds Spell4 30900.
  let assert Ok(spell) =
    planned(
      rows: rows_with(
        effect: removal(selector: 2, named: 30_900, counts: #(3, 3)),
      ),
    )
  let assert [remove] = spell.removes
  assert remove.selector == Spell(Spell4Id(30_900))
  assert remove.count == 3
  assert remove.aim == spell_plan.AimsAtCaster
  assert remove.effect_id == Spell4EffectsId(99_020)
}

pub fn a_removal_of_a_spell4_base_and_of_a_group_are_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(by_base) =
    planned(
      rows: rows_with(
        effect: removal(selector: 3, named: 19_102, counts: #(1, 1)),
      ),
    )
  let assert [remove] = by_base.removes
  assert remove.selector == lasting.Base(Spell4BaseId(19_102))
  let group_row =
    planted_table.row(spell4_group_list.schema, [
      #("ID", Integer(5)),
      #("spellGroupId00", Integer(51)),
    ])
  let assert Ok(by_group) =
    planned(
      rows: spell_tables.Rows(
        ..rows_with(effect: removal(selector: 1, named: 51, counts: #(1, 1))),
        spell4_group_lists: [group_row],
      ),
    )
  let assert [remove] = by_group.removes
  assert remove.selector == Group(spell_group_id: 51)
}

pub fn a_removal_row_in_a_spell_outside_the_tree_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // The plans read the level-1 abilities' trees: a row of a spell no ability reaches
  // fails nothing, as the 36 rows that name no row do not.
  let stray =
    planted_table.row(spell4_effects.schema, [
      #("ID", Integer(99_030)),
      #("spellId", Integer(7)),
      #("effectType", Integer(80)),
      #("targetFlags", Integer(1)),
      #("dataBits00", Integer(4)),
    ])
  let assert Ok(_) = planned(rows: rows_with(effect: stray))
  Nil
}

pub fn a_removal_selector_other_than_1_to_3_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      rows: rows_with(effect: removal(selector: 4, named: 1, counts: #(1, 1))),
    )
    == spell_plan.ForceRemoveSelectorNotRead(
      spell4_id: strike,
      effect_id: 99_020,
      selector: 4,
    )
}

pub fn a_removal_that_names_no_row_fails_the_load_naming_the_table_and_id_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      rows: rows_with(
        effect: removal(selector: 2, named: 77_777, counts: #(1, 1)),
      ),
    )
    == spell_plan.NoRow(table: "Spell4", id: 77_777)
  assert plan_error(
      rows: rows_with(
        effect: removal(selector: 3, named: 77_777, counts: #(1, 1)),
      ),
    )
    == spell_plan.NoRow(table: "Spell4Base", id: 77_777)
  assert plan_error(
      rows: rows_with(
        effect: removal(selector: 1, named: 77_777, counts: #(1, 1)),
      ),
    )
    == spell_plan.NoRow(table: "Spell4GroupList", id: 77_777)
}

pub fn a_removal_whose_two_counts_differ_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      rows: rows_with(
        effect: removal(selector: 2, named: 30_900, counts: #(1, 5)),
      ),
    )
    == spell_plan.ForceRemoveCountsDiffer(
      spell4_id: strike,
      effect_id: 99_020,
      data_bits03: 1,
      data_bits04: 5,
    )
    as "which of dataBits03 and 04 is the count is not settled: 232 rows differ"
}

// ---- a spell's groups and stack ----

pub fn a_spell_reads_its_spell_groups_and_its_stack_group_and_cap_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let with_groups =
    spell_tables.Rows(
      ..rows,
      spell4: list.map(rows.spell4, fn(row) {
        case row {
          [planted_table.Integer(32_893), ..] ->
            spell_tables.method_spell_row(
              id: 32_893,
              base: strike_base,
              cast_time: 1250,
              cooldown: 0,
              kind: 0,
              global: 213,
              cost: #(0, 0),
              more: [
                #("spell4GroupListId", 8),
                #("spell4StackGroupId", 1450),
              ],
            )
          other -> other
        }
      }),
      spell4_group_lists: [
        planted_table.row(spell4_group_list.schema, [
          #("ID", Integer(8)),
          #("spellGroupId00", Integer(51)),
          #("spellGroupId01", Integer(52)),
        ]),
      ],
      spell4_stack_groups: [
        planted_table.row(spell4_stack_group.schema, [
          #("ID", Integer(1450)),
          #("stackCap", Integer(2)),
        ]),
      ],
    )
  let assert Ok(spell) = planned(rows: with_groups)
  assert spell.groups == [51, 52]
  assert spell.stack == Stack(group_id: 1450, cap: 2)
}

pub fn a_spell_with_no_group_or_stack_row_ids_holds_none_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(spell) = planned(rows: spell_tables.rows())
  assert spell.groups == []
  assert spell.stack == Stack(group_id: 0, cap: 0)
}

pub fn a_stack_group_the_tables_lack_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let missing =
    spell_tables.Rows(
      ..rows,
      spell4: list.map(rows.spell4, fn(row) {
        case row {
          [planted_table.Integer(32_893), ..] ->
            spell_tables.method_spell_row(
              id: 32_893,
              base: strike_base,
              cast_time: 1250,
              cooldown: 0,
              kind: 0,
              global: 213,
              cost: #(0, 0),
              more: [#("spell4StackGroupId", 1450)],
            )
          other -> other
        }
      }),
    )
  assert plan_error(rows: missing)
    == spell_plan.NoRow(table: "Spell4StackGroup", id: 1450)
}

// ---- the client's rows ----

pub fn power_charge_holds_its_fluff_and_80383_removes_3_stacks_of_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(client_tables.shared())
  let assert Ok(discharge) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(38_201))
    as "Discharge is a level-1 ability"
  let tree = spell_plan.tree(spell: discharge, started: fn(_) { True })
  let assert Ok(power_charge) =
    list.find(tree, fn(spell) { spell.spell4_id == Spell4Id(42_569) })
    as "Power Charge is in Discharge's tree"
  assert list.map(power_charge.lasting, fn(row) {
      #(row.effect_id, row.aim, row.row, row.condition)
    })
    == [
      #(
        Spell4EffectsId(96_819),
        spell_plan.AimsAtCaster,
        LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
        Always,
      ),
    ]
    as "Spell4Effects 96819: type 17, targetFlags 1, flags 2 (trace §4)"
  assert power_charge.stack == Stack(group_id: 1450, cap: 2)
    as "Spell4 42569 names stack group 1450, whose stackCap is 2 (Spell4StackGroup.stackCap)"
  let assert Ok(actuator_build) =
    list.find(tree, fn(spell) { spell.spell4_id == Spell4Id(80_383) })
    as "80383 is in Discharge's tree"
  assert list.map(actuator_build.removes, fn(row) {
      #(row.effect_id, row.selector, row.count, row.aim, row.condition)
    })
    == [
      #(
        Spell4EffectsId(212_836),
        Spell(Spell4Id(42_569)),
        3,
        spell_plan.AimsAtCaster,
        Always,
      ),
    ]
    as "Spell4Effects 212836: type 80, Spell4 42569, 3 stacks, aimed at the caster"
  assert actuator_build.stack == Stack(group_id: 2, cap: 0)
    as "Spell4 80383 is in stack group 2, cap 0"
  Nil
}

pub fn quick_draws_removal_is_gated_on_the_caster_under_its_marker_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(client_tables.shared())
  let assert Ok(quick_draw) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(27_638))
    as "Quick Draw is a level-1 ability"
  let tree = spell_plan.tree(spell: quick_draw, started: fn(_) { True })
  let assert Ok(row) =
    list.find_map(tree, fn(spell) {
      list.find(spell.removes, fn(row) {
        row.effect_id == Spell4EffectsId(196_521)
      })
    })
    as "Spell4Effects 196521 is in Quick Draw's tree"
  assert row.selector == Spell(Spell4Id(43_500))
  let assert GatedOnCaster(gates: [_]) = row.condition
    as "prerequisiteIdCasterApply 17302"
  Nil
}

// ---- the CCStateSet rows ----

/// Kick's CCStateSet row 140382 planted on the spell: a Knockdown (dataBits00 8) of
/// 3000 ms after 166 ms, removing 1 Interrupt Armor (dataBits03), aimed at the area
/// (`table_rows -- Spell4Effects 140382`).
fn knockdown_row(
  state state: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  effect(id: 140_382, type_: 4, target_flags:, columns: [
    #("delayTime", Integer(166)),
    #("durationTime", Integer(3000)),
    #("dataBits00", Integer(state)),
    #("dataBits03", Integer(1)),
    ..columns
  ])
}

pub fn a_crowd_control_row_is_read_with_its_state_time_armor_and_aim_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(spell) =
    planned(
      rows: rows_with(
        effect: knockdown_row(state: 8, target_flags: 4, columns: []),
      ),
    )
  assert spell.controls
    == [
      spell_plan.CrowdControl(
        effect_id: Spell4EffectsId(140_382),
        phase_flags: -1,
        aim: spell_plan.AimsAtArea,
        row: crowd_control.Row(
          state: crowd_control_state.Knockdown,
          delay_ms: 166,
          duration_ms: 3000,
          armor_removed: 1,
        ),
        tag: spend.EqualTo(0),
      ),
    ]
    as "Spell4Effects.effectType.4: dataBits00 the state, dataBits03 the armor, delayTime and durationTime the time"
}

pub fn a_crowd_control_row_of_a_state_other_than_a_stun_or_a_knockdown_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      rows: rows_with(
        effect: knockdown_row(state: 21, target_flags: 4, columns: []),
      ),
    )
    == spell_plan.ControlStateNotRead(
      spell4_id: strike,
      effect_id: 140_382,
      state: 21,
    )
    as "Snare (21) has no rule on a creature"
}

pub fn a_crowd_control_row_aimed_at_the_caster_or_by_other_flags_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([1, 3], fn(flags) {
    assert plan_error(
        rows: rows_with(
          effect: knockdown_row(state: 8, target_flags: flags, columns: []),
        ),
      )
      == spell_plan.ControlAimNotRead(
        spell4_id: strike,
        effect_id: 140_382,
        target_flags: flags,
      )
      as "a state on the caster is a player's, which no creature casts"
  })
}

pub fn a_crowd_control_row_behind_an_apply_prerequisite_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    ["prerequisiteIdCasterApply", "prerequisiteIdTargetApply"],
    fn(column) {
      assert plan_error(
          rows: rows_with(
            effect: knockdown_row(state: 8, target_flags: 4, columns: [
              #(column, Integer(17_302)),
            ]),
          ),
        )
        == spell_plan.ControlPrerequisiteNotRead(
          spell4_id: strike,
          effect_id: 140_382,
        )
    },
  )
}
