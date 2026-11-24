//// The gates a go checks against the caster (`genesis_prime/game/cast`): a Proxy
//// behind a caster apply prerequisite or one named by its dataBits06 starts its
//// child only when the gate passes (a Proxy's target gate is `cast_position_test`'s), a
//// gain behind a prerequisite of a vital reads the caster's vitals, and
//// a type 37 condition takes a roll only when one is checked. Expected values come
//// from these places, each named at its assertion:
//// - The client's rows: Prerequisite 903 (`Prerequisite.prerequisiteTypeId.28`,
////   comparison 1: in combat), 4585 (type 37, comparison 6, value 50), 11153
////   (type 73, comparison 4, vital 6, value 100), 4918 (type 71, comparison 1,
////   vital 6, value 100), and 33154 (type 59, which the server does not read),
////   copied as `table_rows -- Prerequisite <id>` prints them.
//// - The client's code: `0x1403b3320` (Vitals 5 to 11 are the caster's resource
////   slots 0 to 6) and `0x14049eeb0` (type 179 reads the unit's difficulty, which a
////   player does not hold here).
//// - The design of the step: a gate decides on the state before the go's own
////   effects (the casts as they stood before its children start and before its
////   finish), a Proxy's caster-side gates are checked at its
////   phase's go with the caster as subject, and a prerequisite of a type or a vital not read
////   leaves one debug line (`Spell4Effects.effectType.26.dataBits06`).
//// The bag index 8 is the exempt spell, which these tests replace with a spell of no
//// cast time and one Proxy.

import cast_support as support
import genesis_prime/game/activate
import genesis_prime/game/cast
import genesis_prime/game/cast/control as cast_control
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/class_resource.{Gain}
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/heal_split
import genesis_prime/game/lasting
import genesis_prime/game/player_address.{type PlayerAddress, PlayerAddress}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Proxy, type Spell, Proxy, Spell}
import genesis_prime/game/spend
import genesis_prime/game/strike_tell
import genesis_prime/game/ticking
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import map_support
import owned_test
import player_state_support
import prerequisite_support
import spell_tables

const child_spell4_id = 99

/// A Proxy to the child spell 99, aimed at the caster, in phase 0, behind this
/// condition.
fn proxy(condition: spell_plan.Condition) -> Proxy {
  Proxy(
    period: None,
    effect_id: Spell4EffectsId(1),
    delay_ms: 0,
    phase_flags: 1,
    condition:,
    tag: spend.always,
    target: spell_plan.OnCaster,
    spell: support.child(spell4_id: child_spell4_id, base: child_spell4_id),
    gains: [],
  )
}

/// The exempt spell with no cast time, so it goes at the press, holding these
/// Proxies and gains.
fn spell_with(
  proxies proxies: List(Proxy),
  gains gains: List(spell_plan.Gain),
) -> Spell {
  support.with_effects(
    spell: support.with_effects(
      spell: Spell(..support.exempt(), cast_time_ms: 0),
      kinds: list.map(proxies, spell_plan.ProxyEffect),
    ),
    kinds: list.map(gains, spell_plan.GainEffect),
  )
}

/// Every effect of a press of the bag index 8, answered with a round that struck
/// nobody, the go taking these rolls.
fn pressed(
  spell spell: Spell,
  caster caster: cast_state.Caster,
  rolls rolls: List(Int),
) -> List(cast_state.Effect) {
  let plans = support.with_spells(plans: support.plans(), spells: [spell])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster:,
      bag_index: 8,
      target: 0,
      at: 1000,
    )
  let #(_, effects) =
    support.answered_as(
      caster:,
      state:,
      effects: raw,
      at: 1000,
      struck: [],
      rolls:,
    )
  effects
}

fn children_started(effects: List(cast_state.Effect)) -> Int {
  support.started_count(effects:, spell4_id: child_spell4_id)
}

fn in_combat() -> cast_state.Caster {
  cast_state.Caster(..support.caster(), in_combat: True)
}

fn gated_on(gates: List(prerequisite.Prerequisite)) -> Proxy {
  proxy(spell_plan.GatedOnCaster(gates:))
}

pub fn a_caster_gate_that_passes_starts_the_child_at_the_go_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    spell_with(
      proxies: [
        gated_on([
          prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0)),
        ]),
      ],
      gains: [],
    )
  let effects = pressed(spell:, caster: in_combat(), rolls: [])
  assert children_started(effects) == 1
    as "Prerequisite 903 is type 28, comparison 1: the caster is in combat, so the gate passes and the Proxy starts its child"
  assert support.debug_lines(effects) == []
    as "a gate that passes leaves no line"
}

pub fn a_caster_gate_that_fails_does_not_start_the_child_and_says_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    spell_with(
      proxies: [
        gated_on([
          prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0)),
        ]),
      ],
      gains: [],
    )
  let effects = pressed(spell:, caster: support.caster(), rolls: [])
  assert children_started(effects) == 0
    as "Prerequisite 903 is comparison 1 of type 28 and the caster is out of combat: the gate fails"
  assert support.debug_lines(effects) == []
    as "a gate that fails is the client's answer, not a gap"
}

pub fn both_gates_of_a_proxy_must_pass_test() -> Nil {
  use <- owned_test.run(5000)
  let in_combat_gate =
    prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0))
  let out_of_combat_gate =
    prerequisite_support.single(id: 1, condition: #(28, 2, 0, 0))
  let both =
    spell_with(proxies: [gated_on([in_combat_gate, in_combat_gate])], gains: [])
  let contradictory =
    spell_with(
      proxies: [gated_on([in_combat_gate, out_of_combat_gate])],
      gains: [],
    )
  assert children_started(pressed(spell: both, caster: in_combat(), rolls: []))
    == 1
    as "the caster apply gate and the dataBits06 gate both pass"
  assert children_started(
      pressed(spell: contradictory, caster: in_combat(), rolls: []),
    )
    == 0
    as "28 comparison 2 fails in combat, so the Proxy does not start whatever the other gate gives"
}

