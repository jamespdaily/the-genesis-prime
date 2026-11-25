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
//// - `Spell4Effects.effectType.14.dataBits07`: the id space of dataBits08, 0 a Spell4Base,
////   1 a Spell4, 2 a group of Spell4GroupList; a dataBits08 of 0 is no filter in all three.
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
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/effect_kind
import genesis_prime/game/effect_row_read
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite
import genesis_prime/game/proc as event_proc
import genesis_prime/game/spell_plan.{
  type ProcReading, type Spell, Always, AtHolder, AtOtherUnit, Died,
  EnteredStealth, ForLife, InGroup, InWindow, Kills, LandsCritical,
  LandsCriticalHeal, LandsHeal, LandsHit, LandsMeleeHit, LeftCombat, LeftStealth,
  OfBase, OneSpell, ProcIsLeftOut, ProcIsRead, ProcKindNotRead, ProcNotRead,
  ProcReading,
}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects.{type Spell4Effects, Spell4Effects}
import genesis_prime/table/spell4_group_list
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
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

/// A Proc row of this kind and targetFlags that lasts 12 000 ms, as Healing Salve's 86457
/// does (flags 4, kind 16): the shape of a row an ally holds, with no gate and no delay.
fn timed(id id: Int, flags flags: Int, kind kind: Int) -> Spell4Effects {
  Spell4Effects(
    ..row(id:),
    target_flags: flags,
    data_bits00: kind,
    duration_time: 12_000,
    flags: 0,
  )
}

/// What `row` reads as, with the trigger given: chance 1.0, once in 500 ms, any spell, at
/// the holder, no gates and no delay.
fn reading(trigger trigger: spell_plan.Trigger) -> ProcReading {
  ProcReading(
    holder: spell_plan.HeldByCaster,
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
    sources: spell_plan.sources_of(tables:),
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
      spell: cast_support.real_spell(spell4_id: 38_784),
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
      spell: cast_support.real_spell(spell4_id: 60_769),
      as_kind: spell_plan.as_remove,
    ))
    == 1
    as "60769's one row, 147136, is a SpellForceRemove (type 80)"
  assert list.map(
      spell_plan.payloads(
        spell: cast_support.real_spell(spell4_id: 79_932),
        as_kind: spell_plan.as_modifier,
      ),
      fn(row) { row.effect_id.value },
    )
    |> list.sort(int.compare)
    == [210_998, 212_528, 212_529, 212_530]
    as "79932's four UnitPropertyModifier rows (Spell4.79932)"
  assert list.map(
      spell_plan.payloads(
        spell: cast_support.real_spell(spell4_id: 63_366),
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
  use <- owned_test.run(10_000)
  list.each(kinds_read(), fn(kind) {
    assert read_of(
        effect: Spell4Effects(..row(id: 99_010), data_bits00: kind.0),
      )
      == reading(trigger: kind.1)
      as {
        "Spell4Effects.effectType.14.dataBits00"
        <> kind.2
        <> ": kind "
        <> int.to_string(kind.0)
        <> " is read with its trigger"
      }
  })
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

pub fn a_filter_reads_data_bits08_in_the_id_space_data_bits07_names_and_0_as_no_filter_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4Effects.effectType.14.dataBits07: 0 a Spell4Base, 1 a Spell4, 2 a spell group;
  // a dataBits08 of 0 is no filter in all three.
  let cases = [
    #(0, 0, spell_plan.AnySpell, "kind 0 with no id is every spell"),
    #(
      1,
      0,
      spell_plan.AnySpell,
      "kind 1 with no id is every spell, as Spell4Effects 189684 of the Q9396 Probebot",
    ),
    #(
      2,
      0,
      spell_plan.AnySpell,
      "kind 2 with no id is every spell, as Thunderfury's 108540",
    ),
    #(
      0,
      27_740,
      OfBase(spell4_base_id: Spell4BaseId(27_740)),
      "kind 0 with an id names a Spell4Base, as Arcane Missiles T4 Proc 200794 names 27740",
    ),
    #(
      1,
      79_220,
      OneSpell(spell4_id: Spell4Id(79_220)),
      "kind 1 with an id names the Spell4 dataBits08",
    ),
    #(
      2,
      463,
      InGroup(group_id: 463),
      "kind 2 with an id names the Spell4GroupList group dataBits08, as in row 208200",
    ),
  ]
  list.each(cases, fn(found) {
    let #(kind, id, expected, reason) = found
    assert read_of(
        effect: Spell4Effects(
          ..row(id: 99_015),
          data_bits07: kind,
          data_bits08: id,
        ),
      ).filter
      == expected
      as reason
  })
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
        data_bits00: 3,
        data_bits01: 72_838,
      ),
    )
    == Error(ProcKindNotRead(spell4_id: 38_784, effect_id: 178_239, kind: 3))
    as "kind 3 has no reading (Spell4Effects.effectType.14.dataBits00.guess)"
  assert planned(effect: Spell4Effects(..row(id: 178_239), data_bits00: 3))
    == Ok(spell_plan.LeftOut(why: spell_plan.ProcOfAnotherKind(kind: 3)))
    as "the plan leaves the row out, naming the kind"
}

