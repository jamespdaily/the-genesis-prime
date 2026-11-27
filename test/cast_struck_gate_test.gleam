//// A go row aimed past the caster behind a target apply prerequisite that reads the struck
//// creature's own state (`spell_plan.StruckGate`) is applied on a unit only when that unit's
//// answer says it passed the gate: the strike round (`genesis_prime/game/strike`) tells each
//// unit its aim names the gate, closes on the answers, and the go (`genesis_prime/game/cast`
//// `went`) lists and starts the row on the units that passed it. Each test runs the two rules
//// back to back with hand-written answers, as the connection does; the creature's own check
//// is the creature side's (`genesis_prime/world_map/creature`). Expected values come from
//// these places.
//// - `Spell4Effects.prerequisiteIdTargetApply`: a row lands only on the units that pass its
////   target apply prerequisite, so a unit that did not pass it has no effect of the row in
////   its entry of the go, and a row with no such prerequisite lands on every unit its aim names.
//// - `Spell4Effects.targetFlags`: bit 2 names the primary target, bit 4 the units the round
////   hit, bit 1 the caster; the go's entry for a unit is built from the rows whose flags name it.
//// - The strike round's rule (`genesis_prime/game/strike` module docs): a go's round is told to
////   every unit a row of the phase names, waits for their answers up to the deadline of 1,000
////   ms after the go, and leaves out a unit that refused or never answered. A gate takes no
////   random bytes: the creature's subject holds none, so a round of gates alone takes the 12
////   bytes of each unit and nothing more.

import cast_struck_support
import cast_support as support
import fixture_tables
import genesis_prime/game/cast
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/strike
import genesis_prime/game/strike_tell.{Answered, Landed, Refused}
import genesis_prime/shared/lasting.{LastingRow}
import genesis_prime/shared/lasts
import genesis_prime/shared/spell_plan.{
  type Spell, AimsAtArea, AimsAtPrimaryTarget,
}
import genesis_prime/shared/spend
import genesis_prime/shared/unit_properties

import genesis_prime/table/id.{Spell4EffectsId, UnitProperty2Id}
import gleam/dict
import gleam/list
import gleam/option.{None}
import owned_test
import rating_support
import strike_support

/// The effect ids each unit's entry of the go lists, by unit, in unit order; a struck unit
/// is an entry of the go whatever the rows do, so a unit that lists no effect is left out.
fn listed(effects effects: List(cast_state.Effect)) -> List(#(Int, List(Int))) {
  list.filter(support.listed_by_unit(effects:), fn(entry) { entry.1 != [] })
}

fn answer(
  state state: strike.State,
  asked asked: cast_state.GoAsked,
  unit_id unit_id: Int,
  outcome outcome: strike_tell.Outcome,
) -> #(strike.State, List(strike.Effect)) {
  strike.answered(
    strike: state,
    answer: Answered(
      key: strike_tell.Key(
        cast_id: asked.cast_id,
        occasion: strike_tell.AtGo(phase: asked.phase),
        unit_id:,
      ),
      outcome:,
    ),
    now: cast_struck_support.at(ms: 1100),
  )
}

fn passed(ids ids: List(Int)) -> strike_tell.Outcome {
  Landed(descriptions: [], controls: [], armor_removed: 0, gates_passed: ids)
}

/// The units each strike told, with the effect ids of the gates it carries.
fn gates_told(effects effects: List(strike.Effect)) -> List(#(Int, List(Int))) {
  list.map(strike_support.creatures_told(effects:), fn(told) {
    let #(unit_id, _life, strike_tell.Strike(gates:, ..)) = told
    #(unit_id, list.map(gates, fn(gate: strike_tell.Gate) { gate.effect_id }))
  })
}

