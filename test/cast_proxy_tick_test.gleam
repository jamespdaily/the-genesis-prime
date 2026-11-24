//// A Proxy with a tickTime aimed at the caster casts its named spell at each tick, each
//// tick a child cast of its own (`genesis_prime/game/cast`, `genesis_prime/game/cast/tick`),
//// on a clock the test drives. Expected values come from these places, each named at its
//// assertion:
//// - `Spell4Effects.effectType.26.periodic`: the client gives a Proxy no behaviour, so a
////   Proxy with a tickTime casts its spell every tickTime for its durationTime
////   (texts 504979 "generate 1 Psi Point every 1s for 5s", 311216 for Plasma Wall "every
////   0.5s").
//// - Rows 121345 (delay 1, tick 1000, duration 10000, in Spell4 47860, naming 71371) and
////   228473 (tick 500, duration 5000, gate 43748, in Spell4 38787, naming 87477): the
////   schedules planted below are theirs (`ticking.schedule_of`: tick k lands delay plus k
////   times tickTime).
//// - `opcode.0x7ff.root_parent`: a non-zero parent marks a cast no press made, and the
////   root is the pressed spell (`Live.root`).
//// - Spell4 38787's `prerequisiteIdCasterPersistence` 43680 (text 311216, "Removed when you
////   fall below 250 Kinetic Energy"): the persistence ends the cast, here a planted
////   in-combat condition.
//// The planted holder replaces the ability of base 3 (bag index 11); its children are
//// planted spells with no rows of their own.

import cast_support as support
import client_tables
import genesis_prime/game/area
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{type Proxy, type Spell, Proxy, Spell}
import genesis_prime/game/spend
import genesis_prime/game/strike_tell
import genesis_prime/game/ticking.{type Schedule, Schedule, Ticks}
import genesis_prime/message/crowd_control_state
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/message/spell_targets_removed
import genesis_prime/step.{type TimerId}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import genesis_prime/table/loader/store
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import owned_test
import prerequisite_support as prerequisites
import spell_tables
import unitest

const press_ms = 1000

const holder_spell4_id = 90_100

const ability_spell4_id = 90_001

const child_spell4_id = 71_371

/// Row 121345's schedule: delay 1, tickTime 1000, durationTime 10000, ten ticks.
fn engineer_stance() -> Schedule {
  Schedule(delay_ms: 1, tick_ms: 1000, duration_ms: 10_000, count: Ticks(10))
}

/// Row 228473's schedule: tickTime 500, durationTime 5000, ten ticks.
fn plasma_wall() -> Schedule {
  Schedule(delay_ms: 0, tick_ms: 500, duration_ms: 5000, count: Ticks(10))
}

/// A schedule of no delay, a tickTime of 1000 and `count` ticks.
fn every_second(count count: Int) -> Schedule {
  Schedule(
    delay_ms: 0,
    tick_ms: 1000,
    duration_ms: 1000 * count,
    count: Ticks(count),
  )
}

fn child() -> Spell {
  support.child(spell4_id: child_spell4_id, base: child_spell4_id)
}

/// A Proxy aimed at the caster in every phase that casts `named` at each tick of `schedule`.
fn periodic(
  schedule schedule: Schedule,
  condition condition: spell_plan.Condition,
  named named: Spell,
) -> Proxy {
  Proxy(
    ..once(named:),
    effect_id: Spell4EffectsId(121_345),
    condition:,
    period: Some(spell_plan.Periodic(schedule:, persistence: None)),
  )
}

/// A Proxy aimed at the caster that casts `named` at the go.
fn once(named named: Spell) -> Proxy {
  Proxy(
    effect_id: Spell4EffectsId(90_002),
    delay_ms: 0,
    phase_flags: -1,
    condition: spell_plan.Always,
    tag: spend.always,
    target: spell_plan.OnCaster,
    spell: named,
    gains: [],
    period: None,
  )
}

/// A spell that goes at once and holds these Proxies.
fn holding(
  proxies proxies: List(Proxy),
  spell4_id spell4_id: Int,
  base base: Int,
) -> Spell {
  support.with_effects(
    spell: support.child(spell4_id:, base:),
    kinds: list.map(proxies, spell_plan.ProxyEffect),
  )
}

fn holder(proxies proxies: List(Proxy)) -> Spell {
  holding(proxies:, spell4_id: holder_spell4_id, base: 3)
}

/// Mind Burst (Spell4 32809), which spends every Psi Point held: bag index 2 of the planted
/// Esper.
fn mind_burst() -> Spell {
  spell_tables.planted_ability(base: 19_019)
}

fn in_combat() -> Caster {
  support.caster_in_combat(in_combat: True)
}

/// A press of the base 3 ability of `plans` at `press_ms`, its go answered by a round that
/// struck nobody.
fn pressed(
  plans plans: spell_plan.Plans,
  caster caster: Caster,
) -> #(State, List(Effect)) {
  support.press_as(
    plans:,
    state: cast_state.new(),
    caster:,
    bag: support.started_bag_index,
    at: press_ms,
  )
}

/// Every timer the press started and each timer those start, fired on the driven clock up to
/// `until_ms`.
fn ran(
  caster caster: Caster,
  pressed pressed: #(State, List(Effect)),
  until_ms until_ms: Int,
) -> #(State, List(#(Int, List(Effect)))) {
  support.run_timers_until_as(
    caster:,
    state: pressed.0,
    effects: pressed.1,
    from_ms: press_ms,
    until_ms:,
  )
}

pub fn a_go_arms_a_periodic_proxys_first_tick_one_tick_time_after_its_delay_and_the_nodes_end_at_its_life_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: engineer_stance(),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
    ])
  let #(_, effects) = pressed(plans:, caster: support.caster())
  assert list.map(support.started_timers(effects:), fn(started) { started.1 })
    |> list.sort(int.compare)
    == [1001, 10_001]
    as "row 121345: the first tick lands 1001 ms on (delay 1 plus one tick of 1000) and the holder's node ends at its delay plus durationTime, 10001 ms on"
  assert support.started_in(effects:) == []
    as "nothing is cast at the go: the first cast is one tick on (text 504979: 5 Psi Points in 5 s)"
}

