//// The resource gains of the plan (`genesis_prime/game/spell_plan` `Gain`) and the
//// Proxies it keeps behind a prerequisite. Expected values come from the client's
//// rows, which `spell_tables` plants as `table_rows` prints them and the real tables
//// hold where the client is present:
//// - `Spell4Effects.effectType.1`: a VitalModifier's dataBits00 is the vital (6 is
////   slot 1), dataBits02 the amount; 127603 (+180, behind 24581) and 147972 (+200,
////   behind 24582) in 53865, which Relentless Strikes' stage spells 70033, 70045
////   and 70054 proxy at the area (targetFlags 4: Proxies 177057, 177099 and
////   177122); 56858 (+1, no prerequisite) in 30900, which Telekinetic Strike's
////   Proxy 62204 starts at the area; 228910 (+4 behind 43811) and 228918 (+1 every
////   2000 ms for 8000 ms, behind 43812) in Energize 69450, on the caster.
//// - `Spell4Effects.effectType.26.dataBits06`: five level-1 Proxies name a
////   Prerequisite in dataBits06, which gates them against the caster.
//// - The design of issue 418: a gain of a child started at each struck unit is
////   given once per go of its parent, so the plan moves it onto the Proxy.

import client_tables
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type Gain, type Proxy, type Spell, Gain, TickingGain,
}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/loader/store as table_store
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import owned_test
import planted_table
import spell_tables
import unitest

/// A gain as (effect id, slot, amount, phase flags, prerequisite id), with the tick
/// and duration of a ticking one.
fn read(gain: Gain) -> #(Int, Int, Int, Int, Option(Int), Option(#(Int, Int))) {
  let prerequisite_id =
    option.map(gain.prerequisite, fn(prerequisite) {
      prerequisite.id(prerequisite:).value
    })
  let ticking = case gain {
    Gain(..) -> None
    TickingGain(tick_ms:, duration_ms:, ..) -> Some(#(tick_ms, duration_ms))
  }
  #(
    gain.effect_id.value,
    gain.slot,
    gain.amount,
    gain.phase_flags,
    prerequisite_id,
    ticking,
  )
}

/// The Prerequisite ids a Proxy is gated on against the caster, in order; `Error`
/// for a Proxy with no such gate.
fn caster_gates(proxy: Proxy) -> Result(List(Int), Nil) {
  case proxy.condition {
    spell_plan.GatedOnCaster(gates:) ->
      Ok(
        list.map(gates, fn(gate) { prerequisite.id(prerequisite: gate).value }),
      )
    spell_plan.Always | spell_plan.GatedOnTarget(..) -> Error(Nil)
  }
}

/// Every Proxy in the spell's tree, its stages' trees among them.
fn proxies_in(spell: Spell) -> List(Proxy) {
  list.flat_map(spell_plan.tree(spell:, started: fn(_) { True }), fn(below) {
    below.proxies
  })
}

/// The Proxies of the effect id in the ability's tree.
fn proxies_of(ability: Spell, effect_id: Int) -> List(Proxy) {
  list.filter(proxies_in(ability), fn(proxy) {
    proxy.effect_id == Spell4EffectsId(effect_id)
  })
}

fn planted(base: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_tables.default_plans(),
      base: Spell4BaseId(base),
    )
    as "the planted class holds the ability"
  spell
}

/// Relentless Strikes (Spell4Base 18309).
const relentless_strikes = 18_309

/// Telekinetic Strike (Spell4Base 19102).
const telekinetic_strike = 19_102

fn relentless_strikes_gains_are_on_the_proxy(ability: Spell) -> Nil {
  let proxies =
    list.flat_map([177_057, 177_099, 177_122], fn(id) {
      proxies_of(ability, id)
    })
  assert list.length(proxies) == 3
    as "each stage spell, 70033, 70045 and 70054, proxies 53865 at the area"
  list.each(proxies, fn(proxy) {
    assert proxy.target == spell_plan.OnEachStruck
      as "targetFlags 4: one child for each struck unit"
    assert list.map(proxy.gains, read)
      == [
        #(127_603, 1, 180, 1, Some(24_581), None),
        #(147_972, 1, 200, 1, Some(24_582), None),
      ]
      as "Spell4Effects 127603 and 147972: vital 6 (slot 1), dataBits02 180 and 200, phase 1, behind 24581 and 24582, moved onto the Proxy"
    assert proxy.spell.spell4_id.value == 53_865
    assert proxy.spell.gains == []
      as "the child 53865 under the Proxy keeps none: once per go, not per foe (issue 418)"
  })
}

