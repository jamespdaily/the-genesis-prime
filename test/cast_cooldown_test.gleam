//// The cast rule's cooldown effects (`genesis_prime/game/cast`, `genesis_prime/game/cooldown`):
//// a ModifySpellCooldown row (`Spell4Effects.effectType.73`) of a go changes the
//// server's cooldowns as the client changes its own. Expected values come from these
//// places:
//// - `0x14053e5a0` ApplySpellGo: the go starts the spell's cooldowns (`0x14053ebfb` and
////   `0x14053ec4e`) before it applies the target info (`0x14053ecbf`), so a type 73 row
////   in a go already sees the cooldown the same go starts.
//// - `0x14046b920` ModifyRunningCooldowns: the change reaches the running cooldowns
////   whose spell the selector picks, and skips the entry of spell id 0, which is the
////   global cooldown (`0x14046afc0` StartGlobalCooldown).
//// - `0x14046b7f0` AddSpellCooldownModifier and `0x14046a890` ApplyCooldownModifiers: an
////   effect with a lifetime is kept, and a cooldown that starts while it is kept goes
////   through the kept modifiers in the order they were added.
//// - `opcode.0x7f4.effect_time`: an effect's lifetime is its delay plus durationTime, the
////   larger of the two for a spell with the record flag 0x10000000 (Spell4.propertyFlags
////   0x2000), and never ends for flags bit 2.
//// - `opcode.0x804`: the client's own cooldown comes from the go, and an 0x804 would
////   undo a type 73 change, so the server sends none.
//// - `0x1403b14c0`: a press with 500 ms of a cooldown left or less is sent by the client
////   and held by the server; with more it is refused 15 (own) or 14 (global).
//// - The kit's rows (`table_rows -- Spell4Effects 80977 80979 180712 231992 231993`):
////   80977 of Charged Shot's stage 34720 (index 0) multiplies the cooldowns of base 20684
////   by 0.0, and 80979 of stage 34722 (index 1) by 0.4; 180712, 231992 and 231993 of
////   70775 take 1500, 500 and 500 ms off base 32336; 231992 and 231993 hold the caster
////   apply prerequisite 4585 (type 37, comparison 6, value 50: one roll).
//// - The planted spells (`cast_support`): `slow` is Spell4 3 of base 3 with a cast time
////   of 1000 ms, a cooldown of 5000 ms from its go and global cooldown kind 3, so its
////   cooldown is measured by pressing it. The other planted spells are the test's own:
////   they hold the rows or the removal that a test is about.
//// - The server's choices, in the cast rule's doc: the rows end with their node, a later
////   go keeps them again, a press held for a cooldown waits for the end wherever it
////   moves, and the hold's repeat timer does the same (`cast.hold_repeat`).

import cast_support as support
import genesis_prime/game/cast.{type Effect, type State}
import genesis_prime/game/cooldown.{
  type Operation, AddMs, Base, Modifier, NoLonger, SetMs,
}
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/spell_plan.{type Plans, type Spell, Always}
import genesis_prime/game/spend
import genesis_prime/message/spell_go
import genesis_prime/step.{type TimerId, TimerId}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId, Spell4Id}
import gleam/int
import gleam/list
import owned_test
import prerequisite_support
import spell_tables

// The planted bases are bag indexes in `cast_support.abilities`: base 3 (`slow`) is 11,
// base 1 is 8 and base 2 is 10.
const bag_of_slow = 11

const bag_of_holder = 8

const bag_of_remover = 10

/// A planted spell of Spell4 `spell4_id` and base `base` that goes at once and holds
/// these type 73 rows.
fn holder_of(
  spell4_id spell4_id: Int,
  base base: Int,
  rows rows: List(spell_plan.CooldownModifier),
) -> Spell {
  spell_plan.Spell(..support.child(spell4_id:, base:), cooldown_modifiers: rows)
}

/// A type 73 row that applies `operation` to every cooldown of base 3, the planted
/// `slow` spell's, from `delay` for `duration` milliseconds, in every phase, aimed at
/// the caster.
fn row(
  effect_id effect_id: Int,
  operation operation: Operation,
  delay delay: Int,
  duration duration: Int,
) -> spell_plan.CooldownModifier {
  spell_plan.CooldownModifier(
    effect_id: Spell4EffectsId(effect_id),
    phase_flags: -1,
    modifier: Modifier(selector: Base(Spell4BaseId(3)), operation:),
    row: LastingRow(
      delay_ms: delay,
      duration_ms: duration,
      until_removed: False,
    ),
    condition: Always,
    tag: spend.always,
  )
}

