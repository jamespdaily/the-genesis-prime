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
import genesis_prime/game/class_resource
import genesis_prime/game/lasting
import genesis_prime/game/spell_plan.{
  type Plans, type Spell, AtFirstGo, GlobalCooldown, NoWeaponNeeded, Normal,
  Spell,
}
import genesis_prime/message/cancel_cast.{CancelCast}
import genesis_prime/message/cast_result.{type CastResult}
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_stack_removed
import genesis_prime/message/spell_targets_removed
import genesis_prime/step.{
  type ConnectionId, type LogLevel, type Now, type TimerId, ConnectionId, Now,
}
import genesis_prime/table/id.{
  type Spell4BaseId, Item2Id, Spell4BaseId, Spell4Id,
}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import place_support
import spell_tables

/// A child spell the client's row gives these ids: no cast time, no cooldown, no
/// range, kind 3 (`opcode.0x7ff.root_parent`: the global cooldown kind of every
/// child of the nine abilities), and the dead bit of caster condition row 1, which
/// most of those children name (`Spell4.spell4ConditionsIdCaster`).
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
    longer_of_delay_and_duration: False,
    weapon: NoWeaponNeeded,
    caster_death: spell_plan.CannotBeDead,
    global_cooldown: GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: None,
    ),
    costs: [],
    requirements: [],
    requirement_waiver: None,
    phase_delays_ms: [],
    threshold_ms: 0,
    stages: [],
    channel: None,
    proxies: [],
    gains: [],
    groups: [],
    stack: lasting.Stack(group_id: 0, cap: 0),
    lasting: [],
    removes: [],
    modifiers: [],
    forced_moves: [],
    controls: [],
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
/// 2 and 3, standing at the live character's place, holding `full_slot_1`.
pub fn caster() -> Caster {
  let place = place_support.live_character_place()
  cast.Caster(
    unit_id: 7,
    place:,
    abilities: abilities(),
    weapon: Some(Item2Id(81_351)),
    audience: set.from_list([ConnectionId(2), ConnectionId(3)]),
    dead: False,
    resources: class_resource.new(resource: full_slot_1()),
    in_combat: False,
    life_vitals: dict.new(),
  )
}

/// A planted resource of 1000 points in slot 1, full: it meets every level-1 cost
/// and requirement of slot 1 (Mind Burst's 1, Electrocute's 8, Gamma Rays' 2,
/// Rampage's at least 250), so a test that is not about resources is not refused
/// for one, and holds nothing in slot 3 (Impale's 35).
pub fn full_slot_1() -> class_resource.Resource {
  class_resource.Resource(
    slot: 1,
    max: 1000.0,
    start: 1000.0,
    regen: None,
    refill_after_combat_ms: None,
    drain: None,
    empty_after_combat_ms: None,
  )
}

/// The caster holding `resources` in place of `full_slot_1`.
pub fn caster_holding(resources resources: class_resource.Resources) -> Caster {
  cast.Caster(..caster(), resources:)
}

/// What the presses of a step paid, in order.
pub fn payments(effects effects: List(Effect)) -> List(class_resource.Payment) {
  list.flat_map(effects, fn(effect) {
    case effect {
      cast.Pay(payments:) -> payments
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Strike(..)
      | cast.Gain(..)
      | cast.Log(..)
      | cast.PropertyStarts(..)
      | cast.PropertyEnds(..) -> []
    }
  })
}

/// The `Gain` effects of the steps, each its list of gains, in order.
pub fn gains(effects effects: List(Effect)) -> List(List(class_resource.Gain)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.Gain(gains:) -> Ok(gains)
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Strike(..)
      | cast.Pay(..)
      | cast.Log(..)
      | cast.PropertyStarts(..)
      | cast.PropertyEnds(..) -> Error(Nil)
    }
  })
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

/// The body of the client's 0x4db (opcode.0x4db): the bag index, the target and
/// the held bit.
pub fn hold_body(
  bag_index bag_index: Int,
  target target: Int,
  held held: Int,
) -> BitArray {
  game_client.hold_body(bag_index:, target:, held:)
}