/// What the round that closed in these effects tells the go: the units it struck and the
/// effect ids each passed.
fn closed(
  effects effects: List(strike.Effect),
) -> Result(#(List(cast_state.Struck), dict.Dict(Int, List(Int))), Nil) {
  list.first(
    list.map(strike_support.rounds_closed(effects:), fn(closed) {
      #(closed.1, closed.2)
    }),
  )
}

/// What the cast rule does for a round that closed so.
fn went_effects(
  state state: cast_state.State,
  asked asked: cast_state.GoAsked,
  round round: #(List(cast_state.Struck), dict.Dict(Int, List(Int))),
) -> List(cast_state.Effect) {
  let #(_, effects) =
    cast.went(
      cast: state,
      caster: support.caster(),
      now: cast_struck_support.at(ms: 1100),
      cast_id: asked.cast_id,
      phase: asked.phase,
      spell: Error(Nil),
      struck: round.0,
      gates_passed: round.1,
      poses: dict.new(),
      indexes: dict.new(),
      units: dict.new(),
      rolls: [],
      fired: False,
    )
  effects
}

/// The go the cast rule writes for a round that closed so.
fn written(
  state state: cast_state.State,
  asked asked: cast_state.GoAsked,
  round round: #(List(cast_state.Struck), dict.Dict(Int, List(Int))),
) -> List(#(Int, List(Int))) {
  listed(effects: went_effects(state:, asked:, round:))
}

// ---- rows applied at the go ----

pub fn go_row_on_a_struck_creature_waits_for_its_answer_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = cast_struck_support.spell_gated_at(gated_aim: AimsAtArea)
  let #(cast, asked) = cast_struck_support.pressed(spell:, target: 20)
  let selection =
    cast_struck_support.selection_of(spell:, asked:, units: [20, 21])
  assert strike.entropy_needed(selection:) == 2 * 12
    as "a round of gates alone takes the 12 bytes of each unit and no roll"
  let #(state, effects) = cast_struck_support.begun(selection:)
  assert gates_told(effects:)
    == [
      #(20, [cast_struck_support.gated_id]),
      #(21, [cast_struck_support.gated_id]),
    ]
    as "no blow and no state, yet each unit the row's aim names is told the strike with the row's gate"
  assert closed(effects:) == Error(Nil)
    as "the go waits for the answers: nothing is written yet"
  let #(state, first) =
    answer(
      state:,
      asked:,
      unit_id: 20,
      outcome: passed(ids: [cast_struck_support.gated_id]),
    )
  assert closed(effects: first) == Error(Nil) as "unit 21 has not answered"
  let #(_, last) =
    answer(
      state:,
      asked:,
      unit_id: 21,
      outcome: passed(ids: [cast_struck_support.gated_id]),
    )
  let assert Ok(round) = closed(effects: last)
    as "the last answer closes the round"
  assert written(state: cast, asked:, round:)
    == [
      #(7, [cast_struck_support.own_id]),
      #(20, [cast_struck_support.gated_id, cast_struck_support.ungated_id]),
      #(21, [cast_struck_support.gated_id, cast_struck_support.ungated_id]),
    ]
    as "both units passed, so the go lists the gated row on both, beside the ungated rows"
}

pub fn go_row_failing_its_gate_is_not_applied_or_listed_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = cast_struck_support.spell_gated_at(gated_aim: AimsAtArea)
  let #(cast, asked) = cast_struck_support.pressed(spell:, target: 20)
  let #(state, _) =
    cast_struck_support.begun(
      selection: cast_struck_support.selection_of(spell:, asked:, units: [
        20,
        21,
      ]),
    )
  // Unit 21 answers that it passed none: it landed the strike, so its entry stays.
  let #(state, _) =
    answer(
      state:,
      asked:,
      unit_id: 20,
      outcome: passed(ids: [cast_struck_support.gated_id]),
    )
  let #(_, last) = answer(state:, asked:, unit_id: 21, outcome: passed(ids: []))
  let assert Ok(round) = closed(effects: last)
  assert dict.to_list(round.1) == [#(20, [cast_struck_support.gated_id])]
    as "the round tells the go only the gate unit 20 passed"
  assert written(state: cast, asked:, round:)
    == [
      #(7, [cast_struck_support.own_id]),
      #(20, [cast_struck_support.gated_id, cast_struck_support.ungated_id]),
      #(21, [cast_struck_support.ungated_id]),
    ]
    as "the gated row is on unit 20 only; unit 21 keeps the rows with no gate"
}

