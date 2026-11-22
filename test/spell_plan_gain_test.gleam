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
//// - `Spell4Effects.dataBits05`: a Focus gain with a dataBits02 of 0 holds a share of the
////   maximum Focus as a float (Meditate's row 65493: 0.04, text 243889 "Restore 4% of your
////   maximum Focus"; Recharge's four rows 228352, 228357, 228361 and 228363: 0.05 to 0.20
////   per Actuator held, text 383170 "restore ... of your maximum Focus per Actuator", each
////   behind the Prerequisite that picks the Actuator count: 43658, 43659, 43660 and
////   29891); a dataBits02 holds points (Rations' row 88371: 80 in dataBits01 and dataBits02,
////   which text 270070 prints as "... Focus every second while channeling"); 88544 holds
////   1.0, 86177 100.0 ("Full Heal") and 161906 holds no amount.
//// - `Spell4Effects.effectType.26.dataBits06`: five level-1 Proxies name a
////   Prerequisite in dataBits06, which gates them against the caster.
//// - The design of issue 418: a gain of a child started at each struck unit is
////   given once per go of its parent, so the plan moves it onto the Proxy.

import client_tables
import fixture_tables
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{
  type Gain, type Gift, type Proxy, type Spell, ClassVitalPoints, FocusPoints,
  FocusShare, Gain, TickingGain,
}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/loader/store as table_store
import gleam/dict
import gleam/float
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
  let prerequisite_id = case gain.condition {
    spell_plan.GatedOnCaster(gates: [prerequisite, ..]) ->
      Some(prerequisite.id(prerequisite:).value)
    spell_plan.GatedOnCaster(gates: [])
    | spell_plan.Always
    | spell_plan.GatedOnTarget(..)
    | spell_plan.GatedOnCasterAndTarget(..) -> None
  }
  let ticking = case gain {
    Gain(..) -> None
    TickingGain(tick_ms:, duration_ms:, ..) -> Some(#(tick_ms, duration_ms))
  }
  let assert spell_plan.SlotPoints(slot:, points:) = gain.gift
    as "these rows give the points of vital 6, a resource slot"
  #(
    gain.effect_id.value,
    slot,
    points,
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
    spell_plan.Always
    | spell_plan.GatedOnTarget(..)
    | spell_plan.GatedOnCasterAndTarget(..) -> Error(Nil)
  }
}

