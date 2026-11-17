//// The Proc effects of the plan (`genesis_prime/game/spell_plan` `ProcRow`, `Trigger`,
//// `proc_read`). Rows are read in memory, on a copy of the fixture's tables where a gate or
//// a spell must be looked up; the plan of the client's own tables is read where the client
//// is present. Expected values come from these places:
//// - `Spell4Effects.effectType.14.dataBits00.217_218` and `.0_44`: the Stalker's passive
////   45057 (Class 5, Spell4Base 29131) holds five Proc rows on its caster, in row order
////   (`table_rows -- Spell4Effects spellId=45057`, column orderIndex): 147119 (kind 217,
////   casts 60724), 147132 (218, 60769), 159136 (44, 63366), 202043 (0, 63366) and 211002
////   (218, 79932); each has targetFlags 1, chance 1.0 (dataBits02 1065353216), durationTime
////   0 with flags 2 (until removed), dataBits04 and dataBits05 of 500 and 1 for kinds 217
////   and 218 and 1000 and 1 for 44 and 0.
//// - `Spell4Effects.effectType.14.dataBits00`: kinds 12, 13, 145, 1, 20 and 147 are the
////   events of the holder's own casts and heals; kinds 16 'takes damage' (Stalker 38784's
////   178239, casts 72838), 146, 51 and 115 are the events of a creature's blow on the
////   holder.
//// - `Spell4Effects.effectType.14.dataBits02`: the chance as 32-bit float bits.
//// - `Spell4Effects.effectType.14.limits`: dataBits05 times in dataBits04 milliseconds; a
////   dataBits04 of -1 holds no window.
//// - `Spell4Effects.effectType.14.dataBits07`: 0 any spell, 1 one Spell4, 2 a group of
////   Spell4GroupList, named by dataBits08.
//// - `Spell4Effects.effectType.14.dataBits03`: bit 4 aims at the other unit.
//// - `Spell4Effects.effectType.14.prerequisites`: dataBits06 gates the event's unit and
////   dataBits09 the holder; a caster or target persistence or a target apply prerequisite
////   is left out.
//// - `Spell4Effects.effectType.14.lifetime`: a row with no life is left out.
//// - `Spell4Base.school`, `Spell.CodeEnumSchool`: 0 Spell, 1 Melee, 2 Bolt.
//// - Row 208200 (Stalker Proc Damage Tier 1, Spell4 79229): kind 12, targetFlags 1,
////   dataBits01 79221, chance 1.0, dataBits03 4, dataBits04 500, dataBits05 1, dataBits06
////   37038, dataBits07 2 and dataBits08 463; 178239 (Spell4 38784) kind 16; 123744
////   (Spell4 52371) kind 12 with caster persistence 28926.

import cast_support
import client_tables
import fixture_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type ProcReading, type Spell, Always, AtHolder, AtOtherUnit, Died,
  EnteredStealth, ForLife, InGroup, InWindow, Kills, LandsCritical,
  LandsCriticalHeal, LandsHeal, LandsHit, LandsMeleeHit, LeftCombat, LeftStealth,
  OneSpell, ProcIsLeftOut, ProcIsRead, ProcKindNotRead, ProcNotRead, ProcReading,
}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import owned_test
import planted_table.{Integer}
import spell_tables
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

/// What `row` reads as, with the trigger given: chance 1.0, once in 500 ms, any spell, at
/// the holder, no gates and no delay.
fn reading(trigger trigger: spell_plan.Trigger) -> ProcReading {
  ProcReading(
    trigger:,
    chance: 1.0,
    limit: InWindow(window_ms: 500, count: 1),
    filter: spell_plan.AnySpell,
    aim: AtHolder,
    event_gate: 0,
    holder_gate: 0,
    delay_ms: 0,
  )
}

