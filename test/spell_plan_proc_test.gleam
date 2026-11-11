//// The Proc effects of the plan (`genesis_prime/game/spell_plan` `ProcRow`, `Trigger`,
//// `proc_read`). What the plan refuses is tested on rows in memory, since each planted
//// load puts 4 MiB of terms into the run; the plan of the client's own tables is read
//// where the client is present. Expected values come from these places:
//// - `Spell4Effects.effectType.14.dataBits00.217_218` and `.0_44`: the Stalker's passive
////   45057 (Class 5, Spell4Base 29131) holds five Proc rows on its caster, in row order
////   (`table_rows -- Spell4Effects spellId=45057`, column orderIndex): 147119 (kind 217,
////   casts 60724), 147132 (218, 60769), 159136 (44, 63366), 202043 (0, 63366) and 211002
////   (218, 79932); each has targetFlags 1, chance 1.0 (dataBits02 1065353216), durationTime
////   0 with flags 2 (until removed), dataBits04 and dataBits05 of 500 and 1 for kinds 217
////   and 218 and 1000 and 1 for 44 and 0.
//// - `Spell4Effects.effectType.14.limits`: dataBits05 times in dataBits04 milliseconds.
//// - `Spell4Effects.effectType.14.dataBits00`: kind 12 is 'lands a hit' (Engineer 52371's
////   123744, casts 52370) and kind 16 'takes damage' (Stalker 38784's 178239, casts
////   72838): the plan reads neither.
//// - `Spell4Effects.effectType.14`: dataBits01 is the Spell4 the proc casts; the Spell4
////   rows 60769 (effect 147136, type 80), 79932 (210998, 212528 to 212530, type 11) and
////   63366 (159134, type 73) are its tree.
//// - The server's load rules (the plan's doc, `Spell4Effects.effectType.14.dataBits03`,
////   `.prerequisites`, `.dataBits07`, `.lifetime`): a row of a kind read with a column the
////   plan does not read fails the load naming it. Across the client's 83 rows of the four
////   kinds, 30 hold targetFlags other than 1 (rows 791, 5725, 5898), 9 a dataBits04 of -1
////   (2313, 4435, 37547) and 1 a delayTime (144096); the other 43 are read.

import cast_support
import client_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{
  type Spell, Always, Died, EnteredStealth, LeftCombat, LeftStealth,
  ProcKindNotRead, ProcNotRead, ProcReading,
}
import genesis_prime/table/id.{Spell4BaseId}
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import unitest

/// The spell the in-memory rows are said to belong to: the Stalker's passive.
const holder = 45_057

/// The Stalker's passive as the real plans hold it, by its Spell4Base.
fn passive() -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: cast_support.real_plans(),
      base: Spell4BaseId(29_131),
    )
    as "the plans hold the Stalker's innate passive"
  spell
}

/// Every spell of every tree the real plans hold, by Spell4 id.
fn spell_named(spell4_id spell4_id: Int) -> Spell {
  let assert Ok(spell) =
    list.flat_map(dict.values(cast_support.real_plans()), fn(ability) {
      spell_plan.tree(spell: ability, started: fn(_) { True })
    })
    |> list.find(fn(spell) { spell.spell4_id.value == spell4_id })
    as "a tree of the plans holds the spell"
  spell
}

/// A Proc row aimed at the caster as 147119 holds it, in memory, with this id and the
/// columns changed: kind 217 casting 60724, chance 1.0, once in 500 ms, until removed.
fn row(id id: Int) -> Spell4Effects {
  Spell4Effects(
    id:,
    spell_id: holder,
    target_flags: 1,
    effect_type: 14,
    damage_type: 0,
    delay_time: 0,
    tick_time: 0,
    duration_time: 0,
    flags: 2,
    data_bits00: 217,
    data_bits01: 60_724,
    data_bits02: 1_065_353_216,
    data_bits03: 1,
    data_bits04: 500,
    data_bits05: 1,
    data_bits06: 0,
    data_bits07: 0,
    data_bits08: 0,
    data_bits09: 0,
    innate_cost_per_tick_type0: 0,
    innate_cost_per_tick_type1: 0,
    innate_cost_per_tick0: 0,
    innate_cost_per_tick1: 0,
    emm_comparison: 0,
    emm_value: 0,
    threat_multiplier: 0.0,
    spell4_effect_group_list_id: 0,
    prerequisite_id_caster_apply: 0,
    prerequisite_id_target_apply: 0,
    prerequisite_id_caster_persistence: 0,
    prerequisite_id_target_persistence: 0,
    prerequisite_id_target_suspend: 0,
    parameter_type00: 0,
    parameter_type01: 0,
    parameter_type02: 0,
    parameter_type03: 0,
    parameter_value00: 0.0,
    parameter_value01: 0.0,
    parameter_value02: 0.0,
    parameter_value03: 0.0,
    phase_flags: -1,
    order_index: 0,
  )
}

