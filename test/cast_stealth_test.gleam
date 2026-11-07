//// The cast rule's stealth (`genesis_prime/game/cast` `State.stealth`, `stealthed`,
//// `damage_taken`, `StealthChanged`). The Stalker's toggle is the client's rows of
//// 46073, 38784 and 38783 (`spell_tables.fixture_plans`);
//// every other spell is planted by hand (`cast_support.child` with a Stealth row), on a
//// clock the test drives. Expected values come from these places:
//// - `Spell4.46073`: a press of the toggle proxies 38784 'Stealth - On' when the caster
////   is not stealthed (Prerequisite 7050, type 116 comparison 2) and 38783 'Stealth -
////   Cancel' when it is (8127, comparison 1); 38783 force-removes 38784, which ends the
////   stealth; 38784's cooldown effect 159128 clears the toggle's cooldown out of combat.
//// - `Spell4Effects.effectType.83`: a Stealth effect holds the stealth until it is
////   removed (no durationTime; the plan reads no flags); dataBits02 1 means damage does
////   not end it, 0 means it does.
//// - `Spell4.spellCastStealthChange.break`: a spell of value 1 ends the stealth after the
////   effects of its last go, so gates on the caster being stealthed in any of its goes see
////   it (Impale's phase 1 Proxies); value 0 ends it after the effects of a go; value 2
////   ends nothing. The column is read nowhere by the client, so this is the server's rule,
////   and so is a cast that stops after one of its goes and before its last ending it as it
////   stops, while one that stops before its first go leaves it held.
//// - `opcode.0x811`: a cast whose last node leaves a unit is destroyed by the client when
////   its cast method is Normal, so the end of a Normal cast's node is the 0x811 alone;
////   `cast.target_node_end`: a 0x7fe destroys every node of a cast, and the client
////   handles no death, so a death's 0x7fe ends the nodes.
//// - The server's choices, in the rule's doc: the stealth is settled once for each input
////   and `StealthChanged` is its last effect; the stealth sources of a cast leave with the
////   cast's node; a camp writes nothing.

import cast_support as support
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, Always, BrokenByDamage, EndsStealthAfterLastGo,
  EndsStealthAtEachGo, GatedOnCaster, KeepsStealth, KeptOnDamage, Proxy,
  RemoveStealthRow, Spell, StealthRow,
}
import genesis_prime/game/spend
import genesis_prime/message/cast_result
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_target_info
import genesis_prime/step.{type TimerId}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import gleam/list
import owned_test
import prerequisite_support
import spell_tables

// ---- the planted spells and the toggle ----

/// The bag index of the toggle's base 30075, after the planted abilities
/// (`cast_support.abilities` holds 21).
const toggle_bag = 21

/// The bag indices of the planted bases 1, 2 and 3 (`cast_support.abilities`).
const bag_of_base_1 = 8

const bag_of_base_2 = 10

const bag_of_base_3 = 11

fn caster() -> Caster {
  cast.Caster(
    ..support.caster(),
    abilities: list.append(support.abilities(), [Spell4BaseId(30_075)]),
  )
}

/// The plans of the planted Stalker toggle with these spells in place of the planted
/// bases they name.
fn plans_of(spells: List(Spell)) -> Plans {
  support.with_spells(plans: spell_tables.fixture_plans(), spells:)
}

/// A spell with no stealth row whose go does what its value says to the stealth.
fn attack(
  spell4_id spell4_id: Int,
  base base: Int,
  change change: spell_plan.StealthChange,
) -> Spell {
  Spell(..support.child(spell4_id:, base:), stealth_change: change)
}

/// A spell whose go takes the casts of the Spell4 `cancelled` off the caster, as
/// 38783's 83832 does.
fn cancelling(
  spell4_id spell4_id: Int,
  base base: Int,
  of cancelled: Int,
) -> Spell {
  Spell(..support.child(spell4_id:, base:), removes: [
    spell_plan.ForceRemove(
      effect_id: Spell4EffectsId(83_832),
      phase_flags: -1,
      aim: spell_plan.AimsAtCaster,
      selector: lasting.Spell(Spell4Id(cancelled)),
      count: 1,
      condition: Always,
      tag: spend.always,
    ),
  ])
}

/// The spell of base 1: Spell4 38784's Stealth row 83834, broken by damage.
fn broken() -> Spell {
  support.stealthing(spell4_id: 38_784, base: 1, rows: [
    support.stealth_row(id: 83_834, breaks: BrokenByDamage),
  ])
}

