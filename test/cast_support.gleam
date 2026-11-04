//// What the cast rule's tests share: the abilities as the plan holds them, built
//// from the client's rows the fact file records (each value named where it is
//// set), a caster, the bytes of the client's presses and cancels, and helpers
//// that find the writes, the tells and the timers in a step's effects.
////
//// Three spells are planted, not client rows, because no level-1 ability has
//// global cooldown kind 2, a cast bar that lets a press through, or a cast time
//// with a cooldown of its own: `blocked_only` (kind 2), `exempt` and `slow`.

import genesis_prime/client_connection.{type News}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast.{type Caster, type Effect, type State}
import genesis_prime/game/spell_plan.{
  type Plans, type Proxy, type Spell, Always, GlobalCooldown, NoWeaponNeeded,
  Normal, PrimaryWeapon, Proxy, Spell,
}
import genesis_prime/message/cancel_cast.{CancelCast}
import genesis_prime/message/cast_ability.{CastAbility}
import genesis_prime/message/cast_result.{type CastResult}
import genesis_prime/step.{
  type ConnectionId, type Now, type TimerId, ConnectionId, Now,
}
import genesis_prime/table/id.{Item2Id, Spell4BaseId, Spell4EffectsId, Spell4Id}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import place_support

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
    cast_bar: False,
    free_while_live: False,
    ignores_casting: False,
    weapon: NoWeaponNeeded,
    global_cooldown: GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: None,
    ),
    unpayable_cost: None,
    phase_delays_ms: [],
    proxies: [],
  )
}

fn proxy(
  effect effect: Int,
  delay delay: Int,
  phases phases: Int,
  spell spell: Spell,
) -> Proxy {
  Proxy(
    effect_id: Spell4EffectsId(effect),
    delay_ms: delay,
    phase_flags: phases,
    condition: Always,
    spell:,
  )
}

/// Telekinetic Strike, `Spell4.32893`: 1250 ms with a cast bar, kind 0
/// with SpellCoolDown 213 (1000 ms), and the Proxy to 30900 on the caster.
pub fn telekinetic_strike() -> Spell {
  Spell(
    ..child(spell4_id: 32_893, base: 19_102),
    cast_time_ms: 1250,
    cast_bar: True,
    global_cooldown: GlobalCooldown(
      refused_while_running: True,
      starts_for_ms: Some(1000),
    ),
    proxies: [
      proxy(
        effect: 62_204,
        delay: 0,
        phases: -1,
        spell: child(spell4_id: 30_900, base: 17_288),
      ),
    ],
  )
}

/// Kick, `Spell4.58591`: instant, cooldown 20 s, range 7, kind 3.
pub fn kick() -> Spell {
  Spell(..child(spell4_id: 58_591, base: 38_017), cooldown_ms: 20_000)
}

/// Crush, `Spell4.32812`: cooldown 35 s, kind 3, a Proxy 100 ms after the go to 42297.
pub fn crush() -> Spell {
  Spell(
    ..child(spell4_id: 32_812, base: 19_022),
    cooldown_ms: 35_000,
    ignores_casting: True,
    proxies: [
      proxy(
        effect: 62_007,
        delay: 100,
        phases: 1,
        spell: child(spell4_id: 42_297, base: 26_488),
      ),
    ],
  )
}

/// Stagger, `Spell4.38791`: cooldown 25 s, weapon slot 1, kind 1 with
/// SpellCoolDown 180 (750 ms), a Proxy to 38780, a Multiphase spell of phases of
/// 166, 200, 167 and 167 ms that proxies 38781 in each phase.
pub fn stagger() -> Spell {
  let phases =
    Spell(
      ..child(spell4_id: 38_780, base: 23_162),
      method: spell_plan.Multiphase,
      phase_delays_ms: [166, 200, 167, 167],
      proxies: [
        proxy(
          effect: 83_823,
          delay: 0,
          phases: 1,
          spell: child(spell4_id: 38_781, base: 23_163),
        ),
        proxy(
          effect: 83_824,
          delay: 0,
          phases: 2,
          spell: child(spell4_id: 38_781, base: 23_163),
        ),
        proxy(
          effect: 83_825,
          delay: 0,
          phases: 4,
          spell: child(spell4_id: 38_781, base: 23_163),
        ),
        proxy(
          effect: 83_826,
          delay: 0,
          phases: 8,
          spell: child(spell4_id: 38_781, base: 23_163),
        ),
      ],
    )
  Spell(
    ..child(spell4_id: 38_791, base: 23_173),
    ignores_casting: True,
    cooldown_ms: 25_000,
    weapon: PrimaryWeapon,
    global_cooldown: GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: Some(750),
    ),
    proxies: [
      proxy(effect: 83_853, delay: 0, phases: 1, spell: phases),
    ],
  )
}