pub fn a_proc_held_by_a_unit_other_than_its_caster_is_left_out_not_a_load_failure_test() -> Nil {
  use <- owned_test.run(60_000)
  // A row the ally's connection tells the caster the event of reads with the unit that
  // holds it: targetFlags 2 the primary target, 4 the area's allies
  // (`Spell4Effects.targetFlags`; text 315682 "yourself and N allies").
  list.each([16, 146, 51, 115], fn(kind) {
    assert read_of(effect: timed(id: 99_030, flags: 2, kind:)).holder
      == spell_plan.HeldByPrimaryTarget
      as "flags 2 is held by the primary target"
    assert read_of(effect: timed(id: 99_031, flags: 4, kind:)).holder
      == spell_plan.HeldByAreaAllies
      as "flags 4 is held by the area's allies"
  })
  assert read_of(effect: Spell4Effects(..row(id: 99_032), flags: 2)).holder
    == spell_plan.HeldByCaster
    as "flags 1 is the caster's"
  // The event of any other kind is not told by an ally, so a row read would never fire:
  // the plan leaves it out in the place that gives the row an ally.
  list.each([12, 21, 0, 10, 20], fn(kind) {
    list.each(
      [
        #(2, spell_tables.pressed),
        #(4, spell_tables.pressed_finding_allies),
      ],
      fn(found) {
        let #(flags, place) = found
        assert spell_tables.read_row(
            effect: timed(id: 99_033, flags:, kind:),
            place:,
          )
          == Ok(spell_plan.LeftOut(why: spell_plan.ProcHeldEventNotTold(kind:)))
          as "an ally-held row of a kind no ally tells is left out naming it"
      },
    )
  })
  // Flags that name several units at once stay with the unit that holds them.
  list.each([3, 5, 6, 7], fn(flags) {
    left_out(
      effect: timed(id: 99_034, flags:, kind: 16),
      why: spell_plan.ProcHeldByAnotherUnit(target_flags: flags),
    )
  })
  // A kind the texts name and the server does not raise is told so first.
  assert spell_plan.proc_read(
      spell4_id: holder,
      effect: timed(id: 99_035, flags: 2, kind: 23),
    )
    == Ok(
      ProcIsLeftOut(why: spell_plan.ProcKindWaits(
        kind: 23,
        event: "the holder taking a blow: direct, magic or critical damage, damage to its shield, an absorb destroyed, or a glance",
      )),
    )
}

/// What the plan made of a Proc row in a place: the unit that holds it when read, or the
/// reason it is left out.
type Outcome {
  ReadFor(holder: spell_plan.ProcHolder)
  LeftOutFor(why: spell_plan.LeftOutReason)
}

fn outcome_of(
  reading reading: Result(spell_plan.RowReading, spell_plan.PlanError),
) -> Outcome {
  case reading {
    Ok(spell_plan.Applied(spell_plan.ReadProc(reading:, ..))) ->
      ReadFor(holder: reading.holder)
    Ok(spell_plan.LeftOut(why:)) -> LeftOutFor(why:)
    Error(error) ->
      panic as {
        "a Proc row is read or left out, never a load failure: "
        <> spell_plan.describe(error:)
      }
    Ok(..) -> panic as "a Proc row is read as a Proc row or left out"
  }
}

pub fn a_proc_row_is_read_for_the_unit_its_place_gives_it_and_left_out_where_it_gives_none_or_the_row_has_a_gate_or_a_delay_test() -> Nil {
  use <- owned_test.run(60_000)
  // Healing Salve's 86457 (Spell4 39386: targetFlags 4, kind 16, 12 000 ms, no gate, no
  // delay) and its caster's own row 86458 (flags 1) are the client's rows; the cases an
  // edit of 86457 makes are shapes no client row of a spell in the fixture holds:
  // Analyze Weakness 231582 (a struck unit's child, flags 2), the rows with a gate (dataBits06
  // or dataBits09), a delay or flags bit 2 that 99 client rows of kinds 16, 146, 51 and 115 hold.
  let tables = fixture_tables.shared()
  let salve = spell_tables.effect_row_in(tables:, id: 86_457)
  let own = spell_tables.effect_row_in(tables:, id: 86_458)
  let held_by_primary_target = Spell4Effects(..salve, target_flags: 2)
  let until_removed = Spell4Effects(..salve, flags: 2, duration_time: 0)
  let struck_child =
    spell_tables.started_on_each_struck(spell4_id: 39_386, proxy_effect_id: 1)
  let cases = [
    #(
      "flags 4 in a place that finds allies is held by the area's allies",
      salve,
      spell_tables.pressed_finding_allies,
      ReadFor(holder: spell_plan.HeldByAreaAllies),
    ),
    #(
      "flags 4 in a place that hits foes finds no ally: a creature holds it",
      salve,
      spell_tables.pressed_hitting_foes,
      LeftOutFor(why: spell_plan.ProcHeldByAnotherUnit(target_flags: 4)),
    ),
    #(
      "flags 4 in a place that finds no ally holds nobody",
      salve,
      spell_tables.pressed,
      LeftOutFor(why: spell_plan.ProcHeldByAnotherUnit(target_flags: 4)),
    ),
    #(
      "flags 2 in a spell no Proxy starts on a struck unit is held by the primary target",
      held_by_primary_target,
      spell_tables.pressed,
      ReadFor(holder: spell_plan.HeldByPrimaryTarget),
    ),
    #(
      "flags 2 in a struck unit's child is a creature's",
      held_by_primary_target,
      struck_child,
      LeftOutFor(why: spell_plan.ProcHeldByAnotherUnit(target_flags: 2)),
    ),
    #(
      "flags 2 in a place that hits foes is a creature's",
      held_by_primary_target,
      spell_tables.pressed_hitting_foes,
      LeftOutFor(why: spell_plan.ProcHeldByAnotherUnit(target_flags: 2)),
    ),
    #(
      "a holder gate (dataBits09) on an ally's row is left out",
      Spell4Effects(..salve, data_bits09: 5),
      spell_tables.pressed_finding_allies,
      LeftOutFor(why: spell_plan.ProcAllyGateNotRead),
    ),
    #(
      "an event gate (dataBits06) on an ally's row is left out",
      Spell4Effects(..salve, data_bits06: 5),
      spell_tables.pressed_finding_allies,
      LeftOutFor(why: spell_plan.ProcAllyGateNotRead),
    ),
    #(
      "a delay on an ally's row is left out",
      Spell4Effects(..salve, delay_time: 500),
      spell_tables.pressed_finding_allies,
      LeftOutFor(why: spell_plan.ProcAllyDelayNotRead),
    ),
    #(
      "dataBits07 1 with dataBits08 0 on an ally's row is no filter, so the row is read",
      Spell4Effects(..salve, data_bits07: 1, data_bits08: 0),
      spell_tables.pressed_finding_allies,
      ReadFor(holder: spell_plan.HeldByAreaAllies),
    ),
    #(
      "the same filter on a row the primary target holds is read too",
      Spell4Effects(..held_by_primary_target, data_bits07: 1, data_bits08: 0),
      spell_tables.pressed,
      ReadFor(holder: spell_plan.HeldByPrimaryTarget),
    ),
    #(
      "an ally's row that lasts until removed is left out in a spell that is no aura",
      until_removed,
      spell_tables.pressed_finding_allies,
      LeftOutFor(why: spell_plan.ProcAllyUntilRemoved),
    ),
    #(
      "an ally's row that lasts until removed is read in an aura that ends",
      until_removed,
      spell_tables.pressed_finding_allies_as_aura,
      ReadFor(holder: spell_plan.HeldByAreaAllies),
    ),
    #(
      "an ally's row of a kind no ally tells (12) is left out naming it",
      Spell4Effects(..salve, data_bits00: 12),
      spell_tables.pressed_finding_allies,
      LeftOutFor(why: spell_plan.ProcHeldEventNotTold(kind: 12)),
    ),
    #(
      "the caster's own row (flags 1) is read as before, in any place",
      own,
      spell_tables.pressed_finding_allies,
      ReadFor(holder: spell_plan.HeldByCaster),
    ),
    #(
      "the caster's own row that lasts until removed is read in a spell that is no aura",
      Spell4Effects(..own, flags: 2, duration_time: 0),
      spell_tables.pressed,
      ReadFor(holder: spell_plan.HeldByCaster),
    ),
  ]
  list.each(cases, fn(found) {
    let #(reason, effect, place, expected) = found
    assert outcome_of(reading: spell_tables.read_row(effect:, place:))
      == expected
      as reason
  })
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

