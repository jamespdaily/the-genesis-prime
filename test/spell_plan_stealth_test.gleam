//// The Stealth and RemoveStealth effects of the plan and a spell's stealth change
//// (`genesis_prime/game/spell_plan` `StealthRow`, `RemoveStealthRow`, `StealthChange`).
//// What the plan refuses is tested on rows in memory, since each planted load puts
//// 4 MiB of terms into the run; a few whole-plan tests read the planted toggle tree
//// and the client's own. Expected values come from these places:
//// - `Spell4Effects.effectType.83`: a Stealth row aimed at the caster (targetFlags 1)
////   holds the stealth until it is removed when it has no durationTime; dataBits02 0 means
////   damage ends it and 1 means it does not. The Stalker's rows are 83834 in Spell4 38784
////   (dataBits02 0, caster apply prerequisite 16152, phase flags 1) and 95774
////   (dataBits02 1, 16153), as `table_rows -- Spell4Effects spellId=38784` prints them.
//// - `Spell4Effects.effectType.84`: a RemoveStealth row ends its target's stealth.
//// - `Spell4.spellCastStealthChange`: 1 on Impale 38779, 0 on its Proxies' children 39426
////   and 39427 and on 38783, 2 on 46073, 38784 and Impale's Fluff child 70775.
//// - `Spell4Conditions.conditionMask.16`: the client's stealth test in a caster or target
////   conditions row; the server does not check results 65 and 114, so a planned spell
////   that names such a row fails the load.
//// - The server's load rules (the plan's doc): a Stealth or RemoveStealth row aimed other
////   than at the caster alone, behind a target apply prerequisite, or (a Stealth row) with
////   a delayTime or durationTime, fails the load, and so does a stealth change or a
////   dataBits02 the plan has no case for.

import client_tables
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  Always, BrokenByDamage, EndsStealthAfterLastGo, EndsStealthAtEachGo,
  GatedOnCaster, KeepsStealth, KeptOnDamage, RemoveStealthRow, StealthRow,
}
import genesis_prime/game/spend
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/spell4_conditions.{Spell4Conditions}
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table.{Integer}
import prerequisite_support
import spell_tables
import unitest

/// The spell the in-memory rows are said to belong to: Telekinetic Strike's Spell4.
const strike = 32_893

/// The base of the Stalker's Stealth toggle, 46073, and Impale's.
const toggle_base = 30_075

const impale_base = 23_161

/// A Spell4Effects row aimed at the caster, in memory, with every other column 0: the
/// planted tables' rows are the whole-plan tests'.
fn blank(id id: Int) -> Spell4Effects {
  spell_tables.blank_effect(
    id:,
    spell: strike,
    effect_type: 83,
    target_flags: 1,
  )
}

fn plans_spell(base base: Int) -> spell_plan.Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_tables.fixture_plans(),
      base: Spell4BaseId(base),
    )
    as "the planted plans hold the ability"
  spell
}

// ---- the rows of the plan, whole ----

