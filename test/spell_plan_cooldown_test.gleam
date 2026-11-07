//// The cooldown modifiers of the plan (`genesis_prime/game/spell_plan`
//// `CooldownModifier`, `genesis_prime/game/effect_kind`). Expected values come from
//// these places:
//// - `Spell4Effects.effectType.73`: a ModifySpellCooldown row names its selector in
////   dataBits00 (0 a Spell4Base, 1 a Spell4, 2 a spell group, 3 a cooldown group, any
////   other value every spell), the id it compares in dataBits01, the operation in
////   dataBits02 (0 to 3) and the 32-bit float in dataBits03. The kit's five rows are
////   80977 (spell 34720, base 20684, operation 0, 0.0), 80979 (34722, base 20684,
////   operation 0, 0.4 = 0x3ECCCCCD), 180712 (spell 70775, base 32336, operation 2,
////   -1500.0 = 0xC4BB8000), 231992 and 231993 (70775, base 32336, operation 2, -500.0 =
////   0xC3FA0000, caster apply prerequisite 4585), all aimed at the caster with no delay
////   and no duration (`table_rows -- Spell4Effects 80977 80979 180712 231992 231993`).
//// - `0x14046b920` and `0x14046b1e0`: the client compares the ids and looks up no row by
////   dataBits01, so an id that no row holds loads and matches nothing; a cooldown group
////   the spell names must have a SpellCoolDown row, as StartSpellCooldowns reports an
////   error for a missing one.
//// - `Spell4Effects.targetFlags`: bit 1 is the caster, 2 the primary target, 4 the area.
//// - The table columns are signed 32-bit integers (`game_table.column_type`), so a
////   float's bits above 0x7FFFFFFF arrive negative.
//// - The load's rules: a float that is an infinity or not a number fails the load, as
////   type 11's coefficients do.

import client_tables
import genesis_prime/game/cooldown.{
  AddMs, Base, CooldownGroup, EverySpell, Modifier, NoLonger, SetMs, Spell,
  SpellGroup,
}
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  type Spell as PlannedSpell, Always, GatedOnCaster, GatedOnTarget,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, Spell4Id,
}
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables
import unitest

/// Telekinetic Strike's Spell4 and base, whose tree the planted rows hold
/// (`spell_tables`).
const strike = 32_893

/// A type 73 row of a planted spell aimed by `target_flags`, in every phase, with these
/// columns beside its id, spell and type: the selector 0 on base 20684 and operation 0
/// with the factor 0.0 unless the columns say otherwise.
fn cooldown_row(
  id id: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(73)),
    #("targetFlags", Integer(target_flags)),
    #("phaseFlags", Integer(-1)),
    #("orderIndex", Integer(9)),
    #("dataBits00", Integer(0)),
    #("dataBits01", Integer(20_684)),
    #("dataBits02", Integer(0)),
    #("dataBits03", Integer(0)),
  ]
  planted_table.row(
    spell4_effects.schema,
    list.append(
      list.filter(defaults, fn(default) {
        !list.any(columns, fn(given) { given.0 == default.0 })
      }),
      columns,
    ),
  )
}

fn modifiers_of(row row: List(Cell)) -> List(spell_plan.CooldownModifier) {
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
  spell.cooldown_modifiers
}

fn plan_error(row row: List(Cell)) -> spell_plan.PlanError {
  let assert Error(error) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
    as "the build fails"
  error
}

fn selector_of(row row: List(Cell)) -> cooldown.Selector {
  let assert [modifier] = modifiers_of(row:)
  modifier.modifier.selector
}

// ---- the rows of the plan ----

pub fn each_selector_value_decodes_to_its_case_test() -> Nil {
  use <- owned_test.run(60_000)
  assert selector_of(
      row: cooldown_row(id: 99_070, target_flags: 1, columns: [
        #("dataBits00", Integer(0)),
        #("dataBits01", Integer(20_684)),
      ]),
    )
    == Base(Spell4BaseId(20_684))
  assert selector_of(
      row: cooldown_row(id: 99_071, target_flags: 1, columns: [
        #("dataBits00", Integer(1)),
        #("dataBits01", Integer(34_718)),
      ]),
    )
    == Spell(Spell4Id(34_718))
  assert selector_of(
      row: cooldown_row(id: 99_072, target_flags: 1, columns: [
        #("dataBits00", Integer(2)),
        #("dataBits01", Integer(12)),
      ]),
    )
    == SpellGroup(12)
  assert selector_of(
      row: cooldown_row(id: 99_073, target_flags: 1, columns: [
        #("dataBits00", Integer(3)),
        #("dataBits01", Integer(133)),
      ]),
    )
    == CooldownGroup(133)
  assert selector_of(
      row: cooldown_row(id: 99_074, target_flags: 1, columns: [
        #("dataBits00", Integer(7)),
        #("dataBits01", Integer(5)),
      ]),
    )
    == EverySpell(selector: 7)
    as "0x14046b920: any other value picks every spell, whatever dataBits01 names"
}