/// The spell of base 3: a Stealth row damage does not end, as 95774.
fn kept() -> Spell {
  support.stealthing(spell4_id: 38_913, base: 3, rows: [
    support.stealth_row(id: 95_774, breaks: KeptOnDamage),
  ])
}

// ---- reading what a step did ----

/// What a step wrote and told that matters here, in order: a child cast's start, a go,
/// a cast taken off, a cast's end and the stealth change.
fn trace(effects effects: List(Effect)) -> List(String) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.Send(frame:) ->
        case frame.message_id {
          0x07FF -> Ok("start")
          0x07F4 -> Ok("go")
          0x0811 -> Ok("off")
          0x07FE -> Ok("end")
          _ -> Error(Nil)
        }
      cast.StealthChanged(stealthed: True) -> Ok("stealth on")
      cast.StealthChanged(stealthed: False) -> Ok("stealth off")
      cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Strike(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.CasterChangeStarts(..)
      | cast.CasterChangeEnds(..) -> Error(Nil)
    }
  })
}

/// The `StealthChanged` effects of a step, in order.
fn changes(effects effects: List(Effect)) -> List(Bool) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.StealthChanged(stealthed:) -> Ok(stealthed)
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Strike(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.CasterChangeStarts(..)
      | cast.CasterChangeEnds(..) -> Error(Nil)
    }
  })
}

/// The casts the step started with a 0x7ff, in order, as (Spell4 id, cast id).
fn children_started_with_ids(
  effects effects: List(Effect),
) -> List(#(Int, Int)) {
  list.map(
    support.frames_of(message_id: spell_started.message_id, effects:),
    fn(frame) {
      let assert Ok(decoded) = spell_started.decode(frame.body)
        as "a 0x7ff the rule wrote decodes"
      #(decoded.spell4_id, decoded.cast_id)
    },
  )
}

/// The Spell4 ids of the casts the step started with a 0x7ff, in order.
fn children_started(effects effects: List(Effect)) -> List(Int) {
  list.map(children_started_with_ids(effects:), fn(started) { started.0 })
}

/// The cast id of the child of the Spell4 that the step started.
fn child_of(spell4_id spell4_id: Int, effects effects: List(Effect)) -> Int {
  let assert Ok(started) =
    list.find(children_started_with_ids(effects:), fn(started) {
      started.0 == spell4_id
    })
    as "the step started a cast of the Spell4"
  started.1
}

/// The effect rows a go of the cast lists on the caster, unit 7.
fn listed_on_the_caster(
  cast_id cast_id: Int,
  effects effects: List(Effect),
) -> List(Int) {
  list.flat_map(
    support.frames_of(message_id: spell_go.message_id, effects:),
    fn(frame) {
      let assert Ok(go) = spell_go.decode(frame.body)
        as "a 0x7f4 the rule wrote decodes"
      case go.cast_id == cast_id {
        True -> effect_rows_on_the_caster(targets: go.targets)
        False -> []
      }
    },
  )
}

/// The effect rows a go's target info lists on the caster, unit 7.
fn effect_rows_on_the_caster(
  targets targets: List(spell_target_info.SpellTargetInfo),
) -> List(Int) {
  list.filter(targets, fn(target) { target.unit_id == 7 })
  |> list.flat_map(fn(target) {
    list.map(target.effects, fn(effect) { effect.spell4_effects_id })
  })
}

