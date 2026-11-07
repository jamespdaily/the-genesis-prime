//// The Scale (18), RavelSignal (81) and UnitPropertyConversion (145) rows of the plan
//// (`genesis_prime/game/spell_plan`, `genesis_prime/game/effect_kind`). Expected values
//// come from these places:
//// - `Spell4Effects.effectType.18`: the client resizes any unit it lands on and the
////   server only lists the row in the go with its lifetime, so a Scale row is a lasting
////   row; the game holds 531 rows of it, 109482 (Onslaught's 42908: targetFlags 1,
////   durationTime 8000, dataBits00 1.3) the one in the level-1 trees.
//// - `Spell4Effects.effectType.81`: the client gives it no class, so it is only a life
////   for its spell; 91018 in 38784 is the one in the level-1 trees, behind target apply
////   prerequisite 11311.
//// - `Spell4Effects.effectType.145`: property dataBits01 gains dataBits02 (a 32-bit
////   float) times property dataBits00; 229304 in the Engineer passive 45000 is 47 to 60
////   at 0x3e800000 (0.25), flags 2, targetFlags 1 (`table_rows -- Spell4Effects
////   spellId=45000`).
//// - `Spell4Effects.targetFlags` (bit 1 the caster, 2 the primary target, 4 the area):
////   Scale rows aimed by 3 (2 rows) and 7 (3 rows) and RavelSignal rows aimed by 3 (61)
////   and 7 (11) exist in the game and the plan refuses them, as it does a Fluff row.
//// - The plan's rule that an effect behind a target apply prerequisite is not applied,
////   and CLAUDE.md's "a missing row fails the load".
//// The tests on the client's tables are skipped where it is not on the machine.

import client_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  AimsAtArea, AimsAtBoth, AimsAtCaster, AimsAtPrimaryTarget, Always,
  GatedOnCaster, GatedOnTarget,
}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import genesis_prime/table/spell4_effects
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/set
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables
import unitest

/// Telekinetic Strike's Spell4 and base, whose tree the planted rows hold
/// (`spell_tables`).
const strike = 32_893

/// 1.3 as the client's row 109482 holds it (`table_rows -- Spell4Effects spellId=42908`).
const one_point_three = 1_067_869_798

/// 0.25 as row 229304 holds it.
const a_quarter = 1_048_576_000

fn planned(row row: List(Cell)) -> spell_plan.Spell {
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
    as "the plan builds"
  spell
}

fn plan_error(row row: List(Cell)) -> spell_plan.PlanError {
  let assert Error(error) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
    as "the build fails"
  error
}

/// The lasting row of the planted effect id, which the plan holds or not. A planted row
/// takes an id no client row holds, since it would replace the client's
/// (`spell_tables.rows_with_effect`); a comment names the client row whose shape it has.
fn lasting_row(
  spell spell: spell_plan.Spell,
  id id: Int,
) -> Result(spell_plan.Lasting, Nil) {
  list.find(spell.lasting, fn(row) { row.effect_id == Spell4EffectsId(id) })
}

// ---- the decode ----

pub fn kind_of_gives_scale_ravel_signal_and_property_conversion_and_each_is_read_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 18) == effect_kind.Scale
    as "Spell.CodeEnumSpellEffectType value 18 'Scale' (Spell4Effects.effectType.18)"
  assert effect_kind.kind_of(effect_type: 81) == effect_kind.RavelSignal
    as "value 81 'RavelSignal' (Spell4Effects.effectType.81)"
  assert effect_kind.kind_of(effect_type: 145) == effect_kind.PropertyConversion
    as "value 145 'UnitPropertyConversion' (Spell4Effects.effectType.145)"
  assert effect_kind.is_read(effect_type: 18)
  assert effect_kind.is_read(effect_type: 81)
  assert effect_kind.is_read(effect_type: 145)
}

