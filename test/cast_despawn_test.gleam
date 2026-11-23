//// The cast rule's despawns of creatures (`genesis_prime/game/cast`,
//// `genesis_prime/game/cast/control` `despawns_told`). Expected values come from these places:
//// - `Spell4Effects.effectType.97`: a DespawnUnit row removes the unit its targetFlags name
////   after its delayTime; the client reads no row of the type, so what the server tells is
////   its own: the rows are 99864 (Spell4 43559, targetFlags 2, delay 0, the spell's only
////   effect), 119478 (Spell4 50224, targetFlags 2, delay 3000) and 56028 (Spell4 30600,
////   targetFlags 2, delay 4000, phaseFlags 1), `table_rows -- Spell4Effects effectType=97`.
//// - The design of the step: the creature owns the delay, so the cast tells every creature
////   the go hit in the go's own step with the row's delay and arms no timer; the delay runs
////   from the go's time, and the strike time of the round tells which life it hit.
//// - `Spell4Effects.phaseFlags`: bit n is phase n; a row applies in the phases it names.
//// - `Prerequisite.prerequisiteTypeId.37` (comparison 6, value 50, row 4585) and `.38`
////   (Prerequisite 20210's shape: comparison 1 passes the unit that is the creature of its
////   row): the gates a despawn row may sit behind.
//// - `opcode.0x7f4.target_info`: the go's target info lists only the effects the server
////   lists; a despawn is not among them, and the client reads no row of the type.

import cast_support as support
import genesis_prime/game/cast/state.{type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell, Always}
import genesis_prime/game/spend
import genesis_prime/message/spell_go
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/dict
import gleam/list
import owned_test
import prerequisite_support

/// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

/// A despawn row of 99864's shape: phase 0, no delay, aimed at the units the go hit.
fn despawn_row(delay_ms delay_ms: Int) -> spell_plan.Despawn {
  spell_plan.Despawn(
    effect_id: Spell4EffectsId(99_864),
    phase_flags: 1,
    delay_ms:,
    aim: spell_plan.AimsAtArea,
    condition: Always,
    tag: spend.always,
  )
}

fn despawner(rows rows: List(spell_plan.Despawn)) -> Spell {
  support.with_effects(
    spell: support.child(spell4_id: 43_559, base: 3),
    kinds: list.map(rows, spell_plan.DespawnEffect),
  )
}

/// A creature the round hit in `life` at the monotonic time 900, before the go at 1000.
fn hit(unit_id unit_id: Int, life life: Int) -> cast_state.Struck {
  support.creature_hit(unit_id:, life:, struck_at_ms: 900)
}

/// The press of the spell at 1000 aimed at `target`, and the go its round answers at 1000.
fn went(
  spell spell: Spell,
  target target: Int,
  struck struck: List(cast_state.Struck),
) -> #(State, List(cast_state.Effect)) {
  support.pressed_and_answered(
    spell:,
    bag_index: bag_of_base_3,
    target:,
    struck:,
    at: 1000,
  )
}

fn removed(
  unit_id unit_id: Int,
  life life: Int,
  delay_ms delay_ms: Int,
) -> cast_state.Effect {
  cast_state.CreatureDespawns(
    unit_id:,
    life:,
    struck_at_ms: 900,
    went_at_ms: 1000,
    delay_ms:,
  )
}

pub fn a_despawn_of_delay_0_is_told_in_the_go_step_after_the_go_frames_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    went(spell: despawner(rows: [despawn_row(delay_ms: 0)]), target: 0, struck: [
      hit(unit_id: 21, life: 3),
    ])
  assert support.despawns(effects:)
    == [removed(unit_id: 21, life: 3, delay_ms: 0)]
    as "Spell4Effects 99864: the go that hit creature 21 tells it to leave in the go's own step"
  let position_of = fn(wanted) {
    let assert Ok(found) =
      list.key_find(
        list.index_map(effects, fn(effect, i) { #(effect, i) }),
        wanted,
      )
    found
  }
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  assert position_of(cast_state.Send(frame: go))
    < position_of(removed(unit_id: 21, life: 3, delay_ms: 0))
    as "the go's frame is written before the creature is told, so the caster sees the go first"
}

pub fn a_delayed_despawn_is_told_at_the_go_and_arms_no_cast_timer_test() -> Nil {
  use <- owned_test.run(5000)
  // Spell4Effects 119478 (Spell4 50224): delayTime 3000.
  let creatures = [hit(unit_id: 21, life: 3)]
  let #(state, effects) =
    went(
      spell: despawner(rows: [despawn_row(delay_ms: 3000)]),
      target: 0,
      struck: creatures,
    )
  assert support.despawns(effects:)
    == [removed(unit_id: 21, life: 3, delay_ms: 3000)]
    as "the tell carries the row's delay of 3000: the creature owns it"
  assert support.started_timers(effects:) == []
    as "the cast starts no timer for the despawn: no node, no property, no delay of its own"
  let #(_, fired) =
    support.run_timers_striking(
      state:,
      effects:,
      from_ms: 1000,
      struck: creatures,
    )
  assert fired == [] as "and nothing is left for a timer to tell later"
}

pub fn the_tell_carries_the_life_and_the_go_time_the_round_hit_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    went(spell: despawner(rows: [despawn_row(delay_ms: 0)]), target: 0, struck: [
      hit(unit_id: 21, life: 3),
      hit(unit_id: 23, life: 5),
    ])
  assert support.despawns(effects:)
    == [
      cast_state.CreatureDespawns(
        unit_id: 21,
        life: 3,
        struck_at_ms: 900,
        went_at_ms: 1000,
        delay_ms: 0,
      ),
      cast_state.CreatureDespawns(
        unit_id: 23,
        life: 5,
        struck_at_ms: 900,
        went_at_ms: 1000,
        delay_ms: 0,
      ),
    ]
    as "each creature in the life the round hit, struck_at_ms the round's time 900 and went_at_ms the go's time 1000, in the order the round hit them"
}