/// The position of the first line of this text in a trace.
fn first_of(lines lines: List(String), line line: String) -> Int {
  let assert Ok(found) =
    list.index_map(lines, fn(found, index) { #(found, index) })
    |> list.find(fn(entry) { entry.0 == line })
    as "the trace holds the line"
  found.1
}

/// The position of the last line of this text in a trace.
fn last_of(lines lines: List(String), line line: String) -> Int {
  let assert Ok(found) =
    list.index_map(lines, fn(found, index) { #(found, index) })
    |> list.filter(fn(entry) { entry.0 == line })
    |> list.last
    as "the trace holds the line"
  found.1
}

// ---- the toggle ----

/// A press whose goes are each taken as an input of their own, answered as rounds that
/// struck nobody: the state, and the effects of the press and then of each go, in the
/// order the connection takes them. The stealth change ends the input that moved it.
fn press_by_inputs(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(List(Effect))) {
  let #(state, asked) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: caster(),
      bag_index: bag,
      target: 0,
      at: ms,
    )
  let #(state, goes) = goes_apart(state:, effects: asked, at: ms)
  #(state, [asked, ..goes])
}

/// Each go the effects ask for, and each go those ask for, taken as an input of its own.
fn goes_apart(
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
) -> #(State, List(List(Effect))) {
  list.fold(effects, #(state, []), fn(so_far, effect) {
    let #(state, inputs) = so_far
    case effect {
      cast.Strike(asked:) -> {
        let #(state, going) =
          support.went(
            cast: state,
            caster: support.caster(),
            now: support.at(ms:),
            cast_id: asked.cast_id,
            phase: asked.phase,
            struck: [],
          )
        let #(state, later) = goes_apart(state:, effects: going, at: ms)
        #(state, list.append(inputs, [going, ..later]))
      }
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.CasterChangeStarts(..)
      | cast.CasterChangeEnds(..)
      | cast.StealthChanged(..) -> so_far
    }
  })
}

/// A press of the toggle at 1000 ms by a caster that is not stealthed.
fn toggled() -> #(State, List(Effect)) {
  support.press_by(
    caster: caster(),
    plans: plans_of([]),
    state: cast.new(),
    bag: toggle_bag,
    at: 1000,
  )
}

pub fn a_press_of_the_toggle_when_not_stealthed_starts_38784_whose_go_lists_83834_and_holds_the_stealth_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, effects) = toggled()
  assert children_started(effects:) == [38_784]
    as "7050 (type 116, comparison 2) passes and 8127 (comparison 1) fails: only 38784 starts"
  let on = child_of(spell4_id: 38_784, effects:)
  let listed = listed_on_the_caster(cast_id: on, effects:)
  assert list.contains(listed, 83_834)
    as "83834 is the Stealth row 38784 lists on the caster, behind 16152"
  assert !list.contains(listed, 95_774)
    as "95774 is behind 16153, the caster under 59389, which it is not"
  assert list.contains(listed, 159_128)
    as "159128 changes the cooldown of group 182 (behind 390, not in combat)"
  assert cast.stealthed(cast: state) as "the caster holds the stealth"
  assert !list.contains(support.finished_ids(support.writes(effects:)), on)
    as "the stealth's node lasts until removed, so 38784's 0x7fe waits"
  assert support.started_timers(effects:) == []
    as "a node until removed arms no timer (Spell4Effects.effectType.83: no durationTime)"
  assert changes(effects:) == [True] as "one change, to stealthed"
}

pub fn the_stealth_change_is_the_last_effect_of_38784s_go_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(_, inputs) =
    press_by_inputs(
      plans: plans_of([]),
      state: cast.new(),
      bag: toggle_bag,
      at: 1000,
    )
  let assert Ok(last_input) = list.last(inputs)
  let assert [go, change] = trace(effects: last_input)
    as "38784's go writes its 0x7f4 and then the change, and nothing else of the two"
  assert go == "go" && change == "stealth on"
  assert changes(
      effects: list.flatten(list.take(inputs, list.length(inputs) - 1)),
    )
    == []
    as "the press and the toggle's own go move no stealth"
}

pub fn a_press_of_the_toggle_when_stealthed_takes_38784_off_and_ends_the_stealth_after_it_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(state, entered) = toggled()
  let on = child_of(spell4_id: 38_784, effects: entered)
  // The toggle's own cooldown of 25 s would refuse this press, but 159128 cleared it
  // out of combat (Spell4.46073); 4000 ms is past the 1000 ms global cooldown.
  let #(state, inputs) =
    press_by_inputs(plans: plans_of([]), state:, bag: toggle_bag, at: 4000)
  let effects = list.flatten(inputs)
  assert support.refusals(effects:) == []
    as "the press is not refused: the cooldown was cleared by 159128"
  assert children_started(effects:) == [38_783]
    as "8127 passes and 7050 fails: only 38783 starts"
  assert support.removed_targets(support.writes(effects:)) == [#(on, [7])]
    as "38783's 83832 takes 38784 off the caster: 0x811 naming its unit"
  assert !list.contains(support.finished_ids(support.writes(effects:)), on)
    as "and no 0x7fe for 38784: the client destroys a Normal cast whose last node goes (opcode.0x811)"
  assert changes(effects:) == [False]
  let assert Ok(last_input) = list.last(inputs)
  assert list.drop(trace(effects: last_input), 1)
    == ["off", "end", "stealth off"]
    as "38783's go writes its 0x7f4, the 0x811 of 38784, the 0x7fe that ends 38783 itself (it holds no node), and the change is last"
  assert !cast.stealthed(cast: state)
  // A third press enters stealth again; 159130 cleared the cooldown again.
  let #(state, again) =
    support.press_by(
      caster: caster(),
      plans: plans_of([]),
      state:,
      bag: toggle_bag,
      at: 7000,
    )
  assert children_started(effects: again) == [38_784]
  assert changes(effects: again) == [True]
  assert cast.stealthed(cast: state)
}

