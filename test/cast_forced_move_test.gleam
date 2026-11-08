//// The cast rule's forced moves aimed at the caster (`genesis_prime/game/cast`).
//// Expected values come from these places:
//// - `Spell4Effects.effectType.3.player`: for a forced move on the player's own unit
////   the server sends only the go listing the effect on that unit; the client works out
////   the destination and moves itself. So the rule writes the row into the caster's
////   target info and starts no timer, node or property for it.
//// - `opcode.0x7f4.target_info`: the effect's id and delay are in the unit's list; the
////   kit's rows are 67776 (Gate's blink, delay 200, phaseFlags 1) and 67777
////   (FallingDamageMultiplier, delay 180, duration 400, phaseFlags 1), both aimed at
////   the caster (`table_rows -- Spell4Effects 67776 67777`).
//// - `Spell4Effects.effectType.17` and `opcode.0x7f4.effect_time`: a unit's node takes
////   its life from the effects with a duration, so a spell whose only effect is a forced
////   move (durationTime 0) gives its caster no node and finishes with its go.
//// - `Spell4Effects.phaseFlags`: bit n is phase n; a row applies in the phases it names.
//// - `Prerequisite.prerequisiteTypeId.37` (comparison 6, value 50, row 4585): a type 37
////   condition takes one roll, drawn by the connection from `rolls_needed`.

import cast_support as support
import genesis_prime/game/cast.{type State}
import genesis_prime/game/spell_plan.{type Spell, Always}
import genesis_prime/game/spend
import genesis_prime/message/spell_go
import genesis_prime/table/id.{PrerequisiteId, Spell4EffectsId}
import gleam/int
import gleam/list
import owned_test
import prerequisite_support

/// 67776 as the client holds it: delay 200, phase flags 1.
fn blink_row() -> spell_plan.ForcedMove {
  spell_plan.ForcedMove(
    effect_id: Spell4EffectsId(67_776),
    phase_flags: 1,
    delay_ms: 200,
    condition: Always,
    tag: spend.always,
  )
}

fn holder(
  forced_moves forced_moves: List(spell_plan.ForcedMove),
  modifiers modifiers: List(spell_plan.PropertyModifier),
) -> Spell {
  spell_plan.Spell(
    ..support.child(spell4_id: 34_355, base: 3),
    forced_moves:,
    modifiers:,
  )
}

// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

fn press(spell spell: Spell) -> #(State, List(cast.Effect)) {
  support.pressed_in(
    plans: support.plans_with(spell:),
    state: cast.new(),
    caster: support.caster(),
    bag_index: bag_of_base_3,
    target: 0,
    at: 1000,
  )
}

/// The effects the go's target info of the unit lists, with each one's delay, and the
/// unit.
fn listed(
  effects effects: List(cast.Effect),
) -> List(#(Int, List(#(Int, Int)))) {
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  list.map(decoded.targets, fn(info) {
    #(
      info.unit_id,
      list.map(info.effects, fn(effect) {
        #(effect.spell4_effects_id, effect.delay_ms)
      })
        |> list.sort(fn(first, second) { int.compare(first.0, second.0) }),
    )
  })
}

/// Whether the effect starts or ends a change of one of the caster's properties.
fn changes_a_property(effect effect: cast.Effect) -> Bool {
  case effect {
    cast.CasterChangeStarts(..) | cast.CasterChangeEnds(..) -> True
    cast.Send(..)
    | cast.Tell(..)
    | cast.StartTimer(..)
    | cast.CancelTimer(..)
    | cast.Log(..)
    | cast.Strike(..)
    | cast.Pay(..)
    | cast.TargetChangeStarts(..)
    | cast.TargetChangeEnds(..)
    | cast.StealthChanged(..)
    | cast.Gain(..) -> False
  }
}

// ---- what a go lists ----

pub fn gates_go_lists_the_blink_in_the_casters_target_info_beside_the_modifier_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    press(
      spell: holder(forced_moves: [blink_row()], modifiers: [
        support.falling_row(),
      ]),
    )
  assert listed(effects:) == [#(7, [#(67_776, 200), #(67_777, 180)])]
    as "unit 7 is the caster the rows aim at; 67776 is listed with its delay of 200 beside 67777's 180"
}

pub fn a_forced_move_alone_is_listed_on_the_caster_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    press(spell: holder(forced_moves: [blink_row()], modifiers: []))
  assert listed(effects:) == [#(7, [#(67_776, 200)])]
}

pub fn a_forced_move_of_a_phase_the_go_is_not_in_is_not_listed_test() -> Nil {
  use <- owned_test.run(5000)
  // The row is moved to phaseFlags 2 (phase 1 only), which a go of phase 0 does not hold.
  let later = spell_plan.ForcedMove(..blink_row(), phase_flags: 2)
  let #(_, effects) = press(spell: holder(forced_moves: [later], modifiers: []))
  assert listed(effects:) == [] as "no row applies in phase 0"
}

pub fn a_forced_move_behind_a_target_prerequisite_is_not_listed_test() -> Nil {
  use <- owned_test.run(5000)
  let gated =
    spell_plan.ForcedMove(
      ..blink_row(),
      condition: spell_plan.GatedOnTarget(prerequisite_id: PrerequisiteId(5)),
    )
  let #(_, effects) = press(spell: holder(forced_moves: [gated], modifiers: []))
  assert listed(effects:) == []
    as "a row behind a target prerequisite is not applied, as a Fluff effect's is not"
}

// ---- what a forced move starts ----

pub fn a_forced_move_gives_the_caster_no_node_timer_or_property_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    press(spell: holder(forced_moves: [blink_row()], modifiers: []))
  assert support.started_timers(effects:) == []
    as "the client moves itself and the row has no duration: nothing for the server to time"
  assert list.length(support.finished_ids(support.writes(effects:))) == 1
    as "no effect has a life, so no node, and the cast finishes with its go"
  assert list.all(effects, fn(effect) { !changes_a_property(effect:) })
    as "a forced move changes no property"
}

// ---- the rolls ----

pub fn a_forced_move_behind_a_type_37_gate_takes_one_roll_and_is_listed_when_it_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let chance = prerequisite_support.single(id: 4585, condition: #(37, 6, 0, 50))
  let gated =
    spell_plan.ForcedMove(
      ..blink_row(),
      condition: spell_plan.GatedOnCaster(gates: [chance]),
    )
  let spell = holder(forced_moves: [gated], modifiers: [])
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_with(spell:),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
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
        | cast.Gain(..)
        | cast.CasterChangeStarts(..)
        | cast.CasterChangeEnds(..)
        | cast.TargetChangeStarts(..)
        | cast.TargetChangeEnds(..)
        | cast.StealthChanged(..) -> Error(Nil)
      }
    })
  assert cast.rolls_needed(
      cast: state,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: [],
    )
    == 1
    as "Prerequisite 4585 is type 37: the go draws one roll for the row's gate"
  let went = fn(roll) {
    let #(_, effects) =
      support.answered_as(
        caster: support.caster(),
        state:,
        effects: raw,
        at: 1000,
        struck: [],
        rolls: [roll],
      )
    listed(effects:)
  }
  assert went(50) == [#(7, [#(67_776, 200)])]
    as "a roll of 50 passes comparison 6 on 50"
  assert went(51) == [] as "a roll of 51 fails and the row is not applied"
}