pub fn a_deflected_creature_is_not_despawned_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    went(spell: despawner(rows: [despawn_row(delay_ms: 0)]), target: 0, struck: [
      cast_state.Deflected(unit_id: 21),
      hit(unit_id: 23, life: 5),
    ])
  assert support.despawns(effects:)
    == [removed(unit_id: 23, life: 5, delay_ms: 0)]
    as "a deflected creature took no effect of the strike, as it is not thrown; only the one the go hit is told"
}

pub fn a_creature_the_round_left_out_is_not_despawned_test() -> Nil {
  use <- owned_test.run(5000)
  // A creature that refused the strike as dead, or gave no answer by the round's deadline,
  // is left out of the round (`strike.filled`), so the go does not name it: only the
  // creature 23 the round hit is in the area.
  let #(_, effects) =
    went(spell: despawner(rows: [despawn_row(delay_ms: 0)]), target: 0, struck: [
      hit(unit_id: 23, life: 5),
    ])
  assert support.despawns(effects:)
    == [removed(unit_id: 23, life: 5, delay_ms: 0)]
    as "the creature 21 the round left out is told nothing"
  let #(_, effects) =
    went(
      spell: despawner(rows: [despawn_row(delay_ms: 0)]),
      target: 0,
      struck: [],
    )
  assert support.despawns(effects:) == []
    as "a round that hit nobody tells nobody"
}

pub fn a_despawn_of_another_phase_or_a_failed_caster_gate_is_not_told_test() -> Nil {
  use <- owned_test.run(5000)
  let creatures = [hit(unit_id: 21, life: 3)]
  let #(_, effects) =
    went(
      spell: despawner(rows: [
        spell_plan.Despawn(..despawn_row(delay_ms: 0), phase_flags: 2),
      ]),
      target: 0,
      struck: creatures,
    )
  assert support.despawns(effects:) == []
    as "phaseFlags 2 names phase 1 only: the go of phase 0 tells nothing"
  // Prerequisite 4585 is a type 37 chance gate (comparison 6, value 50) on the caster; the
  // go draws one roll for it, and a roll of 51 fails.
  let gated =
    spell_plan.Despawn(
      ..despawn_row(delay_ms: 0),
      condition: spell_plan.GatedOnCaster(gates: [
        prerequisite_support.single(id: 4585, condition: #(37, 6, 0, 50)),
      ]),
    )
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_with(spell: despawner(rows: [gated])),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let rolled = fn(roll) {
    let #(_, effects) =
      support.answered_as(
        caster: support.caster(),
        state:,
        effects: raw,
        at: 1000,
        struck: creatures,
        rolls: [roll],
      )
    support.despawns(effects:)
  }
  assert rolled(50) == [removed(unit_id: 21, life: 3, delay_ms: 0)]
    as "a roll of 50 passes comparison 6 on 50 and the creature is told"
  assert rolled(51) == [] as "a roll of 51 fails the caster gate: no tell"
}

pub fn each_go_tells_the_despawns_of_its_own_phase_test() -> Nil {
  use <- owned_test.run(5000)
  // Phase flags 1 and 2 name the first and the second go; the second go comes 300 ms after
  // the first (`Spell.phase_delays_ms`).
  let first = spell_plan.Despawn(..despawn_row(delay_ms: 0), phase_flags: 1)
  let second =
    spell_plan.Despawn(
      ..despawn_row(delay_ms: 500),
      effect_id: Spell4EffectsId(99_865),
      phase_flags: 2,
    )
  let spell =
    spell_plan.Spell(..despawner(rows: [first, second]), phase_delays_ms: [
      0,
      300,
    ])
  let creatures = [hit(unit_id: 21, life: 3)]
  let #(state, effects) = went(spell:, target: 0, struck: creatures)
  assert support.despawns(effects:)
    == [removed(unit_id: 21, life: 3, delay_ms: 0)]
    as "the first go tells the row of phase 0 only"
  let #(_, fired) =
    support.run_timers_striking(
      state:,
      effects:,
      from_ms: 1000,
      struck: creatures,
    )
  let told =
    list.flat_map(fired, fn(step) {
      list.map(support.despawns(effects: step.1), fn(despawn) {
        #(step.0, despawn)
      })
    })
  assert told
    == [
      #(
        1300,
        cast_state.CreatureDespawns(
          unit_id: 21,
          life: 3,
          struck_at_ms: 900,
          went_at_ms: 1300,
          delay_ms: 500,
        ),
      ),
    ]
    as "the second go, at 1000 + 300, tells its own row with its own delay from its own go time 1300"
}

