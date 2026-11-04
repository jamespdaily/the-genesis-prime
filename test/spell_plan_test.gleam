//// The tree of casts each class's level-1 ability starts (`genesis_prime/game/spell_plan`).
//// Expected values come from the client's rows, which the fact file records and
//// `table_rows` prints, each named at the assertion: `Spell4.32893` (Telekinetic
//// Strike), `Spell4.32812` (Crush), `Spell4.38791` (Stagger), `Spell4.29874` and
//// `Spell4.32809` with `Spell4CastResult.vital_cost` (the short vitals),
//// `Spell4Effects.effectType.26` (a Proxy starts a spell),
//// `SpellPhase.phaseDelay` with `0x14055e180` (the phases), `0x14046afc0` and
//// `0x1403b14c0` (the global cooldown), `Spell.CodeEnumCastMethod`,
//// `cast.current_cast` with `Spell4Base.castBarType` and `Spell4.thresholdTime`
//// (the cast bar of each method), `Spell4Thresholds.spell4IdToCast` with
//// `0x1403bfd60` (the stages), `0x14053d1f0` (a channel's gos), `0x14053e5a0` (the
//// cooldown of each method) and `Spell4CastResult.vital_cost`. The
//// planted tables hold those rows (`spell_tables`); the real tables are read
//// where the client is present. A missing row and a cycle are planted.

import client_tables
import genesis_prime/game/loadout
import genesis_prime/game/spell_plan.{
  type Spell, Always, AtFirstGo, AtLastGo, Channel, Channeled, ChargeRelease,
  GlobalCooldown, Multiphase, Normal, NotAtAGo, PrimaryWeapon, RapidTap,
}
import genesis_prime/table/id.{ClassId, Spell4BaseId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import planted_table
import qcheck
import spell_tables
import unitest

fn planted(base base: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(plans: spell_tables.plans(), base: Spell4BaseId(base))
    as "the planted class holds the ability"
  spell
}

pub fn telekinetic_strike_takes_1250_ms_has_a_global_cooldown_of_1000_ms_that_blocks_and_one_child_on_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = planted(base: 19_102)
  assert spell.spell4_id == Spell4Id(32_893)
  assert spell.method == Normal
    as "Spell.CodeEnumCastMethod 0, Spell4Base 19102"
  assert spell.cast_time_ms == 1250 as "Spell4.32893: castTime 1250"
  assert spell.cooldown_ms == 0 as "Spell4.32893: no cooldown of its own"
  assert spell.cast_bar == spell_plan.ShowsCastBar
    as "Spell4Base 19102: castBarType 1 with a cast time, so the client shows the bar and keeps it as the current cast (cast.current_cast)"
  assert !spell.ignores_casting && !spell.free_while_live
    as "Spell4.32893: propertyFlags 0x4000002 has neither 0x1, 0x10 nor 0x40"
  assert spell.global_cooldown
    == GlobalCooldown(refused_while_running: True, starts_for_ms: Some(1000))
    as "kind 0 is refused while the global cooldown runs and starts it (0x1403b14c0, 0x14046afc0); SpellCoolDown row 213 is 1000 ms"
  assert spell.unpayable_cost == None
  assert spell.phase_delays_ms == []
  let assert [proxy] = spell.proxies
    as "Spell4Effects 62204 is the one Proxy; 62159, the damage, starts no cast"
  assert proxy.spell.spell4_id == Spell4Id(30_900)
    as "Spell4Effects.effectType.26: dataBits00 is the Spell4 it starts"
  assert proxy.delay_ms == 0
  assert proxy.condition == Always
  assert spell_plan.go_times_ms(spell:) == [1250]
    as "a spell that is not Multiphase has the one go, at the end of its cast time"
}

pub fn crush_starts_its_child_100_ms_after_its_go_and_blocks_and_starts_no_global_cooldown_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = planted(base: 19_022)
  assert spell.cooldown_ms == 35_000 as "Spell4.32812: cooldown 35 s"
  assert spell.global_cooldown
    == GlobalCooldown(refused_while_running: False, starts_for_ms: None)
    as "kind 3 is neither refused by the global cooldown nor starts it (opcode.0x7ff.root_parent: kind 3 for the abilities' children)"
  let assert [proxy] = spell.proxies
  assert proxy.spell.spell4_id == Spell4Id(42_297)
    as "Spell4.32812: the Proxy starts 42297"
  assert proxy.delay_ms == 100 as "Spell4.32812: delayTime 100"
  assert proxy.spell.global_cooldown.starts_for_ms == None
}

