//// What the cast rule's tests share: the abilities as the plan holds them, built
//// from the client's rows the fact file records (each value named where it is
//// set), a caster, the bytes of the client's presses and cancels, and helpers
//// that find the writes, the tells and the timers in a step's effects.
////
//// Four spells are planted, not client rows, because no level-1 ability has
//// global cooldown kind 2, a cast bar that lets a press through, a cast time
//// with a cooldown of its own, or a cast method the rule does not cast:
//// `blocked_only` (kind 2), `exempt`, `slow` and `unbuilt` (PressHold).

import game_client
import genesis_prime/client_connection.{type News}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, AtFirstGo, GlobalCooldown, NoWeaponNeeded, Normal,
  Spell,
}
import genesis_prime/message/cancel_cast.{CancelCast}
import genesis_prime/message/cast_result.{type CastResult}
import genesis_prime/step.{
  type ConnectionId, type Now, type TimerId, ConnectionId, Now,
}
import genesis_prime/table/id.{
  type Spell4BaseId, Item2Id, Spell4BaseId, Spell4Id,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import place_support
import spell_tables

/// A child spell the client's row gives these ids: no cast time, no cooldown, no
/// range, kind 3 (`opcode.0x7ff.root_parent`: the global cooldown kind of every
/// child of the nine abilities).
pub fn child(spell4_id spell4_id: Int, base base: Int) -> Spell {
  Spell(
    spell4_id: Spell4Id(spell4_id),
    spell4_base_id: Spell4BaseId(base),
    method: Normal,
    cast_time_ms: 0,
    cooldown_ms: 0,
    cast_bar: spell_plan.HidesCastBar,
    free_while_live: False,
    ignores_casting: False,
    weapon: NoWeaponNeeded,
    global_cooldown: GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: None,
    ),
    unpayable_cost: None,
    phase_delays_ms: [],
    threshold_ms: 0,
    stages: [],
    channel: None,
    proxies: [],
    cooldown_start: AtFirstGo,
    cooldown_phase: None,
  )
}

/// A planted spell with a cast time of 1000 ms and a cast bar whose live cast
/// leaves the caster free to press another (`0x1403afb10`).
pub fn exempt() -> Spell {
  Spell(
    ..child(spell4_id: 1, base: 1),
    cast_time_ms: 1000,
    cast_bar: spell_plan.ShowsCastBar,
    free_while_live: True,
  )
}

/// A planted spell of global cooldown kind 2: refused while it runs, starting none.
pub fn blocked_only() -> Spell {
  Spell(
    ..child(spell4_id: 2, base: 2),
    global_cooldown: GlobalCooldown(
      refused_while_running: True,
      starts_for_ms: None,
    ),
  )
}

/// A planted spell with a cast time of 1000 ms and a cooldown of 5000 ms, kind 3,
/// for the rule that the spell's own cooldown runs from its first go.
pub fn slow() -> Spell {
  Spell(..child(spell4_id: 3, base: 3), cast_time_ms: 1000, cooldown_ms: 5000)
}

/// The abilities by bag index, as Spell4Base ids: 0 Telekinetic Strike, 1 Crush,
/// 2 Mind Burst, 3 Kick, 4 Stagger, 5 Gate, 6 Gamma Rays, 7 Electrocute, 8 the
/// exempt spell, 9 Zap, 10 the kind 2 spell, 11 the slow spell, 12 Pulse Blast,
/// 13 Quick Draw, 14 Discharge, 15 Shred, 16 Relentless Strikes, 17 Rampage,
/// 18 Charged Shot, 19 Impale and 20 the PressHold spell.
pub fn abilities() -> List(Spell4BaseId) {
  list.map(
    [
      19_102, 19_022, 19_019, 38_017, 23_173, 20_325, 16_322, 25_473, 1, 25_635,
      2, 3, 26_468, 27_638, 38_201, 23_148, 18_309, 37_968, 20_684, 23_161, 4,
    ],
    Spell4BaseId,
  )
}

pub const pulse_blast = 12

pub const quick_draw = 13

pub const discharge = 14

pub const shred = 15

pub const relentless_strikes = 16

pub const rampage = 17

pub const charged_shot = 18

pub const impale = 19

pub const unbuilt_bag_index = 20

/// A planted spell of the PressHold method, which the rule does not cast
/// (`Spell.CodeEnumCastMethod`).
pub fn unbuilt() -> Spell {
  Spell(..child(spell4_id: 4, base: 4), method: spell_plan.PressHold)
}

/// The plans of the abilities above: the client's trees as `spell_plan.build`
/// makes them from the planted rows (`spell_tables`, each value the client's own
/// row), and the three planted spells by hand.
pub fn plans() -> Plans {
  with_spells(plans: spell_tables.default_plans(), spells: [
    exempt(),
    blocked_only(),
    slow(),
    unbuilt(),
  ])
}

/// The plans with these spells in place of the ability of the same Spell4Base id.
pub fn with_spells(plans plans: Plans, spells spells: List(Spell)) -> Plans {
  list.fold(spells, plans, fn(plans, spell) {
    dict.insert(plans, spell.spell4_base_id.value, spell)
  })
}

/// The ability of the Spell4Base id as the plans hold it.
pub fn ability(base base: Int) -> Spell {
  let assert Ok(spell) =
    spell_plan.in_plans(plans: plans(), base: Spell4BaseId(base))
    as "the plans hold the ability"
  spell
}

