//// The cast rule's property modifiers (`genesis_prime/game/cast` `CasterChangeStarts`,
//// `CasterChangeEnds`). Expected values come from these places:
//// - `Spell4Effects.effectType.11.change`: a type 11 row applies at its go plus its
////   delayTime for its durationTime; the kit's two rows are 135954 (BaseCritChance,
////   multiplier 1.0, flat 0.08, no delay, 8000 ms, every phase) and 67777
////   (FallingDamageMultiplier, 0.0 and 0.0, delay 180, duration 400, phase 0).
//// - `Spell4Effects.effectType.17` and `opcode.0x7f4.effect_time`: an effect that has a
////   lifetime gives its spell a node on its unit, whose life is the longest effect's, so
////   a spell whose only effect is a type 11 row shows its buff for the row's time; the
////   client ends no buff on time, so the 0x7fe waits for the last node.
//// - The server's choices, in the cast rule's doc: the modifier ends at its own end by
////   a timer, a node taken off the caster ends the cast's modifiers, the caster's death
////   ends every modifier still pending, and a later go of the cast arms its modifier
////   again from that go.

import cast_support as support
import genesis_prime/game/cast.{type Effect}
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{type Plans, Always}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{type Modifier, Change}
import genesis_prime/message/spell_go
import genesis_prime/step.{type TimerId, TimerId}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id, UnitProperty2Id}
import gleam/int
import gleam/list
import gleam/option.{None}
import owned_test

/// 135954 as the client holds it: BaseCritChance, multiplier 1.0, flat 0.08, 8000 ms.
fn crit_row() -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(135_954),
    phase_flags: -1,
    change: spell_plan.PropertyChange(crit_modifier()),
    row: LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
    condition: Always,
    tag: spend.always,
    armor: None,
  )
}

fn crit_modifier() -> Modifier {
  Change(
    property: UnitProperty2Id(102),
    mode: 3,
    multiplier: 1.0,
    flat: 0.08,
    per_level: 0.0,
  )
}

// The planted base 3 is bag index 11 and base 1 is bag index 8 (`cast_support.abilities`).
const bag_of_base_3 = 11

const bag_of_base_1 = 8

fn all_timer_delays(effects effects: List(Effect)) -> List(Int) {
  list.map(support.started_timers(effects:), fn(timer) { timer.1 })
  |> list.sort(int.compare)
}

// ---- what a go lists and how long the cast lasts ----

pub fn a_go_lists_a_modifier_aimed_at_the_caster_and_its_node_lives_for_the_row_test() -> Nil {
  use <- owned_test.run(5000)
  // Mind Burst's 57030 holds only 135954: its go lists the row on the caster, and the
  // cast waits for the node's 8 s before its 0x7fe.
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 57_030, base: 3, modifiers: [crit_row()]),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.unit_id == 7 as "the caster is the unit the row aims at"
  assert list.map(info.effects, fn(effect) { effect.spell4_effects_id })
    == [135_954]
  assert support.finished_ids(support.writes(effects:)) == []
    as "the node has life, so the 0x7fe waits (cast.target_node_end)"
  let id = support.pressed_id(effects:)
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  let finishes =
    list.filter(fired, fn(step) {
      support.finished_ids(support.writes(effects: step.1)) == [id]
    })
  assert list.map(finishes, fn(step) { step.0 }) == [9000]
    as "the buff shows for the row's 8000 ms from the go"
}

// ---- when a modifier starts and ends ----

pub fn a_modifier_with_no_delay_starts_at_the_go_and_ends_after_its_duration_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 57_030, base: 3, modifiers: [crit_row()]),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 135_954)
  assert support.property_starts(effects:) == [#(source, crit_modifier())]
    as "a row with no delay starts in the go's own step"
  assert support.caster_change_ends(effects:) == []
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:) == [#(9000, "end", source)]
    as "it ends 8000 ms after the go, once"
}