pub fn a_gate_of_a_type_the_server_does_not_read_starts_nothing_and_leaves_one_debug_line_test() -> Nil {
  use <- owned_test.run(5000)
  let unread = prerequisite_support.unread_type()
  let spell =
    spell_with(
      proxies: [
        gated_on([
          prerequisite_support.single(id: 4301, condition: #(unread, 1, 0, 1)),
        ]),
      ],
      gains: [],
    )
  let effects = pressed(spell:, caster: in_combat(), rolls: [])
  assert children_started(effects) == 0
    as "Prerequisite 4301 holds a type the server does not read: the client would decide it, the server cannot, so the Proxy does not start"
  let lines = support.debug_lines(effects)
  assert list.length(lines) == 1
  assert list.all(lines, fn(line) {
    string.contains(line, "Spell4 99")
    && string.contains(line, "prerequisite 4301")
    && string.contains(line, "of type " <> int.to_string(unread))
  })
    as "one line names the child, the prerequisite and its type"
}

pub fn a_proxy_with_no_gate_starts_as_before_test() -> Nil {
  use <- owned_test.run(5000)
  let effects =
    pressed(
      spell: spell_with(proxies: [proxy(spell_plan.Always)], gains: []),
      caster: support.caster(),
      rolls: [],
    )
  assert children_started(effects) == 1
}

// ---- type 37: the roll ----

fn chance_gate() -> prerequisite.Prerequisite {
  prerequisite_support.single(id: 4585, condition: #(37, 6, 0, 50))
}

pub fn a_type_37_gate_starts_the_child_when_its_roll_is_at_most_the_value_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = spell_with(proxies: [gated_on([chance_gate()])], gains: [])
  assert children_started(
      pressed(spell:, caster: support.caster(), rolls: [50]),
    )
    == 1
    as "Prerequisite 4585: comparison 6 on 50, so a roll of 50 passes"
  assert children_started(
      pressed(spell:, caster: support.caster(), rolls: [51]),
    )
    == 0
    as "a roll of 51 fails"
}

pub fn a_type_37_target_gate_of_a_proxy_on_the_caster_takes_one_roll_test() -> Nil {
  use <- owned_test.run(5000)
  // The Proxy's target gate is checked on the caster, its first unit, with a roll off the
  // front of the go's rolls (Prerequisite 4585, comparison 6 on 50).
  let spell =
    spell_with(
      proxies: [
        proxy(spell_plan.GatedOnCasterAndTarget(
          caster: [],
          target: chance_gate(),
        )),
      ],
      gains: [],
    )
  let #(state, asked) = live_go_of(spell:)
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 1
    as "the one type 37 condition of the target gate, checked on the caster"
  assert children_started(
      pressed(spell:, caster: support.caster(), rolls: [50]),
    )
    == 1
    as "a roll of 50 passes comparison 6 on 50"
  assert children_started(
      pressed(spell:, caster: support.caster(), rolls: [51]),
    )
    == 0
    as "a roll of 51 fails"
}

fn live_go_of(spell spell: Spell) -> #(cast_state.State, cast_state.GoAsked) {
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
  let assert [asked] =
    list.filter_map(raw, fn(effect) {
      case effect {
        cast_state.Strike(asked:) -> Ok(asked)
        _ -> Error(Nil)
      }
    })
    as "the press of a spell with no cast time asks for its go at once"
  #(state, asked)
}

pub fn a_go_takes_a_roll_for_each_type_37_condition_it_may_check_and_none_otherwise_test() -> Nil {
  use <- owned_test.run(5000)
  let needing = spell_with(proxies: [gated_on([chance_gate()])], gains: [])
  let #(state, asked) = live_go_of(spell: needing)
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 1
    as "one type 37 condition in the gate of the one Proxy of the phase"
  let none =
    spell_with(
      proxies: [
        gated_on([
          prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0)),
        ]),
      ],
      gains: [],
    )
  let #(state, asked) = live_go_of(spell: none)
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 0
    as "no type 37 condition: no roll is drawn, so no other roll of the connection moves"
  let #(state, asked) =
    live_go_of(
      spell: spell_with(proxies: [proxy(spell_plan.Always)], gains: []),
    )
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 0
    as "a Proxy with no gate takes none"
  let not_there =
    cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id + 1000,
      phase: 0,
      struck: [],
    )
  assert not_there == 0 as "a cast that is not live takes none"
}

// ---- the caster's vitals ----

fn gain_behind(
  prerequisite prerequisite: prerequisite.Prerequisite,
) -> spell_plan.Gain {
  spell_plan.Gain(
    effect_id: Spell4EffectsId(2),
    gift: spell_plan.SlotPoints(slot: 1, points: 5),
    phase_flags: 1,
    condition: spell_plan.GatedOnCaster(gates: [prerequisite]),
    tag: spend.always,
  )
}

fn gain_under(condition condition: spell_plan.Condition) -> spell_plan.Gain {
  spell_plan.Gain(
    effect_id: Spell4EffectsId(2),
    gift: spell_plan.SlotPoints(slot: 1, points: 5),
    phase_flags: 1,
    condition:,
    tag: spend.always,
  )
}

pub fn a_gain_behind_a_target_gate_reads_the_caster_as_the_unit_it_reaches_test() -> Nil {
  use <- owned_test.run(5000)
  // Prerequisite 903 is type 28, comparison 1: in combat. A gain aims at the caster alone,
  // so the unit its target apply prerequisite is checked on is the caster's own.
  let spell =
    spell_with(proxies: [], gains: [
      gain_under(
        condition: spell_plan.GatedOnTarget(
          prerequisite: prerequisite_support.single(id: 903, condition: #(
            28,
            1,
            0,
            0,
          )),
        ),
      ),
    ])
  assert support.gains(effects: pressed(spell:, caster: in_combat(), rolls: []))
    == [[Gain(slot: 1, amount: 5)]]
    as "the caster is in combat: the target gate passes on the caster, so the gain is given"
  assert support.gains(
      effects: pressed(spell:, caster: support.caster(), rolls: []),
    )
    == []
    as "the caster is not in combat: the target gate fails on the caster, so the gain is not given"
}