pub fn a_scale_or_ravel_signal_row_is_read_for_every_aim_and_a_conversion_row_for_the_caster_only_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([1, 2, 4, 6], fn(flags) {
    assert effect_kind.is_row_read(effect_type: 18, target_flags: flags)
      as "the client resizes any unit the effect lands on (Spell4Effects.effectType.18)"
    assert effect_kind.is_row_read(effect_type: 81, target_flags: flags)
  })
  assert effect_kind.is_row_read(effect_type: 145, target_flags: 1)
    as "a conversion works on its holder's properties: the caster"
  assert !effect_kind.is_row_read(effect_type: 145, target_flags: 2)
    as "a row aimed only at another unit is left out, as a type 11 row is"
}

// ---- the plan: planted tables ----

pub fn a_scale_row_aimed_at_the_caster_is_a_lasting_row_with_its_columns_test() -> Nil {
  use <- owned_test.run(60_000)
  // 109482 as the client holds it: caster, 8000 ms, no flags.
  let spell =
    planned(
      row: spell_tables.effect_row_with(
        id: 99_071,
        effect_type: 18,
        target_flags: 1,
        columns: [
          #("durationTime", Integer(8000)),
          #("dataBits00", Integer(one_point_three)),
          #("dataBits01", Integer(500)),
          #("dataBits02", Integer(1000)),
        ],
      ),
    )
  assert lasting_row(spell:, id: 99_071)
    == Ok(spell_plan.Lasting(
      effect_id: Spell4EffectsId(99_071),
      phase_flags: -1,
      aim: AimsAtCaster,
      row: LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
      condition: Always,
      tag: spend.EqualTo(value: 0),
    ))
    as "the delay and durationTime are the row's; the row's emmComparison 0 and emmValue 0 are the tag"
  // The same row with a delay, flags bit 2, one phase and a caster prerequisite.
  let spell =
    planned(
      row: spell_tables.effect_row_with(
        id: 99_101,
        effect_type: 18,
        target_flags: 1,
        columns: [
          #("delayTime", Integer(250)),
          #("flags", Integer(2)),
          #("phaseFlags", Integer(2)),
          #("prerequisiteIdCasterApply", Integer(17_302)),
        ],
      ),
    )
  let assert Ok(row) = lasting_row(spell:, id: 99_101)
  assert row.row
    == LastingRow(delay_ms: 250, duration_ms: 0, until_removed: True)
  assert row.phase_flags == 2
  let assert GatedOnCaster(gates: [_]) = row.condition
  assert list.length(spell_plan.lasting_in_phase(spell:, phase: 1, spent: None))
    == 1
  assert spell_plan.lasting_in_phase(spell:, phase: 0, spent: None) == []
}

pub fn a_scale_or_ravel_signal_row_is_held_for_each_aim_the_plan_reads_test() -> Nil {
  use <- owned_test.run(60_000)
  let aims = [
    #(1, AimsAtCaster),
    #(2, AimsAtPrimaryTarget),
    #(4, AimsAtArea),
    #(6, AimsAtBoth),
  ]
  list.each([18, 81], fn(effect_type) {
    list.each(aims, fn(aim) {
      let spell =
        planned(
          row: spell_tables.effect_row_with(
            id: 99_102,
            effect_type:,
            target_flags: aim.0,
            columns: [#("durationTime", Integer(1000))],
          ),
        )
      let assert Ok(row) = lasting_row(spell:, id: 99_102)
      assert row.aim == aim.1
        as "Spell4Effects.targetFlags: 1 the caster, 2 the primary target, 4 the area, 6 both"
    })
  })
}

pub fn a_ravel_signal_row_behind_a_target_prerequisite_is_held_gated_on_the_target_test() -> Nil {
  use <- owned_test.run(60_000)
  // 91018: caster and target 11311 (Spell4Effects.effectType.81).
  let spell =
    planned(
      row: spell_tables.effect_row_with(
        id: 99_073,
        effect_type: 81,
        target_flags: 1,
        columns: [
          #("dataBits00", Integer(1)),
          #("dataBits01", Integer(13_076)),
          #("prerequisiteIdTargetApply", Integer(11_311)),
        ],
      ),
    )
  let assert Ok(row) = lasting_row(spell:, id: 99_073)
  assert row.condition == GatedOnTarget(prerequisite_id: PrerequisiteId(11_311))
    as "an effect behind a target apply prerequisite is not applied"
}

pub fn a_scale_row_aimed_by_3_and_a_ravel_signal_row_aimed_by_7_fail_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      row: spell_tables.effect_row_with(
        id: 99_103,
        effect_type: 18,
        target_flags: 3,
        columns: [],
      ),
    )
    == spell_plan.LastingAimNotRead(
      spell4_id: strike,
      effect_id: 99_103,
      target_flags: 3,
    )
  assert plan_error(
      row: spell_tables.effect_row_with(
        id: 99_104,
        effect_type: 81,
        target_flags: 7,
        columns: [],
      ),
    )
    == spell_plan.LastingAimNotRead(
      spell4_id: strike,
      effect_id: 99_104,
      target_flags: 7,
    )
}