pub fn a_modifier_with_a_delay_starts_after_it_and_ends_after_its_duration_test() -> Nil {
  use <- owned_test.run(5000)
  // Gate's 67777: from go + 180 for 400 ms.
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 34_355, base: 3, modifiers: [
        support.falling_row(),
      ]),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 67_777)
  assert support.property_starts(effects:) == []
    as "nothing starts at the go: the row waits its delay"
  assert all_timer_delays(effects:) == [180, 580, 580]
    as "a start timer at the delay, an end timer and the node's end at delay + duration"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:)
    == [#(1180, "start", source), #(1580, "end", source)]
    as "it starts at go + 180 and ends 400 ms later"
}

pub fn a_modifier_of_a_phase_the_go_is_not_in_is_not_applied_test() -> Nil {
  use <- owned_test.run(5000)
  // Gate's 67777 has phaseFlags 1: a go of phase 1 does not hold it.
  let go_only_in_phase_1 =
    spell_plan.PropertyModifier(..support.falling_row(), phase_flags: 2)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 34_355, base: 3, modifiers: [
        go_only_in_phase_1,
      ]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert support.property_starts(effects:) == []
  assert all_timer_delays(effects:) == []
    as "no row applies in phase 0, so no node and no timer"
}

pub fn a_modifier_that_lasts_until_removed_starts_at_the_go_and_has_no_end_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let until_removed =
    spell_plan.PropertyModifier(
      ..crit_row(),
      row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    )
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 57_030, base: 3, modifiers: [
        until_removed,
      ]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert list.length(support.property_starts(effects:)) == 1
  assert all_timer_delays(effects:) == []
    as "flags bit 2: the modifier and the node end only when the cast is taken off"
  assert support.finished_ids(support.writes(effects:)) == []
}

pub fn a_row_with_no_life_applies_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let lifeless =
    spell_plan.PropertyModifier(
      ..crit_row(),
      row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
    )
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 57_030, base: 3, modifiers: [lifeless]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert support.property_starts(effects:) == []
    as "a zero duration is no time to be changed for"
  assert list.length(support.finished_ids(support.writes(effects:))) == 1
    as "and no node, so the cast finishes with its go"
}

pub fn a_modifier_behind_a_target_prerequisite_is_not_applied_test() -> Nil {
  use <- owned_test.run(5000)
  let gated =
    spell_plan.PropertyModifier(
      ..crit_row(),
      condition: spell_plan.GatedOnTarget(prerequisite_id: id.PrerequisiteId(5)),
    )
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 57_030, base: 3, modifiers: [gated]),
    ])
  let #(_, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert support.property_starts(effects:) == []
    as "a row behind a target prerequisite is not applied, as a Fluff effect's is not"
}

// ---- a later go, a removal and a death ----

fn two_gos() -> Plans {
  support.plans_of([
    spell_plan.Spell(
      ..support.spell_holding(spell4_id: 57_030, base: 3, modifiers: [
        crit_row(),
      ]),
      phase_delays_ms: [0, 1000],
    ),
  ])
}

pub fn a_later_go_of_the_cast_arms_its_modifier_again_from_that_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    support.press(
      plans: two_gos(),
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 135_954)
  assert list.map(support.property_starts(effects:), fn(start) { start.0 })
    == [source]
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  let ending =
    list.filter(support.timeline(fired:), fn(entry) { entry.1 == "end" })
  assert ending == [#(10_000, "end", source)]
    as "the modifier ends 8000 ms after the second go, at 2000, and once: the first go's end timer was cancelled"
  let starting_again =
    list.filter(support.timeline(fired:), fn(entry) { entry.1 == "start" })
  assert starting_again == [#(2000, "start", source)]
    as "the second go names the same source again, which the properties hold once"
}

pub fn a_type_80_removal_of_the_cast_ends_its_modifiers_and_cancels_their_timers_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 57_030, base: 3, modifiers: [crit_row()]),
      spell_plan.Spell(..support.child(spell4_id: 301, base: 1), removes: [
        spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(196_521),
          phase_flags: -1,
          aim: spell_plan.AimsAtCaster,
          selector: lasting.Spell(Spell4Id(57_030)),
          count: 1,
          condition: Always,
          tag: spend.always,
        ),
      ]),
    ])
  let #(state, first) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects: first)
  let #(_, removal) =
    support.press(plans:, state:, bag: bag_of_base_1, at: 2000)
  assert support.caster_change_ends(effects: removal)
    == [support.source_of(cast_id: id, effect_id: 135_954)]
    as "taking the cast's node off the caster ends its modifier at once"
  let numbers = fn(timers: List(TimerId)) {
    list.map(timers, fn(timer) {
      let TimerId(number) = timer
      number
    })
    |> list.sort(int.compare)
  }
  assert numbers(support.cancelled_timers(effects: removal))
    == numbers(
      list.map(support.started_timers(effects: first), fn(started) { started.0 }),
    )
    as "exactly the two timers the first press started are cancelled: the modifier's end and the node's end"
}