pub fn an_id_that_no_row_holds_is_loaded_and_matches_nothing_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client compares dataBits01 with ids and looks up no row (0x14046b920): 22 rows
  // of the client name a base or a Spell4 that no row holds.
  assert selector_of(
      row: cooldown_row(id: 99_075, target_flags: 1, columns: [
        #("dataBits00", Integer(0)),
        #("dataBits01", Integer(0)),
      ]),
    )
    == Base(Spell4BaseId(0))
  assert selector_of(
      row: cooldown_row(id: 99_076, target_flags: 1, columns: [
        #("dataBits00", Integer(1)),
        #("dataBits01", Integer(77_777)),
      ]),
    )
    == Spell(Spell4Id(77_777))
}

pub fn each_operation_decodes_with_its_float_test() -> Nil {
  use <- owned_test.run(60_000)
  let operation_of = fn(operation, bits) {
    let assert [modifier] =
      modifiers_of(
        row: cooldown_row(id: 99_077, target_flags: 1, columns: [
          #("dataBits02", Integer(operation)),
          #("dataBits03", Integer(bits)),
        ]),
      )
    modifier.modifier.operation
  }
  assert operation_of(0, 1_053_609_165) == NoLonger(0.4000000059604645)
    as "0x3ECCCCCD is the 32-bit float 0.4, the row 80979's"
  assert operation_of(1, 1_073_741_824) == cooldown.Multiply(2.0)
    as "0x40000000 is 2.0"
  assert operation_of(2, -994_344_960) == AddMs(-1500.0)
    as "0xC4BB8000 is -1500.0, the row 180712's"
  assert operation_of(3, 1_198_153_728) == SetMs(60_000.0)
    as "0x476A6000 is 60000.0"
  assert operation_of(219, 0) == cooldown.Unchanged(operation: 219)
    as "the row 50869 holds the operation 219"
}

pub fn a_float_that_is_infinite_or_not_a_number_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x7F800000 is +infinity, 0xFF800000 is -infinity and 0x7FC00000 is not a number.
  assert plan_error(
      row: cooldown_row(id: 99_078, target_flags: 1, columns: [
        #("dataBits03", Integer(0x7F800000)),
      ]),
    )
    == spell_plan.CooldownNumberNotFinite(spell4_id: strike, effect_id: 99_078)
  assert plan_error(
      row: cooldown_row(id: 99_079, target_flags: 1, columns: [
        #("dataBits02", Integer(2)),
        #("dataBits03", Integer(-8_388_608)),
      ]),
    )
    == spell_plan.CooldownNumberNotFinite(spell4_id: strike, effect_id: 99_079)
  assert plan_error(
      row: cooldown_row(id: 99_080, target_flags: 1, columns: [
        #("dataBits03", Integer(0x7FC00000)),
      ]),
    )
    == spell_plan.CooldownNumberNotFinite(spell4_id: strike, effect_id: 99_080)
}

pub fn an_operation_the_client_has_no_case_for_reads_no_float_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x14046b920 reads the float only in the branches of operations 0 to 3.
  let assert [modifier] =
    modifiers_of(
      row: cooldown_row(id: 99_081, target_flags: 1, columns: [
        #("dataBits02", Integer(219)),
        #("dataBits03", Integer(0x7FC00000)),
      ]),
    )
  assert modifier.modifier.operation == cooldown.Unchanged(operation: 219)
}