// ---- a cast ends stealth after its go ----

/// The caster stealthed by a press of the spell of base 1 at 1000 ms, with the other
/// planted spells given.
fn stealthed_by_base_1(
  others others: List(Spell),
) -> #(Plans, State, List(Effect)) {
  let plans = plans_of([broken(), ..others])
  let #(state, effects) =
    support.press_by(
      caster: caster(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_1,
      at: 1000,
    )
  #(plans, state, effects)
}

/// A Proxy to the child, behind the caster gate, as Impale's 83818 and 83819 are
/// without their target gates.
fn gated_proxy(
  child child: Int,
  effect effect: Int,
  gate gate: prerequisite.Prerequisite,
) -> spell_plan.Proxy {
  Proxy(
    effect_id: Spell4EffectsId(effect),
    delay_ms: 0,
    phase_flags: -1,
    condition: GatedOnCaster(gates: [gate]),
    tag: spend.always,
    target: spell_plan.OnCaster,
    spell: support.child(spell4_id: child, base: child),
    gains: [],
  )
}

/// 38585 (type 116 comparison 1, or a live cast of 39407) and 38587 (comparison 2 and
/// not under a cast by 39407), as `table_rows -- Prerequisite 38585 38587` prints them.
fn impales_gates() -> #(prerequisite.Prerequisite, prerequisite.Prerequisite) {
  #(
    prerequisite_support.loaded(id: 38_585, rows: [
      prerequisite_support.row(id: 38_585, flags: 1, conditions: [
        #(116, 1, 0, 28_455),
        #(15, 1, 0, 39_407),
      ]),
    ]),
    prerequisite_support.loaded(id: 38_587, rows: [
      prerequisite_support.row(id: 38_587, flags: 0, conditions: [
        #(116, 2, 0, 28_455),
        #(50, 2, 0, 39_407),
      ]),
    ]),
  )
}

pub fn an_attack_from_stealth_reads_the_stealth_in_its_gates_then_ends_it_after_its_effects_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(on_gate, off_gate) = impales_gates()
  let impale =
    Spell(
      ..attack(spell4_id: 38_779, base: 2, change: EndsStealthAfterLastGo),
      proxies: [
        gated_proxy(child: 39_427, effect: 83_819, gate: on_gate),
        gated_proxy(child: 39_426, effect: 83_818, gate: off_gate),
      ],
    )
  let #(plans, state, entered) = stealthed_by_base_1(others: [impale])
  let held = support.pressed_id(effects: entered)
  let #(state, effects) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_2,
      at: 2000,
    )
  assert children_started(effects:) == [39_427]
    as "38585 passes against the caster stealthed before the go and 38587 fails: only 39427 starts, though the cast ends the stealth"
  assert support.removed_targets(support.writes(effects:)) == [#(held, [7])]
    as "the cast that holds the stealth is taken off the caster: 0x811"
  assert !cast.stealthed(cast: state)
  assert changes(effects:) == [False]
  let lines = trace(effects:)
  assert last_of(lines:, line: "go") < first_of(lines:, line: "off")
    as "the 0x811 follows every go, the cast's and its child's"
  assert list.last(lines) == Ok("stealth off")
    as "the change is the input's last effect"
}

/// An attack of two goes, as Impale's: phase delays 0 and 300 ms, its two Proxies in
/// phase 1 (phaseFlags 2) behind the caster gates of 38585 and 38587, with this stealth
/// change.
fn two_phase_attack(
  spell4_id spell4_id: Int,
  change change: spell_plan.StealthChange,
) -> Spell {
  let #(on_gate, off_gate) = impales_gates()
  Spell(
    ..attack(spell4_id:, base: 2, change:),
    phase_delays_ms: [0, 300],
    proxies: [
      Proxy(
        ..gated_proxy(child: 39_427, effect: 83_819, gate: on_gate),
        phase_flags: 2,
      ),
      Proxy(
        ..gated_proxy(child: 39_426, effect: 83_818, gate: off_gate),
        phase_flags: 2,
      ),
    ],
  )
}