pub fn each_tick_starts_the_named_spell_as_a_child_cast_of_its_own_with_the_holder_as_parent_and_its_root_test() -> Nil {
  use <- owned_test.run(5000)
  let ability =
    holding(
      proxies: [
        once(
          named: holder(proxies: [
            periodic(
              schedule: every_second(count: 5),
              condition: spell_plan.Always,
              named: child(),
            ),
          ]),
        ),
      ],
      spell4_id: ability_spell4_id,
      base: 3,
    )
  let #(state, effects) =
    pressed(plans: support.plans_of([ability]), caster: support.caster())
  let #(_, steps) =
    ran(caster: support.caster(), pressed: #(state, effects), until_ms: 3000)
  let held =
    support.starts_of(
      steps: [#(press_ms, effects)],
      spell4_id: holder_spell4_id,
    )
  let assert [#(_, holder_start)] = held
    as "the ability's own Proxy starts the holder at the press"
  assert holder_start.root_spell4_id == ability_spell4_id
    && holder_start.parent_spell4_id == ability_spell4_id
    as "opcode.0x7ff.root_parent: a Proxy's child names the pressed spell as root and the spell whose Proxy fired as parent"
  let ticks = support.starts_of(steps:, spell4_id: child_spell4_id)
  assert support.times_of(starts: ticks) == [2000, 3000]
    as "ticks 1 and 2 of a schedule of one tick a second, counted from the holder's go at the press"
  list.each(ticks, fn(tick) {
    let start = tick.1
    assert start.parent_spell4_id == holder_spell4_id
      as "the holder is the tick child's parent"
    assert start.root_spell4_id == ability_spell4_id
      as "the root is the pressed spell, carried by the holder after its last go (Lingering.root), not the holder's own id"
    assert start.primary_target_unit_id == support.caster().unit_id
      as "a Proxy aimed at the caster casts on the caster"
  })
  let ids = list.map(ticks, fn(tick) { { tick.1 }.cast_id })
  assert list.unique(ids) == ids && !list.contains(ids, holder_start.cast_id)
    as "each tick is a cast of its own with a new cast id"
  let in_last_step =
    list.flat_map(steps, fn(step) {
      case step.0 == 3000 {
        True -> support.cast_lines(frames: support.writes(effects: step.1))
        False -> []
      }
    })
  assert in_last_step
    == [
      "started k1 71371 root 90001 parent 90100",
      "went k1 p0",
      "finished k1",
    ]
    as "the child's own go and finish follow its start as for any child"
}

pub fn a_timed_periodic_proxy_starts_duration_over_tick_time_children_and_the_holder_finishes_after_the_last_test() -> Nil {
  use <- owned_test.run(5000)
  let slow_child =
    Spell(
      ..support.child(spell4_id: 87_477, base: 87_477),
      cast_time_ms: 1000,
      cast_bar: spell_plan.ShowsCastBar,
    )
  let gate = prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
  let plans =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: plasma_wall(),
          condition: spell_plan.GatedOnCaster(gates: [gate]),
          named: slow_child,
        ),
      ]),
    ])
  let #(state, effects) = pressed(plans:, caster: in_combat())
  let holder_id = support.pressed_id(effects:)
  let #(_, steps) =
    ran(caster: in_combat(), pressed: #(state, effects), until_ms: 20_000)
  let children = support.starts_of(steps:, spell4_id: 87_477)
  assert support.times_of(starts: children)
    == [1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000]
    as "row 228473: durationTime 5000 over tickTime 500 is ten children, the tenth 5000 ms after the first possible tick and no eleventh"
  let finishes =
    list.flat_map(steps, fn(step) {
      list.map(
        support.frames_of(
          message_id: spell_finished.message_id,
          effects: step.1,
        ),
        fn(frame) { #(step.0, support.finished_cast_id(frame)) },
      )
    })
  let assert [#(holder_finished_at, _)] =
    list.filter(finishes, fn(finish) { finish.1 == holder_id })
    as "the holder finishes once"
  assert holder_finished_at == 6000
    as "the holder's node ends with the tenth tick's time, and its 0x7fe follows that tick's child in the same step"
  let assert Ok(#(last_start_at, last)) = list.last(children)
  assert last_start_at == 6000
  let assert [#(last_finished_at, _)] =
    list.filter(finishes, fn(finish) { finish.1 == last.cast_id })
  assert last_finished_at > holder_finished_at
    as "a child outlives its holder: StartChild's parent need not be live"
}

/// The persistence is a planted one (Prerequisite type 28, id 903: the caster is in combat),
/// not Plasma Wall's own 43680, so the test reaches `persistence_end` through the caster's
/// combat flag; the ticks it drops are the same rows whatever the prerequisite.
pub fn a_persistence_end_stops_a_periodic_proxys_ticks_test() -> Nil {
  use <- owned_test.run(5000)
  let persisting =
    Spell(
      ..holder(proxies: [
        periodic(
          schedule: plasma_wall(),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
      caster_persistence: Some(
        prerequisites.single(id: 903, condition: #(28, 1, 0, 0)),
      ),
    )
  let #(state, effects) =
    pressed(plans: support.plans_of([persisting]), caster: in_combat())
  let #(state, steps) =
    ran(caster: in_combat(), pressed: #(state, effects), until_ms: 3000)
  assert support.times_of(starts: support.starts_of(
      steps:,
      spell4_id: child_spell4_id,
    ))
    == [1500, 2000, 2500, 3000]
    as "four ticks have landed by 3000"
  assert support.tick_timers(state:) == 1
    as "the fifth tick is armed while the persistence holds"
  let #(state, ended) =
    cast.persisted(
      cast: state,
      caster: support.caster_in_combat(in_combat: False),
      now: support.at(ms: 3100),
    )
  assert support.tick_timers(state:) == 0
    as "text 311216: the cast ends when the persistence fails, and its tick timer is cancelled, so no child follows"
  assert list.length(support.cancelled_timers(effects: ended)) >= 1
  assert support.starts_of(steps: [#(3100, ended)], spell4_id: child_spell4_id)
    == []
  // An open row (no durationTime): its persistence ends the cast the same way, and no node's
  // end would.
  let open_persisting =
    Spell(
      ..holder(proxies: [
        periodic(
          schedule: support.open_schedule(delay_ms: 0, tick_ms: 500),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
      caster_persistence: Some(
        prerequisites.single(id: 903, condition: #(28, 1, 0, 0)),
      ),
    )
  let #(open_state, open_effects) =
    pressed(plans: support.plans_of([open_persisting]), caster: in_combat())
  let #(open_state, open_steps) =
    ran(
      caster: in_combat(),
      pressed: #(open_state, open_effects),
      until_ms: 3000,
    )
  assert support.times_of(starts: support.starts_of(
      steps: open_steps,
      spell4_id: child_spell4_id,
    ))
    == [1500, 2000, 2500, 3000]
    as "four ticks have landed by 3000"
  assert support.tick_timers(state: open_state) == 1
    as "the fifth is armed while the persistence holds"
  let #(open_state, open_ended) =
    cast.persisted(
      cast: open_state,
      caster: support.caster_in_combat(in_combat: False),
      now: support.at(ms: 3100),
    )
  assert support.tick_timers(state: open_state) == 0
    && dict.size(open_state.lingering) + dict.size(open_state.casts) == 0
    as "the cast ends when the persistence fails: its tick timer is cancelled and nothing lingers"
  assert support.starts_of(
      steps: [#(3100, open_ended)],
      spell4_id: child_spell4_id,
    )
    == []
}

pub fn a_caster_gate_is_read_again_at_each_tick_and_a_failing_tick_starts_no_child_test() -> Nil {
  use <- owned_test.run(5000)
  let gate = prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
  let plans =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: every_second(count: 3),
          condition: spell_plan.GatedOnCaster(gates: [gate]),
          named: child(),
        ),
      ]),
    ])
  let #(state, effects) = pressed(plans:, caster: in_combat())
  let #(_, fired, _) =
    support.run_timers_scripted(
      caster: in_combat(),
      state:,
      effects:,
      from_ms: press_ms,
      struck: [],
      until_ms: None,
      before: fn(due, caster) {
        cast_state.Caster(..caster, in_combat: due != 3000)
      },
      leaves_open: fn(_) { False },
    )
  let steps = list.map(fired, fn(step) { #(step.at_ms, step.effects) })
  assert support.times_of(starts: support.starts_of(
      steps:,
      spell4_id: child_spell4_id,
    ))
    == [2000, 4000]
    as "the gate (in combat) passes at ticks 1 and 3 and fails at tick 2, which starts no child; the ticks go on"
  assert list.flat_map(steps, fn(step) { support.debug_lines(effects: step.1) })
    == []
    as "a gate that fails is the client's answer, not a gap"
  let chance = prerequisites.single(id: 4585, condition: #(37, 6, 0, 50))
  let rolling =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: every_second(count: 2),
          condition: spell_plan.GatedOnCaster(gates: [chance]),
          named: child(),
        ),
      ]),
    ])
  let #(state, raw) =
    support.pressed_raw_in(
      plans: rolling,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: support.started_bag_index,
      target: 0,
      at: press_ms,
    )
  let #(state, go) =
    support.answered_as(
      caster: support.caster(),
      state:,
      effects: raw,
      at: press_ms,
      struck: [],
      rolls: [50],
    )
  let #(_, steps) =
    ran(caster: support.caster(), pressed: #(state, go), until_ms: 3000)
  assert support.starts_of(steps:, spell4_id: child_spell4_id) == []
    as "a type 37 gate needs a roll and a tick draws none: no child"
  let lines =
    list.flat_map(steps, fn(step) { support.debug_lines(effects: step.1) })
  assert list.length(lines) == 2
  assert list.all(lines, fn(line) {
    string.contains(line, "Spell4 71371")
    && string.contains(line, "prerequisite 4585")
    && string.contains(line, "of type 37")
  })
    as "each tick says it cannot tell, naming the child, the prerequisite and its type"
}

pub fn a_periodic_proxy_whose_caster_gate_fails_at_the_go_still_arms_its_ticks_and_a_tick_whose_gate_passes_starts_its_child_test() -> Nil {
  use <- owned_test.run(5000)
  // The gate is that the caster is in combat (Prerequisite type 28, id 903), failing at the go
  // and holding from the second tick, as Plasma Wall's 43748 (not under Overdrive 42908) does
  // when Overdrive ends while the wall stands.
  let gate = prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
  let plans =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: every_second(count: 3),
          condition: spell_plan.GatedOnCaster(gates: [gate]),
          named: child(),
        ),
      ]),
    ])
  let #(state, effects) = pressed(plans:, caster: support.caster())
  assert support.tick_timers(state:) == 1
    as "the go armed the first tick although the gate fails at the go"
  let #(_, fired, _) =
    support.run_timers_scripted(
      caster: support.caster(),
      state:,
      effects:,
      from_ms: press_ms,
      struck: [],
      until_ms: None,
      before: fn(due, caster) {
        cast_state.Caster(..caster, in_combat: due >= press_ms + 2000)
      },
      leaves_open: fn(_) { False },
    )
  let steps = list.map(fired, fn(step) { #(step.at_ms, step.effects) })
  assert support.times_of(starts: support.starts_of(
      steps:,
      spell4_id: child_spell4_id,
    ))
    == [press_ms + 2000, press_ms + 3000]
    as "tick 1 reads the gate failing and starts no child; ticks 2 and 3 read it passing and start one each"
  assert list.flat_map(steps, fn(step) { support.debug_lines(effects: step.1) })
    == []
    as "a gate that fails is the client's answer, not a gap"
}

pub fn the_children_of_a_tick_count_no_quest_objective_and_hold_the_items_value_test() -> Nil {
  use <- owned_test.run(5000)
  let live_child =
    Spell(..child(), cast_time_ms: 5000, cast_bar: spell_plan.ShowsCastBar)
  let held_child =
    Spell(..support.child(spell4_id: 71_372, base: 71_372), cast_time_ms: 5000)
  let plans =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: every_second(count: 2),
          condition: spell_plan.Always,
          named: live_child,
        ),
        once(named: held_child),
      ]),
    ])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: support.started_bag_index,
      target: 0,
      at: press_ms,
    )
  // The press is the use of an item and counts a quest objective: the cast the press made
  // is of that kind before its go.
  let item = cast_state.Item(item_level: 5, passed_in: 12.0)
  let with = cast_state.WithCast(spell4_id: 12_345, target: None)
  let state =
    cast_state.State(
      ..state,
      casts: dict.map_values(state.casts, fn(_, live) {
        cast_state.Live(..live, pressed: Some(item), counted_with: with)
      }),
    )
  let #(state, go) =
    support.answered_as(
      caster: support.caster(),
      state:,
      effects: raw,
      at: press_ms,
      struck: [],
      rolls: [],
    )
  let #(state, _) =
    ran(caster: support.caster(), pressed: #(state, go), until_ms: 2000)
  let lives = dict.values(state.casts)
  let assert Ok(from_go) =
    list.find(lives, fn(live) { live.spell.spell4_id.value == 71_372 })
    as "the Proxy that casts at the go started its child, live for its cast time"
  assert from_go.pressed == Some(item) && from_go.counted_with == with
    as "a child a go starts takes the item's use and the objective count of its parent (`handed_down`)"
  let assert Ok(from_tick) =
    list.find(lives, fn(live) { live.spell.spell4_id.value == child_spell4_id })
    as "the tick started its child, live for its cast time"
  assert from_tick.pressed == Some(item)
    as "a tick's child reads the item's value the holder's cast was pressed from, as the child a go starts does"
  assert from_tick.counted_with == cast_state.WithNothing
    as "and counts no quest objective"
}

pub fn a_child_that_holds_its_own_periodic_proxy_ticks_on_its_own_cast_test() -> Nil {
  use <- owned_test.run(5000)
  let grandchild = support.child(spell4_id: 71_373, base: 71_373)
  // Each child ticks 1500 ms after its start (delay 500 plus one tick), between the holder's
  // own ticks, three times.
  let child_schedule =
    Schedule(delay_ms: 500, tick_ms: 1000, duration_ms: 3500, count: Ticks(3))
  let first_ticks = fn(stack) {
    let middle =
      Spell(
        ..holding(
          proxies: [
            periodic(
              schedule: child_schedule,
              condition: spell_plan.Always,
              named: grandchild,
            ),
          ],
          spell4_id: child_spell4_id,
          base: child_spell4_id,
        ),
        stack:,
      )
    let plans =
      support.plans_of([
        holder(proxies: [
          periodic(
            schedule: every_second(count: 3),
            condition: spell_plan.Always,
            named: middle,
          ),
        ]),
      ])
    let #(state, effects) = pressed(plans:, caster: support.caster())
    let #(_, steps) =
      ran(
        caster: support.caster(),
        pressed: #(state, effects),
        until_ms: 20_000,
      )
    support.times_of(starts: support.starts_of(steps:, spell4_id: 71_373))
  }
  assert first_ticks(lasting.Stack(group_id: 1, cap: 10))
    == [3500, 4500, 4500, 5500, 5500, 5500, 6500, 6500, 7500]
    as "children start at 2000, 3000 and 4000 and each ticks at 1500, 2500 and 3500 ms after its start: one child ticks once at 3500, two at 4500 and 5500, and so on, each on its own cast"
  assert first_ticks(lasting.Stack(group_id: 1, cap: 1)) == [5500, 6500, 7500]
    as "at a cap of one each new child pushes the one before off the caster before its first tick: only the last child's ticks come, the others' cancelled with their nodes"
}

pub fn a_proxy_with_no_tick_time_that_names_its_spell_in_data_bits01_starts_its_child_once_at_the_go_test() -> Nil {
  use <- owned_test.run(60_000)
  // Mental Boon's row 76609 names 33258 in dataBits01 and has no tickTime; its targetFlags
  // 5 in a spell that hits no foes start the child on the caster.
  let spell = spell_tables.client_spell(spell4_id: 36_562)
  let plans =
    support.plans_of([Spell(..spell, spell4_base_id: Spell4BaseId(3))])
  let #(state, effects) = pressed(plans:, caster: support.caster())
  let #(_, steps) =
    ran(caster: support.caster(), pressed: #(state, effects), until_ms: 20_000)
  let starts =
    support.starts_of(steps: [#(press_ms, effects), ..steps], spell4_id: 33_258)
  assert support.times_of(starts:) == [press_ms]
    as "text 245408: the heal sits only in 33258, which only the tick-0 Proxy names, so it is cast once, at the go and not at a tick"
  let assert [#(_, start)] = starts
  assert start.parent_spell4_id == 36_562
}

pub fn a_periodic_proxy_gives_the_caster_node_its_life_and_lists_no_effect_in_the_0x7f4_test() -> Nil {
  use <- owned_test.run(5000)
  let proxy =
    periodic(
      schedule: engineer_stance(),
      condition: spell_plan.Always,
      named: child(),
    )
  let caster = support.caster()
  let aimed =
    cast_state.Aimed(
      units: [],
      reached: [],
      reach_logs: [],
      controls: [],
      restrictions: [],
      ticking: support.proxies_ticking_on_the_caster(proxies: [proxy], caster:),
      rolls_left: [],
    )
  assert cast_tick.nodes_aimed(aimed:) == [caster.unit_id]
    as "the caster holds a node for the periodic Proxy"
  let assert Ok(node) =
    cast_tick.node_of(
      spell: holder(proxies: [proxy]),
      held: None,
      aimed:,
      unit_id: caster.unit_id,
      started_ms: press_ms,
      now_ms: press_ms,
    )
  assert node.life == lasting.EndsAt(ms: press_ms + 1 + 10_000)
    as "the node lives the row's delay plus durationTime (`opcode.0x7f4.effect_time`)"
  assert node.effects != []
    && list.all(node.effects, fn(effect) {
      case effect {
        lasting.LifeOnly(..) -> True
        lasting.Listed(..) -> False
      }
    })
    as "a Proxy row gives the node its life only, listed to no viewer: the client builds the plain effect for type 26"
  let #(_, effects) =
    pressed(
      plans: support.plans_of([holder(proxies: [proxy])]),
      caster: support.caster(),
    )
  let goes =
    support.frames_of(message_id: spell_go.message_id, effects:)
    |> list.map(fn(frame) {
      let assert Ok(go) = spell_go.decode(frame.body)
        as "a 0x7f4 the rule wrote decodes"
      go
    })
  assert goes != []
    && list.all(goes, fn(go) {
      list.all(go.targets, fn(target) { target.effects == [] })
    })
    as "the go's 0x7f4 lists no effect for the Proxy row (`opcode.0x7f4.effect_time`)"
}

pub fn a_proxy_under_a_phase_that_has_not_gone_or_whose_tag_does_not_hold_arms_no_tick_test() -> Nil {
  use <- owned_test.run(5000)
  // A Proxy of phase 0 only in a holder of two gos, 1000 ms apart: the go of phase 1 does
  // not arm it again, so its ticks keep the times the first go gave them.
  let first_phase =
    Proxy(
      ..periodic(
        schedule: every_second(count: 3),
        condition: spell_plan.Always,
        named: child(),
      ),
      phase_flags: 1,
    )
  let twice =
    Spell(..holder(proxies: [first_phase]), phase_delays_ms: [0, 1000])
  let #(state, effects) =
    pressed(plans: support.plans_of([twice]), caster: support.caster())
  let #(_, steps) =
    ran(caster: support.caster(), pressed: #(state, effects), until_ms: 20_000)
  assert support.times_of(starts: support.starts_of(
      steps:,
      spell4_id: child_spell4_id,
    ))
    == [2000, 3000, 4000]
    as "armed at the go of phase 0, counted from it; the go of phase 1, at 2000, arms nothing (`cast_gate.proxies_with_targets` is the filter)"
  // Mind Burst spends every point held: n is the points spent above the base cost of 1. A
  // Proxy whose tag is emmComparison 0 emmValue 4 (rows like 135961) holds at 5 points, one
  // of comparison 1 value 2 (230116) at 3 or more.
  let burst = fn(tag) {
    Proxy(
      ..periodic(
        schedule: every_second(count: 3),
        condition: spell_plan.Always,
        named: child(),
      ),
      tag:,
    )
  }
  let mind_burst =
    support.with_effects(spell: mind_burst(), kinds: [
      spell_plan.ProxyEffect(burst(spend.EqualTo(value: 4))),
      spell_plan.ProxyEffect(
        Proxy(
          ..burst(spend.AtLeast(value: 2)),
          effect_id: Spell4EffectsId(230_116),
        ),
      ),
    ])
  let armed = fn(points) {
    let #(state, _) =
      support.press_as(
        plans: support.plans_with(spell: mind_burst),
        state: cast_state.new(),
        caster: support.caster_holding(resources: support.holding(
          class_id: 3,
          value: int.to_float(points),
        )),
        bag: 2,
        at: press_ms,
      )
    support.tick_timers(state:)
  }
  assert list.map([1, 2, 3, 4, 5], armed) == [0, 0, 1, 1, 2]
    as "n is points - 1: the tag of 4 holds at 5 points, the tag of at least 2 at 3 points and more; a Proxy whose tag does not hold arms no tick"
}

pub fn a_tick_whose_child_the_cast_rule_refuses_logs_and_the_ticks_go_on_test() -> Nil {
  use <- owned_test.run(5000)
  // The named spell's caster condition needs a dead caster (`Spell4.spell4ConditionsIdCaster`,
  // `spell_plan.refused_life`), and the caster lives.
  let needs_the_dead = Spell(..child(), caster_death: spell_plan.MustBeDead)
  let plans =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: every_second(count: 3),
          condition: spell_plan.Always,
          named: needs_the_dead,
        ),
      ]),
    ])
  let #(state, effects) = pressed(plans:, caster: support.caster())
  let #(_, steps) =
    ran(caster: support.caster(), pressed: #(state, effects), until_ms: 20_000)
  assert support.starts_of(steps:, spell4_id: child_spell4_id) == []
    as "no child is cast for a caster the spell refuses"
  let lines =
    list.flat_map(steps, fn(step) { support.debug_lines(effects: step.1) })
  assert list.length(lines) == 3
    as "each of the three ticks, which go on, leaves one debug line"
  assert list.all(lines, fn(line) {
    string.contains(line, "the periodic Proxy effect 121345 of Spell4")
    && string.contains(line, "does not cast Spell4 71371")
    && string.contains(line, "caster that is alive")
  })
}

/// The ids of the state's timers that are a tick of a periodic row.
fn tick_timer_ids(state state: State) -> List(TimerId) {
  support.timers_matching(state:, matching: fn(due) {
    case due {
      cast_state.Tick(..) -> True
      _ -> False
    }
  })
}

/// How many of the state's timers end a node.
fn node_end_timers(state state: State) -> Int {
  list.length(
    support.timers_matching(state:, matching: fn(due) {
      case due {
        cast_state.NodesEnd(..) -> True
        _ -> False
      }
    }),
  )
}

pub fn an_open_periodic_proxy_ticks_each_tick_time_with_one_timer_and_no_nodes_end_and_a_late_timer_fires_each_due_tick_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  // Row 210304's shape: delay 1000, tickTime 1000, flags bit 2.
  let plans =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: support.open_schedule(delay_ms: 1000, tick_ms: 1000),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
    ])
  let #(state, effects) = pressed(plans:, caster: support.caster())
  assert list.map(support.started_timers(effects:), fn(started) { started.1 })
    == [2000]
    as "the go arms the first tick alone, delay plus one tick time on: no end is armed for a node that lasts until removed"
  let #(state, steps) =
    ran(
      caster: support.caster(),
      pressed: #(state, effects),
      until_ms: press_ms + 60_000,
    )
  assert support.times_of(starts: support.starts_of(
      steps:,
      spell4_id: child_spell4_id,
    ))
    == int.range(from: 60, to: 1, with: [], run: fn(times, second) {
      [press_ms + second * 1000, ..times]
    })
    as "a child at the delay plus each tick time after the go, up to 60 s on"
  assert dict.size(state.lingering) + dict.size(state.casts) == 1
    as "the cast lingers with its node"
  // The run is replayed to each tick's time: after every step the holder's row is the only
  // tick timer and no node's end is armed, since the node lasts until removed.
  list.each(int.range(from: 60, to: 0, with: [], run: list.prepend), fn(second) {
    let #(at_step, _) =
      ran(
        caster: support.caster(),
        pressed: pressed(plans:, caster: support.caster()),
        until_ms: press_ms + second * 1000,
      )
    assert support.tick_timers(state: at_step) == 1
      as "one timer for the holder's row, re-armed one tick at a time"
    assert node_end_timers(state: at_step) == 0
      as "no NodesEnd timer: the node lasts until removed"
  })
  // The timer for tick 3 (due press + 4000) is handled 2500 ms late, at press + 6500: ticks
  // 3, 4 and 5 (due at press + 4000, 5000 and 6000) each start a child, then tick 6 is armed.
  let #(early, _) =
    ran(
      caster: support.caster(),
      pressed: pressed(plans:, caster: support.caster()),
      until_ms: press_ms + 3000,
    )
  let assert [timer] = tick_timer_ids(state: early)
    as "tick 3's timer is the one armed after tick 2 landed"
  let #(_, late) =
    support.fired_raw_as(
      caster: support.caster(),
      state: early,
      timer:,
      at: press_ms + 6500,
    )
  assert list.length(support.started_in(effects: late)) == 3
    as "ticks 3, 4 and 5 are due by the late firing: three children, and tick 6, due 7000 ms after the press, is not"
  assert list.map(support.started_timers(effects: late), fn(started) {
      started.1
    })
    == [500]
    as "the next tick is armed 500 ms on, never before now"
  // Two open rows on one holder make the order of the due ticks visible: row 121345 (child
  // 71371) ticks 2000, 3000, ... after the go and row 121346 (child 71372) 1500, 3000, 4500,
  // ... 6000. A timer handled at 6500 lands every tick due by then, earliest first and at
  // one time the lower row id first.
  let other_child = support.child(spell4_id: 71_372, base: 71_372)
  let two_rows =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: support.open_schedule(delay_ms: 1000, tick_ms: 1000),
          condition: spell_plan.Always,
          named: child(),
        ),
        Proxy(
          ..periodic(
            schedule: support.open_schedule(delay_ms: 0, tick_ms: 1500),
            condition: spell_plan.Always,
            named: other_child,
          ),
          effect_id: Spell4EffectsId(121_346),
        ),
      ]),
    ])
  let #(two_pressed, _) =
    ran(
      caster: support.caster(),
      pressed: pressed(plans: two_rows, caster: support.caster()),
      until_ms: press_ms + 1000,
    )
  let assert [first_timer, ..] = tick_timer_ids(state: two_pressed)
    as "the holder's rows have armed ticks"
  let #(_, late_two) =
    support.fired_raw_as(
      caster: support.caster(),
      state: two_pressed,
      timer: first_timer,
      at: press_ms + 6500,
    )
  assert list.map(support.started_in(effects: late_two), fn(start) {
      start.spell4_id
    })
    == [
      71_372,
      71_371,
      71_371,
      71_372,
      71_371,
      71_372,
      71_371,
      71_371,
      71_372,
    ]
    as "due at 1500 (row 121346), 2000, 3000 (121345 then 121346), 4000, 4500, 5000, 6000 (121345 then 121346): each tick in the order of its due time"
}

