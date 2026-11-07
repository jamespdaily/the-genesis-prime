//// A go's resource gains (`genesis_prime/game/cast` `Gain`). Expected values come
//// from these places, each named at its assertion:
//// - The client's rows the planted tables hold (`spell_tables`):
////   `Spell4Effects.effectType.1` (127603: +180 of slot 1 behind 24581; 147972:
////   +200 behind 24582; both in 53865, which the stage spells of Relentless Strikes
////   proxy at the area; 56858: +1 in 30900, which Telekinetic Strike's Proxy 62204
////   starts at the area; 228910: +4 behind 43811 and 228918, ticking, in Energize
////   69450), and the Prerequisite rows 24581, 24582 and 43811, read by
////   `Prerequisite.prerequisiteTypeId.15` and `Prerequisite.flags`.
//// - The design of issue 418: a gain is given once per go, not once per struck foe
////   (Jim, 2026-11-05), and a ticking gain is not applied.
//// The bag indices are `cast_support.abilities`'.

import cast_support as support
import class_resource_support
import genesis_prime/game/cast
import genesis_prime/game/class_resource.{Gain, Payment}
import genesis_prime/game/spell_plan.{Spell}
import genesis_prime/message/cast_result
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_started
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{Spell4BaseId, Spell4Id}
import gleam/list
import gleam/string
import owned_test
import spell_tables

/// Every effect of a press of the bag index at 1000 and of every timer it leads to,
/// each go striking `struck`.
fn pressed_through(
  plans plans: spell_plan.Plans,
  caster caster: cast.Caster,
  bag_index bag_index: Int,
  struck struck: List(cast.Struck),
) -> List(cast.Effect) {
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index:,
      target: 0,
      at: 1000,
    )
  let #(state, effects) =
    support.answered_by(state:, effects: raw, at: 1000, struck:)
  let #(_, fired) =
    support.run_timers_striking(state:, effects:, from_ms: 1000, struck:)
  list.append(effects, list.flat_map(fired, fn(step) { step.1 }))
}

/// The children of the spell started among the effects (0x7ff).
fn children_started(effects: List(cast.Effect), spell4_id: Int) -> Int {
  list.count(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(started) = spell_started.decode(frame.body)
          as "0x7ff decodes"
        started.spell4_id == spell4_id
      }
      False -> False
    }
  })
}

// ---- 19 ----

pub fn relentless_strikes_striking_3_foes_gives_180_once_and_starts_3_children_test() -> Nil {
  use <- owned_test.run(20_000)
  let effects =
    pressed_through(
      plans: support.plans(),
      caster: support.caster(),
      bag_index: support.relentless_strikes,
      struck: support.hits([10, 11, 12]),
    )
  assert support.gains(effects:) == [[Gain(slot: 1, amount: 180)]]
    as "one Gain of 180 to slot 1 for the go (127603, behind 24581, which passes with no Overdrive), not one per foe; 147972's 24582 needs 59208, which is not live"
  assert children_started(effects, 53_865) == 3
    as "Proxy 177057 (targetFlags 4) still starts 53865 on each of the 3 Hits"
}

// ---- 20 ----

pub fn relentless_strikes_with_only_deflects_or_no_foe_gives_nothing_test() -> Nil {
  use <- owned_test.run(20_000)
  let deflected =
    pressed_through(
      plans: support.plans(),
      caster: support.caster(),
      bag_index: support.relentless_strikes,
      struck: [cast.Deflected(unit_id: 10), cast.Deflected(unit_id: 11)],
    )
  assert support.gains(effects: deflected) == []
    as "a deflect is no Hit: no child and no gain"
  let nobody =
    pressed_through(
      plans: support.plans(),
      caster: support.caster(),
      bag_index: support.relentless_strikes,
      struck: [],
    )
  assert support.gains(effects: nobody) == [] as "no foe struck: no gain"
}

// ---- 21 ----

pub fn telekinetic_strike_striking_2_foes_gives_1_psi_point_once_test() -> Nil {
  use <- owned_test.run(20_000)
  let effects =
    pressed_through(
      plans: support.plans(),
      caster: support.caster(),
      bag_index: 0,
      struck: support.hits([10, 11]),
    )
  assert support.gains(effects:) == [[Gain(slot: 1, amount: 1)]]
    as "56858: +1 of slot 1 with no prerequisite, once for the go"
  assert children_started(effects, 30_900) == 2
}

// ---- 22 ----

