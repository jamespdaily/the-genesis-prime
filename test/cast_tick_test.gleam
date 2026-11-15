//// Damage and heals over time in the cast rule: a go arms the ticks of each periodic row
//// on each unit it reached, a damage tick asks its unit for a strike round of its own and
//// writes its 0x7f8 when the round closes, a heal tick heals the caster, and the cast's
//// 0x7fe waits for its last tick (`opcode.0x7f8`, `cast.miss_after_finish`).
////
//// The spell is a planted child of base 3 with no rows of its own: a damage row reaches
//// the go through the round's `ticking` (genesis_prime/game/strike), so the go strikes
//// with the rows the test gives it. The schedules are planted for the test; how a row's
//// times give its schedule is genesis_prime/game/ticking's.

import attacker_support
import cast_support as support
import genesis_prime/client_connection.{type News, CastTicked}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/damage.{Formula, Parameter}
import genesis_prime/game/effect_kind
import genesis_prime/game/hit
import genesis_prime/game/lasting
import genesis_prime/game/spell_area.{DamageEffect, TickingDamage}
import genesis_prime/game/spell_plan.{type Spell, AimsAtArea, AimsAtCaster}
import genesis_prime/game/spend
import genesis_prime/game/ticking.{Schedule}
import genesis_prime/message/cast_result
import genesis_prime/message/combat_log
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription, SpellDamageDescription,
}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_info.{SpellEffectInfo}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_effect_tick.{
  type SpellEffectTick, SpellEffectTick,
}
import genesis_prime/message/spell_failed
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/step.{type ConnectionId, type TimerId, TimerId}
import genesis_prime/table/id.{Spell4BaseId, Spell4EffectsId}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/set
import owned_test
import prerequisite_support as prerequisites

/// The planted base 3 is bag index 11 (`cast_support.abilities`).
const bag_of_base_3 = 11

const press_ms = 1000

/// Paralytic Surge's damage row (Spell4Effects 96125), its own formula and type.
fn surge_blow() -> spell_area.DamageEffect {
  DamageEffect(
    effect_id: Spell4EffectsId(96_125),
    damage_type: 2,
    delay_ms: 0,
    phase_flags: -1,
    aim: AimsAtArea,
    formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
      Parameter(kind: 12, value: 0.0935),
      Parameter(kind: 13, value: 0.0935),
      Parameter(kind: 10, value: 8.14),
    ]),
    threat_multiplier: 1.0,
    tag: spend.always,
  )
}

/// The row ticking with no delay, every 2000 ms for 6000 ms: three ticks, at 2000, 4000
/// and 6000 after the go.
fn every_two_seconds() -> ticking.Schedule {
  Schedule(delay_ms: 0, tick_ms: 2000, duration_ms: 6000, count: 3)
}

fn surge_ticking() -> List(spell_area.TickingDamage) {
  [TickingDamage(damage: surge_blow(), schedule: every_two_seconds())]
}

fn surge() -> Spell {
  support.child(spell4_id: 58_591, base: 3)
}

/// A hit on the creature `unit_id` in its third life, with no description of its own
/// and these periodic rows.
fn hit_ticking(
  unit_id unit_id: Int,
  ticking ticking: List(spell_area.TickingDamage),
) -> cast.Struck {
  cast.Hit(
    unit_id:,
    unit: cast.HitCreature(life: 3, struck_at_ms: press_ms),
    descriptions: [],
    controls: [],
    armor_removed: 0,
    ticking:,
  )
}

// ---- the driver: the clock, the timers and the tick rounds are the test's ----

/// What the creature answers a tick's strike: its round closes at once with this, or
/// stays open.
type Answer {
  Answered(struck: Option(cast.Struck))
  Held
}