/// The player 7 with the abilities above and its weapon, seen by the connections
/// 2 and 3, standing at the live character's place.
pub fn caster() -> Caster {
  let place = place_support.live_character_place()
  cast.Caster(
    unit_id: 7,
    place:,
    abilities: abilities(),
    weapon: Some(Item2Id(81_351)),
    audience: set.from_list([ConnectionId(2), ConnectionId(3)]),
  )
}

/// The input time: a monotonic time, the system time 0.
pub fn at(ms ms: Int) -> Now {
  Now(monotonic_ms: ms, filetime: 0)
}

/// The body of the client's 0x9a (opcode.0x9a): its cast id, the bag index, the
/// target and the press bit.
pub fn press_body(
  client_cast_id client_cast_id: Int,
  bag_index bag_index: Int,
  target target: Int,
  press press: Int,
) -> BitArray {
  game_client.press_body(client_cast_id:, bag_index:, target:, press:)
}

/// The body of the client's 0x801 (opcode.0x801): the server's cast id, the
/// reason and the bit.
pub fn cancel_body(
  cast_id cast_id: Int,
  reason reason: CastResult,
  bit bit: Int,
) -> BitArray {
  let assert Ok(body) =
    cancel_cast.encode(CancelCast(cast_id:, reason:, field_3: bit))
    as "the cancel fits the message"
  body
}

/// A press of the bag index at the time, with the client's cast id 9 and the
/// target given, taken by the rule; it must be taken, not refused.
pub fn pressed(
  state state: State,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_by(state:, caster: caster(), bag_index:, target:, at: ms)
}

pub fn pressed_by(
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_in(plans: plans(), state:, caster:, bag_index:, target:, at: ms)
}

/// A press at the time of an ability of the plans given.
pub fn pressed_in(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    cast.take(
      cast: state,
      message: cast.Pressed,
      body: press_body(client_cast_id: 9, bag_index:, target:, press: 1),
      caster:,
      plans:,
      now: at(ms:),
    )
    as "the press is taken: a refusal of the client's own checks is a 0x7fc, never an error"
  taken
}

/// The client's 0x801 at the time, taken by the rule.
pub fn cancelled(
  state state: State,
  cast_id cast_id: Int,
  reason reason: CastResult,
  bit bit: Int,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast.Refusal) {
  cast.take(
    cast: state,
    message: cast.Cancelled,
    body: cancel_body(cast_id:, reason:, bit:),
    caster: caster(),
    plans: plans(),
    now: at(ms:),
  )
}

/// What the client is written, in order.
pub fn writes(effects effects: List(Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.Send(frame:) -> Ok(frame)
      cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..) -> Error(Nil)
    }
  })
}

/// What viewers are told, by connection, in order.
pub fn tells(effects effects: List(Effect)) -> List(#(ConnectionId, News)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.Tell(to:, news:) -> Ok(#(to, news))
      cast.Send(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..) -> Error(Nil)
    }
  })
}

/// The timers started, with their delays, in order.
pub fn started_timers(effects effects: List(Effect)) -> List(#(TimerId, Int)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.StartTimer(timer:, after_ms:) -> Ok(#(timer, after_ms))
      cast.Send(..) | cast.Tell(..) | cast.CancelTimer(..) | cast.Log(..) ->
        Error(Nil)
    }
  })
}

/// The timers cancelled, in order.
pub fn cancelled_timers(effects effects: List(Effect)) -> List(TimerId) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.CancelTimer(timer:) -> Ok(timer)
      cast.Send(..) | cast.Tell(..) | cast.StartTimer(..) | cast.Log(..) ->
        Error(Nil)
    }
  })
}

/// Fires a timer at the time.
pub fn fired(
  state state: State,
  timer timer: TimerId,
  at ms: Int,
) -> #(State, List(Effect)) {
  cast.timer_fired(cast: state, timer:, caster: caster(), now: at(ms:))
}

/// A frame's message id.
pub fn ids(frames frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

/// Fires every timer a step started, earliest first, and each timer those steps
/// start, until none is left: the time each fired at (`from_ms` plus the delays
/// that led to it) with the effects of its step. The clock is the test's.
pub fn run_timers(
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
) -> #(State, List(#(Int, List(Effect)))) {
  run_pending(
    state:,
    pending: due_of(effects:, now_ms: from_ms),
    fired_so_far: [],
  )
}

fn due_of(
  effects effects: List(Effect),
  now_ms now_ms: Int,
) -> List(#(Int, TimerId)) {
  list.map(started_timers(effects:), fn(started) {
    #(now_ms + started.1, started.0)
  })
}

fn run_pending(
  state state: State,
  pending pending: List(#(Int, TimerId)),
  fired_so_far fired_so_far: List(#(Int, List(Effect))),
) -> #(State, List(#(Int, List(Effect)))) {
  case
    list.sort(pending, fn(first, second) { int.compare(first.0, second.0) })
  {
    [] -> #(state, list.reverse(fired_so_far))
    [#(due, timer), ..rest] -> {
      let #(state, effects) = fired(state:, timer:, at: due)
      let cancelled = cancelled_timers(effects:)
      run_pending(
        state:,
        pending: list.append(
          list.filter(rest, fn(other) { !list.contains(cancelled, other.1) }),
          due_of(effects:, now_ms: due),
        ),
        fired_so_far: [#(due, effects), ..fired_so_far],
      )
    }
  }
}