pub fn energize_gives_4_actuators_and_logs_its_ticking_gain_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans = spell_tables.fixture_plans()
  let effects =
    pressed_through(
      plans:,
      caster: cast.Caster(
        ..support.caster(),
        abilities: list.map([38_201, 16_322, 26_543, 46_615], Spell4BaseId),
      ),
      bag_index: 3,
      struck: [],
    )
  assert support.gains(effects:) == [[Gain(slot: 1, amount: 4)]]
    as "228910: +4 of slot 1 on the caster, behind 43811, which passes with no Power Cadence 58999 live; it needs no foe; the Medic holds Energize as its innate, at bag index 3 after its three abilities"
  assert list.any(support.logs(effects:), fn(line) {
    line.0 == LogDebug && string.contains(line.1, "228918")
  })
    as "228918, the ticking +1, is not applied, and says so in a debug line"
}

// ---- 23 ----

pub fn a_gain_whose_prerequisite_fails_is_not_given_test() -> Nil {
  use <- owned_test.run(20_000)
  let overdrive = Spell(..support.exempt(), spell4_id: Spell4Id(42_908))
  let plans = support.with_spells(plans: support.plans(), spells: [overdrive])
  let #(state, _) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: 8,
      target: 0,
      at: 1000,
    )
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: support.caster(),
      bag_index: support.relentless_strikes,
      target: 0,
      at: 1000,
    )
  let struck = support.hits([10])
  let #(state, effects) =
    support.answered_by(state:, effects: raw, at: 1000, struck:)
  let #(_, fired) =
    support.run_timers_striking(state:, effects:, from_ms: 1000, struck:)
  let every = list.append(effects, list.flat_map(fired, fn(step) { step.1 }))
  assert children_started(every, 53_865) == 1
    as "the stage spell struck the foe and started its child"
  assert support.gains(effects: every) == []
    as "a cast of Overdrive 42908, live until 2000, has the Warrior as its target: 24581's comparison 2 on 42908 fails, so the +180 is not given"
}

// ---- a press held behind a go meets the go's gain ----

/// An Esper holding no Psi Points presses Telekinetic Strike (bag index 0, a bar of
/// 1250 ms) at 1000 and Mind Burst (bag index 2) at 1800, 450 ms before the go, which
/// holds it until the go clears the current cast; the go at 2250 strikes `struck`.
/// What the go's step gives: its payments, gains and 0x7fc results.
fn mind_burst_held_behind_the_go(
  struck struck: List(cast.Struck),
) -> #(List(class_resource.Payment), List(List(class_resource.Gain)), List(Int)) {
  let caster =
    support.caster_holding(
      resources: class_resource.new(
        resource: class_resource_support.resource_of(3),
      ),
    )
  let take = fn(state, body, at) {
    let assert Ok(taken) =
      cast.take(
        cast: state,
        message: cast.Pressed,
        body:,
        caster:,
        plans: support.plans(),
        now: support.at(ms: at),
      )
      as "taken"
    taken
  }
  let #(state, started) =
    take(
      cast.new(),
      support.press_body(client_cast_id: 8, bag_index: 0, target: 0, press: 1),
      1000,
    )
  let #(state, held) =
    take(
      state,
      support.press_body(client_cast_id: 9, bag_index: 2, target: 0, press: 1),
      1800,
    )
  assert support.writes(effects: held) == []
    as "450 ms of the bar are left: the press is held for the go, not refused"
  let assert [#(go_timer, _)] = support.started_timers(effects: started)
  let #(state, fired) =
    cast.timer_fired(
      cast: state,
      timer: go_timer,
      caster:,
      now: support.at(ms: 2250),
    )
  let assert [cast.Strike(asked:)] = fired as "the go is asked"
  let #(_, effects) =
    support.went(
      cast: state,
      caster:,
      now: support.at(ms: 2250),
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck:,
    )
  #(
    support.payments(effects:),
    support.gains(effects:),
    list.filter_map(support.writes(effects:), fn(frame) {
      case frame.message_id == spell_cast_refused.message_id {
        True -> {
          let assert Ok(refused) = spell_cast_refused.decode(frame.body)
            as "0x7fc decodes"
          Ok(cast_result.to_value(refused.result))
        }
        False -> Error(Nil)
      }
    }),
  )
}

pub fn a_press_held_behind_a_go_is_checked_against_the_bar_with_that_gos_gain_test() -> Nil {
  use <- owned_test.run(20_000)
  assert mind_burst_held_behind_the_go(struck: support.hits([10]))
    == #([Payment(slot: 1, amount: 1)], [[Gain(slot: 1, amount: 1)]], [])
    as "Spell4.32809 costs 1 Psi Point (Spell4CastResult.vital_cost) and 0 Psi Points are refused 51 (CasterVitalCostResource1); Telekinetic Strike's go struck a foe and gave +1 (56858), so the held Mind Burst is accepted and pays it"
  assert mind_burst_held_behind_the_go(struck: []) == #([], [], [51])
    as "a go that struck nobody gives no Psi Point, so the held Mind Burst meets 0 and is refused 51"
}
