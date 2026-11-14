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
import genesis_prime/game/cast.{type Caster, type Effect}
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/effect_kind
import genesis_prime/game/heal_split
import genesis_prime/game/lasting
import genesis_prime/game/spell_plan.{
  type Spell, AimsAtCaster, AimsAtPrimaryTarget, Always, GatedOnCaster,
}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{type Source, Change}
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/spell_damage_description.{SpellDamageDescription}
import genesis_prime/message/spell_effect_damage.{SpellEffectDamage}
import genesis_prime/message/spell_effect_info.{
  type SpellEffectInfo, SpellEffectInfo,
}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/step.{type TimerId, LogDebug}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id, UnitProperty2Id}
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
fn energize(delay_ms delay_ms: Int) -> spell_plan.Heal {
  heal_of(id: 228_914, delay_ms:, condition: Always)
}

/// A heal of Energize's formula with this row id, delay and condition.
fn heal_of(
  id id: Int,
  delay_ms delay_ms: Int,
  condition condition: spell_plan.Condition,
) -> spell_plan.Heal {
  heal_row(
    id:,
    vital: effect_kind.Shield,
    aim: AimsAtCaster,
    delay_ms:,
    condition:,
    formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
      Parameter(kind: 22, value: 0.3),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ]),
  )
}

/// A heal with this row id, vital, aim, delay, condition and formula, in every phase.
fn heal_row(
  id id: Int,
  vital vital: effect_kind.Vital,
  aim aim: spell_plan.Aim,
  delay_ms delay_ms: Int,
  condition condition: spell_plan.Condition,
  formula formula: damage.Formula,
) -> spell_plan.Heal {
  spell_plan.Heal(
    effect_id: Spell4EffectsId(id),
    vital:,
    phase_flags: -1,
    aim:,
    condition:,
    tag: spend.always,
    formula:,
    delay_ms:,
  )
}

/// A Health heal of Mind Over Body's formula (Spell4Effects 62019: 0.3281 of Support Power
/// and 17.51 a level, multiplier 1, no flat part), with this row id, delay and aim.
fn health_heal(
  id id: Int,
  delay_ms delay_ms: Int,
  aim aim: spell_plan.Aim,
) -> spell_plan.Heal {
  heal_row(
    id:,
    vital: effect_kind.Health,
    aim:,
    delay_ms:,
    condition: Always,
    formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
      Parameter(kind: 13, value: 0.3281),
      Parameter(kind: 10, value: 17.51),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ]),
  )
}

/// The caster of level 5 and 400 Support Rating, with 500 of its 736 health and 250 of
/// its 450 shield: Mind Over Body's formula reads it as round(0.3281 x 100) + 17.51 x 5 =
/// 33 + 87.55 = 120.55, which is 121 (the stat part is rounded alone, `0x140565600`; one
/// rounding of 120.36 would give 120).
fn healing_caster(health health: Int) -> Caster {
  cast.Caster(
    ..struck_caster(),
    stats: damage.Attacker(level: 5, assault_rating: 0.0, support_rating: 400.0),
    vitals: damage.Vitals(
      health:,
      max_health: 736,
      shield: 250,
      max_shield: 450,
    ),
  )
}