/// The reading of a row, which must be read.
fn read_of(effect effect: Spell4Effects) -> ProcReading {
  let assert Ok(ProcIsRead(reading:)) =
    spell_plan.proc_read(spell4_id: holder, effect:)
    as "the plan reads the row"
  reading
}

/// The reading of a row on the fixture's tables: its plan row or what refuses it.
fn planned(
  effect effect: Spell4Effects,
) -> Result(spell_plan.RowReading, spell_plan.PlanError) {
  let tables = fixture_tables.shared()
  spell_plan.read_row(
    tables:,
    spell_groups: spell_plan.spell_groups(tables:),
    place: spell_tables.pressed,
    effect:,
  )
}

// ---- the rows of the plan, whole ----

pub fn the_stalkers_passive_holds_its_five_procs_on_the_caster_in_row_order_with_their_limits_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let procs =
    list.map(
      spell_plan.payloads(spell: passive(), as_kind: spell_plan.as_proc),
      fn(proc) {
        #(
          proc.effect_id.value,
          proc.trigger,
          proc.spell.spell4_id.value,
          proc.limit,
        )
      },
    )
  assert procs
    == [
      #(147_119, EnteredStealth, 60_724, InWindow(window_ms: 500, count: 1)),
      #(147_132, LeftStealth, 60_769, InWindow(window_ms: 500, count: 1)),
      #(159_136, LeftCombat, 63_366, InWindow(window_ms: 1000, count: 1)),
      #(202_043, Died, 63_366, InWindow(window_ms: 1000, count: 1)),
      #(211_002, LeftStealth, 79_932, InWindow(window_ms: 500, count: 1)),
    ]
    as "Spell4Effects 147119, 147132, 159136, 202043 and 211002 in orderIndex order: dataBits00 217, 218, 44, 0 and 218, dataBits01 the spell cast, dataBits04 the window and dataBits05 the count"
  assert list.all(
    spell_plan.payloads(spell: passive(), as_kind: spell_plan.as_proc),
    fn(proc) {
      proc.row == LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
      && proc.condition == Always
      && proc.phase_flags == -1
      && proc.chance == 1.0
      && proc.filter == spell_plan.AnySpell
      && proc.event_gate == None
      && proc.holder_gate == None
      && proc.delay_ms == 0
    },
  )
    as "durationTime 0 with flags 2 (until removed), no caster apply prerequisite, every phase, chance 1.0 and no filter, gate or delay on each of the five rows"
}

pub fn a_proc_of_kind_16_is_in_its_spells_proc_list_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let assert [takes_damage] =
    spell_plan.payloads(
      spell: spell_named(spell4_id: 38_784),
      as_kind: spell_plan.as_proc,
    )
    as "38784 'Stealth - On' holds the one Proc row 178239, kind 16"
  assert takes_damage.effect_id.value == 178_239
  assert takes_damage.trigger == spell_plan.TakesDamage
    as "dataBits00 16, a creature's blow lowers the holder's health"
  assert takes_damage.spell.spell4_id.value == 72_838
    as "dataBits01 72838, the spell the proc casts"
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
  assert list.length(spell_plan.payloads(
      spell: spell_named(spell4_id: 60_769),
      as_kind: spell_plan.as_remove,
    ))
    == 1
    as "60769's one row, 147136, is a SpellForceRemove (type 80)"
  assert list.map(
      spell_plan.payloads(
        spell: spell_named(spell4_id: 79_932),
        as_kind: spell_plan.as_modifier,
      ),
      fn(row) { row.effect_id.value },
    )
    |> list.sort(int.compare)
    == [210_998, 212_528, 212_529, 212_530]
    as "79932's four UnitPropertyModifier rows (Spell4.79932)"
  assert list.map(
      spell_plan.payloads(
        spell: spell_named(spell4_id: 63_366),
        as_kind: spell_plan.as_cooldown_modifier,
      ),
      fn(row) { row.effect_id.value },
    )
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
  assert read_of(effect: row(id: 147_119)) == reading(trigger: EnteredStealth)
    as "147119: kind 217, 500 ms, once"
  assert read_of(effect: Spell4Effects(..row(id: 147_132), data_bits00: 218))
    == reading(trigger: LeftStealth)
    as "147132: kind 218"
  assert read_of(
      effect: Spell4Effects(
        ..row(id: 159_136),
        data_bits00: 44,
        data_bits04: 1000,
      ),
    )
    == ProcReading(
      ..reading(trigger: LeftCombat),
      limit: InWindow(window_ms: 1000, count: 1),
    )
    as "159136: kind 44, 1000 ms, once"
  assert read_of(
      effect: Spell4Effects(
        ..row(id: 202_043),
        data_bits00: 0,
        data_bits03: 9,
        data_bits04: 1000,
      ),
    )
    == ProcReading(
      ..reading(trigger: Died),
      limit: InWindow(window_ms: 1000, count: 1),
    )
    as "202043: kind 0 with dataBits03 9 (the unit's bits 1 and 8 are read alike)"
  assert read_of(effect: Spell4Effects(..row(id: 99_001), data_bits05: 2))
    == ProcReading(
      ..reading(trigger: EnteredStealth),
      limit: InWindow(window_ms: 500, count: 2),
    )
    as "dataBits05 is how many fires fit in the window (Spell4Effects.effectType.14.limits)"
}

