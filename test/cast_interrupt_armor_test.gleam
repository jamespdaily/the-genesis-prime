//// The cast rule's Interrupt Armor rows (`genesis_prime/game/cast` `CasterChangeStarts`,
//// `CasterChangeEnds`): a row is a change of property 44, whose armor the player's armor
//// follows (`player_life_interrupt_armor_test`). Expected values come from these places:
//// - `Spell4Effects.effectType.52`: a type 52 row adds dataBits00 points of Interrupt
////   Armor to the unit it lands on for durationTime; Esper's row 199192 of Spell4 76766
////   is +1 for 5000 ms with dataBits01 0 (the armor is kept at the end), and row 210820
////   of Spell4 79875 is +2 for 8000 ms with dataBits01 1 (taken back); row 210961 of
////   Spell4 79917 has flags 2 and a delay of 150000 (`table_rows -- Spell4Effects
////   spellId=76766`, `=79875`, `210961`).
//// - `opcode.0x7f4.effect_time` and `Spell4Effects.effectType.17`: an effect that has a
////   lifetime gives its spell a node on its unit, which lives as long as the longest
////   effect, so a spell whose only effect is an Interrupt Armor row shows its buff for
////   the row's time and the client's 0x7fe waits for the last node; an effect whose
////   flags have bit 2 never ends.
//// - The type 11 precedent (`cast_modifier_test`): the row starts at the go plus its
////   delay and ends after its duration by a timer of its own; a node taken off the
////   caster, a persistence that stops holding and the caster's death end it and cancel
////   its timers; a later go of the cast arms it again from that go.

import cast_support as support
import genesis_prime/game/cast
import genesis_prime/game/lasting.{type LastingRow, LastingRow}
import genesis_prime/game/spell_plan.{AimsAtCaster, Always, InterruptArmor}
import genesis_prime/game/spend
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test
import prerequisite_support as prerequisites

// The planted base 3 is bag index 11 and base 1 is bag index 8 (`cast_support.abilities`).
const bag_of_base_3 = 11

const bag_of_base_1 = 8

/// Row 199192 as the client holds it: +1 for 5000 ms, kept at the end.
fn spectral_form_row() -> spell_plan.PropertyModifier {
  armor_row(
    id: 199_192,
    points: 1,
    takes_back: False,
    row: LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False),
  )
}

fn armor_row(
  id id: Int,
  points points: Int,
  takes_back takes_back: Bool,
  row row: LastingRow,
) -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    change: spell_plan.PropertyChange(
      support.raising_interrupt_armor_threshold(points: int.to_float(points)),
    ),
    row:,
    condition: Always,
    tag: spend.always,
    armor: Some(InterruptArmor(points:, takes_back:, aim: AimsAtCaster)),
  )
}

// ---- what a go lists and how long the cast lasts ----

pub fn a_go_with_interrupt_armor_lists_it_on_the_caster_and_gives_the_node_its_time_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 76_766, base: 3, modifiers: [
        spectral_form_row(),
      ]),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.unit_id == 7 as "the caster is the unit the row aims at"
  assert list.map(info.effects, fn(effect) {
      #(effect.spell4_effects_id, effect.delay_ms, effect.result)
    })
    == [
      #(199_192, 0, spell_effect_result.Bit(SpellEffectBit(field_2: 0))),
    ]
    as "row 199192 is listed with a bit result, as a Fluff effect is"
  assert support.finished_ids(support.writes(effects:)) == []
    as "the node has life, so the 0x7fe waits (cast.target_node_end)"
  assert list.length(support.property_starts(effects:)) == 1
    as "and the armor starts in the go's own step"
  let id = support.pressed_id(effects:)
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  let finishes =
    list.filter(fired, fn(step) {
      support.finished_ids(support.writes(effects: step.1)) == [id]
    })
  assert list.map(finishes, fn(step) { step.0 }) == [6000]
    as "the buff shows for the row's 5000 ms from the go"
}

// ---- when the armor starts and ends ----

pub fn interrupt_armor_with_no_delay_starts_in_the_gos_step_and_ends_after_its_duration_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 76_766, base: 3, modifiers: [
        spectral_form_row(),
      ]),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 199_192)
  assert support.property_starts(effects:)
    == [#(source, support.raising_interrupt_armor_threshold(points: 1.0))]
    as "row 199192: x 1.0 + 1 on property 44, in the go's own step"
  assert support.caster_change_ends(effects:) == []
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:) == [#(6000, "end", source)]
    as "it ends 5000 ms after the go, once"
}