fn until_removed(
  row row: spell_plan.CooldownModifier,
) -> spell_plan.CooldownModifier {
  spell_plan.CooldownModifier(
    ..row,
    row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
  )
}

/// The planted plans with the base 1 spell holding these rows.
fn plans_holding(rows rows: List(spell_plan.CooldownModifier)) -> Plans {
  plans_with(spells: [holder_of(spell4_id: 1, base: 1, rows:)])
}

fn plans_with(spells spells: List(Spell)) -> Plans {
  support.with_spells(plans: support.plans(), spells:)
}

/// A removal of the base 1 spell's casts from the caster, as a type 80 row aimed at the
/// caster does (`Spell4Effects.effectType.80`).
fn remover() -> Spell {
  spell_plan.Spell(..support.child(spell4_id: 2, base: 2), removes: [
    spell_plan.ForceRemove(
      effect_id: Spell4EffectsId(196_521),
      phase_flags: -1,
      aim: spell_plan.AimsAtCaster,
      selector: lasting.Spell(Spell4Id(1)),
      count: 1,
      condition: Always,
      tag: spend.always,
    ),
  ])
}

fn press(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  support.pressed_in(
    plans:,
    state:,
    caster: support.caster(),
    bag_index: bag,
    target: 0,
    at: ms,
  )
}

/// The slow spell pressed at the time and its go fired: its cooldown runs for 5000 ms
/// from `at + 1000`.
fn slow_cast(plans plans: Plans, state state: State, at ms: Int) -> State {
  let #(state, effects) = press(plans:, state:, bag: bag_of_slow, at: ms)
  let #(state, _) = support.run_timers(state:, effects:, from_ms: ms)
  state
}

/// What a press of the slow spell meets: it is accepted, refused with a result, or held
/// for a wait.
type Meets {
  Accepted
  Refused(result: Int)
  Held(wait_ms: Int)
}

fn meets(plans plans: Plans, state state: State, at ms: Int) -> Meets {
  let #(_, effects) = press(plans:, state:, bag: bag_of_slow, at: ms)
  meets_of(effects:)
}

