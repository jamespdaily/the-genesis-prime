//// The Interrupt Armor rows of the plan (`genesis_prime/game/spell_plan`
//// `PropertyModifier.armor`, `genesis_prime/game/effect_kind`). Expected values come
//// from these places.
//// - `Spell4Effects.effectType.52`: a ModifyInterruptArmor row adds dataBits00 points to
////   the unit it lands on for durationTime; dataBits01 1 or 0 says whether the points
////   are taken back at the end (the test spells 42697 'Test IA - Modify +2 Remove', row
////   97340: targetFlags 1, dataBits00 2, durationTime 10000, dataBits01 1; and 42698
////   'Modify +2 No Remove', row 97343: the same with dataBits01 0), and the client
////   clamps the armor to property 44, so the row is a property change too
////   (`table_rows -- Spell4Effects spellId=42697`, `=42698`, `UnitProperty2 44`).
//// - Row 199192 of Spell4 76766 (targetFlags 2, dataBits00 1, durationTime 5000,
////   dataBits01 0), which Esper's Proxy 178143 (targetFlags 1) starts on the caster;
////   row 210820 of Spell4 79875 (targetFlags 2, dataBits00 2, durationTime 8000,
////   dataBits01 1), which Warrior's Proxy 210822 starts behind Prerequisite 37438
////   (`table_rows -- Spell4Effects spellId=76766`, `=79875`, `=46867`, `=58586`).
//// - Row 105619 of type 52 (targetFlags 4): aimed at the units a go strikes, which the
////   creature side holds (`creature_control`).
//// - `opcode.0x7f4.effect_time`: a row whose Spell4Effects flags have bit 2 never ends;
////   8 rows of type 52 hold it (`table_rows -- Spell4Effects 210961`: flags 2).
//// - `Spell4Effects.targetFlags`: bit 1 the caster, 2 the primary target, 4 the area. The
////   server's present simplification is that the primary target of a cast on the caster
////   is the caster, so a flags-2 row of such a spell reaches the caster; a child a Proxy
////   starts on each struck unit has that unit as its primary target.
//// The rows are in memory except in the last test, which reads the client's tables.

import client_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  AimsAtCaster, AimsAtPrimaryTarget, Always, GatedOnCaster, InterruptArmor,
  OnCaster, OnEachStruck,
}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{type Modifier, Change}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, UnitProperty2Id}
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/list
import gleam/option.{Some}
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables
import unitest

/// Telekinetic Strike's Spell4, whose tree the planted rows hold (`spell_tables`).
const strike = 32_893

/// A type 52 row of the planted spell aimed by `target_flags`, in every phase, with
/// these columns beside its id, spell and type.
fn armor_row(
  id id: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(52)),
    #("targetFlags", Integer(target_flags)),
    #("phaseFlags", Integer(-1)),
    #("orderIndex", Integer(9)),
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

fn modifiers_of(row row: List(Cell)) -> List(spell_plan.PropertyModifier) {
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
  spell.modifiers
}

fn plan_error(row row: List(Cell)) -> spell_plan.PlanError {
  let assert Error(error) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
    as "the build fails"
  error
}

/// The change an Interrupt Armor row of `points` makes to property 44: x * 1.0 + points,
/// the type 11 formula, with no row mode.
fn raising_property_44(points points: Float) -> Modifier {
  Change(
    property: UnitProperty2Id(44),
    mode: 0,
    multiplier: 1.0,
    flat: points,
    per_level: 0.0,
  )
}

// ---- the rows of the plan ----

pub fn an_interrupt_armor_row_aimed_at_the_caster_is_read_with_its_points_time_and_take_back_test() -> Nil {
  use <- owned_test.run(60_000)
  assert modifiers_of(
      row: armor_row(id: 97_340, target_flags: 1, columns: [
        #("dataBits00", Integer(2)),
        #("dataBits01", Integer(1)),
        #("durationTime", Integer(10_000)),
      ]),
    )
    == [
      spell_plan.PropertyModifier(
        effect_id: Spell4EffectsId(97_340),
        phase_flags: -1,
        change: spell_plan.PropertyChange(raising_property_44(points: 2.0)),
        row: LastingRow(delay_ms: 0, duration_ms: 10_000, until_removed: False),
        condition: Always,
        tag: spend.EqualTo(value: 0),
        armor: Some(InterruptArmor(
          points: 2,
          takes_back: True,
          aim: AimsAtCaster,
        )),
      ),
    ]
    as "row 97340: +2 for 10000 ms from the go, dataBits01 1 takes the points back; the armor row is a x 1.0 + 2 change of property 44"
  let assert [kept] =
    modifiers_of(
      row: armor_row(id: 97_343, target_flags: 1, columns: [
        #("dataBits00", Integer(2)),
        #("dataBits01", Integer(0)),
        #("durationTime", Integer(10_000)),
      ]),
    )
  assert kept.armor
    == Some(InterruptArmor(points: 2, takes_back: False, aim: AimsAtCaster))
    as "row 97343: dataBits01 0 keeps the armor up to the new maximum"
}

