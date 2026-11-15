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
//// - `Spell4Effects.effectType.3.other_unit`: a row aimed at the units a strike hits throws
////   each creature the go hit, at the go plus the row's delayTime; its columns are 73826's
////   (kind 4, 10.0 m, 375 ms, flags 1, apex 2.0, `table_rows -- Spell4Effects 73826`).
//// - `Spell4Effects.prerequisiteIdTargetApply` and `Prerequisite.prerequisiteTypeId.38`: a throw
////   row behind a target gate moves only the creatures that pass it (Prerequisite 20210's
////   shape: comparison 1 passes the unit that is the creature of its row).
//// - The server's choices, in the cast rule's doc: a throw's start is a timer of the
////   cast's node on the creature, so the node's end cancels one still waiting.

import cast_support as support
import genesis_prime/game/cast.{type State}
import genesis_prime/game/forced_move
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Spell, Always}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{Change}
import genesis_prime/message/spell_go
import genesis_prime/table/id.{Spell4EffectsId, UnitProperty2Id}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None}
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
    | cast.TickStrike(..)
    | cast.Pay(..)
    | cast.TargetChangeStarts(..)
    | cast.TargetChangeEnds(..)
    | cast.ForcedMoveStarts(..)
    | cast.Activated(..)
    | cast.ShortcutCast(..)
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
      condition: spell_plan.GatedOnTarget(
        prerequisite: prerequisite_support.single(id: 5, condition: #(
          38,
          1,
          0,
          5,
        )),
      ),
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
        | cast.ForcedMoveStarts(..)
        | cast.Activated(..)
        | cast.ShortcutCast(..)
        | cast.TickStrike(..)
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

// ---- the creatures a go throws ----

/// The move of Spell4Effects 73826: kind 4 (away from a unit), 10.0 m, 375 ms, flags 1,
/// apex 2.0.
fn knockback() -> forced_move.Move {
  forced_move.Move(
    way: forced_move.Away,
    mover: forced_move.Flight,
    min_distance: 10.0,
    max_distance: 10.0,
    flight_ms: 375,
    gravity: 0.0,
    flags: 1,
    height: 2.0,
  )
}

/// A row of that move aimed at the units the go hit, with its delay.
fn throwing_row(delay_ms delay_ms: Int) -> spell_plan.StruckMove {
  spell_plan.StruckMove(
    effect_id: Spell4EffectsId(73_826),
    phase_flags: 1,
    delay_ms:,
    move: knockback(),
    aim: spell_plan.AimsAtArea,
    condition: Always,
    tag: spend.always,
  )
}

/// A creature the round hit in `life` at the monotonic time 1000.
fn hit(unit_id unit_id: Int, life life: Int) -> cast.Struck {
  cast.Hit(
    unit_id:,
    unit: cast.HitCreature(life:, struck_at_ms: 1000),
    descriptions: [],
    controls: [],
    armor_removed: 0,
    ticking: [],
  )
}

/// The effects of the press and of the go that the round `struck` answers.
fn thrown_by(
  spell spell: Spell,
  struck struck: List(cast.Struck),
) -> #(State, List(cast.Effect)) {
  let #(state, effects) =
    support.pressed_raw_in(
      plans: support.plans_with(spell:),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let #(state, answered) =
    support.answered_by(state:, effects:, at: 1000, struck:)
  #(state, list.append(effects, answered))
}

fn thrower(rows rows: List(spell_plan.StruckMove)) -> Spell {
  spell_plan.Spell(
    ..support.child(spell4_id: 34_355, base: 3),
    struck_moves: rows,
  )
}

fn thrown(unit_id: Int, life: Int) -> cast.Effect {
  cast.ForcedMoveStarts(unit_id:, life:, struck_at_ms: 1000, move: knockback())
}

pub fn a_go_tells_each_hit_creature_its_throw_in_the_same_step_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    thrown_by(spell: thrower(rows: [throwing_row(delay_ms: 0)]), struck: [
      hit(unit_id: 21, life: 3),
      hit(unit_id: 23, life: 5),
    ])
  assert support.throws(effects:) == [thrown(21, 3), thrown(23, 5)]
    as "each creature the go hit is thrown in the lives the go struck, at the go's own time 1000, in the order the go hit them"
}