pub fn interrupt_armor_with_a_delay_starts_on_a_timer_test() -> Nil {
  use <- owned_test.run(20_000)
  // Row 210961: delay 150000 and flags 2, which never ends.
  let delayed =
    armor_row(
      id: 210_961,
      points: 1,
      takes_back: True,
      row: LastingRow(delay_ms: 150_000, duration_ms: 0, until_removed: True),
    )
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 79_917, base: 3, modifiers: [delayed]),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 210_961)
  assert support.property_starts(effects:) == []
    as "nothing starts at the go: the row waits its delay"
  assert list.map(support.started_timers(effects:), fn(timer) { timer.1 })
    == [150_000]
    as "one start timer, and no end timer or node end for a row that never ends"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:) == [#(151_000, "start", source)]
    as "it starts at go + 150000 and never ends"
  assert list.flat_map(fired, fn(step) {
      support.property_starts(effects: step.1)
    })
    == [#(source, support.raising_interrupt_armor_threshold(points: 1.0))]
}

// ---- a removal, a persistence, a death and a later go ----

pub fn interrupt_armor_ends_at_once_when_its_node_is_taken_off_or_its_persistence_fails_test() -> Nil {
  use <- owned_test.run(20_000)
  // A type 80 removal of the cast.
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 76_766, base: 3, modifiers: [
        spectral_form_row(),
      ]),
      spell_plan.Spell(..support.child(spell4_id: 301, base: 1), removes: [
        spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(196_521),
          phase_flags: -1,
          aim: spell_plan.AimsAtCaster,
          selector: lasting.Spell(Spell4Id(76_766)),
          count: 1,
          condition: Always,
          tag: spend.always,
        ),
      ]),
    ])
  let #(state, first) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects: first)
  assert list.length(support.property_starts(effects: first)) == 1
    as "the armor started in the press's go"
  let #(_, removal) =
    support.press(plans:, state:, bag: bag_of_base_1, at: 2000)
  assert support.caster_change_ends(effects: removal)
    == [support.source_of(cast_id: id, effect_id: 199_192)]
    as "taking the cast's node off the caster ends the armor at once"
  assert support.timer_numbers(timers: support.cancelled_timers(
      effects: removal,
    ))
    == support.timer_numbers(
      timers: list.map(support.started_timers(effects: first), fn(started) {
        started.0
      }),
    )
    as "exactly the two timers the press started are cancelled: the armor's end and the node's end"
  // A persistence that stops holding: prerequisite 903, type 28 comparison 1, the caster
  // in combat.
  let in_combat = prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
  let guarded =
    support.plans_of([
      spell_plan.Spell(
        ..support.spell_holding(spell4_id: 76_766, base: 3, modifiers: [
          spectral_form_row(),
        ]),
        caster_persistence: Some(in_combat),
      ),
    ])
  let fighting = cast.Caster(..support.caster(), in_combat: True)
  let #(lingering, pressed) =
    support.pressed_in(
      plans: guarded,
      state: cast.new(),
      caster: fighting,
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let held_id = support.pressed_id(effects: pressed)
  assert list.length(support.property_starts(effects: pressed)) == 1
    as "the armor started in the press's go"
  let #(_, ended) =
    cast.persisted(
      cast: lingering,
      caster: cast.Caster(..support.caster(), in_combat: False),
      now: support.at(ms: 2000),
    )
  assert support.caster_change_ends(effects: ended)
    == [support.source_of(cast_id: held_id, effect_id: 199_192)]
    as "the persistence ends the cast as a death ends one, and the armor with it"
  assert support.timer_numbers(timers: support.cancelled_timers(effects: ended))
    == support.timer_numbers(
      timers: list.map(support.started_timers(effects: pressed), fn(started) {
        started.0
      }),
    )
    as "and its two timers are cancelled"
}

pub fn the_casters_death_ends_its_interrupt_armor_test() -> Nil {
  use <- owned_test.run(20_000)
  let delayed =
    armor_row(
      id: 210_961,
      points: 1,
      takes_back: True,
      row: LastingRow(delay_ms: 150_000, duration_ms: 0, until_removed: True),
    )
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 76_766, base: 3, modifiers: [
        spectral_form_row(),
      ]),
      support.spell_holding(spell4_id: 79_917, base: 1, modifiers: [delayed]),
    ])
  let #(state, first) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  assert list.length(support.property_starts(effects: first)) == 1
    as "the first cast's armor started in its go"
  let #(state, second) =
    support.press(plans:, state:, bag: bag_of_base_1, at: 1100)
  let #(_, ended) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1200),
    )
  assert support.caster_change_ends(effects: ended)
    == [
      support.source_of(
        cast_id: support.pressed_id(effects: first),
        effect_id: 199_192,
      ),
      support.source_of(
        cast_id: support.pressed_id(effects: second),
        effect_id: 210_961,
      ),
    ]
    as "the one that started and the one still pending are both told ended: every grant of its casts, in cast order (no passive holds a type 52 row)"
}

pub fn a_later_go_of_the_same_cast_arms_the_armor_again_and_holds_it_once_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    support.plans_of([
      spell_plan.Spell(
        ..support.spell_holding(spell4_id: 76_766, base: 3, modifiers: [
          spectral_form_row(),
        ]),
        phase_delays_ms: [0, 1000],
      ),
    ])
  let #(state, effects) =
    support.press(plans:, state: cast.new(), bag: bag_of_base_3, at: 1000)
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 199_192)
  assert list.map(support.property_starts(effects:), fn(start) { start.0 })
    == [source]
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.filter(support.timeline(fired:), fn(entry) { entry.1 == "start" })
    == [#(2000, "start", source)]
    as "the second go names the same source again, which the player's properties and life hold once (unit_properties: the same source applied twice is held once)"
  assert list.filter(support.timeline(fired:), fn(entry) { entry.1 == "end" })
    == [#(7000, "end", source)]
    as "the armor ends 5000 ms after the second go, once: the first go's end timer was cancelled"
}