pub fn stagger_needs_no_target_and_proxies_a_multiphase_spell_whose_four_phases_each_start_the_damage_spell_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = planted(base: 23_173)
  assert spell.ignores_casting
    as "Spell4.38791: propertyFlags 0x4000003 has 0x1, so a press of Stagger is never refused 13"
  assert spell.weapon == PrimaryWeapon
    as "Spell4Base 23173: weaponSlot 1 (0x1403afb10)"
  assert spell.global_cooldown
    == GlobalCooldown(refused_while_running: False, starts_for_ms: Some(750))
    as "kind 1 starts the global cooldown and is not refused by it; row 180 is 750 ms"
  let assert [staggering] = spell.proxies
  assert staggering.spell.spell4_id == Spell4Id(38_780)
  assert staggering.spell.cast_bar == spell_plan.HidesCastBar
    as "Spell4Base 23162: castBarType 0, so the client never makes 38780 the current cast (Spell4Base.castBarType)"
  assert staggering.spell.method == spell_plan.Multiphase
    as "Spell.CodeEnumCastMethod 8; Spell4.38791"
  assert staggering.spell.phase_delays_ms == [166, 200, 167, 167]
    as "SpellPhase 3717 to 3720: phaseDelay in order index order"
  assert spell_plan.go_times_ms(spell: staggering.spell) == [166, 366, 533, 700]
    as "each delay is the gap after the phase before (SpellPhase.phaseDelay)"
  list.each([0, 1, 2, 3], fn(phase) {
    let assert [hit] =
      spell_plan.proxies_in_phase(spell: staggering.spell, phase:)
      as {
        "phase "
        <> int.to_string(phase)
        <> " has one Proxy (phaseFlags 1, 2, 4, 8)"
      }
    assert hit.spell.spell4_id == Spell4Id(38_781)
      as "Spell4.38791: each phase proxies 38781"
  })
}

pub fn a_cost_the_unit_cannot_pay_gives_the_result_of_its_resource_slot_test() -> Nil {
  use <- owned_test.run(60_000)
  assert planted(base: 19_019).unpayable_cost == Some(51)
    as "Spell4CastResult.vital_cost: Mind Burst, type 6 (Resource1), gives 51"
  let gamma_rays = planted(base: 16_322)
  assert gamma_rays.unpayable_cost == Some(55)
    as "Spell4CastResult.vital_cost: Gamma Rays, type 18, with Class 4's slots 1 to 5 holding vital 18, gives 50 + the last, 55"
  assert gamma_rays.weapon == PrimaryWeapon
  assert list.length(gamma_rays.proxies) == 2
    as "Spell4.29874: Proxies to 34775 and 35886"
}

pub fn a_spell_row_a_tree_names_that_the_tables_lack_fails_the_build_naming_the_table_and_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let result =
    spell_tables.with_loaded(
      rows: spell_spell4_without(rows:, ids: [30_900]),
      body: fn(tables) { spell_plan.build(tables:) },
    )
  assert result == Error(spell_plan.NoRow(table: "Spell4", id: 30_900))
    as "62204 proxies 30900, which has no Spell4 row: the load names the table and the id"
}

/// The planted rows with one more effect row.
fn with_effect(effect effect: List(planted_table.Cell)) -> spell_tables.Rows {
  let rows = spell_tables.rows()
  spell_tables.Rows(..rows, spell4_effects: [effect, ..rows.spell4_effects])
}