/// Gate, `Spell4.34355`: cooldown 30 s, kind 1 with SpellCoolDown 155 (750 ms),
/// Proxies to 25190 and 30436; it deals no damage.
pub fn gate() -> Spell {
  Spell(
    ..child(spell4_id: 34_355, base: 20_325),
    ignores_casting: True,
    cooldown_ms: 30_000,
    global_cooldown: GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: Some(750),
    ),
    proxies: [
      proxy(
        effect: 67_778,
        delay: 0,
        phases: -1,
        spell: child(spell4_id: 25_190, base: 11_781),
      ),
      proxy(
        effect: 67_779,
        delay: 0,
        phases: -1,
        spell: child(spell4_id: 30_436, base: 16_838),
      ),
    ],
  )
}

/// Mind Burst, `Spell4.32809`: cost of 1 in vital 6, which a new unit cannot pay
/// (`Spell4CastResult.vital_cost`: 51).
pub fn mind_burst() -> Spell {
  Spell(
    ..child(spell4_id: 32_809, base: 19_019),
    global_cooldown: GlobalCooldown(
      refused_while_running: True,
      starts_for_ms: Some(1250),
    ),
    unpayable_cost: Some(51),
  )
}

/// Gamma Rays, `Spell4.29874`: cost of 2 in vital 18 (`Spell4CastResult.vital_cost`: 55).
pub fn gamma_rays() -> Spell {
  Spell(
    ..child(spell4_id: 29_874, base: 16_322),
    cast_bar: True,
    cast_time_ms: 1250,
    weapon: PrimaryWeapon,
    global_cooldown: GlobalCooldown(
      refused_while_running: True,
      starts_for_ms: Some(1250),
    ),
    unpayable_cost: Some(55),
  )
}

/// Electrocute, `Spell4.41276`: a Channeled spell (`0x14053d1f0`), not Normal.
pub fn electrocute() -> Spell {
  Spell(..child(spell4_id: 41_276, base: 25_473), method: spell_plan.Channeled)
}

/// Zap, `Spell4.41438`: weapon slot 1, kind 1 with no global row, cooldown 30 s.
pub fn zap() -> Spell {
  Spell(
    ..child(spell4_id: 41_438, base: 25_635),
    ignores_casting: True,
    cooldown_ms: 30_000,
    weapon: PrimaryWeapon,
  )
}

/// A planted spell with a cast time of 1000 ms and a cast bar whose live cast
/// leaves the caster free to press another (`0x1403afb10`).
pub fn exempt() -> Spell {
  Spell(
    ..child(spell4_id: 1, base: 1),
    cast_time_ms: 1000,
    cast_bar: True,
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

/// The abilities by bag index: 0 Telekinetic Strike, 1 Crush, 2 Mind Burst, 3 Kick,
/// 4 Stagger, 5 Gate, 6 Gamma Rays, 7 Electrocute, 8 the exempt spell, 9 Zap,
/// 10 the kind 2 spell and 11 the slow spell.
pub fn spells() -> List(Spell) {
  [
    telekinetic_strike(),
    crush(),
    mind_burst(),
    kick(),
    stagger(),
    gate(),
    gamma_rays(),
    electrocute(),
    exempt(),
    zap(),
    blocked_only(),
    slow(),
  ]
}

pub fn plans() -> Plans {
  dict.from_list(
    list.map(spells(), fn(spell) { #({ spell.spell4_base_id }.value, spell) }),
  )
}

/// The player 7 with the abilities above and its weapon, seen by the connections
/// 2 and 3, standing at the live character's place.
pub fn caster() -> Caster {
  let place = place_support.live_character_place()
  cast.Caster(
    unit_id: 7,
    place:,
    abilities: list.map(spells(), fn(spell) { spell.spell4_base_id }),
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
  let assert Ok(body) =
    cast_ability.encode(CastAbility(
      client_cast_id:,
      bag_index:,
      target_unit_id: target,
      press:,
    ))
    as "the press fits the message"
  body
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
  let assert Ok(taken) =
    cast.take(
      cast: state,
      message: cast.Pressed,
      body: press_body(client_cast_id: 9, bag_index:, target:, press: 1),
      caster:,
      plans: plans(),
      now: at(ms:),
    )
    as "the press is taken: a refusal of the client's own checks is a 0x7fc, never an error"
  taken
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