fn meets_of(effects effects: List(Effect)) -> Meets {
  case support.refusal_results(effects:), support.started_timers(effects:) {
    [result, ..], _ -> Refused(result:)
    [], [#(_, wait_ms)] if effects != [] -> held_or_accepted(effects:, wait_ms:)
    [], _ -> Accepted
  }
}

fn held_or_accepted(
  effects effects: List(Effect),
  wait_ms wait_ms: Int,
) -> Meets {
  case support.writes(effects:) {
    [] -> Held(wait_ms:)
    [_, ..] -> Accepted
  }
}

/// The effects the go's target info of each unit lists, with each one's delay, and the
/// unit.
fn listed(effects effects: List(Effect)) -> List(#(Int, List(#(Int, Int)))) {
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

fn delays_of(effects effects: List(Effect)) -> List(Int) {
  list.map(support.started_timers(effects:), fn(started) { started.1 })
}

fn number_of(timer timer: TimerId) -> Int {
  let TimerId(number) = timer
  number
}

fn numbers_of(timers timers: List(TimerId)) -> List(Int) {
  list.map(timers, number_of) |> list.sort(int.compare)
}

/// The timers a step started, in numbers.
fn started_numbers(effects effects: List(Effect)) -> List(Int) {
  numbers_of(
    timers: list.map(support.started_timers(effects:), fn(started) { started.0 }),
  )
}

// ---- Charged Shot ----

/// The planted plans with Charged Shot's two type 73 rows (`spell_tables`).
fn charged_plans() -> Plans {
  spell_tables.plans_with_cooldown_effects()
}

fn charged(
  plans plans: Plans,
  state state: State,
  at ms: Int,
) -> #(State, List(Effect)) {
  press(plans:, state:, bag: support.charged_shot, at: ms)
}

fn is_accepted(effects effects: List(Effect)) -> Bool {
  list.first(support.ids(frames: support.writes(effects:))) == Ok(0x07FD)
}

pub fn charged_shot_released_at_once_ends_the_cooldown_its_go_started_test() -> Nil {
  use <- owned_test.run(20_000)
  let #(state, _) = charged(plans: charged_plans(), state: cast.new(), at: 1000)
  let #(state, release) = charged(plans: charged_plans(), state:, at: 1100)
  assert listed(effects: release) == [#(7, [#(80_977, 0)])]
    as "the index-0 stage 34720's go lists 80977 in the caster's target info (opcode.0x7f4.target_info)"
  // The global cooldown of the first press, 1000 ms from 1000, has passed at 2000.
  let #(_, again) = charged(plans: charged_plans(), state:, at: 2000)
  assert support.refusal_results(effects: again) == []
    && is_accepted(effects: again)
    as "0x14053e5a0: the go starts 34718's 10 s cooldown and then applies 80977's x0.0, so the press is accepted, not refused 15"
}

pub fn without_the_type_73_row_the_same_release_leaves_the_cooldown_running_test() -> Nil {
  use <- owned_test.run(20_000)
  // The planted rows without 80977 and 80979: the harness can fail.
  let #(state, _) = charged(plans: support.plans(), state: cast.new(), at: 1000)
  let #(state, _) = charged(plans: support.plans(), state:, at: 1100)
  let #(_, again) = charged(plans: support.plans(), state:, at: 2000)
  assert support.refusal_results(effects: again) == [15]
    as "Spell4.34718: a cooldown of 10 s from the release's go"
}

pub fn charged_shot_released_at_index_1_leaves_four_seconds_of_its_cooldown_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans = charged_plans()
  let #(state, pressed) = charged(plans:, state: cast.new(), at: 1000)
  let assert [#(level_1, 1000)] = support.started_timers(effects: pressed)
  let #(state, _) = support.fired(state:, timer: level_1, at: 2000)
  let #(state, release) = charged(plans:, state:, at: 2500)
  assert listed(effects: release) == [#(7, [#(80_979, 0)])]
    as "Spell4Thresholds 123: a release after 1000 ms casts 34722, whose go lists 80979"
  // The go at 2500 starts 10000 ms and 80979 leaves 10000 x 0.4 = 4000: the end is 6500.
  let #(_, early) = charged(plans:, state:, at: 2500 + 3400)
  assert support.refusal_results(effects: early) == [15]
    as "600 ms are left, more than the queue window of 500: refused 15"
  let #(held, near) = charged(plans:, state:, at: 2500 + 3600)
  assert support.writes(effects: near) == []
    && delays_of(effects: near) == [400]
    as "400 ms are left, within the queue window: the press is held"
  let assert [#(timer, 400)] = support.started_timers(effects: near)
  let #(_, started) = support.fired(state: held, timer:, at: 6500)
  assert is_accepted(effects: started)
    as "the held press starts 4000 ms after the go (0x1403b14c0, cast.press_queue)"
}

pub fn a_row_that_selects_the_spell_leaves_the_global_cooldown_as_it_was_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans = charged_plans()
  let #(state, _) = charged(plans:, state: cast.new(), at: 1000)
  let #(state, _) = charged(plans:, state:, at: 1100)
  let #(_, early) = charged(plans:, state:, at: 1200)
  assert support.refusal_results(effects: early) == [14]
    as "80977 selects base 20684, whose press started the global cooldown (kind 0, SpellCoolDown 82, 1000 ms); ModifyRunningCooldowns skips the entry of spell id 0 (0x14046b920), so 800 ms of it are left and the press is refused 14"
  let #(_, near) = charged(plans:, state:, at: 1600)
  assert support.writes(effects: near) == []
    && delays_of(effects: near) == [400]
    as "the global cooldown still ends at 2000, 400 ms from 1600"
}

pub fn no_0x804_is_written_at_a_go_with_a_type_73_row_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans = charged_plans()
  let #(state, pressed) = charged(plans:, state: cast.new(), at: 1000)
  let #(state, release) = charged(plans:, state:, at: 1100)
  let #(_, fired) = support.run_timers(state:, effects: pressed, from_ms: 1000)
  let frames =
    list.flatten([
      support.writes(effects: pressed),
      support.writes(effects: release),
      list.flat_map(fired, fn(step) { support.writes(effects: step.1) }),
    ])
  assert list.contains(support.ids(frames:), 0x07F4)
    as "the run holds the go that lists the row"
  assert !list.contains(support.ids(frames:), 0x0804)
    as "opcode.0x804 would give back the 10 s the row took away; the client's own cooldown comes from the go"
}

// ---- Impale's child ----

/// 180712 and 231992 of 70775 as the client holds them, in the planted spell of Spell4 70775:
/// 1500 and 500 ms off base 32336, the second behind the type 37 prerequisite 4585.
fn impale_child(gate gate: spell_plan.Condition) -> Spell {
  let off = fn(effect_id, amount, condition) {
    spell_plan.CooldownModifier(
      effect_id: Spell4EffectsId(effect_id),
      phase_flags: -1,
      modifier: Modifier(
        selector: Base(Spell4BaseId(32_336)),
        operation: AddMs(amount),
      ),
      row: LastingRow(delay_ms: 0, duration_ms: 0, until_removed: False),
      condition:,
      tag: spend.always,
    )
  }
  holder_of(spell4_id: 70_775, base: 1, rows: [
    off(180_712, -1500.0, Always),
    off(231_992, -500.0, gate),
  ])
}

pub fn impale_childs_go_lists_180712_and_changes_no_running_cooldown_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans = plans_with(spells: [impale_child(gate: Always)])
  // The slow spell's cooldown runs until 7000; base 32336 is no spell of the server's.
  let state = slow_cast(plans:, state: cast.new(), at: 1000)
  let #(state, child) = press(plans:, state:, bag: bag_of_holder, at: 2500)
  assert listed(effects: child) == [#(7, [#(180_712, 0), #(231_992, 0)])]
    as "the go lists the rows on the caster, and the client applies them to its own charge recharges"
  assert meets(plans:, state:, at: 6600) == Held(wait_ms: 400)
    as "Punish (base 32336) has spellCoolDown 0, so no server cooldown holds that base and the slow spell's 7000 end stays"
}

pub fn a_row_behind_a_type_37_gate_takes_one_roll_and_is_listed_when_it_passes_test() -> Nil {
  use <- owned_test.run(20_000)
  let chance = prerequisite_support.single(id: 4585, condition: #(37, 6, 0, 50))
  let plans =
    plans_with(spells: [
      impale_child(gate: spell_plan.GatedOnCaster(gates: [chance])),
    ])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster: support.caster(),
      bag_index: bag_of_holder,
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
        | cast.PropertyStarts(..)
        | cast.PropertyEnds(..)
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
    as "Prerequisite 4585 is type 37: 231992 behind it takes one roll and 180712 takes none"
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
  assert went(50) == [#(7, [#(180_712, 0), #(231_992, 0)])]
    as "a roll of 50 passes comparison 6 on 50"
  assert went(51) == [#(7, [#(180_712, 0)])]
    as "a roll of 51 fails and 231992 is not listed"
}

pub fn several_rows_of_one_go_apply_in_their_listed_order_test() -> Nil {
  use <- owned_test.run(20_000)
  // x0.5 then -1000 on the slow spell's 5000 ms is 1500; the other order is 2000.
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 0),
      row(effect_id: 2, operation: AddMs(-1000.0), delay: 0, duration: 0),
    ])
  let state = slow_cast(plans:, state: cast.new(), at: 1000)
  // The slow spell's go at 2000 starts its cooldown, which ends at 7000.
  let #(state, _) = press(plans:, state:, bag: bag_of_holder, at: 2500)
  // 4500 ms are left at 2500: x0.5 is 2250 and -1000 is 1250, so the end is 3750.
  assert meets(plans:, state:, at: 3500) == Held(wait_ms: 250)
    as "the listed order gives 1250 ms from 2500; the other gives 1750 and a refusal"
}

// ---- a row that acts once ----

pub fn a_row_that_acts_once_is_not_kept_for_the_cooldowns_that_start_later_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 0),
    ])
  let #(state, _) =
    press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
  let state = slow_cast(plans:, state:, at: 2000)
  // The slow spell's go at 3000 starts 5000 ms, which end at 8000.
  assert meets(plans:, state:, at: 7600) == Held(wait_ms: 400)
    as "0x14046b7f0 keeps an effect only when it has a lifetime: the cooldown that starts after the go is full"
}