// ---- 15 ----

pub fn relentless_strikes_proxies_to_53865_carry_its_gains_and_the_child_none_test() -> Nil {
  use <- owned_test.run(60_000)
  relentless_strikes_gains_are_on_the_proxy(planted(relentless_strikes))
}

// ---- 16 ----

fn telekinetic_strikes_gain_is_on_the_proxy(ability: Spell) -> Nil {
  let assert [proxy] = proxies_of(ability, 62_204)
    as "Telekinetic Strike's Proxy 62204"
  assert proxy.target == spell_plan.OnEachStruck
  assert list.map(proxy.gains, read) == [#(56_858, 1, 1, 1, None, None)]
    as "Spell4Effects 56858: +1 of vital 6 (slot 1), phase 1, no prerequisite"
  assert proxy.spell.gains == []
}

pub fn telekinetic_strikes_proxy_to_30900_carries_its_psi_point_test() -> Nil {
  use <- owned_test.run(60_000)
  telekinetic_strikes_gain_is_on_the_proxy(planted(telekinetic_strike))
}

pub fn the_clients_tables_give_the_same_gains_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  let assert Ok(relentless) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(relentless_strikes))
  relentless_strikes_gains_are_on_the_proxy(relentless)
  let assert Ok(strike) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(telekinetic_strike))
  telekinetic_strikes_gain_is_on_the_proxy(strike)
}

// ---- 17 ----

pub fn energize_holds_its_plus_4_and_its_ticking_gain_on_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert Ok(energize) =
    spell_plan.in_plans(
      plans: spell_tables.plans_with_energize(),
      base: Spell4BaseId(46_615),
    )
  assert list.map(energize.gains, read)
    == [
      #(228_910, 1, 4, -1, Some(43_811), None),
      #(228_918, 1, 1, -1, Some(43_812), Some(#(2000, 8000))),
    ]
    as "Spell4Effects 228910 (+4 of vital 6, behind 43811) and 228918 (+1 each tickTime 2000 for durationTime 8000, behind 43812), in every phase"
}

// ---- 18 ----

fn load_reason(effect: List(planted_table.Cell)) -> String {
  let rows = spell_tables.rows()
  let assert Error(error) =
    spell_tables.derivation_result(
      rows: spell_tables.Rows(
        ..rows,
        spell4_effects: spell_tables.sorted_by_id([
          effect,
          ..rows.spell4_effects
        ]),
      ),
    )
    as "the load fails"
  table_store.describe(error)
}