pub fn a_cycle_of_proxies_fails_the_load_naming_the_spells_on_the_way_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Error(error) =
    spell_tables.derivation_result(
      rows: with_effect(effect: spell_tables.effect_row(
        id: 99_001,
        spell: 30_900,
        type_: 26,
        target_flags: 1,
        delay: 0,
        phases: -1,
        data: 32_893,
      )),
    )
    as "Telekinetic Strike proxies 30900, which proxies Telekinetic Strike: the tables' load fails, so the server does not start"
  assert string.contains(table_store.describe(error), "32893 -> 30900 -> 32893")
    as "the load names the chain from the pressed ability to the spell that repeats"
}

pub fn a_multiphase_spell_with_no_kept_phase_row_fails_the_load_naming_the_table_and_owner_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let assert Error(error) =
    spell_tables.derivation_result(
      rows: spell_tables.Rows(
        ..rows,
        spell_phases: planted_table.without(rows: rows.spell_phases, ids: [
          3717,
          3718,
          3719,
          3720,
        ]),
      ),
    )
    as "38780 is Multiphase and keeps no phase, which the client's rule (0x14055e180) would give it none of: the load fails rather than give it one go"
  let reason = table_store.describe(error)
  assert string.contains(reason, "SpellPhase")
    && string.contains(reason, "38780")
    as "the load names the table and the owner"
}

pub fn the_load_fails_with_the_builds_reason_naming_the_table_and_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let assert Error(error) =
    spell_tables.derivation_result(
      rows: spell_spell4_without(rows:, ids: [30_900]),
    )
    as "a tree that names a missing row fails the tables' load, so the server does not start"
  let reason = table_store.describe(error)
  assert string.contains(reason, "Spell4") && string.contains(reason, "30900")
    as "the message names the table and the id"
  assert string.contains(
    spell_plan.describe(error: spell_plan.NoRow(table: "Spell4", id: 30_900)),
    "30900",
  )
    as "the plan's own sentence names the id"
  assert spell_tables.derivation_result(rows:) == Ok(Nil)
    as "the planted rows load"
}

fn spell_spell4_without(
  rows rows: spell_tables.Rows,
  ids ids: List(Int),
) -> spell_tables.Rows {
  spell_tables.Rows(
    ..rows,
    spell4: planted_table.without(rows: rows.spell4, ids:),
  )
}

pub fn every_class_ability_of_the_clients_tables_builds_a_tree_and_the_nine_normal_ones_are_normal_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let plans = spell_plan.plans(tables:)
  let pressed = [
    #(1, 38_017),
    #(1, 37_968),
    #(1, 18_309),
    #(2, 25_635),
    #(2, 25_473),
    #(2, 26_468),
    #(3, 19_102),
    #(3, 19_019),
    #(3, 19_022),
    #(4, 38_201),
    #(4, 16_322),
    #(4, 26_543),
    #(5, 23_148),
    #(5, 23_161),
    #(5, 23_173),
    #(7, 27_638),
    #(7, 20_684),
    #(7, 20_325),
  ]
  list.each(pressed, fn(pair) {
    let assert Ok(set) =
      loadout.of(tables:, class_id: ClassId(pair.0), faction_id: 166)
      as "the class has a Novice set"
    assert list.contains(set.abilities, Spell4BaseId(pair.1))
      as {
        "class "
        <> int.to_string(pair.0)
        <> " holds the ability "
        <> int.to_string(pair.1)
      }
    let assert Ok(spell) =
      spell_plan.in_plans(plans:, base: Spell4BaseId(pair.1))
      as { "the plan holds the ability " <> int.to_string(pair.1) }
    assert spell.spell4_base_id == Spell4BaseId(pair.1)
  })
  list.each(
    [38_017, 25_635, 19_102, 19_019, 19_022, 16_322, 26_543, 23_173, 20_325],
    fn(base) {
      let assert Ok(spell) =
        spell_plan.in_plans(plans:, base: Spell4BaseId(base))
        as "the plan holds the ability"
      assert spell.method == Normal
        as {
          "Spell4.* of the nine Normal starting abilities (Spell4Base "
          <> int.to_string(base)
          <> " castMethod 0)"
        }
    },
  )
  let assert Ok(strike) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(19_102))
    as "Telekinetic Strike is planned"
  assert strike.cast_time_ms == 1250 as "Spell4.32893"
  assert strike.global_cooldown.starts_for_ms == Some(1000)
    as "Spell4.32893 kind 0, SpellCoolDown 213 (table_rows)"
  let assert Ok(kick) = spell_plan.in_plans(plans:, base: Spell4BaseId(38_017))
  assert kick.cooldown_ms == 20_000 as "Spell4.58591: spellCoolDown 20000"
  assert kick.global_cooldown.starts_for_ms == None
    as "Spell4.58591: global cooldown kind 3"
  let assert Ok(gate) = spell_plan.in_plans(plans:, base: Spell4BaseId(20_325))
  assert list.length(gate.proxies) == 2
    as "Spell4.34355: Proxies to 25190 and 30436"
}