pub fn a_gain_needs_both_its_gates_and_takes_a_roll_for_a_type_37_target_gate_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    spell_with(proxies: [], gains: [
      gain_under(condition: spell_plan.GatedOnCasterAndTarget(
        caster: [
          prerequisite_support.single(id: 903, condition: #(28, 1, 0, 0)),
        ],
        target: chance_gate(),
      )),
    ])
  let #(state, asked) = live_go_of(spell:)
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 1
    as "the one type 37 condition of the target gate, 4585 (comparison 6 on 50)"
  assert support.gains(
      effects: pressed(spell:, caster: in_combat(), rolls: [50]),
    )
    == [[Gain(slot: 1, amount: 5)]]
    as "both gates pass: in combat, and a roll of 50 is at most 50"
  assert support.gains(
      effects: pressed(spell:, caster: in_combat(), rolls: [51]),
    )
    == []
    as "a roll of 51 fails the target gate"
  assert support.gains(
      effects: pressed(spell:, caster: support.caster(), rolls: [50]),
    )
    == []
    as "the caster gate fails out of combat though the roll passes"
}

pub fn a_gain_behind_a_type_73_prerequisite_reads_the_class_resource_slot_of_the_vital_test() -> Nil {
  use <- owned_test.run(5000)
  let at_least_100 =
    spell_with(proxies: [], gains: [
      gain_behind(
        prerequisite: prerequisite_support.single(id: 11_153, condition: #(
          73,
          4,
          6,
          100,
        )),
      ),
    ])
  assert support.gains(
      effects: pressed(spell: at_least_100, caster: support.caster(), rolls: []),
    )
    == [[Gain(slot: 1, amount: 5)]]
    as "Prerequisite 11153: vital 6 (Resource1, slot 1) at least 100; the planted resource holds 1000 in slot 1"
  let at_least_1001 =
    spell_with(proxies: [], gains: [
      gain_behind(
        prerequisite: prerequisite_support.single(id: 1, condition: #(
          73,
          4,
          6,
          1001,
        )),
      ),
    ])
  assert support.gains(
      effects: pressed(
        spell: at_least_1001,
        caster: support.caster(),
        rolls: [],
      ),
    )
    == []
    as "1000 is not at least 1001"
}

pub fn a_gain_behind_a_type_71_prerequisite_reads_the_casters_health_test() -> Nil {
  use <- owned_test.run(5000)
  let on_full_health =
    spell_with(proxies: [], gains: [
      gain_behind(
        prerequisite: prerequisite_support.single(id: 4918, condition: #(
          71,
          1,
          1,
          100,
        )),
      ),
    ])
  let hurt =
    cast_state.Caster(
      ..support.caster(),
      life_vitals: dict.from_list([
        #(1, prerequisite.Vital(current: 50.0, maximum: 100.0)),
      ]),
    )
  let full =
    cast_state.Caster(
      ..support.caster(),
      life_vitals: dict.from_list([
        #(1, prerequisite.Vital(current: 100.0, maximum: 100.0)),
      ]),
    )
  assert support.gains(
      effects: pressed(spell: on_full_health, caster: full, rolls: []),
    )
    == [[Gain(slot: 1, amount: 5)]]
    as "Prerequisite.prerequisiteTypeId.71, Vital 1 (Health): 100 of 100 is exactly 100 percent"
  assert support.gains(
      effects: pressed(spell: on_full_health, caster: hurt, rolls: []),
    )
    == []
    as "50 of 100 is 50 percent, not 100"
}

pub fn a_gain_behind_a_vital_the_server_does_not_hold_is_not_given_and_leaves_a_line_test() -> Nil {
  use <- owned_test.run(5000)
  let unheld =
    spell_with(proxies: [], gains: [
      gain_behind(
        prerequisite: prerequisite_support.single(id: 1, condition: #(
          73,
          4,
          9,
          0,
        )),
      ),
    ])
  let effects = pressed(spell: unheld, caster: support.caster(), rolls: [])
  assert support.gains(effects:) == []
    as "Vital 9 (Resource4) is a slot the caster's class does not hold, so no rule of the server holds it: the prerequisite is not read and no gain is given"
  assert list.length(support.debug_lines(effects)) == 1
    as "and one debug line says so"
}

// ---- the order within a go ----

pub fn a_gain_behind_a_type_15_prerequisite_reads_the_casts_as_they_stood_before_the_go_starts_its_children_test() -> Nil {
  use <- owned_test.run(5000)
  let not_under_the_child =
    spell_with(proxies: [proxy(spell_plan.Always)], gains: [
      gain_behind(
        prerequisite: prerequisite_support.single(id: 1, condition: #(
          15,
          2,
          0,
          child_spell4_id,
        )),
      ),
    ])
  let effects =
    pressed(spell: not_under_the_child, caster: support.caster(), rolls: [])
  assert children_started(effects) == 1
    as "the Proxy starts its child 99 at the go, aimed at the caster"
  assert support.gains(effects:) == [[Gain(slot: 1, amount: 5)]]
    as "a server choice: a gate decides on the state before the go, so the child 99 the same go starts does not yet target the caster and 'not under 99' (type 15, comparison 2) passes"
}

pub fn a_gain_behind_a_type_15_prerequisite_reads_the_casts_as_they_stood_before_the_go_finishes_the_cast_test() -> Nil {
  use <- owned_test.run(5000)
  let under_its_own_cast =
    spell_with(proxies: [], gains: [
      gain_behind(
        prerequisite: prerequisite_support.single(id: 1, condition: #(
          15,
          1,
          0,
          1,
        )),
      ),
    ])
  assert support.gains(
      effects: pressed(
        spell: under_its_own_cast,
        caster: support.caster(),
        rolls: [],
      ),
    )
    == [[Gain(slot: 1, amount: 5)]]
    as "a server choice: the last go's gate decides before its finish, so the live cast of Spell4 1 (the spell itself, aimed at the caster) still targets the caster and 'under 1' (type 15, comparison 1) passes"
}