pub fn go_row_round_past_its_deadline_drops_gated_rows_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = cast_struck_support.spell_gated_at(gated_aim: AimsAtArea)
  let #(cast, asked) = cast_struck_support.pressed(spell:, target: 20)
  let #(state, _) =
    cast_struck_support.begun(
      selection: cast_struck_support.selection_of(spell:, asked:, units: [
        20,
        21,
      ]),
    )
  let #(state, _) =
    answer(
      state:,
      asked:,
      unit_id: 20,
      outcome: passed(ids: [cast_struck_support.gated_id]),
    )
  // Unit 21 never answers (killed or restarted): the strike timer set at the go fires at
  // its deadline, 1,000 ms on, and the round closes without it.
  let #(_, early) =
    strike.timer_fired(strike: state, now: cast_struck_support.at(ms: 1999))
  assert closed(effects: early) == Error(Nil)
    as "before the deadline the round is still open"
  let #(_, due) =
    strike.timer_fired(strike: state, now: cast_struck_support.at(ms: 2000))
  let assert Ok(round) = closed(effects: due)
    as "at the deadline the round closes"
  assert written(state: cast, asked:, round:)
    == [
      #(7, [cast_struck_support.own_id]),
      #(20, [cast_struck_support.gated_id, cast_struck_support.ungated_id]),
    ]
    as "the go is written without unit 21, which never answered, and the caster's own row and unit 20's rows go on"
}

pub fn ungated_go_rows_send_no_strike_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = cast_struck_support.spell_ungated()
  let #(cast, asked) = cast_struck_support.pressed(spell:, target: 20)
  let selection =
    cast_struck_support.selection_of(spell:, asked:, units: [20, 21])
  assert strike.entropy_needed(selection:) == 0
    as "a phase of rows with no gate, no blow and no state draws nothing"
  let #(_, effects) = cast_struck_support.begun(selection:)
  assert gates_told(effects:) == [] as "no unit is told a strike"
  let assert Ok(round) = closed(effects:)
    as "the round closes at once, with no timer to wait for"
  assert written(state: cast, asked:, round:)
    == [
      #(7, [cast_struck_support.own_id]),
      #(20, [cast_struck_support.gated_id, cast_struck_support.ungated_id]),
      #(21, [cast_struck_support.gated_id, cast_struck_support.ungated_id]),
    ]
    as "the go lists every row on every unit its aim names, as it did before"
}

// ---- a gated row aimed at the caster and the area ----

/// A hostile UnitPropertyModifier aimed at the caster and the area (targetFlags 5): the plan
/// holds it as two entries of one effect id, a `PropertyChange` on the caster and a
/// `StruckChange` on the area (`spell_plan.ReadEffects`), and the strike carries the gate of
/// the struck part alone.
fn split_modifier_spell() -> Spell {
  let modifier =
    unit_properties.Change(
      property: UnitProperty2Id(100),
      mode: 2,
      multiplier: 0.5,
      flat: 0.0,
      per_level: 0.0,
    )
  let row = fn(change) {
    spell_plan.PropertyModifier(
      effect_id: Spell4EffectsId(cast_struck_support.gated_id),
      phase_flags: -1,
      change:,
      row: LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 5000)),
      condition: spell_plan.Always,
      tag: spend.always,
      armor: None,
    )
  }
  support.with_effects(
    spell: spell_plan.Spell(
      ..support.child(spell4_id: 101, base: 3),
      struck_gates: [
        cast_struck_support.gate_of(
          id: cast_struck_support.gated_id,
          aim: AimsAtArea,
        ),
      ],
    ),
    kinds: [
      spell_plan.ModifierEffect(row(spell_plan.PropertyChange(modifier:))),
      spell_plan.ModifierEffect(
        row(spell_plan.StruckChange(modifier:, aim: AimsAtArea)),
      ),
    ],
  )
}

