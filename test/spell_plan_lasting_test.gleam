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
import genesis_prime/game/spell_plan.{Always, GatedOnCaster, GatedOnTarget}
import genesis_prime/game/spend
import genesis_prime/message/crowd_control_state
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, Spell4Id,
}
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_group_list
import gleam/int
import gleam/list
import gleam/option
import gleam/string
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

fn plan_error(rows rows: spell_tables.Rows) -> spell_plan.PlanError {
  let assert Error(error) = spell_tables.planned_strike(rows:)
    as "the build fails"
  error
}

// ---- the Fluff rows ----

pub fn a_fluff_row_aimed_at_the_caster_that_lasts_until_removed_is_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // A row shaped as Power Charge's 96819 (targetFlags 1, flags 2), on an id of its own.
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: effect(id: 99_050, type_: 17, target_flags: 1, columns: [
          #("flags", Integer(2)),
        ]),
      ),
    )
  assert spell.lasting
    == [
      spell_plan.Lasting(
        effect_id: Spell4EffectsId(99_050),
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
  // A fluff row of Mental Overflow's kind (200468: type 17, 8 s, aimed at the caster) with a delay added, on an id of its own.
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: effect(id: 99_030, type_: 17, target_flags: 1, columns: [
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
  let rows = spell_tables.fixture_rows()
  assert spell_tables.fixture_strike().longer_of_delay_and_duration == False
  let with_flag =
    spell_tables.Rows(
      ..rows,
      spell4: list.map(rows.spell4, fn(row) {
        case row {
          [planted_table.Integer(32_893), ..] ->
            spell_tables.with_column(
              row:,
              name: "propertyFlags",
              cell: Integer(0x4002002),
            )
          other -> other
        }
      }),
    )
  let assert Ok(spell) = spell_tables.planned_strike(rows: with_flag)
  assert spell.longer_of_delay_and_duration
    as "Spell4.propertyFlags 0x2000 is the record's flag 0x10000000 (0x140568540)"
}

pub fn a_fluff_row_aimed_by_flags_that_are_not_read_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      rows: spell_tables.rows_with_effect(
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
  let rows = spell_tables.fixture_rows()
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
    spell_tables.planned_strike(
      rows: with_gate([#("prerequisiteIdCasterApply", Integer(17_302))]),
    )
  let assert [row] = caster.lasting
  let assert GatedOnCaster(gates: [_]) = row.condition
  let assert Ok(target) =
    spell_tables.planned_strike(
      rows: with_gate([#("prerequisiteIdTargetApply", Integer(5))]),
    )
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
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
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
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
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
    spell_tables.planned_strike(
      rows: spell_tables.Rows(
        ..spell_tables.rows_with_effect(
          effect: removal(selector: 1, named: 51, counts: #(1, 1)),
        ),
        spell4_group_lists: spell_tables.sorted_by_id([
          group_row,
          ..spell_tables.fixture_rows().spell4_group_lists
        ]),
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
  let assert Ok(_) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(
      effect: stray,
    ))
  Nil
}

pub fn a_removal_selector_other_than_1_to_3_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      rows: spell_tables.rows_with_effect(
        effect: removal(selector: 4, named: 1, counts: #(1, 1)),
      ),
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
      rows: spell_tables.rows_with_effect(
        effect: removal(selector: 2, named: 77_777, counts: #(1, 1)),
      ),
    )
    == spell_plan.NoRow(table: "Spell4", id: 77_777)
  assert plan_error(
      rows: spell_tables.rows_with_effect(
        effect: removal(selector: 3, named: 77_777, counts: #(1, 1)),
      ),
    )
    == spell_plan.NoRow(table: "Spell4Base", id: 77_777)
  assert plan_error(
      rows: spell_tables.rows_with_effect(
        effect: removal(selector: 1, named: 77_777, counts: #(1, 1)),
      ),
    )
    == spell_plan.NoRow(table: "Spell4GroupList", id: 77_777)
}

pub fn a_removal_whose_two_counts_differ_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      rows: spell_tables.rows_with_effect(
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
  let spell = spell_tables.fixture_strike()
  assert spell.groups
    == [6, 8, 19, 21, 23, 26, 94, 47, 235, 179, 237, 246, 333, 337, 609]
    as "Spell4 32893 names Spell4GroupList 321, whose non-zero groups these are in column order"
  assert spell.stack == Stack(group_id: 2, cap: 0)
    as "Spell4 32893 names Spell4StackGroup 2, whose stackCap is 0"
}

pub fn a_spell_with_no_group_or_stack_row_ids_holds_none_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_strike_columns(columns: [
        #("spell4GroupListId", Integer(0)),
        #("spell4StackGroupId", Integer(0)),
      ]),
    )
  assert spell.groups == []
  assert spell.stack == Stack(group_id: 0, cap: 0)
}

pub fn a_stack_group_the_tables_lack_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.fixture_rows()
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
              more: [#("spell4StackGroupId", 99_999)],
            )
          other -> other
        }
      }),
    )
  assert plan_error(rows: missing)
    == spell_plan.NoRow(table: "Spell4StackGroup", id: 99_999)
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
  effect(id: 99_040, type_: 4, target_flags:, columns: [
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
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: knockdown_row(state: 8, target_flags: 4, columns: []),
      ),
    )
  assert spell.controls
    == [
      spell_plan.CrowdControl(
        effect_id: Spell4EffectsId(99_040),
        phase_flags: -1,
        aim: spell_plan.AimsAtArea,
        row: crowd_control.Row(
          state: crowd_control_state.Knockdown,
          delay_ms: 166,
          duration_ms: 3000,
          armor_removed: 1,
          until_removed: False,
        ),
        tag: spend.EqualTo(0),
      ),
    ]
    as "Spell4Effects.effectType.4: dataBits00 the state, dataBits03 the armor, delayTime and durationTime the time"
}

/// Spell4Effects 224967 (`table_rows -- Spell4Effects 224967`): the Ability Disable
/// row of 85563, a CCStateSet of state 27 aimed at the caster (targetFlags 1), with no
/// delay or duration and flags 2, on an id of its own.
fn restriction_row(
  state state: Int,
  flags flags: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  effect(id: 99_041, type_: 4, target_flags:, columns: [
    #("dataBits00", Integer(state)),
    #("flags", Integer(flags)),
    ..columns
  ])
}

pub fn a_caster_ability_restriction_row_is_read_until_removed_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: restriction_row(
          state: 27,
          flags: 2,
          target_flags: 1,
          columns: [],
        ),
      ),
    )
  assert spell.controls
    == [
      spell_plan.CrowdControl(
        effect_id: Spell4EffectsId(99_041),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row: crowd_control.Row(
          state: crowd_control_state.AbilityRestriction,
          delay_ms: 0,
          duration_ms: 0,
          armor_removed: 0,
          until_removed: True,
        ),
        tag: spend.EqualTo(0),
      ),
    ]
    as "Unit.CodeEnumCCState 27 is AbilityRestriction, and Spell4Effects.flags bit 2 is a state that never times out (224967: dataBits00 27, flags 2, targetFlags 1)"
  assert spell_plan.controls_in_phase(spell:, phase: 0, spent: option.None)
    == []
    as "a state on the caster is no creature's: the strike's controls leave it out"
  assert list.map(
      spell_plan.restrictions_in_phase(spell:, phase: 0, spent: option.None),
      fn(control) { control.effect_id },
    )
    == [Spell4EffectsId(99_041)]
    as "the caster's states are read apart, by the phase flags the row names"
  let assert Ok(timed) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: restriction_row(state: 27, flags: 0, target_flags: 1, columns: [
          #("durationTime", Integer(4000)),
        ]),
      ),
    )
  assert list.map(timed.controls, fn(control) { control.row.until_removed })
    == [False]
    as "a row without flags bit 2 is not held until removed"
}

