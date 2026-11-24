//// The effects a go reaches (`genesis_prime/game/cast` `aimed_at`): one list, each row once
//// for each unit it reaches, in the plan's rank order. Expected values come from these
//// places, each named at its assertion:
//// - The plan's rank (`genesis_prime/game/spell_effect` `ranked`, `spell_plan.kind_rank`):
////   lasting, then property modifiers, then cooldown modifiers, then heals, whatever order
////   the rows were given in.
//// - The cast rule's own cases: a heal's amount is its formula's `amount_on_caster`
////   (`cast_heal_test`: a flat formula of base 40 is an amount of 40, and a caster whose
////   vitals have no room is overhealed by the whole amount), and a cooldown row is kept for
////   the cooldowns that start later when it lives past its start (`cast_cooldown_test`:
////   a lasting row is kept, one that acts once is not).
//// The player 7 is the caster; the creature 77 is the primary target.

import cast_support as support
import genesis_prime/game/cast
import genesis_prime/game/cast/control as cast_control
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/cooldown.{AddMs, Base, Modifier}
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/effect_kind
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell, Spell}
import genesis_prime/game/spend
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import gleam/dict
import gleam/list
import gleam/option.{None}
import owned_test
import prerequisite_support

const caster_id = 7

const creature_id = 77

/// A lasting effect (row 1), a plain property modifier (row 2), a cooldown row (row 3) that
/// lives 5000 ms and a flat heal of 40 (row 4), in every phase, the lasting effect and the
/// heal aimed at the caster and the primary target; given in the scrambled order heal,
/// cooldown, modifier, lasting.
fn four_kinds() -> Spell {
  support.with_effects(
    spell: Spell(..support.exempt(), cast_time_ms: 0),
    kinds: [
      spell_plan.HealEffect(spell_plan.Heal(
        effect_id: Spell4EffectsId(4),
        vital: effect_kind.Health,
        phase_flags: -1,
        aim: spell_plan.AimsAtCasterAndPrimaryTarget,
        condition: spell_plan.Always,
        tag: spend.always,
        formula: Formula(multiplier: 1.0, base: 40.0, parameters: [
          Parameter(kind: 0, value: 0.0),
          Parameter(kind: 0, value: 0.0),
          Parameter(kind: 0, value: 0.0),
          Parameter(kind: 0, value: 0.0),
        ]),
        delay_ms: 0,
      )),
      spell_plan.CooldownEffect(spell_plan.CooldownModifier(
        effect_id: Spell4EffectsId(3),
        phase_flags: -1,
        modifier: Modifier(
          selector: Base(Spell4BaseId(3)),
          operation: AddMs(-1000.0),
        ),
        row: lasting.LastingRow(
          delay_ms: 0,
          duration_ms: 5000,
          until_removed: False,
        ),
        condition: spell_plan.Always,
        tag: spend.always,
      )),
      spell_plan.ModifierEffect(
        spell_plan.PropertyModifier(
          ..support.falling_row(),
          effect_id: Spell4EffectsId(2),
          phase_flags: -1,
        ),
      ),
      spell_plan.LastingEffect(spell_plan.Lasting(
        effect_id: Spell4EffectsId(1),
        phase_flags: -1,
        aim: spell_plan.AimsAtCasterAndPrimaryTarget,
        row: lasting.LastingRow(
          delay_ms: 0,
          duration_ms: 0,
          until_removed: True,
        ),
        condition: spell_plan.Always,
        tag: spend.always,
      )),
    ],
  )
}

/// What the reach stage makes of the first go of this spell, aimed at the creature 77,
/// with no strike and no rolls.
fn reached_by_the_first_go_of(spell spell: Spell) -> List(cast_state.Reached) {
  let plans = support.with_spells(plans: support.plans(), spells: [spell])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: 8,
      target: 0,
      at: 1000,
    )
  let assert [asked] = support.goes_asked(effects: raw)
    as "the press of a spell with no cast time asks for its go at once"
  let assert Ok(live) = dict.get(state.casts, asked.cast_id)
    as "the cast is live while its go is asked"
  let live = cast_state.Live(..live, primary_target: creature_id)
  let #(applied, _, _) =
    cast_control.lasting_applied(
      spell:,
      phase: 0,
      spent: None,
      subject: prerequisite_support.holding(held: [], second_unit: None),
      told: fn(_) { False },
      rolls: [],
    )
  cast.aimed_at(
    applied:,
    caster: support.caster(),
    live:,
    struck: [],
    gates_passed: dict.new(),
    phase: 0,
    restricting: [],
    target_verdict: fn(_, _, rolls) { #(prerequisite.Passes, rolls) },
    rolls: [],
    now_ms: 1000,
  ).reached
}

pub fn aimed_reached_holds_each_row_once_per_unit_in_rank_order_test() -> Nil {
  use <- owned_test.run(5000)
  let reached = reached_by_the_first_go_of(spell: four_kinds())
  assert list.map(reached, fn(entry) {
      #(entry.effect.effect_id.value, entry.unit_id)
    })
    == [
      #(1, caster_id),
      #(1, creature_id),
      #(2, caster_id),
      #(3, caster_id),
      #(4, caster_id),
      #(4, creature_id),
    ]
    as "the rows given heal, cooldown, modifier, lasting are reached in the plan's rank order, lasting (1), modifier (2), cooldown (3), heal (4), each once for each unit its aim names; the modifier is the caster's alone"
  let assert [
    lasting_on_caster,
    lasting_on_creature,
    modifier,
    cooldown,
    ..heals
  ] = reached
  assert [
      lasting_on_caster.product,
      lasting_on_creature.product,
      modifier.product,
    ]
    == [cast_state.Plain, cast_state.Plain, cast_state.Plain]
    as "a lasting effect and a modifier carry nothing beside their unit"
  assert cooldown.product == cast_state.CooldownKept(True)
    as "a cooldown row of a life of 5000 ms past its start is kept for the cooldowns that start later (`cast_cooldown_test`)"
  let assert [heal_on_caster, heal_on_creature] = heals
  let assert cast_state.Healing(healed) = heal_on_caster.product
    as "the heal on the caster carries the heal worked out at the go"
  assert #(healed.effect_id, healed.vital, healed.delay_ms, healed.amount)
    == #(Spell4EffectsId(4), effect_kind.Health, 0, 40)
    as "a flat formula of base 40 is an amount of 40 (`cast_heal_test`)"
  assert #(healed.split.amount, healed.split.overheal) == #(40, 40)
    as "a caster whose vitals have no room is overhealed by the whole amount (`cast_heal_test`)"
  assert heal_on_creature.product == cast_state.Plain
    as "a heal on another unit lands nothing (heals on other units are not built), so it carries no heal"
}