/// Every Proxy in the spell's tree, its stages' trees among them.
fn proxies_in(spell: Spell) -> List(Proxy) {
  list.flat_map(spell_plan.tree(spell:, started: fn(_) { True }), fn(below) {
    spell_plan.payloads(spell: below, as_kind: spell_plan.as_proxy)
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
      plans: spell_tables.fixture_plans(),
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
    assert spell_plan.payloads(spell: proxy.spell, as_kind: spell_plan.as_gain)
      == []
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
  assert spell_plan.payloads(spell: proxy.spell, as_kind: spell_plan.as_gain)
    == []
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
      plans: spell_tables.fixture_plans(),
      base: Spell4BaseId(46_615),
    )
  assert list.map(
      spell_plan.payloads(spell: energize, as_kind: spell_plan.as_gain),
      read,
    )
    == [
      #(228_910, 1, 4, -1, Some(43_811), None),
      #(228_918, 1, 1, -1, Some(43_812), Some(#(2000, 8000))),
    ]
    as "Spell4Effects 228910 (+4 of vital 6, behind 43811) and 228918 (+1 each tickTime 2000 for durationTime 8000, behind 43812), in every phase"
}

// ---- 18 ----

fn load_reason(effect: List(planted_table.Cell)) -> String {
  let rows = spell_tables.fixture_rows()
  let assert Error(error) =
    spell_tables.derivation_result(
      reaching: [#("SpellLevel", 647)],
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
  let rows = spell_tables.fixture_rows()
  let assert Ok(_) =
    spell_tables.derivation_result(
      reaching: [#("SpellLevel", 647)],
      rows: spell_tables.Rows(
        ..rows,
        spell4_effects: spell_tables.sorted_by_id([
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
          ..rows.spell4_effects
        ]),
      ),
    )
    as "a gain aimed at the caster behind a target apply prerequisite loads: its gate is read on the caster"
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
    True ->
      list.map(
        spell_plan.payloads(spell:, as_kind: spell_plan.as_gain),
        fn(gain) { #(True, gain.phase_flags) },
      )
    False -> []
  }
  let below =
    list.flat_map(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_proxy),
      fn(proxy) {
        let each_struck = under || proxy.target == spell_plan.OnEachStruck
        list.append(
          list.map(proxy.gains, fn(gain) { #(under, gain.phase_flags) }),
          gains_under_each_struck(spell: proxy.spell, under: each_struck),
        )
      },
    )
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

// ---- Focus and class vital gains ----

/// The effect id and gift of each gain of the spell's own list, in the plan's order.
fn gifts_of(spell: Spell) -> List(#(Int, Gift)) {
  list.map(spell_plan.payloads(spell:, as_kind: spell_plan.as_gain), fn(gain) {
    #(gain.effect_id.value, gain.gift)
  })
}

/// The caster gate of each gain of the spell's own list, in the plan's order.
fn gates_of(spell: Spell) -> List(Option(Int)) {
  list.map(spell_plan.payloads(spell:, as_kind: spell_plan.as_gain), fn(gain) {
    case gain.condition {
      spell_plan.GatedOnCaster(gates: [gate, ..]) ->
        Some(prerequisite.id(prerequisite: gate).value)
      spell_plan.GatedOnCaster(gates: [])
      | spell_plan.Always
      | spell_plan.GatedOnTarget(..)
      | spell_plan.GatedOnCasterAndTarget(..) -> None
    }
  })
}

/// Whether a gift is the expected one; a share is a 32-bit float of the column, so it is
/// compared to the decimal the client's text prints, within 1e-6.
fn is_gift(gift: Gift, expected: Gift) -> Bool {
  case gift, expected {
    FocusShare(share: got), FocusShare(share: wanted) ->
      float.loosely_equals(got, wanted, tolerating: 1.0e-6)
    _, _ -> gift == expected
  }
}

fn planned_on(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Spell, spell_plan.PlanError) {
  spell_plan.spell_alone(
    tables:,
    sources: spell_plan.sources_of(tables:),
    spell4_id:,
    chain: [],
  )
}

fn cell(number: Int) -> planted_table.Cell {
  planted_table.Integer(number)
}

pub fn a_focus_gain_reads_points_a_share_up_to_1_and_refuses_a_larger_share_or_a_class_vital_share_by_name_test() -> Nil {
  use <- owned_test.run(60_000)
  // (spell, row, gift, why): a dataBits02 other than 0 is points, a dataBits02 of 0 with a
  // dataBits05 in (0, 1.0] a share of the maximum, neither no points.
  list.each(
    [
      #(
        34_776,
        88_371,
        FocusPoints(80),
        "Rations: dataBits02 80, as text 270070 prints it",
      ),
      #(
        32_818,
        65_493,
        FocusShare(0.04),
        "Meditate: dataBits05 0.04 of the maximum, text 243889",
      ),
      #(
        64_945,
        161_906,
        FocusPoints(0),
        "no dataBits02 and no dataBits05: 0 points",
      ),
    ],
    fn(row) {
      let #(spell4_id, effect_id, expected, why) = row
      let assert Ok(spell) =
        planned_on(tables: fixture_tables.shared(), spell4_id:)
        as why
      let assert Ok(gift) = list.key_find(gifts_of(spell), effect_id) as why
      assert is_gift(gift, expected) as why
    },
  )
  // The rows of 1.0 (88544 and 101844, "Refill Resources") are in spells that also hold a
  // vital 9 row, which the plan refuses, so Rations' 88371 is edited to hold 1.0: the whole
  // maximum.
  let assert Ok(whole) =
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 88_371,
      with: [#("dataBits02", cell(0)), #("dataBits05", cell(1_065_353_216))],
      body: fn(edited) { planned_on(tables: edited, spell4_id: 34_776) },
    )
    as "Rations with a share of 1.0 plans"
  assert list.key_find(gifts_of(whole), 88_371) == Ok(FocusShare(1.0))
    as "dataBits05 1.0 is the whole maximum"
  // A share above 1.0 is not read: rows 86177, 105624, 175652, 175666 and 175671 hold 100.0
  // or 10.0 ("Full Heal", "10% Heal"), and clamping them would read a name that says 100
  // times as the whole. Their spells hold other rows the plan refuses, so Rations' 88371 is
  // edited to 100.0.
  let refused =
    fixture_tables.changed(
      table: "Spell4Effects",
      id: 88_371,
      with: [#("dataBits02", cell(0)), #("dataBits05", cell(1_120_403_456))],
      body: fn(edited) { planned_on(tables: edited, spell4_id: 34_776) },
    )
  let assert Error(error) = refused as "a share of 100.0 is refused"
  let text = spell_plan.describe(error:)
  assert string.contains(text, "34776") && string.contains(text, "88371")
    as "the refusal names the spell and the row"
  assert spell_plan.is_unbuilt(error:)
    as "a later ability with such a row is left out of the plans, not a failed load"
  // No client row holds a share on a class vital, so Recharge's -4 of vital 18 is edited to
  // dataBits02 0 and dataBits05 0.05.
  use edited <- fixture_tables.changed(
    table: "Spell4Effects",
    id: 228_362,
    with: [
      #("dataBits02", cell(0)),
      #("dataBits05", cell(1_028_443_341)),
    ],
  )
  assert planned_on(tables: edited, spell4_id: 42_596)
    == Error(spell_plan.GainShareNotRead(
      spell4_id: 42_596,
      effect_id: 228_362,
      vital: 18,
      data_bits05: 1_028_443_341,
    ))
    as "a share of a class vital's maximum is refused by name"
}

pub fn recharge_plans_four_focus_shares_behind_the_actuator_counts_and_its_vital_18_rows_in_row_order_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = fixture_tables.shared()
  let assert Ok(recharge) = planned_on(tables:, spell4_id: 42_596)
    as "Recharge plans"
  let first = gifts_of(recharge)
  assert list.map(first, fn(gain) { gain.0 })
    == [228_352, 228_357, 228_361, 228_363, 228_362]
    as "orderIndex 1, 2, 3, 4 and 6: the four shares, then the cost of the Actuators"
  assert list.zip(list.map(first, fn(gain) { gain.1 }), [
      FocusShare(0.05),
      FocusShare(0.1),
      FocusShare(0.15),
      FocusShare(0.2),
      ClassVitalPoints(vital: 18, points: -4),
    ])
    |> list.all(fn(pair) { is_gift(pair.0, pair.1) })
    as "dataBits05 0.05, 0.10, 0.15 and 0.20 per the text 383170, and dataBits02 -4 of vital 18"
  assert gates_of(recharge)
    == [Some(43_658), Some(43_659), Some(43_660), Some(29_891), None]
    as "each share is behind the Prerequisite that counts the Actuators: 43658 to 43660 (type 73 of vital 6 equal to 1, 2, 3) and 29891 (at least 4)"
  let assert Ok(tier) = planned_on(tables:, spell4_id: 59_885)
    as "tier 59885 plans"
  assert list.map(gifts_of(tier), fn(gain) { gain.0 })
    == [228_368, 228_376, 228_384, 228_392, 228_400, 228_405]
    as "the cost of 4 (228400, orderIndex 4) comes before the +2 (228405, orderIndex 5)"
  assert list.drop(gifts_of(tier), 4)
    == [
      #(228_400, ClassVitalPoints(vital: 18, points: -4)),
      #(228_405, ClassVitalPoints(vital: 18, points: 2)),
    ]
  let assert Ok(unplanned) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
    as "the fixture's plans build"
  assert list.filter(unplanned, fn(left_out) {
      left_out.spell4_id == 32_818 || left_out.spell4_id == 42_596
    })
    == []
    as "Meditate (Esper level 24) and Recharge (Medic level 14) are planned, not left out"
}

pub fn each_recharge_tier_gives_the_actuator_count_times_its_per_actuator_share_test() -> Nil {
  use <- owned_test.run(60_000)
  // Texts 383170 and 513199: "restore X of your maximum Focus per Actuator", so the row for
  // 2, 3 and 4 Actuators holds 2, 3 and 4 times the row for 1.
  list.each(
    [42_596, 59_882, 59_883, 59_884, 59_885, 59_886, 59_887, 59_888, 59_889],
    fn(spell4_id) {
      let assert Ok(spell) =
        planned_on(tables: fixture_tables.shared(), spell4_id:)
        as "the tier plans"
      let shares =
        list.filter_map(gifts_of(spell), fn(gain) {
          case gain.1 {
            FocusShare(share:) -> Ok(share)
            FocusPoints(..)
            | ClassVitalPoints(..)
            | spell_plan.SlotPoints(..) -> Error(Nil)
          }
        })
      let assert [one, two, three, four] = shares
        as "four shares, for 1 to 4 Actuators"
      let why = "tier " <> int.to_string(spell4_id)
      assert float.loosely_equals(two, 2.0 *. one, tolerating: 1.0e-6) as why
      assert float.loosely_equals(three, 3.0 *. one, tolerating: 1.0e-6) as why
      assert float.loosely_equals(four, 4.0 *. one, tolerating: 1.0e-6) as why
    },
  )
}

pub fn a_gain_of_a_class_vital_plans_as_that_vital_for_4_12_13_14_18_and_19_and_one_of_vital_7_still_fails_the_load_test() -> Nil {
  use <- owned_test.run(60_000)
  // 0x1405e7980 takes these vitals for a class cost; no client row holds a non-ticking
  // caster gain of 4, 12, 13 or 14, so Recharge's -4 (row 228362, vital 18) is edited to each.
  list.each([4, 12, 13, 14, 18, 19], fn(vital) {
    use edited <- fixture_tables.changed(
      table: "Spell4Effects",
      id: 228_362,
      with: [#("dataBits00", cell(vital))],
    )
    let assert Ok(spell) = planned_on(tables: edited, spell4_id: 42_596)
      as { "vital " <> int.to_string(vital) <> " plans" }
    assert list.key_find(gifts_of(spell), 228_362)
      == Ok(ClassVitalPoints(vital:, points: -4))
      as { "vital " <> int.to_string(vital) <> " of -4 is that class vital's" }
  })
  // The Spellslinger's vital 19 (Class.vitalEnumResource04) as the client holds it: row 68677
  // of 34629 gives +100.
  let assert Ok(boost) =
    planned_on(tables: fixture_tables.shared(), spell4_id: 34_629)
    as "34629 plans"
  assert list.key_find(gifts_of(boost), 68_677)
    == Ok(ClassVitalPoints(vital: 19, points: 100))
    as "Spell4Effects 68677 is +100 of vital 19"
  use edited <- fixture_tables.changed(
    table: "Spell4Effects",
    id: 228_362,
    with: [#("dataBits00", cell(7))],
  )
  let assert Error(refused) = planned_on(tables: edited, spell4_id: 42_596)
    as "vital 7 is not read"
  assert refused
    == spell_plan.GainVitalNotRead(
      spell4_id: 42_596,
      effect_id: 228_362,
      vital: 7,
    )
    as "the refusal names the vital"
}