/// The key of the bag index goes down (`held` 1) or up (`held` 0) at the time, for
/// the abilities of the plans given, taken by the rule; it must be taken, not
/// refused. A go it asks for is a `Strike` effect, not yet written.
pub fn key_raw_in(
  plans plans: Plans,
  state state: State,
  bag_index bag_index: Int,
  held held: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    cast.take(
      cast: state,
      message: cast.KeyHeld,
      body: hold_body(bag_index:, target: 0, held:),
      caster: caster(),
      plans:,
      now: at(ms:),
    )
    as "a 0x4db that fits the message is taken"
  taken
}

/// The same, with each go answered as a round that struck nobody.
pub fn key_in(
  plans plans: Plans,
  state state: State,
  bag_index bag_index: Int,
  held held: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) = key_raw_in(plans:, state:, bag_index:, held:, at: ms)
  answered_with_no_targets(state:, effects:, at: ms)
}

/// The plans with Mind Burst (bag index 2) costless: it costs 1 Psi Point
/// (`Spell4CastResult.vital_cost`), and a test of the repeat is not about paying it.
/// Every other value is the client's row.
pub fn plans_with_costless_mind_burst() -> Plans {
  with_spells(plans: plans(), spells: [
    Spell(..ability(base: 19_019), costs: []),
  ])
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

/// A press at the time of an ability of the plans given, taken by the rule, and its
/// go answered as a round that struck nobody.
pub fn pressed_in(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    pressed_raw_in(plans:, state:, caster:, bag_index:, target:, at: ms)
  answered_with_no_targets(state:, effects:, at: ms)
}

/// A press whose go, and each go it leads to at once, strikes these units.
pub fn pressed_striking(
  state state: State,
  bag_index bag_index: Int,
  struck struck: List(cast.Struck),
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    pressed_raw(state:, caster: caster(), bag_index:, target: 0, at: ms)
  answered_by(state:, effects:, at: ms, struck:)
}

/// A press of the bag index, as the rule gives it: a go it asks for is a `Strike`
/// effect, not yet written.
pub fn pressed_raw(
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_raw_in(plans: plans(), state:, caster:, bag_index:, target:, at: ms)
}

/// A press at the time of an ability of the plans given, as the rule gives it.
pub fn pressed_raw_in(
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

/// The client's 0x801 at the time, taken by the rule with these plans.
pub fn cancelled_in(
  plans plans: Plans,
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
    plans:,
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
      | cast.Strike(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.PropertyStarts(..)
      | cast.PropertyEnds(..) -> Error(Nil)
    }
  })
}

/// The frames of the effects written to the client that carry this message id.
pub fn frames_of(
  message_id message_id: Int,
  effects effects: List(Effect),
) -> List(Frame) {
  list.filter(writes(effects:), fn(frame) { frame.message_id == message_id })
}

/// The cast id of a 0x7fe frame.
pub fn finished_cast_id(frame: Frame) -> Int {
  let assert Ok(finished) = spell_finished.decode(frame.body)
    as "a 0x7fe the rule wrote decodes"
  finished.cast_id
}

/// The cast ids of the 0x7fe frames among the frames, in order.
pub fn finished_ids(frames: List(Frame)) -> List(Int) {
  list.filter(frames, fn(frame) {
    frame.message_id == spell_finished.message_id
  })
  |> list.map(finished_cast_id)
}

/// The 0x811 frames among the frames, each as the cast id and the unit ids.
pub fn removed_targets(frames: List(Frame)) -> List(#(Int, List(Int))) {
  list.filter(frames, fn(frame) {
    frame.message_id == spell_targets_removed.message_id
  })
  |> list.map(fn(frame) {
    let assert Ok(removed) = spell_targets_removed.decode(frame.body)
      as "a 0x811 the rule wrote decodes"
    #(removed.cast_id, removed.unit_ids)
  })
}

/// The 0x813 frames among the frames, each as the cast id and the unit id.
pub fn removed_stacks(frames: List(Frame)) -> List(#(Int, Int)) {
  list.filter(frames, fn(frame) {
    frame.message_id == spell_stack_removed.message_id
  })
  |> list.map(fn(frame) {
    let assert Ok(removed) = spell_stack_removed.decode(frame.body)
      as "a 0x813 the rule wrote decodes"
    #(removed.cast_id, removed.unit_id)
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
      | cast.Strike(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.PropertyStarts(..)
      | cast.PropertyEnds(..) -> Error(Nil)
    }
  })
}