pub fn a_row_that_acts_once_gives_the_node_its_delay_as_life_and_a_kept_row_gives_it_the_rows_life_test() -> Nil {
  use <- owned_test.run(20_000)
  let acts_once =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 2000, duration: 0),
    ])
  let #(state, once) =
    press(plans: acts_once, state: cast.new(), bag: bag_of_holder, at: 1000)
  assert delays_of(effects: once) == [2000, 2000]
    as "the row's own timer and the node's end, each at the row's delay (opcode.0x7f4.effect_time)"
  assert support.finished_ids(support.writes(effects: once)) == []
    as "the 0x7fe waits for the node, as the client's 0x7fe would destroy the pending effect (opcode.0x7fe, cast.target_node_end)"
  let #(_, fired) = support.run_timers(state:, effects: once, from_ms: 1000)
  assert list.map(fired, fn(step) { step.0 }) == [3000, 3000]
  assert list.length(
      support.finished_ids(
        support.writes(effects: list.flat_map(fired, fn(step) { step.1 })),
      ),
    )
    == 1
    as "the cast finishes at go + delay"
  let kept =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 8000),
    ])
  let #(_, lasting) =
    press(plans: kept, state: cast.new(), bag: bag_of_holder, at: 1000)
  assert support.finished_ids(support.writes(effects: lasting)) == []
    as "a kept row gives the caster's node its life, so the 0x7fe waits (opcode.0x7f4.effect_time, cast.target_node_end)"
  assert list.sort(delays_of(effects: lasting), int.compare) == [8000, 8000]
    as "the row's end and the node's end, each at delay plus duration"
}