pub fn a_filter_naming_an_id_its_table_lacks_leaves_the_row_out_whoever_holds_it_test() -> Nil {
  use <- owned_test.run(10_000)
  // The client never reads a Proc row, so its tables keep stale ids (Spell4Effects 75724
  // names Spell4 36366, 217742 names Spell4Base 25688, neither of which has a row): no
  // event's spell is one, so the row could never fire, and the holder spell plans all the same.
  let tables = fixture_tables.shared()
  let salve = spell_tables.effect_row_in(tables:, id: 86_457)
  let missing = 999_999_999
  let cases = [
    #(
      "a caster's row naming a Spell4 the table lacks is left out",
      Spell4Effects(..row(id: 99_046), data_bits07: 1, data_bits08: missing),
      spell_tables.pressed,
      LeftOutFor(why: spell_plan.ProcFilterNamesNoSpell4(spell4_id: missing)),
    ),
    #(
      "a caster's row naming a Spell4Base the table lacks is left out",
      Spell4Effects(..row(id: 99_046), data_bits07: 0, data_bits08: missing),
      spell_tables.pressed,
      LeftOutFor(why: spell_plan.ProcFilterNamesNoSpell4Base(
        spell4_base_id: missing,
      )),
    ),
    #(
      "an area ally's row naming a Spell4 the table lacks is left out",
      Spell4Effects(..salve, data_bits07: 1, data_bits08: missing),
      spell_tables.pressed_finding_allies,
      LeftOutFor(why: spell_plan.ProcFilterNamesNoSpell4(spell4_id: missing)),
    ),
    #(
      "the primary target's row naming a Spell4Base the table lacks is left out",
      Spell4Effects(
        ..salve,
        target_flags: 2,
        data_bits07: 0,
        data_bits08: missing,
      ),
      spell_tables.pressed,
      LeftOutFor(why: spell_plan.ProcFilterNamesNoSpell4Base(
        spell4_base_id: missing,
      )),
    ),
    #(
      "a caster's row naming a group no Spell4GroupList lists is left out",
      Spell4Effects(..row(id: 99_046), data_bits07: 2, data_bits08: missing),
      spell_tables.pressed,
      LeftOutFor(why: spell_plan.ProcFilterNamesNoGroup(group_id: missing)),
    ),
    #(
      "the primary target's row naming a group no Spell4GroupList lists is left out",
      Spell4Effects(
        ..salve,
        target_flags: 2,
        data_bits07: 2,
        data_bits08: missing,
      ),
      spell_tables.pressed,
      LeftOutFor(why: spell_plan.ProcFilterNamesNoGroup(group_id: missing)),
    ),
    #(
      "a group a Spell4GroupList lists (463, the Stalker's damage group) is read",
      Spell4Effects(..row(id: 99_046), data_bits07: 2, data_bits08: 463),
      spell_tables.pressed,
      ReadFor(holder: spell_plan.HeldByCaster),
    ),
    #(
      "a Spell4 the table holds (Telekinetic Strike) is read",
      Spell4Effects(..row(id: 99_046), data_bits07: 1, data_bits08: 32_893),
      spell_tables.pressed,
      ReadFor(holder: spell_plan.HeldByCaster),
    ),
    #(
      "a Spell4Base the table holds (19102, Telekinetic Strike's) is read",
      Spell4Effects(..row(id: 99_046), data_bits07: 0, data_bits08: 19_102),
      spell_tables.pressed,
      ReadFor(holder: spell_plan.HeldByCaster),
    ),
    #(
      "an id of 0 names no table row and reads as no filter",
      Spell4Effects(..row(id: 99_046), data_bits07: 1, data_bits08: 0),
      spell_tables.pressed,
      ReadFor(holder: spell_plan.HeldByCaster),
    ),
  ]
  list.each(cases, fn(found) {
    let #(reason, effect, place, expected) = found
    assert outcome_of(reading: spell_tables.read_row(effect:, place:))
      == expected
      as reason
  })
}

/// The Spell4Effects id of a planted Proc row and of a planted summon row (type 98) in
/// Telekinetic Strike's spell.
const planted_proc = 99_201

const planted_summon = 99_202