pub fn a_node_that_ends_by_time_ends_its_modifiers_and_cancels_their_timers_test() -> Nil {
  use <- owned_test.run(5000)
  // A spell whose propertyFlags have bit 0x2000 takes the larger of delay and duration
  // for a node's life (`Spell4.propertyFlags`, `opcode.0x7f4.effect_time`): Gate's row
  // (delay 180, duration 400) gives a node that ends at go + 400, while the modifier's own
  // end is go + 580. The node's end ends the modifier, as taking the node off does.
  let plans =
    support.plans_of([
      spell_plan.Spell(
        ..support.spell_holding(spell4_id: 34_355, base: 3, modifiers: [
          support.falling_row(),
        ]),
        longer_of_delay_and_duration: True,
      ),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 67_777)
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:)
    == [#(1180, "start", source), #(1400, "end", source)]
    as "the modifier ends with its node at go + 400 and its own end timer at go + 580 never fires"
}

pub fn the_caster_dying_ends_every_modifier_still_pending_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 34_355, base: 3, modifiers: [
        support.falling_row(),
      ]),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let #(_, ended) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1100),
    )
  assert support.caster_change_ends(effects: ended)
    == [support.source_of(cast_id: id, effect_id: 67_777)]
    as "the modifier had not started, and its end is told: the properties hold none, so it changes nothing"
}

pub fn a_caster_that_leaves_ends_no_modifier_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 57_030, base: 3, modifiers: [crit_row()]),
    ])
  let #(state, _) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let #(_, left) = cast.left(cast: state)
  assert support.caster_change_ends(effects: left) == []
    as "the connection's properties go with the player's Entered"
}

// ---- a modifier aimed at the units the go struck ----
//
// A type 11 row whose targetFlags are 2, 4 or 6 aims at units other than the caster; the
// cast starts it on each creature the go struck and ends it on every path a node ends
// (`Spell4Effects.targetFlags`). The row is 7711 as the client holds it: Spell4 671,
// targetFlags 4 (the units the go hit), property 100, mode 2, multiplier 0.5 (dataBits02
// 1056964608 = 0x3F000000), flat 0, per level 0, from go + 1000 ms for 5000 ms, phase 0.

const creature = 21

const other_player = 22

const bag_of_base_2 = 10

/// 7711 as the client holds it.
fn slowing_row() -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(7711),
    phase_flags: 1,
    change: spell_plan.StruckChange(
      modifier: slowing_modifier(),
      aim: spell_plan.AimsAtArea,
    ),
    row: LastingRow(delay_ms: 1000, duration_ms: 5000, until_removed: False),
    condition: Always,
    tag: spend.always,
    armor: None,
  )
}

fn slowing_modifier() -> Modifier {
  Change(
    property: UnitProperty2Id(100),
    mode: 2,
    multiplier: 0.5,
    flat: 0.0,
    per_level: 0.0,
  )
}

/// The same row with no delay, so its start is in the go's own step.
fn immediate_row(effect_id effect_id: Int) -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    ..slowing_row(),
    effect_id: Spell4EffectsId(effect_id),
    row: LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False),
  )
}

/// The creature 21 in its life 3, struck at the monotonic time 1000.
fn creature_struck() -> List(cast.Struck) {
  [
    cast.Hit(
      unit_id: creature,
      unit: cast.HitCreature(life: 3, struck_at_ms: 1000),
      descriptions: [],
      controls: [],
    ),
  ]
}