pub fn a_proc_of_each_own_kind_is_read_with_its_trigger_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(12, LandsHit),
      #(13, LandsMeleeHit),
      #(145, LandsCritical),
      #(1, Kills),
      #(20, LandsHeal),
      #(147, LandsCriticalHeal),
    ],
    fn(kind) {
      assert read_of(
          effect: Spell4Effects(..row(id: 99_010), data_bits00: kind.0),
        )
        == reading(trigger: kind.1)
        as {
          "Spell4Effects.effectType.14.dataBits00: kind "
          <> int.to_string(kind.0)
          <> " is the holder's own event"
        }
    },
  )
}

pub fn a_procs_chance_is_read_from_the_float_bits_of_data_bits02_test() -> Nil {
  use <- owned_test.run(5000)
  // 1036831949 is 0x3dcccccd, the 32-bit float 0.1 (Spell4Effects.effectType.14, dataBits02).
  let tenth =
    read_of(
      effect: Spell4Effects(..row(id: 99_011), data_bits02: 1_036_831_949),
    )
  assert tenth.chance >. 0.0999999 && tenth.chance <. 0.1000001
    as "1036831949 reads as 0.1"
  assert read_of(effect: row(id: 99_012)).chance == 1.0
    as "1065353216 reads as 1.0"
}

pub fn a_window_of_minus_1_reads_as_a_count_for_the_procs_life_test() -> Nil {
  use <- owned_test.run(5000)
  assert read_of(
      effect: Spell4Effects(..row(id: 99_013), data_bits04: -1, data_bits05: 60),
    ).limit
    == ForLife(count: 60)
    as "dataBits04 -1 holds no window (Spell4Effects.effectType.14.limits), so the count is for the proc's life"
  assert read_of(
      effect: Spell4Effects(
        ..row(id: 99_014),
        data_bits04: 3000,
        data_bits05: 1,
      ),
    ).limit
    == InWindow(window_ms: 3000, count: 1)
    as "dataBits04 3000 with dataBits05 1 is once in 3000 ms"
}

pub fn a_filter_of_2_is_a_group_and_1_is_one_spell_test() -> Nil {
  use <- owned_test.run(5000)
  assert read_of(
      effect: Spell4Effects(..row(id: 99_015), data_bits07: 2, data_bits08: 463),
    ).filter
    == InGroup(group_id: 463)
    as "dataBits07 2 names the Spell4GroupList group dataBits08, as in row 208200"
  assert read_of(
      effect: Spell4Effects(
        ..row(id: 99_016),
        data_bits07: 1,
        data_bits08: 79_220,
      ),
    ).filter
    == OneSpell(spell4_id: Spell4Id(79_220))
    as "dataBits07 1 names the Spell4 dataBits08"
  assert read_of(effect: row(id: 99_017)).filter == spell_plan.AnySpell
    as "dataBits07 0 is every spell"
}

