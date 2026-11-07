//// The cast rule's disguise rows (`genesis_prime/game/cast` `CasterChangeStarts` with a
//// `Look` change, `CasterChangeEnds`): a DisguiseOutfit row is timed as a property
//// modifier is (`cast_modifier_test`). Expected values come from these places:
//// - `Spell4Effects.effectType.112`: the Eradication ExoSuit's rows 112543 (ItemDisplay
////   4807, behind prerequisite 30100) and 178142 (7221, behind 30101) each last 10,250
////   ms on the caster, from the go of Spell4 47860.
//// - `-- Prerequisite 30100 30101`: flags 1 (any condition passes), a type 243 and a
////   type 250 condition, comparison 1, value 167 (30100) or 166 (30101). Type 250 reads
////   the base faction (`Prerequisite.prerequisiteTypeId.250`) and type 243 is not
////   passed by anyone (`Prerequisite.prerequisiteTypeId.243`), so the gate holds for
////   the faction of its value.
//// - `opcode.0x7f4.effect_time`: an effect with a lifetime gives its spell a node on its
////   unit, which the go lists.
//// - The type 11 precedent (`cast_modifier_test`, `cast_interrupt_armor_test`): a row
////   starts at the go plus its delay and ends after its duration by a timer of its own;
////   a node taken off the caster, a node ending by time, a persistence that stops
////   holding and the caster's death end it and cancel its timers; leaving ends none.

import cast_support as support
import genesis_prime/game/cast.{type Effect}
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/look.{type Disguise, Disguise}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell, Always}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{type Source}
import genesis_prime/game/worn_visual.{WornVisual}
import genesis_prime/message/spell_go
import genesis_prime/table/id.{
  ItemDisplayId, ItemSlotId, Spell4EffectsId, Spell4Id,
}
import gleam/list
import gleam/option.{Some}
import owned_test
import prerequisite_support as prerequisites

// The planted base 3 is bag index 11 and base 1 is bag index 8 (`cast_support.abilities`).
const bag_of_base_3 = 11

const bag_of_base_1 = 8

/// A gate as 30100 and 30101 are held: flags 1, a type 243 and a type 250 condition,
/// comparison 1, of this faction.
fn faction_gate(id id: Int, faction faction: Int) -> prerequisite.Prerequisite {
  prerequisites.loaded(id:, rows: [
    prerequisites.row(id:, flags: 1, conditions: [
      #(243, 1, 0, faction),
      #(250, 1, 0, faction),
    ]),
  ])
}

fn disguise_of(display display: Int) -> Disguise {
  Disguise(shown: [
    WornVisual(slot: ItemSlotId(64), display: ItemDisplayId(display)),
  ])
}

/// A DisguiseOutfit row of the ExoSuit's kind: slot 64, this display, 10,250 ms from this
/// delay, behind this condition.
fn suit_row(
  id id: Int,
  display display: Int,
  delay delay: Int,
  condition condition: spell_plan.Condition,
) -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    change: spell_plan.LookChange(disguise: disguise_of(display:)),
    row: LastingRow(delay_ms: delay, duration_ms: 10_250, until_removed: False),
    condition:,
    tag: spend.always,
    armor: option.None,
  )
}

/// 112543 and 178142 as the client holds them, each behind its faction's gate.
fn exile_row() -> spell_plan.PropertyModifier {
  suit_row(
    id: 112_543,
    display: 4807,
    delay: 0,
    condition: spell_plan.GatedOnCaster(gates: [
      faction_gate(id: 30_100, faction: 167),
    ]),
  )
}

fn dominion_row() -> spell_plan.PropertyModifier {
  suit_row(
    id: 178_142,
    display: 7221,
    delay: 0,
    condition: spell_plan.GatedOnCaster(gates: [
      faction_gate(id: 30_101, faction: 166),
    ]),
  )
}

fn holder(modifiers modifiers: List(spell_plan.PropertyModifier)) -> Spell {
  spell_plan.Spell(..support.child(spell4_id: 47_860, base: 3), modifiers:)
}