/// The planted base 3's spell with these heals.
fn healer(heals heals: List(spell_plan.Heal)) -> Spell {
  spell_plan.Spell(..support.child(spell4_id: 69_450, base: 3), heals: heals)
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

/// The heals the effects start, with their sources and amounts.
fn heals(effects effects: List(Effect)) -> List(#(Source, Int)) {
  list.map(healed(effects:), fn(heal) { #(heal.0, heal.2) })
}

/// The heals the effects start, with their sources, the vital each raises and its amount.
fn healed(
  effects effects: List(Effect),
) -> List(#(Source, effect_kind.Vital, Int)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.CasterChangeStarts(source:, change: cast.Heal(vital:, amount:)) ->
        Ok(#(source, vital, amount))
      cast.CasterChangeStarts(change: cast.Property(..), ..)
      | cast.CasterChangeStarts(change: cast.Look(..), ..)
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
      | cast.TargetChangeStarts(..)
      | cast.TargetChangeEnds(..)
      | cast.Activated(..)
      | cast.ShortcutCast(..)
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
  kind kind: damage_type.DamageType,
  overkill overkill: Int,
) -> spell_effect_result.SpellEffectResult {
  spell_effect_result.Damage(
    SpellEffectDamage(
      description: SpellDamageDescription(
        raw_damage: amount,
        scaled_raw_damage: amount,
        absorbed: 0,
        shield_absorbed: 0,
        health_damage_with_overkill: amount,
        overkill:,
        glance: 0,
        killed: 0,
        combat_result: combat_result.Hit,
        damage_type: kind,
        hits: [],
      ),
    ),
  )
}

// ---- what the go lists ----

pub fn a_go_with_a_shield_heal_lists_it_on_the_caster_with_a_heal_description_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([healer(heals: [energize(delay_ms: 10)])])
  let #(_, effects) =
    support.press_as(
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
        result: heal_description(
          amount: 60,
          kind: damage_type.HealShields,
          overkill: 0,
        ),
      ),
    ]
    as "0.3 x (450 - 250) = 60: raw, scaled raw and health change 60, type HealShields (5), result Hit (2), nothing else"
}

pub fn a_shield_heal_with_no_delay_lands_in_the_steps_of_the_go_after_its_0x7f4_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([healer(heals: [energize(delay_ms: 0)])])
  let #(_, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert heals(effects:)
    == [#(support.source_of(cast_id: id, effect_id: 228_914), 60)]
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
        | cast.TargetChangeStarts(..)
        | cast.TargetChangeEnds(..)
        | cast.Activated(..)
        | cast.ShortcutCast(..)
        | cast.StealthChanged(..) -> False
      }
    })
  let healed = position(fn(effect) { heals(effects: [effect]) != [] })
  assert go_written < healed
    as "the description first, then the shield (the server's choice: 0x938 must not reach the client before the description)"
}