// ---- the rows of the plan, whole ----

pub fn the_stalkers_passive_holds_its_five_procs_on_the_caster_in_row_order_with_their_limits_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let procs =
    list.map(passive().procs, fn(proc) {
      #(
        proc.effect_id.value,
        proc.trigger,
        proc.spell.spell4_id.value,
        proc.window_ms,
        proc.count,
      )
    })
  assert procs
    == [
      #(147_119, EnteredStealth, 60_724, 500, 1),
      #(147_132, LeftStealth, 60_769, 500, 1),
      #(159_136, LeftCombat, 63_366, 1000, 1),
      #(202_043, Died, 63_366, 1000, 1),
      #(211_002, LeftStealth, 79_932, 500, 1),
    ]
    as "Spell4Effects 147119, 147132, 159136, 202043 and 211002 in orderIndex order: dataBits00 217, 218, 44, 0 and 218, dataBits01 the spell cast, dataBits04 the window and dataBits05 the count"
  assert list.all(passive().procs, fn(proc) {
    proc.row == LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
    && proc.condition == Always
    && proc.phase_flags == -1
  })
    as "durationTime 0 with flags 2 (until removed), no caster apply prerequisite and every phase, on each of the five rows"
}

pub fn a_proc_of_a_kind_not_read_is_in_no_list_and_the_load_succeeds_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  assert spell_named(spell4_id: 52_371).procs == []
    as "52371 'Eradication ExoSuit - Proc Base' holds 123744, kind 12: it is skipped"
  assert spell_named(spell4_id: 38_784).procs == []
    as "38784 'Stealth - On' holds 178239, kind 16: it is skipped"
}

pub fn a_procs_spell_is_planned_as_its_tree_and_the_tree_walks_it_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let ids =
    spell_plan.tree(spell: passive(), started: fn(_) { True })
    |> list.map(fn(spell) { spell.spell4_id.value })
    |> set.from_list
  assert set.is_subset(set.from_list([60_724, 60_769, 79_932, 63_366]), of: ids)
    as "dataBits01 of each Proc row is a spell of the passive's tree, with the Proxy child 60724 it already held"
  assert list.length(spell_named(spell4_id: 60_769).removes) == 1
    as "60769's one row, 147136, is a SpellForceRemove (type 80)"
  assert list.map(spell_named(spell4_id: 79_932).modifiers, fn(row) {
      row.effect_id.value
    })
    |> list.sort(int.compare)
    == [210_998, 212_528, 212_529, 212_530]
    as "79932's four UnitPropertyModifier rows (Spell4.79932)"
  assert list.map(spell_named(spell4_id: 63_366).cooldown_modifiers, fn(row) {
      row.effect_id.value
    })
    == [159_134]
    as "63366's one row, 159134, is a ModifySpellCooldown (type 73)"
}

pub fn a_proc_that_leads_back_to_a_spell_on_the_way_fails_as_a_cycle_naming_the_chain_test() -> Nil {
  use <- owned_test.run(5000)
  // The chain a proc's spell is planned on is the chain of the Proxy children
  // (`spell_plan.chain_extended`): a Proc row of 60724 that cast 45057 would repeat it.
  assert spell_plan.chain_extended(chain: [45_057], spell4_id: 60_724)
    == Ok([45_057, 60_724])
  assert spell_plan.chain_extended(chain: [45_057, 60_724], spell4_id: 45_057)
    == Error(spell_plan.ProxyCycle(chain: [45_057, 60_724, 45_057]))
    as "the spells from the pressed ability to the one that repeats, as a cycle of Proxies is named"
}

// ---- what a row says, on rows in memory ----