pub fn a_gain_behind_a_resource_slot_the_class_does_not_hold_is_not_given_and_leaves_a_line_test() -> Nil {
  use <- owned_test.run(5000)
  assert class_resource.slot(resources: support.caster().resources) == 1
    as "the planted caster's class holds slot 1 (Vital 6, Resource1) only"
  list.each([#(73, 5), #(73, 7), #(71, 11)], fn(condition) {
    let spell =
      spell_with(proxies: [], gains: [
        gain_behind(
          prerequisite: prerequisite_support.single(id: 1, condition: #(
            condition.0,
            1,
            condition.1,
            0,
          )),
        ),
      ])
    let effects = pressed(spell:, caster: support.caster(), rolls: [])
    assert support.gains(effects:) == []
      as "0x1403b3320: Vitals 5 to 11 read the caster's resource slots 0 to 6; a slot the class does not hold is not read, not 0 of 0, so even 'equal to 0' gives no gain"
    assert list.length(support.debug_lines(effects)) == 1
      as "and one debug line says so"
  })
}

pub fn a_gain_behind_the_units_difficulty_is_not_given_to_a_player_and_leaves_a_line_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    spell_with(proxies: [], gains: [
      gain_behind(
        prerequisite: prerequisite_support.single(id: 30_527, condition: #(
          179,
          4,
          7,
          0,
        )),
      ),
    ])
  let effects = pressed(spell:, caster: support.caster(), rolls: [])
  assert support.gains(effects:) == []
    as "0x14049eeb0: type 179 reads the unit's difficulty, which only a creature's side supplies; a player's subject holds none, so the prerequisite is not read"
  assert list.length(support.debug_lines(effects)) == 1
    as "and one debug line says so"
}

// ---- the one list of effects: the order the gates walk it in ----

/// A lasting effect, a removal and a heal, all aimed at the caster in every phase, each
/// behind this condition; given in the scrambled order heal, removal, lasting.
fn lasting_remove_and_heal(condition condition: spell_plan.Condition) -> Spell {
  support.with_effects(
    spell: Spell(..support.exempt(), cast_time_ms: 0),
    kinds: [
      spell_plan.HealEffect(spell_plan.Heal(
        effect_id: Spell4EffectsId(3),
        vital: effect_kind.Health,
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        condition:,
        tag: spend.always,
        formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: []),
        delay_ms: 0,
      )),
      spell_plan.RemoveEffect(spell_plan.ForceRemove(
        effect_id: Spell4EffectsId(2),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        selector: lasting.Spell(Spell4Id(7)),
        count: 1,
        condition:,
        tag: spend.always,
      )),
      spell_plan.LastingEffect(spell_plan.Lasting(
        effect_id: Spell4EffectsId(1),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row: lasting.LastingRow(
          delay_ms: 0,
          duration_ms: 0,
          until_removed: True,
        ),
        condition:,
        tag: spend.always,
      )),
    ],
  )
}

/// The effect ids of the rows `lasting_applied` let pass at the go of phase 0, with the
/// rolls it left, given these rolls.
fn passed_with(
  spell spell: Spell,
  rolls rolls: List(Int),
) -> #(List(Int), List(Int)) {
  let #(applied, _, left) =
    cast_control.lasting_applied(
      spell:,
      phase: 0,
      spent: None,
      subject: prerequisite_support.holding(held: [], second_unit: None),
      told: fn(_) { False },
      rolls:,
    )
  #(
    list.map(applied.passed, fn(planned) {
      case planned.kind {
        spell_plan.LastingEffect(lasting: row) -> row.effect_id.value
        spell_plan.RemoveEffect(remove: row) -> row.effect_id.value
        spell_plan.HealEffect(heal: row) -> row.effect_id.value
        spell_plan.ProxyEffect(..)
        | spell_plan.GainEffect(..)
        | spell_plan.ModifierEffect(..)
        | spell_plan.ForcedMoveEffect(..)
        | spell_plan.StruckMoveEffect(..)
        | spell_plan.CooldownEffect(..)
        | spell_plan.StealthEffect(..)
        | spell_plan.RemoveStealthEffect(..)
        | spell_plan.ProcEffect(..)
        | spell_plan.ControlEffect(..)
        | spell_plan.DespawnEffect(..)
        | spell_plan.UnitStateEffect(..)
        | spell_plan.DelayEffect(..)
        | spell_plan.QuestAdvanceEffect(..) -> -1
      }
    }),
    left,
  )
}

pub fn applied_passed_holds_the_rows_each_gate_passed_in_rank_order_test() -> Nil {
  use <- owned_test.run(5000)
  let always = lasting_remove_and_heal(condition: spell_plan.Always)
  assert passed_with(spell: always, rolls: []) == #([1, 2, 3], [])
    as "rows given heal, removal, lasting are held in the plan's rank order: lasting (1), removal (2), heal (3), the order `gate.rolls_needed` and `lasting_applied` took the kinds in"
  let chancy =
    lasting_remove_and_heal(
      condition: spell_plan.GatedOnCaster(gates: [chance_gate()]),
    )
  assert passed_with(spell: chancy, rolls: [50, 51, 51]) == #([1], [])
    as "Prerequisite 4585 passes a roll of at most 50: the first roll of the go is the lasting effect's, the second the removal's, the third the heal's"
  assert passed_with(spell: chancy, rolls: [51, 51, 50]) == #([3], [])
    as "the same rolls reversed pass the heal alone: the heal's gate is checked last"
  let #(state, asked) = live_go_of(spell: chancy)
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 3
    as "one type 37 condition on each of the three rows, each reaching the caster alone: three rolls, as many as `lasting_applied` drew above"
}

/// A property modifier with no life (no durationTime, flags bit 2 clear) and a lasting
/// effect, both aimed at the caster in every phase behind this condition, given in the
/// order modifier, lasting.
fn lifeless_modifier_and_lasting(
  condition condition: spell_plan.Condition,
) -> Spell {
  support.with_effects(
    spell: Spell(..support.exempt(), cast_time_ms: 0),
    kinds: [
      spell_plan.ModifierEffect(
        spell_plan.PropertyModifier(..lifeless_modifier(), condition:),
      ),
      spell_plan.LastingEffect(spell_plan.Lasting(
        effect_id: Spell4EffectsId(1),
        phase_flags: -1,
        aim: spell_plan.AimsAtCaster,
        row: lasting.LastingRow(
          delay_ms: 0,
          duration_ms: 0,
          until_removed: True,
        ),
        condition:,
        tag: spend.always,
      )),
    ],
  )
}

