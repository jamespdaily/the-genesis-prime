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
import genesis_prime/game/cast
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/lasting
import genesis_prime/game/spell_plan.{type Proxy, type Spell, Proxy, Spell}
import genesis_prime/game/spend
import genesis_prime/game/ticking.{type Schedule, Schedule, Ticks}
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_started
import genesis_prime/step.{LogDebug}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import prerequisite_support as prerequisites
import spell_tables

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
  let assert Ok(spell) =
    spell_plan.in_plans(
      plans: spell_tables.fixture_plans(),
      base: Spell4BaseId(19_019),
    )
    as "the fixture's plans hold Mind Burst"
  spell
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

/// Each 0x7ff of the spell `spell4_id` the steps write, with the time of its step.
fn starts_of(
  steps steps: List(#(Int, List(Effect))),
  spell4_id spell4_id: Int,
) -> List(#(Int, spell_started.SpellStarted)) {
  list.flat_map(steps, fn(step) {
    support.started_in(effects: step.1)
    |> list.filter(fn(start) { start.spell4_id == spell4_id })
    |> list.map(fn(start) { #(step.0, start) })
  })
}

fn times_of(
  starts starts: List(#(Int, spell_started.SpellStarted)),
) -> List(Int) {
  list.map(starts, fn(start) { start.0 })
}

fn debug_lines(effects effects: List(Effect)) -> List(String) {
  list.filter_map(support.logs(effects:), fn(line) {
    case line.0 == LogDebug {
      True -> Ok(line.1)
      False -> Error(Nil)
    }
  })
}

/// The timers of the state that are a tick of a periodic row.
fn tick_timers(state state: State) -> Int {
  list.count(dict.values(state.timers), fn(due) {
    case due {
      cast_state.Tick(..) -> True
      _ -> False
    }
  })
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
    starts_of(steps: [#(press_ms, effects)], spell4_id: holder_spell4_id)
  let assert [#(_, holder_start)] = held
    as "the ability's own Proxy starts the holder at the press"
  assert holder_start.root_spell4_id == ability_spell4_id
    && holder_start.parent_spell4_id == ability_spell4_id
    as "opcode.0x7ff.root_parent: a Proxy's child names the pressed spell as root and the spell whose Proxy fired as parent"
  let ticks = starts_of(steps:, spell4_id: child_spell4_id)
  assert times_of(starts: ticks) == [2000, 3000]
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
  let children = starts_of(steps:, spell4_id: 87_477)
  assert times_of(starts: children)
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
  assert times_of(starts: starts_of(steps:, spell4_id: child_spell4_id))
    == [1500, 2000, 2500, 3000]
    as "four ticks have landed by 3000"
  assert tick_timers(state:) == 1
    as "the fifth tick is armed while the persistence holds"
  let #(state, ended) =
    cast.persisted(
      cast: state,
      caster: support.caster_in_combat(in_combat: False),
      now: support.at(ms: 3100),
    )
  assert tick_timers(state:) == 0
    as "text 311216: the cast ends when the persistence fails, and its tick timer is cancelled, so no child follows"
  assert list.length(support.cancelled_timers(effects: ended)) >= 1
  assert starts_of(steps: [#(3100, ended)], spell4_id: child_spell4_id) == []
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
  assert times_of(starts: starts_of(steps:, spell4_id: child_spell4_id))
    == [2000, 4000]
    as "the gate (in combat) passes at ticks 1 and 3 and fails at tick 2, which starts no child; the ticks go on"
  assert list.flat_map(steps, fn(step) { debug_lines(effects: step.1) }) == []
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
  assert starts_of(steps:, spell4_id: child_spell4_id) == []
    as "a type 37 gate needs a roll and a tick draws none: no child"
  let lines = list.flat_map(steps, fn(step) { debug_lines(effects: step.1) })
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
  assert tick_timers(state:) == 1
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
  assert times_of(starts: starts_of(steps:, spell4_id: child_spell4_id))
    == [press_ms + 2000, press_ms + 3000]
    as "tick 1 reads the gate failing and starts no child; ticks 2 and 3 read it passing and start one each"
  assert list.flat_map(steps, fn(step) { debug_lines(effects: step.1) }) == []
    as "a gate that fails is the client's answer, not a gap"
}

pub fn the_children_of_a_tick_count_no_quest_objective_and_hold_no_item_value_test() -> Nil {
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
  assert from_tick.pressed == None
    as "a tick's child holds no item value: Child(counted_with: WithNothing, from: None), as a proc's"
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
    times_of(starts: starts_of(steps:, spell4_id: 71_373))
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
    starts_of(steps: [#(press_ms, effects), ..steps], spell4_id: 33_258)
  assert times_of(starts:) == [press_ms]
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
      ticking: cast_tick.proxies_ticking(proxies: [proxy], caster:),
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
  assert times_of(starts: starts_of(steps:, spell4_id: child_spell4_id))
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
    tick_timers(state:)
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
  assert starts_of(steps:, spell4_id: child_spell4_id) == []
    as "no child is cast for a caster the spell refuses"
  let lines = list.flat_map(steps, fn(step) { debug_lines(effects: step.1) })
  assert list.length(lines) == 3
    as "each of the three ticks, which go on, leaves one debug line"
  assert list.all(lines, fn(line) {
    string.contains(line, "the periodic Proxy effect 121345 of Spell4")
    && string.contains(line, "does not cast Spell4 71371")
    && string.contains(line, "caster that is alive")
  })
}