/// A Proc row of kind 217 aimed at the caster in Telekinetic Strike's spell, with these
/// columns changed.
fn planted_proc_row(
  columns columns: List(#(String, planted_table.Cell)),
) -> List(planted_table.Cell) {
  spell_tables.effect_row_with(
    id: planted_proc,
    effect_type: 14,
    target_flags: 1,
    columns: list.append(columns, spell_tables.proc_columns(kind: 217)),
  )
}

/// A summon row (type 98) of Creature2 63677, aimed at the primary target as Spell4Effects
/// 189689 of the Q9396 Probebot is, in Telekinetic Strike's spell.
fn planted_summon_row() -> List(planted_table.Cell) {
  spell_tables.effect_row_with(
    id: planted_summon,
    effect_type: 98,
    target_flags: 2,
    columns: [
      #("dataBits00", Integer(63_677)),
      #("durationTime", Integer(3_600_000)),
    ],
  )
}

pub fn a_proc_the_caster_holds_beside_a_summon_row_leaves_the_spell_unbuilt_test() -> Nil {
  use <- owned_test.run(10_000)
  // The summon creates a unit the server does not build, and the Proc beside it is that
  // unit's own (Spell4 73125, the Q9396 Probebot: Proc 189684 and summon 189689; Spell4
  // 76365: 198006 and 198007), so a plan that kept it would hold it on the player.
  let refused =
    Error(spell_plan.SummonedProcNotRead(
      spell4_id: 32_893,
      proc_effect_id: planted_proc,
      summon_effect_id: planted_summon,
      creature2_id: 63_677,
    ))
  let built = fn(rows) {
    spell_tables.planned_strike(rows: spell_tables.rows_with_effects(
      effects: rows,
    ))
    |> result.replace(Nil)
  }
  let cases = [
    #(
      "a Proc aimed at the caster beside a summon row is refused",
      [planted_proc_row(columns: []), planted_summon_row()],
      refused,
    ),
    #(
      "a Proc with no summon beside it is read",
      [planted_proc_row(columns: [])],
      Ok(Nil),
    ),
    #(
      "a summon row with no Proc beside it builds",
      [planted_summon_row()],
      Ok(Nil),
    ),
    #(
      "a Proc the plan leaves out (a filter naming a Spell4 with no row) lands nowhere, so a summon beside it refuses nothing",
      [
        planted_proc_row(columns: [
          #("dataBits07", Integer(1)),
          #("dataBits08", Integer(999_999_999)),
        ]),
        planted_summon_row(),
      ],
      Ok(Nil),
    ),
    #(
      "a lasting row beside a summon row is no Proc, so the spell builds",
      [
        spell_tables.effect_row_with(
          id: planted_proc,
          effect_type: 17,
          target_flags: 1,
          columns: [#("durationTime", Integer(5000))],
        ),
        planted_summon_row(),
      ],
      Ok(Nil),
    ),
  ]
  list.each(cases, fn(found) {
    let #(reason, rows, expected) = found
    assert built(rows) == expected as reason
  })
  let error =
    spell_plan.SummonedProcNotRead(
      spell4_id: 32_893,
      proc_effect_id: planted_proc,
      summon_effect_id: planted_summon,
      creature2_id: 63_677,
    )
  assert spell_plan.is_unbuilt(error:)
    as "the ability is left out and the load goes on"
  assert string.contains(
    spell_plan.describe(error:),
    "its summon (type 98, Creature2 63677) is not built",
  )
    as "the reason names the summon as not built"
}

pub fn an_event_spell_carries_the_spell4base_of_its_spell4_test() -> Nil {
  use <- owned_test.run(10_000)
  // Spell4 32893 (Telekinetic Strike) is a spell of Spell4Base 19102 (Spell4.spell4BaseIdBaseSpell).
  let tables = fixture_tables.shared()
  let assert Ok(facts) =
    spell_plan.facts_of_spell4(tables:, spell4_id: Spell4Id(32_893))
    as "the facts of Telekinetic Strike"
  assert facts.spell4_base_id == Spell4BaseId(19_102)
    as "the facts of a Spell4 hold its Spell4Base"
  assert cast_proc.event_spell_of_facts(spell4_id: Spell4Id(32_893), facts:).spell4_base_id
    == Spell4BaseId(19_102)
    as "a creature's blow, whose spell is only a Spell4 id, carries the Spell4Base to its events"
  let assert Ok(spell) =
    spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id: 32_893,
      chain: [],
    )
    as "Telekinetic Strike plans"
  assert cast_proc.event_spell(spell:).spell4_base_id == Spell4BaseId(19_102)
    as "a spell the caster casts carries its Spell4Base to its events"
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
      spell: cast_support.real_spell(spell4_id: 79_229),
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
      spell: cast_support.real_spell(spell4_id: 52_371),
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
      sources: spell_plan.sources_of(tables:),
      place: spell_tables.pressed,
      effect: stealth_on,
    )
    as "the plan reads 178239 as a Proc"
  assert reading.trigger == spell_plan.TakesDamage
    as "kind 16 is a creature's blow taken"
  assert reading.limit == InWindow(window_ms: 1000, count: 1)
    as "dataBits04 1000 and dataBits05 1"
}