pub fn the_toggles_two_stealth_rows_and_its_spells_stealth_changes_are_read_as_the_rows_hold_them_test() -> Nil {
  use <- owned_test.run(60_000)
  let toggle = plans_spell(base: toggle_base)
  assert toggle.stealth_change == KeepsStealth
    as "46073 holds spellCastStealthChange 2 (Spell4.spellCastStealthChange)"
  let assert [on, cancel] = list.map(toggle.proxies, fn(proxy) { proxy.spell })
  assert on.spell4_id.value == 38_784
  assert cancel.spell4_id.value == 38_783
  assert on.stealth_change == KeepsStealth
    as "38784 holds 2: the toggle's own spells do not end the stealth they make"
  assert cancel.stealth_change == EndsStealthAtEachGo
    as "38783 holds 0, and 0 ends stealth (Spell4.spellCastStealthChange.break)"
  assert on.stealth
    == [
      StealthRow(
        effect_id: Spell4EffectsId(83_834),
        phase_flags: 1,
        breaks: BrokenByDamage,
        row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
        condition: GatedOnCaster(gates: [
          prerequisite_support.single(id: 16_152, condition: #(50, 2, 0, 59_389)),
        ]),
        tag: spend.EqualTo(value: 0),
      ),
      StealthRow(
        effect_id: Spell4EffectsId(95_774),
        phase_flags: 1,
        breaks: KeptOnDamage,
        row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
        condition: GatedOnCaster(gates: [
          prerequisite_support.single(id: 16_153, condition: #(50, 1, 0, 59_389)),
        ]),
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "83834 breaks on damage (dataBits02 0) behind 16152 and 95774 is kept (dataBits02 1) behind 16153; both have no durationTime, so they last until removed"
  assert on.remove_stealth == []
  assert cancel.stealth == []
  assert plans_spell(base: impale_base).stealth_change == EndsStealthAfterLastGo
    as "Impale 38779 holds 1, and 1 ends stealth after the cast's last go"
}

pub fn impales_tree_in_the_clients_tables_ends_stealth_in_all_but_its_fluff_child_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Impale 38779 holds 1, its Proxies' children 39426 and 39427 hold 0 and its Fluff
  // child 70775 holds 2 (`table_rows -- Spell4 38779 39426 39427 70775`).
  let assert Ok(impale) =
    spell_plan.in_plans(
      plans: spell_plan.plans(client_tables.shared()),
      base: Spell4BaseId(impale_base),
    )
    as "the client's plans hold Impale"
  let changes =
    list.map(spell_plan.tree(spell: impale, started: fn(_) { True }), fn(spell) {
      #(spell.spell4_id.value, spell.stealth_change)
    })
    |> list.unique
  assert list.sort(changes, fn(first, second) { int.compare(first.0, second.0) })
    == [
      #(38_779, EndsStealthAfterLastGo),
      #(39_426, EndsStealthAtEachGo),
      #(39_427, EndsStealthAtEachGo),
      #(70_775, KeepsStealth),
    ]
    as "the tree of Impale: 1, 0, 0 and 2"
}

pub fn a_remove_stealth_row_aimed_at_the_caster_is_read_in_its_phases_with_its_gate_test() -> Nil {
  use <- owned_test.run(60_000)
  // A type 84 row of the client aimed at the caster (targetFlags 1): the planted row
  // has no prerequisite and every phase (Spell4Effects.effectType.84).
  let row =
    planted_table.row(spell4_effects.schema, [
      #("ID", Integer(99_841)),
      #("spellId", Integer(strike)),
      #("effectType", Integer(84)),
      #("targetFlags", Integer(1)),
      #("phaseFlags", Integer(-1)),
      #("orderIndex", Integer(9)),
    ])
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
  assert spell.remove_stealth
    == [
      RemoveStealthRow(
        effect_id: Spell4EffectsId(99_841),
        phase_flags: -1,
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
}

// ---- what fails the load, on rows in memory ----

pub fn a_stealth_row_aimed_at_the_caster_says_whether_damage_ends_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.stealth_read(
      spell4_id: strike,
      effect: Spell4Effects(..blank(id: 1), data_bits02: 0),
    )
    == Ok(BrokenByDamage)
    as "dataBits02 0 on 83834 (Spell4Effects.effectType.83)"
  assert spell_plan.stealth_read(
      spell4_id: strike,
      effect: Spell4Effects(..blank(id: 2), data_bits02: 1),
    )
    == Ok(KeptOnDamage)
    as "dataBits02 1 on 95774"
}

pub fn a_stealth_row_with_a_duration_or_a_delay_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(5000)
  // 38 of the client's 74 type 83 rows hold a durationTime and 3 a delayTime: timed
  // stealth is not built (`table_rows -- Spell4Effects effectType=83`, columns
  // durationTime and delayTime).
  assert spell_plan.stealth_read(
      spell4_id: strike,
      effect: Spell4Effects(..blank(id: 99_831), duration_time: 8000),
    )
    == Error(spell_plan.StealthTimedNotRead(
      spell4_id: strike,
      effect_id: 99_831,
    ))
  assert spell_plan.stealth_read(
      spell4_id: strike,
      effect: Spell4Effects(..blank(id: 99_832), delay_time: 100),
    )
    == Error(spell_plan.StealthTimedNotRead(
      spell4_id: strike,
      effect_id: 99_832,
    ))
}

pub fn a_stealth_or_remove_stealth_row_not_aimed_at_the_caster_alone_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(5000)
  // targetFlags 2 is the primary target and 4 the area: the client's type 83 rows hold 1
  // (63 rows), 2 (7) and 4 (4), and its type 84 rows 1 (5), 2 (3) and 4 (1)
  // (`table_rows -- Spell4Effects effectType=83`, `effectType=84`, column targetFlags).
  list.each([2, 3, 4, 6], fn(flags) {
    let effect = Spell4Effects(..blank(id: 99_833), target_flags: flags)
    let refusal =
      spell_plan.StealthAimNotRead(
        spell4_id: strike,
        effect_id: 99_833,
        target_flags: flags,
      )
    assert spell_plan.stealth_read(spell4_id: strike, effect:) == Error(refusal)
    assert spell_plan.stealth_on_the_caster(spell4_id: strike, effect:)
      == Error(refusal)
  })
  assert spell_plan.stealth_on_the_caster(
      spell4_id: strike,
      effect: blank(id: 1),
    )
    == Ok(Nil)
    as "targetFlags 1 is the caster"
}

pub fn a_stealth_or_remove_stealth_row_behind_a_target_prerequisite_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(5000)
  // 33144 is a target apply prerequisite three of the client's type 83 rows hold
  // (`table_rows -- Spell4Effects prerequisiteIdTargetApply=33144`).
  let effect =
    Spell4Effects(..blank(id: 99_834), prerequisite_id_target_apply: 33_144)
  let refusal =
    spell_plan.StealthTargetPrerequisiteNotRead(
      spell4_id: strike,
      effect_id: 99_834,
    )
  assert spell_plan.stealth_read(spell4_id: strike, effect:) == Error(refusal)
  assert spell_plan.stealth_on_the_caster(spell4_id: strike, effect:)
    == Error(refusal)
}

pub fn a_stealth_row_with_a_databits02_that_is_not_0_or_1_fails_the_load_naming_itself_test() -> Nil {
  use <- owned_test.run(5000)
  // The client's type 83 rows hold 0 (47 rows) and 1 (27): dataBits02 says whether
  // damage ends the stealth (`table_rows -- Spell4Effects effectType=83`, column
  // dataBits02).
  assert spell_plan.stealth_read(
      spell4_id: strike,
      effect: Spell4Effects(..blank(id: 99_835), data_bits02: 2),
    )
    == Error(spell_plan.StealthBreaksNotRead(
      spell4_id: strike,
      effect_id: 99_835,
      value: 2,
    ))
}

pub fn a_stealth_change_of_0_and_1_ends_stealth_2_keeps_it_and_3_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  // The client's column holds 0 (61356 rows), 1 (533) and 2 (4702) and no other value
  // (Spell4.spellCastStealthChange).
  assert spell_plan.stealth_change_of(spell4_id: strike, value: 0)
    == Ok(EndsStealthAtEachGo)
  assert spell_plan.stealth_change_of(spell4_id: strike, value: 1)
    == Ok(EndsStealthAfterLastGo)
  assert spell_plan.stealth_change_of(spell4_id: strike, value: 2)
    == Ok(KeepsStealth)
  assert spell_plan.stealth_change_of(spell4_id: strike, value: 3)
    == Error(spell_plan.StealthChangeNotRead(spell4_id: strike, value: 3))
}

pub fn a_caster_or_target_conditions_row_with_the_stealth_bit_fails_the_load_naming_the_row_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Conditions.conditionMask.16 is the stealth test: a mask of 16 (a planted row
  // 12), and 129, the client's row 15 (bits 1 and 128), which has none.
  let stealthy =
    Some(Spell4Conditions(id: 12, condition_mask: 16, condition_value: 0))
  let plain =
    Some(Spell4Conditions(id: 15, condition_mask: 129, condition_value: 0))
  assert spell_plan.stealth_conditions_read(spell4_id: strike, conditions: [
      plain,
      None,
    ])
    == Ok(Nil)
  let refused =
    Error(spell_plan.StealthConditionNotRead(
      spell4_id: strike,
      spell4_conditions_id: 12,
    ))
  assert spell_plan.stealth_conditions_read(spell4_id: strike, conditions: [
      stealthy,
      None,
    ])
    == refused
    as "the caster row"
  assert spell_plan.stealth_conditions_read(spell4_id: strike, conditions: [
      None,
      stealthy,
    ])
    == refused
    as "the target row"
}
