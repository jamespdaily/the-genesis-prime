//// The cast rule's shield heals (`genesis_prime/game/cast` `CasterChange`,
//// `CasterChangeStarts`, `ModifierStart`). Expected values come from these places:
//// - `Spell4Effects.effectType.118`: a HealShields result is shown by the client as a
////   floater and a log line from the go's damage description, and never changes the
////   shield, so the server works the amount out, puts it in the description's health
////   change and raises the shield itself; Energize's row 228914 is 0.3 x the missing
////   shield, at 10 ms, aimed at the caster (`table_rows -- Spell4Effects spellId=69450`).
//// - `GameLib.CodeEnumDamageType` (5 HealShields) and `GameLib.CodeEnumCombatResult` (2
////   Hit): the description's type and result; `0x140094890` (tag 1 of an effect result is
////   a damage description) and `0x1405d77a0` (the delay is added before a damage result
////   is applied): the heal lands at the go plus its delay.
//// - `opcode.0x7f4.effect_time`: an effect that has a lifetime gives its spell a node on
////   its unit, so a heal of a delay gives the caster's node a life of that delay and the
////   0x7fe waits for it (the type 73 precedent).
//// - Row 210834's prerequisite 24571: type 50, comparison 1, value 59178, the Warrior's
////   Impenetrable AMP (`table_rows -- Prerequisite 24571`), which a caster that does not
////   hold the AMP fails.
//// - The server's choices, in the cast rule's doc: a go's gates and amount read the caster
////   as it stood before the go's own effects; a pending heal is dropped with the node it
////   belongs to, by a death, a type 80 removal or a persistence that stops holding; a
////   later go of a cast heals again; the description is written the same for every
////   viewer.

import cast_support as support
import genesis_prime/client_connection.{CastWent}
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/lasting
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, AimsAtCaster, Always, GatedOnCaster,
}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{type Source, Change, Source}
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/spell_damage_description.{SpellDamageDescription}
import genesis_prime/message/spell_effect_damage.{SpellEffectDamage}
import genesis_prime/message/spell_effect_info.{
  type SpellEffectInfo, SpellEffectInfo,
}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/step.{type TimerId, LogDebug, TimerId}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id, UnitProperty2Id}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import prerequisite_support as prerequisites

/// The planted base 3 is bag index 11 and base 1 is bag index 8
/// (`cast_support.abilities`).
const bag_of_base_3 = 11

const bag_of_base_1 = 8

/// Energize's row 228914: 0.3 of the missing shield, aimed at the caster, after `delay`.
fn energize(delay_ms delay_ms: Int) -> spell_plan.ShieldHeal {
  heal_of(id: 228_914, delay_ms:, condition: Always)
}

/// A heal of Energize's formula with this row id, delay and condition.
fn heal_of(
  id id: Int,
  delay_ms delay_ms: Int,
  condition condition: spell_plan.Condition,
) -> spell_plan.ShieldHeal {
  spell_plan.ShieldHeal(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    aim: AimsAtCaster,
    condition:,
    tag: spend.always,
    formula: Formula(multiplier: 1.0, base: 0, parameters: [
      Parameter(kind: 22, value: 0.3),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ]),
    delay_ms:,
  )
}

/// The planted base 3's spell with these heals.
fn healer(heals heals: List(spell_plan.ShieldHeal)) -> Spell {
  spell_plan.Spell(
    ..support.child(spell4_id: 69_450, base: 3),
    shield_heals: heals,
  )
}

fn plans_of(spells: List(Spell)) -> Plans {
  support.with_spells(plans: support.plans(), spells:)
}

/// The caster with 250 of its 450 shield and 500 of its 736 health, which no go of the
/// tests changes.
fn struck_caster() -> Caster {
  cast.Caster(
    ..support.caster(),
    vitals: damage.Vitals(
      health: 500,
      max_health: 736,
      shield: 250,
      max_shield: 450,
    ),
  )
}

/// A press of the bag index by the caster, its go answered with no unit struck, read for
/// the same caster.
fn press(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster:,
      bag_index: bag,
      target: 0,
      at: ms,
    )
  support.answered_as(
    caster:,
    state:,
    effects: raw,
    at: ms,
    struck: [],
    rolls: [],
  )
}

fn source_of(cast_id cast_id: Int, effect_id effect_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(effect_id))
}