/// A property modifier whose row has neither a durationTime nor flags bit 2.
fn lifeless_modifier() -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    ..support.falling_row(),
    effect_id: Spell4EffectsId(2),
    phase_flags: -1,
    row: lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
  )
}

pub fn rolls_needed_counts_no_roll_for_a_modifier_with_no_life_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    lifeless_modifier_and_lasting(
      condition: spell_plan.GatedOnCaster(gates: [chance_gate()]),
    )
  let #(state, asked) = live_go_of(spell:)
  assert cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 1
    as "`lasting.has_life`: a property modifier with neither a durationTime nor flags bit 2 is no time to be changed for, so the go checks no gate for it and its type 37 condition draws no roll; the lasting row's alone is counted"
  assert passed_with(spell:, rolls: [50, 51]) == #([1], [51])
    as "the lasting row's gate takes the go's first roll (Prerequisite 4585 passes a roll of at most 50) and the second roll is left"
  assert cast_gate.gates_checked_on_caster(
      kind: spell_plan.ModifierEffect(modifier: lifeless_modifier()),
    )
    == Error(Nil)
    as "one filter decides the count and the check: a modifier with no life has no gates"
}

/// The rolls the first go of `spell` takes from `rolls`, aimed at the caster alone: the caster
/// gates of `lasting_applied`, then the target gates of the rows it reaches, each checked as
/// `cast_gate.checked` takes its type 37 conditions' rolls off the front.
fn rolls_the_go_takes(spell spell: Spell, rolls rolls: List(Int)) -> Int {
  rolls_taken(go: live_go_of(spell:), spell:, struck: [], rolls:).0
}

/// The same for the go the cast `go` asks, in a round that closed with `struck`: how many
/// rolls it takes and the effect ids of the heal rows that pass their caster gates.
fn rolls_taken(
  go go: #(cast_state.State, cast_state.GoAsked),
  spell spell: Spell,
  struck struck: List(cast_state.Struck),
  rolls rolls: List(Int),
) -> #(Int, List(Int)) {
  let #(state, asked) = go
  let assert Ok(live) = dict.get(state.casts, asked.cast_id)
    as "the cast is live while its go is asked"
  let subject = prerequisite_support.holding(held: [], second_unit: None)
  let #(applied, _, left) =
    cast_control.lasting_applied(
      spell:,
      phase: 0,
      spent: None,
      subject:,
      told: cast_gate.heal_told(_, primary_target: live.primary_target, struck:),
      rolls:,
    )
  let aimed =
    cast.aimed_at(
      applied:,
      caster: support.caster(),
      live:,
      struck:,
      gates_passed: dict.new(),
      phase: 0,
      restricting: [],
      target_verdict: fn(gate, _unit_id, rolls) {
        cast_gate.checked(prerequisite: gate, subject:, rolls:)
      },
      rolls: left,
    )
  #(
    list.length(rolls) - list.length(aimed.rolls_left),
    cast_state.passed_of(applied:, as_kind: spell_plan.as_heal)
      |> list.map(fn(row) { row.effect_id.value }),
  )
}

/// The player in the caster's sight that the spell is pressed at.
const ally = 40

/// The first go of `spell`, pressed at the ally as Mind Over Body is (a beneficial Targeted
/// kind, Spell4TargetMechanics row 4): the cast and the go it asks.
fn live_go_at_the_ally(
  spell spell: Spell,
) -> #(cast_state.State, cast_state.GoAsked) {
  let spell =
    Spell(
      ..spell,
      targeting: spell_tables.client_spell(spell4_id: 32_820).targeting,
    )
  let caster =
    cast_state.Caster(
      ..support.caster(),
      other_players: player_state_support.in_range_of_the_caster(units: [ally]),
      players_in_sight: dict.from_list([
        #(
          ally,
          PlayerAddress(
            connection: ConnectionId(ally),
            unit_id: ally,
            stay: map_support.stay(count: ally),
          ),
        ),
      ]),
    )
  let assert Ok(#(state, raw)) =
    cast.take(
      cast: cast_state.new(),
      message: cast_state.Pressed,
      body: support.press_body(
        client_cast_id: 9,
        bag_index: 8,
        target: ally,
        press: 1,
      ),
      caster:,
      plans: support.with_spells(plans: support.plans(), spells: [spell]),
      target_of: fn(unit_id) {
        case unit_id == ally {
          True -> activate.AnotherPlayer
          False -> activate.Unseen
        }
      },
      now: support.at(ms: 1000),
    )
    as "the press at the ally in sight is taken"
  let assert [asked] = support.goes_asked(effects: raw)
    as "the press of a spell with no cast time asks for its go at once"
  #(state, asked)
}