/// The ids of the stages of a spell, in order, with each thresholdDuration.
fn stages_of(spell spell: Spell) -> List(#(Int, Int)) {
  list.map(spell.stages, fn(stage) {
    #(stage.spell.spell4_id.value, stage.duration_ms)
  })
}

pub fn the_stages_of_a_tap_or_charge_ability_are_the_rows_of_spell4_thresholds_in_order_index_order_test() -> Nil {
  use <- owned_test.run(60_000)
  assert stages_of(spell: planted(base: 23_148)) == [#(38_766, 0)]
    as "Spell4Thresholds 238: Shred casts 38766"
  assert stages_of(spell: planted(base: 18_309)) == [#(32_079, 0), #(32_080, 0)]
    as "Spell4Thresholds 9 and 10: Relentless Strikes, orderIndex 0 and 1"
  assert stages_of(spell: planted(base: 37_968))
    == [#(66_987, 0), #(71_125, 0), #(71_126, 0)]
    as "Spell4Thresholds 1073 to 1075: Rampage"
  assert stages_of(spell: planted(base: 20_684))
    == [#(34_720, 0), #(34_722, 1000), #(36_691, 1400)]
    as "Spell4Thresholds 125, 123 and 124 by orderIndex 0, 1 and 2, not by id: each row's thresholdDuration is the time to the level"
  assert planted(base: 19_102).stages == []
    as "a Normal ability has no Spell4Thresholds row"
}

pub fn a_stage_spell_is_a_full_tree_with_its_own_proxy_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [stage] = planted(base: 23_148).stages
  let assert [proxy] = stage.spell.proxies
    as "Spell4Effects 83782: the stage 38766 proxies 39467"
  assert proxy.spell.spell4_id == Spell4Id(39_467)
  assert stage.spell.method == RapidTap
    as "Spell4Base 23149: castMethod 6, with thresholdTime 0"
  assert stage.spell.threshold_ms == 0 && stage.spell.stages == []
    as "Spell4.38766: a stage opens no threshold of its own"
}

pub fn a_stage_spell4_row_the_tables_lack_fails_the_build_naming_the_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let result =
    spell_tables.with_loaded(
      rows: spell_spell4_without(rows: spell_tables.rows(), ids: [38_766]),
      body: fn(tables) { spell_plan.build(tables:) },
    )
  assert result == Error(spell_plan.NoRow(table: "Spell4", id: 38_766))
    as "Spell4Thresholds 238 casts 38766, which has no Spell4 row"
}

pub fn the_stage_resolver_gives_the_row_at_the_index_the_ability_at_minus_1_and_nothing_past_the_end_test() -> Nil {
  use <- owned_test.run(60_000)
  let charged_shot = planted(base: 20_684)
  let spell4_id_at = fn(index) {
    spell_plan.stage_at(spell: charged_shot, index:)
    |> result.map(fn(spell) { spell.spell4_id.value })
  }
  assert spell4_id_at(0) == Ok(34_720)
    as "0x1403bfd60: an open threshold casts the row at its index"
  assert spell4_id_at(1) == Ok(34_722)
  assert spell4_id_at(2) == Ok(36_691)
  assert spell4_id_at(-1) == Ok(34_718)
    as "0x1403bfd60: the index -1 casts the spell itself"
  assert spell4_id_at(3) == Error(Nil)
    as "0x1403bfd60: past the last row the press is refused 4"
}

pub fn a_cost_in_a_stage_row_gives_the_result_of_its_vital_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let costly =
    list.map(rows.spell4_thresholds, fn(row) {
      case row {
        [planted_table.Integer(124), ..] ->
          spell_tables.threshold_row(
            id: 124,
            parent: 34_718,
            to_cast: 36_691,
            order: 2,
            duration: 1400,
            cost: #(15, 5),
          )
        _ -> row
      }
    })
  let result =
    spell_tables.with_loaded(
      rows: spell_tables.Rows(..rows, spell4_thresholds: costly),
      body: fn(tables) { spell_plan.build(tables:) },
    )
  let assert Ok(plans) = result as "the planted rows build"
  let assert Ok(charged_shot) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(20_684))
  let assert Ok(last) = spell_plan.stage_at(spell: charged_shot, index: 2)
  assert last.unpayable_cost == Some(167)
    as "Spell4CastResult.vital_cost: a cost of 5 in vital 15 (Focus) of a unit that holds none gives 167; row 124's own value is 0, which passes"
  assert list.all(planted(base: 20_684).stages, fn(stage) {
    stage.spell.unpayable_cost == None
  })
    as "Spell4Thresholds 124 holds Focus with the value 0"
}