/// The rule's state after a run, each step's time and effects, the timers left
/// pending with their due times, and the tick strikes left open.
type Run {
  Run(
    state: State,
    steps: List(#(Int, List(Effect))),
    pending: List(#(Int, TimerId)),
    held: List(cast.TickAsked),
  )
}

/// A press of base 3 at `press_ms` whose go strikes `struck`, with its tick strikes
/// answered by `answer`.
fn pressed(
  plans plans: spell_plan.Plans,
  caster caster: Caster,
  struck struck: List(cast.Struck),
  answer answer: fn(Int, cast.TickAsked) -> Answer,
) -> Run {
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: bag_of_base_3,
      target: 0,
      at: press_ms,
    )
  let #(state, effects, held) =
    settled(caster:, state:, effects: raw, at: press_ms, struck:, answer:)
  Run(
    state:,
    steps: [#(press_ms, effects)],
    pending: support.due_of(effects:, now_ms: press_ms),
    held:,
  )
}

/// Every pending timer due at `until_ms` or before fires, earliest first and, at one
/// time, in the order it was started; each go strikes `struck` and each tick strike is
/// answered by `answer`.
fn ran(
  caster caster: Caster,
  run run: Run,
  until_ms until_ms: Int,
  struck struck: List(cast.Struck),
  answer answer: fn(Int, cast.TickAsked) -> Answer,
) -> Run {
  case list.sort(run.pending, by_due) {
    [#(due, timer), ..rest] if due <= until_ms -> {
      let #(state, raw) =
        support.fired_raw_as(caster:, state: run.state, timer:, at: due)
      let #(state, effects, held) =
        settled(caster:, state:, effects: raw, at: due, struck:, answer:)
      ran(
        caster:,
        run: Run(
          state:,
          steps: list.append(run.steps, [#(due, effects)]),
          pending: pending_after(pending: rest, effects:, at: due),
          held: list.append(run.held, held),
        ),
        until_ms:,
        struck:,
        answer:,
      )
    }
    sorted -> Run(..run, pending: sorted)
  }
}

/// The run after a step the test takes itself at `at`: its effects recorded and its
/// timers taken in.
fn stepped(
  run run: Run,
  at at: Int,
  taken taken: #(State, List(Effect)),
) -> Run {
  let #(state, effects) = taken
  Run(
    ..run,
    state:,
    steps: list.append(run.steps, [#(at, effects)]),
    pending: pending_after(pending: run.pending, effects:, at:),
  )
}

fn pending_after(
  pending pending: List(#(Int, TimerId)),
  effects effects: List(Effect),
  at at: Int,
) -> List(#(Int, TimerId)) {
  let cancelled = support.cancelled_timers(effects:)
  list.append(
    list.filter(pending, fn(other) { !list.contains(cancelled, other.1) }),
    support.due_of(effects:, now_ms: at),
  )
}

fn by_due(first: #(Int, TimerId), second: #(Int, TimerId)) -> order.Order {
  let TimerId(first_id) = first.1
  let TimerId(second_id) = second.1
  int.compare(first.0, second.0)
  |> order.break_tie(int.compare(first_id, second_id))
}

/// The strikes of the effects answered as gos that struck `struck`, and each tick
/// strike answered by `answer`, an answered one closing its round at the same time.
fn settled(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at at: Int,
  struck struck: List(cast.Struck),
  answer answer: fn(Int, cast.TickAsked) -> Answer,
) -> #(State, List(Effect), List(cast.TickAsked)) {
  let #(state, effects) =
    support.answered_as(caster:, state:, effects:, at:, struck:, rolls: [])
  list.fold(tick_strikes(effects:), #(state, effects, []), fn(so_far, asked) {
    let #(state, effects, held) = so_far
    case answer(at, asked) {
      Held -> #(state, effects, list.append(held, [asked]))
      Answered(struck:) -> {
        let #(state, more) =
          cast.ticked(
            cast: state,
            caster:,
            now: support.at(ms: at),
            asked:,
            struck:,
          )
        #(state, list.append(effects, more), held)
      }
    }
  })
}

/// Every tick lands on its unit for 8 health, killing it when `killed` is 1.
fn landed(killed killed: Int) -> fn(Int, cast.TickAsked) -> Answer {
  fn(_, asked: cast.TickAsked) {
    Answered(struck: Some(tick_hit(asked:, killed:)))
  }
}

fn tick_hit(asked asked: cast.TickAsked, killed killed: Int) -> cast.Struck {
  cast.Hit(
    unit_id: asked.unit_id,
    unit: cast.HitCreature(life: asked.life, struck_at_ms: 0),
    descriptions: [
      hit.Description(
        spell4_effects_id: asked.effect_id.value,
        delay_ms: 0,
        damage: tick_damage(killed:),
      ),
    ],
    controls: [],
    armor_removed: 0,
    ticking: [],
  )
}

fn tick_damage(killed killed: Int) -> SpellDamageDescription {
  SpellDamageDescription(
    raw_damage: 8,
    scaled_raw_damage: 8,
    absorbed: 0,
    shield_absorbed: 0,
    health_damage_with_overkill: 8,
    overkill: 0,
    glance: 0,
    killed:,
    combat_result: combat_result.Hit,
    damage_type: damage_type.Tech,
    hits: [],
  )
}

fn held(_: Int, _: cast.TickAsked) -> Answer {
  Held
}

// ---- what the steps hold ----

fn tick_strikes(effects effects: List(Effect)) -> List(cast.TickAsked) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.TickStrike(asked:) -> Ok(asked)
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..)
      | cast.Strike(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.CasterChangeStarts(..)
      | cast.CasterChangeEnds(..)
      | cast.TargetChangeStarts(..)
      | cast.TargetChangeEnds(..)
      | cast.ForcedMoveStarts(..)
      | cast.Activated(..)
      | cast.ShortcutCast(..)
      | cast.StealthChanged(..) -> Error(Nil)
    }
  })
}

/// Each tick strike of the run as its time, the go of its schedule and its tick.
fn strikes_of(run run: Run) -> List(#(Int, Int, Int)) {
  list.flat_map(run.steps, fn(step) {
    list.map(tick_strikes(effects: step.1), fn(asked) {
      #(step.0, asked.go, asked.tick)
    })
  })
}

fn ids(effects effects: List(Effect)) -> List(Int) {
  list.map(support.writes(effects:), fn(frame) { frame.message_id })
}

/// The 0x7f8 the effects write, decoded.
fn ticks_of(effects effects: List(Effect)) -> List(SpellEffectTick) {
  support.frames_of(message_id: spell_effect_tick.message_id, effects:)
  |> list.map(fn(frame) {
    let assert Ok(tick) = spell_effect_tick.decode(frame.body)
    tick
  })
}

fn all_ticks(run run: Run) -> List(#(Int, SpellEffectTick)) {
  list.flat_map(run.steps, fn(step) {
    list.map(ticks_of(effects: step.1), fn(tick) { #(step.0, tick) })
  })
}

/// The 0x7f8 the audience is told.
fn ticks_told(effects effects: List(Effect)) -> List(#(ConnectionId, News)) {
  list.filter(support.tells(effects:), fn(tell) {
    case tell.1 {
      CastTicked(..) -> True
      client_connection.CastStarted(..)
      | client_connection.CastWent(..)
      | client_connection.CastFinished(..)
      | client_connection.CastInterrupted(..)
      | client_connection.CastMissed(..)
      | client_connection.CastTargetsRemoved(..)
      | client_connection.CastStackRemoved(..)
      | client_connection.Appeared(..)
      | client_connection.CreatureAppeared(..)
      | client_connection.Moving(..)
      | client_connection.Removed
      | client_connection.Health(..)
      | client_connection.Died
      | client_connection.CameBack
      | client_connection.DeathLogged
      | client_connection.CameBackLogged
      | client_connection.CreatureMoved(..)
      | client_connection.CreaturePlaced(..)
      | client_connection.Targeting(..)
      | client_connection.Threat(..)
      | client_connection.CombatState(..)
      | client_connection.Shield(..)
      | client_connection.CrowdControlApplied(..)
      | client_connection.CrowdControlEnded(..)
      | client_connection.InterruptArmor(..)
      | client_connection.Absorption(..)
      | client_connection.Level(..)
      | client_connection.PropertiesChanged(..)
      | client_connection.Stealth(..)
      | client_connection.LookChanged(..) -> False
    }
  })
}

/// No 0x7f8 of a cast follows its 0x7fe (`opcode.0x7fe`: the cast is gone from the
/// client then, and a later 0x7f8 for it is dropped, `0x140561c30`).
fn no_tick_after_finish(run run: Run) -> Nil {
  let frames: List(Frame) =
    list.flat_map(run.steps, fn(step) { support.writes(effects: step.1) })
  let _finished =
    list.fold(frames, set.new(), fn(finished, frame) {
      case frame.message_id {
        id if id == spell_finished.message_id ->
          set.insert(finished, support.finished_cast_id(frame))
        id if id == spell_effect_tick.message_id -> {
          let assert Ok(tick) = spell_effect_tick.decode(frame.body)
          assert !set.contains(finished, tick.cast_id)
            as "no 0x7f8 of a cast follows its 0x7fe"
          finished
        }
        _ -> finished
      }
    })
  Nil
}

/// A run of the surge on creature 10 to its end, every tick landing.
fn surge_run(answer answer: fn(Int, cast.TickAsked) -> Answer) -> Run {
  let struck = [hit_ticking(unit_id: 10, ticking: surge_ticking())]
  pressed(
    plans: support.plans_of([surge()]),
    caster: support.caster(),
    struck:,
    answer:,
  )
  |> fn(run) {
    ran(caster: support.caster(), run:, until_ms: 20_000, struck:, answer:)
  }
}

// ---- the tests ----

pub fn the_go_arms_its_ticks_in_its_own_step_test() -> Nil {
  use <- owned_test.run(5000)
  let run =
    pressed(
      plans: support.plans_of([surge()]),
      caster: support.caster(),
      struck: [hit_ticking(unit_id: 10, ticking: surge_ticking())],
      answer: held,
    )
  let assert [#(_, effects)] = run.steps
  assert ids(effects:)
    |> list.filter(fn(id) {
      id == spell_go.message_id || id == spell_finished.message_id
    })
    == [spell_go.message_id]
    as "the go writes its 0x7f4 and the cast lingers on its node: no 0x7fe yet"
  assert list.map(support.started_timers(effects:), fn(started) { started.1 })
    == [2000, 6000]
    as "the step that writes the 0x7f4 starts the first tick's timer, 2000 ms on (delay 0 plus one tick), and the node's end at its durationTime, 6000 ms on, so no state holds the go without its ticks"
  let longer =
    pressed(
      plans: support.plans_of([surge()]),
      caster: support.caster(),
      struck: [
        hit_ticking(unit_id: 10, ticking: [
          TickingDamage(
            damage: surge_blow(),
            schedule: Schedule(
              delay_ms: 0,
              tick_ms: 2000,
              duration_ms: 7000,
              count: 3,
            ),
          ),
        ]),
      ],
      answer: held,
    )
  let assert [#(_, effects)] = longer.steps
  assert list.map(support.started_timers(effects:), fn(started) { started.1 })
    == [2000, 7000]
    as "a durationTime of 7000 with a tickTime of 2000 gives three ticks, and the node lives the row's own 7000 ms, as the client's end timer for the effect counts delay plus durationTime (`opcode.0x7f4.effect_time`), not to the last tick at 6000"
}

pub fn the_go_lists_ticking_rows_and_no_tick_is_logged_test() -> Nil {
  use <- owned_test.run(5000)
  let run = surge_run(answer: landed(killed: 0))
  let assert [#(_, effects), ..] = run.steps
  let assert [go] = support.frames_of(message_id: spell_go.message_id, effects:)
  let assert Ok(decoded) = spell_go.decode(go.body)
  let assert [target] = decoded.targets
  assert target.unit_id == 10
  assert target.effects
    == [
      SpellEffectInfo(
        spell4_effects_id: 96_125,
        instance_id: 1,
        delay_ms: 0,
        field_4: 0,
        result: spell_effect_result.Bit(SpellEffectBit(field_2: 0)),
      ),
    ]
    as "the go lists the periodic row on the unit it hit as a bit, with no description: the ticks carry the damage"
  assert list.flat_map(run.steps, fn(step) {
      support.frames_of(message_id: combat_log.message_id, effects: step.1)
    })
    == []
    as "neither the go nor a tick writes a 0x247: the client logs each tick from its 0x7f8's description"
  assert list.length(all_ticks(run:)) == 3
}

pub fn the_finish_follows_the_last_tick_test() -> Nil {
  use <- owned_test.run(5000)
  let struck = [hit_ticking(unit_id: 10, ticking: surge_ticking())]
  let answer = fn(at, asked) {
    case at < 7000 {
      True -> landed(killed: 0)(at, asked)
      False -> Held
    }
  }
  let run =
    pressed(
      plans: support.plans_of([surge()]),
      caster: support.caster(),
      struck:,
      answer:,
    )
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 20_000, struck:, answer:)
    }
  assert list.map(all_ticks(run:), fn(tick) { tick.0 }) == [3000, 5000]
    as "ticks 1 and 2 land 2000 and 4000 ms after the go"
  let assert [last] = run.held as "tick 3's strike is asked at 7000 and held"
  assert last.tick == 3
  assert list.flat_map(run.steps, fn(step) {
      support.frames_of(message_id: spell_finished.message_id, effects: step.1)
    })
    == []
    as "the node's end at 7000 waits while tick 3's round is open: no 0x7fe"
  let closed =
    stepped(
      run:,
      at: 7100,
      taken: cast.ticked(
        cast: run.state,
        caster: support.caster(),
        now: support.at(ms: 7100),
        asked: last,
        struck: Some(tick_hit(asked: last, killed: 0)),
      ),
    )
  let assert Ok(#(_, effects)) = list.last(closed.steps)
  assert ids(effects:)
    == [spell_effect_tick.message_id, spell_finished.message_id]
    as "tick 3's close writes its 0x7f8, then the cast's 0x7fe, the last frame of the cast"
  no_tick_after_finish(run: closed)
}

/// Spell4Effects 82888 (table_rows -- Spell4Effects spellId=38514): delayTime 1000,
/// tickTime 1000, durationTime 4000, four whole ticks, at 2000, 3000, 4000 and 5000 ms
/// after the go.
fn atomic_surge_ticking() -> List(spell_area.TickingDamage) {
  [
    TickingDamage(
      damage: DamageEffect(
        ..surge_blow(),
        effect_id: Spell4EffectsId(82_888),
        delay_ms: 1000,
      ),
      schedule: Schedule(
        delay_ms: 1000,
        tick_ms: 1000,
        duration_ms: 4000,
        count: 4,
      ),
    ),
  ]
}

/// The planted spell with spell 38514's propertyFlags bit 0x2000, so its node lasts
/// max(delay, durationTime): 4000 ms for row 82888 (`0x140568540`).
fn longer_time_spell() -> Spell {
  spell_plan.Spell(..surge(), longer_of_delay_and_duration: True)
}

/// A press of the 0x2000 spell whose go hits creature 10 with row 82888, its tick
/// strikes answered by `answer`, run to `until_ms`.
fn atomic_surge_run(
  answer answer: fn(Int, cast.TickAsked) -> Answer,
  until_ms until_ms: Int,
) -> Run {
  let struck = [hit_ticking(unit_id: 10, ticking: atomic_surge_ticking())]
  pressed(
    plans: support.plans_of([longer_time_spell()]),
    caster: support.caster(),
    struck:,
    answer:,
  )
  |> fn(run) {
    ran(caster: support.caster(), run:, until_ms:, struck:, answer:)
  }
}

/// The step that writes the cast's 0x7fe, which there is one of.
fn finish_step(run run: Run) -> #(Int, List(Effect)) {
  let assert [finish] =
    list.filter(run.steps, fn(step) {
      list.contains(ids(effects: step.1), spell_finished.message_id)
    })
    as "the cast finishes once"
  finish
}

fn ticks_and_finish(effects effects: List(Effect)) -> List(Int) {
  list.filter(ids(effects:), fn(id) {
    id == spell_effect_tick.message_id || id == spell_finished.message_id
  })
}

pub fn ticks_stop_at_the_node_life_of_a_spell_whose_life_is_its_longer_time_test() -> Nil {
  use <- owned_test.run(5000)
  let run = atomic_surge_run(answer: landed(killed: 0), until_ms: 20_000)
  assert list.map(all_ticks(run:), fn(tick) { tick.0 }) == [3000, 4000, 5000]
    as "ticks 1 to 3 land 2000, 3000 and 4000 ms after the go (delay 1000 plus each 1000 ms tick)"
  assert list.map(strikes_of(run:), fn(strike) { strike.2 }) == [1, 2, 3]
    as "tick 4, due 5000 ms after the go, is past the node's 4000 ms life and is never asked"
  let #(finished_at, effects) = finish_step(run:)
  assert finished_at == 5000
    as "the 0x7fe goes when the node's life ends, 4000 ms after the go"
  assert ticks_and_finish(effects:)
    == [spell_effect_tick.message_id, spell_finished.message_id]
    as "tick 3's 0x7f8 comes before the 0x7fe in the step the node ends"
  no_tick_after_finish(run:)
}

pub fn a_late_node_end_sends_no_tick_past_the_node_life_test() -> Nil {
  use <- owned_test.run(5000)
  let run = atomic_surge_run(answer: landed(killed: 0), until_ms: 4999)
  let assert Ok(#(4000, tick_2_effects)) = list.last(run.steps)
  let assert [#(_, 1000), #(node_end, 1000)] =
    support.started_timers(effects: tick_2_effects)
    as "tick 2, 3000 ms after the go, arms tick 3 and starts the node's end again, both 1000 ms on"
  let #(state, raw) =
    support.fired_raw_as(
      caster: support.caster(),
      state: run.state,
      timer: node_end,
      at: 6000,
    )
  let #(state, effects, _) =
    settled(
      caster: support.caster(),
      state:,
      effects: raw,
      at: 6000,
      struck: [hit_ticking(unit_id: 10, ticking: atomic_surge_ticking())],
      answer: landed(killed: 0),
    )
  let late =
    Run(..run, state:, steps: list.append(run.steps, [#(6000, effects)]))
  assert list.map(strikes_of(run: late), fn(strike) { strike.2 }) == [1, 2, 3]
    as "the node's end, due 4000 ms after the go and handled 1000 ms late, fires tick 3, which was due within the node's life, and not tick 4, due 5000 ms after the go, past it"
  assert list.map(all_ticks(run: late), fn(tick) { tick.0 })
    == [3000, 4000, 6000]
  assert ticks_and_finish(effects:)
    == [spell_effect_tick.message_id, spell_finished.message_id]
    as "tick 3's 0x7f8, then the 0x7fe, and no fourth tick"
  no_tick_after_finish(run: late)
}

pub fn a_node_kept_by_an_open_strike_round_sends_no_tick_past_its_life_test() -> Nil {
  use <- owned_test.run(5000)
  let answer = fn(at, asked) {
    case at < 5000 {
      True -> landed(killed: 0)(at, asked)
      False -> Held
    }
  }
  let run = atomic_surge_run(answer:, until_ms: 20_000)
  assert list.map(strikes_of(run:), fn(strike) { strike.2 }) == [1, 2, 3]
    as "while the open round keeps the node, tick 4, due 5000 ms after the go, is past the node's life and is never asked"
  let assert [last] = run.held
    as "tick 3's strike, asked when the node's life ends 4000 ms after the go, is held open"
  assert last.tick == 3
  assert list.flat_map(run.steps, fn(step) {
      support.due_of(effects: step.1, now_ms: step.0)
    })
    |> list.all(fn(due) { due.0 <= 5000 })
    as "no timer is armed past the node's life, 4000 ms after the go"
  let closed =
    stepped(
      run:,
      at: 5100,
      taken: cast.ticked(
        cast: run.state,
        caster: support.caster(),
        now: support.at(ms: 5100),
        asked: last,
        struck: Some(tick_hit(asked: last, killed: 0)),
      ),
    )
  let #(finished_at, effects) = finish_step(run: closed)
  assert finished_at == 5100
  assert ticks_and_finish(effects:)
    == [spell_effect_tick.message_id, spell_finished.message_id]
    as "tick 3's close writes its 0x7f8, then the cast's 0x7fe"
  no_tick_after_finish(run: closed)
}

pub fn only_a_hit_or_immune_unit_gets_ticks_test() -> Nil {
  use <- owned_test.run(5000)
  let struck = [
    hit_ticking(unit_id: 10, ticking: surge_ticking()),
    cast.Deflected(unit_id: 11),
    cast.Immune(
      unit_id: 12,
      unit: cast.HitCreature(life: 1, struck_at_ms: press_ms),
      controls: [],
      armor_removed: 0,
      ticking: surge_ticking(),
    ),
  ]
  let run =
    pressed(
      plans: support.plans_of([surge()]),
      caster: support.caster(),
      struck:,
      answer: held,
    )
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 3000, struck:, answer: held)
    }
  assert list.map(run.held, fn(asked) { #(asked.unit_id, asked.life) })
    == [#(10, 3), #(12, 1)]
    as "the hit unit and the immune one each get their first tick, in the life the go struck; the deflected unit and the one the round left out get none"
}

pub fn a_later_go_restarts_the_schedule_test() -> Nil {
  use <- owned_test.run(5000)
  let twice = spell_plan.Spell(..surge(), phase_delays_ms: [0, 1000])
  let struck = [hit_ticking(unit_id: 10, ticking: surge_ticking())]
  let answer = landed(killed: 0)
  let run =
    pressed(
      plans: support.plans_of([twice]),
      caster: support.caster(),
      struck:,
      answer:,
    )
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 20_000, struck:, answer:)
    }
  assert strikes_of(run:) == [#(4000, 2, 1), #(6000, 2, 2), #(8000, 2, 3)]
    as "the second go at 2000 cancels the first go's tick and counts the schedule again from itself, as the client sets its node again (`opcode.0x7f4.effect_time`)"
  no_tick_after_finish(run:)
  // The first go's tick 1, at 3000, is held open past the second go at 4000.
  let later = spell_plan.Spell(..surge(), phase_delays_ms: [0, 3000])
  let answer = fn(at, asked) {
    case at {
      3000 -> Held
      _ -> landed(killed: 0)(at, asked)
    }
  }
  let open =
    pressed(
      plans: support.plans_of([later]),
      caster: support.caster(),
      struck:,
      answer:,
    )
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 4500, struck:, answer:)
    }
  let assert [first_round] = open.held
  assert #(first_round.go, first_round.tick) == #(1, 1)
  let assert Ok(#(4000, second_go)) = list.last(open.steps)
  let assert [#(second_tick, 2000), ..] =
    support.started_timers(effects: second_go)
    as "the second go arms its own tick 1, 2000 ms on"
  let #(_, shown) =
    cast.ticked(
      cast: open.state,
      caster: support.caster(),
      now: support.at(ms: 4500),
      asked: first_round,
      struck: Some(tick_hit(asked: first_round, killed: 0)),
    )
  assert list.map(ticks_of(effects: shown), fn(tick) {
      #(tick.spell4_effects_id, tick.unit_id)
    })
    == [#(96_125, 10)]
    as "the first go's round closing after the second go still writes its 0x7f8: the creature took the damage and its health news goes out"
  let #(_, killing) =
    cast.ticked(
      cast: open.state,
      caster: support.caster(),
      now: support.at(ms: 4500),
      asked: first_round,
      struck: Some(tick_hit(asked: first_round, killed: 1)),
    )
  assert list.length(ticks_of(effects: killing)) == 1
  assert list.contains(support.cancelled_timers(effects: killing), second_tick)
    as "and a killing one drops the unit's ticks, the second go's among them"
}

pub fn a_dropped_node_stops_its_ticks_test() -> Nil {
  use <- owned_test.run(5000)
  let capped = spell_plan.Spell(..surge(), stack: lasting_stack_of_one())
  let plans = support.plans_of([capped])
  let struck = [hit_ticking(unit_id: 10, ticking: surge_ticking())]
  let answer = landed(killed: 0)
  let first = pressed(plans:, caster: support.caster(), struck:, answer:)
  let assert [#(_, first_effects)] = first.steps
  let first_id = support.pressed_id(effects: first_effects)
  let assert [#(first_tick, 2000), ..] =
    support.started_timers(effects: first_effects)
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: first.state,
      caster: support.caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: 1500,
    )
  let #(state, second_effects, _) =
    settled(
      caster: support.caster(),
      state:,
      effects: raw,
      at: 1500,
      struck:,
      answer:,
    )
  let second_id = support.pressed_id(effects: second_effects)
  assert list.contains(
    support.cancelled_timers(effects: second_effects),
    first_tick,
  )
    as "the second cast pushes the first off the creature at the stack's cap, and the first cast's tick timer is cancelled with its node"
  let run =
    ran(
      caster: support.caster(),
      run: Run(
        state:,
        steps: [#(1500, second_effects)],
        pending: pending_after(
          pending: first.pending,
          effects: second_effects,
          at: 1500,
        ),
        held: [],
      ),
      until_ms: 20_000,
      struck:,
      answer:,
    )
  assert list.map(all_ticks(run:), fn(tick) { { tick.1 }.cast_id })
    == [second_id, second_id, second_id]
    as "every later 0x7f8 is the second cast's"
  assert first_id != second_id
  no_tick_after_finish(run:)
}

pub fn a_dead_target_gets_no_more_ticks_test() -> Nil {
  use <- owned_test.run(5000)
  let killing = surge_run(answer: landed(killed: 1))
  let assert [#(3000, tick)] = all_ticks(run: killing)
    as "the killing tick's 0x7f8 is written, and no tick follows it"
  assert list.map(tick.descriptions, fn(description) { description.killed })
    == [1]
  assert list.map(strikes_of(run: killing), fn(strike) { strike.0 }) == [3000]
    as "no later tick is asked of the dead creature"
  no_tick_after_finish(run: killing)
  let refused = surge_run(answer: fn(_, _) { Answered(struck: None) })
  assert all_ticks(run: refused) == []
    as "a tick the creature refuses writes nothing"
  assert list.map(strikes_of(run: refused), fn(strike) { strike.0 }) == [3000]
    as "and the unit's ticks stop"
}

pub fn ticks_due_together_go_in_key_order_test() -> Nil {
  use <- owned_test.run(5000)
  // A second row of the same schedule, planted beside Paralytic Surge's: the row ids
  // order the ticks of one unit.
  let other = DamageEffect(..surge_blow(), effect_id: Spell4EffectsId(96_126))
  let struck = [
    hit_ticking(unit_id: 10, ticking: [
      TickingDamage(damage: other, schedule: every_two_seconds()),
      TickingDamage(damage: surge_blow(), schedule: every_two_seconds()),
    ]),
  ]
  let run =
    pressed(
      plans: support.plans_of([surge()]),
      caster: support.caster(),
      struck:,
      answer: held,
    )
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 3000, struck:, answer: held)
    }
  let assert [_, #(3000, effects)] = run.steps
    as "both rows' first ticks fire in one step"
  assert list.map(tick_strikes(effects:), fn(asked) { asked.effect_id.value })
    == [96_125, 96_126]
    as "in row id order"
  let healing = heal_run(rows: [health_heal(schedule: every_two_seconds())])
  let assert Ok(#(7000, last)) = list.last(healing.steps)
  assert ids(effects: last)
    == [spell_effect_tick.message_id, spell_finished.message_id]
    as "a tick due with the node's end fires first in the same step, and the 0x7fe follows it"
  no_tick_after_finish(run: healing)
  // A connection fallen behind: only the node's end fires, at 7000, with all three
  // ticks overdue.
  let #(state, raw) =
    support.pressed_raw_in(
      plans: support.plans_of([
        spell_plan.Spell(..surge(), heals: [
          health_heal(schedule: every_two_seconds()),
        ]),
      ]),
      state: cast.new(),
      caster: healing_caster(),
      bag_index: bag_of_base_3,
      target: 0,
      at: press_ms,
    )
  let #(state, go, _) =
    settled(
      caster: healing_caster(),
      state:,
      effects: raw,
      at: press_ms,
      struck: [],
      answer: held,
    )
  let assert [_, #(nodes_end, 6000)] = support.started_timers(effects: go)
  let #(_, late) =
    support.fired_raw_as(
      caster: healing_caster(),
      state:,
      timer: nodes_end,
      at: 7000,
    )
  assert ids(effects: late)
    == [
      spell_effect_tick.message_id,
      spell_effect_tick.message_id,
      spell_effect_tick.message_id,
      spell_finished.message_id,
    ]
    as "every tick due at the node's end fires before it, each of the row's three overdue ticks, then the 0x7fe"
  assert support.started_timers(effects: late) == []
    as "and no tick is armed after the last"
}

pub fn a_tick_left_out_at_the_deadline_test() -> Nil {
  use <- owned_test.run(5000)
  let answer = fn(at, asked) {
    case at < 7000 {
      True -> landed(killed: 0)(at, asked)
      False -> Held
    }
  }
  let struck = [hit_ticking(unit_id: 10, ticking: surge_ticking())]
  let run =
    pressed(
      plans: support.plans_of([surge()]),
      caster: support.caster(),
      struck:,
      answer:,
    )
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 20_000, struck:, answer:)
    }
  let assert [last] = run.held
  let closed =
    stepped(
      run:,
      at: 8000,
      taken: cast.ticked(
        cast: run.state,
        caster: support.caster(),
        now: support.at(ms: 8000),
        asked: last,
        struck: None,
      ),
    )
  let assert Ok(#(_, effects)) = list.last(closed.steps)
  assert ids(effects:) == [spell_finished.message_id]
    as "the round left out at its deadline writes no 0x7f8, and the node it held ends with the cast's 0x7fe"
  let first =
    pressed(
      plans: support.plans_of([surge()]),
      caster: support.caster(),
      struck:,
      answer: held,
    )
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 3000, struck:, answer: held)
    }
  let assert [round] = first.held
  assert round.tick == 1
  let left_out =
    stepped(
      run: first,
      at: 4000,
      taken: cast.ticked(
        cast: first.state,
        caster: support.caster(),
        now: support.at(ms: 4000),
        asked: round,
        struck: None,
      ),
    )
  let assert Ok(#(_, effects)) = list.last(left_out.steps)
  assert ids(effects:) == [spell_finished.message_id]
    as "tick 1 of 3 left out at its deadline stops the unit's ticks and releases its node at once: the cast's 0x7fe goes then, not at the node's end at 7000"
  assert left_out.pending == []
    as "with the next tick's timer and the node's end cancelled"
}

pub fn a_removed_unit_writes_no_tick_test() -> Nil {
  use <- owned_test.run(5000)
  let struck = [hit_ticking(unit_id: 10, ticking: surge_ticking())]
  let run =
    pressed(
      plans: support.plans_of([surge()]),
      caster: support.caster(),
      struck:,
      answer: held,
    )
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 3000, struck:, answer: held)
    }
  let assert [first] = run.held
  let removed =
    stepped(
      run:,
      at: 3200,
      taken: cast.unit_removed(cast: run.state, unit_id: 10, now_ms: 3200),
    )
  assert removed.pending == []
    as "the removal drops the unit's node and cancels its next tick"
  let #(_, late) =
    cast.ticked(
      cast: removed.state,
      caster: support.caster(),
      now: support.at(ms: 3300),
      asked: first,
      struck: Some(tick_hit(asked: first, killed: 0)),
    )
  assert support.writes(effects: late) == []
    as "the tick whose round closes after the removal writes no 0x7f8"
  assert ticks_told(effects: late) == [] as "and tells no viewer of it"
}

pub fn a_restarted_creature_refuses_the_old_lifes_tick_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature's refusal of a tell for an old life reaches the cast as a round with
  // no answer for the unit (genesis_prime/game/strike `Ticked` with none).
  let answer = fn(at, asked) {
    case at {
      3000 -> landed(killed: 0)(at, asked)
      _ -> Answered(struck: None)
    }
  }
  let run = surge_run(answer:)
  assert list.map(strikes_of(run:), fn(strike) { strike.0 }) == [3000, 5000]
    as "the refused tick at 5000 is the unit's last"
  assert list.map(all_ticks(run:), fn(tick) { tick.0 }) == [3000]
  assert list.filter_map(run.steps, fn(step) {
      case
        support.frames_of(
          message_id: spell_finished.message_id,
          effects: step.1,
        )
      {
        [] -> Error(Nil)
        [_, ..] -> Ok(step.0)
      }
    })
    == [5000]
    as "the refused tick releases the unit's node at once: the cast's 0x7fe goes at 5000, not at the node's end at 7000"
}

pub fn a_dead_caster_ends_its_ticks_test() -> Nil {
  use <- owned_test.run(5000)
  let run = surge_run_until(until_ms: 3000)
  let #(_, effects) =
    cast.died(
      cast: run.state,
      caster: support.dead_caster(),
      now: support.at(ms: 3500),
    )
  assert list.contains(ids(effects:), spell_finished.message_id)
    as "the death writes the cast's 0x7fe"
  let cancelled = support.cancelled_timers(effects:)
  assert run.pending != []
  assert list.all(run.pending, fn(pending) {
    list.contains(cancelled, pending.1)
  })
    as "and cancels its next tick and its node's end, so no 0x7f8 follows"
  // The innate passive's cast is set aside by a death: its heal ticks go on, and one
  // that fires on the dead caster heals nothing.
  let passive =
    spell_plan.Spell(..support.child(spell4_id: 250_020, base: 250_020), heals: [
      health_heal(schedule: Schedule(
        delay_ms: 0,
        tick_ms: 1000,
        duration_ms: 3000,
        count: 3,
      )),
    ])
  let plans = support.plans_of([passive])
  let #(state, raw) =
    cast.passive_started(
      cast: cast.new(),
      caster: healing_caster(),
      plans:,
      base: Spell4BaseId(250_020),
      now: support.at(ms: press_ms),
    )
  let #(state, started, _) =
    settled(
      caster: healing_caster(),
      state:,
      effects: raw,
      at: press_ms,
      struck: [],
      answer: held,
    )
  let assert [#(tick_timer, 1000), ..] =
    support.started_timers(effects: started)
  let #(state, dying) =
    cast.died(
      cast: state,
      caster: cast.Caster(..healing_caster(), dead: True),
      now: support.at(ms: 1500),
    )
  assert !list.contains(support.cancelled_timers(effects: dying), tick_timer)
    as "the passive's tick survives the death"
  let #(_, fired) =
    support.fired_raw_as(
      caster: cast.Caster(..healing_caster(), dead: True),
      state:,
      timer: tick_timer,
      at: 2000,
    )
  assert ticks_of(effects: fired) == []
    as "a tick on the dead caster writes no 0x7f8"
  assert heals(effects: fired) == [] as "and heals nothing"
  assert list.map(support.started_timers(effects: fired), fn(started) {
      started.1
    })
    == [1000]
    as "and the next tick is armed"
}

pub fn a_heal_tick_heals_the_caster_each_tick_test() -> Nil {
  use <- owned_test.run(5000)
  let schedule =
    Schedule(delay_ms: 0, tick_ms: 1000, duration_ms: 3000, count: 3)
  let run = heal_run(rows: [health_heal(schedule:)])
  let assert [#(_, go), ..ticks] = run.steps
  assert heals(effects: go) == [] as "the go heals nothing itself"
  let cast_id = support.pressed_id(effects: go)
  assert list.map(ticks, fn(step) {
      #(step.0, ticks_of(effects: step.1), heals(effects: step.1))
    })
    == list.map([2000, 3000, 4000], fn(at) {
      #(
        at,
        [
          SpellEffectTick(
            cast_id:,
            spell4_effects_id: 62_019,
            unit_id: 7,
            descriptions: [
              heal_description(amount: 121, kind: damage_type.Heal),
            ],
          ),
        ],
        [#(62_019, effect_kind.Health, 121)],
      )
    })
    as "each tick writes a 0x7f8 to the caster with the heal's description and heals it by Mind Over Body's 121 (see `healing_caster`)"
  let assert [#(_, first_tick), ..] = ticks
  assert first_written_before_heal(effects: first_tick)
    as "the 0x7f8 comes before the heal it shows"
  assert list.map(ticks_told(effects: first_tick), fn(tell) { tell.0 })
    == [step.ConnectionId(2), step.ConnectionId(3)]
    as "and the audience is told each tick"
  let shields = heal_run(rows: [shield_heal(schedule:)])
  let assert [_, #(_, first_shield), ..] = shields.steps
  assert list.map(ticks_of(effects: first_shield), fn(tick) {
      tick.descriptions
    })
    == [[heal_description(amount: 56, kind: damage_type.HealShields)]]
    as "a HealShields tick shows 0.125 of the 450 maximum shield, 56.25, rounded to 56"
  assert heals(effects: first_shield) == [#(210_834, effect_kind.Shield, 56)]
  let both = heal_run(rows: [shield_heal(schedule:), health_heal(schedule:)])
  let assert [_, #(_, first_both), ..] = both.steps
  assert list.map(ticks_of(effects: first_both), fn(tick) {
      tick.spell4_effects_id
    })
    == [62_019, 210_834]
    as "two heal rows due at once each write their 0x7f8, in row id order"
  assert list.map(heals(effects: first_both), fn(heal) { heal.0 })
    == [62_019, 210_834]
    as "and each heals once"
  // A second row of Mind Over Body's formula, planted beside it on the same vital.
  let twice =
    heal_run(rows: [
      health_heal(schedule:),
      health_heal_of(effect_id: 62_020, schedule:),
    ])
  let assert [_, #(_, first_twice), ..] = twice.steps
  assert list.map(ticks_of(effects: first_twice), fn(tick) {
      #(tick.spell4_effects_id, tick.descriptions)
    })
    == [
      #(62_019, [heal_description(amount: 121, kind: damage_type.Heal)]),
      #(62_020, [
        SpellDamageDescription(
          ..heal_description(amount: 121, kind: damage_type.Heal),
          overkill: 6,
        ),
      ]),
    ]
    as "two health ticks due at once: the first takes 121 of the 236 room (736 - 500), and the second reads the 115 left, so 6 of its 121 is overheal"
}

pub fn a_cancel_keeps_ticks_and_an_interrupt_ends_them_test() -> Nil {
  use <- owned_test.run(5000)
  let twice = spell_plan.Spell(..surge(), phase_delays_ms: [0, 1000])
  let plans = support.plans_of([twice])
  let struck = [hit_ticking(unit_id: 10, ticking: surge_ticking())]
  let answer = landed(killed: 0)
  let first = pressed(plans:, caster: support.caster(), struck:, answer:)
  let assert [#(_, press)] = first.steps
  let assert Ok(taken) =
    support.cancelled_in(
      plans:,
      state: first.state,
      cast_id: support.pressed_id(effects: press),
      reason: cast_result.from_value(11),
      bit: 1,
      at: 1500,
    )
  let run =
    stepped(run: first, at: 1500, taken:)
    |> fn(run) {
      ran(caster: support.caster(), run:, until_ms: 20_000, struck:, answer:)
    }
  assert list.map(all_ticks(run:), fn(tick) { tick.0 }) == [3000, 5000, 7000]
    as "a 0x801 after the first go keeps its ticks to the node's end"
  no_tick_after_finish(run:)
  let persisting =
    spell_plan.Spell(
      ..surge(),
      caster_persistence: Some(
        prerequisites.single(id: 903, condition: #(28, 1, 0, 0)),
      ),
    )
  let in_combat = support.caster_in_combat(in_combat: True)
  let kept =
    pressed(
      plans: support.plans_of([persisting]),
      caster: in_combat,
      struck:,
      answer:,
    )
    |> fn(run) {
      ran(caster: in_combat, run:, until_ms: 3000, struck:, answer:)
    }
  let ended =
    stepped(
      run: kept,
      at: 3500,
      taken: cast.persisted(
        cast: kept.state,
        caster: support.caster_in_combat(in_combat: False),
        now: support.at(ms: 3500),
      ),
    )
  let assert Ok(#(_, effects)) = list.last(ended.steps)
  assert list.first(ids(effects:)) == Ok(cast_result_failed_id())
    as "the persistence's end writes the cast's 0x7f9"
  assert ended.pending == []
    as "and cancels every tick timer of the cast, so no 0x7f8 follows"
}

// ---- heal rows ----

/// A heal row of Mind Over Body's formula (Spell4Effects 62019: 0.3281 of Support Power
/// and 17.51 a level), planted as periodic on the caster with this schedule.
fn health_heal(schedule schedule: ticking.Schedule) -> spell_plan.Heal {
  health_heal_of(effect_id: 62_019, schedule:)
}

/// Mind Over Body's heal row under the id `effect_id`.
fn health_heal_of(
  effect_id effect_id: Int,
  schedule schedule: ticking.Schedule,
) -> spell_plan.Heal {
  spell_plan.TickingHeal(
    effect_id: Spell4EffectsId(effect_id),
    vital: effect_kind.Health,
    phase_flags: -1,
    aim: AimsAtCaster,
    condition: spell_plan.Always,
    tag: spend.always,
    formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
      Parameter(kind: 13, value: 0.3281),
      Parameter(kind: 10, value: 17.51),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ]),
    schedule:,
  )
}

/// Row 210834: 0.125 of the maximum shield each tick.
fn shield_heal(schedule schedule: ticking.Schedule) -> spell_plan.Heal {
  spell_plan.TickingHeal(
    effect_id: Spell4EffectsId(210_834),
    vital: effect_kind.Shield,
    phase_flags: -1,
    aim: AimsAtCaster,
    condition: spell_plan.Always,
    tag: spend.always,
    formula: Formula(multiplier: 1.0, base: 0.0, parameters: [
      Parameter(kind: 16, value: 0.125),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
      Parameter(kind: 0, value: 0.0),
    ]),
    schedule:,
  )
}

/// The caster of level 5 and 400 Support Rating, with 500 of its 736 health and 250 of
/// its 450 shield: Mind Over Body's formula reads it as round(0.3281 x 100) + 17.51 x 5 =
/// 33 + 87.55 = 120.55, which is 121 (the stat part is rounded alone, `0x140565600`).
fn healing_caster() -> Caster {
  cast.Caster(
    ..support.caster(),
    stats: damage.Attacker(
      ..attacker_support.fresh(),
      level: 5,
      assault_rating: 0.0,
      support_rating: 400.0,
    ),
    vitals: damage.Vitals(
      health: 500,
      max_health: 736,
      shield: 250,
      max_shield: 450,
    ),
  )
}

/// A cast of base 3 with these heal rows to its end, its go striking nothing.
fn heal_run(rows rows: List(spell_plan.Heal)) -> Run {
  let spell = spell_plan.Spell(..surge(), heals: rows)
  pressed(
    plans: support.plans_of([spell]),
    caster: healing_caster(),
    struck: [],
    answer: held,
  )
  |> fn(run) {
    ran(
      caster: healing_caster(),
      run:,
      until_ms: 20_000,
      struck: [],
      answer: held,
    )
  }
}

fn surge_run_until(until_ms until_ms: Int) -> Run {
  let struck = [hit_ticking(unit_id: 10, ticking: surge_ticking())]
  let answer = landed(killed: 0)
  pressed(
    plans: support.plans_of([surge()]),
    caster: support.caster(),
    struck:,
    answer:,
  )
  |> fn(run) {
    ran(caster: support.caster(), run:, until_ms:, struck:, answer:)
  }
}

/// The heals the effects start, as the row, the vital and the amount.
fn heals(
  effects effects: List(Effect),
) -> List(#(Int, effect_kind.Vital, Int)) {
  list.filter_map(support.caster_change_starts(effects:), fn(start) {
    case start.1 {
      cast.Heal(vital:, amount:) ->
        Ok(#({ start.0 }.effect_id.value, vital, amount))
      cast.Property(..) | cast.Look(..) | cast.Absorb(..) -> Error(Nil)
    }
  })
}

fn first_written_before_heal(effects effects: List(Effect)) -> Bool {
  let #(before, from_heal) =
    list.split_while(effects, fn(effect) {
      support.caster_change_starts(effects: [effect]) == []
    })
  let ticks_in = fn(effects) {
    support.frames_of(message_id: spell_effect_tick.message_id, effects:)
  }
  list.length(ticks_in(before)) == 1
  && list.length(support.caster_change_starts(effects: from_heal)) == 1
  && ticks_in(from_heal) == []
}

fn heal_description(
  amount amount: Int,
  kind kind: damage_type.DamageType,
) -> SpellDamageDescription {
  SpellDamageDescription(
    raw_damage: amount,
    scaled_raw_damage: amount,
    absorbed: 0,
    shield_absorbed: 0,
    health_damage_with_overkill: amount,
    overkill: 0,
    glance: 0,
    killed: 0,
    combat_result: combat_result.Hit,
    damage_type: kind,
    hits: [],
  )
}

fn lasting_stack_of_one() -> lasting.Stack {
  lasting.Stack(group_id: 1, cap: 1)
}

fn cast_result_failed_id() -> Int {
  spell_failed.message_id
}