fn pressed_striking(
  plans plans: Plans,
  state state: cast.State,
  bag bag: Int,
  struck struck: List(cast.Struck),
  at ms: Int,
) -> #(cast.State, List(Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: support.caster(),
      bag_index: bag,
      target: 0,
      at: ms,
    )
  support.answered_by(state:, effects:, at: ms, struck:)
}

fn striking_plans(row: spell_plan.PropertyModifier) -> Plans {
  support.plans_of([
    support.spell_holding(spell4_id: 671, base: 3, modifiers: [row]),
  ])
}

fn started_on_creature(source: unit_properties.Source) -> Effect {
  cast.TargetChangeStarts(
    unit_id: creature,
    life: 3,
    struck_at_ms: 1000,
    source:,
    modifier: slowing_modifier(),
  )
}

fn ended_on_creature(source: unit_properties.Source) -> Effect {
  cast.TargetChangeEnds(unit_id: creature, life: 3, source:)
}

pub fn go_lists_modifier_in_creature_target_info_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    pressed_striking(
      plans: striking_plans(slowing_row()),
      state: cast.new(),
      bag: bag_of_base_3,
      struck: creature_struck(),
      at: 1000,
    )
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] =
    list.filter(decoded.targets, fn(target) { target.unit_id == creature })
    as "the struck creature is a unit of the go"
  assert list.map(info.effects, fn(effect) { effect.spell4_effects_id })
    == [7711]
    as "the row aimed at the units the go hit is an effect of the creature's entry"
  assert list.filter(decoded.targets, fn(target) { target.unit_id == 7 }) == []
    as "and not of the caster's, which the row does not aim at"
}

pub fn modifier_on_creature_starts_after_delay_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = striking_plans(slowing_row())
  let #(state, effects) =
    pressed_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: creature_struck(),
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 7711)
  assert support.target_changes(effects:) == []
    as "the row waits its delayTime of 1000 ms: nothing starts at the go"
  assert support.caster_change_starts(effects:) == []
    as "and the caster's own properties are not the row's"
  let #(_, fired) =
    support.run_timers_striking(
      state:,
      effects:,
      from_ms: 1000,
      struck: creature_struck(),
    )
  assert support.target_timeline(fired:)
    == [
      #(2000, started_on_creature(source)),
      #(7000, ended_on_creature(source)),
    ]
    as "it starts at go + 1000 for the life and the strike time of the hit, and ends with the node at go + 1000 + 5000"
}

pub fn node_end_ends_creature_modifier_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = striking_plans(immediate_row(effect_id: 7711))
  let #(state, effects) =
    pressed_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: creature_struck(),
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 7711)
  assert support.target_changes(effects:) == [started_on_creature(source)]
    as "a row with no delay starts in the go's own step"
  let #(state, fired) =
    support.run_timers_striking(
      state:,
      effects:,
      from_ms: 1000,
      struck: creature_struck(),
    )
  assert support.target_timeline(fired:) == [#(6000, ended_on_creature(source))]
    as "the node's life is the row's 5000 ms, and its end ends the modifier once"
  let assert [#(_, ending)] =
    list.filter(fired, fn(step) {
      support.target_changes(effects: step.1) != []
    })
  assert support.finished_ids(support.writes(effects: ending)) == [id]
    as "the lingering cast left with no node ends with its 0x7fe, as for any lasting node"
  assert support.target_changes(effects: cast.left(cast: state).1) == []
    as "and nothing is told again when the caster leaves"
}

pub fn removal_ends_creature_modifier_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 671, base: 3, modifiers: [
        immediate_row(effect_id: 7711),
      ]),
      spell_plan.Spell(..support.child(spell4_id: 301, base: 1), removes: [
        spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(196_521),
          phase_flags: -1,
          aim: spell_plan.AimsAtArea,
          selector: lasting.Spell(Spell4Id(671)),
          count: 1,
          condition: Always,
          tag: spend.always,
        ),
      ]),
    ])
  let #(state, first) =
    pressed_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: creature_struck(),
      at: 1000,
    )
  let id = support.pressed_id(effects: first)
  let source = support.source_of(cast_id: id, effect_id: 7711)
  let #(state, removal) =
    pressed_striking(
      plans:,
      state:,
      bag: bag_of_base_1,
      struck: creature_struck(),
      at: 2000,
    )
  assert support.target_changes(effects: removal) == [ended_on_creature(source)]
    as "the type 80 row takes the cast's node off the creature, which ends its modifier"
  assert list.contains(
    support.removed_targets(support.writes(effects: removal)),
    #(id, [creature]),
  )
    as "with the 0x811 for the creature"
  let #(_, fired) =
    support.run_timers_striking(
      state:,
      effects: first,
      from_ms: 1000,
      struck: creature_struck(),
    )
  assert support.target_timeline(fired:) == []
    as "its node's end timer was cancelled with the node, so nothing ends it twice"
  assert support.target_changes(effects: cast.left(cast: state).1) == []
}