/// The Proc rows of the spell `spell4_id` an ability's tree holds, with how the tree starts it.
fn procs_of_spell(
  ability ability: Spell,
  spell4_id spell4_id: Int,
) -> List(#(spell_plan.ProcRow, spell_plan.Start)) {
  spell_plan.tree_started_with_alternate(spell: ability)
  |> list.filter(fn(started) { { started.0 }.spell4_id.value == spell4_id })
  |> list.flat_map(fn(started) {
    list.map(
      spell_plan.payloads(spell: started.0, as_kind: spell_plan.as_proc),
      fn(row) { #(row, started.1) },
    )
  })
}

pub fn the_proc_rows_of_a_planned_tree_held_by_another_unit_are_read_for_an_ally_or_left_out_for_their_reason_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let plans = spell_plan.plans_with_later(tables:)
  let ability = fn(spell4_id: Int) {
    let assert Ok(row) = spell4.get(tables:, id: Spell4Id(spell4_id))
      as "the ability's press is a Spell4 row"
    let assert Ok(spell) =
      spell_plan.in_plans(
        plans:,
        base: Spell4BaseId(row.spell4_base_id_base_spell),
      )
      as "the plans hold the ability"
    spell
  }
  // Healing Salve (Spellslinger, press 39121): its child 39386 holds 86457 (flags 4) beside
  // the caster's own 86458 (flags 1); the Surge alternate's child 45100 holds 104567.
  let salve = ability(39_121)
  let assert [#(area_row, _)] =
    procs_of_spell(ability: salve, spell4_id: 39_386)
    |> list.filter(fn(found) { { found.0 }.effect_id.value == 86_457 })
    as "39386 holds 86457 as a Proc row"
  assert area_row.holder == spell_plan.HeldByAreaAllies
    as "targetFlags 4 is held by the area's allies"
  let assert [#(surge_row, _)] =
    procs_of_spell(ability: salve, spell4_id: 45_100)
    |> list.filter(fn(found) { { found.0 }.effect_id.value == 104_567 })
    as "the alternate's 45100 holds 104567"
  assert surge_row.holder == spell_plan.HeldByAreaAllies
  // Sentinel (Warrior, press 54395): a Proxy at each ally starts 58432, whose 139830 is
  // held by the primary target, the ally the Proxy started it on.
  let assert [#(sentinel_row, start)] =
    procs_of_spell(ability: ability(54_395), spell4_id: 58_432)
    |> list.filter(fn(found) { { found.0 }.effect_id.value == 139_830 })
    as "58432 holds 139830 as a Proc row"
  assert sentinel_row.holder == spell_plan.HeldByPrimaryTarget
  assert start == spell_plan.Proxied(target: spell_plan.OnEachAlly)
  // The rows the plan leaves out, each for its reason, in the place their spell has.
  let effects = spell4_effects.all(tables)
  let place_of = effect_row_read.places(tables:, effects:)
  let sources = spell_plan.sources_of(tables:)
  let read_row = fn(row: Spell4Effects) {
    spell_plan.read_row(
      tables:,
      sources:,
      place: place_of(row.spell_id),
      effect: row,
    )
  }
  let read = fn(id: Int) { read_row(spell_tables.effect_row_in(tables:, id:)) }
  list.each([207_508, 207_874], fn(id) {
    assert read(id)
      == Ok(spell_plan.LeftOut(why: spell_plan.ProcHeldEventNotTold(kind: 21)))
      as "Affinity's rows are kind 21, a heal received, which an ally does not tell"
  })
  assert read(231_582)
    == Ok(
      spell_plan.LeftOut(why: spell_plan.ProcHeldByAnotherUnit(target_flags: 2)),
    )
    as "Analyze Weakness's row is a struck unit's child's: a creature holds it"
  assert read(85_628)
    == Ok(
      spell_plan.LeftOut(why: spell_plan.ProcKindWaits(
        kind: 76,
        event: "a spell of another unit landing on the holder",
      )),
    )
    as "kind 76 is left out naming its event"
  assert outcome_of(reading: read(107_509))
    == ReadFor(holder: spell_plan.HeldByPrimaryTarget)
    as "Spell4 45994's row has flags 2 and dataBits07 1 with dataBits08 0, which is no filter: read for the primary target"
  // Rows of three spells that last until removed (flags bit 2): only the one in an aura that
  // ends (castMethod 10, spellDuration above 0) is read. Field Probes' field 198781 has
  // spellDuration 10 000; 141538's spellDuration is -1 and 106000's castMethod is 0, and both
  // sit behind a persistence prerequisite, which the edit clears to reach the decision.
  assert outcome_of(reading: read(198_781))
    == ReadFor(holder: spell_plan.HeldByAreaAllies)
    as "an aura that ends gives the ally's row its end"
  list.each([141_538, 106_000], fn(id) {
    let row = spell_tables.effect_row_in(tables:, id:)
    assert outcome_of(reading: read_row(
        Spell4Effects(
          ..row,
          prerequisite_id_caster_persistence: 0,
          prerequisite_id_target_persistence: 0,
        ),
      ))
      == LeftOutFor(why: spell_plan.ProcAllyUntilRemoved)
      as "a spell that is no aura that ends gives an ally's until-removed row no end"
  })
}

pub fn no_proc_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let read = spell_tables.rows_read(tables:, effect_type: 14)
  assert read != [] as "the client's tables hold Proc rows"
  list.each(read, fn(found) {
    let #(effect, reading) = found
    case reading {
      Ok(_) -> Nil
      Error(spell_plan.SummonedProcNotRead(..) as error) -> {
        assert spell_plan.is_unbuilt(error:)
          as "a Proc beside a summon leaves its ability out and the load goes on"
      }
      Error(error) ->
        panic as {
          "the Proc row "
          <> int.to_string(effect.id)
          <> " fails the load: "
          <> spell_plan.describe(error:)
        }
    }
  })
}

pub fn each_client_proc_row_beside_a_summon_row_refuses_its_spell_and_no_other_does_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let summoning =
    spell4_effects.all(tables)
    |> list.filter(fn(effect) { effect.effect_type == 98 })
    |> list.map(fn(effect) { effect.spell_id })
    |> set.from_list
  let refused =
    spell_tables.rows_read(tables:, effect_type: 14)
    |> list.filter_map(fn(found) {
      case found.1 {
        Error(spell_plan.SummonedProcNotRead(
          spell4_id:,
          proc_effect_id:,
          summon_effect_id:,
          creature2_id:,
        )) -> {
          assert spell4_id == { found.0 }.spell_id
            && proc_effect_id == { found.0 }.id
            as "the error names the Proc row and its spell"
          let assert Ok(summon) =
            spell4_effects.get(
              tables:,
              id: id.Spell4EffectsId(summon_effect_id),
            )
            as "the error names a row of the tables"
          assert summon.effect_type == 98
            && summon.spell_id == spell4_id
            && summon.data_bits00 == creature2_id
            as "the summon row is a type 98 row of the same spell naming the Creature2 in dataBits00"
          Ok(proc_effect_id)
        }
        _ -> Error(Nil)
      }
    })
  assert list.contains(refused, 189_684)
    as "Spell4Effects 189684 (Spell4 73125, the Q9396 Probebot's Proc) is refused"
  assert list.contains(refused, 198_006)
    as "Spell4Effects 198006 (Spell4 76365) is refused"
  list.each(refused, fn(proc_effect_id) {
    let assert Ok(effect) =
      spell4_effects.get(tables:, id: id.Spell4EffectsId(proc_effect_id))
    assert set.contains(summoning, effect.spell_id) && effect.target_flags == 1
      as "a refused Proc is aimed at the caster in a spell that holds a type 98 row"
  })
}

pub fn each_client_proc_row_reads_its_filter_in_the_id_space_its_kind_names_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let read = spell_tables.rows_read(tables:, effect_type: 14)
  let filter_of = fn(found: #(Spell4Effects, _)) {
    case found.1 {
      Ok(spell_plan.Applied(spell_plan.ReadProc(reading:, ..)))
      | Ok(spell_plan.Held(spell_plan.ReadProc(reading:, ..))) ->
        Ok(#(found.0, reading.filter))
      _ -> Error(Nil)
    }
  }
  let filters = list.filter_map(read, filter_of)
  let expected_of = fn(effect: Spell4Effects) {
    case effect.data_bits07, effect.data_bits08 {
      _, 0 -> spell_plan.AnySpell
      0, base -> OfBase(spell4_base_id: Spell4BaseId(base))
      1, spell4_id -> OneSpell(spell4_id: Spell4Id(spell4_id))
      _, group_id -> InGroup(group_id:)
    }
  }
  list.each(filters, fn(found) {
    assert found.1 == expected_of(found.0)
      as {
        "the Proc row "
        <> int.to_string({ found.0 }.id)
        <> " reads dataBits08 in the id space dataBits07 names, and 0 as no filter"
      }
  })
  let listed_groups =
    spell4_group_list.all(tables)
    |> list.flat_map(fn(row) { spell_plan.group_ids_of(row:) })
    |> set.from_list
  list.each(filters, fn(found) {
    case found.1 {
      InGroup(group_id:) -> {
        assert set.contains(listed_groups, group_id)
          as {
            "the Proc row "
            <> int.to_string({ found.0 }.id)
            <> " is read with a group filter no Spell4GroupList row lists"
          }
      }
      OfBase(..) | OneSpell(..) | spell_plan.AnySpell -> Nil
    }
  })
  let classes = [
    #(0, 0, "kind 0 with no id"),
    #(1, 0, "kind 1 with no id"),
    #(2, 0, "kind 2 with no id"),
    #(0, 1, "kind 0 with a Spell4Base id"),
    #(1, 1, "kind 1 with a Spell4 id"),
    #(2, 1, "kind 2 with a group id"),
  ]
  list.each(classes, fn(class) {
    assert list.any(filters, fn(found) {
      found.0.data_bits07 == class.0
      && { found.0.data_bits08 == 0 } == { class.1 == 0 }
    })
      as { "the plan reads a Proc row of " <> class.2 }
  })
  list.each(read, fn(found) {
    let #(effect, reading) = found
    case reading {
      Ok(spell_plan.LeftOut(why: spell_plan.ProcFilterNamesNoSpell4(spell4_id:))) -> {
        assert effect.data_bits07 == 1
          && effect.data_bits08 == spell4_id
          && spell4_id != 0
          && spell4.get(tables:, id: Spell4Id(spell4_id)) == Error(Nil)
          as {
            "the Proc row "
            <> int.to_string(effect.id)
            <> " is left out for a Spell4 filter whose id the Spell4 table lacks"
          }
      }
      Ok(spell_plan.LeftOut(why: spell_plan.ProcFilterNamesNoSpell4Base(
        spell4_base_id:,
      ))) -> {
        assert effect.data_bits07 == 0
          && effect.data_bits08 == spell4_base_id
          && spell4_base_id != 0
          && spell4_base.get(tables:, id: Spell4BaseId(spell4_base_id))
          == Error(Nil)
          as {
            "the Proc row "
            <> int.to_string(effect.id)
            <> " is left out for a Spell4Base filter whose id the Spell4Base table lacks"
          }
      }
      Ok(spell_plan.LeftOut(why: spell_plan.ProcFilterNamesNoGroup(group_id:))) -> {
        assert effect.data_bits07 == 2
          && effect.data_bits08 == group_id
          && group_id != 0
          && !set.contains(listed_groups, group_id)
          as {
            "the Proc row "
            <> int.to_string(effect.id)
            <> " is left out for a group filter whose id no Spell4GroupList row lists"
          }
      }
      _ -> Nil
    }
  })
}

pub fn real_rows_of_the_landing_kinds_read_with_their_filter_gate_aim_and_life_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  // Spell4Effects.effectType.14.dataBits00.229_230_231 and .27: each row below is the
  // client's, with the filter and the gate its columns hold (`.dataBits07`, `.prerequisites`),
  // the aim of its dataBits03 (bit 4 at the other unit) and the life of its durationTime.
  let read =
    spell_tables.rows_read(tables: client_tables.shared(), effect_type: 14)
  let rows = [
    #(
      98_744,
      spell_plan.LandsPhysicalDamage,
      InGroup(group_id: 333),
      AtHolder,
      0,
      InWindow(window_ms: 1000, count: 1),
      lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    ),
    #(
      228_626,
      spell_plan.LandsPhysicalDamage,
      InGroup(group_id: 491),
      AtHolder,
      0,
      InWindow(window_ms: 500, count: 1),
      lasting.LastingRow(delay_ms: 0, duration_ms: 10_000, until_removed: False),
    ),
    #(
      174_297,
      spell_plan.LandsTechDamage,
      InGroup(group_id: 492),
      AtHolder,
      0,
      InWindow(window_ms: 450, count: 1),
      lasting.LastingRow(delay_ms: 0, duration_ms: 10_000, until_removed: False),
    ),
    #(
      180_868,
      spell_plan.LandsMagicDamage,
      InGroup(group_id: 333),
      AtHolder,
      0,
      InWindow(window_ms: 1000, count: 1),
      lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    ),
    #(
      122_737,
      spell_plan.LandsSpell,
      spell_plan.AnySpell,
      AtHolder,
      22_150,
      ForLife(count: 1),
      lasting.LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
    ),
    #(
      228_564,
      spell_plan.LandsSpell,
      InGroup(group_id: 747),
      AtHolder,
      0,
      InWindow(window_ms: 250, count: 90),
      lasting.LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False),
    ),
    #(
      146_845,
      spell_plan.LandsSpell,
      InGroup(group_id: 496),
      AtOtherUnit,
      0,
      InWindow(window_ms: 250, count: 5),
      lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    ),
    #(
      217_391,
      spell_plan.LandsSpell,
      OfBase(spell4_base_id: Spell4BaseId(25_531)),
      AtHolder,
      0,
      InWindow(window_ms: 1000, count: 60),
      lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    ),
  ]
  list.each(rows, fn(expected) {
    let #(id, trigger, filter, aim, holder_gate, limit, life) = expected
    let assert Ok(#(effect, outcome)) =
      list.find(read, fn(found) { { found.0 }.id == id })
      as "the tables hold the row"
    let assert Ok(spell_plan.Applied(spell_plan.ReadProc(reading:, ..))) =
      outcome
      as "the plan reads the row"
    assert reading.trigger == trigger
    assert reading.holder == spell_plan.HeldByCaster
    assert reading.filter == filter
      as "the filter is read in the id space dataBits07 names"
    assert reading.aim == aim
    assert reading.holder_gate == holder_gate
    assert reading.limit == limit
    assert spell_plan.lasting_row_of(effect:) == life
      as {
        "the Proc row "
        <> int.to_string(id)
        <> " lasts as its durationTime says"
      }
  })
}