/// A press of the two-phase attack by a caster stealthed by base 1, with the first go
/// answered at once: the state, the effects of the stealthing press, the press's, and
/// the timer of the second go.
fn first_phase_gone(
  spell spell: Spell,
) -> #(Plans, State, List(Effect), List(Effect), TimerId) {
  let #(plans, state, entered) = stealthed_by_base_1(others: [spell])
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: caster(),
      bag_index: bag_of_base_2,
      target: 0,
      at: 2000,
    )
  let #(state, first) =
    support.answered_with_no_targets(state:, effects: pressed, at: 2000)
  let assert [#(second_go, 300)] = support.started_timers(effects: first)
    as "the second go waits 300 ms (SpellPhase 3716)"
  #(plans, state, entered, first, second_go)
}

pub fn an_attack_of_value_1_with_two_phases_reads_the_stealth_in_its_second_phase_gate_and_ends_it_after_that_phase_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(_, state, entered, first, second_go) =
    first_phase_gone(spell: two_phase_attack(
      spell4_id: 38_779,
      change: EndsStealthAfterLastGo,
    ))
  assert children_started(effects: first) == []
    as "the Proxies are phase 1's: the first go starts none"
  assert changes(effects: first) == [] as "the first go ends no stealth"
  assert support.removed_targets(support.writes(effects: first)) == []
  assert cast.stealthed(cast: state)
    as "the stealth holds while the cast's last go is yet to come"
  let #(state, second) = support.fired(state:, timer: second_go, at: 2300)
  assert children_started(effects: second) == [39_427]
    as "38585 reads the caster stealthed and 38587 does not: only 39427 starts (Spell4.spellCastStealthChange.break: Impale's Proxies still see the stealth)"
  assert support.removed_targets(support.writes(effects: second))
    == [#(support.pressed_id(effects: entered), [7])]
    as "the cast that holds the stealth comes off the caster after the last go"
  assert changes(effects: second) == [False]
  assert !cast.stealthed(cast: state)
  let lines = trace(effects: second)
  assert last_of(lines:, line: "go") < first_of(lines:, line: "off")
    as "the 0x811 follows every go of the phase"
  assert list.last(lines) == Ok("stealth off")
}