pub fn a_crowd_control_row_of_a_value_that_is_no_state_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([28, 99, -1], fn(state) {
    assert plan_error(
        rows: spell_tables.rows_with_effect(
          effect: knockdown_row(state:, target_flags: 4, columns: []),
        ),
      )
      == spell_plan.ControlStateNotRead(
        spell4_id: strike,
        effect_id: 99_040,
        state:,
      )
      as "Unit.CodeEnumCCState names the values 0 to 27; the client's CCStates table holds no other row"
  })
}

/// `Unit.CodeEnumCCState`: the 28 states, 0 to 27.
fn every_state() -> List(Int) {
  int.range(from: 0, to: 28, with: [], run: fn(states, state) {
    [state, ..states]
  })
  |> list.reverse
}

pub fn every_state_is_read_on_every_simple_aim_test() -> Nil {
  use <- owned_test.run(120_000)
  let aims = [
    #(1, spell_plan.AimsAtCaster),
    #(2, spell_plan.AimsAtPrimaryTarget),
    #(4, spell_plan.AimsAtArea),
    #(6, spell_plan.AimsAtBoth),
  ]
  list.each(aims, fn(aim) {
    let #(flags, expected_aim) = aim
    list.each(every_state(), fn(state) {
      let assert Ok(spell) =
        spell_tables.planned_strike(
          rows: spell_tables.rows_with_effect(
            effect: knockdown_row(state:, target_flags: flags, columns: []),
          ),
        )
        as {
          "Spell4Effects.effectType.4: state "
          <> int.to_string(state)
          <> " aimed by flags "
          <> int.to_string(flags)
          <> " is read"
        }
      assert spell.controls
        == [
          spell_plan.CrowdControl(
            effect_id: Spell4EffectsId(99_040),
            phase_flags: -1,
            aim: expected_aim,
            row: crowd_control.Row(
              state: crowd_control_state.from_value(state),
              delay_ms: 166,
              duration_ms: 3000,
              armor_removed: 1,
              until_removed: False,
            ),
            tag: spend.EqualTo(0),
          ),
        ]
        as "dataBits00 the state, delayTime and durationTime the time, dataBits03 the armor, targetFlags 1, 2, 4 and 6 the caster, the primary target, the area and both"
    })
  })
}