pub fn an_open_periodic_proxy_under_an_aura_stops_at_the_auras_end_and_the_node_end_writes_the_0x7fe_alone_test() -> Nil {
  use <- owned_test.run(5000)
  // An aura of 2500 ms started at the press (Spell4.spellDuration, `0x1407180c0`) holding a
  // Proxy of tickTime 1000 that lasts until removed: its node ends at the press plus 2500.
  let aura =
    Spell(
      ..holder(proxies: [
        periodic(
          schedule: support.open_schedule(delay_ms: 0, tick_ms: 1000),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
      aura_ms: Some(2500),
    )
  let #(state, effects) =
    pressed(plans: support.plans_of([aura]), caster: support.caster())
  let holder_id = support.pressed_id(effects:)
  let #(state, steps) =
    ran(
      caster: support.caster(),
      pressed: #(state, effects),
      until_ms: press_ms + 20_000,
    )
  assert support.times_of(starts: support.starts_of(
      steps:,
      spell4_id: child_spell4_id,
    ))
    == [press_ms + 1000, press_ms + 2000]
    as "the ticks at 1000 and 2000 after the go land within the aura and none at 3000"
  let assert [#(node_end_at, node_end)] =
    list.filter(steps, fn(step) {
      list.contains(
        support.finished_ids(support.writes(effects: step.1)),
        holder_id,
      )
    })
    as "the cast finishes once"
  assert node_end_at == press_ms + 2500
    as "the node ends with the aura, 2500 ms after the cast's start"
  assert list.map(support.writes(effects: node_end), fn(frame) {
      frame.message_id
    })
    == [spell_finished.message_id]
    as "the node on the caster ends with the 0x7fe alone: no 0x811, the caster's own node is not told removed"
  assert dict.size(state.casts) + dict.size(state.lingering) == 0
    && dict.size(state.timers) == 0
    as "nothing is left of the cast or its timers"
}

pub fn each_stack_of_a_child_that_holds_an_open_proxy_keeps_one_tick_timer_and_the_holders_own_is_counted_test() -> Nil {
  use <- owned_test.run(5000)
  // Kinetic Rage's shape: a holder with a Proxy that casts a stack-capped child at each tick
  // (Spell4StackGroup 1916, cap 100), the child holding a Proxy of tickTime 250 that lasts
  // until removed (row 210337).
  let grandchild = support.child(spell4_id: 71_373, base: 71_373)
  let stack =
    Spell(
      ..holding(
        proxies: [
          periodic(
            schedule: support.open_schedule(delay_ms: 0, tick_ms: 250),
            condition: spell_plan.Always,
            named: grandchild,
          ),
        ],
        spell4_id: child_spell4_id,
        base: child_spell4_id,
      ),
      stack: lasting.Stack(group_id: 1916, cap: 100),
    )
  let plans =
    support.plans_of([
      holder(proxies: [
        periodic(
          schedule: every_second(count: 5),
          condition: spell_plan.Always,
          named: stack,
        ),
      ]),
    ])
  let #(state, effects) = pressed(plans:, caster: support.caster())
  let ran_to = fn(until_ms) {
    ran(
      caster: support.caster(),
      pressed: #(state, effects),
      until_ms: press_ms + until_ms,
    )
  }
  let #(at_2500, _) = ran_to(2500)
  assert support.tick_timers(state: at_2500) == 3
    as "the holder's own timer and the two stacks'"
  let #(at_5001, steps) = ran_to(5001)
  assert support.tick_timers(state: at_5001) == 5
    as "the holder's fifth tick has landed and its timer is gone: five stacks hold five"
  let #(_, to_6000) = ran_to(6000)
  let in_the_last_second =
    list.filter(support.starts_of(steps: to_6000, spell4_id: 71_373), fn(start) {
      start.0 > press_ms + 5000
    })
  assert list.length(in_the_last_second) == 5 * 4
    as "each of the five live stacks starts four children in a second (tickTime 250)"
  assert list.length(support.starts_of(steps:, spell4_id: child_spell4_id)) == 5
    as "the holder cast one stack at each of its five ticks"
}

// ---- a periodic Proxy aimed at the area ----
//
// The scenes plant a field: a holder of no cast time that a once Proxy of the pressed
// ability starts on the caster, holding a periodic Proxy aimed at each struck unit. The
// connection's answer to each ask is a script of the units found at each tick
// (`cast_support.run_timers_finding` splices the answer's effects in place of the ask, as
// `connection/casting.carried_out` does). Expected values: texts 574032 and 306769 ("apply
// ... to foes inside the field every Ns": the units are found at each tick), and the rule's
// own doc comments.

/// A Proxy aimed at each struck unit, in every phase, that casts `named` at each tick of
/// `schedule`.
fn area_periodic(
  schedule schedule: Schedule,
  condition condition: spell_plan.Condition,
  named named: Spell,
) -> Proxy {
  Proxy(
    ..periodic(schedule:, condition:, named:),
    target: spell_plan.OnEachStruck,
  )
}

/// Four ticks 500 ms apart: at 500, 1000, 1500 and 2000 after the go.
fn four_ticks() -> Schedule {
  Schedule(delay_ms: 0, tick_ms: 500, duration_ms: 2000, count: Ticks(4))
}

/// The pressed ability, whose once Proxy starts the holder of `proxies` on the caster.
fn ability_over(proxies proxies: List(Proxy)) -> Spell {
  holding(
    proxies: [once(named: holder(proxies:))],
    spell4_id: ability_spell4_id,
    base: 3,
  )
}

/// The answer of the connection to an ask: the units listed for its tick, none for a tick the
/// script does not name.
fn found_in(
  script script: List(#(Int, List(Int))),
) -> fn(cast_state.ProxyTickAsked) -> List(Int) {
  fn(asked: cast_state.ProxyTickAsked) {
    list.key_find(script, asked.tick)
    |> result.unwrap([])
  }
}

/// The step the effects belong to, as time and effects.
fn as_steps(fired fired: List(support.Fired)) -> List(#(Int, List(Effect))) {
  list.map(fired, fn(step) { #(step.at_ms, step.effects) })
}

/// The pose of a caster's place.
fn pose_of(caster caster: Caster) -> area.Pose {
  area.pose_of(place: caster.place)
}

/// The caster standing 50 m from where `support.caster()` stands.
fn moved_caster() -> Caster {
  support.standing_at(
    caster: support.caster(),
    x: 4655.65,
    y: -7.571,
    z: 494.996,
  )
}

pub fn a_periodic_proxy_aimed_at_the_area_asks_for_its_units_at_each_tick_and_starts_a_child_on_each_with_that_unit_as_primary_target_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      ability_over(proxies: [
        area_periodic(
          schedule: four_ticks(),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
    ])
  let #(state, effects) = pressed(plans:, caster: support.caster())
  let assert [#(_, holder_start)] =
    support.starts_of(
      steps: [#(press_ms, effects)],
      spell4_id: holder_spell4_id,
    )
    as "the ability's Proxy starts the holder at the press"
  assert list.map(support.started_in(effects:), fn(start) { start.spell4_id })
    == [holder_spell4_id]
    as "nothing is cast at the go: the first units are found one tick on"
  let run = fn(until_ms) {
    support.run_timers_finding(
      caster: support.caster(),
      state:,
      effects:,
      from_ms: press_ms,
      until_ms:,
      units: dict.new(),
      found_by: found_in(script: [#(1, [21, 22]), #(2, [23])]),
    ).1
  }
  assert run(1499) == [] as "no ask before the first tick, 500 ms after the go"
  let fired = run(2000)
  let assert [first, second] = fired
    as "ticks 1 and 2 land at 1500 and 2000 and ask once each"
  assert first.at_ms == 1500 && second.at_ms == 2000
  assert first.found
    == [
      cast_state.ProxyTickAsked(
        cast_id: holder_start.cast_id,
        spell4_id: id.Spell4Id(holder_spell4_id),
        effect_id: Spell4EffectsId(121_345),
        phase: 0,
        primary_target: support.caster().unit_id,
        started_at: pose_of(caster: support.caster()),
        primary_pose: None,
        go: 1,
        tick: 1,
      ),
    ]
    as "the ask names the cast, the holder, the row, the phase of the go that armed it, the caster as the unit the row ticks on, the pose the cast started at, tick 1 and go 1"
  assert { second.found |> list.map(fn(asked) { asked.tick }) } == [2]
    as "the second ask is tick 2 of the same go"
  let children =
    support.starts_of(steps: as_steps(fired:), spell4_id: child_spell4_id)
  assert support.times_of(starts: children) == [1500, 1500, 2000]
    as "a child for each unit found, at the tick that found it"
  assert list.map(children, fn(child) { { child.1 }.primary_target_unit_id })
    == [21, 22, 23]
    as "each child is made on its unit as primary target, in the order the units were found"
  list.each(children, fn(child) {
    let start = child.1
    assert start.parent_spell4_id == holder_spell4_id
      && start.root_spell4_id == ability_spell4_id
      as "opcode.0x7ff.root_parent: the holder is the parent and the pressed spell the root, carried by the holder"
    assert start.caster_item_level == 0
      as "opcode.0x7ff.caster_item_level: a press of no item tells 0"
  })
  // The same press as the use of an item: each child the tick starts tells the item's level, the
  // one its holder's cast was pressed from (`handed_down`).
  let item = cast_state.Item(item_level: 5, passed_in: 12.0)
  let #(pressed_state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast_state.new(),
      caster: support.caster(),
      bag_index: support.started_bag_index,
      target: 0,
      at: press_ms,
    )
  let #(item_state, item_effects) =
    support.answered_as(
      caster: support.caster(),
      state: cast_state.State(
        ..pressed_state,
        casts: dict.map_values(pressed_state.casts, fn(_, live) {
          cast_state.Live(..live, pressed: Some(item))
        }),
      ),
      effects: raw,
      at: press_ms,
      struck: [],
      rolls: [],
    )
  let from_item =
    support.run_timers_finding(
      caster: support.caster(),
      state: item_state,
      effects: item_effects,
      from_ms: press_ms,
      until_ms: 2000,
      units: dict.new(),
      found_by: found_in(script: [#(1, [21, 22]), #(2, [23])]),
    ).1
  let item_children =
    support.starts_of(
      steps: as_steps(fired: from_item),
      spell4_id: child_spell4_id,
    )
  assert list.map(item_children, fn(child) {
      { child.1 }.primary_target_unit_id
    })
    == [21, 22, 23]
    as "the setup: each unit found has a child"
  assert list.map(item_children, fn(child) { { child.1 }.caster_item_level })
    == [5, 5, 5]
    as "opcode.0x7ff.caster_item_level: each child of the area tick tells the item's level 5"
  let ids = list.map(children, fn(child) { { child.1 }.cast_id })
  assert list.unique(ids) == ids && !list.contains(ids, holder_start.cast_id)
    as "each child is a cast of its own"
  assert support.cast_lines(frames: support.writes(effects: first.effects))
    == [
      "started k1 71371 root 90001 parent 90100",
      "went k1 p0",
      "finished k1",
      "started k2 71371 root 90001 parent 90100",
      "went k2 p0",
      "finished k2",
    ]
    as "each child's own go and finish follow its start, as for any child"
}

pub fn a_tick_that_finds_nobody_starts_no_child_closes_its_round_and_the_next_tick_is_armed_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      ability_over(proxies: [
        area_periodic(
          schedule: four_ticks(),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
    ])
  let #(state, effects) = pressed(plans:, caster: support.caster())
  let holder_id =
    support.starts_of(
      steps: [#(press_ms, effects)],
      spell4_id: holder_spell4_id,
    )
    |> list.map(fn(start) { { start.1 }.cast_id })
  let assert [holder_id] = holder_id as "the holder started once"
  let run = fn(until_ms) {
    support.run_timers_finding(
      caster: support.caster(),
      state:,
      effects:,
      from_ms: press_ms,
      until_ms:,
      units: dict.new(),
      found_by: found_in(script: []),
    )
  }
  let #(after_tick_2, fired) = run(2000)
  assert support.starts_of(steps: as_steps(fired:), spell4_id: child_spell4_id)
    == []
    as "nobody inside: no child starts"
  let assert Ok(holder) =
    cast_state.holder_of(cast: after_tick_2, cast_id: holder_id)
  let assert Ok(row) =
    dict.get(
      holder.ticking,
      cast_state.tick_key(
        unit_id: support.caster().unit_id,
        effect_id: Spell4EffectsId(121_345),
      ),
    )
    as "the row is still held"
  assert cast_state.ticking_open(row:) == 0
    && cast_state.ticking_tick(row:) == 2
    as "the round the ask opened is closed, so a node end that follows is not held"
  assert support.tick_timers(state: after_tick_2) == 1
    as "the next tick is armed"
  let #(after_tick_4, steps) = run(3000)
  assert support.tick_timers(state: after_tick_4) == 0
    as "the last tick arms none"
  assert list.flat_map(steps, fn(step) {
      support.finished_ids(support.writes(effects: step.effects))
    })
    == [holder_id]
    as "the node end at the last tick's time finishes the holder: no round is left holding it"
}

pub fn the_ask_of_a_lingering_field_carries_the_pose_the_cast_started_at_and_the_phase_it_was_armed_in_test() -> Nil {
  use <- owned_test.run(5000)
  // The first tick's ask after the go of a spell pressed by `press_caster` whose gos struck
  // `struck_units`, answered with these poses at the go, and fired by `tick_caster`.
  let first_ask = fn(
    spell: Spell,
    press_caster: Caster,
    tick_caster: Caster,
    struck_units: List(Int),
    poses: dict.Dict(Int, area.Pose),
  ) {
    let #(state, raw) =
      support.pressed_raw_in(
        plans: support.plans_of([spell]),
        state: cast_state.new(),
        caster: press_caster,
        bag_index: support.started_bag_index,
        target: 0,
        at: press_ms,
      )
    let #(state, _) =
      support.answered_posed(
        caster: press_caster,
        state:,
        effects: raw,
        at: press_ms,
        struck: support.hits(struck_units),
        rolls: [],
        poses:,
      )
    let assert [timer, ..] = tick_timer_ids(state:) as "the go armed a tick"
    let #(_, ticked) =
      support.fired_raw_as(
        caster: tick_caster,
        state:,
        timer:,
        at: press_ms + 500,
      )
    #(support.proxy_tick_asks(effects: ticked), state)
  }
  let field =
    Spell(
      ..holder(proxies: [
        area_periodic(
          schedule: support.open_schedule(delay_ms: 0, tick_ms: 500),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
      aura_ms: Some(5000),
    )
  // On the caster, which has walked 50 m away before the tick.
  let #(asks, state) =
    first_ask(field, support.caster(), moved_caster(), [], dict.new())
  let assert [on_the_caster] = asks as "one ask for the one row"
  assert on_the_caster.started_at == pose_of(caster: support.caster())
    && on_the_caster.started_at != pose_of(caster: moved_caster())
    as "the ask holds the pose the cast started at, not the caster's pose at the tick (`Live.started_at`, 0x14053a210.held_position)"
  assert on_the_caster.primary_pose == None && on_the_caster.phase == 0
    as "a field on the caster holds no primary pose and the phase of the go that armed it"
  assert dict.size(state.lingering) == 1 && dict.size(state.casts) == 0
    as "the field has finished its go and lingers: the row, not the holder, carries the pose"
  // On a struck creature, whose pose at the go the round's answer gave.
  let at_the_go = area.Pose(at: area.Point(x: 12.0, z: -4.0), yaw: 1.0)
  let on_each_struck =
    holding(
      proxies: [Proxy(..once(named: field), target: spell_plan.OnEachStruck)],
      spell4_id: ability_spell4_id,
      base: 3,
    )
  let #(asks, _) =
    first_ask(
      on_each_struck,
      support.caster(),
      support.caster(),
      [21],
      dict.from_list([#(21, at_the_go)]),
    )
  let assert [on_the_creature] = asks as "one ask for the one row"
  assert on_the_creature.primary_target == 21
    && on_the_creature.primary_pose == Some(at_the_go)
    as "a field on a struck creature ticks on it and holds the pose it stood in at the go"
  // Two gos, 300 ms apart, both arming the row (phaseFlags -1): the second go arms it again.
  let two_gos = Spell(..field, phase_delays_ms: [0, 300])
  let #(state, effects) =
    pressed(plans: support.plans_of([two_gos]), caster: support.caster())
  let #(_, fired) =
    support.run_timers_finding(
      caster: support.caster(),
      state:,
      effects:,
      from_ms: press_ms,
      until_ms: press_ms + 800,
      units: dict.new(),
      found_by: found_in(script: []),
    )
  let asks = list.flat_map(fired, fn(step) { step.found })
  let assert [latest] = asks
    as "the second go cancelled the first go's tick and armed its own, which lands 500 ms after it"
  assert latest.phase == 1 && latest.go == 2
    as "the ask holds the phase of the latest go and which go armed the row"
}

pub fn the_last_tick_of_a_field_asks_while_its_node_end_is_due_and_the_node_waits_for_the_answer_then_ends_with_the_0x7fe_alone_test() -> Nil {
  use <- owned_test.run(5000)
  // An aura of 2000 ms holding an open Proxy of tickTime 500 aimed at the area: ticks at 500,
  // 1000, 1500 and 2000, the last at the node's end (`ticking.ending_with_node`: a tick due at
  // the end lands before the node ends). The tick timer and the `NodesEnd` timer are two
  // timers at 2000, and the driven clock keeps list order for equal times, so the test fires
  // the `NodesEnd` timer alone with the last tick overdue, as a connection fallen behind
  // does (cast_tick_test.ticks_due_together_go_in_key_order_test): the rule fires the due
  // tick, whose ask opens a round, and then ends the node, which the open round must hold.
  let field =
    Spell(
      ..holder(proxies: [
        area_periodic(
          schedule: support.open_schedule(delay_ms: 0, tick_ms: 500),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
      aura_ms: Some(2000),
    )
  let #(state, effects) =
    pressed(plans: support.plans_of([field]), caster: support.caster())
  let holder_id = support.pressed_id(effects:)
  let found = found_in(script: [#(4, [21])])
  let #(before_the_end, _) =
    support.run_timers_finding(
      caster: support.caster(),
      state:,
      effects:,
      from_ms: press_ms,
      until_ms: press_ms + 1999,
      units: dict.new(),
      found_by: found,
    )
  let assert [node_end] =
    support.timers_matching(state: before_the_end, matching: fn(due) {
      case due {
        cast_state.NodesEnd(..) -> True
        _ -> False
      }
    })
    as "the aura's node end is armed"
  assert tick_timer_ids(state: before_the_end) != []
    as "the last tick's timer is armed too"
  let #(state, raw) =
    support.fired_raw_as(
      caster: support.caster(),
      state: before_the_end,
      timer: node_end,
      at: press_ms + 2000,
    )
  assert list.map(support.proxy_tick_asks(effects: raw), fn(asked) {
      asked.tick
    })
    == [4]
    as "the node end's firing lands the overdue last tick, which asks"
  assert support.finished_ids(support.writes(effects: raw)) == []
    && dict.size(state.lingering) == 1
    as "the open round holds the node: no 0x7fe is written before the answer, and the cast is still held"
  let #(state, answered) =
    support.answered_finding(
      caster: support.caster(),
      state:,
      effects: raw,
      at: press_ms + 2000,
      struck_of: fn(_) { [] },
      rolls: [],
      poses: dict.new(),
      units: dict.new(),
      found_by: Some(found),
    )
  assert support.cast_lines(frames: support.writes(effects: answered))
    == [
      "started k1 71371 root 90100 parent 90100",
      "went k1 p0",
      "finished k1",
      "finished k2",
    ]
    as "the child of the last tick comes before the field's 0x7fe, which is alone (fact opcode.0x7fe: the client's FinishCast destroys every node)"
  assert list.map(support.writes(effects: answered), fn(frame) {
      frame.message_id
    })
    |> list.contains(spell_targets_removed.message_id)
    == False
    as "no 0x811 comes with it: a lingering cast's last node ends by time with the 0x7fe alone"
  assert dict.size(state.lingering) == 0
    && dict.size(state.casts) == 0
    && support.finished_ids(support.writes(effects: answered))
    |> list.contains(holder_id)
    as "the field is gone once the answer closed the round"
}

pub fn an_answer_for_a_row_that_was_dropped_or_armed_again_starts_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let field =
    Spell(
      ..holder(proxies: [
        area_periodic(
          schedule: support.open_schedule(delay_ms: 0, tick_ms: 500),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
      phase_delays_ms: [0, 1000],
    )
  let caster = support.caster()
  let #(state, _) = pressed(plans: support.plans_of([field]), caster:)
  // Tick 1 of go 1 is due at 1500; fired by itself it asks and leaves its round open.
  let assert [tick_timer] = tick_timer_ids(state:)
    as "go 1 armed the first tick"
  let #(state, raw) =
    support.fired_raw_as(caster:, state:, timer: tick_timer, at: press_ms + 500)
  let assert [asked] = support.proxy_tick_asks(effects: raw) as "the tick asks"
  let answered = fn(state: State) {
    support.answered_finding(
      caster:,
      state:,
      effects: [cast_state.FindProxyTickUnits(asked:)],
      at: press_ms + 600,
      struck_of: fn(_) { [] },
      rolls: [],
      poses: dict.new(),
      units: dict.new(),
      found_by: Some(fn(_) { [21, 22] }),
    )
  }
  let row_of = fn(state: State) {
    let assert Ok(holder) =
      cast_state.holder_of(cast: state, cast_id: asked.cast_id)
    dict.get(
      holder.ticking,
      cast_state.tick_key(
        unit_id: asked.primary_target,
        effect_id: asked.effect_id,
      ),
    )
  }
  let control = answered(state)
  assert list.length(support.started_in(effects: control.1)) == 2
    as "the control: an answer for the row as it was asked starts a child on each unit"
  list.each(
    [
      #(
        "the node was removed",
        cast_tick.ticks_dropped(
          cast: state,
          cast_id: asked.cast_id,
          unit_id: asked.primary_target,
        ).0,
        "every path that drops a node drops its ticks (ticks_dropped)",
      ),
      #(
        "the cast finished or its persistence ended",
        cast_tick.ticks_all_dropped(cast: state, cast_id: asked.cast_id).0,
        "a finish, a persistence end and a death cancel every tick (ticks_all_dropped)",
      ),
    ],
    fn(row) {
      let #(what, dropped, reason) = row
      let #(_, answer) = answered(dropped)
      assert answer == []
        as {
          "the row was dropped between ask and answer ("
          <> what
          <> "): the answer starts nothing and writes nothing, as `cast.ticked` does for a damage tick; "
          <> reason
        }
    },
  )
  // A later go arms the row again while the ask waits: the go of phase 1, due at 2000.
  let assert Ok(open_row) = row_of(state)
  assert cast_state.ticking_open(row: open_row) == 1
    && cast_state.ticking_go(row: open_row) == 1
    as "the ask holds the row's round open for go 1"
  let assert [go_timer] =
    support.timers_matching(state:, matching: fn(due) {
      case due {
        cast_state.Go(..) -> True
        _ -> False
      }
    })
    as "go 2 is waiting"
  let #(state, go_raw) =
    support.fired_raw_as(caster:, state:, timer: go_timer, at: press_ms + 1000)
  let #(state, _) =
    support.answered_with_no_targets(
      state:,
      effects: go_raw,
      at: press_ms + 1000,
    )
  let assert Ok(armed_again) = row_of(state)
  assert cast_state.ticking_go(row: armed_again) == 2
    && cast_state.ticking_open(row: armed_again) == 1
    as "go 2 armed the row again from its own time, keeping the open round of the earlier schedule"
  let #(state, answer) = answered(state)
  assert support.started_in(effects: answer) == []
    as "the answer is for go 1 and the row is go 2's: no child starts"
  let assert Ok(closed) = row_of(state)
  assert cast_state.ticking_open(row: closed) == 0
    as "the round of the earlier schedule closes, so the new schedule's node end is not held"
}

pub fn a_periodic_area_proxys_gates_are_read_at_the_tick_the_casters_before_the_ask_and_each_units_after_it_test() -> Nil {
  use <- owned_test.run(5000)
  let combat_gate = prerequisites.single(id: 903, condition: #(28, 1, 0, 0))
  // Prerequisite type 38 comparison 1: the first unit is the creature of this Creature2 row
  // (`Prerequisite.prerequisiteTypeId.38`); a type 37 condition takes a roll a tick does not
  // draw (`Prerequisite.prerequisiteTypeId.37`).
  let creature_gate =
    prerequisites.single(id: 3475, condition: #(38, 1, 0, 12_700))
  let chance_gate = prerequisites.single(id: 4585, condition: #(37, 6, 0, 50))
  let kinds =
    dict.from_list([
      #(21, prerequisite.NonPlayer(12_700)),
      #(22, prerequisite.NonPlayer(1)),
      #(23, prerequisite.NonPlayer(12_700)),
    ])
  let needs_the_dead = Spell(..child(), caster_death: spell_plan.MustBeDead)
  list.each(
    [
      #(
        "the caster passes its gate",
        spell_plan.GatedOnCaster(gates: [combat_gate]),
        child(),
        in_combat(),
        1,
        [23, 22, 21],
        0,
        "control: the caster is in combat, so the tick asks and every unit found starts a child, in the order found",
      ),
      #(
        "the caster's gate fails",
        spell_plan.GatedOnCaster(gates: [combat_gate]),
        child(),
        support.caster(),
        0,
        [],
        0,
        "the caster is not in combat, so its gate fails at the tick: no ask and no line",
      ),
      #(
        "the named spell refuses the caster's life",
        spell_plan.Always,
        needs_the_dead,
        support.caster(),
        0,
        [],
        1,
        "the spell's caster condition needs a dead caster and the caster lives: no ask and the debug line",
      ),
      #(
        "a target gate that one unit fails",
        spell_plan.GatedOnCasterAndTarget(caster: [], target: creature_gate),
        child(),
        support.caster(),
        1,
        [23, 21],
        0,
        "the gate reads each unit found: 22 is a creature of another row, so a child starts on 23 and 21 in the order found",
      ),
      #(
        "a target gate that needs a roll",
        spell_plan.GatedOnCasterAndTarget(caster: [], target: chance_gate),
        child(),
        support.caster(),
        1,
        [],
        3,
        "a tick draws no roll, so a type 37 gate cannot be decided for any unit: no child and one debug line for each of the three",
      ),
    ],
    fn(row) {
      let #(what, condition, named, caster, asks, started, lines, reason) = row
      let plans =
        support.plans_of([
          holder(proxies: [
            area_periodic(schedule: four_ticks(), condition:, named:),
          ]),
        ])
      let #(state, effects) = pressed(plans:, caster:)
      let #(_, fired) =
        support.run_timers_finding(
          caster:,
          state:,
          effects:,
          from_ms: press_ms,
          until_ms: press_ms + 500,
          units: kinds,
          found_by: found_in(script: [#(1, [23, 22, 21])]),
        )
      let all = as_steps(fired:)
      assert list.length(list.flat_map(fired, fn(step) { step.found })) == asks
        as { what <> ": " <> reason }
      assert list.map(
          support.starts_of(steps: all, spell4_id: child_spell4_id),
          fn(start) { { start.1 }.primary_target_unit_id },
        )
        == started
        as { what <> ": " <> reason }
      assert list.length(
          list.flat_map(all, fn(step) { support.debug_lines(effects: step.1) }),
        )
        == lines
        as { what <> ": " <> reason }
    },
  )
}

pub fn a_periodic_area_proxy_of_a_field_cast_on_another_unit_ticks_on_that_unit_and_stops_with_its_node_test() -> Nil {
  use <- owned_test.run(5000)
  // The ability's Proxy starts the field on each unit its go struck (a Proxy aimed at the
  // area), so the field's primary target is the creature 21, and the node of the field's
  // ticking rows lives on it. A second periodic Proxy of the same field is aimed at the caster.
  let at_the_caster =
    Proxy(
      ..periodic(
        schedule: support.open_schedule(delay_ms: 0, tick_ms: 500),
        condition: spell_plan.Always,
        named: child(),
      ),
      effect_id: Spell4EffectsId(121_346),
    )
  let field =
    holder(proxies: [
      area_periodic(
        schedule: support.open_schedule(delay_ms: 0, tick_ms: 500),
        condition: spell_plan.Always,
        named: child(),
      ),
      at_the_caster,
    ])
  let ability =
    holding(
      proxies: [Proxy(..once(named: field), target: spell_plan.OnEachStruck)],
      spell4_id: ability_spell4_id,
      base: 3,
    )
  let caster = support.caster()
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_of([ability]),
      state: cast_state.new(),
      caster:,
      bag_index: support.started_bag_index,
      target: 0,
      at: press_ms,
    )
  let #(state, effects) =
    support.answered_as(
      caster:,
      state:,
      effects: raw,
      at: press_ms,
      struck: support.hits([21]),
      rolls: [],
    )
  let assert [#(_, field_start)] =
    support.starts_of(
      steps: [#(press_ms, effects)],
      spell4_id: holder_spell4_id,
    )
    as "the field started once, on the creature"
  assert field_start.primary_target_unit_id == 21
  assert support.tick_timers_on(state:, unit_id: 21) == 1
    && support.tick_timers_on(state:, unit_id: caster.unit_id) == 1
    as "the area row ticks on the creature and the caster-aimed row on the caster"
  let #(_, fired) =
    support.run_timers_finding(
      caster:,
      state:,
      effects:,
      from_ms: press_ms,
      until_ms: press_ms + 500,
      units: dict.new(),
      found_by: found_in(script: []),
    )
  assert list.flat_map(fired, fn(step) {
      list.map(step.found, fn(asked) {
        #(asked.primary_target, asked.effect_id)
      })
    })
    == [#(21, Spell4EffectsId(121_345))]
    as "the ask of the area row names the creature as the unit the row ticks on"
  let #(dropped, _) =
    cast_tick.ticks_dropped(
      cast: state,
      cast_id: field_start.cast_id,
      unit_id: 21,
    )
  assert support.tick_timers_on(state: dropped, unit_id: 21) == 0
    as "the creature's node is taken off, so the ticks that ride on it stop (cast_tick.ticks_dropped: every path that drops a node calls it)"
  assert support.tick_timers_on(state: dropped, unit_id: caster.unit_id) == 1
    as "the caster-aimed row of the same field keeps ticking on the caster"
}

pub fn a_late_timer_asks_once_for_each_due_tick_of_an_area_proxy_with_its_own_tick_number_test() -> Nil {
  use <- owned_test.run(5000)
  let plans =
    support.plans_of([
      holder(proxies: [
        area_periodic(
          schedule: four_ticks(),
          condition: spell_plan.Always,
          named: child(),
        ),
      ]),
    ])
  let caster = support.caster()
  let #(state, _) = pressed(plans:, caster:)
  let assert [timer] = tick_timer_ids(state:) as "tick 1's timer, due at 1500"
  // Handled 900 ms late, at 2400: ticks 1 (1500) and 2 (2000) are due, tick 3 (2500) is not.
  let #(state, raw) =
    support.fired_raw_as(caster:, state:, timer:, at: press_ms + 1400)
  assert list.map(support.proxy_tick_asks(effects: raw), fn(asked) {
      #(asked.tick, asked.go)
    })
    == [#(1, 1), #(2, 1)]
    as "each due tick asks once with its own tick number, none twice"
  assert list.map(support.started_timers(effects: raw), fn(started) {
      started.1
    })
    == [100]
    as "the next tick is armed from the schedule, 100 ms on (tick 3 at 2500), not 500 ms from the late time"
  let #(_, answered) =
    support.answered_finding(
      caster:,
      state:,
      effects: raw,
      at: press_ms + 1400,
      struck_of: fn(_) { [] },
      rolls: [],
      poses: dict.new(),
      units: dict.new(),
      found_by: Some(found_in(script: [#(1, [21]), #(2, [22, 23])])),
    )
  assert list.map(support.started_in(effects: answered), fn(start) {
      start.primary_target_unit_id
    })
    == [21, 22, 23]
    as "the children come in tick order, each tick's units in the order found"
}

/// Restrictor 38279 over the client's tables: the Medic whose only ability it is, a press at
/// `press_ms`, and the snare child 77118 as the plan holds it.
fn restrictor_over(
  tables tables: store.Tables,
) -> #(Caster, #(State, List(Effect)), spell_plan.CrowdControl) {
  let plans = spell_plan.plans_with_later(tables:)
  let base = Spell4BaseId(22_861)
  let caster =
    cast_state.Caster(..support.caster(), abilities: [base], book: [base])
  let assert Ok(ability) = spell_plan.in_plans(plans:, base:)
    as "the client's plans hold Restrictor"
  let assert [snare] =
    list.flat_map(
      spell_plan.tree(spell: ability, started: fn(_) { True }),
      fn(spell) {
        case spell.spell4_id == id.Spell4Id(77_118) {
          True -> spell_plan.payloads(spell:, as_kind: spell_plan.as_control)
          False -> []
        }
      },
    )
    |> list.unique
    as "Snare 77118 holds the one CCStateSet row"
  #(
    caster,
    support.press_as(
      plans:,
      state: cast_state.new(),
      caster:,
      bag: 0,
      at: press_ms,
    ),
    snare,
  )
}

pub fn restrictors_field_over_the_clients_rows_asks_eight_times_and_each_child_carries_the_snare_row_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  // Restrictor 38279 blinks back and starts the field 38287 (aura 4000), whose Proxy 131274
  // (tickTime 500) casts Snare 77118 on the units found; the Snare's one row is the
  // CCStateSet 200476, state 21, 2000 ms (text 306769;
  // `table_rows -- Spell4Effects 131274 200476 -- Spell4 38287 77118`).
  let #(caster, pressed, snare) =
    restrictor_over(tables: client_tables.shared())
  assert snare.effect_id == Spell4EffectsId(200_476)
    && snare.row.state == crowd_control_state.Snare
    && snare.row.duration_ms == 2000
    as "the plan's row is the client's: state 21, 2000 ms"
  let told = fn(at_ms: Int, asked: cast_state.GoAsked) {
    // The units the connection's strike gives each child: the one it was made on, told the
    // row of the plan under an instance id of its cast.
    [
      cast_state.Hit(
        unit_id: asked.primary_target,
        unit: support.first_life,
        descriptions: [],
        controls: [
          strike_tell.ControlLanded(
            tell: strike_tell.ControlTell(
              effect_id: snare.effect_id.value,
              instance_id: asked.cast_id,
              row: snare.row,
              throw: None,
            ),
            ends_at_ms: at_ms + snare.row.delay_ms + snare.row.duration_ms,
            interrupted: None,
          ),
        ],
        armor_removed: 0,
        ticking: [],
      ),
    ]
  }
  let #(_, fired) =
    support.run_timers_finding_striking(
      caster:,
      state: pressed.0,
      effects: pressed.1,
      from_ms: press_ms,
      until_ms: 20_000,
      units: dict.new(),
      found_by: fn(_) { [21, 22] },
      struck_by: told,
    )
  let asks =
    list.flat_map(fired, fn(step) {
      list.map(step.found, fn(asked) { #(step.at_ms, asked.tick) })
    })
  assert asks
    == [
      #(1500, 1),
      #(2000, 2),
      #(2500, 3),
      #(3000, 4),
      #(3500, 5),
      #(4000, 6),
      #(4500, 7),
      #(5000, 8),
    ]
    as "an ask every 500 ms for the field's 4000 ms, the eighth at 5000 before the field's 0x7fe, and no ninth"
  let steps = as_steps(fired:)
  let children = support.starts_of(steps:, spell4_id: 77_118)
  assert list.length(children) == 16
    as "a child on each of the two units at each of the eight ticks"
  list.each(children, fn(child) {
    assert { child.1 }.parent_spell4_id == 38_287
      && { child.1 }.root_spell4_id == 38_279
      as "the field is the parent and Restrictor the root"
  })
  let listed =
    list.flat_map(steps, fn(step) {
      list.flat_map(
        support.frames_of(message_id: spell_go.message_id, effects: step.1),
        fn(frame) {
          let assert Ok(go) = spell_go.decode(frame.body)
            as "a 0x7f4 the rule wrote decodes"
          list.flat_map(go.targets, fn(target) {
            list.map(target.effects, fn(effect) {
              #(step.0, target.unit_id, effect.spell4_effects_id)
            })
          })
        },
      )
    })
  assert list.length(listed) == 16
    && list.all(listed, fn(entry) { entry.2 == 200_476 })
    as "each child's go lists the CCStateSet row 200476 on its unit"
  let removed =
    list.flat_map(steps, fn(step) {
      support.removed_targets(support.writes(effects: step.1))
    })
  let cast_and_unit = fn(child: #(Int, spell_started.SpellStarted)) {
    #({ child.1 }.cast_id, [{ child.1 }.primary_target_unit_id])
  }
  assert removed == list.map(list.take(children, 14), cast_and_unit)
    as "stack group 1771 holds one snare of a caster on a unit: each child takes the snare the same caster's last child gave that unit off it (0x811), so the units found twice in a row lose the oldest each tick and the last tick's children keep theirs"
  Nil
}