pub fn a_proc_row_is_read_for_its_trigger_and_its_limit_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.proc_read(spell4_id: holder, effect: row(id: 147_119))
    == Ok(ProcReading(trigger: EnteredStealth, window_ms: 500, count: 1))
    as "147119: kind 217, 500 ms, once"
  assert spell_plan.proc_read(
      spell4_id: holder,
      effect: Spell4Effects(..row(id: 147_132), data_bits00: 218),
    )
    == Ok(ProcReading(trigger: LeftStealth, window_ms: 500, count: 1))
    as "147132: kind 218"
  assert spell_plan.proc_read(
      spell4_id: holder,
      effect: Spell4Effects(
        ..row(id: 159_136),
        data_bits00: 44,
        data_bits04: 1000,
      ),
    )
    == Ok(ProcReading(trigger: LeftCombat, window_ms: 1000, count: 1))
    as "159136: kind 44, 1000 ms, once"
  assert spell_plan.proc_read(
      spell4_id: holder,
      effect: Spell4Effects(
        ..row(id: 202_043),
        data_bits00: 0,
        data_bits03: 9,
        data_bits04: 1000,
      ),
    )
    == Ok(ProcReading(trigger: Died, window_ms: 1000, count: 1))
    as "202043: kind 0 with dataBits03 9 (the unit's bits 1 and 8 are read alike)"
  assert spell_plan.proc_read(
      spell4_id: holder,
      effect: Spell4Effects(..row(id: 99_001), data_bits05: 2),
    )
    == Ok(ProcReading(trigger: EnteredStealth, window_ms: 500, count: 2))
    as "dataBits05 is how many fires fit in the window (Spell4Effects.effectType.14.limits)"
}

pub fn a_proc_of_a_kind_the_server_does_not_read_is_skipped_not_failed_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.proc_read(
      spell4_id: 52_371,
      effect: Spell4Effects(
        ..row(id: 123_744),
        spell_id: 52_371,
        data_bits00: 12,
        data_bits01: 52_370,
        data_bits03: 4,
      ),
    )
    == Error(ProcKindNotRead(spell4_id: 52_371, effect_id: 123_744, kind: 12))
    as "123744: kind 12, 'lands a hit', which the next step reads, whatever its other columns hold"
  assert spell_plan.proc_read(
      spell4_id: 38_784,
      effect: Spell4Effects(
        ..row(id: 178_239),
        spell_id: 38_784,
        data_bits00: 16,
        data_bits01: 72_838,
      ),
    )
    == Error(ProcKindNotRead(spell4_id: 38_784, effect_id: 178_239, kind: 16))
    as "178239: kind 16, 'takes damage'"
}

fn refused(
  effect effect: Spell4Effects,
  column column: String,
  value value: Int,
) -> Nil {
  assert spell_plan.proc_read(spell4_id: holder, effect:)
    == Error(ProcNotRead(
      spell4_id: holder,
      effect_id: effect.id,
      column:,
      value:,
    ))
  Nil
}

pub fn a_proc_of_a_kind_read_with_a_column_the_plan_does_not_read_fails_the_load_naming_it_test() -> Nil {
  use <- owned_test.run(5000)
  let base = row(id: 99_100)
  refused(
    effect: Spell4Effects(..base, target_flags: 2),
    column: "targetFlags",
    value: 2,
  )
  // 791 is one of the 30 rows of the four kinds the client aims at another unit.
  refused(
    effect: Spell4Effects(..base, target_flags: 3),
    column: "targetFlags",
    value: 3,
  )
  // 1056964608 is 0.5 as 32 float bits: every row of the four kinds holds 1.0, and a
  // chance below 1 needs a roll the connection draws before the input.
  refused(
    effect: Spell4Effects(..base, data_bits02: 1_056_964_608),
    column: "dataBits02",
    value: 1_056_964_608,
  )
  refused(
    effect: Spell4Effects(..base, data_bits03: 4),
    column: "dataBits03",
    value: 4,
  )
  refused(
    effect: Spell4Effects(..base, data_bits03: 33),
    column: "dataBits03",
    value: 33,
  )
  // Rows 2313, 4435 and 37547 hold a dataBits04 of -1, which names no window.
  refused(
    effect: Spell4Effects(..base, data_bits04: -1),
    column: "dataBits04",
    value: -1,
  )
  refused(
    effect: Spell4Effects(..base, data_bits05: 0),
    column: "dataBits05",
    value: 0,
  )
  refused(
    effect: Spell4Effects(..base, data_bits06: 24_381),
    column: "dataBits06",
    value: 24_381,
  )
  refused(
    effect: Spell4Effects(..base, data_bits07: 2, data_bits08: 333),
    column: "dataBits07",
    value: 2,
  )
  refused(
    effect: Spell4Effects(..base, data_bits08: 333),
    column: "dataBits08",
    value: 333,
  )
  refused(
    effect: Spell4Effects(..base, data_bits09: 24_381),
    column: "dataBits09",
    value: 24_381,
  )
  refused(
    effect: Spell4Effects(..base, prerequisite_id_target_apply: 33_144),
    column: "prerequisiteIdTargetApply",
    value: 33_144,
  )
  refused(
    effect: Spell4Effects(..base, prerequisite_id_caster_persistence: 28_926),
    column: "prerequisiteIdCasterPersistence",
    value: 28_926,
  )
  refused(
    effect: Spell4Effects(..base, prerequisite_id_target_persistence: 28_926),
    column: "prerequisiteIdTargetPersistence",
    value: 28_926,
  )
  // Row 144096 holds a delayTime.
  refused(
    effect: Spell4Effects(..base, delay_time: 100),
    column: "delayTime",
    value: 100,
  )
}

