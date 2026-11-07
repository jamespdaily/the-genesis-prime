//// The cast rule's Absorption rows (`genesis_prime/game/cast` `CasterChangeStarts` of an
//// `Absorb`, `CasterChangeEnds`): a row is a pool the caster's life holds
//// (`player_life_absorb_test`). Expected values come from these places.
//// - `Spell4Effects.effectType.29`: an Absorption row gives the unit it lands on a pool of
////   an amount for durationTime that takes the damage types of dataBits04; Esper's row
////   178144 of Spell4 58586 (Spectral Form) is targetFlags 1, durationTime 5000, mask 7,
////   Assault Power x 2.531 and Support Power x 2.531, phaseFlags 1, and a level-1 Novice
////   (Assault Rating 203.0625, Support Rating 55.6875, `player.level1_gear_properties`)
////   gets round(2.531 x 50.765625 + 2.531 x 13.921875) = 164 of it (`table_rows --
////   Spell4Effects spellId=58586`). Row 56356 of Spell4 30724 has targetFlags 2, delayTime
////   251 and durationTime 10000; the rows planted here give it the formula 1.0 x 100.0
////   (its dataBits01 is 1120403456 = 100.0; its own dataBits00 is 0).
//// - `opcode.0x7f4.effect_time` and `Spell4Effects.effectType.17`: an effect that has a
////   lifetime gives its spell a node on its unit, which lives as long as the longest
////   effect, so a spell whose only effect is an Absorption row shows its buff for the
////   row's time and the client's 0x7fe waits for the last node.
//// - The type 11 precedent (`cast_modifier_test`, `cast_interrupt_armor_test`): the row
////   starts at the go plus its delay and ends after its duration by a timer of its own; a
////   node taken off the caster, a persistence that stops holding and the caster's death
////   end it and cancel its timers.
//// - The gates' rule (`cast_shield_heal_test`): a go's effects read the caster as it
////   stood before the go's own effects.

import attacker_support
import cast_support as support
import genesis_prime/game/cast.{type Effect}
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/lasting.{type LastingRow, LastingRow}
import genesis_prime/game/spell_plan.{Absorption, AimsAtCaster, Always}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{type Source, Change}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_go
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id, UnitProperty2Id}
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support as prerequisites

// The planted base 3 is bag index 11 and base 1 is bag index 8 (`cast_support.abilities`).
const bag_of_base_3 = 11

const bag_of_base_1 = 8

/// A level-1 Novice: Assault Rating 203.0625 and Support Rating 55.6875.
fn novice() -> cast.Caster {
  cast.Caster(..support.caster(), stats: attacker_support.novice())
}

/// Row 178144's formula as the client holds it.
fn spectral_form_row_formula() -> damage.Formula {
  Formula(multiplier: 1.0, base: 0.0, parameters: [
    Parameter(kind: 12, value: 2.5309998989105225),
    Parameter(kind: 13, value: 2.5309998989105225),
    Parameter(kind: 0, value: 0.0),
    Parameter(kind: 0, value: 0.0),
  ])
}

/// Row 178144 as the client holds it.
fn spectral_form_row() -> spell_plan.PropertyModifier {
  absorb_row(
    id: 178_144,
    formula: spectral_form_row_formula(),
    row: LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False),
  )
}

fn absorb_row(
  id id: Int,
  formula formula: damage.Formula,
  row row: LastingRow,
) -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(id),
    phase_flags: 1,
    change: spell_plan.AbsorbChange(Absorption(
      formula:,
      mask: 7,
      aim: AimsAtCaster,
    )),
    row:,
    condition: Always,
    tag: spend.always,
    armor: None,
  )
}