pub fn bit_4_of_data_bits03_aims_at_the_other_unit_and_the_other_bits_at_the_holder_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([4, 12], fn(bits) {
    assert read_of(effect: Spell4Effects(..row(id: 99_018), data_bits03: bits)).aim
      == AtOtherUnit
      as "dataBits03 bit 4 is the other unit of the event (Spell4Effects.effectType.14.dataBits03)"
  })
  list.each([1, 2, 9, 18], fn(bits) {
    assert read_of(effect: Spell4Effects(..row(id: 99_019), data_bits03: bits)).aim
      == AtHolder
      as "a guess: bits 1, 2, 8 and 16 name the holder, as the passive's rows with 9 do"
  })
}

pub fn data_bits06_and_data_bits09_are_read_as_the_event_gate_and_the_holder_gate_test() -> Nil {
  use <- owned_test.run(5000)
  let gated =
    read_of(
      effect: Spell4Effects(
        ..row(id: 99_020),
        data_bits06: 37_038,
        data_bits09: 28_926,
      ),
    )
  assert gated.event_gate == 37_038
    as "dataBits06 is the Prerequisite on the event's unit, as in row 208200"
  assert gated.holder_gate == 28_926
    as "dataBits09 is the Prerequisite on the holder"
  assert read_of(effect: row(id: 99_021)).event_gate == 0 as "0 is no gate"
}

pub fn a_procs_delay_time_is_read_as_its_delay_test() -> Nil {
  use <- owned_test.run(5000)
  assert read_of(effect: Spell4Effects(..row(id: 99_022), delay_time: 1000)).delay_ms
    == 1000
    as "Spell4Effects.delayTime: the wait between the event and the cast"
  assert read_of(effect: row(id: 99_023)).delay_ms == 0
}

pub fn a_spells_school_is_read_from_its_spell4base_row_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 32893 (Telekinetic Strike) is a spell of Spell4Base 19102, school 0.
  let school_with = fn(school) {
    use tables <- fixture_tables.changed(table: "Spell4Base", id: 19_102, with: [
      #("school", Integer(school)),
    ])
    let assert Ok(spell) =
      spell_plan.spell_alone(
        tables:,
        sources: spell_plan.sources_of(tables:),
        spell4_id: 32_893,
        chain: [],
      )
      as "Telekinetic Strike plans"
    spell.school
  }
  assert school_with(0) == 0
    as "Spell4Base 19102 school 0 (Spell.CodeEnumSchool 0)"
  assert school_with(1) == 1 as "school 1 is Melee"
  assert school_with(2) == 2 as "school 2 is Bolt"
}

// ---- rows the plan leaves out or refuses ----

fn left_out(
  effect effect: Spell4Effects,
  why why: spell_plan.LeftOutReason,
) -> Nil {
  assert spell_plan.proc_read(spell4_id: holder, effect:)
    == Ok(ProcIsLeftOut(why:))
  assert planned(effect:) == Ok(spell_plan.LeftOut(why:))
    as "the load goes on, with the row in no list of its spell"
  Nil
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

pub fn a_proc_of_a_kind_the_server_does_not_read_is_skipped_not_failed_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_plan.proc_read(
      spell4_id: 38_784,
      effect: Spell4Effects(
        ..row(id: 178_239),
        spell_id: 38_784,
        data_bits00: 27,
        data_bits01: 72_838,
      ),
    )
    == Error(ProcKindNotRead(spell4_id: 38_784, effect_id: 178_239, kind: 27))
    as "kind 27 is no kind the server reads"
  assert planned(effect: Spell4Effects(..row(id: 178_239), data_bits00: 27))
    == Ok(spell_plan.LeftOut(why: spell_plan.ProcOfAnotherKind(kind: 27)))
    as "the plan leaves the row out, naming the kind"
}