pub fn a_row_aimed_at_the_caster_is_read_with_its_lifetime_columns_test() -> Nil {
  use <- owned_test.run(60_000)
  assert modifiers_of(
      row: cooldown_row(id: 99_082, target_flags: 1, columns: [
        #("delayTime", Integer(2000)),
        #("durationTime", Integer(8000)),
        #("phaseFlags", Integer(1)),
      ]),
    )
    == [
      spell_plan.CooldownModifier(
        effect_id: Spell4EffectsId(99_082),
        phase_flags: 1,
        modifier: Modifier(
          selector: Base(Spell4BaseId(20_684)),
          operation: NoLonger(0.0),
        ),
        row: LastingRow(delay_ms: 2000, duration_ms: 8000, until_removed: False),
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "the delay and duration are the lifetime's columns; the row's emmComparison 0 and emmValue 0 are the tag"
}

pub fn a_row_with_flags_bit_2_lasts_until_removed_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [row] =
    modifiers_of(
      row: cooldown_row(id: 99_083, target_flags: 1, columns: [
        #("flags", Integer(2)),
      ]),
    )
  assert row.row == LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
}

pub fn a_row_aimed_only_at_other_units_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // 2 the primary target, 4 the area, 6 both: 34 rows of the client, 30 at flags 2 and 4
  // at flags 4.
  list.each([2, 4, 6], fn(flags) {
    assert modifiers_of(
        row: cooldown_row(id: 99_084, target_flags: flags, columns: []),
      )
      == []
      as "a row aimed only at others changes another unit's cooldowns, which no rule keeps"
  })
}

pub fn a_row_aimed_at_the_caster_and_others_is_read_for_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3, 5 and 7 include the caster (8 rows of the client at flags 3): its part is read.
  list.each([3, 5, 7], fn(flags) {
    let assert [row] =
      modifiers_of(
        row: cooldown_row(id: 99_085, target_flags: flags, columns: []),
      )
    assert row.effect_id == Spell4EffectsId(99_085)
  })
}

pub fn a_row_behind_a_caster_prerequisite_is_gated_on_the_caster_and_behind_a_target_one_is_not_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [caster] =
    modifiers_of(
      row: cooldown_row(id: 99_086, target_flags: 1, columns: [
        #("prerequisiteIdCasterApply", Integer(17_302)),
      ]),
    )
  let assert GatedOnCaster(gates: [_]) = caster.condition
  let assert [target] =
    modifiers_of(
      row: cooldown_row(id: 99_087, target_flags: 1, columns: [
        #("prerequisiteIdTargetApply", Integer(5)),
      ]),
    )
  assert target.condition == GatedOnTarget(prerequisite_id: PrerequisiteId(5))
}

pub fn the_rows_of_a_phase_are_those_whose_phase_flags_name_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // phaseFlags bit n is phase n (`Spell4Effects.phaseFlags`).
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: cooldown_row(id: 99_088, target_flags: 1, columns: [
          #("phaseFlags", Integer(2)),
        ]),
      ),
    )
  assert spell_plan.cooldown_modifiers_in_phase(spell:, phase: 0, spent: None)
    == []
  assert list.length(spell_plan.cooldown_modifiers_in_phase(
      spell:,
      phase: 1,
      spent: None,
    ))
    == 1
}

// ---- the cooldown groups ----

pub fn a_spell_holds_the_cooldown_groups_its_row_names_test() -> Nil {
  use <- owned_test.run(60_000)
  // The kit's Charged Shot 34718 holds the group 133 (`table_rows -- Spell4 34718`); the
  // changed Telekinetic Strike names 133 and 134, and the client's SpellCoolDown holds a
  // row for both.
  let rows =
    spell_tables.rows_with_strike(name: "spellCoolDownId00", cell: Integer(133))
  let rows =
    spell_tables.Rows(
      ..rows,
      spell4: list.map(rows.spell4, fn(row) {
        case row {
          [Integer(32_893), ..] ->
            spell_tables.with_column(
              row:,
              name: "spellCoolDownId02",
              cell: Integer(134),
            )
          other -> other
        }
      }),
    )
  let assert Ok(spell) = spell_tables.planned_strike(rows:)
  assert spell.cooldown_groups == [133, 134]
    as "the non-zero of spellCoolDownId00 to 02, in column order (0x14055e180 lines 898-913)"
  let without = spell_tables.fixture_strike()
  assert without.cooldown_groups == [] as "a column holding 0 names no group"
}

pub fn a_cooldown_group_with_no_spellcooldown_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error(error) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_strike(
      name: "spellCoolDownId01",
      cell: Integer(999),
    ))
  assert error == spell_plan.NoRow(table: "SpellCoolDown", id: 999)
    as "StartSpellCooldowns reports an error for a group it finds no row for"
}

// ---- the effect kind ----