pub fn the_phases_channel_and_threshold_of_each_method_are_read_from_the_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  let pulse_blast = planted(base: 26_468)
  assert pulse_blast.method == Multiphase
  assert spell_plan.go_times_ms(spell: pulse_blast) == [0, 1250]
    as "SpellPhase 5390 and 5391: delays 0 and 1250 (the running sum)"
  assert pulse_blast.cooldown_start == AtLastGo
    as "SpellPhase 5391: phaseFlags 0x200, so the cooldown starts at the last phase (0x14053e5a0)"
  let quick_draw = planted(base: 27_638)
  assert spell_plan.go_times_ms(spell: quick_draw) == [0, 366, 566, 766, 1000]
    as "SpellPhase 5882 to 5886: delays 0, 366, 200, 200 and 234"
  assert quick_draw.cooldown_start == AtLastGo
    as "SpellPhase 5883: phaseFlags 0x200"
  assert quick_draw.channel == None
    as "Spell4.43468: the channel columns hold values, but only a Channeled spell keeps them (Spell4.channelPulseTime)"
  assert list.all(quick_draw.proxies, fn(proxy) {
    case proxy.condition {
      spell_plan.NeedsPrerequisite(..) -> True
      Always -> False
    }
  })
    as "Spell4Effects 196513 to 196522: every Proxy of Quick Draw sits behind prerequisite 17301 or 17302"
  assert planted(base: 23_161).cooldown_start == AtFirstGo
    as "SpellPhase 3715 and 3716: flags 0 and 0x180, no 0x200"
  let discharge = planted(base: 38_201)
  assert discharge.method == Channeled
  assert discharge.channel
    == Some(Channel(
      initial_delay_ms: 410,
      max_time_ms: 1250,
      pulse_time_ms: 410,
    ))
    as "Spell4.58832: channelInitialDelay 410, channelMaxTime 1250, channelPulseTime 410"
  assert discharge.cooldown_start == AtLastGo
    as "0x14053e5a0: a channel's cooldown starts at the go that reaches the count"
  assert planted(base: 23_148).threshold_ms == 4000
    as "Spell4.38765: thresholdTime 4000"
  assert planted(base: 23_148).cooldown_start == NotAtAGo
    as "0x14053e5a0: a RapidTap go starts no cooldown"
  assert planted(base: 20_684).method == ChargeRelease
  assert planted(base: 20_684).threshold_ms == 8200
    as "Spell4.34718: thresholdTime 8200"
  assert spell_plan.go_times_ms(spell: planted(base: 20_684)) == []
    as "cast.charge_release_base: the base cast of Charged Shot has no go before its 0x7fe"
}

