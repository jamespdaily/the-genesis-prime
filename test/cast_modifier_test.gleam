//// The cast rule's property modifiers (`genesis_prime/game/cast` `CasterChangeStarts`,
//// `PropertyEnds`). Expected values come from these places:
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
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{type Plans, type Spell, Always}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{
  type Modifier, type Source, Change, Source,
}
import genesis_prime/message/spell_go
import genesis_prime/step.{type TimerId, TimerId}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id, UnitProperty2Id}
import gleam/int
import gleam/list
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

/// 67777 as the client holds it: FallingDamageMultiplier set to 0.0 from 180 ms for
/// 400 ms, in phase 0 only.
fn falling_row() -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(67_777),
    phase_flags: 1,
    change: spell_plan.PropertyChange(Change(
      property: UnitProperty2Id(134),
      mode: 3,
      multiplier: 0.0,
      flat: 0.0,
      per_level: 0.0,
    )),
    row: LastingRow(delay_ms: 180, duration_ms: 400, until_removed: False),
    condition: Always,
    tag: spend.always,
  )
}

fn holder(
  spell4_id spell4_id: Int,
  base base: Int,
  modifiers modifiers: List(spell_plan.PropertyModifier),
) -> Spell {
  spell_plan.Spell(..support.child(spell4_id:, base:), modifiers:)
}

// The planted base 3 is bag index 11 and base 1 is bag index 8 (`cast_support.abilities`).
const bag_of_base_3 = 11

const bag_of_base_1 = 8

fn plans_of(spells: List(Spell)) -> Plans {
  support.with_spells(plans: support.plans(), spells:)
}

fn press(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.pressed_in(
    plans:,
    state:,
    caster: support.caster(),
    bag_index: bag,
    target: 0,
    at: ms,
  )
}

fn source_of(cast_id cast_id: Int, effect_id effect_id: Int) -> Source {
  Source(cast_id:, effect_id: Spell4EffectsId(effect_id))
}

/// A modifier an effect starts or ends.
type Change {
  Started(source: Source, modifier: Modifier)
  Ended(source: Source)
}

fn change_of(effect effect: Effect) -> Result(Change, Nil) {
  case effect {
    cast.CasterChangeStarts(source:, change: cast.Property(modifier:)) ->
      Ok(Started(source:, modifier:))
    cast.CasterChangeStarts(change: cast.ShieldHeal(..), ..) -> Error(Nil)
    cast.CasterChangeStarts(change: cast.Look(..), ..) -> Error(Nil)
    cast.PropertyEnds(source:) -> Ok(Ended(source:))
    cast.Send(..)
    | cast.Tell(..)
    | cast.StartTimer(..)
    | cast.CancelTimer(..)
    | cast.Log(..)
    | cast.Strike(..)
    | cast.Pay(..)
    | cast.StealthChanged(..)
    | cast.Gain(..) -> Error(Nil)
  }
}