pub fn split_gated_modifier_keeps_its_caster_half_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = split_modifier_spell()
  let #(cast, asked) = cast_struck_support.pressed(spell:, target: 20)
  let answers = [
    #("passed the gate", passed(ids: [cast_struck_support.gated_id])),
    #("failed the gate", passed(ids: [])),
    #("refused", Refused(why: strike_tell.Dead)),
  ]
  list.each(answers, fn(answered) {
    let #(state, _) =
      cast_struck_support.begun(
        selection: cast_struck_support.selection_of(spell:, asked:, units: [20]),
      )
    let #(_, last) = answer(state:, asked:, unit_id: 20, outcome: answered.1)
    let assert Ok(round) = closed(effects: last)
    let effects = went_effects(state: cast, asked:, round:)
    assert list.map(support.property_starts(effects:), fn(start) { start.0 })
      == [
        support.source_of(
          cast_id: asked.cast_id,
          effect_id: cast_struck_support.gated_id,
        ),
      ]
      as {
        "the caster's own half is its modifier whatever unit 20 answered: "
        <> answered.0
      }
    assert list.length(support.target_changes(effects:))
      == case answered.0 {
        "passed the gate" -> 1
        _ -> 0
      }
      as {
        "the struck half starts on unit 20 only when it passed the gate: "
        <> answered.0
      }
  })
}

pub fn struck_move_failing_its_gate_is_not_thrown_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 29856 (`table_rows -- Spell4Effects spellId=29856`): its ForcedMove row 53184 has
  // targetFlags 4 (the area), phaseFlags 1, delayTime 0 and target apply 6802, which is one
  // condition of type 4 (comparison 2, value 174; `table_rows -- Prerequisite 6802`): a
  // faction the creature itself holds, so the creature checks it and the plan keeps the row.
  let tables = fixture_tables.shared()
  let assert Ok(planned) =
    spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id: 29_856,
      chain: [],
    )
    as "a ForcedMove row behind a faction gate the creature holds plans"
  let assert [thrown_row] =
    spell_plan.payloads(spell: planned, as_kind: spell_plan.as_struck_move)
  assert thrown_row.effect_id == Spell4EffectsId(53_184)
    as "Spell4Effects.53184 is the spell's one ForcedMove row"
  assert list.map(planned.struck_gates, fn(gate) { gate.effect_id })
    == [Spell4EffectsId(53_184)]
    as "the strike tells the creature the move's gate"
  let spell =
    support.with_effects(
      spell: spell_plan.Spell(
        ..support.child(spell4_id: 101, base: 3),
        struck_gates: planned.struck_gates,
      ),
      kinds: list.map(
        spell_plan.payloads(spell: planned, as_kind: spell_plan.as_struck_move),
        spell_plan.StruckMoveEffect,
      ),
    )
  let #(cast, asked) = cast_struck_support.pressed(spell:, target: 20)
  let #(state, _) =
    cast_struck_support.begun(
      selection: cast_struck_support.selection_of(spell:, asked:, units: [
        20,
        21,
      ]),
    )
  let #(state, _) =
    answer(state:, asked:, unit_id: 20, outcome: passed(ids: [53_184]))
  let #(_, last) = answer(state:, asked:, unit_id: 21, outcome: passed(ids: []))
  let assert Ok(round) = closed(effects: last)
  let thrown_units =
    list.map(
      support.throws(effects: went_effects(state: cast, asked:, round:)),
      fn(effect) {
        let assert cast_state.ForcedMoveStarts(unit_id:, ..) = effect
          as "throws lists only throws"
        unit_id
      },
    )
  assert thrown_units == [20]
    as "Spell4Effects.prerequisiteIdTargetApply: unit 20 passed the gate and is thrown; unit 21 failed it and stays"
}

