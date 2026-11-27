//// The strike round of a cast whose row waits for a struck creature's gate, built for the tests
//// that run the round against a creature (`cast_struck_gate_test`, `world_relay_test`): the
//// spell with a gate on its row, the cast pressed on it, the selection of its go and the
//// strike the go begins, at the time of the go.

import cast_support as support
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/strike.{Aimed, Selection}
import genesis_prime/shared/spell_plan.{type Spell, AimsAtArea, AimsAtCaster}
import genesis_prime/shared/spend
import genesis_prime/step.{Now}
import genesis_prime/table/id.{Spell4EffectsId}
import gleam/dict
import gleam/list
import prerequisite_support
import rating_support
import strike_support

// The planted base 3 is the bag index 11 (`cast_support.abilities`).
pub const bag_of_base_3 = 11

/// The gated row's effect id, the ungated area row's and the caster's own.
pub const gated_id = 7

pub const ungated_id = 8

pub const own_id = 9

pub fn at(ms ms: Int) -> step.Now {
  Now(monotonic_ms: ms, filetime: 0)
}

/// The struck gate of the row `id`: the target apply prerequisite 5001 (a type 28
/// condition, comparison 1) which the cast rule never reads, as the creature checks it.
pub fn gate_of(id id: Int, aim aim: spell_plan.Aim) -> spell_plan.StruckGate {
  spell_plan.StruckGate(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    aim:,
    prerequisite: prerequisite_support.single(id: 5001, condition: #(
      28,
      1,
      0,
      0,
    )),
    tag: spend.always,
  )
}

/// A spell whose go has a gated row aimed at `gated_aim`, an ungated one aimed at the area
/// and one aimed at the caster.
pub fn spell_gated_at(gated_aim gated_aim: spell_plan.Aim) -> Spell {
  support.with_effects(
    spell: spell_plan.Spell(
      ..support.child(spell4_id: 101, base: 3),
      struck_gates: [gate_of(id: gated_id, aim: gated_aim)],
    ),
    kinds: [
      spell_plan.LastingEffect(support.marker_row(id: gated_id, aim: gated_aim)),
      spell_plan.LastingEffect(support.marker_row(
        id: ungated_id,
        aim: AimsAtArea,
      )),
      spell_plan.LastingEffect(support.marker_row(id: own_id, aim: AimsAtCaster)),
    ],
  )
}

/// The same spell with no gate at all.
pub fn spell_ungated() -> Spell {
  spell_plan.Spell(..spell_gated_at(gated_aim: AimsAtArea), struck_gates: [])
}

/// The cast pressed on the spell at `target`: its state and the go it asks for.
pub fn pressed(
  spell spell: Spell,
  target target: Int,
) -> #(cast_state.State, cast_state.GoAsked) {
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_of([spell]),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target:,
      at: 1000,
    )
  let assert [asked] = support.goes_asked(effects: raw)
    as "the press asks for one go"
  #(state, asked)
}

pub fn selection_of(
  spell spell: Spell,
  asked asked: cast_state.GoAsked,
  units units: List(Int),
) -> strike.Selection {
  Selection(
    asked:,
    units: list.map(units, fn(unit_id) { Aimed(unit_id:, life: 3) }),
    area: units,
    blows: [],
    ticking: [],
    controls: [],
    gates: spell.struck_gates,
    players: [],
    acts_on_each_unit: False,
    heals: [],
  )
}

/// The strike the go begins on the units, at the time of the go.
pub fn begun(
  selection selection: strike.Selection,
) -> #(strike.State, List(strike.Effect)) {
  strike.begin(
    strike: strike.new(),
    selection:,
    attacker: strike_support.attacker(),
    formulas: rating_support.formulas(),
    entropy: <<0:size({ strike.entropy_needed(selection:) * 8 })>>,
    gate: cast_tick.strike_gate(
      cast: cast_state.new(),
      caster: support.caster(),
      poses: dict.new(),
      indexes: dict.new(),
      units: dict.new(),
    ),
    now: at(ms: 1000),
  )
}