pub fn each_ally_proc_row_the_plan_reads_waits_for_a_trigger_a_creatures_blow_raises_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let spell =
    event_proc.EventSpell(
      spell4_id: Spell4Id(5649),
      spell4_base_id: Spell4BaseId(4947),
      groups: [],
      school: 1,
    )
  let blows = [
    cast_proc.BlowDeflected(striker: 31, spell:),
    ..list.flat_map([True, False], fn(lowered) {
      list.flat_map([True, False], fn(critical) {
        list.map([True, False], fn(shield_depleted) {
          cast_proc.BlowLanded(
            striker: 31,
            spell:,
            lowered:,
            critical:,
            shield_depleted:,
          )
        })
      })
    })
  ]
  let raised =
    list.flat_map(blows, fn(blow) { cast_proc.blow_events(blow:) })
    |> list.map(fn(event) { event.trigger })
  let ally_rows_read =
    spell_tables.rows_read(tables: client_tables.shared(), effect_type: 14)
    |> list.filter_map(fn(found) {
      case found {
        #(effect, Ok(spell_plan.Applied(spell_plan.ReadProc(reading:, ..))))
          if effect.target_flags == 2 || effect.target_flags == 4
        -> Ok(#(effect, reading))
        _ -> Error(Nil)
      }
    })
  assert ally_rows_read != [] as "the plan reads Proc rows an ally holds"
  list.each(ally_rows_read, fn(found) {
    let #(effect, reading) = found
    assert list.contains(raised, reading.trigger)
      as {
        "the Proc row "
        <> int.to_string(effect.id)
        <> " is held by an ally and waits for kind "
        <> int.to_string(effect.data_bits00)
        <> ", which no blow of a creature on the ally raises"
      }
  })
}