/// A round whose one unit is the ally, who answered the heal rows `effect_ids`.
fn ally_answered(effect_ids effect_ids: List(Int)) -> List(cast_state.Struck) {
  [
    cast_state.Hit(
      unit_id: ally,
      unit: cast_state.HitOtherPlayer(
        heals: list.map(effect_ids, fn(effect_id) {
          strike_tell.HealLanded(
            effect_id: Spell4EffectsId(effect_id),
            vital: effect_kind.Health,
            split: heal_split.Split(
              amount: 121,
              shield: 0,
              health: 100,
              overheal: 21,
            ),
          )
        }),
      ),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
  ]
}

/// One go at the ally: why, the aim and condition of row 1, what the ally answered (none: the
/// strike gave no answer; some: the heal rows it told, which may be none), the rolls given,
/// how many rolls the go is counted to take and the heal rows that pass their caster gates.
type RollRow {
  RollRow(
    why: String,
    aim: spell_plan.Aim,
    condition: spell_plan.Condition,
    answered: Option(List(Int)),
    rolls: List(Int),
    counted: Int,
    passed: List(Int),
  )
}

pub fn a_heal_row_the_ally_answered_takes_no_roll_at_the_go_and_is_not_counted_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 1 heals the ally or the caster and the ally, and row 2 the caster, each behind
  // Prerequisite 4585's type 37 condition (comparison 6 on 50: a roll of 50 passes, 51
  // fails). The strike drew the ally row's rolls once when it gated the row it told, so an
  // answered row takes none at the go, and the ally takes none for the target gate of a row
  // that reaches the caster as well.
  let heal = fn(id, aim, condition) {
    support.heal_row(
      id:,
      vital: effect_kind.Health,
      aim:,
      delay_ms: 0,
      condition:,
      formula: support.mind_over_body_formula(),
    )
  }
  let caster_gate = spell_plan.GatedOnCaster([chance_gate()])
  let both_gates =
    spell_plan.GatedOnCasterAndTarget(
      caster: [chance_gate()],
      target: chance_gate(),
    )
  let primary = spell_plan.AimsAtPrimaryTarget
  let caster_and_primary = spell_plan.AimsAtCasterAndPrimaryTarget
  let area = spell_plan.AimsAtArea
  let caster_and_area = spell_plan.AimsAtCasterAndArea
  list.each(
    [
      RollRow(
        "no answer, the ally row behind a caster gate: both rows draw their rolls, 50 then 51, so the caster's row fails",
        primary,
        caster_gate,
        None,
        [50, 51],
        2,
        [1],
      ),
      RollRow(
        "the ally answered row 1: it draws none, so the roll 50 reaches the caster's row, which passes",
        primary,
        caster_gate,
        Some([1]),
        [50, 51],
        1,
        [1, 2],
      ),
      RollRow(
        "no answer, the ally row behind a caster gate and a target gate: a roll for the caster gate and one for the ally's target gate, then the caster's row",
        primary,
        both_gates,
        None,
        [50, 50, 50],
        3,
        [1, 2],
      ),
      RollRow(
        "the ally answered row 1, behind both gates: its target gate is not checked again either, so only the caster's row draws",
        primary,
        both_gates,
        Some([1]),
        [50, 51],
        1,
        [1, 2],
      ),
      RollRow(
        "no answer, row 1 aimed at the caster and the ally behind both gates: the caster gate once, the target gate for the caster and for the ally, then the caster's row",
        caster_and_primary,
        both_gates,
        None,
        [50, 50, 50, 50],
        4,
        [1, 2],
      ),
      RollRow(
        "the ally answered row 1, aimed at the caster as well: its caster gate and the target gate for the caster are checked at the go, the target gate for the ally is not",
        caster_and_primary,
        both_gates,
        Some([1]),
        [50, 50, 50],
        3,
        [1, 2],
      ),
      RollRow(
        "the ally answered row 1, aimed at the area alone behind a caster gate: the strike gated it once and the caster is not healed by it, so the go draws none and the roll 50 reaches the caster's row, which passes",
        area,
        caster_gate,
        Some([1]),
        [50, 51],
        1,
        [1, 2],
      ),
      RollRow(
        "the ally answered row 1, aimed at the area alone behind both gates: neither gate is checked again",
        area,
        both_gates,
        Some([1]),
        [50, 51],
        1,
        [1, 2],
      ),
      RollRow(
        "the ally answered with no heal (a Proxy selected it), row 1 aimed at the caster and the area behind both gates: the empty answer is an answer, so the target gate is not drawn for the ally; the caster gate, the caster's own target gate and the caster's row are",
        caster_and_area,
        both_gates,
        Some([]),
        [50, 50, 50],
        3,
        [1, 2],
      ),
      RollRow(
        "no answer, row 1 aimed at the area alone: the strike told it to the allies it selected and drew its rolls, so the go draws none whoever answered",
        area,
        caster_gate,
        None,
        [50, 51],
        1,
        [1, 2],
      ),
    ],
    fn(row) {
      let spell =
        support.with_effects(
          spell: Spell(..support.exempt(), cast_time_ms: 0),
          kinds: [
            spell_plan.HealEffect(heal(1, row.aim, row.condition)),
            spell_plan.HealEffect(heal(2, spell_plan.AimsAtCaster, caster_gate)),
          ],
        )
      let go = live_go_at_the_ally(spell:)
      let struck = case row.answered {
        None -> []
        Some(effect_ids) -> ally_answered(effect_ids:)
      }
      assert cast_gate.rolls_needed(
          cast: go.0,
          caster: support.caster().unit_id,
          cast_id: { go.1 }.cast_id,
          phase: { go.1 }.phase,
          struck:,
        )
        == row.counted
        as { row.why <> ": the rolls the go is counted to take" }
      assert rolls_taken(go:, spell:, struck:, rolls: row.rolls)
        == #(row.counted, row.passed)
        as {
          row.why
          <> ": the rolls the go takes and the rows that pass their caster gates"
        }
    },
  )
}

pub fn rolls_needed_counts_no_roll_for_the_target_gate_of_a_modifier_with_no_life_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    lifeless_modifier_and_lasting(
      condition: spell_plan.GatedOnTarget(prerequisite: chance_gate()),
    )
  let #(state, asked) = live_go_of(spell:)
  let counted =
    cast_gate.rolls_needed(
      cast: state,
      caster: support.caster().unit_id,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
  assert counted == 1
    as "`lasting.has_life`: the modifier with neither a durationTime nor flags bit 2 is applied by no go, so its target gate (4585, one type 37 condition) is checked for no unit; the lasting row's alone, on the caster it aims at, is counted"
  assert rolls_the_go_takes(spell:, rolls: [50, 51, 52]) == counted
    as "the go draws the one roll of the lasting row's target gate and none for the modifier, so the count is what the go takes"
}