pub fn type_73_is_read_for_the_rows_that_include_the_caster_only_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 73) == effect_kind.CooldownModifier
  assert effect_kind.is_read(effect_type: 73)
  list.each([1, 3, 5, 7], fn(flags) {
    assert effect_kind.is_row_read(effect_type: 73, target_flags: flags)
      as "bit 1 of targetFlags is the caster"
  })
  list.each([2, 4, 6], fn(flags) {
    assert !effect_kind.is_row_read(effect_type: 73, target_flags: flags)
      as "a row aimed only at other units changes their cooldowns, which no rule keeps"
  })
  assert effect_kind.is_row_read(effect_type: 3, target_flags: 1)
    && !effect_kind.is_row_read(effect_type: 3, target_flags: 2)
    as "type 3 keeps its own reading"
}

// ---- the client's own rows ----

/// Every spell of the tree of a plan, the ability's own first.
fn tree_of(spell spell: PlannedSpell) -> List(PlannedSpell) {
  [
    spell,
    ..list.flatten([
      list.flat_map(spell.proxies, fn(proxy) { tree_of(spell: proxy.spell) }),
      list.flat_map(spell.stages, fn(stage) { tree_of(spell: stage.spell) }),
    ])
  ]
}

fn spell_in_trees(
  plans plans: spell_plan.Plans,
  spell4_id spell4_id: Int,
) -> PlannedSpell {
  let assert Ok(spell) =
    list.find(
      list.flat_map(
        list.map([20_684, 23_161], fn(base) {
          let assert Ok(ability) =
            spell_plan.in_plans(plans:, base: Spell4BaseId(base))
            as "the plans hold Charged Shot and Impale"
          ability
        }),
        fn(ability) { tree_of(spell: ability) },
      ),
      fn(spell) { spell.spell4_id == Spell4Id(spell4_id) },
    )
    as "the tree of Charged Shot or Impale holds the spell"
  spell
}

pub fn the_kits_five_rows_are_read_from_the_clients_tables_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  let charged_release = spell_in_trees(plans:, spell4_id: 34_720)
  assert charged_release.cooldown_modifiers
    == [
      spell_plan.CooldownModifier(
        effect_id: Spell4EffectsId(80_977),
        phase_flags: -1,
        modifier: Modifier(
          selector: Base(Spell4BaseId(20_684)),
          operation: NoLonger(0.0),
        ),
        row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "80977: Charged Shot's index-0 stage multiplies base 20684's cooldowns by 0.0, once, aimed at the caster"
  let level_1 = spell_in_trees(plans:, spell4_id: 34_722)
  assert list.map(level_1.cooldown_modifiers, fn(row) {
      #(row.effect_id, row.modifier, row.row)
    })
    == [
      #(
        Spell4EffectsId(80_979),
        Modifier(
          selector: Base(Spell4BaseId(20_684)),
          operation: NoLonger(0.4000000059604645),
        ),
        LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
      ),
    ]
    as "80979: index 1 multiplies by 0.4"
  let impale_child = spell_in_trees(plans:, spell4_id: 70_775)
  assert list.map(impale_child.cooldown_modifiers, fn(row) {
      #(row.effect_id, row.modifier, row.row)
    })
    == [
      #(
        Spell4EffectsId(180_712),
        Modifier(
          selector: Base(Spell4BaseId(32_336)),
          operation: AddMs(-1500.0),
        ),
        LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
      ),
      #(
        Spell4EffectsId(231_992),
        Modifier(selector: Base(Spell4BaseId(32_336)), operation: AddMs(-500.0)),
        LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
      ),
      #(
        Spell4EffectsId(231_993),
        Modifier(selector: Base(Spell4BaseId(32_336)), operation: AddMs(-500.0)),
        LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
      ),
    ]
    as "180712 takes 1500 ms and 231992 and 231993 500 ms each off base 32336 (Punish), in their orderIndex order 0, 1, 2"
  let assert [_, first, second] = impale_child.cooldown_modifiers
  let assert GatedOnCaster(gates: [_]) = first.condition
  let assert GatedOnCaster(gates: [_]) = second.condition
    as "231992 and 231993 hold the caster apply prerequisite 4585"
  let charged_shot = spell_in_trees(plans:, spell4_id: 34_718)
  assert charged_shot.cooldown_groups == [133]
    as "Spell4 34718: spellCoolDownId00 133 (table_rows -- Spell4 34718)"
}