pub fn a_proc_held_by_a_unit_other_than_its_caster_is_left_out_not_a_load_failure_test() -> Nil {
  use <- owned_test.run(60_000)
  left_out(
    effect: Spell4Effects(..row(id: 99_030), target_flags: 2),
    why: spell_plan.ProcHeldByAnotherUnit(target_flags: 2),
  )
  left_out(
    effect: Spell4Effects(..row(id: 99_031), target_flags: 3),
    why: spell_plan.ProcHeldByAnotherUnit(target_flags: 3),
  )
}

pub fn a_proc_behind_a_persistence_prerequisite_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // Row 123744's shape (Spell4 52371, kind 12, casts 52370, caster persistence 28926).
  left_out(
    effect: Spell4Effects(
      ..row(id: 123_744),
      spell_id: 52_371,
      data_bits00: 12,
      data_bits01: 52_370,
      data_bits03: 4,
      prerequisite_id_caster_persistence: 28_926,
    ),
    why: spell_plan.ProcBehindPersistence,
  )
  left_out(
    effect: Spell4Effects(
      ..row(id: 99_032),
      prerequisite_id_target_persistence: 28_926,
    ),
    why: spell_plan.ProcBehindPersistence,
  )
}

pub fn a_proc_behind_a_target_apply_prerequisite_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  left_out(
    effect: Spell4Effects(
      ..row(id: 99_033),
      prerequisite_id_target_apply: 33_144,
    ),
    why: spell_plan.ProcBehindTargetApply,
  )
}

pub fn a_proc_naming_a_group_with_no_filter_kind_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  left_out(
    effect: Spell4Effects(..row(id: 99_034), data_bits07: 0, data_bits08: 333),
    why: spell_plan.ProcGroupWithoutFilter,
  )
}

pub fn a_proc_with_data_bits03_of_32_or_above_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  left_out(
    effect: Spell4Effects(..row(id: 99_035), data_bits03: 33),
    why: spell_plan.ProcAimNotRead(data_bits03: 33),
  )
  left_out(
    effect: Spell4Effects(..row(id: 99_036), data_bits03: 32),
    why: spell_plan.ProcAimNotRead(data_bits03: 32),
  )
}

pub fn a_proc_with_no_life_is_left_out_and_a_timed_one_is_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // All rows of the kinds the plan reads hold flags 2 (until removed) or a durationTime:
  // a row with neither gives its holder's node no life, so it would never be held
  // (Spell4Effects.effectType.14.lifetime).
  left_out(
    effect: Spell4Effects(..row(id: 99_102), flags: 0),
    why: spell_plan.ProcWithoutLife,
  )
  assert read_of(
      effect: Spell4Effects(..row(id: 99_103), flags: 0, duration_time: 3000),
    )
    == reading(trigger: EnteredStealth)
    as "a durationTime gives the node its life"
}

pub fn a_window_of_0_or_a_count_of_0_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  // Rows hold -1 or a window above 0, and a count above 0: any other value is outside
  // every known reading (Spell4Effects.effectType.14.limits).
  refused(
    effect: Spell4Effects(..row(id: 99_040), data_bits04: 0),
    column: "dataBits04",
    value: 0,
  )
  refused(
    effect: Spell4Effects(..row(id: 99_041), data_bits04: -2),
    column: "dataBits04",
    value: -2,
  )
  refused(
    effect: Spell4Effects(..row(id: 99_042), data_bits05: 0),
    column: "dataBits05",
    value: 0,
  )
}