pub fn a_delayed_throw_is_told_at_the_go_plus_its_delay_test() -> Nil {
  use <- owned_test.run(5000)
  let creatures = [hit(unit_id: 21, life: 3)]
  let #(state, effects) =
    thrown_by(
      spell: thrower(rows: [throwing_row(delay_ms: 200)]),
      struck: creatures,
    )
  assert support.throws(effects:) == []
    as "the row waits its delayTime of 200 ms: nothing is told at the go"
  let #(_, fired) =
    support.run_timers_striking(
      state:,
      effects:,
      from_ms: 1000,
      struck: creatures,
    )
  assert support.throw_timeline(fired:) == [#(1200, thrown(21, 3))]
    as "the throw is told at go 1000 + 200, still for the strike time 1000 of the hit"
}

pub fn a_deflected_creature_is_not_thrown_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    thrown_by(spell: thrower(rows: [throwing_row(delay_ms: 0)]), struck: [
      cast.Deflected(unit_id: 21),
      hit(unit_id: 23, life: 5),
    ])
  assert support.throws(effects:) == [thrown(23, 5)]
    as "opcode.0x7fb: the creature that deflected the strike took no effect of it; only the one the go hit is thrown"
}

pub fn a_delayed_throw_is_cancelled_with_its_cast_node_test() -> Nil {
  use <- owned_test.run(5000)
  // A lasting row of 5000 ms on the same creature gives the cast a node there that ends
  // at 6000 (`Spell4Effects.effectType.17`).
  let lasting_row =
    spell_plan.PropertyModifier(
      effect_id: Spell4EffectsId(7711),
      phase_flags: 1,
      change: spell_plan.StruckChange(
        modifier: Change(
          property: UnitProperty2Id(100),
          mode: 2,
          multiplier: 0.5,
          flat: 0.0,
          per_level: 0.0,
        ),
        aim: spell_plan.AimsAtArea,
      ),
      row: LastingRow(delay_ms: 0, duration_ms: 5000, until_removed: False),
      condition: Always,
      tag: spend.always,
      armor: None,
    )
  let creatures = [hit(unit_id: 21, life: 3)]
  let holding = fn(delay_ms) {
    spell_plan.Spell(..thrower(rows: [throwing_row(delay_ms:)]), modifiers: [
      lasting_row,
    ])
  }
  let #(state, effects) = thrown_by(spell: holding(7000), struck: creatures)
  let #(_, fired) =
    support.run_timers_striking(
      state:,
      effects:,
      from_ms: 1000,
      struck: creatures,
    )
  assert support.throw_timeline(fired:) == []
    as "the node ends at 6000, before the throw's start at 8000, and takes its timer with it"
  let #(state, effects) = thrown_by(spell: holding(4000), struck: creatures)
  let #(_, fired) =
    support.run_timers_striking(
      state:,
      effects:,
      from_ms: 1000,
      struck: creatures,
    )
  assert support.throw_timeline(fired:) == [#(5000, thrown(21, 3))]
    as "and a throw that starts before the node ends, at 1000 + 4000, is told"
}

// ---- what the go lists and rolls for a throw ----

pub fn a_go_lists_each_throw_on_the_creature_it_throws_with_its_delay_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, effects) =
    thrown_by(spell: thrower(rows: [throwing_row(delay_ms: 200)]), struck: [
      cast.Deflected(unit_id: 21),
      hit(unit_id: 23, life: 5),
    ])
  assert listed(effects:) == [#(23, [#(73_826, 200)])]
    as "Spell4Effects.effectType.3.other_unit: the go lists the ForcedMove row with its delay of 200 ms on the creature it throws, 23, and on none that deflected the strike"
}

/// The throw row of 73826 behind the chance gate of Prerequisite 792 on the caster
/// (`table_rows -- Prerequisite 792`: type 37, comparison 6, value 24).
fn chance_throw() -> Spell {
  thrower(rows: [
    spell_plan.StruckMove(
      ..throwing_row(delay_ms: 0),
      condition: spell_plan.GatedOnCaster(gates: [
        prerequisite_support.single(id: 792, condition: #(37, 6, 0, 24)),
      ]),
    ),
  ])
}

pub fn a_throw_behind_a_type_37_gate_takes_one_roll_and_is_thrown_when_it_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let creatures = [hit(unit_id: 21, life: 3)]
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_with(spell: chance_throw()),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let assert [asked] = support.goes_asked(effects: raw)
  assert cast.rolls_needed(
      cast: state,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck: creatures,
    )
    == 1
    as "Prerequisite 792 is type 37: the go draws one roll for the throw row's gate, as for every other row"
  let went = fn(roll) {
    let #(_, effects) =
      support.answered_as(
        caster: support.caster(),
        state:,
        effects: raw,
        at: 1000,
        struck: creatures,
        rolls: [roll],
      )
    support.throws(effects:)
  }
  assert went(24) == [thrown(21, 3)] as "a roll of 24 passes comparison 6 on 24"
  assert went(25) == [] as "a roll of 25 fails and the creature is not thrown"
}

