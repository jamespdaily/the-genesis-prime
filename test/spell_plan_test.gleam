//// The tree of casts each class's level-1 ability starts (`genesis_prime/game/spell_plan`).
//// Expected values come from the client's rows, which the fact file records and
//// `table_rows` prints, each named at the assertion: `Spell4.32893` (Telekinetic
//// Strike), `Spell4.32812` (Crush), `Spell4.38791` (Stagger), `Spell4.29874` and
//// `Spell4.32809` with `Spell4CastResult.vital_cost` (the short vitals),
//// `Spell4Effects.effectType.26` (a Proxy starts a spell),
//// `SpellPhase.phaseDelay` with `0x14055e180` (the phases), `0x14046afc0` and
//// `0x1403b14c0` (the global cooldown) and `Spell.CodeEnumCastMethod`. The
//// planted tables hold those rows (`spell_tables`); the real tables are read
//// where the client is present. A missing row and a cycle are planted.

import client_tables
import genesis_prime/game/loadout
import genesis_prime/game/spell_plan.{
  type Spell, Always, GlobalCooldown, Normal, PrimaryWeapon,
}
import genesis_prime/table/id.{ClassId, Spell4BaseId, Spell4Id}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import spell_tables
import unitest

fn planted(base base: Int) -> Spell {
  spell_tables.with_loaded(rows: spell_tables.rows(), body: fn(tables) {
    let assert Ok(plans) = spell_plan.build(tables:) as "the planted rows build"
    let assert Ok(spell) = spell_plan.in_plans(plans:, base: Spell4BaseId(base))
      as "the planted class holds the ability"
    spell
  })
}

pub fn telekinetic_strike_takes_1250_ms_has_a_global_cooldown_of_1000_ms_that_blocks_and_one_child_on_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  let spell = planted(base: 19_102)
  assert spell.spell4_id == Spell4Id(32_893)
  assert spell.method == Normal
    as "Spell.CodeEnumCastMethod 0, Spell4Base 19102"
  assert spell.cast_time_ms == 1250 as "Spell4.32893: castTime 1250"
  assert spell.cooldown_ms == 0 as "Spell4.32893: no cooldown of its own"
  assert spell.cast_bar
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
  assert !staggering.spell.cast_bar
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

pub fn a_cycle_of_proxies_fails_the_build_naming_the_spells_on_the_way_test() -> Nil {
  use <- owned_test.run(60_000)
  let rows = spell_tables.rows()
  let result =
    spell_tables.with_loaded(
      rows: spell_tables.Rows(..rows, spell4_effects: [
        spell_tables.effect_row(
          id: 99_001,
          spell: 30_900,
          type_: 26,
          target_flags: 1,
          delay: 0,
          phases: -1,
          data: 32_893,
        ),
        ..rows.spell4_effects
      ]),
      body: fn(tables) { spell_plan.build(tables:) },
    )
  assert result == Error(spell_plan.ProxyCycle(chain: [32_893, 30_900, 32_893]))
    as "Telekinetic Strike proxies 30900, which proxies Telekinetic Strike: the chain from the pressed ability to the spell that repeats"
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
    spell4: spell_tables.without(rows: rows.spell4, ids:),
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