pub fn union_and_bit_eight_aims_stay_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([3, 5, 7, 9], fn(flags) {
    let error =
      plan_error(
        rows: spell_tables.rows_with_effect(
          effect: knockdown_row(state: 0, target_flags: flags, columns: []),
        ),
      )
    assert error
      == spell_plan.ControlAimNotRead(
        spell4_id: strike,
        effect_id: 99_040,
        target_flags: flags,
      )
      as "aim_of reads targetFlags 1, 2, 4 and 6 only"
    let named = case flags {
      9 -> "#336"
      _ -> "#794"
    }
    assert string.contains(spell_plan.describe(error:), named)
      as "the refusal names the issue that will read the aim: the union aims 3, 5 and 7 are #794, bit eight (9) is #336"
  })
}

pub fn a_state_until_removed_on_another_unit_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each([2, 4, 6], fn(flags) {
    let error =
      plan_error(
        rows: spell_tables.rows_with_effect(
          effect: knockdown_row(state: 0, target_flags: flags, columns: [
            #("flags", Integer(2)),
            #("durationTime", Integer(0)),
          ]),
        ),
      )
    assert error
      == spell_plan.ControlUntilRemovedNotRead(
        spell4_id: strike,
        effect_id: 99_040,
      )
      as "cc_state.instance_id: flags bit 2 never times out, and no rule of the server ends a creature's state when its cast's node ends"
    assert string.contains(spell_plan.describe(error:), "#803")
      as "the refusal names the issue that will end it"
  })
  let assert Ok(on_caster) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: knockdown_row(state: 0, target_flags: 1, columns: [
          #("flags", Integer(2)),
          #("durationTime", Integer(0)),
        ]),
      ),
    )
    as "a state on the caster ends with its cast's node (cast.restrictions)"
  assert list.map(on_caster.controls, fn(control) { control.row.until_removed })
    == [True]
}

pub fn a_persistence_prerequisite_on_another_unit_is_refused_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    [
      "prerequisiteIdTargetPersistence",
      "prerequisiteIdCasterPersistence",
      "prerequisiteIdTargetSuspend",
    ],
    fn(column) {
      let error =
        plan_error(
          rows: spell_tables.rows_with_effect(
            effect: knockdown_row(state: 0, target_flags: 2, columns: [
              #(column, Integer(17_302)),
            ]),
          ),
        )
      assert error
        == spell_plan.ControlPersistenceNotRead(
          spell4_id: strike,
          effect_id: 99_040,
        )
        as "Spell4Effects.prerequisiteIdTargetPersistence and its two siblings keep a state through a death or a leave, which no creature rule holds"
      assert string.contains(spell_plan.describe(error:), "#787")
        as "the refusal names the issue that will read persistence"
    },
  )
  let assert Ok(on_caster) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: knockdown_row(state: 0, target_flags: 1, columns: [
          #("prerequisiteIdTargetPersistence", Integer(17_302)),
        ]),
      ),
    )
    as "a row aimed at the caster still plans: the caster's own state is held by the cast"
  assert list.length(on_caster.controls) == 1
}

pub fn a_crowd_control_row_behind_an_apply_prerequisite_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(
    ["prerequisiteIdCasterApply", "prerequisiteIdTargetApply"],
    fn(column) {
      assert plan_error(
          rows: spell_tables.rows_with_effect(
            effect: knockdown_row(state: 8, target_flags: 4, columns: [
              #(column, Integer(17_302)),
            ]),
          ),
        )
        == spell_plan.ControlPrerequisiteNotRead(
          spell4_id: strike,
          effect_id: 99_040,
        )
    },
  )
}

pub fn every_ability_restriction_row_on_the_caster_is_read_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let spell_groups = spell_plan.spell_groups(tables:)
  let rows =
    spell4_effects.all(tables)
    |> list.filter(fn(row) {
      row.effect_type == 4 && row.data_bits00 == 27 && row.target_flags == 1
    })
  assert list.length(rows) == 24
    as "24 Spell4Effects rows are a CCStateSet of state 27 aimed at the caster (an own count over the table's dump)"
  let readings =
    list.map(rows, fn(effect) {
      spell_plan.read_row(
        tables:,
        spell_groups:,
        place: spell_tables.pressed,
        effect:,
      )
    })
  assert list.count(readings, fn(reading) {
      case reading {
        Ok(spell_plan.Applied(spell_plan.PlannedControl(control:))) ->
          control.aim == spell_plan.AimsAtCaster
          && control.row.state == crowd_control_state.AbilityRestriction
        _ -> False
      }
    })
    == 23
    as "23 of them are read: a state on the caster that no apply prerequisite gates"
  let refused =
    list.zip(rows, readings)
    |> list.filter_map(fn(pair) {
      case pair.1 {
        Error(spell_plan.ControlPrerequisiteNotRead(effect_id:, ..)) ->
          Ok(#(effect_id, pair.0.prerequisite_id_target_apply))
        _ -> Error(Nil)
      }
    })
  assert refused == [#(226_585, 903)]
    as "the one other is Spell4Effects 226585, behind the target apply prerequisite 903, which the plan refuses"
}