pub fn an_attack_of_value_0_with_two_phases_ends_the_stealth_at_its_first_go_test() -> Nil {
  use <- owned_test.run(120_000)
  // Value 0 is built as it ends the stealth at a go (the fact's guess, 'when the cast
  // starts', is not built): the first go ends it, so the second phase's Proxies read
  // the caster as not stealthed.
  let #(_, state, entered, first, second_go) =
    first_phase_gone(spell: two_phase_attack(
      spell4_id: 38_783,
      change: EndsStealthAtEachGo,
    ))
  assert support.removed_targets(support.writes(effects: first))
    == [#(support.pressed_id(effects: entered), [7])]
  assert changes(effects: first) == [False]
  assert !cast.stealthed(cast: state)
  let #(_, second) = support.fired(state:, timer: second_go, at: 2300)
  assert children_started(effects: second) == [39_426]
    as "38587 passes and 38585 fails once the stealth is gone"
  assert changes(effects: second) == []
}

pub fn a_cast_cancelled_after_one_of_its_goes_ends_the_stealth_as_it_stops_test() -> Nil {
  use <- owned_test.run(120_000)
  // The server's choice, the client giving no case (Spell4.spellCastStealthChange): the
  // goes that ran applied their effects (Spell4.spellCastStealthChange.break), so a
  // value 1 cast that stops after one and before its last ends the stealth as it stops.
  let #(plans, state, entered, first, second_go) =
    first_phase_gone(spell: two_phase_attack(
      spell4_id: 38_779,
      change: EndsStealthAfterLastGo,
    ))
  let assert Ok(#(state, cancelled)) =
    support.cancelled_in(
      plans:,
      state:,
      cast_id: support.pressed_id(effects: first),
      reason: cast_result.from_value(11),
      bit: 1,
      at: 2100,
    )
  assert support.cancelled_timers(effects: cancelled) == [second_go]
    as "the second go was waiting and is cancelled"
  assert support.removed_targets(support.writes(effects: cancelled))
    == [#(support.pressed_id(effects: entered), [7])]
    as "the cast that holds the stealth comes off the caster"
  assert changes(effects: cancelled) == [False]
  assert list.last(trace(effects: cancelled)) == Ok("stealth off")
  assert !cast.stealthed(cast: state)
}

pub fn a_cast_cancelled_before_its_first_go_keeps_the_stealth_test() -> Nil {
  use <- owned_test.run(120_000)
  // No go ran, so none of its effects was applied: the stealth stays.
  let waiting =
    Spell(
      ..two_phase_attack(spell4_id: 38_779, change: EndsStealthAfterLastGo),
      cast_time_ms: 1000,
    )
  let #(plans, state, _) = stealthed_by_base_1(others: [waiting])
  let #(state, pressed) =
    support.pressed_raw_in(
      plans:,
      state:,
      caster: caster(),
      bag_index: bag_of_base_2,
      target: 0,
      at: 2000,
    )
  assert support.started_timers(effects: pressed) != []
    as "the first go waits for the cast time"
  let assert Ok(#(state, cancelled)) =
    support.cancelled_in(
      plans:,
      state:,
      cast_id: support.pressed_id(effects: pressed),
      reason: cast_result.from_value(11),
      bit: 1,
      at: 2500,
    )
  assert support.removed_targets(support.writes(effects: cancelled)) == []
  assert changes(effects: cancelled) == []
  assert cast.stealthed(cast: state)
}

pub fn a_stealth_row_of_a_later_phase_of_a_value_1_spell_is_kept_when_the_older_source_ends_test() -> Nil {
  use <- owned_test.run(120_000)
  // The cast's own Stealth row, applied in phase 1 with the cast's last go, is its own
  // source: only the casts held before it come off.
  let makes =
    Spell(
      ..two_phase_attack(spell4_id: 38_913, change: EndsStealthAfterLastGo),
      proxies: [],
      stealth: [
        StealthRow(
          ..support.stealth_row(id: 95_774, breaks: KeptOnDamage),
          phase_flags: 2,
        ),
      ],
    )
  let #(_, state, entered, first, second_go) = first_phase_gone(spell: makes)
  assert changes(effects: first) == []
  assert cast.stealthed(cast: state)
  let #(state, second) = support.fired(state:, timer: second_go, at: 2300)
  assert support.removed_targets(support.writes(effects: second))
    == [#(support.pressed_id(effects: entered), [7])]
    as "the older source's cast comes off and the phase's own source stays"
  assert changes(effects: second) == []
  assert cast.stealthed(cast: state)
}

pub fn an_attack_of_value_1_or_0_ends_the_stealth_the_same_way_test() -> Nil {
  use <- owned_test.run(120_000)
  // Shred 38765 holds 1 and Cancel 38783 holds 0 (Spell4.spellCastStealthChange): both
  // end the stealth of their one go; the toggle's own cancel is tested above.
  list.each(
    [
      #(38_765, "Shred", EndsStealthAfterLastGo),
      #(38_783, "Cancel", EndsStealthAtEachGo),
    ],
    fn(spell) {
      let #(plans, state, entered) =
        stealthed_by_base_1(others: [
          attack(spell4_id: spell.0, base: 2, change: spell.2),
        ])
      let #(state, effects) =
        support.press_by(
          caster: caster(),
          plans:,
          state:,
          bag: bag_of_base_2,
          at: 2000,
        )
      assert support.removed_targets(support.writes(effects:))
        == [#(support.pressed_id(effects: entered), [7])]
        as {
          spell.1
          <> " ends the stealth with the 0x811 of the cast that holds it"
        }
      assert changes(effects:) == [False]
      assert !cast.stealthed(cast: state)
    },
  )
}

pub fn a_spell_of_value_2_cast_on_its_own_ends_nothing_test() -> Nil {
  use <- owned_test.run(120_000)
  // 70775, Impale's Fluff child, holds 2 (Spell4.spellCastStealthChange).
  let #(plans, state, _) =
    stealthed_by_base_1(others: [
      attack(spell4_id: 70_775, base: 2, change: KeepsStealth),
    ])
  let #(state, effects) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_2,
      at: 2000,
    )
  assert support.removed_targets(support.writes(effects:)) == []
  assert changes(effects:) == []
  assert cast.stealthed(cast: state) as "the stealth holds"
}

pub fn a_stealth_row_the_same_go_applied_is_kept_and_only_the_older_source_ends_test() -> Nil {
  use <- owned_test.run(120_000)
  // A spell of value 1 that holds a Stealth row of its own: its break ends the stealth
  // other casts hold, never the stealth the cast made (Spell4.spellCastStealthChange.break).
  let makes =
    Spell(
      ..support.stealthing(spell4_id: 38_913, base: 2, rows: [
        support.stealth_row(id: 95_774, breaks: KeptOnDamage),
      ]),
      stealth_change: EndsStealthAfterLastGo,
    )
  let plans = plans_of([broken(), makes])
  let #(state, alone) =
    support.press_by(
      caster: caster(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_2,
      at: 1000,
    )
  assert changes(effects: alone) == [True]
    as "from no stealth the go makes it, and its break ends none"
  assert support.removed_targets(support.writes(effects: alone)) == []
  assert cast.stealthed(cast: state)
  let #(state, first) =
    support.press_by(
      caster: caster(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_1,
      at: 1000,
    )
  let #(state, effects) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_2,
      at: 2000,
    )
  assert support.removed_targets(support.writes(effects:))
    == [#(support.pressed_id(effects: first), [7])]
    as "the older source's cast comes off and the go's own stays"
  assert changes(effects:) == []
    as "the caster is stealthed before and after the go: no change is written"
  assert cast.stealthed(cast: state)
}

pub fn a_go_after_the_stealth_ended_finds_nothing_to_end_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(plans, state, _) =
    stealthed_by_base_1(others: [
      attack(spell4_id: 38_779, base: 2, change: EndsStealthAfterLastGo),
    ])
  let #(state, _) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_2,
      at: 2000,
    )
  let #(_, effects) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_2,
      at: 3000,
    )
  assert support.removed_targets(support.writes(effects:)) == []
  assert changes(effects:) == []
}

// ---- damage ----

fn damaged(state state: State, at ms: Int) -> #(State, List(Effect)) {
  cast.damage_taken(cast: state, caster: caster(), now: support.at(ms:))
}

pub fn damage_takes_the_cast_of_a_source_it_breaks_off_and_ends_the_stealth_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(_, state, entered) = stealthed_by_base_1(others: [])
  let #(state, effects) = damaged(state:, at: 3000)
  assert support.removed_targets(support.writes(effects:))
    == [#(support.pressed_id(effects: entered), [7])]
    as "the stealth cast's node comes off the caster: 0x811 (Spell4Effects.effectType.83: dataBits02 0)"
  assert changes(effects:) == [False]
  assert list.last(trace(effects:)) == Ok("stealth off")
  assert !cast.stealthed(cast: state)
  let #(_, again) = damaged(state:, at: 3001)
  assert again == [] as "a second blow finds nothing to end"
}

pub fn damage_does_not_end_a_stealth_kept_on_damage_or_one_not_held_test() -> Nil {
  use <- owned_test.run(120_000)
  let plans = plans_of([kept()])
  let #(state, _) =
    support.press_by(
      caster: caster(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(state, effects) = damaged(state:, at: 3000)
  assert effects == [] as "dataBits02 1: damage does not end it"
  assert cast.stealthed(cast: state)
  let #(_, none) = damaged(state: cast.new(), at: 3000)
  assert none == [] as "a caster that holds no stealth is told nothing"
}

pub fn damage_ends_the_cast_it_breaks_and_keeps_the_stealth_another_cast_holds_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(plans, state, entered) = stealthed_by_base_1(others: [kept()])
  let #(state, _) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_3,
      at: 2000,
    )
  let #(state, effects) = damaged(state:, at: 3000)
  assert support.removed_targets(support.writes(effects:))
    == [#(support.pressed_id(effects: entered), [7])]
    as "only the cast whose source damage breaks comes off"
  assert changes(effects:) == []
    as "the kept source still holds the stealth: no change"
  assert cast.stealthed(cast: state)
}

pub fn a_cast_that_holds_both_a_broken_and_a_kept_source_loses_both_with_its_node_test() -> Nil {
  use <- owned_test.run(120_000)
  // Both rows are of the one cast, as 38784 holds 83834 and 95774: its node holds both.
  let both =
    support.stealthing(spell4_id: 38_784, base: 1, rows: [
      support.stealth_row(id: 83_834, breaks: BrokenByDamage),
      support.stealth_row(id: 95_774, breaks: KeptOnDamage),
    ])
  let plans = plans_of([both])
  let #(state, _) =
    support.press_by(
      caster: caster(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_1,
      at: 1000,
    )
  let #(state, effects) = damaged(state:, at: 3000)
  assert changes(effects:) == [False]
  assert !cast.stealthed(cast: state)
    as "the node leaves the caster and takes the cast's two sources with it"
}

// ---- RemoveStealth ----

pub fn a_remove_stealth_row_on_the_caster_ends_a_broken_source_and_a_kept_one_with_one_change_test() -> Nil {
  use <- owned_test.run(120_000)
  let removes =
    Spell(
      ..attack(spell4_id: 51_908, base: 2, change: KeepsStealth),
      remove_stealth: [
        RemoveStealthRow(
          effect_id: Spell4EffectsId(51_908),
          phase_flags: -1,
          condition: Always,
          tag: spend.always,
        ),
      ],
    )
  let #(plans, state, first) = stealthed_by_base_1(others: [kept(), removes])
  let #(state, second) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_3,
      at: 2000,
    )
  let #(state, effects) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_2,
      at: 3000,
    )
  assert support.removed_targets(support.writes(effects:))
    == [
      #(support.pressed_id(effects: first), [7]),
      #(support.pressed_id(effects: second), [7]),
    ]
    as "both casts come off, the older first (Spell4Effects.effectType.84)"
  assert changes(effects:) == [False] as "one change for the one input"
  assert !cast.stealthed(cast: state)
}

// ---- settled once for each input ----

pub fn a_second_stealth_cast_at_the_stack_cap_takes_the_first_off_with_no_change_and_one_cancel_ends_it_test() -> Nil {
  use <- owned_test.run(120_000)
  // 38784 holds stack group 173 of cap 1 (Spell4StackGroup 173): a second cast pushes
  // the first off the caster.
  let stacking = Spell(..broken(), stack: lasting.Stack(group_id: 173, cap: 1))
  let plans =
    plans_of([stacking, cancelling(spell4_id: 38_783, base: 2, of: 38_784)])
  let #(state, first) =
    support.press_by(
      caster: caster(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_1,
      at: 1000,
    )
  let #(state, second) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_1,
      at: 2000,
    )
  assert support.removed_targets(support.writes(effects: second))
    == [#(support.pressed_id(effects: first), [7])]
    as "the cap takes the first cast's node off: one 0x811"
  assert changes(effects: second) == []
    as "stealthed before and after the input: no 0x8f5"
  assert cast.stealthed(cast: state)
  let #(state, cancel) =
    support.press_by(
      caster: caster(),
      plans:,
      state:,
      bag: bag_of_base_2,
      at: 3000,
    )
  assert support.removed_targets(support.writes(effects: cancel))
    == [#(support.pressed_id(effects: second), [7])]
  assert changes(effects: cancel) == [False] as "one cancel, one change"
  assert !cast.stealthed(cast: state)
}

// ---- death and leaving ----

pub fn a_death_while_stealthed_by_a_kept_on_damage_source_ends_the_casts_then_changes_once_test() -> Nil {
  use <- owned_test.run(120_000)
  let plans = plans_of([kept()])
  let #(state, entered) =
    support.press_by(
      caster: caster(),
      plans:,
      state: cast.new(),
      bag: bag_of_base_3,
      at: 1000,
    )
  let #(state, effects) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 2000),
    )
  assert list.contains(
    support.finished_ids(support.writes(effects:)),
    support.pressed_id(effects: entered),
  )
    as "the stealth cast's 0x7fe destroys its node and the buff goes (cast.target_node_end)"
  assert changes(effects:) == [False] as "the change is told once"
  let lines = trace(effects:)
  assert list.last(lines) == Ok("stealth off")
    as "and it is the last effect, after the casts' 0x7fe"
  assert last_of(lines:, line: "end") < first_of(lines:, line: "stealth off")
  assert !cast.stealthed(cast: state)
  let #(_, healthy) =
    cast.died(
      cast: cast.new(),
      caster: support.dead_caster(),
      now: support.at(ms: 2000),
    )
  assert changes(effects: healthy) == []
    as "a caster that was not stealthed is told no change"
}

pub fn leaving_while_stealthed_writes_nothing_and_the_next_stay_starts_unstealthed_test() -> Nil {
  use <- owned_test.run(120_000)
  let #(_, state, _) = stealthed_by_base_1(others: [])
  let #(left, effects) = cast.left(cast: state)
  assert support.writes(effects:) == []
  assert changes(effects:) == []
  assert !cast.stealthed(cast: left)
  assert !cast.stealthed(cast: cast.new())
}