pub fn a_despawn_never_names_the_caster_or_another_player_test() -> Nil {
  use <- owned_test.run(5000)
  // A row aimed at the primary target and the area (Spell4Effects 87795's aim, 6), pressed
  // on the caster's own unit 7, whose round holds another player's unit 9 and a creature
  // 21: only a creature the round hit is told (marked guess: no client row shows a player).
  let wide =
    spell_plan.Despawn(
      ..despawn_row(delay_ms: 0),
      aim: spell_plan.AimsAtPrimaryTargetAndArea,
    )
  let #(_, effects) =
    went(spell: despawner(rows: [wide]), target: 7, struck: [
      cast_state.Hit(
        unit_id: 9,
        unit: cast_state.HitPlayer,
        descriptions: [],
        controls: [],
        armor_removed: 0,
        ticking: [],
      ),
      hit(unit_id: 21, life: 3),
    ])
  assert support.despawns(effects:)
    == [removed(unit_id: 21, life: 3, delay_ms: 0)]
    as "neither the caster 7 (the primary target) nor the player 9 is told to leave"
}

pub fn a_despawn_behind_a_failed_gate_is_not_told_test() -> Nil {
  use <- owned_test.run(5000)
  // Prerequisite.prerequisiteTypeId.38 in Prerequisite 20210's shape: comparison 1 passes
  // the unit that is the creature of Creature2 48404. Unit 23 is that creature and 21 is not.
  let gated =
    spell_plan.Despawn(
      ..despawn_row(delay_ms: 0),
      condition: spell_plan.GatedOnTarget(
        prerequisite: prerequisite_support.single(id: 20_210, condition: #(
          38,
          1,
          0,
          48_404,
        )),
      ),
    )
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_with(spell: despawner(rows: [gated])),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let struck = [hit(unit_id: 21, life: 3), hit(unit_id: 23, life: 5)]
  let #(_, answered) =
    support.answered_known(
      caster: support.caster(),
      state:,
      effects: raw,
      at: 1000,
      struck_of: fn(_) { struck },
      rolls: [],
      poses: dict.new(),
      units: dict.from_list([
        #(21, prerequisite.NonPlayer(1)),
        #(23, prerequisite.NonPlayer(48_404)),
      ]),
    )
  assert support.despawns(effects: answered)
    == [removed(unit_id: 23, life: 5, delay_ms: 0)]
    as "creature 23 passes the gate and is told to leave; creature 21 fails it and stays"
}

pub fn a_despawn_tell_needs_no_cast_timer_so_the_casters_leaving_cannot_cancel_it_test() -> Nil {
  use <- owned_test.run(5000)
  // Every timer of a cast is cleared when the caster leaves (`cast_tick.left`); a despawn
  // told at the go holds none, so the delay of 60000 ms (Spell4Effects 87795's) survives it.
  let #(state, effects) =
    went(
      spell: despawner(rows: [despawn_row(delay_ms: 60_000)]),
      target: 0,
      struck: [hit(unit_id: 21, life: 3)],
    )
  assert support.despawns(effects:)
    == [removed(unit_id: 21, life: 3, delay_ms: 60_000)]
    as "the go told the creature already, with its delay"
  assert support.started_timers(effects:) == []
    as "and armed nothing the caster's leaving could clear"
  let #(_, after_leaving) = cast_tick.left(cast: state)
  assert support.despawns(effects: after_leaving) == []
    as "the caster's leaving tells no second despawn and cancels no first one"
  assert support.cancelled_timers(effects: after_leaving) == []
}