pub fn a_periodic_proxy_aimed_at_the_area_is_armed_though_the_round_struck_nobody_and_a_once_one_starts_no_child_test() -> Nil {
  use <- owned_test.run(5000)
  // A field's own go strikes nobody (Nullifier's field 58868 holds a Fluff on its primary
  // target and a Proxy 141450 aimed at the area), yet text 574032 has that Proxy tick; a
  // Proxy that casts once on each struck unit has no unit without a Hit
  // (`cast_gate.starts_a_child`).
  let at_the_area =
    Proxy(..proxy(spell_plan.Always), target: spell_plan.OnEachStruck)
  let periodic =
    Proxy(
      ..at_the_area,
      period: option.Some(spell_plan.Periodic(
        schedule: ticking.Schedule(
          delay_ms: 0,
          tick_ms: 1000,
          duration_ms: 6000,
          count: ticking.Ticks(6),
        ),
        persistence: None,
      )),
    )
  let at_the_caster = Proxy(..periodic, target: spell_plan.OnCaster)
  let hit = support.hits([21])
  let deflected = [cast_state.Deflected(unit_id: 21)]
  let armed = fn(proxy, struck) {
    cast_gate.proxies_with_targets(
      spell: support.with_effects(
        spell: support.child(spell4_id: 7000, base: 3),
        kinds: [spell_plan.ProxyEffect(proxy:)],
      ),
      phase: 0,
      struck:,
      spent: None,
    )
    != []
  }
  list.each(
    [
      #(
        periodic,
        [],
        True,
        "a periodic Proxy at the area is armed at a go that struck nobody",
      ),
      #(periodic, hit, True, "and at a go that hit a unit"),
      #(periodic, deflected, True, "and at a go whose only unit deflected"),
      #(
        at_the_area,
        [],
        False,
        "a once Proxy at the area starts no child at a go that struck nobody",
      ),
      #(at_the_area, deflected, False, "nor at a go whose only unit deflected"),
      #(at_the_area, hit, True, "but starts one at a go that hit a unit"),
      #(
        at_the_caster,
        [],
        True,
        "a periodic Proxy at the caster is armed as before",
      ),
      #(
        Proxy(..at_the_caster, period: None),
        [],
        True,
        "a once Proxy at the caster starts as before",
      ),
    ],
    fn(row) {
      let #(proxy, struck, expected, reason) = row
      assert armed(proxy, struck) == expected as reason
    },
  )
}

// ---- a modifier row on another player ----

/// A player the caster sees that the press does not name, and a creature; the caster is the
/// default caster's unit 7.
const bystander = 41

const creature = 21

fn address_of(unit_id unit_id: Int) -> PlayerAddress {
  PlayerAddress(
    connection: ConnectionId(unit_id),
    unit_id:,
    stay: map_support.stay(count: unit_id),
  )
}