pub fn an_interrupt_armor_row_aimed_at_the_primary_target_of_a_child_on_the_caster_is_read_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 199192 of Spell4 76766, as the client holds it: targetFlags 2, +1, 5000 ms,
  // dataBits01 0.
  let row =
    spell4_effects_row(
      id: 199_192,
      spell: 76_766,
      target_flags: 2,
      points: 1,
      duration_ms: 5000,
      data_bits01: 0,
    )
  let assert Ok(read) =
    spell_plan.interrupt_armor_of(
      spell4_id: 76_766,
      effect: row,
      condition: Always,
    )
  assert read.armor
    == Some(InterruptArmor(
      points: 1,
      takes_back: False,
      aim: AimsAtPrimaryTarget,
    ))
    as "targetFlags 2 is the primary target"
  assert read.row
    == LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False)
  assert spell_plan.proxy_armors_read(
      spell4_id: 58_586,
      proxy_effect_id: 178_143,
      target: OnCaster,
      modifiers: [read],
    )
    == Ok(Nil)
    as "Proxy 178143 has targetFlags 1: spell_plan.target_of starts the child on the caster, whose primary target is the caster"
}

pub fn an_interrupt_armor_row_aimed_at_the_primary_target_of_a_child_on_each_struck_unit_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    spell4_effects_row(
      id: 199_192,
      spell: 76_766,
      target_flags: 2,
      points: 1,
      duration_ms: 5000,
      data_bits01: 0,
    )
  let assert Ok(on_primary) =
    spell_plan.interrupt_armor_of(
      spell4_id: 76_766,
      effect: row,
      condition: Always,
    )
  assert spell_plan.proxy_armors_read(
      spell4_id: 58_586,
      proxy_effect_id: 178_143,
      target: OnEachStruck,
      modifiers: [on_primary],
    )
    == Error(spell_plan.InterruptArmorOnStruckUnit(
      spell4_id: 58_586,
      proxy_effect_id: 178_143,
      effect_id: 199_192,
    ))
    as "the child's primary target is a struck unit, and Interrupt Armor on one is not built"
  let assert Ok(on_caster) =
    spell_plan.interrupt_armor_of(
      spell4_id: 76_766,
      effect: spell_tables.blank_effect(
        id: 199_192,
        spell: 76_766,
        effect_type: 52,
        target_flags: 3,
      ),
      condition: Always,
    )
  assert spell_plan.proxy_armors_read(
      spell4_id: 58_586,
      proxy_effect_id: 178_143,
      target: OnEachStruck,
      modifiers: [on_caster],
    )
    == Ok(Nil)
    as "a row that includes the caster reaches the caster, whichever unit the child is cast on"
}

pub fn a_planted_area_proxys_child_holding_an_interrupt_armor_row_on_its_primary_target_fails_the_plan_test() -> Nil {
  use <- owned_test.run(60_000)
  // The planted Telekinetic Strike (32893) holds Proxy 62204, aimed at the area (targetFlags
  // 4), which starts 30900 on each unit it strikes (`spell_tables`).
  assert plan_error(
      row: armor_row(id: 99_054, target_flags: 2, columns: [
        #("spellId", Integer(30_900)),
        #("dataBits00", Integer(1)),
        #("durationTime", Integer(5000)),
      ]),
    )
    == spell_plan.InterruptArmorOnStruckUnit(
      spell4_id: strike,
      proxy_effect_id: 62_204,
      effect_id: 99_054,
    )
    as "the child's primary target is a struck unit, so the load fails, naming the Proxy and the row"
  assert modifiers_of(
      row: armor_row(id: 99_055, target_flags: 3, columns: [
        #("spellId", Integer(30_900)),
        #("dataBits00", Integer(1)),
        #("durationTime", Integer(5000)),
      ]),
    )
    == []
    as "a row that includes the caster loads: the strike's own spell holds no armor row"
}

pub fn an_interrupt_armor_row_aimed_only_at_struck_units_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // Row 105619 has targetFlags 4: the creature side's.
  assert modifiers_of(
      row: armor_row(id: 105_619, target_flags: 4, columns: [
        #("dataBits00", Integer(1)),
        #("durationTime", Integer(5000)),
      ]),
    )
    == []
    as "aimed only at the area, it is left out of the plan"
  assert list.length(
      modifiers_of(
        row: armor_row(id: 105_620, target_flags: 1, columns: [
          #("dataBits00", Integer(1)),
          #("durationTime", Integer(5000)),
        ]),
      ),
    )
    == 1
    as "while the same row aimed at the caster is read, so the plan does read type 52"
  assert list.map([4, 6], fn(flags) {
      modifiers_of(
        row: armor_row(id: 105_619, target_flags: flags, columns: [
          #("durationTime", Integer(5000)),
        ]),
      )
    })
    == [[], []]
    as "4 and 6 aim only at other units"
}