/// The heals the effects start, with their sources and amounts.
fn heals(effects effects: List(Effect)) -> List(#(Source, Int)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.CasterChangeStarts(source:, change: cast.ShieldHeal(amount:)) ->
        Ok(#(source, amount))
      cast.CasterChangeStarts(change: cast.Property(..), ..)
      | cast.CasterChangeStarts(change: cast.Absorb(..), ..)
      | cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..)
      | cast.Strike(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.CasterChangeEnds(..)
      | cast.StealthChanged(..) -> Error(Nil)
    }
  })
}

/// The time each step's effects were taken at, with the heals it starts.
fn timeline(
  fired fired: List(#(Int, List(Effect))),
) -> List(#(Int, Source, Int)) {
  list.flat_map(fired, fn(step) {
    list.map(heals(effects: step.1), fn(heal) { #(step.0, heal.0, heal.1) })
  })
}

/// The effect infos of the unit the go's 0x7f4 lists first.
fn listed(effects effects: List(Effect)) -> List(SpellEffectInfo) {
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  list.flat_map(decoded.targets, fn(target) { target.effects })
}

fn heal_description(
  amount amount: Int,
) -> spell_effect_result.SpellEffectResult {
  spell_effect_result.Damage(
    SpellEffectDamage(
      description: SpellDamageDescription(
        raw_damage: amount,
        scaled_raw_damage: amount,
        absorbed: 0,
        shield_absorbed: 0,
        health_damage_with_overkill: amount,
        overkill: 0,
        glance: 0,
        killed: 0,
        combat_result: combat_result.Hit,
        damage_type: damage_type.HealShields,
        hits: [],
      ),
    ),
  )
}

// ---- what the go lists ----

pub fn a_go_with_a_shield_heal_lists_it_on_the_caster_with_a_heal_description_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = plans_of([healer(heals: [energize(delay_ms: 10)])])
  let #(_, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.unit_id == 7 as "the heal is listed on the caster"
  assert info.effects
    == [
      SpellEffectInfo(
        spell4_effects_id: 228_914,
        instance_id: 1,
        delay_ms: 10,
        field_4: 0,
        result: heal_description(amount: 60),
      ),
    ]
    as "0.3 x (450 - 250) = 60: raw, scaled raw and health change 60, type HealShields (5), result Hit (2), nothing else"
}

pub fn a_shield_heal_with_no_delay_lands_in_the_steps_of_the_go_after_its_0x7f4_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = plans_of([healer(heals: [energize(delay_ms: 0)])])
  let #(_, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert heals(effects:) == [#(source_of(cast_id: id, effect_id: 228_914), 60)]
    as "a heal with no delay starts in the go's own step"
  let position = fn(wanted: fn(Effect) -> Bool) {
    let assert Ok(found) =
      list.index_map(effects, fn(effect, index) { #(effect, index) })
      |> list.find(fn(entry) { wanted(entry.0) })
    found.1
  }
  let go_written =
    position(fn(effect) {
      case effect {
        cast.Send(frame:) -> frame.message_id == spell_go.message_id
        cast.CasterChangeStarts(..)
        | cast.Tell(..)
        | cast.StartTimer(..)
        | cast.CancelTimer(..)
        | cast.Log(..)
        | cast.Strike(..)
        | cast.Pay(..)
        | cast.Gain(..)
        | cast.CasterChangeEnds(..)
        | cast.StealthChanged(..) -> False
      }
    })
  let healed = position(fn(effect) { heals(effects: [effect]) != [] })
  assert go_written < healed
    as "the description first, then the shield (the server's choice: 0x938 must not reach the client before the description)"
}

pub fn a_shield_heal_with_a_delay_lands_on_a_timer_of_its_delay_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = plans_of([healer(heals: [energize(delay_ms: 10)])])
  let #(state, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert heals(effects:) == []
    as "nothing lands at the go: the client adds the delay before it applies a result (0x1405d77a0)"
  assert list.contains(
    list.map(support.started_timers(effects:), fn(timer) { timer.1 }),
    10,
  )
    as "a timer of the row's delay is started"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert timeline(fired:)
    == [#(1010, source_of(cast_id: id, effect_id: 228_914), 60)]
    as "the heal lands at go + 10, with the amount worked out at the go"
}

pub fn the_amount_reads_the_caster_as_it_stood_before_the_gos_own_effects_test() -> Nil {
  use <- owned_test.run(5000)
  // The same go raises ShieldCapacityMax (property 41) by 100: the heal is still 0.3 of
  // the missing shield the caster had when the go began, 200, not 0.3 of 300.
  let raising =
    spell_plan.PropertyModifier(
      effect_id: Spell4EffectsId(99_001),
      phase_flags: -1,
      modifier: Change(
        property: UnitProperty2Id(41),
        mode: 3,
        multiplier: 1.0,
        flat: 100.0,
        per_level: 0.0,
      ),
      row: lasting.LastingRow(
        delay_ms: 0,
        duration_ms: 8000,
        until_removed: False,
      ),
      condition: Always,
      tag: spend.always,
      armor: None,
    )
  let plans =
    plans_of([
      spell_plan.Spell(..healer(heals: [energize(delay_ms: 0)]), modifiers: [
        raising,
      ]),
    ])
  let #(_, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert heals(effects:) == [#(source_of(cast_id: id, effect_id: 228_914), 60)]
    as "0.3 x (450 - 250) = 60: the gates' rule, a go's effects read the caster before the go's own"
  assert list.any(effects, fn(effect) {
    case effect {
      cast.CasterChangeStarts(change: cast.Property(..), ..) -> True
      cast.CasterChangeStarts(change: cast.ShieldHeal(..), ..)
      | cast.CasterChangeStarts(change: cast.Absorb(..), ..)
      | cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..)
      | cast.Strike(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.CasterChangeEnds(..)
      | cast.StealthChanged(..) -> False
    }
  })
    as "and the raised maximum does start in the same go"
}

// ---- the caster's node ----

pub fn a_delayed_shield_heal_holds_the_casters_node_until_it_lands_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = plans_of([healer(heals: [energize(delay_ms: 500)])])
  let #(state, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert support.finished_ids(support.writes(effects:)) == []
    as "the heal row gives the caster's node a life of its delay, so the 0x7fe waits (the type 73 precedent)"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  let finishes =
    list.filter(fired, fn(step) {
      support.finished_ids(support.writes(effects: step.1)) == [id]
    })
  assert list.map(finishes, fn(step) { step.0 }) == [1500]
    as "the 0x7fe comes 500 ms after the go"
  assert timeline(fired:)
    == [#(1500, source_of(cast_id: id, effect_id: 228_914), 60)]
    as "and the heal lands in the same millisecond"
}

pub fn a_heal_whose_nodes_end_fires_first_still_lands_test() -> Nil {
  use <- owned_test.run(5000)
  // The node's end and the heal's start are due in the same millisecond; whichever the
  // shell delivers first, the heal lands once.
  let plans = plans_of([healer(heals: [energize(delay_ms: 10)])])
  let #(state, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let numbers =
    list.map(support.started_timers(effects:), fn(timer) { timer.0 })
  let #(state, first) =
    support.fired_raw(state:, timer: last_of(numbers), at: 1010)
  let #(_, second) =
    support.fired_raw(state:, timer: first_of(numbers), at: 1010)
  assert support.finished_ids(support.writes(effects: first)) == [id]
    as "the first step is the node's end, which writes the 0x7fe: the heal had not fired yet"
  assert list.append(heals(effects: first), heals(effects: second))
    == [#(source_of(cast_id: id, effect_id: 228_914), 60)]
    as "the heal lands once, in the step of whichever timer comes first"
  assert heals(effects: first) != []
    as "here the node's end lands it, and the heal's own timer, cancelled, finds nothing"
}

fn first_of(timers: List(TimerId)) -> TimerId {
  let assert [first, ..] = timers as "the go started timers"
  first
}

fn last_of(timers: List(TimerId)) -> TimerId {
  let assert Ok(last) = list.last(timers) as "the go started timers"
  last
}

// ---- gates ----

pub fn a_shield_heal_behind_a_caster_gate_that_fails_is_neither_listed_nor_applied_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 210834's prerequisite 24571: type 50 on the AMP spell 59178, which this caster
  // does not hold.
  let gate = prerequisites.single(id: 24_571, condition: #(50, 1, 0, 59_178))
  let gated =
    heal_of(id: 228_914, delay_ms: 0, condition: GatedOnCaster(gates: [gate]))
  let plans = plans_of([healer(heals: [gated])])
  let #(_, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert listed(effects:) == [] as "the go lists nothing"
  assert heals(effects:) == [] as "and nothing lands"
  // The same heal behind a gate that passes (type 28, the caster in combat) is listed
  // and lands, so the rows above were held back by their gate.
  let open_gate = prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
  let plans =
    plans_of([
      healer(heals: [
        heal_of(
          id: 228_914,
          delay_ms: 0,
          condition: GatedOnCaster(gates: [open_gate]),
        ),
      ]),
    ])
  let #(_, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: cast.Caster(..struck_caster(), in_combat: True),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert list.length(listed(effects:)) == 1 && list.length(heals(effects:)) == 1
}

// ---- dropped heals ----

/// The ids of the timers the effects start, as numbers, sorted.
fn numbers(timers: List(TimerId)) -> List(Int) {
  list.map(timers, fn(timer) {
    let TimerId(number) = timer
    number
  })
  |> list.sort(int.compare)
}

pub fn a_pending_shield_heal_is_dropped_when_the_caster_dies_or_its_node_is_taken_off_test() -> Nil {
  use <- owned_test.run(5000)
  let delayed = healer(heals: [energize(delay_ms: 500)])
  let started_by = fn(effects) {
    numbers(list.map(support.started_timers(effects:), fn(timer) { timer.0 }))
  }
  // A death before the delay.
  let plans = plans_of([delayed])
  let #(state, first) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(_, alive) = support.run_timers(state:, effects: first, from_ms: 1000)
  assert list.length(timeline(fired: alive)) == 1
    as "left alone, the heal lands at go + 500"
  let #(dead, died) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1100),
    )
  assert heals(effects: died) == []
  assert numbers(support.cancelled_timers(effects: died)) == started_by(first)
    as "every timer the press started is cancelled, the heal's among them"
  let #(_, later) =
    support.run_timers(state: dead, effects: first, from_ms: 1000)
  assert timeline(fired: later) == [] as "no heal lands after the death"
  // A type 80 removal of the cast before the delay.
  let remover =
    spell_plan.Spell(..support.child(spell4_id: 301, base: 1), removes: [
      spell_plan.ForceRemove(
        effect_id: Spell4EffectsId(196_521),
        phase_flags: -1,
        aim: AimsAtCaster,
        selector: lasting.Spell(Spell4Id(69_450)),
        count: 1,
        condition: Always,
        tag: spend.always,
      ),
    ])
  let plans = plans_of([delayed, remover])
  let #(state, first) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(_, alive) = support.run_timers(state:, effects: first, from_ms: 1000)
  assert list.length(timeline(fired: alive)) == 1
    as "left alone, the heal lands at go + 500"
  let #(state, removal) =
    press(plans:, state:, caster: struck_caster(), bag: bag_of_base_1, at: 1100)
  assert heals(effects: removal) == []
  assert list.all(started_by(first), fn(started) {
    list.contains(numbers(support.cancelled_timers(effects: removal)), started)
  })
    as "taking the cast's node off the caster cancels the heal's timer with the node's end"
  let #(_, later) = support.run_timers(state:, effects: first, from_ms: 1000)
  assert timeline(fired: later) == []
  // A persistence that stops holding before the delay.
  let persisting =
    spell_plan.Spell(
      ..delayed,
      caster_persistence: Some(
        prerequisites.single(id: 903, condition: #(28, 1, 0, 0)),
      ),
    )
  let fighting = cast.Caster(..struck_caster(), in_combat: True)
  let #(state, first) =
    press(
      plans: plans_of([persisting]),
      state: cast.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(_, alive) = support.run_timers(state:, effects: first, from_ms: 1000)
  assert list.length(timeline(fired: alive)) == 1
    as "left alone, the heal lands at go + 500"
  let #(state, ended) =
    cast.persisted(
      cast: state,
      caster: cast.Caster(..fighting, in_combat: False),
      now: support.at(ms: 1100),
    )
  assert heals(effects: ended) == []
  assert list.all(started_by(first), fn(started) {
    list.contains(numbers(support.cancelled_timers(effects: ended)), started)
  })
    as "a cast ended by its persistence drops the heal with its node"
  let #(_, later) = support.run_timers(state:, effects: first, from_ms: 1000)
  assert timeline(fired: later) == []
}

// ---- rows the rule does not apply ----

pub fn a_ticking_shield_heal_whose_gate_passes_is_not_applied_and_writes_one_debug_line_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 210834: 0.125 of the maximum shield each 1000 ms for 8000 ms; a periodic heal
  // needs a 0x7f8 for each tick, which no rule of the server sends.
  let ticking =
    spell_plan.TickingShieldHeal(
      effect_id: Spell4EffectsId(210_834),
      phase_flags: -1,
      aim: AimsAtCaster,
      condition: Always,
      tag: spend.always,
      tick_ms: 1000,
      duration_ms: 8000,
    )
  let plans = plans_of([healer(heals: [ticking])])
  let #(_, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert heals(effects:) == [] as "nothing lands"
  assert listed(effects:) == [] as "and the go lists nothing"
  let assert [#(LogDebug, line)] = support.logs(effects:)
    as "one debug line says why"
  assert string.contains(line, "210834") && string.contains(line, "0x7f8")
    as "it names the row and the missing tick message"
}

pub fn two_shield_heal_rows_of_one_go_each_land_and_a_later_go_heals_again_test() -> Nil {
  use <- owned_test.run(5000)
  let second = heal_of(id: 228_999, delay_ms: 0, condition: Always)
  let plans =
    plans_of([
      spell_plan.Spell(
        ..healer(heals: [energize(delay_ms: 0), second]),
        phase_delays_ms: [0, 1000],
      ),
    ])
  let #(state, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert heals(effects:)
    == [
      #(source_of(cast_id: id, effect_id: 228_914), 60),
      #(source_of(cast_id: id, effect_id: 228_999), 60),
    ]
    as "each row is its own heal, each worked out from the caster as the go found it"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.map(timeline(fired:), fn(entry) { entry.0 }) == [2000, 2000]
    as "the second go heals again, each go its own heal"
}

pub fn two_goes_with_overlapping_delayed_heals_both_land_each_at_its_own_delay_test() -> Nil {
  use <- owned_test.run(5000)
  // Goes at 1000 and 1100 of a Multiphase-like cast, each with a heal of delay 500: the
  // second go cancels nothing of the first.
  let plans =
    plans_of([
      spell_plan.Spell(
        ..healer(heals: [energize(delay_ms: 500)]),
        phase_delays_ms: [0, 100],
      ),
    ])
  let #(state, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = source_of(cast_id: id, effect_id: 228_914)
  let timer_after = fn(effects, wanted_ms) {
    let assert Ok(found) =
      list.find(support.started_timers(effects:), fn(timer) {
        timer.1 == wanted_ms
      })
      as "the step started a timer of this delay"
    found.0
  }
  // The second go at 1100, taken for the same struck caster, then each heal's timer.
  let #(state, raw) =
    support.fired_raw_as(
      caster: struck_caster(),
      state:,
      timer: timer_after(effects, 100),
      at: 1100,
    )
  let #(state, second) =
    support.answered_as(
      caster: struck_caster(),
      state:,
      effects: raw,
      at: 1100,
      struck: [],
      rolls: [],
    )
  let #(state, first_lands) =
    support.fired_raw(state:, timer: timer_after(effects, 500), at: 1500)
  assert heals(effects: first_lands) == [#(source, 60)]
    as "the first go's heal lands at 1500, though the second go came before it"
  let #(_, second_lands) =
    support.fired_raw(state:, timer: timer_after(second, 500), at: 1600)
  assert heals(effects: second_lands) == [#(source, 60)]
    as "the second go's heal lands at 1600: it cancelled nothing of the first"
}

// ---- viewers ----

pub fn the_viewers_go_carries_the_same_heal_description_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = plans_of([healer(heals: [energize(delay_ms: 10)])])
  let #(_, effects) =
    press(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [written] =
    support.frames_of(message_id: spell_go.message_id, effects:)
  assert list.map(listed(effects:), fn(info) { info.spell4_effects_id })
    == [228_914]
    as "the go lists the heal"
  let told =
    list.filter_map(support.tells(effects:), fn(tell) {
      case tell.1 {
        CastWent(go:) -> Ok(#(tell.0, go))
        client_connection.CastStarted(..)
        | client_connection.CastFinished(..)
        | client_connection.CastMissed(..)
        | client_connection.CastTargetsRemoved(..)
        | client_connection.CastStackRemoved(..)
        | client_connection.Appeared(..)
        | client_connection.CreatureAppeared(..)
        | client_connection.Moving(..)
        | client_connection.Removed
        | client_connection.Health(..)
        | client_connection.Died
        | client_connection.CameBack
        | client_connection.DeathLogged
        | client_connection.CameBackLogged
        | client_connection.CreatureMoved(..)
        | client_connection.CreaturePlaced(..)
        | client_connection.Targeting(..)
        | client_connection.Threat(..)
        | client_connection.CombatState(..)
        | client_connection.Shield(..)
        | client_connection.CrowdControlApplied(..)
        | client_connection.CrowdControlEnded(..)
        | client_connection.InterruptArmor(..)
        | client_connection.Absorption(..)
        | client_connection.PropertiesChanged(..)
        | client_connection.Stealth(..) -> Error(Nil)
      }
    })
  assert list.length(told) == 2 as "the caster's audience is two connections"
  assert list.all(told, fn(tell) { cast.went_frame(go: tell.1) == written })
    as "each viewer is written the very 0x7f4 the caster is, heal description included"
}