pub fn each_go_of_a_cast_keeps_the_delayed_throw_it_armed_test() -> Nil {
  use <- owned_test.run(5000)
  // Phase flags 3: the row applies in both gos, at 1000 and 1300; its delay of 500 ms
  // outlasts the second go, so the first go's throw is still waiting when the second
  // go arms its own.
  let row = spell_plan.StruckMove(..throwing_row(delay_ms: 500), phase_flags: 3)
  let spell =
    spell_plan.Spell(..thrower(rows: [row]), phase_delays_ms: [0, 300])
  let creatures = [hit(unit_id: 21, life: 3)]
  let #(state, effects) = thrown_by(spell:, struck: creatures)
  let #(_, fired) =
    support.run_timers_striking(
      state:,
      effects:,
      from_ms: 1000,
      struck: creatures,
    )
  assert list.map(support.throw_timeline(fired:), fn(entry) { entry.0 })
    == [1500, 1800]
    as "the first go's throw starts at 1000 + 500 and the second go's at 1300 + 500: a later go does not cancel an earlier throw that waits"
}

pub fn a_throw_behind_a_type_37_target_gate_takes_one_roll_for_each_creature_it_reaches_test() -> Nil {
  use <- owned_test.run(5000)
  // Prerequisite.prerequisiteTypeId.37: a target gate's test draws a roll for each unit the
  // row reaches, in unit order; comparison 6 on 24 passes a roll of 24 (as for the caster
  // gate above).
  let spell =
    thrower(rows: [
      spell_plan.StruckMove(
        ..throwing_row(delay_ms: 0),
        condition: spell_plan.GatedOnTarget(
          prerequisite: prerequisite_support.single(id: 792, condition: #(
            37,
            6,
            0,
            24,
          )),
        ),
      ),
    ])
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_with(spell:),
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1000,
    )
  let assert [asked] = support.goes_asked(effects: raw)
  let rolls_for = fn(struck) {
    cast.rolls_needed(
      cast: state,
      cast_id: asked.cast_id,
      phase: asked.phase,
      struck:,
    )
  }
  assert rolls_for([hit(unit_id: 21, life: 3)]) == 1
    as "one creature struck: one roll for the target gate"
  let struck = [hit(unit_id: 21, life: 3), hit(unit_id: 23, life: 5)]
  assert rolls_for(struck) == 2
    as "two creatures struck: the gate is tested for each, a roll of its own for each"
  let #(_, answered) =
    support.answered_known(
      caster: support.caster(),
      state:,
      effects: raw,
      at: 1000,
      struck_of: fn(_) { struck },
      rolls: [24, 25],
      poses: dict.new(),
      units: dict.from_list([
        #(21, prerequisite.NonPlayer(1)),
        #(23, prerequisite.NonPlayer(1)),
      ]),
    )
  assert support.throws(effects: answered) == [thrown(21, 3)]
    as "unit 21 takes the roll of 24 and passes, unit 23 takes 25 and fails: only 21 is thrown"
}

/// A type 38 target gate of Prerequisite 20210's shape (`table_rows -- Prerequisite 20210`):
/// comparison 1 on Creature2 row 48404, which passes the unit that is that creature.
fn named_creature_gate() -> spell_plan.Condition {
  spell_plan.GatedOnTarget(
    prerequisite: prerequisite_support.single(id: 20_210, condition: #(
      38,
      1,
      0,
      48_404,
    )),
  )
}

pub fn forced_move_past_the_caster_behind_a_target_gate_moves_only_passing_units_test() -> Nil {
  use <- owned_test.run(5000)
  // Prerequisite.prerequisiteTypeId.38: unit 23 is the creature the gate names and unit 21
  // is not, so only 23 is thrown and only 23 is listed with the row.
  let spell =
    thrower(rows: [
      spell_plan.StruckMove(
        ..throwing_row(delay_ms: 0),
        condition: named_creature_gate(),
      ),
    ])
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_with(spell:),
      state: cast.new(),
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
  assert support.throws(effects: answered) == [thrown(23, 5)]
    as "the creature 23 passes the gate and is thrown in the life the go struck; creature 21 fails it and stays"
  assert listed(effects: answered) == [#(21, []), #(23, [#(73_826, 0)])]
    as "the go names both struck units and lists the row on the creature it throws only"
}