/// The log lines written, with their levels, in order.
pub fn logs(effects effects: List(Effect)) -> List(#(LogLevel, String)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.Log(level:, text:) -> Ok(#(level, text))
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Strike(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.PropertyStarts(..)
      | cast.PropertyEnds(..) -> Error(Nil)
    }
  })
}

/// The timers started, with their delays, in order.
pub fn started_timers(effects effects: List(Effect)) -> List(#(TimerId, Int)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.StartTimer(timer:, after_ms:) -> Ok(#(timer, after_ms))
      cast.Send(..)
      | cast.Tell(..)
      | cast.CancelTimer(..)
      | cast.Strike(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.PropertyStarts(..)
      | cast.PropertyEnds(..) -> Error(Nil)
    }
  })
}

/// The timers cancelled, in order.
pub fn cancelled_timers(effects effects: List(Effect)) -> List(TimerId) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast.CancelTimer(timer:) -> Ok(timer)
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.Strike(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.PropertyStarts(..)
      | cast.PropertyEnds(..) -> Error(Nil)
    }
  })
}

/// Fires a timer at the time, and answers every go it asks for with no target, as a
/// caster with no foe in its area is answered: the rule's tests that are not about
/// targets read the go as written at once.
pub fn fired(
  state state: State,
  timer timer: TimerId,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) = fired_raw(state:, timer:, at: ms)
  answered_with_no_targets(state:, effects:, at: ms)
}

/// Fires a timer at the time, as the rule gives it.
pub fn fired_raw(
  state state: State,
  timer timer: TimerId,
  at ms: Int,
) -> #(State, List(Effect)) {
  cast.timer_fired(cast: state, timer:, caster: caster(), now: at(ms:))
}

/// Each `Strike` effect replaced, in place, by what `went` gives for a round that struck
/// nobody; the effects it gives are answered the same way.
pub fn answered_with_no_targets(
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
) -> #(State, List(Effect)) {
  answered_by(state:, effects:, at: ms, struck: [])
}

/// `cast.went` for a round whose go checks no type 37 condition, so it takes no roll.
pub fn went(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(cast.Struck),
) -> #(State, List(Effect)) {
  cast.went(cast:, caster:, now:, cast_id:, phase:, struck:, rolls: [])
}

/// Each `Strike` effect replaced, in place, by what `went` gives for a round that struck
/// these units; the effects it gives are answered the same way.
pub fn answered_by(
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck struck: List(cast.Struck),
) -> #(State, List(Effect)) {
  answered_as(caster: caster(), state:, effects:, at: ms, struck:, rolls: [])
}

/// The same for this caster, each go taking these rolls for its type 37
/// conditions.
pub fn answered_as(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck struck: List(cast.Struck),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  list.fold(effects, #(state, []), fn(so_far, effect) {
    let #(state, done) = so_far
    case effect {
      cast.Strike(asked:) -> {
        let #(state, going) =
          cast.went(
            cast: state,
            caster:,
            now: at(ms:),
            cast_id: asked.cast_id,
            phase: asked.phase,
            struck:,
            rolls:,
          )
        let #(state, more) =
          answered_as(caster:, state:, effects: going, at: ms, struck:, rolls:)
        #(state, list.append(done, more))
      }
      cast.Send(..)
      | cast.Tell(..)
      | cast.StartTimer(..)
      | cast.CancelTimer(..)
      | cast.Log(..)
      | cast.Pay(..)
      | cast.Gain(..)
      | cast.PropertyStarts(..)
      | cast.PropertyEnds(..) -> #(state, list.append(done, [effect]))
    }
  })
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
  run_timers_striking(state:, effects:, from_ms:, struck: [])
}

/// The same, with each go striking these units.
pub fn run_timers_striking(
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  struck struck: List(cast.Struck),
) -> #(State, List(#(Int, List(Effect)))) {
  run_pending(
    state:,
    pending: due_of(effects:, now_ms: from_ms),
    fired_so_far: [],
    struck:,
    until_ms: None,
  )
}

