//// A Medic's Discharge on the client's own rows (`genesis_prime/game/cast` with the
//// plans of the real tables): each pulse starts 80382, whose Proxies start Power
//// Charge 42569 while the caster holds fewer than 2 stacks of it and 80383 at exactly 2
//// stacks; 80383 gives 1 Actuator and takes the 3 stacks off. Expected values come from
//// these places:
//// - `Prerequisite.prerequisiteTypeId.59`: the stack count of 42569 on the caster is
////   the sum of its casts' node counts (gate 33154: fewer than 2; 32921: exactly 2).
//// - `Spell4Effects.effectType.17` and `.80`: 96819 is Power Charge's Fluff, which lasts
////   until removed; 80383's row 212836 removes 3 stacks of Spell4 42569 (trace §4, §5).
//// - `opcode.0x811`: a cast taken off a unit is one 0x811.
//// Skipped where the client's tables are not on the machine.

import cast_support as support
import client_tables
import genesis_prime/game/cast.{type Effect}
import genesis_prime/game/class_resource
import genesis_prime/game/spell_plan.{type Plans, Spell}
import genesis_prime/message/spell_effect_info.{type SpellEffectInfo}
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed
import genesis_prime/table/id.{Spell4BaseId}
import gleam/list
import owned_test
import unitest

/// Discharge with no cooldown of its own, so a second press meets none
/// (`cast_method_test` does the same for its cooldown rule).
fn real_plans() -> Plans {
  let plans = spell_plan.plans(client_tables.shared())
  let assert Ok(discharge) =
    spell_plan.in_plans(plans:, base: Spell4BaseId(38_201))
    as "Discharge is a level-1 ability"
  support.with_spells(plans:, spells: [Spell(..discharge, cooldown_ms: 0)])
}

/// The 0x7ff starts in the effects, each as (cast id, Spell4 id): the casts a Proxy
/// started.
fn starts(effects: List(Effect)) -> List(#(Int, Int)) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(start) = spell_started.decode(frame.body)
          as "a 0x7ff the rule wrote decodes"
        Ok(#(start.cast_id, start.spell4_id))
      }
      False -> Error(Nil)
    }
  })
}

/// The Spell4 ids of the casts that started in the effects.
fn started_spells(effects: List(Effect)) -> List(Int) {
  list.map(starts(effects), fn(start) { start.1 })
}

/// The ids of the casts that started with this Spell4 id.
fn started_ids_of(
  effects effects: List(Effect),
  spell4_id spell4_id: Int,
) -> List(Int) {
  list.filter_map(starts(effects), fn(start) {
    case start.1 == spell4_id {
      True -> Ok(start.0)
      False -> Error(Nil)
    }
  })
}

/// The effect infos of every go frame in the effects.
fn listed_effects(effects: List(Effect)) -> List(SpellEffectInfo) {
  list.filter(support.writes(effects:), fn(frame) {
    frame.message_id == spell_go.message_id
  })
  |> list.flat_map(fn(frame) {
    let assert Ok(go) = spell_go.decode(frame.body)
      as "a go the rule wrote decodes"
    list.flat_map(go.targets, fn(target) { target.effects })
  })
}

/// How many effect infos of the go frames in the effects name this Spell4Effects id.
fn listed(effects effects: List(Effect), effect_id effect_id: Int) -> Int {
  list.count(listed_effects(effects), fn(effect) {
    effect.spell4_effects_id == effect_id
  })
}

fn removed(effects effects: List(Effect)) -> List(#(Int, List(Int))) {
  list.filter_map(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_targets_removed.message_id {
      True -> {
        let assert Ok(removed) = spell_targets_removed.decode(frame.body)
          as "a 0x811 the rule wrote decodes"
        Ok(#(removed.cast_id, removed.unit_ids))
      }
      False -> Error(Nil)
    }
  })
}

pub fn discharge_shows_power_charge_1_then_2_then_the_third_pulse_turns_the_stacks_into_an_actuator_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans = real_plans()
  let #(state, pressed) =
    support.pressed_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: support.discharge,
      target: 0,
      at: 1000,
    )
  let #(_, steps) = support.run_timers(state:, effects: pressed, from_ms: 1000)
  let assert [first, second, third, _] = steps
  assert first.0 == 1410 && second.0 == 1820 && third.0 == 2230
    as "Spell4.58832: three pulses at 410 ms (cast_method_test)"
  assert listed(effects: first.1, effect_id: 96_819) == 1
    as "pulse 1 starts Power Charge: its go lists Fluff 96819 for the caster"
  assert listed(effects: second.1, effect_id: 96_819) == 1
    as "pulse 2 starts the second (gate 33154 passes at 1 stack)"
  assert removed(effects: first.1) == [] && removed(effects: second.1) == []
  assert started_spells(first.1) == [80_382, 42_569]
  assert started_spells(second.1) == [80_382, 42_569]
  assert started_spells(third.1) == [80_382, 80_383, 42_568]
    as "pulse 3: 33154 fails at 2 stacks and 32921 passes (Prerequisite.prerequisiteTypeId.59); 80383 starts 42568, the Actuator, by its Proxy 212837 (trace §5)"
  assert listed(effects: third.1, effect_id: 96_819) == 0
  let first_charge = started_ids_of(effects: first.1, spell4_id: 42_569)
  let second_charge = started_ids_of(effects: second.1, spell4_id: 42_569)
  assert removed(effects: third.1)
    == list.map(list.append(first_charge, second_charge), fn(id) { #(id, [7]) })
    as "80383 takes both Power Charge casts off the caster, oldest first: one 0x811 each (opcode.0x811)"
  assert list.any(support.gains(effects: third.1), fn(gains) {
    list.any(gains, fn(gain: class_resource.Gain) { gain.amount == 1 })
  })
    as "80383 gives 1 Actuator (Proxy 212837 to 42568, trace §5)"
}

pub fn the_pulse_after_the_stacks_went_starts_power_charge_again_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let plans = real_plans()
  let #(state, pressed) =
    support.pressed_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: support.discharge,
      target: 0,
      at: 1000,
    )
  let #(state, _) = support.run_timers(state:, effects: pressed, from_ms: 1000)
  let #(state, again) =
    support.pressed_in(
      plans:,
      state:,
      caster: support.caster(),
      bag_index: support.discharge,
      target: 0,
      at: 5000,
    )
  let #(_, steps) = support.run_timers(state:, effects: again, from_ms: 5000)
  let assert [first, ..] = steps
  assert started_spells(first.1) == [80_382, 42_569]
    as "the stacks went at the third pulse, so the gate passes at 0 stacks again"
}