pub fn a_gain_aimed_other_than_at_the_caster_or_of_an_unread_vital_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  let aimed =
    load_reason(
      spell_tables.vital_modifier_row_with(
        id: 99_418,
        spell: 30_900,
        vital: 6,
        amount: 1,
        delay: 0,
        phases: 1,
        prerequisite: 0,
        order: 5,
        more: [#("targetFlags", 4)],
      ),
    )
  assert string.contains(aimed, "30900")
    && string.contains(aimed, "99418")
    && string.contains(aimed, "flags 4")
    as "a VitalModifier at the area of a level-1 tree is not read: the load names the spell, the effect and the flags"
  let vital =
    load_reason(spell_tables.vital_modifier_row(
      id: 99_419,
      spell: 30_900,
      vital: 7,
      amount: 1,
      delay: 0,
      phases: 1,
      prerequisite: 0,
      order: 5,
    ))
  assert string.contains(vital, "99419") && string.contains(vital, "vital 7")
    as "vital 7 is neither 6 (slot 1) nor 8 (slot 3): the load names it"
  let target =
    load_reason(
      spell_tables.vital_modifier_row_with(
        id: 99_420,
        spell: 30_900,
        vital: 6,
        amount: 1,
        delay: 0,
        phases: 1,
        prerequisite: 0,
        order: 5,
        more: [#("prerequisiteIdTargetApply", 24_581)],
      ),
    )
  assert string.contains(target, "99420")
    && string.contains(target, "target prerequisite")
    as "a target apply prerequisite on a gain is not read: the load names the effect"
  let missing =
    load_reason(spell_tables.vital_modifier_row(
      id: 99_421,
      spell: 30_900,
      vital: 6,
      amount: 1,
      delay: 0,
      phases: 1,
      prerequisite: 99_999,
      order: 5,
    ))
  assert string.contains(missing, "Prerequisite")
    && string.contains(missing, "99999")
    as "a gain behind a Prerequisite row the table lacks: the load names the table and the id"
}

// ---- the Proxies behind dataBits06 ----

pub fn a_proxy_whose_data_bits_06_names_a_prerequisite_is_kept_behind_it_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [proxy, ..] = proxies_of(planted(relentless_strikes), 177_873)
    as "53865's Proxy 177873 to 60947"
  assert caster_gates(proxy) == Ok([24_582])
    as "dataBits06 24582 gates the Proxy against the caster (Spell4Effects.effectType.26.dataBits06): it starts only when the prerequisite passes"
}

pub fn the_five_level_one_proxies_with_a_data_bits_06_are_each_behind_it_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  let every = list.flat_map(dict.values(plans), proxies_in)
  list.each(
    [
      #(177_873, 60_947, 24_582),
      #(135_961, 57_030, 23_344),
      #(200_542, 41_869, 35_913),
      #(212_835, 42_569, 33_154),
      #(212_838, 80_383, 32_921),
    ],
    fn(expected) {
      let #(effect_id, child, prerequisite_id) = expected
      let found =
        list.filter(every, fn(proxy) {
          proxy.effect_id == Spell4EffectsId(effect_id)
        })
      assert found != []
        as { "a level-1 tree holds Proxy " <> int.to_string(effect_id) }
      assert list.all(found, fn(proxy) {
        proxy.spell.spell4_id.value == child
        && caster_gates(proxy) == Ok([prerequisite_id])
      })
        as {
          "Proxy "
          <> int.to_string(effect_id)
          <> " to "
          <> int.to_string(child)
          <> " is behind its dataBits06 "
          <> int.to_string(prerequisite_id)
        }
    },
  )
}

/// Every gain a spell's tree holds under a Proxy aimed at each struck unit, as the
/// flags it fires in and whether it sits below a cast that is already started for
/// each struck unit: a gain lifted onto the Proxy is not below one, a gain left on
/// that cast or lifted from a Proxy under it is.
fn gains_under_each_struck(
  spell spell: Spell,
  under under: Bool,
) -> List(#(Bool, Int)) {
  let own = case under {
    True -> list.map(spell.gains, fn(gain) { #(True, gain.phase_flags) })
    False -> []
  }
  let below =
    list.flat_map(spell.proxies, fn(proxy) {
      let each_struck = under || proxy.target == spell_plan.OnEachStruck
      list.append(
        list.map(proxy.gains, fn(gain) { #(under, gain.phase_flags) }),
        gains_under_each_struck(spell: proxy.spell, under: each_struck),
      )
    })
  let staged =
    list.flat_map(spell.stages, fn(stage) {
      gains_under_each_struck(spell: stage.spell, under:)
    })
  list.flatten([own, below, staged])
}

pub fn every_gain_under_an_each_struck_proxy_is_in_phase_0_and_one_level_deep_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  let gains =
    list.flat_map(dict.values(plans), fn(spell) {
      gains_under_each_struck(spell:, under: False)
    })
  assert gains != []
    as "Relentless Strikes and Telekinetic Strike hold such gains"
  assert list.all(gains, fn(gain) { gain == #(False, 1) })
    as "Spell4Effects.phaseFlags of every VitalModifier under a Proxy aimed at each struck unit in the level-1 trees is 1 (phase 0), and none sits below a cast already started for each struck unit: lifting by phase 0 moves each whole, none is lost to a later phase, and none stays on a child that casts once per unit"
}