// ---- a lasting row ----

pub fn a_lasting_row_changes_the_running_cooldowns_at_its_start_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 8000),
    ])
  let state = slow_cast(plans:, state: cast.new(), at: 1000)
  // The slow spell's cooldown ends at 7000; at 2500 4500 ms are left, and x0.5 is 2250.
  let #(state, _) = press(plans:, state:, bag: bag_of_holder, at: 2500)
  assert meets(plans:, state:, at: 4400) == Held(wait_ms: 350)
    as "the end moved from 7000 to 4750 (0x14046b7f0: kept, then ModifyRunningCooldowns)"
}

pub fn a_lasting_row_changes_each_cooldown_started_while_it_lasts_in_the_order_kept_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 8000),
      row(effect_id: 2, operation: AddMs(-1000.0), delay: 0, duration: 8000),
    ])
  let #(state, _) =
    press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
  // The kept rows are x0.5 and then -1000: 5000 becomes 2500 and 1500. The slow spell's
  // go at 3000 ends at 4500.
  let state = slow_cast(plans:, state:, at: 2000)
  assert meets(plans:, state:, at: 4100) == Held(wait_ms: 400)
    as "0x14046a890: the order kept; the other order gives 2000 ms and an end at 5000"
}

pub fn a_cooldown_started_after_a_lasting_rows_end_is_full_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 8000),
    ])
  let #(state, pressed) =
    press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
  // The row lasts from 1000 to 9000 (delay 0 plus duration 8000).
  let #(before, _) =
    support.run_timers_until(
      state:,
      effects: pressed,
      from_ms: 1000,
      until_ms: 7500,
    )
  let before = slow_cast(plans:, state: before, at: 7500)
  // The slow spell's go at 8500 is inside the row: 2500 ms, ending at 11000.
  assert meets(plans:, state: before, at: 10_600) == Held(wait_ms: 400)
  let #(after, _) =
    support.run_timers_until(
      state:,
      effects: pressed,
      from_ms: 1000,
      until_ms: 9500,
    )
  let after = slow_cast(plans:, state: after, at: 9500)
  // The go at 10500 is after the end: 5000 ms, ending at 15500.
  assert meets(plans:, state: after, at: 15_100) == Held(wait_ms: 400)
    as "opcode.0x7f4.effect_time: the lifetime is delay plus duration, so the row is dropped at 9000"
}

pub fn a_spell_with_the_larger_of_delay_and_duration_ends_its_row_sooner_test() -> Nil {
  use <- owned_test.run(20_000)
  // The row starts at go + 2000 and lasts 8000: delay plus duration ends it at 11000,
  // and the larger of the two, 8000, at 9000 (Spell4.propertyFlags 0x2000).
  let rows = [
    row(effect_id: 1, operation: NoLonger(0.5), delay: 2000, duration: 8000),
  ]
  let slow_after_9500 = fn(plans) {
    let #(state, pressed) =
      press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
    let #(state, _) =
      support.run_timers_until(
        state:,
        effects: pressed,
        from_ms: 1000,
        until_ms: 9500,
      )
    slow_cast(plans:, state:, at: 9500)
  }
  let summed = plans_holding(rows:)
  // The go at 10500 is inside the row's 11000: 2500 ms, ending at 13000.
  assert meets(plans: summed, state: slow_after_9500(summed), at: 12_600)
    == Held(wait_ms: 400)
  let larger =
    plans_with(spells: [
      spell_plan.Spell(
        ..holder_of(spell4_id: 1, base: 1, rows:),
        longer_of_delay_and_duration: True,
      ),
    ])
  // The same go is after the larger's 9000: 5000 ms, ending at 15500.
  assert meets(plans: larger, state: slow_after_9500(larger), at: 15_100)
    == Held(wait_ms: 400)
    as "opcode.0x7f4.effect_time"
}