/// The modifiers the effects start, with their sources.
fn starts(effects effects: List(Effect)) -> List(#(Source, Modifier)) {
  list.filter_map(effects, fn(effect) {
    case change_of(effect:) {
      Ok(Started(source:, modifier:)) -> Ok(#(source, modifier))
      Ok(Ended(..)) | Error(Nil) -> Error(Nil)
    }
  })
}

/// The sources the effects end.
fn ends(effects effects: List(Effect)) -> List(Source) {
  list.filter_map(effects, fn(effect) {
    case change_of(effect:) {
      Ok(Ended(source:)) -> Ok(source)
      Ok(Started(..)) | Error(Nil) -> Error(Nil)
    }
  })
}

/// The time each step's effects were taken at, with a modifier starting or ending.
fn timeline(
  fired fired: List(#(Int, List(Effect))),
) -> List(#(Int, String, Source)) {
  list.flat_map(fired, fn(step) {
    list.flatten([
      list.map(starts(effects: step.1), fn(start) {
        #(step.0, "start", start.0)
      }),
      list.map(ends(effects: step.1), fn(source) { #(step.0, "end", source) }),
    ])
  })
}

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
    plans_of([holder(spell4_id: 57_030, base: 3, modifiers: [crit_row()])])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
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
    plans_of([holder(spell4_id: 57_030, base: 3, modifiers: [crit_row()])])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = source_of(cast_id: id, effect_id: 135_954)
  assert starts(effects:) == [#(source, crit_modifier())]
    as "a row with no delay starts in the go's own step"
  assert ends(effects:) == []
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert timeline(fired:) == [#(9000, "end", source)]
    as "it ends 8000 ms after the go, once"
}

pub fn a_modifier_with_a_delay_starts_after_it_and_ends_after_its_duration_test() -> Nil {
  use <- owned_test.run(5000)
  // Gate's 67777: from go + 180 for 400 ms.
  let plans =
    plans_of([holder(spell4_id: 34_355, base: 3, modifiers: [falling_row()])])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = source_of(cast_id: id, effect_id: 67_777)
  assert starts(effects:) == []
    as "nothing starts at the go: the row waits its delay"
  assert all_timer_delays(effects:) == [180, 580, 580]
    as "a start timer at the delay, an end timer and the node's end at delay + duration"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert timeline(fired:) == [#(1180, "start", source), #(1580, "end", source)]
    as "it starts at go + 180 and ends 400 ms later"
}

pub fn a_modifier_of_a_phase_the_go_is_not_in_is_not_applied_test() -> Nil {
  use <- owned_test.run(5000)
  // Gate's 67777 has phaseFlags 1: a go of phase 1 does not hold it.
  let go_only_in_phase_1 =
    spell_plan.PropertyModifier(..falling_row(), phase_flags: 2)
  let plans =
    plans_of([
      holder(spell4_id: 34_355, base: 3, modifiers: [go_only_in_phase_1]),
    ])
  let #(_, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert starts(effects:) == []
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
    plans_of([holder(spell4_id: 57_030, base: 3, modifiers: [until_removed])])
  let #(_, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert list.length(starts(effects:)) == 1
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
    plans_of([holder(spell4_id: 57_030, base: 3, modifiers: [lifeless])])
  let #(_, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert starts(effects:) == []
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
  let plans = plans_of([holder(spell4_id: 57_030, base: 3, modifiers: [gated])])
  let #(_, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert starts(effects:) == []
    as "a row behind a target prerequisite is not applied, as a Fluff effect's is not"
}

// ---- a later go, a removal and a death ----

fn two_gos() -> Plans {
  plans_of([
    spell_plan.Spell(
      ..holder(spell4_id: 57_030, base: 3, modifiers: [crit_row()]),
      phase_delays_ms: [0, 1000],
    ),
  ])
}

pub fn a_later_go_of_the_cast_arms_its_modifier_again_from_that_go_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, effects) =
    press(plans: two_gos(), state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = source_of(cast_id: id, effect_id: 135_954)
  assert list.map(starts(effects:), fn(start) { start.0 }) == [source]
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  let ending = list.filter(timeline(fired:), fn(entry) { entry.1 == "end" })
  assert ending == [#(10_000, "end", source)]
    as "the modifier ends 8000 ms after the second go, at 2000, and once: the first go's end timer was cancelled"
  let starting_again =
    list.filter(timeline(fired:), fn(entry) { entry.1 == "start" })
  assert starting_again == [#(2000, "start", source)]
    as "the second go names the same source again, which the properties hold once"
}

pub fn a_type_80_removal_of_the_cast_ends_its_modifiers_and_cancels_their_timers_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([
      holder(spell4_id: 57_030, base: 3, modifiers: [crit_row()]),
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
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects: first)
  let #(_, removal) = press(plans:, state:, bag: bag_of_base_1, at: 2000)
  assert ends(effects: removal) == [source_of(cast_id: id, effect_id: 135_954)]
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
    plans_of([
      spell_plan.Spell(
        ..holder(spell4_id: 34_355, base: 3, modifiers: [falling_row()]),
        longer_of_delay_and_duration: True,
      ),
    ])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = source_of(cast_id: id, effect_id: 67_777)
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert timeline(fired:) == [#(1180, "start", source), #(1400, "end", source)]
    as "the modifier ends with its node at go + 400 and its own end timer at go + 580 never fires"
}

pub fn the_caster_dying_ends_every_modifier_still_pending_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([holder(spell4_id: 34_355, base: 3, modifiers: [falling_row()])])
  let #(state, effects) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let #(_, ended) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1100),
    )
  assert ends(effects: ended) == [source_of(cast_id: id, effect_id: 67_777)]
    as "the modifier had not started, and its end is told: the properties hold none, so it changes nothing"
}

pub fn a_caster_that_leaves_ends_no_modifier_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    plans_of([holder(spell4_id: 57_030, base: 3, modifiers: [crit_row()])])
  let #(state, _) =
    press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let #(_, left) = cast.left(cast: state)
  assert ends(effects: left) == []
    as "the connection's properties go with the player's Entered"
}
