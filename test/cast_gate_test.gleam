//// The gates a go checks against the caster (`genesis_prime/game/cast`): a Proxy
//// behind a caster apply prerequisite or one named by its dataBits06 starts its
//// child only when the gate passes, one behind a target apply prerequisite never
//// starts, a gain behind a prerequisite of a vital reads the caster's vitals, and
//// a type 37 condition takes a roll only when one is checked. Expected values come
//// from these places, each named at its assertion:
//// - The client's rows: Prerequisite 903 (`Prerequisite.prerequisiteTypeId.28`,
////   comparison 1: in combat), 4585 (type 37, comparison 6, value 50), 11153
////   (type 73, comparison 4, vital 6, value 100), 4918 (type 71, comparison 1,
////   vital 6, value 100), 33154 (type 59, which the server does not read) and 5734
////   (type 108 in a target apply column, `Spell4Effects.prerequisiteIdTargetApply`),
////   copied as `table_rows -- Prerequisite <id>` prints them.
//// - The client's code: `0x1403b3320` (Vitals 5 to 11 are the caster's resource
////   slots 0 to 6) and `0x14049eeb0` (type 179 reads the unit's difficulty, which a
////   player does not hold here).
//// - The design of the step: a gate decides on the state before the go's own
////   effects (the casts as they stood before its children start and before its
////   finish), a Proxy's caster-side gates are checked at its
////   phase's go with the caster as subject, a Proxy with a target apply
////   prerequisite is not started, and a prerequisite of a type or a vital not read
////   leaves one debug line (`Spell4Effects.effectType.26.dataBits06`).
//// The bag index 8 is the exempt spell, which these tests replace with a spell of no
//// cast time and one Proxy.

import cast_support as support
import genesis_prime/game/cast
import genesis_prime/game/class_resource.{Gain}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Proxy, type Spell, Proxy, Spell}
import genesis_prime/game/spend
import genesis_prime/message/spell_started
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{PrerequisiteId, Spell4EffectsId}
import gleam/dict
import gleam/list
import gleam/option.{Some}
import gleam/string
import owned_test
import prerequisite_support

const child_spell4_id = 99

/// A Proxy to the child spell 99, aimed at the caster, in phase 0, behind this
/// condition.
fn proxy(condition: spell_plan.Condition) -> Proxy {
  Proxy(
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
  Spell(..support.exempt(), cast_time_ms: 0, proxies:, gains:)
}

/// Every effect of a press of the bag index 8, answered with a round that struck
/// nobody, the go taking these rolls.
fn pressed(
  spell spell: Spell,
  caster caster: cast.Caster,
  rolls rolls: List(Int),
) -> List(cast.Effect) {
  let plans = support.with_spells(plans: support.plans(), spells: [spell])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
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

fn children_started(effects: List(cast.Effect)) -> Int {
  list.count(support.writes(effects:), fn(frame) {
    case frame.message_id == spell_started.message_id {
      True -> {
        let assert Ok(started) = spell_started.decode(frame.body)
          as "0x7ff decodes"
        started.spell4_id == child_spell4_id
      }
      False -> False
    }
  })
}

fn debug_lines(effects: List(cast.Effect)) -> List(String) {
  list.filter_map(support.logs(effects:), fn(line) {
    case line.0 == LogDebug {
      True -> Ok(line.1)
      False -> Error(Nil)
    }
  })
}

fn in_combat() -> cast.Caster {
  cast.Caster(..support.caster(), in_combat: True)
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
  assert debug_lines(effects) == [] as "a gate that passes leaves no line"
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
  assert debug_lines(effects) == []
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
  let spell =
    spell_with(
      proxies: [
        gated_on([
          prerequisite_support.single(id: 33_154, condition: #(59, 5, 42_569, 2)),
        ]),
      ],
      gains: [],
    )
  let effects = pressed(spell:, caster: in_combat(), rolls: [])
  assert children_started(effects) == 0
    as "Prerequisite 33154 is type 59, which the server does not read: the client would decide it, the server cannot, so the Proxy does not start"
  let lines = debug_lines(effects)
  assert list.length(lines) == 1
  assert list.all(lines, fn(line) {
    string.contains(line, "Spell4 99")
    && string.contains(line, "prerequisite 33154")
    && string.contains(line, "of type 59")
  })
    as "one line names the child, the prerequisite and its type"
}

pub fn a_proxy_behind_a_target_apply_prerequisite_is_not_started_test() -> Nil {
  use <- owned_test.run(5000)
  let spell =
    spell_with(
      proxies: [
        proxy(spell_plan.GatedOnTarget(prerequisite_id: PrerequisiteId(5734))),
      ],
      gains: [],
    )
  let effects = pressed(spell:, caster: in_combat(), rolls: [])
  assert children_started(effects) == 0
    as "Prerequisite 5734 sits in Spell4Effects.prerequisiteIdTargetApply: the server checks no target-side prerequisite"
  assert list.length(debug_lines(effects)) == 1
    as "one debug line says it is not started"
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

fn live_go_of(spell spell: Spell) -> #(cast.State, cast.GoAsked) {
  let plans = support.with_spells(plans: support.plans(), spells: [spell])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: 8,
      target: 0,
      at: 1000,
    )
  let assert [asked] =
    list.filter_map(raw, fn(effect) {
      case effect {
        cast.Strike(asked:) -> Ok(asked)
        cast.Send(..)
        | cast.Tell(..)
        | cast.StartTimer(..)
        | cast.CancelTimer(..)
        | cast.Log(..)
        | cast.Pay(..)
        | cast.Gain(..) -> Error(Nil)
      }
    })
    as "the press of a spell with no cast time asks for its go at once"
  #(state, asked)
}

pub fn a_go_takes_a_roll_for_each_type_37_condition_it_may_check_and_none_otherwise_test() -> Nil {
  use <- owned_test.run(5000)
  let needing = spell_with(proxies: [gated_on([chance_gate()])], gains: [])
  let #(state, asked) = live_go_of(spell: needing)
  assert cast.rolls_needed(
      cast: state,
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
  assert cast.rolls_needed(
      cast: state,
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
  assert cast.rolls_needed(
      cast: state,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 0
    as "a Proxy with no gate takes none"
  let not_there =
    cast.rolls_needed(
      cast: state,
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
    slot: 1,
    amount: 5,
    phase_flags: 1,
    prerequisite: Some(prerequisite),
    tag: spend.always,
  )
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
    cast.Caster(
      ..support.caster(),
      life_vitals: dict.from_list([
        #(1, prerequisite.Vital(current: 50.0, maximum: 100.0)),
      ]),
    )
  let full =
    cast.Caster(
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
  let focus =
    spell_with(proxies: [], gains: [
      gain_behind(
        prerequisite: prerequisite_support.single(id: 1, condition: #(
          73,
          4,
          15,
          0,
        )),
      ),
    ])
  let effects = pressed(spell: focus, caster: support.caster(), rolls: [])
  assert support.gains(effects:) == []
    as "Vital 15 (Focus) is held by no rule of the server: the prerequisite is not read, so no gain is given"
  assert list.length(debug_lines(effects)) == 1 as "and one debug line says so"
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
    assert list.length(debug_lines(effects)) == 1
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
  assert list.length(debug_lines(effects)) == 1 as "and one debug line says so"
}