/// The same for a state that repeats, which never runs out of timers: only the
/// timers due at `until_ms` or before fire, and the ones due later are left, as the
/// clock the test drives has not reached them.
pub fn run_timers_until(
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  until_ms until_ms: Int,
) -> #(State, List(#(Int, List(Effect)))) {
  run_pending(
    state:,
    pending: due_of(effects:, now_ms: from_ms),
    fired_so_far: [],
    struck: [],
    until_ms: Some(until_ms),
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
  struck struck: List(cast.Struck),
  until_ms until_ms: Option(Int),
) -> #(State, List(#(Int, List(Effect)))) {
  let limit = option.unwrap(until_ms, 9_007_199_254_740_991)
  case
    list.sort(pending, fn(first, second) { int.compare(first.0, second.0) })
  {
    [] -> #(state, list.reverse(fired_so_far))
    [#(due, _), ..] if due > limit -> #(state, list.reverse(fired_so_far))
    [#(due, timer), ..rest] -> {
      let #(state, raw) = fired_raw(state:, timer:, at: due)
      let #(state, effects) =
        answered_by(state:, effects: raw, at: due, struck:)
      let cancelled = cancelled_timers(effects:)
      run_pending(
        state:,
        pending: list.append(
          list.filter(rest, fn(other) { !list.contains(cancelled, other.1) }),
          due_of(effects:, now_ms: due),
        ),
        fired_so_far: [#(due, effects), ..fired_so_far],
        struck:,
        until_ms:,
      )
    }
  }
}

/// What a client reads of the casts among its frames, as one line each, the
/// casts named k1, k2 and so on in the order their ids first appear.
pub fn cast_lines(frames frames: List(Frame)) -> List(String) {
  let events = game_client.casts_in(frames:)
  let ids =
    list.filter_map(events, fn(event) {
      case event {
        game_client.CastConfirmed(server_cast_id:, ..) -> Ok(server_cast_id)
        game_client.CastStarted(cast_id:, ..)
        | game_client.CastWent(cast_id:, ..)
        | game_client.CastFinished(cast_id:) -> Ok(cast_id)
        game_client.CastRefused(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..) -> Error(Nil)
      }
    })
    |> list.unique
  let label = fn(id) {
    let assert Ok(position) =
      list.index_map(ids, fn(known, position) { #(known, position) })
      |> list.key_find(id)
      as "every cast id of a line was read before"
    "k" <> int.to_string(position + 1)
  }
  list.map(events, fn(event) {
    case event {
      game_client.CastRefused(spell4_id:, result:, ..) ->
        "refused " <> int.to_string(spell4_id) <> " " <> int.to_string(result)
      game_client.CastConfirmed(server_cast_id:, ..) ->
        "confirmed " <> label(server_cast_id)
      game_client.CastStarted(
        cast_id:,
        spell4_id:,
        root_spell4_id:,
        parent_spell4_id:,
        ..,
      ) ->
        "started "
        <> label(cast_id)
        <> " "
        <> int.to_string(spell4_id)
        <> " root "
        <> int.to_string(root_spell4_id)
        <> " parent "
        <> int.to_string(parent_spell4_id)
      game_client.CastWent(cast_id:, phase:) ->
        "went " <> label(cast_id) <> " p" <> int.to_string(phase)
      game_client.CastFinished(cast_id:) -> "finished " <> label(cast_id)
      game_client.ThresholdOpened(spell4_id:, cancel_cast_id:) ->
        "opened " <> int.to_string(spell4_id) <> " " <> label(cancel_cast_id)
      game_client.ThresholdIndex(spell4_id:, index:) ->
        "index " <> int.to_string(spell4_id) <> " " <> int.to_string(index)
      game_client.ThresholdClosed(spell4_id:, start_cooldowns:) ->
        "closed "
        <> int.to_string(spell4_id)
        <> " "
        <> int.to_string(start_cooldowns)
      game_client.ThresholdEnded(spell4_id:) ->
        "ended " <> int.to_string(spell4_id)
    }
  })
}