pub fn a_property_conversion_row_is_a_modifier_that_converts_47_into_60_at_a_quarter_test() -> Nil {
  use <- owned_test.run(60_000)
  // 229304: 47 to 60 at 0x3e800000, flags 2, orderIndex 4.
  let spell =
    planned(
      row: spell_tables.effect_row_with(
        id: 99_074,
        effect_type: 145,
        target_flags: 1,
        columns: [
          #("flags", Integer(2)),
          #("orderIndex", Integer(4)),
          #("dataBits00", Integer(47)),
          #("dataBits01", Integer(60)),
          #("dataBits02", Integer(a_quarter)),
        ],
      ),
    )
  let assert Ok(row) =
    list.find(spell.modifiers, fn(row) {
      row.effect_id == Spell4EffectsId(99_074)
    })
  assert row.change
    == spell_plan.PropertyChange(unit_properties.Conversion(
      from: UnitProperty2Id(47),
      to: UnitProperty2Id(60),
      share: 0.25,
    ))
  assert row.row == LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
    as "flags bit 2: until removed"
  assert row.condition == Always
}

pub fn a_conversion_row_naming_no_property_or_a_nan_share_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client's UnitProperty2 holds ids 0 to 199 and has no row 200.
  assert plan_error(
      row: spell_tables.effect_row_with(
        id: 99_105,
        effect_type: 145,
        target_flags: 1,
        columns: [
          #("flags", Integer(2)),
          #("dataBits00", Integer(47)),
          #("dataBits01", Integer(200)),
          #("dataBits02", Integer(a_quarter)),
        ],
      ),
    )
    == spell_plan.ModifierPropertyHasNoRow(
      spell4_id: strike,
      effect_id: 99_105,
      property: 200,
    )
  assert plan_error(
      row: spell_tables.effect_row_with(
        id: 99_106,
        effect_type: 145,
        target_flags: 1,
        columns: [
          #("flags", Integer(2)),
          #("dataBits00", Integer(200)),
          #("dataBits01", Integer(60)),
          #("dataBits02", Integer(a_quarter)),
        ],
      ),
    )
    == spell_plan.ModifierPropertyHasNoRow(
      spell4_id: strike,
      effect_id: 99_106,
      property: 200,
    )
  // 0x7FC00000 is a NaN.
  assert plan_error(
      row: spell_tables.effect_row_with(
        id: 99_107,
        effect_type: 145,
        target_flags: 1,
        columns: [
          #("flags", Integer(2)),
          #("dataBits00", Integer(47)),
          #("dataBits01", Integer(60)),
          #("dataBits02", Integer(2_143_289_344)),
        ],
      ),
    )
    == spell_plan.ModifierNumberNotFinite(
      spell4_id: strike,
      effect_id: 99_107,
      column: "dataBits02",
    )
}

// ---- the plan: the client's tables ----