pub fn a_row_with_flags_bit_2_lasts_until_its_node_is_taken_off_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_with(spells: [
      holder_of(spell4_id: 1, base: 1, rows: [
        until_removed(row: row(
          effect_id: 1,
          operation: NoLonger(0.5),
          delay: 0,
          duration: 0,
        )),
      ]),
      remover(),
    ])
  let #(state, pressed) =
    press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
  assert delays_of(effects: pressed) == []
    as "flags bit 2 never ends by time: no end timer and no node end"
  // A cooldown that starts 50 s later is still halved: the go at 51000 ends at 53500.
  let long_after = slow_cast(plans:, state:, at: 50_000)
  assert meets(plans:, state: long_after, at: 53_100) == Held(wait_ms: 400)
  let #(removed, _) = press(plans:, state:, bag: bag_of_remover, at: 60_000)
  let after = slow_cast(plans:, state: removed, at: 70_000)
  // The go at 71000 is after the removal: 5000 ms, ending at 76000.
  assert meets(plans:, state: after, at: 75_600) == Held(wait_ms: 400)
}

// ---- an end ----

pub fn taking_the_casts_node_off_the_caster_drops_the_row_and_cancels_its_timers_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_with(spells: [
      holder_of(spell4_id: 1, base: 1, rows: [
        row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 8000),
      ]),
      remover(),
    ])
  let #(state, first) =
    press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
  let #(state, removal) = press(plans:, state:, bag: bag_of_remover, at: 2000)
  assert numbers_of(timers: support.cancelled_timers(effects: removal))
    == started_numbers(effects: first)
    as "the row's end and the node's end, the two timers the first press started"
  let after = slow_cast(plans:, state:, at: 3000)
  // The go at 4000 starts 5000 ms, ending at 9000.
  assert meets(plans:, state: after, at: 8600) == Held(wait_ms: 400)
    as "taking the node off the caster drops the row, as it ends a property modifier"
}

pub fn the_caster_dying_drops_every_lasting_row_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 8000),
    ])
  let #(state, _) =
    press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
  let #(state, _) =
    cast.died(
      cast: state,
      caster: support.dead_caster(),
      now: support.at(ms: 1100),
    )
  let after = slow_cast(plans:, state:, at: 3000)
  assert meets(plans:, state: after, at: 8600) == Held(wait_ms: 400)
    as "the death ends every cast and cancels every timer, so the row is not kept"
}

pub fn a_caster_that_leaves_drops_every_lasting_row_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 8000),
    ])
  let #(state, _) =
    press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
  let #(state, _) = cast.left(cast: state)
  let after = slow_cast(plans:, state:, at: 3000)
  assert meets(plans:, state: after, at: 8600) == Held(wait_ms: 400)
}

pub fn a_later_go_of_the_cast_keeps_its_row_again_from_that_go_test() -> Nil {
  use <- owned_test.run(20_000)
  let holder =
    spell_plan.Spell(
      ..holder_of(spell4_id: 1, base: 1, rows: [
        row(effect_id: 1, operation: NoLonger(0.5), delay: 0, duration: 8000),
      ]),
      phase_delays_ms: [0, 3000],
    )
  let plans = plans_with(spells: [holder, remover()])
  let #(state, pressed) =
    press(plans:, state: cast.new(), bag: bag_of_holder, at: 1000)
  let assert [#(second_go, 3000), ..] =
    list.filter(support.started_timers(effects: pressed), fn(started) {
      started.1 == 3000
    })
    as "the second phase's go waits 3000 ms"
  let #(state, _) = press(plans:, state:, bag: bag_of_remover, at: 2000)
  let between = slow_cast(plans:, state:, at: 2100)
  // The slow spell's go at 3100 is after the removal and before the second go: 5000 ms,
  // ending at 8100.
  assert meets(plans:, state: between, at: 7700) == Held(wait_ms: 400)
  let #(state, _) = support.fired(state:, timer: second_go, at: 4000)
  let after = slow_cast(plans:, state:, at: 4500)
  // The second go at 4000 kept the row again; the slow spell's go at 5500 ends at 8000.
  assert meets(plans:, state: after, at: 7600) == Held(wait_ms: 400)
    as "a later go of the same cast keeps its row again, after the removal dropped it"
}

// ---- a delayed row ----

pub fn a_delayed_row_changes_the_cooldowns_at_its_timer_not_at_the_go_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 2000, duration: 0),
    ])
  let state = slow_cast(plans:, state: cast.new(), at: 500)
  // The slow spell's go at 1500 starts a cooldown that ends at 6500.
  let #(at_the_go, pressed) =
    press(plans:, state:, bag: bag_of_holder, at: 1000)
  assert list.contains(delays_of(effects: pressed), 2000)
    as "the row waits its delay of 2000 on a timer (opcode.0x7f4.effect_time)"
  assert meets(plans:, state: at_the_go, at: 6100) == Held(wait_ms: 400)
    as "nothing changed at the go"
  let #(at_the_timer, _) =
    support.run_timers_until(
      state: at_the_go,
      effects: pressed,
      from_ms: 1000,
      until_ms: 3000,
    )
  // At 3000, 3500 ms are left and x0.5 is 1750: the end is 4750.
  assert meets(plans:, state: at_the_timer, at: 4400) == Held(wait_ms: 350)
    as "the row changed the running cooldown at go + 2000"
  let later = slow_cast(plans:, state: at_the_timer, at: 5000)
  // The go at 6000 is after the row, which acted once: 5000 ms, ending at 11000.
  assert meets(plans:, state: later, at: 10_600) == Held(wait_ms: 400)
    as "a row with a delay and no duration acts once"
}