fn dominion() -> cast.Caster {
  cast.Caster(
    ..support.caster(),
    factions: prerequisite.Factions(current: 166, base: 166),
  )
}

/// The disguises the effects start, with their sources.
fn starts(effects effects: List(Effect)) -> List(#(Source, Disguise)) {
  list.filter_map(support.caster_change_starts(effects:), fn(start) {
    case start.1 {
      cast.Look(disguise:) -> Ok(#(start.0, disguise))
      cast.Property(..) | cast.ShieldHeal(..) | cast.Absorb(..) -> Error(Nil)
    }
  })
}

/// The spell4_effects_id of each effect the go lists on the caster.
fn listed(effects effects: List(Effect)) -> List(Int) {
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [info] = decoded.targets
  list.map(info.effects, fn(effect) { effect.spell4_effects_id })
}

// ---- the gates ----

pub fn an_exile_gets_the_exile_suit_and_a_dominion_player_the_dominion_one_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([holder(modifiers: [exile_row(), dominion_row()])])
  let #(_, exile) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects: exile)
  assert listed(effects: exile) == [112_543]
    as "the Exile's go lists 112543 and not 178142, whose gate wants faction 166"
  assert starts(effects: exile)
    == [
      #(
        support.source_of(cast_id: id, effect_id: 112_543),
        disguise_of(display: 4807),
      ),
    ]
    as "its look change starts in the go's own step, with ItemDisplay 4807"
  let #(_, other) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: dominion(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let other_id = support.pressed_id(effects: other)
  assert listed(effects: other) == [178_142]
  assert starts(effects: other)
    == [
      #(
        support.source_of(cast_id: other_id, effect_id: 178_142),
        disguise_of(display: 7221),
      ),
    ]
}

// ---- the time ----

pub fn a_disguise_ends_after_10250_ms_on_its_own_timer_and_a_delayed_one_starts_after_its_delay_test() -> Nil {
  use <- owned_test.run(5000)
  let plans = support.plans_of([holder(modifiers: [exile_row()])])
  let #(state, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 112_543)
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:) == [#(11_250, "end", source)]
    as "the suit ends 10,250 ms after the go (Spell4Effects 112543 durationTime)"
  // The same row with a delay: it starts after it and ends a duration later.
  let delayed =
    support.plans_of([
      holder(modifiers: [
        suit_row(
          id: 112_543,
          display: 4807,
          delay: 500,
          condition: spell_plan.GatedOnCaster(gates: [
            faction_gate(id: 30_100, faction: 167),
          ]),
        ),
      ]),
    ])
  let #(state, effects) =
    support.press_as(
      plans: delayed,
      state: cast.new(),
      caster: support.caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert starts(effects:) == [] as "nothing starts at the go: the row waits"
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 112_543)
  assert support.timeline(fired:)
    == [#(1500, "start", source), #(11_750, "end", source)]
    as "it starts at go + 500 and ends 10,250 ms later"
}

// ---- the end ----

pub fn a_removal_a_node_ending_a_persistence_and_a_death_each_end_the_disguise_and_cancel_its_timers_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      holder(modifiers: [exile_row()]),
      spell_plan.Spell(..support.child(spell4_id: 301, base: 1), removes: [
        spell_plan.ForceRemove(
          effect_id: Spell4EffectsId(196_521),
          phase_flags: -1,
          aim: spell_plan.AimsAtCaster,
          selector: lasting.Spell(Spell4Id(47_860)),
          count: 1,
          condition: Always,
          tag: spend.always,
        ),
      ]),
    ])
  let #(state, first) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects: first)
  let source = support.source_of(cast_id: id, effect_id: 112_543)
  let timers_started =
    list.map(support.started_timers(effects: first), fn(started) { started.0 })
  // A type 80 removal of the cast.
  let #(_, removal) =
    support.press_as(
      plans:,
      state:,
      caster: support.caster(),
      bag: bag_of_base_1,
      at: 2000,
    )
  assert support.caster_change_ends(effects: removal) == [source]
    as "taking the cast's node off the caster ends the disguise at once"
  assert support.timer_numbers(timers: support.cancelled_timers(
      effects: removal,
    ))
    == support.timer_numbers(timers: timers_started)
    as "and cancels the two timers the go started: the disguise's end and the node's end"
  // The caster's death.
  let #(_, died) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 2000),
    )
  assert support.caster_change_ends(effects: died) == [source]
    as "death ends the disguise"
  assert support.timer_numbers(timers: support.cancelled_timers(effects: died))
    == support.timer_numbers(timers: timers_started)
    as "and cancels the two timers the go started"
  // A persistence that stops holding: prerequisite 903, the caster in combat.
  let in_combat = prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
  let guarded =
    support.plans_of([
      spell_plan.Spell(
        ..holder(modifiers: [exile_row()]),
        caster_persistence: Some(in_combat),
      ),
    ])
  let fighting = cast.Caster(..support.caster(), in_combat: True)
  let #(lingering, pressed) =
    support.press_as(
      plans: guarded,
      state: cast.new(),
      caster: fighting,
      bag: bag_of_base_3,
      at: 1000,
    )
  let held_id = support.pressed_id(effects: pressed)
  let #(_, ended) =
    cast.persisted(
      cast: lingering,
      caster: cast.Caster(..support.caster(), in_combat: False),
      now: support.at(ms: 2000),
    )
  assert support.caster_change_ends(effects: ended)
    == [support.source_of(cast_id: held_id, effect_id: 112_543)]
    as "the persistence ends the cast, and the disguise with it"
  assert support.timer_numbers(timers: support.cancelled_timers(effects: ended))
    == support.timer_numbers(
      timers: list.map(support.started_timers(effects: pressed), fn(started) {
        started.0
      }),
    )
    as "and cancels the two timers its go started"
}