pub fn a_filter_kind_other_than_0_1_or_2_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  refused(
    effect: Spell4Effects(..row(id: 99_043), data_bits07: 3, data_bits08: 463),
    column: "dataBits07",
    value: 3,
  )
}

pub fn a_chance_of_0_or_above_1_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  refused(
    effect: Spell4Effects(..row(id: 99_044), data_bits02: 0),
    column: "dataBits02",
    value: 0,
  )
  // 1073741824 is 2.0 as 32 float bits.
  refused(
    effect: Spell4Effects(..row(id: 99_045), data_bits02: 1_073_741_824),
    column: "dataBits02",
    value: 1_073_741_824,
  )
}

pub fn a_one_spell_filter_naming_a_missing_spell4_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert planned(
      effect: Spell4Effects(
        ..row(id: 99_046),
        data_bits07: 1,
        data_bits08: 999_999_999,
      ),
    )
    == Error(spell_plan.NoRow(table: "Spell4", id: 999_999_999))
    as "a filter naming a Spell4 the tables lack fails the load, as a gate naming no row does"
}

pub fn a_proc_casting_a_spell4_the_tables_lack_is_left_out_test() -> Nil {
  use <- owned_test.run(60_000)
  // The client never reads a Proc row and its Spell4 table has no row 22930, which 54 of
  // the 621 Proc rows of kind 16 (effectType 14, dataBits00 16) name in dataBits01 (counted
  // over the extracted Spell4Effects and Spell4 tables; Spell4Effects 44636 of Spell4 27029,
  // for one): the holder spell casts all the same.
  assert planned(effect: Spell4Effects(..row(id: 99_049), data_bits01: 22_930))
    == Ok(
      spell_plan.LeftOut(why: spell_plan.ProcCastsNoSpell(spell4_id: 22_930)),
    )
    as "a spell with no row leaves the row out and the load goes on"
  assert planned(effect: Spell4Effects(..row(id: 99_050), data_bits01: 0))
    == Ok(spell_plan.LeftOut(why: spell_plan.ProcCastsNoSpell(spell4_id: 0)))
    as "a spell 0 is no row too"
}

pub fn a_proc_gate_naming_a_missing_prerequisite_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  assert planned(
      effect: Spell4Effects(..row(id: 99_047), data_bits06: 999_999_999),
    )
    == Error(spell_plan.NoRow(table: "Prerequisite", id: 999_999_999))
    as "dataBits06 naming a Prerequisite the tables lack fails the load"
  assert planned(
      effect: Spell4Effects(..row(id: 99_048), data_bits09: 999_999_999),
    )
    == Error(spell_plan.NoRow(table: "Prerequisite", id: 999_999_999))
    as "dataBits09 too"
}

pub fn the_first_column_the_plan_does_not_read_is_the_one_named_test() -> Nil {
  use <- owned_test.run(5000)
  refused(
    effect: Spell4Effects(
      ..row(id: 99_101),
      data_bits04: 0,
      data_bits07: 3,
      delay_time: -1,
    ),
    column: "dataBits04",
    value: 0,
  )
}

// ---- the client's own tables ----