/// The timers fired one after the other at the time, in this order; a timer an earlier
/// step cancelled is not fired, as the clock the shell drives would not fire it.
fn fired_in_order(
  state state: State,
  timers timers: List(TimerId),
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects, _) =
    list.fold(timers, #(state, [], []), fn(so_far, timer) {
      let #(state, effects, cancelled) = so_far
      case list.contains(cancelled, timer) {
        True -> so_far
        False -> {
          let #(state, more) = support.fired(state:, timer:, at: ms)
          #(
            state,
            list.append(effects, more),
            list.append(cancelled, support.cancelled_timers(effects: more)),
          )
        }
      }
    })
  #(state, effects)
}

/// The timers the effects start that are due after this delay.
fn timers_after(
  effects effects: List(Effect),
  delay_ms delay_ms: Int,
) -> List(TimerId) {
  list.filter_map(support.started_timers(effects:), fn(started) {
    case started.1 == delay_ms {
      True -> Ok(started.0)
      False -> Error(Nil)
    }
  })
}

pub fn a_row_applies_when_its_nodes_end_fires_first_in_the_same_millisecond_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 2000, duration: 0),
    ])
  let state = slow_cast(plans:, state: cast.new(), at: 500)
  // The slow spell's go at 1500 starts a cooldown that ends at 6500.
  let #(state, pressed) = press(plans:, state:, bag: bag_of_holder, at: 1000)
  let timers = timers_after(effects: pressed, delay_ms: 2000)
  assert list.length(timers) == 2
    as "the row's start and the node's end are due in the same millisecond"
  list.each([timers, list.reverse(timers)], fn(order) {
    let #(after, effects) = fired_in_order(state:, timers: order, at: 3000)
    assert list.length(support.finished_ids(support.writes(effects:))) == 1
      as "the node's end finishes the cast"
    // At 3000, 3500 ms are left and x0.5 is 1750: the end is 4750.
    assert meets(plans:, state: after, at: 4400) == Held(wait_ms: 350)
      as "the row changed the running cooldown whichever timer fired first"
  })
}

pub fn a_row_that_sets_a_cooldown_at_go_plus_ten_lands_before_the_cast_finishes_test() -> Nil {
  use <- owned_test.run(20_000)
  // Row 130784 of Spell4 34751 sets base 59823's cooldown to 5000 ms at go + 10
  // (`table_rows -- Spell4Effects 130784`); base 3 is the planted slow spell's.
  let plans =
    plans_holding(rows: [
      row(effect_id: 130_784, operation: SetMs(5000.0), delay: 10, duration: 0),
    ])
  let state = slow_cast(plans:, state: cast.new(), at: 1000)
  // The slow spell's go at 2000 starts a cooldown that ends at 7000; at 6600 400 ms are
  // left, a press the client allows and the server holds.
  let #(state, pressed) = press(plans:, state:, bag: bag_of_holder, at: 6600)
  assert support.finished_ids(support.writes(effects: pressed)) == []
    as "the cast stays until the row lands: the client's 0x7fe would destroy the pending effect"
  assert meets(plans:, state:, at: 6605) == Held(wait_ms: 395)
    as "before go + 10 the cooldown is as it was, so the press the client allows is not refused"
  let #(after, effects) =
    fired_in_order(
      state:,
      timers: timers_after(effects: pressed, delay_ms: 10),
      at: 6610,
    )
  assert list.length(support.finished_ids(support.writes(effects:))) == 1
    as "the 0x7fe is written at go + 10, with the row applied"
  assert meets(plans:, state: after, at: 6700) == Refused(result: 15)
    as "the cooldown is 5000 ms from go + 10, as the client's effect leaves it"
}