pub fn a_channels_gos_fall_at_the_initial_delay_plus_each_pulse_and_its_finish_at_the_max_time_test() -> Nil {
  use <- owned_test.run(60_000)
  let discharge = planted(base: 38_201)
  assert spell_plan.go_times_ms(spell: discharge) == [410, 820, 1230]
    as "Spell4.58832: (1250 - 410 + 410) / 410 = 3 gos (0x14053d1f0), at the initial delay plus each pulse (the times are a server choice)"
  assert spell_plan.finish_after_ms(spell: discharge) == Some(1250)
    as "the channel ends at channelMaxTime, after its last pulse at 1230"
  let electrocute = planted(base: 25_473)
  assert spell_plan.go_times_ms(spell: electrocute)
    == [500, 1000, 1500, 2000, 2500, 3000]
    as "Spell4.41276: (3000 - 500 + 500) / 500 = 6 gos"
  assert spell_plan.finish_after_ms(spell: electrocute) == None
    as "its last pulse is at channelMaxTime, so the finish comes with it"
}

pub fn a_channels_gos_number_the_formula_of_the_client_and_stay_within_its_max_time_test() -> Nil {
  use <- owned_test.run(60_000)
  use #(initial, extra, pulse) <- qcheck.given(qcheck.tuple3(
    qcheck.bounded_int(from: 0, to: 3000),
    qcheck.bounded_int(from: 0, to: 10_000),
    qcheck.bounded_int(from: 1, to: 2000),
  ))
  let max = initial + extra
  let times =
    spell_plan.channel_go_times_ms(Channel(
      initial_delay_ms: initial,
      max_time_ms: max,
      pulse_time_ms: pulse,
    ))
  assert list.length(times) == { max - initial + pulse } / pulse
    as "0x14053d1f0: (channelMaxTime - channelInitialDelay + channelPulseTime) / channelPulseTime, in whole numbers"
  assert list.first(times) == Ok(initial)
    as "the first pulse is at the initial delay"
  let assert Ok(last) = list.last(times)
  assert last <= max && last + pulse > max
    as "the last pulse is within the max time and the next would pass it"
  assert list.window_by_2(times)
    |> list.all(fn(pair) { pair.1 - pair.0 == pulse })
    as "the pulses are one pulse time apart"
}

pub fn a_channeled_spell_with_no_pulse_time_fails_the_load_naming_the_spell_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let no_pulse =
    list.map(rows.spell4, fn(row) {
      case row {
        [planted_table.Integer(58_832), ..] ->
          spell_tables.method_spell_row(
            id: 58_832,
            base: 38_201,
            cast_time: 0,
            cooldown: 0,
            kind: 0,
            global: 159,
            cost: #(0, 0),
            more: [
              #("channelInitialDelay", 410),
              #("channelMaxTime", 1250),
              #("channelPulseTime", 0),
            ],
          )
        _ -> row
      }
    })
  let assert Error(error) =
    spell_tables.derivation_result(
      rows: spell_tables.Rows(..rows, spell4: no_pulse),
    )
    as "a pulse time of 0 gives no count of gos (0x14053d1f0), so the load fails"
  assert string.contains(table_store.describe(error), "58832")
}

pub fn the_costs_of_impale_and_electrocute_give_the_results_of_their_vital_slots_test() -> Nil {
  use <- owned_test.run(60_000)
  assert planted(base: 23_161).unpayable_cost == Some(53)
    as "Spell4.38779: an innate cost of type 8 (Resource3) of 35 gives 53"
  assert planted(base: 25_473).unpayable_cost == Some(51)
    as "Spell4.41276: type 6 (Resource1) of 8 gives 51"
}

pub fn the_cast_bar_of_each_method_follows_what_the_client_shows_test() -> Nil {
  use <- owned_test.run(60_000)
  let shows = fn(base, pressed) {
    spell_plan.shows_cast_bar(spell: planted(base:), pressed:)
  }
  assert shows(26_468, True)
    && shows(27_638, True)
    && shows(38_201, True)
    && shows(25_473, True)
    && shows(20_684, True)
    as "cast.current_cast: Multiphase with a cast time or castBarType, Channeled with a castBarType, ChargeRelease with a thresholdTime"
  assert !shows(23_161, True)
    && !shows(23_148, True)
    && !shows(18_309, True)
    && !shows(37_968, True)
    as "cast.current_cast: Impale (Multiphase, no cast time, castBarType 0) and the three RapidTap abilities (no cast time) show none"
  let assert [stage] = planted(base: 23_148).stages
  assert !spell_plan.shows_cast_bar(spell: stage.spell, pressed: False)
    as "a RapidTap stage has no cast time"
  let channeled_without_bar =
    spell_plan.Spell(
      ..planted(base: 38_201),
      cast_bar: spell_plan.ShowsWhenPressed,
    )
  assert spell_plan.shows_cast_bar(spell: channeled_without_bar, pressed: True)
    && !spell_plan.shows_cast_bar(spell: channeled_without_bar, pressed: False)
    as "cast.current_cast: a Channeled spell with no castBarType shows the bar when it is the pressed spell itself"
}