pub fn the_effect_kind_reads_a_proc_row_aimed_at_the_caster_the_primary_target_or_the_area_alone_test() -> Nil {
  use <- owned_test.run(10_000)
  assert effect_kind.is_read(effect_type: 14)
    as "type 14 is handled, for its rows aimed at the caster, the primary target or the area"
  assert effect_kind.kind_of(effect_type: 14) == effect_kind.Proc
  // The plan's own reading of a row's holder: a row left out as held by another unit has
  // targetFlags no holder is named for.
  list.each([0, 1, 2, 3, 4, 5, 6, 7], fn(flags) {
    let plan_holds = case
      spell_plan.proc_read(
        spell4_id: holder,
        effect: timed(id: 1, flags:, kind: 16),
      )
    {
      Ok(ProcIsLeftOut(why: spell_plan.ProcHeldByAnotherUnit(..))) -> False
      Ok(_) -> True
      Error(error) -> panic as spell_plan.describe(error:)
    }
    assert effect_kind.is_row_read(effect_type: 14, target_flags: flags)
      == plan_holds
      as {
        "the effect kind and the plan agree on who holds a Proc row of targetFlags "
        <> int.to_string(flags)
      }
    assert plan_holds == list.contains([1, 2, 4], flags)
      as "Spell4Effects.targetFlags: 1 the caster, 2 the primary target, 4 the area's allies hold a Proc row; 3, 5, 6 and 7 name several units at once"
  })
  use <- unitest.guard(client_tables.present())
  let effects = spell4_effects.all(client_tables.shared())
  let activating =
    list.filter(effects, fn(effect) {
      effect_kind.kind_of(effect_type: effect.effect_type)
      == effect_kind.Activate
    })
    |> list.map(fn(effect) { effect.spell_id })
    |> set.from_list
  effects
  |> list.filter(fn(effect) {
    effect.effect_type == 14 && list.contains([2, 4], effect.target_flags)
  })
  |> list.each(fn(effect) {
    assert !set.contains(activating, effect.spell_id)
      as {
        "the Proc row "
        <> int.to_string(effect.id)
        <> " aimed at another unit sits in an activate spell, which the activation would refuse"
      }
  })
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

// ---- the fairly-sure kinds, each read or left out naming its event ----

/// Each kind the server reads, with its trigger and the suffix of the record that settles it
/// (`Spell4Effects.effectType.14.dataBits00` and the suffix).
fn kinds_read() -> List(#(Int, spell_plan.Trigger, String)) {
  [
    #(217, EnteredStealth, ".217_218"),
    #(218, LeftStealth, ".217_218"),
    #(0, Died, ".0_44"),
    #(44, LeftCombat, ".0_44"),
    #(12, LandsHit, ""),
    #(13, LandsMeleeHit, ".13_school"),
    #(145, LandsCritical, ""),
    #(1, Kills, ""),
    #(20, LandsHeal, ""),
    #(147, LandsCriticalHeal, ""),
    #(10, spell_plan.UsesAbility, ".fairly_sure"),
    #(103, spell_plan.SpendsResource, ".fairly_sure"),
    #(21, spell_plan.ReceivesHeal, ".fairly_sure"),
    #(52, spell_plan.FoeDeflects, ".fairly_sure"),
    #(49, spell_plan.LandsFinisherCritical, ".fairly_sure"),
    #(11, spell_plan.StartsMoving, ".fairly_sure"),
    #(87, spell_plan.ResourceCrosses, ".fairly_sure"),
    #(105, spell_plan.SuitPowerDrops, ".fairly_sure"),
    #(182, spell_plan.LandsTaunt, ".fairly_sure"),
    #(27, spell_plan.LandsSpell, ".27"),
    #(229, spell_plan.LandsPhysicalDamage, ".229_230_231"),
    #(230, spell_plan.LandsTechDamage, ".229_230_231"),
    #(231, spell_plan.LandsMagicDamage, ".229_230_231"),
  ]
}

/// Each kind the server does not raise, with the event its group's texts name and the suffix
/// of the record that settles it.
fn kinds_waiting() -> List(#(Int, String, String)) {
  let with_record = fn(kinds, event, record) {
    list.map(kinds, fn(kind) { #(kind, event, record) })
  }
  list.flatten([
    with_record(
      [57, 40, 117, 154],
      "the holder entering combat, or its health or shield crossing a value",
      ".fairly_sure",
    ),
    with_record(
      [23, 50, 114, 131, 234, 249],
      "the holder taking a blow: direct, magic or critical damage, damage to its shield, an absorb destroyed, or a glance",
      ".fairly_sure",
    ),
    with_record(
      [124, 102, 112],
      "the holder dashing, dodging, or using up its endurance",
      ".fairly_sure",
    ),
    with_record(
      [152],
      "the holder's focus dropping below a value",
      ".fairly_sure",
    ),
    with_record(
      [155, 197, 159, 41, 153, 236],
      "the holder being stunned, snared, rooted or crowd-controlled, breaking a crowd control, or having its cast interrupted",
      ".fairly_sure",
    ),
    with_record([46], "a crowd control on the holder ending", ".fairly_sure"),
    with_record([2], "the holder killing a player", ".fairly_sure"),
    with_record([148], "the holder receiving a critical heal", ".fairly_sure"),
    with_record(
      [251, 253],
      "the holder landing a multi-hit strike or heal",
      ".fairly_sure",
    ),
    with_record([69], "a cast of a spell ending", ".69"),
    with_record([76], "a spell of another unit landing on the holder", ".76"),
  ])
}

pub fn proc_every_kind_read_or_refused_test() -> Nil {
  use <- owned_test.run(120_000)
  list.each(kinds_read(), fn(kind) {
    assert read_of(
        effect: Spell4Effects(..row(id: 99_020), data_bits00: kind.0),
      )
      == reading(trigger: kind.1)
      as {
        "Spell4Effects.effectType.14.dataBits00"
        <> kind.2
        <> ": kind "
        <> int.to_string(kind.0)
        <> " is read"
      }
  })
  use <- unitest.guard(client_tables.present())
  let named =
    list.append(
      list.map(kinds_read(), fn(kind) { kind.0 }),
      list.map(kinds_waiting(), fn(kind) { kind.0 }),
    )
  let procs =
    spell4_effects.all(client_tables.shared())
    |> list.filter(fn(effect) { list.contains(named, effect.data_bits00) })
  assert procs != [] as "the tables hold Proc rows of the named kinds"
  list.each(procs, fn(effect) {
    case spell_plan.proc_read(spell4_id: effect.spell_id, effect:) {
      Error(ProcKindNotRead(..)) ->
        panic as "a row of a named kind falls to ProcKindNotRead"
      Error(..) | Ok(..) -> Nil
    }
  })
  // Kinds 27, 229, 230 and 231: every client row is read but the two the plan leaves out,
  // each for its reason (`Spell4Effects.effectType.14.dataBits00.27`: 59894 is held by the
  // primary target, which an ally's event does not tell for kind 27; 198593 has dataBits03 36).
  let landing_rows =
    spell_tables.rows_read(tables: client_tables.shared(), effect_type: 14)
    |> list.filter(fn(found) {
      list.contains([27, 229, 230, 231], { found.0 }.data_bits00)
    })
  assert landing_rows != [] as "the tables hold rows of the landing kinds"
  list.each(landing_rows, fn(found) {
    let #(effect, outcome) = found
    case effect.id {
      59_894 -> {
        assert outcome
          == Ok(
            spell_plan.LeftOut(why: spell_plan.ProcHeldEventNotTold(kind: 27)),
          )
          as "row 59894 is left out for the unit that holds it"
      }
      198_593 -> {
        assert outcome
          == Ok(
            spell_plan.LeftOut(why: spell_plan.ProcAimNotRead(data_bits03: 36)),
          )
          as "row 198593 is left out for its aim"
      }
      id ->
        case outcome {
          Ok(spell_plan.Applied(spell_plan.ReadProc(..))) -> Nil
          Ok(..) | Error(..) ->
            panic as {
              "the Proc row "
              <> int.to_string(id)
              <> " of a landing kind is read, or left out naming a reason above"
            }
        }
    }
  })
}

pub fn a_proc_of_a_kind_the_server_does_not_raise_is_left_out_naming_the_event_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(kinds_waiting(), fn(kind) {
    let effect = Spell4Effects(..row(id: 99_021), data_bits00: kind.0)
    assert spell_plan.proc_read(spell4_id: holder, effect:)
      == Ok(
        ProcIsLeftOut(why: spell_plan.ProcKindWaits(kind: kind.0, event: kind.1)),
      )
      as {
        "Spell4Effects.effectType.14.dataBits00"
        <> kind.2
        <> ": kind "
        <> int.to_string(kind.0)
        <> " is left out naming its event, never as another kind"
      }
  })
  assert spell_plan.proc_read(
      spell4_id: holder,
      effect: Spell4Effects(..row(id: 99_021), data_bits00: 3),
    )
    == Error(spell_plan.ProcKindNotRead(
      spell4_id: holder,
      effect_id: 99_021,
      kind: 3,
    ))
    as "a kind of no group reads as before"
}

pub fn the_plan_leaves_a_proc_of_a_kind_the_server_does_not_raise_out_naming_the_event_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(kinds_waiting(), fn(kind) {
    assert planned(
        effect: Spell4Effects(..row(id: 99_022), data_bits00: kind.0),
      )
      == Ok(
        spell_plan.LeftOut(why: spell_plan.ProcKindWaits(
          kind: kind.0,
          event: kind.1,
        )),
      )
      as {
        "the plan leaves kind "
        <> int.to_string(kind.0)
        <> " out, naming its event"
      }
  })
  assert planned(effect: Spell4Effects(..row(id: 99_023), data_bits00: 3))
    == Ok(spell_plan.LeftOut(why: spell_plan.ProcOfAnotherKind(kind: 3)))
    as "a kind outside the named ones still reads as another kind"
}