pub fn a_proc_with_no_life_fails_the_load_and_a_timed_one_is_read_test() -> Nil {
  use <- owned_test.run(5000)
  // All 43 rows of the four kinds the plan reads hold flags 2 (until removed) and no
  // durationTime: a row with neither gives its holder's node no life, so it would never
  // be held (Spell4Effects.effectType.14.lifetime).
  refused(
    effect: Spell4Effects(..row(id: 99_102), flags: 0),
    column: "flags",
    value: 0,
  )
  assert spell_plan.proc_read(
      spell4_id: holder,
      effect: Spell4Effects(..row(id: 99_103), flags: 0, duration_time: 3000),
    )
    == Ok(ProcReading(trigger: EnteredStealth, window_ms: 500, count: 1))
    as "a durationTime gives the node its life"
}

pub fn a_spell_refuses_the_life_its_caster_condition_names_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = fn(death) {
    spell_plan.Spell(
      ..cast_support.child(spell4_id: 1, base: 1),
      caster_death: death,
      target_death: spell_plan.AliveOrDead,
    )
  }
  assert spell_plan.refused_life(
      spell: spell(spell_plan.CannotBeDead),
      dead: True,
    )
    == Some(spell_plan.RefusesDead)
    as "Spell4Conditions row 1 (mask 225) refuses a dead caster"
  assert spell_plan.refused_life(
      spell: spell(spell_plan.CannotBeDead),
      dead: False,
    )
    == None
  assert spell_plan.refused_life(
      spell: spell(spell_plan.MustBeDead),
      dead: False,
    )
    == Some(spell_plan.RefusesLiving)
  assert spell_plan.refused_life(
      spell: spell(spell_plan.MustBeDead),
      dead: True,
    )
    == None
  assert spell_plan.refused_life(
      spell: spell(spell_plan.AliveOrDead),
      dead: True,
    )
    == None
    as "row 4 (mask 0) refuses neither"
  assert spell_plan.refused_life(
      spell: spell(spell_plan.AliveOrDead),
      dead: False,
    )
    == None
}

pub fn the_first_column_the_plan_does_not_read_is_the_one_named_test() -> Nil {
  use <- owned_test.run(5000)
  refused(
    effect: Spell4Effects(
      ..row(id: 99_101),
      target_flags: 2,
      data_bits04: -1,
      delay_time: 100,
    ),
    column: "targetFlags",
    value: 2,
  )
}

pub fn the_effect_kind_reads_a_proc_row_aimed_at_the_caster_only_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.is_read(effect_type: 14)
    as "type 14 is handled, for its rows aimed at the caster"
  assert effect_kind.is_row_read(effect_type: 14, target_flags: 1)
  assert !effect_kind.is_row_read(effect_type: 14, target_flags: 2)
    as "a row aimed only at another unit is not read (Spell4Effects.targetFlags)"
  assert effect_kind.kind_of(effect_type: 14) == effect_kind.Proc
}