pub fn caster_death_ends_creature_modifier_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = striking_plans(immediate_row(effect_id: 7711))
  let #(state, effects) =
    pressed_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: creature_struck(),
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 7711)
  let #(state, died) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1100),
    )
  assert support.target_changes(effects: died) == [ended_on_creature(source)]
    as "the cast's modifier on the creature is told ended, once"
  assert support.target_changes(effects: cast.left(cast: state).1) == []
    as "and the caster's leaving tells nothing more"
}

pub fn creature_leaving_sight_ends_its_modifier_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = striking_plans(immediate_row(effect_id: 7711))
  let #(state, effects) =
    pressed_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: creature_struck(),
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 7711)
  let #(state, removed) =
    cast.unit_removed(cast: state, unit_id: creature, now_ms: 1100)
  assert support.target_changes(effects: removed) == [ended_on_creature(source)]
    as "the cast drops its node on a creature that left the caster's sight, so the modifier it holds there ends with it"
  assert support.target_changes(effects: cast.left(cast: state).1) == []
    as "and is not told again"
}

pub fn pushed_off_node_ends_creature_modifier_test() -> Nil {
  use <- owned_test.run(5000)
  // Two spells of the stack group 5 with a cap of 1: the second cast's node on the
  // creature pushes the first cast's off (`lasting.pushed_off`, Jim's decision).
  let stacking = lasting.Stack(group_id: 5, cap: 1)
  let plans =
    support.plans_of([
      spell_plan.Spell(
        ..support.spell_holding(spell4_id: 671, base: 3, modifiers: [
          immediate_row(effect_id: 7711),
        ]),
        stack: stacking,
      ),
      spell_plan.Spell(
        ..support.spell_holding(spell4_id: 672, base: 2, modifiers: [
          immediate_row(effect_id: 7712),
        ]),
        stack: stacking,
      ),
    ])
  let #(state, first) =
    pressed_striking(
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      struck: creature_struck(),
      at: 1000,
    )
  let first_id = support.pressed_id(effects: first)
  let #(_, second) =
    pressed_striking(
      plans:,
      state:,
      bag: bag_of_base_2,
      struck: creature_struck(),
      at: 2000,
    )
  let second_id = support.pressed_id(effects: second)
  assert support.target_changes(effects: second)
    == [
      ended_on_creature(support.source_of(cast_id: first_id, effect_id: 7711)),
      started_on_creature(support.source_of(cast_id: second_id, effect_id: 7712)),
    ]
    as "the first cast's modifier ends when its node is pushed off, before the second starts"
  assert list.contains(
    support.removed_targets(support.writes(effects: second)),
    #(first_id, [creature]),
  )
    as "with the 0x811 for the creature"
}

pub fn modifier_on_another_player_is_left_out_test() -> Nil {
  use <- owned_test.run(5000)
  // A row aimed at a player other than the caster changes nothing until a modifier on
  // another player is built (#570).
  let struck = [
    cast.Hit(
      unit_id: other_player,
      unit: cast.HitPlayer,
      descriptions: [],
      controls: [],
    ),
  ]
  let #(_, effects) =
    pressed_striking(
      plans: striking_plans(immediate_row(effect_id: 7711)),
      state: cast.new(),
      bag: bag_of_base_3,
      struck:,
      at: 1000,
    )
  assert support.target_changes(effects:) == []
  assert support.caster_change_starts(effects:) == []
  assert all_timer_delays(effects:) == [] as "and no node, so no timer"
}