pub fn every_ability_of_the_clients_tables_builds_and_each_spell_shows_the_cast_bar_its_method_gives_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let plans = spell_plan.plans(tables:)
  let ability = fn(base) {
    let assert Ok(spell) = spell_plan.in_plans(plans:, base: Spell4BaseId(base))
      as { "the plan holds the ability " <> int.to_string(base) }
    spell
  }
  list.each(
    [
      #(26_468, 42_276),
      #(27_638, 43_468),
      #(38_201, 58_832),
      #(25_473, 41_276),
      #(20_684, 34_718),
    ],
    fn(pair) {
      assert spell_plan.shows_cast_bar(spell: ability(pair.0), pressed: True)
        as {
          "cast.current_cast: the ability "
          <> int.to_string(pair.1)
          <> " shows its cast bar"
        }
      assert ability(pair.0).spell4_id == Spell4Id(pair.1)
    },
  )
  list.each(
    [#(23_161, 38_779), #(23_148, 38_765), #(18_309, 32_078), #(37_968, 58_524)],
    fn(pair) {
      assert !spell_plan.shows_cast_bar(spell: ability(pair.0), pressed: True)
        as {
          "cast.current_cast: the ability "
          <> int.to_string(pair.1)
          <> " shows no cast bar"
        }
      assert ability(pair.0).spell4_id == Spell4Id(pair.1)
    },
  )
  let stages_of_all =
    list.flat_map([23_148, 18_309, 37_968, 20_684], fn(base) {
      list.map(ability(base).stages, fn(stage) { stage.spell })
    })
  assert list.map(stages_of_all, fn(spell) { spell.spell4_id.value })
    == [38_766, 32_079, 32_080, 66_987, 71_125, 71_126, 34_720, 34_722, 36_691]
    as "Spell4Thresholds.spell4IdToCast: Shred, Relentless Strikes, Rampage and Charged Shot, each in orderIndex order"
  assert list.all(stages_of_all, fn(spell) {
    !spell_plan.shows_cast_bar(spell:, pressed: False)
  })
    as "cast.current_cast: the stages have a thresholdTime and a cast time of 0"
  assert list.map(ability(20_684).stages, fn(stage) { stage.duration_ms })
    == [0, 1000, 1400]
    as "Spell4Thresholds 125, 123 and 124: thresholdDuration 0, 1000 and 1400"
  let assert [pulse_blast_child] =
    list.map(ability(26_468).proxies, fn(proxy) { proxy.spell })
    as "Spell4Effects 95881: Pulse Blast proxies 37302"
  assert pulse_blast_child.spell4_id == Spell4Id(37_302)
    && spell_plan.shows_cast_bar(spell: pulse_blast_child, pressed: False)
    as "Spell4Base 22522: Multiphase with castBarType 1"
  let assert [shred_child] =
    list.map(ability(23_148).proxies, fn(proxy) { proxy.spell })
    as "Spell4Effects 83776: Shred proxies 38767"
  assert shred_child.spell4_id == Spell4Id(38_767)
    && !spell_plan.shows_cast_bar(spell: shred_child, pressed: False)
    as "Spell4Base 23150: Multiphase, castBarType 0, cast time 0"
  let assert [shred_stage] = ability(23_148).stages
  let assert [stage_child] = shred_stage.spell.proxies
  assert stage_child.spell.spell4_id == Spell4Id(39_467)
    && !spell_plan.shows_cast_bar(spell: stage_child.spell, pressed: False)
    as "Spell4Base 23799: Multiphase, castBarType 0, cast time 0"
}