// ---- a press waiting for the end ----

/// The step of the timers a press started that holds a row's change: the effects of
/// the timer that fired at the time.
fn step_at(
  fired fired: List(#(Int, List(Effect))),
  at ms: Int,
) -> List(Effect) {
  list.flat_map(list.filter(fired, fn(step) { step.0 == ms }), fn(step) {
    step.1
  })
}

pub fn a_held_press_starts_at_the_new_end_when_a_row_shortens_the_cooldown_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 4200, duration: 0),
    ])
  let state = slow_cast(plans:, state: cast.new(), at: 1000)
  // The slow spell's cooldown ends at 7000. The row of a press at 2500 acts at 6700.
  let #(state, pressed) = press(plans:, state:, bag: bag_of_holder, at: 2500)
  let #(state, held) = press(plans:, state:, bag: bag_of_slow, at: 6600)
  assert support.writes(effects: held) == []
    && delays_of(effects: held) == [400]
    as "400 ms are left: the press is held until 7000"
  let assert [#(held_timer, _)] = support.started_timers(effects: held)
  let #(state, fired) =
    support.run_timers_until(
      state:,
      effects: pressed,
      from_ms: 2500,
      until_ms: 6700,
    )
  let step = step_at(fired:, at: 6700)
  assert list.contains(support.cancelled_timers(effects: step), held_timer)
    as "the held press's timer is cancelled"
  let assert [#(restarted, 150)] =
    list.filter(support.started_timers(effects: step), fn(started) {
      started.1 == 150
    })
    as "300 ms are left at 6700 and x0.5 is 150: the press waits for the new end"
  let #(_, started) = support.fired(state:, timer: restarted, at: 6850)
  assert is_accepted(effects: started)
    as "the held press starts at the new end, 6850, not at 7000 (the server's choice)"
}

pub fn a_row_that_ends_the_cooldown_arms_the_held_press_for_no_wait_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.0), delay: 4200, duration: 0),
    ])
  let state = slow_cast(plans:, state: cast.new(), at: 1000)
  let #(state, pressed) = press(plans:, state:, bag: bag_of_holder, at: 2500)
  let #(state, _) = press(plans:, state:, bag: bag_of_slow, at: 6600)
  let #(_, fired) =
    support.run_timers_until(
      state:,
      effects: pressed,
      from_ms: 2500,
      until_ms: 6700,
    )
  assert list.contains(delays_of(effects: step_at(fired:, at: 6700)), 0)
    as "a wait of 0 is a timer of 0 ms, so the go's own messages go out before the press starts"
}

pub fn a_held_abilitys_repeat_timer_waits_for_the_new_end_when_a_row_shortens_the_cooldown_test() -> Nil {
  use <- owned_test.run(20_000)
  let plans =
    plans_holding(rows: [
      row(effect_id: 1, operation: NoLonger(0.5), delay: 2000, duration: 0),
    ])
  let #(state, down) =
    support.key_in(
      plans:,
      state: cast.new(),
      bag_index: bag_of_slow,
      held: 1,
      at: 1000,
    )
  let assert [#(go, 1000)] = support.started_timers(effects: down)
  // The go at 2000 starts the cooldown, which ends at 7000: the repeat waits 5000 ms.
  let #(state, went) = support.fired(state:, timer: go, at: 2000)
  let assert [#(repeat, 5000)] = support.started_timers(effects: went)
  // The row of a press at 2500 acts at 4500, when 2500 ms are left: x0.5 is 1250.
  let #(state, pressed) = press(plans:, state:, bag: bag_of_holder, at: 2500)
  let #(state, fired) =
    support.run_timers_until(
      state:,
      effects: pressed,
      from_ms: 2500,
      until_ms: 4500,
    )
  let step = step_at(fired:, at: 4500)
  assert list.contains(support.cancelled_timers(effects: step), repeat)
    as "the repeat timer is cancelled"
  let assert [#(again, 1250)] =
    list.filter(support.started_timers(effects: step), fn(started) {
      started.1 == 1250
    })
    as "the repeat waits for the new end, 5750"
  let #(_, repeated) = support.fired(state:, timer: again, at: 5750)
  assert list.contains(
    support.ids(frames: support.writes(effects: repeated)),
    0x07FF,
  )
    as "the held ability casts again at the new end (cast.hold_repeat)"
}