/// The spell of this Spell4 id inside the tree of the plan of this Spell4Base.
fn in_tree(base base: Int, spell4_id spell4_id: Int) -> spell_plan.Spell {
  let plans = spell_plan.plans(tables: client_tables.shared())
  let assert Ok(root) = spell_plan.in_plans(plans:, base: Spell4BaseId(base))
    as "the plans hold the base"
  let assert Ok(found) =
    spell_plan.tree(spell: root, started: fn(_) { True })
    |> list.find(fn(spell) { spell.spell4_id == Spell4Id(spell4_id) })
    as "the tree holds the spell"
  found
}

pub fn onslaughts_42908_lists_109482_on_the_caster_for_8_seconds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Spell4Base 30828 is the Warrior's innate active (Class 1); 46867 reaches 42908
  // through its ungated Proxy 127637.
  let spell = in_tree(base: 30_828, spell4_id: 42_908)
  assert lasting_row(spell:, id: 109_482)
    == Ok(spell_plan.Lasting(
      effect_id: Spell4EffectsId(109_482),
      phase_flags: -1,
      aim: AimsAtCaster,
      row: LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
      condition: Always,
      tag: spend.EqualTo(value: 0),
    ))
    as "`table_rows -- Spell4Effects spellId=42908`: targetFlags 1, delayTime 0, durationTime 8000, flags 0"
}

pub fn the_stalkers_stealth_child_holds_91018_gated_on_target_prerequisite_11311_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Spell4Base 30075 is the Stalker's innate active (Class 5); 46073 starts 38784.
  let spell = in_tree(base: 30_075, spell4_id: 38_784)
  let assert Ok(row) = lasting_row(spell:, id: 91_018)
  assert row.condition == GatedOnTarget(prerequisite_id: PrerequisiteId(11_311))
    as "`table_rows -- Spell4Effects spellId=38784`: prerequisiteIdTargetApply 11311"
}

pub fn the_engineers_passive_holds_229304_as_a_conversion_from_47_to_60_until_removed_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Spell4Base 29076 is the Engineer's innate passive (Class 2), whose spell is 45000.
  let spell = in_tree(base: 29_076, spell4_id: 45_000)
  let assert Ok(row) =
    list.find(spell.modifiers, fn(row) {
      row.effect_id == Spell4EffectsId(229_304)
    })
  assert row.change
    == spell_plan.PropertyChange(unit_properties.Conversion(
      from: UnitProperty2Id(47),
      to: UnitProperty2Id(60),
      share: 0.25,
    ))
    as "`table_rows -- Spell4Effects spellId=45000`: dataBits00 47, dataBits01 60, dataBits02 0x3e800000"
  assert row.row == LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
    as "flags 2"
}

pub fn the_plans_hold_every_type_18_81_and_145_row_of_the_trees_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let plans = spell_plan.plans(tables:)
  let spells =
    dict.values(plans)
    |> list.flat_map(fn(root) {
      spell_plan.tree(spell: root, started: fn(_) { True })
    })
  let in_the_trees =
    set.from_list(list.map(spells, fn(spell) { spell.spell4_id.value }))
  let rows_in_the_trees =
    list.filter(spell4_effects.all(tables), fn(row) {
      list.contains([18, 81, 145], row.effect_type)
      && set.contains(in_the_trees, row.spell_id)
    })
    |> list.map(fn(row) { row.id })
    |> list.unique
    |> list.sort(int.compare)
  assert rows_in_the_trees == [91_018, 109_482, 229_304]
    as "the walk of the level-1 trees: one row of each type, Spell4Effects 109482 (18), 91018 (81) and 229304 (145)"
  let held =
    list.flat_map(spells, fn(spell) {
      list.flatten([
        list.map(spell.lasting, fn(row) { row.effect_id.value }),
        list.map(spell.modifiers, fn(row) { row.effect_id.value }),
      ])
    })
  list.each(rows_in_the_trees, fn(id) {
    assert list.contains(held, id)
      as { "the plan holds the row " <> int.to_string(id) }
  })
}