pub fn the_starting_abilities_plan_with_178239_and_208200_and_leave_out_123744_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let assert [stalker_damage] =
    spell_plan.payloads(
      spell: spell_named(spell4_id: 79_229),
      as_kind: spell_plan.as_proc,
    )
    as "Spell4 79229 'Stalker Proc Damage Tier 1' holds the one Proc row 208200"
  assert stalker_damage.effect_id.value == 208_200
  assert stalker_damage.trigger == LandsHit as "dataBits00 12"
  assert stalker_damage.spell.spell4_id.value == 79_221
    as "dataBits01 79221, the damage the proc casts"
  assert stalker_damage.aim == AtOtherUnit as "dataBits03 4"
  assert stalker_damage.filter == InGroup(group_id: 463)
    as "dataBits07 2, dataBits08 463"
  assert stalker_damage.limit == InWindow(window_ms: 500, count: 1)
  assert stalker_damage.chance == 1.0
  let assert Some(gate) = stalker_damage.event_gate
    as "dataBits06 37038 is a gate on the struck creature"
  assert prerequisite.id(gate).value == 37_038
  assert stalker_damage.holder_gate == None
  assert spell_plan.payloads(
      spell: spell_named(spell4_id: 52_371),
      as_kind: spell_plan.as_proc,
    )
    == []
    as "52371's 123744 is behind caster persistence 28926: it is left out and the load passes"
  let tables = client_tables.shared()
  let assert Ok(stealth_on) =
    list.find(spell4_effects.all(tables), fn(effect) { effect.id == 178_239 })
    as "the client's Spell4Effects holds 178239"
  assert stealth_on.spell_id == 38_784 && stealth_on.data_bits00 == 16
    as "Spell4 38784 'Stealth - On' holds 178239, kind 16 (takes damage)"
  let assert Ok(spell_plan.Applied(spell_plan.ReadProc(reading:, ..))) =
    spell_plan.read_row(
      tables:,
      spell_groups: spell_plan.spell_groups(tables:),
      place: spell_tables.pressed,
      effect: stealth_on,
    )
    as "the plan reads 178239 as a Proc"
  assert reading.trigger == spell_plan.TakesDamage
    as "kind 16 is a creature's blow taken"
  assert reading.limit == InWindow(window_ms: 1000, count: 1)
    as "dataBits04 1000 and dataBits05 1"
}

pub fn the_proc_rows_read_count_1643_of_the_ten_kinds_and_51_of_the_old_kinds_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let procs =
    spell4_effects.all(client_tables.shared())
    |> list.filter(fn(effect) { effect.effect_type == 14 })
  let reads = fn(kinds: List(Int), as_kind: fn(Int) -> Int) {
    list.filter(procs, fn(effect) { list.contains(kinds, effect.data_bits00) })
    |> list.map(fn(effect) {
      spell_plan.proc_read(
        spell4_id: effect.spell_id,
        effect: Spell4Effects(
          ..effect,
          data_bits00: as_kind(effect.data_bits00),
        ),
      )
    })
  }
  let read_count = fn(
    results: List(Result(spell_plan.ProcRead, spell_plan.PlanError)),
  ) {
    list.count(results, fn(result) {
      case result {
        Ok(ProcIsRead(..)) -> True
        Ok(ProcIsLeftOut(..)) | Error(..) -> False
      }
    })
  }
  let own = reads([12, 13, 145, 1, 20, 147], fn(kind) { kind })
  assert list.all(own, fn(result) {
    case result {
      Error(..) -> False
      Ok(..) -> True
    }
  })
    as "no Proc row of a kind read holds a value outside every reading: the load never fails on one"
  let old = reads([217, 218, 44, 0], fn(kind) { kind })
  let blows_taken = reads([16, 146, 51, 115], fn(kind) { kind })
  assert read_count(old) == 51
    as "the four old kinds hold 83 rows, 51 of them read (a direct read of Spell4Effects)"
  assert read_count(own) + read_count(blows_taken) == 1643
    as "the ten kinds hold 1975 rows, 1643 of them read: 332 are left out"
  assert read_count(own) == 1083
    as "of those, the six kinds of the holder's own casts and heals"
  assert list.all(blows_taken, fn(result) {
    case result {
      Error(..) -> False
      Ok(..) -> True
    }
  })
    as "no row of the four kinds of a blow taken holds a value outside every reading"
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

// ---- the fairly-sure kinds, each read or refused with its issue ----