// ---- a gated row aimed at the primary target ----

/// The go the primary target's round leaves for a spell whose gated row is aimed at the
/// primary target, unit 20, when the unit answers as given (`None`: never). A press has the
/// caster as its own primary target, so the spell is the child a Proxy starts on the
/// creature 20 its parent struck.
fn primary_target_go(
  answer_of answer_of: option.Option(strike_tell.Outcome),
  at_ms at_ms: Int,
) -> List(#(Int, List(Int))) {
  let spell = cast_struck_support.spell_gated_at(gated_aim: AimsAtPrimaryTarget)
  let #(pressed, raw) =
    support.pressed_raw_in(
      plans: support.plans_starting_on_each_struck(started: spell),
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: cast_struck_support.bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let assert [parent_asked] = support.goes_asked(effects: raw)
  let #(cast, started) =
    cast.went(
      cast: pressed,
      caster: support.caster(),
      now: cast_struck_support.at(ms: 1000),
      cast_id: parent_asked.cast_id,
      phase: parent_asked.phase,
      spell: Error(Nil),
      struck: support.hits([20]),
      gates_passed: dict.new(),
      poses: dict.new(),
      indexes: dict.new(),
      units: dict.new(),
      rolls: [],
      fired: False,
    )
  let assert [asked] = support.goes_asked(effects: started)
    as "the parent's go starts the child, which asks for its own go"
  assert asked.primary_target == 20
    as "the child's primary target is the creature the parent struck"
  let #(state, effects) =
    cast_struck_support.begun(
      selection: cast_struck_support.selection_of(spell:, asked:, units: [20]),
    )
  assert gates_told(effects:) == [#(20, [cast_struck_support.gated_id])]
    as "the primary target is told the gate of the row aimed at it"
  let #(_, last) = case answer_of {
    option.Some(outcome) -> answer(state:, asked:, unit_id: 20, outcome:)
    None ->
      strike.timer_fired(strike: state, now: cast_struck_support.at(ms: at_ms))
  }
  let assert Ok(round) = closed(effects: last)
  written(state: cast, asked:, round:)
}

pub fn gated_primary_target_row_applies_on_a_deflect_that_passed_it_test() -> Nil {
  use <- owned_test.run(5000)
  assert primary_target_go(
      answer_of: option.Some(
        strike_tell.Deflected(gates_passed: [cast_struck_support.gated_id]),
      ),
      at_ms: 0,
    )
    == [
      #(7, [cast_struck_support.own_id]),
      #(20, [cast_struck_support.gated_id]),
    ]
    as "the creature deflected the strike but passed the gate, so the row reaches the primary target that no hit names, as an ungated row would"
  assert primary_target_go(
      answer_of: option.Some(strike_tell.Deflected(gates_passed: [])),
      at_ms: 0,
    )
    == [#(7, [cast_struck_support.own_id])]
    as "a deflect that failed the gate applies nothing of the row"
}

pub fn gated_primary_target_row_is_not_applied_on_a_refusal_test() -> Nil {
  use <- owned_test.run(5000)
  assert primary_target_go(
      answer_of: option.Some(Refused(why: strike_tell.Dead)),
      at_ms: 0,
    )
    == [#(7, [cast_struck_support.own_id])]
    as "the creature died after the picture was taken and read no gate: the row, which reaches the primary target whatever the round did, is not applied"
}

pub fn gated_primary_target_row_is_not_applied_when_no_answer_comes_test() -> Nil {
  use <- owned_test.run(5000)
  assert primary_target_go(answer_of: None, at_ms: 2000)
    == [#(7, [cast_struck_support.own_id])]
    as "no answer by the deadline passes no gate: the row is not applied"
}

// ---- the round's failure rows ----

pub fn two_gos_of_one_cast_are_two_rounds_each_with_its_own_gates_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = cast_struck_support.spell_gated_at(gated_aim: AimsAtArea)
  let #(_, asked) = cast_struck_support.pressed(spell:, target: 20)
  let second = cast_state.GoAsked(..asked, phase: 1)
  let #(state, _) =
    cast_struck_support.begun(
      selection: cast_struck_support.selection_of(spell:, asked:, units: [20]),
    )
  let #(state, effects) =
    strike.begin(
      strike: state,
      selection: cast_struck_support.selection_of(spell:, asked: second, units: [
        20,
      ]),
      attacker: strike_support.attacker(),
      formulas: rating_support.formulas(),
      entropy: <<0:size(96)>>,
      gate: cast_tick.strike_gate(
        cast: cast_state.new(),
        caster: support.caster(),
        poses: dict.new(),
        indexes: dict.new(),
        units: dict.new(),
      ),
      now: cast_struck_support.at(ms: 1000),
    )
  assert gates_told(effects:) == [#(20, [cast_struck_support.gated_id])]
    as "the second go tells the unit its own strike"
  // The second go's answer passes the gate; the first go's has not come.
  let #(state, after_second) =
    answer(
      state:,
      asked: second,
      unit_id: 20,
      outcome: passed(ids: [cast_struck_support.gated_id]),
    )
  assert closed(effects: after_second) == Error(Nil)
    as "the second round waits behind the first, which is still open for its unit"
  let #(_, after_first) =
    answer(state:, asked:, unit_id: 20, outcome: passed(ids: []))
  let went =
    list.map(strike_support.rounds_closed(effects: after_first), fn(closed) {
      #({ closed.0 }.phase, dict.to_list(closed.2))
    })
  assert went == [#(0, []), #(1, [#(20, [cast_struck_support.gated_id])])]
    as "the first go closes in its turn with the gates its own answer passed (none), then the second with its own"
}

pub fn an_answer_after_the_round_closed_is_dropped_with_its_passed_gates_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = cast_struck_support.spell_gated_at(gated_aim: AimsAtArea)
  let #(_, asked) = cast_struck_support.pressed(spell:, target: 20)
  let #(state, _) =
    cast_struck_support.begun(
      selection: cast_struck_support.selection_of(spell:, asked:, units: [20]),
    )
  let #(state, due) =
    strike.timer_fired(strike: state, now: cast_struck_support.at(ms: 2000))
  let assert Ok(round) = closed(effects: due)
  assert dict.is_empty(round.1) as "the round closed with no gate passed"
  let #(_, late) =
    answer(
      state:,
      asked:,
      unit_id: 20,
      outcome: passed(ids: [cast_struck_support.gated_id]),
    )
  assert late == []
    as "the late answer changes nothing and writes nothing: its passed gate is dropped with it"
}

pub fn a_caster_that_leaves_with_a_gated_round_open_writes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let spell = cast_struck_support.spell_gated_at(gated_aim: AimsAtArea)
  let #(_, asked) = cast_struck_support.pressed(spell:, target: 20)
  let #(state, _) =
    cast_struck_support.begun(
      selection: cast_struck_support.selection_of(spell:, asked:, units: [20]),
    )
  let #(state, leaving) = strike.left(strike: state)
  assert closed(effects: leaving) == Error(Nil)
    as "the connection ended: no go is written"
  assert leaving == [strike.CancelTimer(timer: strike.strike_timer)]
    as "the only effect is the cancelled deadline timer"
  let #(_, late) =
    answer(
      state:,
      asked:,
      unit_id: 20,
      outcome: passed(ids: [cast_struck_support.gated_id]),
    )
  assert late == [] as "an answer that still arrives finds no round"
}