/// The default caster, who sees these players.
fn seeing(players players: List(Int)) -> cast_state.Caster {
  cast_state.Caster(
    ..support.caster(),
    other_players: player_state_support.in_range_of_the_caster(units: players),
    players_in_sight: dict.from_list(
      list.map(players, fn(unit_id) { #(unit_id, address_of(unit_id:)) }),
    ),
  )
}

/// A player another player's heal answer hit.
fn healed_player(unit_id unit_id: Int) -> cast_state.Struck {
  cast_state.Hit(
    unit_id:,
    unit: cast_state.HitOtherPlayer(heals: []),
    descriptions: [],
    controls: [],
    armor_removed: 0,
    ticking: [],
  )
}

/// Phantasmal Armor's absorb row, 130470, with the aim given.
fn absorb_aimed(aim aim: spell_plan.Aim) -> spell_plan.PropertyModifier {
  support.armor_absorb_row(id: 130_470, support_factor: 2.605299949645996, aim:)
}

/// Phantasmal Armor's modifier row, 130474, with the aim given.
fn modifier_aimed(aim aim: spell_plan.Aim) -> spell_plan.PropertyModifier {
  support.armor_modifier_row(id: 130_474, aim:)
}

/// The units a row lands on, in the order its aim names them: each unit the aim names, with
/// `primary_target` as the primary target and the units the round hit as the area, that
/// `modifier_applies` accepts.
fn landing_on(
  row row: spell_plan.PropertyModifier,
  caster caster: cast_state.Caster,
  primary_target primary_target: Int,
  press_target press_target: option.Option(Int),
  struck struck: List(cast_state.Struck),
) -> List(Int) {
  cast_gate.rows_with_units(
    rows: [row],
    aim: spell_plan.modifier_aim,
    caster:,
    primary_target:,
    struck:,
  )
  |> list.filter(fn(entry) {
    cast_gate.modifier_applies(
      row: entry.0,
      unit_id: entry.1,
      caster:,
      struck:,
      press_target:,
    )
  })
  |> list.map(fn(entry) { entry.1 })
}

pub fn a_modifier_row_lands_on_a_player_only_when_the_press_named_it_and_the_caster_sees_it_test() -> Nil {
  use <- owned_test.run(5000)
  let primary = spell_plan.AimsAtPrimaryTarget
  let one_second =
    lasting.LastingRow(
      delay_ms: 1000,
      duration_ms: 10_000,
      until_removed: False,
    )
  let until_removed =
    lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True)
  let at_ally = option.Some(ally)
  // Rows 130470 and 130474 are Phantasmal Armor's, each targetFlags 2: an `AbsorbChange` and a
  // `StruckChange` aimed at the primary target (`table_rows -- Spell4Effects 130470 130474`).
  // Each row: why, the row, the press target the rule is given, the row's primary target,
  // the players the caster sees, what the round struck, and the units the row lands on.
  let rows = [
    #(
      "an absorb aimed at the primary target lands on the player the press named when the caster sees it",
      absorb_aimed(aim: primary),
      at_ally,
      ally,
      [ally],
      [],
      [ally],
    ),
    #(
      "the same player out of the caster's sight: it does not",
      absorb_aimed(aim: primary),
      at_ally,
      ally,
      [],
      [],
      [],
    ),
    #(
      "a StruckChange row aimed at the primary target lands on the player the press named",
      modifier_aimed(aim: primary),
      at_ally,
      ally,
      [ally],
      [],
      [ally],
    ),
    #(
      "a StruckChange row aimed at the primary target and the area, the player also in the area, lands once",
      modifier_aimed(aim: spell_plan.AimsAtPrimaryTargetAndArea),
      at_ally,
      ally,
      [ally],
      [healed_player(unit_id: ally)],
      [ally],
    ),
    #(
      "a StruckChange row aimed at the area alone does not land on a player the press did not name that a heal's answer hit (friendly areas are not built)",
      modifier_aimed(aim: spell_plan.AimsAtArea),
      at_ally,
      ally,
      [ally, bystander],
      [healed_player(unit_id: bystander)],
      [],
    ),
    #(
      "a property change aimed at the caster lands on the caster alone, whoever the press named",
      spell_plan.PropertyModifier(
        ..modifier_aimed(aim: primary),
        change: spell_plan.PropertyChange(support.slowing_change()),
      ),
      at_ally,
      ally,
      [ally],
      [],
      [7],
    ),
    #(
      "a disguise lands on the caster alone: no sender builds it for another player",
      spell_plan.PropertyModifier(
        ..modifier_aimed(aim: primary),
        change: spell_plan.LookChange(support.disguise_of(display: 1)),
      ),
      at_ally,
      ally,
      [ally],
      [],
      [7],
    ),
    #(
      "a child a Proxy started has no press target: a row aimed at its primary target does not land on a player",
      absorb_aimed(aim: primary),
      option.None,
      ally,
      [ally],
      [],
      [],
    ),
    #(
      "an absorb aimed at the caster and the primary target lands on both",
      absorb_aimed(aim: spell_plan.AimsAtCasterAndPrimaryTarget),
      at_ally,
      ally,
      [ally],
      [],
      [7, ally],
    ),
    #(
      "a StruckChange row aimed at the area lands on the creature the round hit, as before",
      modifier_aimed(aim: spell_plan.AimsAtArea),
      at_ally,
      ally,
      [ally],
      [support.creature_hit(unit_id: creature, life: 3, struck_at_ms: 1000)],
      [creature],
    ),
    #(
      "an absorb aimed at the primary target of a press at oneself lands on the caster, as before",
      absorb_aimed(aim: primary),
      option.Some(7),
      7,
      [ally],
      [],
      [7],
    ),
    #(
      "a StruckChange row aimed at the primary target of a press at oneself lands on the caster (Spell4Effects 130474)",
      modifier_aimed(aim: primary),
      option.Some(7),
      7,
      [ally],
      [],
      [7],
    ),
    #(
      "a StruckChange row aimed at the primary target and the area, pressed at oneself, lands on the caster and on the creature hit, once each",
      modifier_aimed(aim: spell_plan.AimsAtPrimaryTargetAndArea),
      option.Some(7),
      7,
      [],
      [support.creature_hit(unit_id: creature, life: 3, struck_at_ms: 1000)],
      [7, creature],
    ),
    #(
      "a StruckChange row aimed at the area alone, pressed at oneself, lands on the creature hit and not on the caster",
      modifier_aimed(aim: spell_plan.AimsAtArea),
      option.Some(7),
      7,
      [],
      [support.creature_hit(unit_id: creature, life: 3, struck_at_ms: 1000)],
      [creature],
    ),
    #(
      "a StruckChange row aimed at the primary target of a child a Proxy started, whose primary target stands for the caster, does not land on the caster",
      modifier_aimed(aim: primary),
      option.None,
      7,
      [],
      [],
      [],
    ),
    #(
      "an Interrupt Armor row aimed at the primary target lands on the player the press named when the caster sees it (Spell4Effects 199192)",
      support.spectral_form_row(aim: primary),
      at_ally,
      ally,
      [ally],
      [],
      [ally],
    ),
    #(
      "the same Interrupt Armor row with the player out of the caster's sight: it does not",
      support.spectral_form_row(aim: primary),
      at_ally,
      ally,
      [],
      [],
      [],
    ),
    #(
      "the same Interrupt Armor row with a delay lands nothing on a player, as an absorb row does not",
      spell_plan.PropertyModifier(
        ..support.spectral_form_row(aim: primary),
        row: one_second,
      ),
      at_ally,
      ally,
      [ally],
      [],
      [],
    ),
    #(
      "the same Interrupt Armor row that lasts until removed lands nothing on a player",
      spell_plan.PropertyModifier(
        ..support.spectral_form_row(aim: primary),
        row: until_removed,
      ),
      at_ally,
      ally,
      [ally],
      [],
      [],
    ),
    #(
      "an Interrupt Armor row aimed at the caster lands on the caster alone, whoever the press named",
      support.spectral_form_row(aim: spell_plan.AimsAtCaster),
      at_ally,
      ally,
      [ally],
      [],
      [7],
    ),
    #(
      "an Interrupt Armor row aimed at the primary target of a child a Proxy started on the caster (no press target) lands on the caster alone",
      support.spectral_form_row(aim: primary),
      option.None,
      7,
      [ally],
      [],
      [7],
    ),
    #(
      "a row with a delay lands nothing on a player (stated gap: no ability row has one)",
      spell_plan.PropertyModifier(..absorb_aimed(aim: primary), row: one_second),
      at_ally,
      ally,
      [ally],
      [],
      [],
    ),
    #(
      "a row that lasts until removed lands nothing on a player (stated gap: it would need an end of its own)",
      spell_plan.PropertyModifier(
        ..absorb_aimed(aim: primary),
        row: until_removed,
      ),
      at_ally,
      ally,
      [ally],
      [],
      [],
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, planned, press_target, primary_target, sees, struck, lands) =
      row
    assert landing_on(
        row: planned,
        caster: seeing(players: sees),
        primary_target:,
        press_target:,
        struck:,
      )
      == lands
      as reason
  })
  assert cast_gate.modifier_refusal(
      row: support.spectral_form_row(aim: primary),
      unit_id: ally,
      caster: seeing(players: []),
      press_target: at_ally,
    )
    == option.Some("the player is not in the caster's sight")
    as "an Interrupt Armor row aimed at the player the press named, out of the caster's sight, is refused with that reason"
}