pub fn an_interrupt_armor_row_with_an_unknown_data_bits01_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert plan_error(
      row: armor_row(id: 99_052, target_flags: 1, columns: [
        #("dataBits00", Integer(1)),
        #("dataBits01", Integer(2)),
        #("durationTime", Integer(5000)),
      ]),
    )
    == spell_plan.InterruptArmorTakeBackNotRead(
      spell4_id: strike,
      effect_id: 99_052,
      value: 2,
    )
    as "the 38 rows hold dataBits01 0 and 1 only, and nothing says what another value means"
}

pub fn an_interrupt_armor_row_with_flags_bit_2_has_no_end_test() -> Nil {
  use <- owned_test.run(60_000)
  // Row 210961 of Spell4 79917: flags 2, no duration, delay 150000.
  let assert [row] =
    modifiers_of(
      row: armor_row(id: 99_053, target_flags: 1, columns: [
        #("flags", Integer(2)),
        #("dataBits00", Integer(1)),
        #("dataBits01", Integer(1)),
      ]),
    )
  assert row.row == LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
    as "the client gives an effect whose flags have bit 2 no end timer"
}

// ---- the kinds ----

pub fn effect_kind_reads_interrupt_armor_aimed_at_the_caster_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 52) == effect_kind.InterruptArmor
  assert effect_kind.is_read(effect_type: 52)
    as "the measure counts type 52 handled"
  let read = fn(flags) {
    effect_kind.is_row_read(effect_type: 52, target_flags: flags)
  }
  assert list.map([1, 2, 4, 5], read) == [True, True, False, True]
    as "read for the caster (bit 1) or the primary target alone (2), which a spell cast on the caster makes the caster; 4 aims at the area only"
}

// ---- the client's tables ----

/// The Spell4 `spell4_id` of the tree of the innate whose Spell4Base is `base`.
fn planned(base base: Int, spell4_id spell4_id: Int) -> spell_plan.Spell {
  let plans = spell_plan.plans(client_tables.shared())
  let assert Ok(innate) = spell_plan.in_plans(plans:, base: Spell4BaseId(base))
    as "the plans hold the innate"
  let assert Ok(spell) =
    list.find(
      spell_plan.tree(spell: innate, started: fn(_) { True }),
      fn(spell) { spell.spell4_id.value == spell4_id },
    )
    as "the innate's tree holds the spell"
  spell
}

pub fn spectral_forms_child_holds_one_interrupt_armor_for_five_seconds_kept_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let assert [esper] =
    list.filter(planned(base: 38_012, spell4_id: 76_766).modifiers, fn(row) {
      row.effect_id == Spell4EffectsId(199_192)
    })
    as "Spell4Effects spellId=76766: the child holds row 199192"
  assert esper.armor
    == Some(InterruptArmor(
      points: 1,
      takes_back: False,
      aim: AimsAtPrimaryTarget,
    ))
    as "+1, dataBits01 0"
  assert esper.row
    == LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False)
    as "5000 ms"
  assert esper.change
    == spell_plan.PropertyChange(raising_property_44(points: 1.0))
  let assert [warrior] =
    list.filter(planned(base: 30_828, spell4_id: 79_875).modifiers, fn(row) {
      row.effect_id == Spell4EffectsId(210_820)
    })
    as "Spell4Effects spellId=79875: the child holds row 210820"
  assert warrior.armor
    == Some(InterruptArmor(
      points: 2,
      takes_back: True,
      aim: AimsAtPrimaryTarget,
    ))
    as "+2, dataBits01 1"
  assert warrior.row
    == LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False)
    as "8000 ms"
  let assert [gated] =
    list.filter(planned(base: 30_828, spell4_id: 46_867).proxies, fn(proxy) {
      proxy.effect_id == Spell4EffectsId(210_822)
    })
    as "Spell4Effects spellId=46867: Proxy 210822 starts 79875"
  let assert GatedOnCaster(gates: [_]) = gated.condition
    as "Proxy 210822 has prerequisiteIdCasterApply 37438"
  let rows = spell4_effects.all(client_tables.shared())
  let struck_children = spell_plan.struck_unit_children(effects: rows)
  let type_52 = list.filter(rows, fn(row) { row.effect_type == 52 })
  assert list.length(type_52) == 38
    as "`table_rows -- Spell4Effects effectType=52`: 38 rows"
  assert list.count(type_52, fn(row) {
      spell_plan.effect_row_read(effect: row, struck_children:)
    })
    == 36
    as "36 are read; row 105619 (targetFlags 4) is not, and neither is row 100384 (targetFlags 2) of Spell4 43457, which Proxy 99382 (targetFlags 4) starts on each struck unit"
  Nil
}

fn spell4_effects_row(
  id id: Int,
  spell spell: Int,
  target_flags target_flags: Int,
  points points: Int,
  duration_ms duration_ms: Int,
  data_bits01 data_bits01: Int,
) -> Spell4Effects {
  Spell4Effects(
    ..spell_tables.blank_effect(id:, spell:, effect_type: 52, target_flags:),
    duration_time: duration_ms,
    data_bits00: points,
    data_bits01:,
  )
}