/// The fairly-sure kinds the server reads, each with its trigger
/// (`Spell4Effects.effectType.14.dataBits00.fairly_sure`).
fn fairly_sure_read() -> List(#(Int, spell_plan.Trigger)) {
  [
    #(0, Died),
    #(44, LeftCombat),
    #(218, LeftStealth),
    #(10, spell_plan.UsesAbility),
    #(103, spell_plan.SpendsResource),
    #(21, spell_plan.ReceivesHeal),
    #(52, spell_plan.FoeDeflects),
    #(49, spell_plan.LandsFinisherCritical),
    #(11, spell_plan.StartsMoving),
    #(87, spell_plan.ResourceCrosses),
    #(105, spell_plan.SuitPowerDrops),
    #(182, spell_plan.LandsTaunt),
  ]
}

/// The fairly-sure kinds the server refuses, with the open issue each waits on (the
/// approved test list of issue 792).
fn fairly_sure_refused() -> List(#(Int, Int)) {
  list.flatten([
    list.map([57, 40, 117, 154], fn(kind) { #(kind, 869) }),
    list.map([23, 50, 114, 131, 234, 249], fn(kind) { #(kind, 870) }),
    list.map([124, 102, 112], fn(kind) { #(kind, 871) }),
    [#(152, 872)],
    list.map([155, 197, 159, 41, 153, 236], fn(kind) { #(kind, 801) }),
    [#(46, 803), #(2, 56), #(148, 830)],
    list.map([251, 253], fn(kind) { #(kind, 336) }),
  ])
}

pub fn proc_every_kind_read_or_refused_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each(fairly_sure_read(), fn(kind) {
    assert read_of(
        effect: Spell4Effects(..row(id: 99_020), data_bits00: kind.0),
      )
      == reading(trigger: kind.1)
      as {
        "Spell4Effects.effectType.14.dataBits00.fairly_sure: kind "
        <> int.to_string(kind.0)
        <> " is read"
      }
  })
  list.each(fairly_sure_refused(), fn(kind) {
    let effect = Spell4Effects(..row(id: 99_021), data_bits00: kind.0)
    assert spell_plan.proc_read(spell4_id: holder, effect:)
      == Ok(
        ProcIsLeftOut(why: spell_plan.ProcKindWaits(kind: kind.0, issue: kind.1)),
      )
      as {
        "kind "
        <> int.to_string(kind.0)
        <> " is left out with a named reason, never as another kind"
      }
  })
  assert list.length(fairly_sure_read()) + list.length(fairly_sure_refused())
    == 37
    as "the record names 37 fairly-sure kinds"
  use <- unitest.guard(client_tables.present())
  let named =
    list.append(
      list.map(fairly_sure_read(), fn(kind) { kind.0 }),
      list.map(fairly_sure_refused(), fn(kind) { kind.0 }),
    )
  let procs =
    spell4_effects.all(client_tables.shared())
    |> list.filter(fn(effect) { list.contains(named, effect.data_bits00) })
  assert procs != [] as "the tables hold Proc rows of the 37 kinds"
  list.each(procs, fn(effect) {
    case spell_plan.proc_read(spell4_id: effect.spell_id, effect:) {
      Error(ProcKindNotRead(..)) ->
        panic as "a row of a fairly-sure kind falls to ProcKindNotRead"
      Error(..) | Ok(..) -> Nil
    }
  })
}

pub fn proc_refused_kind_names_issue_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(fairly_sure_refused(), fn(kind) {
    assert planned(
        effect: Spell4Effects(..row(id: 99_022), data_bits00: kind.0),
      )
      == Ok(
        spell_plan.LeftOut(why: spell_plan.ProcKindWaits(
          kind: kind.0,
          issue: kind.1,
        )),
      )
      as {
        "the plan leaves kind "
        <> int.to_string(kind.0)
        <> " out, naming issue "
        <> int.to_string(kind.1)
      }
  })
  assert planned(effect: Spell4Effects(..row(id: 99_023), data_bits00: 27))
    == Ok(spell_plan.LeftOut(why: spell_plan.ProcOfAnotherKind(kind: 27)))
    as "a kind outside the 37 still reads as another kind"
}