pub fn a_shield_heal_with_a_delay_lands_on_a_timer_of_its_delay_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([healer(heals: [energize(delay_ms: 10)])])
  let #(state, effects) =
    support.press_as(
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
    == [#(1010, support.source_of(cast_id: id, effect_id: 228_914), 60)]
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
      change: spell_plan.PropertyChange(Change(
        property: UnitProperty2Id(41),
        mode: 3,
        multiplier: 1.0,
        flat: 100.0,
        per_level: 0.0,
      )),
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
    support.plans_of([
      spell_plan.Spell(..healer(heals: [energize(delay_ms: 0)]), modifiers: [
        raising,
      ]),
    ])
  let #(_, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert heals(effects:)
    == [#(support.source_of(cast_id: id, effect_id: 228_914), 60)]
    as "0.3 x (450 - 250) = 60: the gates' rule, a go's effects read the caster before the go's own"
  assert list.any(effects, fn(effect) {
    case effect {
      cast.CasterChangeStarts(change: cast.Property(..), ..) -> True
      cast.CasterChangeStarts(change: cast.Heal(..), ..)
      | cast.CasterChangeStarts(change: cast.Look(..), ..)
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
      | cast.TargetChangeStarts(..)
      | cast.TargetChangeEnds(..)
      | cast.Activated(..)
      | cast.ShortcutCast(..)
      | cast.StealthChanged(..) -> False
    }
  })
    as "and the raised maximum does start in the same go"
}

// ---- the caster's node ----

pub fn a_delayed_shield_heal_holds_the_casters_node_until_it_lands_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([healer(heals: [energize(delay_ms: 500)])])
  let #(state, effects) =
    support.press_as(
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
    == [#(1500, support.source_of(cast_id: id, effect_id: 228_914), 60)]
    as "and the heal lands in the same millisecond"
}

pub fn a_heal_whose_nodes_end_fires_first_still_lands_test() -> Nil {
  use <- owned_test.run(5000)
  // The node's end and the heal's start are due in the same millisecond; whichever the
  // shell delivers first, the heal lands once.
  let plans = support.plans_of([healer(heals: [energize(delay_ms: 10)])])
  let #(state, effects) =
    support.press_as(
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
    == [#(support.source_of(cast_id: id, effect_id: 228_914), 60)]
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
  let plans = support.plans_of([healer(heals: [gated])])
  let #(_, effects) =
    support.press_as(
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
    support.plans_of([
      healer(heals: [
        heal_of(
          id: 228_914,
          delay_ms: 0,
          condition: GatedOnCaster(gates: [open_gate]),
        ),
      ]),
    ])
  let #(_, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: cast.Caster(..struck_caster(), in_combat: True),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert list.length(listed(effects:)) == 1 && list.length(heals(effects:)) == 1
}

// ---- dropped heals ----

pub fn a_pending_shield_heal_is_dropped_when_the_caster_dies_or_its_node_is_taken_off_test() -> Nil {
  use <- owned_test.run(5000)
  let delayed = healer(heals: [energize(delay_ms: 500)])
  let started_by = fn(effects) {
    support.timer_numbers(
      list.map(support.started_timers(effects:), fn(timer) { timer.0 }),
    )
  }
  // A death before the delay.
  let plans = support.plans_of([delayed])
  let #(state, first) =
    support.press_as(
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
  assert support.timer_numbers(support.cancelled_timers(effects: died))
    == started_by(first)
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
  let plans = support.plans_of([delayed, remover])
  let #(state, first) =
    support.press_as(
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
    support.press_as(
      plans:,
      state:,
      caster: struck_caster(),
      bag: bag_of_base_1,
      at: 1100,
    )
  assert heals(effects: removal) == []
  assert list.all(started_by(first), fn(started) {
    list.contains(
      support.timer_numbers(support.cancelled_timers(effects: removal)),
      started,
    )
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
    support.press_as(
      plans: support.plans_of([persisting]),
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
    list.contains(
      support.timer_numbers(support.cancelled_timers(effects: ended)),
      started,
    )
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
    spell_plan.TickingHeal(
      effect_id: Spell4EffectsId(210_834),
      vital: effect_kind.Shield,
      phase_flags: -1,
      aim: AimsAtCaster,
      condition: Always,
      tag: spend.always,
      tick_ms: 1000,
      duration_ms: 8000,
    )
  let plans = support.plans_of([healer(heals: [ticking])])
  let #(_, effects) =
    support.press_as(
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
    support.plans_of([
      spell_plan.Spell(
        ..healer(heals: [energize(delay_ms: 0), second]),
        phase_delays_ms: [0, 1000],
      ),
    ])
  let #(state, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert heals(effects:)
    == [
      #(support.source_of(cast_id: id, effect_id: 228_914), 60),
      #(support.source_of(cast_id: id, effect_id: 228_999), 60),
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
    support.plans_of([
      spell_plan.Spell(
        ..healer(heals: [energize(delay_ms: 500)]),
        phase_delays_ms: [0, 100],
      ),
    ])
  let #(state, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: struck_caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 228_914)
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
  let plans = support.plans_of([healer(heals: [energize(delay_ms: 10)])])
  let #(_, effects) =
    support.press_as(
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
        | client_connection.CastInterrupted(..)
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
        | client_connection.Level(..)
        | client_connection.PropertiesChanged(..)
        | client_connection.Stealth(..)
        | client_connection.LookChanged(..) -> Error(Nil)
      }
    })
  assert list.length(told) == 2 as "the caster's audience is two connections"
  assert list.all(told, fn(tell) { cast.went_frame(go: tell.1) == written })
    as "each viewer is written the very 0x7f4 the caster is, heal description included"
}

// ---- health heals ----

pub fn a_self_heal_go_describes_the_heal_and_starts_the_change_test() -> Nil {
  use <- owned_test.run(5000)
  // Mind Over Body's row 62019 aims at the primary target, which a spell cast on the
  // caster makes the caster; its delay here is 20 ms.
  let plans =
    support.plans_of([
      healer(heals: [
        health_heal(id: 62_019, delay_ms: 20, aim: AimsAtPrimaryTarget),
      ]),
    ])
  let #(state, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: healing_caster(health: 500),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert listed(effects:)
    == [
      SpellEffectInfo(
        spell4_effects_id: 62_019,
        instance_id: 1,
        delay_ms: 20,
        field_4: 0,
        result: heal_description(
          amount: 121,
          kind: damage_type.Heal,
          overkill: 0,
        ),
      ),
    ]
    as "round(0.3281 x 100) + 17.51 x 5 = 121: raw, scaled raw and health change 121, type Heal (4), result Hit (2), no overkill below full health"
  assert healed(effects:) == []
    as "nothing lands at the go: the delay comes first"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.flat_map(fired, fn(step) {
      list.map(healed(effects: step.1), fn(heal) { #(step.0, heal) })
    })
    == [
      #(
        1020,
        #(
          support.source_of(cast_id: id, effect_id: 62_019),
          effect_kind.Health,
          121,
        ),
      ),
    ]
    as "the health heal lands at go + 20 with the amount worked out at the go"
}

pub fn a_heal_past_full_health_reports_the_overheal_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      healer(heals: [
        health_heal(id: 62_019, delay_ms: 0, aim: AimsAtPrimaryTarget),
      ]),
    ])
  let described = fn(health) {
    let #(_, effects) =
      support.press_as(
        plans:,
        state: cast.new(),
        caster: healing_caster(health:),
        bag: bag_of_base_3,
        at: 1000,
      )
    list.map(listed(effects:), fn(info) { info.result })
  }
  assert described(726)
    == [
      heal_description(amount: 121, kind: damage_type.Heal, overkill: 111),
    ]
    as "10 below the maximum: the whole 121 is the health change and 121 - 10 = 111 is the overheal the client logs (0x140563dc0 reads that word as nOverheal)"
  assert described(736)
    == [
      heal_description(amount: 121, kind: damage_type.Heal, overkill: 121),
    ]
    as "at full health the overheal is the whole amount, and the health change is still 121"
}

/// A Health heal of a flat `amount` (a formula of base `amount` alone), aimed at the caster.
fn flat_health_heal(amount amount: Float) -> spell_plan.Heal {
  heal_row(
    id: 62_019,
    vital: effect_kind.Health,
    aim: AimsAtCaster,
    delay_ms: 0,
    condition: Always,
    formula: Formula(multiplier: 1.0, base: amount, parameters: [
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ]),
  )
}

pub fn a_heal_multiplier_changes_the_amount_and_overheal_the_go_tells_the_client_test() -> Nil {
  use <- owned_test.run(5000)
  // The health rises by the heal after the unit's outgoing and incoming heal multipliers
  // (properties 162 and 163, `UnitProperty2.damage_heal_multipliers`) and the client only
  // shows what the server tells it (`0x1405d8350`), so a 1.5x outgoing multiplier makes a
  // heal of 40 a heal of 60, and with the health 30 below its maximum, 60 - 30 = 30 of it
  // is the overheal (nOverheal of `spell.heal_result_log`).
  let plans =
    support.plans_of([healer(heals: [flat_health_heal(amount: 40.0)])])
  let caster =
    cast.Caster(
      ..struck_caster(),
      vitals: damage.Vitals(
        health: 706,
        max_health: 736,
        shield: 250,
        max_shield: 450,
      ),
      heal_scaling: heal_split.Scaling(
        outgoing: 1.5,
        incoming: 1.0,
        to_shield: 0.0,
      ),
    )
  let #(_, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster:,
      bag: bag_of_base_3,
      at: 1000,
    )
  assert list.map(listed(effects:), fn(info) { info.result })
    == [heal_description(amount: 60, kind: damage_type.Heal, overkill: 30)]
    as "40 x 1.5 = 60 is the amount the client is shown, and 60 - 30 of health room = 30 is the overheal"
}

pub fn a_shield_conversion_leaves_the_health_less_room_and_the_go_tells_the_overheal_test() -> Nil {
  use <- owned_test.run(5000)
  // `0x1405d8350` (the client's own split, which the server reproduces): with
  // HealToShieldConversion (property 111) of 0.5, a health heal of
  // 100 gives the shield int(100 x 0.5) = 50 up to the shield's room of 20 and the
  // health the other 80 up to its room of 10, so 100 - 20 - 10 = 70 is the overheal.
  let plans =
    support.plans_of([healer(heals: [flat_health_heal(amount: 100.0)])])
  let caster =
    cast.Caster(
      ..struck_caster(),
      vitals: damage.Vitals(
        health: 726,
        max_health: 736,
        shield: 430,
        max_shield: 450,
      ),
      heal_scaling: heal_split.Scaling(
        outgoing: 1.0,
        incoming: 1.0,
        to_shield: 0.5,
      ),
    )
  let #(_, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster:,
      bag: bag_of_base_3,
      at: 1000,
    )
  assert list.map(listed(effects:), fn(info) { info.result })
    == [heal_description(amount: 100, kind: damage_type.Heal, overkill: 70)]
    as "the shield takes 20 and the health 10 of the 100, so 70 is over"
}

pub fn a_shield_heal_at_full_shield_reports_the_overshield_test() -> Nil {
  use <- owned_test.run(5000)
  // 0.125 of the maximum shield (the formula of the type 118 row 210834, without its
  // tick): 0.125 x 450 = 56.25, which is 56.
  let eighth =
    heal_row(
      id: 228_914,
      vital: effect_kind.Shield,
      aim: AimsAtCaster,
      delay_ms: 0,
      condition: Always,
      formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
        Parameter(kind: 16, value: 0.125),
        Parameter(kind: 0, value: 0.0),
        Parameter(kind: 0, value: 0.0),
        Parameter(kind: 0, value: 0.0),
      ]),
    )
  let plans = support.plans_of([healer(heals: [eighth])])
  let described = fn(shield) {
    let #(_, effects) =
      support.press_as(
        plans:,
        state: cast.new(),
        caster: cast.Caster(
          ..struck_caster(),
          vitals: damage.Vitals(
            health: 500,
            max_health: 736,
            shield:,
            max_shield: 450,
          ),
        ),
        bag: bag_of_base_3,
        at: 1000,
      )
    list.map(listed(effects:), fn(info) { info.result })
  }
  assert described(450)
    == [
      heal_description(amount: 56, kind: damage_type.HealShields, overkill: 56),
    ]
    as "at full shield the whole 56 is overshield, type HealShields (5)"
  assert described(430)
    == [
      heal_description(amount: 56, kind: damage_type.HealShields, overkill: 36),
    ]
    as "20 below the maximum: 56 - 20 = 36 of it is over"
}

pub fn a_heal_aimed_at_another_unit_lands_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  // A Proxy of the parent starts the child that holds the heal aimed at the primary
  // target: on the caster that is the caster, on each struck unit it is that unit. The
  // plan refuses the second from the client's tables; this builds it to show the rule's
  // own answer (`Spell4ValidTargets.targetBitmask`; other players come with #570).
  let child =
    spell_plan.Spell(..support.child(spell4_id: 90_001, base: 90_001), heals: [
      health_heal(id: 62_019, delay_ms: 0, aim: AimsAtPrimaryTarget),
    ])
  let parent = fn(target) {
    spell_plan.Spell(..healer(heals: []), proxies: [
      spell_plan.Proxy(
        effect_id: Spell4EffectsId(90_002),
        delay_ms: 0,
        phase_flags: -1,
        condition: Always,
        tag: spend.always,
        target:,
        spell: child,
        gains: [],
      ),
    ])
  }
  let pressed = fn(target) {
    let caster = healing_caster(health: 500)
    let #(state, raw) =
      support.pressed_raw_in(
        plans: support.plans_of([parent(target)]),
        state: cast.new(),
        caster:,
        bag_index: bag_of_base_3,
        target: 0,
        at: 1000,
      )
    let #(_, effects) =
      support.answered_as(
        caster:,
        state:,
        effects: raw,
        at: 1000,
        struck: support.hits([900]),
        rolls: [],
      )
    effects
  }
  let on_caster = pressed(spell_plan.OnCaster)
  assert list.map(healed(effects: on_caster), fn(heal) { heal.2 }) == [121]
    as "control: the same child made on the caster heals it"
  let on_struck = pressed(spell_plan.OnEachStruck)
  assert healed(effects: on_struck) == []
    as "a child whose primary target is the struck unit 900 changes nothing of the caster"
  assert list.flat_map(
      support.frames_of(message_id: spell_go.message_id, effects: on_struck),
      fn(frame) {
        let assert Ok(decoded) = spell_go.decode(frame.body)
        list.flat_map(decoded.targets, fn(target) { target.effects })
      },
    )
    == []
    as "and no go lists a heal description for it"
  let assert [#(LogDebug, line)] = support.logs(effects: on_struck)
    as "one debug line says why"
  assert string.contains(line, "62019") && string.contains(line, "570")
    as "it names the row and the issue that will build heals on other units"
}

pub fn a_delayed_heal_holds_the_finish_and_drops_on_death_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 85858: a health heal 300 ms after the go, aimed at the caster among others
  // (targetFlags 5).
  let plans =
    support.plans_of([
      healer(heals: [
        health_heal(id: 85_858, delay_ms: 300, aim: AimsAtCaster),
      ]),
    ])
  let #(state, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: healing_caster(health: 500),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert support.finished_ids(support.writes(effects:)) == []
    as "the heal gives the caster's node a life of its delay: the 0x7fe is not written at the go"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.filter(fired, fn(step) {
      support.finished_ids(support.writes(effects: step.1)) == [id]
    })
    |> list.map(fn(step) { step.0 })
    == [1300]
    as "the 0x7fe comes at go + 300, the heal's own time"
  assert timeline(fired:)
    == [#(1300, support.source_of(cast_id: id, effect_id: 85_858), 121)]
    as "and the heal lands then"
  let #(dead, died) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1100),
    )
  assert healed(effects: died) == []
  let #(_, later) = support.run_timers(state: dead, effects:, from_ms: 1000)
  assert timeline(fired: later) == []
    as "the caster's death before 1300 cancels the heal's timer: nothing lands"
}