/// The absorbs the effects start, with their sources: the amount and the mask.
fn starts(effects effects: List(Effect)) -> List(#(Source, Int, Int)) {
  list.filter_map(support.caster_change_starts(effects:), fn(start) {
    case start.1 {
      cast.Absorb(amount:, mask:) -> Ok(#(start.0, amount, mask))
      cast.Property(..) | cast.ShieldHeal(..) | cast.Look(..) -> Error(Nil)
    }
  })
}

pub fn spectral_forms_go_lists_its_absorb_on_the_caster_and_starts_it_for_five_seconds_test() -> Nil {
  use <- owned_test.run(120_000)
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 58_586, base: 3, modifiers: [
        spectral_form_row(),
      ]),
    ])
  let #(state, effects) =
    support.press_as(
      caster: novice(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  assert info.unit_id == 7 as "the caster is the unit the row aims at"
  assert list.map(info.effects, fn(effect) {
      #(effect.spell4_effects_id, effect.delay_ms, effect.result)
    })
    == [
      #(178_144, 0, spell_effect_result.Bit(SpellEffectBit(field_2: 0))),
    ]
    as "row 178144 is listed with a bit result, as a Fluff effect is"
  assert support.finished_ids(support.writes(effects:)) == []
    as "the node has life, so the 0x7f4's 0x7fe waits (cast.target_node_end)"
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 178_144)
  assert starts(effects:) == [#(source, 164, 7)]
    as "Absorb(164, 7) starts in the go's own step: round(2.531 x 50.765625 + 2.531 x 13.921875)"
  assert support.caster_change_ends(effects:) == []
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:) == [#(6000, "end", source)]
    as "the end comes on a timer 5000 ms after the go, once"
  let finishes =
    list.filter(fired, fn(step) {
      support.finished_ids(support.writes(effects: step.1)) == [id]
    })
  assert list.map(finishes, fn(step) { step.0 }) == [6000]
    as "the node lives 5000 ms: the buff shows for the row's time from the go"
}

pub fn a_delayed_absorb_starts_on_a_timer_test() -> Nil {
  use <- owned_test.run(120_000)
  // A planted shape of row 56356 (delay 251, 10000 ms), not the row: the real row's
  // dataBits00 is 0, which the plan refuses (its amount is 0), so this one reads 1.0 x 100.0.
  let delayed =
    absorb_row(
      id: 99_356,
      formula: Formula(multiplier: 1.0, base: 100.0, parameters: []),
      row: LastingRow(delay_ms: 251, duration_ms: 10_000, until_removed: False),
    )
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 30_724, base: 3, modifiers: [delayed]),
    ])
  let #(state, effects) =
    support.press_as(
      caster: novice(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 99_356)
  assert starts(effects:) == []
    as "nothing starts at the go: the row waits its delay"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:)
    == [#(1251, "start", source), #(11_251, "end", source)]
    as "it starts at go + 251 and ends 10000 ms later"
  assert list.flat_map(fired, fn(step) { starts(effects: step.1) })
    == [#(source, 100, 7)]
    as "the pool is the amount worked out at the go: 1.0 x 100.0"
}

pub fn an_absorb_ends_at_once_when_its_node_is_taken_off_or_its_persistence_fails_and_on_the_casters_death_test() -> Nil {
  use <- owned_test.run(120_000)
  // A type 80 removal of the cast.
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 58_586, base: 3, modifiers: [
        spectral_form_row(),
      ]),
      spell_plan.Spell(..support.child(spell4_id: 301, base: 1), removes: [
        spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(196_521),
          phase_flags: -1,
          aim: spell_plan.AimsAtCaster,
          selector: lasting.Spell(Spell4Id(58_586)),
          count: 1,
          condition: Always,
          tag: spend.always,
        ),
      ]),
    ])
  let #(state, first) =
    support.press_as(
      caster: novice(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects: first)
  assert list.length(starts(effects: first)) == 1
    as "the absorb started in the press's go"
  let #(_, removal) =
    support.press_as(
      caster: novice(),
      plans:,
      state:,
      bag: bag_of_base_1,
      at: 2000,
    )
  assert support.caster_change_ends(effects: removal)
    == [support.source_of(cast_id: id, effect_id: 178_144)]
    as "taking the cast's node off the caster ends the absorb at once"
  assert support.timer_numbers(timers: support.cancelled_timers(
      effects: removal,
    ))
    == support.timer_numbers(
      timers: list.map(support.started_timers(effects: first), fn(started) {
        started.0
      }),
    )
    as "exactly the two timers the press started are cancelled: the absorb's end and the node's end"
  // A persistence that stops holding: prerequisite 903, type 28 comparison 1, the caster
  // in combat.
  let in_combat = prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
  let guarded =
    support.plans_of([
      spell_plan.Spell(
        ..support.spell_holding(spell4_id: 58_586, base: 3, modifiers: [
          spectral_form_row(),
        ]),
        caster_persistence: Some(in_combat),
      ),
    ])
  let fighting = cast.Caster(..novice(), in_combat: True)
  let #(lingering, raw) =
    support.pressed_raw_in(
      plans: guarded,
      state: cast.new(),
      caster: fighting,
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(lingering, pressed) =
    support.answered_as(
      caster: fighting,
      state: lingering,
      effects: raw,
      at: 1000,
      struck: [],
      rolls: [],
    )
  let held_id = support.pressed_id(effects: pressed)
  let #(_, ended) =
    cast.persisted(
      cast: lingering,
      caster: cast.Caster(..novice(), in_combat: False),
      now: support.at(ms: 2000),
    )
  assert support.caster_change_ends(effects: ended)
    == [support.source_of(cast_id: held_id, effect_id: 178_144)]
    as "the persistence ends the cast as a death ends one, and the absorb with it"
  assert support.timer_numbers(timers: support.cancelled_timers(effects: ended))
    == support.timer_numbers(
      timers: list.map(support.started_timers(effects: pressed), fn(started) {
        started.0
      }),
    )
    as "and its two timers are cancelled"
  // The caster's death, with a delayed absorb still pending.
  let delayed =
    absorb_row(
      id: 99_356,
      formula: Formula(multiplier: 1.0, base: 100.0, parameters: []),
      row: LastingRow(delay_ms: 251, duration_ms: 10_000, until_removed: False),
    )
  let both =
    support.plans_of([
      support.spell_holding(spell4_id: 58_586, base: 3, modifiers: [
        spectral_form_row(),
      ]),
      support.spell_holding(spell4_id: 30_724, base: 1, modifiers: [delayed]),
    ])
  let #(state, one) =
    support.press_as(
      caster: novice(),
      plans: both,
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(state, two) =
    support.press_as(
      caster: novice(),
      plans: both,
      state:,
      bag: bag_of_base_1,
      at: 1100,
    )
  let #(_, died) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1200),
    )
  assert support.caster_change_ends(effects: died)
    == [
      support.source_of(
        cast_id: support.pressed_id(effects: one),
        effect_id: 178_144,
      ),
      support.source_of(
        cast_id: support.pressed_id(effects: two),
        effect_id: 99_356,
      ),
    ]
    as "the one that started and the one still pending are both told ended, in cast order; the life, holding no pool for the pending one, changes nothing"
}

pub fn the_absorb_amount_reads_the_caster_before_the_gos_own_effects_test() -> Nil {
  use <- owned_test.run(120_000)
  // The same go raises AssaultRating (property 35) by 1000 with a type 11 row, and its
  // absorb starts 251 ms later. The pool is the 164 the caster's stats gave at the go: when
  // the delayed start fires, the rule is handed a caster whose ratings are not the go's
  // (`cast_support` fires timers for a caster with Assault and Support Rating 0, so an
  // amount worked out at the start would be 0), and it still starts the pool of 164.
  let raising =
    spell_plan.PropertyModifier(
      effect_id: Spell4EffectsId(99_001),
      phase_flags: 1,
      change: spell_plan.PropertyChange(Change(
        property: UnitProperty2Id(35),
        mode: 3,
        multiplier: 1.0,
        flat: 1000.0,
        per_level: 0.0,
      )),
      row: LastingRow(delay_ms: 0, duration_ms: 8000, until_removed: False),
      condition: Always,
      tag: spend.always,
      armor: None,
    )
  let delayed =
    absorb_row(
      id: 178_144,
      formula: spectral_form_row_formula(),
      row: LastingRow(delay_ms: 251, duration_ms: 5000, until_removed: False),
    )
  let plans =
    support.plans_of([
      support.spell_holding(spell4_id: 58_586, base: 3, modifiers: [
        raising,
        delayed,
      ]),
    ])
  let #(state, effects) =
    support.press_as(
      caster: novice(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  assert starts(effects:) == []
    as "the absorb waits for its delay; the raised rating starts in the go's step"
  assert list.any(effects, fn(effect) {
    case effect {
      cast.CasterChangeStarts(change: cast.Property(..), ..) -> True
      cast.CasterChangeStarts(change: cast.Absorb(..), ..)
      | cast.CasterChangeStarts(change: cast.ShieldHeal(..), ..)
      | cast.CasterChangeStarts(change: cast.Look(..), ..)
      | cast.CasterChangeEnds(..)
      | cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..)
      | cast.Strike(..)
      | cast.Pay(..)
      | cast.StealthChanged(..)
      | cast.Gain(..) -> False
    }
  })
    as "and the raised rating does start in the same go"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert list.flat_map(fired, fn(step) { starts(effects: step.1) })
    == [#(support.source_of(cast_id: id, effect_id: 178_144), 164, 7)]
    as "the pool is the amount of the go, 164, not one worked out when the start fires"
}