pub fn a_node_that_ends_by_time_ends_the_disguise_and_the_player_leaving_ends_none_test() -> Nil {
  use <- owned_test.run(5000)
  // A spell whose propertyFlags have bit 0x2000 takes the larger of delay and duration
  // for the node's life: with a delay of 500 the node ends at go + 10,250 and the row's
  // own end is go + 10,750, so the node's end ends the disguise first.
  let plans =
    support.plans_of([
      spell_plan.Spell(
        ..holder(modifiers: [
          suit_row(
            id: 112_543,
            display: 4807,
            delay: 500,
            condition: spell_plan.GatedOnCaster(gates: [
              faction_gate(id: 30_100, faction: 167),
            ]),
          ),
        ]),
        longer_of_delay_and_duration: True,
      ),
    ])
  let #(state, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let id = support.pressed_id(effects:)
  let source = support.source_of(cast_id: id, effect_id: 112_543)
  let #(_, fired) = support.run_timers(state:, effects:, from_ms: 1000)
  assert support.timeline(fired:)
    == [#(1500, "start", source), #(11_250, "end", source)]
    as "the disguise ends with its node at go + 10,250; its own end at go + 10,750 never fires"
  let #(_, left) = cast.left(cast: state)
  assert support.caster_change_ends(effects: left) == []
    as "the connection's look goes with the player's Entered"
}

// ---- the aim and the gate on the target ----

pub fn a_disguise_behind_a_target_prerequisite_is_not_applied_test() -> Nil {
  use <- owned_test.run(5000)
  let gated =
    suit_row(
      id: 112_543,
      display: 4807,
      delay: 0,
      condition: spell_plan.GatedOnTarget(prerequisite_id: id.PrerequisiteId(5)),
    )
  let plans = support.plans_of([holder(modifiers: [gated])])
  let #(_, effects) =
    support.press_as(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag: bag_of_base_3,
      at: 1000,
    )
  assert list.length(support.frames_of(
      message_id: spell_go.message_id,
      effects:,
    ))
    == 1
    as "the press went: its go was written"
  assert starts(effects:) == []
    as "a row behind a target apply prerequisite is not applied"
}
