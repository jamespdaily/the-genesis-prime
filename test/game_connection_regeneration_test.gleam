//// A player's health and shield regenerating on the game connection
//// (`genesis_prime/game/connection/life`): the timers the life rule asks for run
//// by the connection, a tick's news written to the player and told to its viewers,
//// and the rule's own input of each timer, with the clock driven by hand as
//// `TimerFired`. Expected values come from these places.
//// - The tests' player is an Engineer of level 1 (class 2): 736 health, 450 shield,
////   Armor 250 (mitigation 0.75), whose shield item holds ShieldRegenPct 0.15 and
////   ShieldRebootTime 5125 (`0x14040dbf0`, as the 0x262's properties 176 and 178
////   carry them: the tests read those two from the player's own 0x262). A blow of
////   1000 is mitigated to 250, of which the shield takes round(156.25) = 156 and
////   the health 94, leaving 294 and 642.
//// - A shield tick adds floor(450 x 0.15) = floor(67.5) = 67 (text 531859), the
////   first ShieldRebootTime after the blow and the next each ShieldTickTime, 500 ms
////   (UnitProperty2 177's default, `UnitProperty2.176`), so 361, 428 and then the
////   maximum 450.
//// - A health tick adds floor(736 x 0.025 x 1.0) = 18 each 500 ms (the two server
////   choices of migration 0015, and HealthRegenMultiplier, UnitProperty2 8, 1.0).
//// - 0x92f is the player's own health, 0x937 another unit's, 0x938 of stat 20 the
////   shield (`opcode.0x92f`, `opcode.0x937`, `opcode.0x938`); the viewers are told
////   the news and write 0x937 and 0x938 themselves (`player_life_test`).
//// - The timer ids 8 and 9 are the connection's free ids above the class
////   resource's.

import connection_rule_support as support
import game_connection_support
import genesis_prime/client_connection.{type Answer, type Message, type Request}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/strike_tell
import genesis_prime/message/float32
import genesis_prime/message/player_health.{PlayerHealth}
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_stat_changed.{UnitStatChanged}
import genesis_prime/step.{
  type ConnectionEvent, type ConnectionStep, type Event, CancelTimer, OwnEffect,
  OwnEvent, StartTimer, TimerFired, TimerId, Unwatch, Watch,
}
import gleam/list
import gleam/option.{Some}
import owned_test
import spawn_support

const health_timer = TimerId(8)

const shield_timer = TimerId(9)

/// The tests' player entering with the health its last save kept.
fn entering_saved(
  saved saved: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.entered_saved(
    in_character_select: game_connection_support.in_select(),
    character: game_connection_support.world_character(),
    saved_health: Some(saved),
  )
}

/// The timers a step starts, as (timer, after_ms).
fn started(taken: ConnectionStep(Request)) -> List(#(step.TimerId, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer:, after_ms:)) -> Ok(#(timer, after_ms))
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The timers a step cancels.
fn cancelled(taken: ConnectionStep(Request)) -> List(step.TimerId) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(CancelTimer(timer:)) -> Ok(timer)
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

fn fire(
  state state: game_connection.State,
  timer timer: step.TimerId,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.feed(state, OwnEvent(TimerFired(timer)))
}

/// A creature's strike of `damage` on the tests' player, as the creature sends it.
fn blow(damage damage: Int) -> Event(ConnectionEvent(Message, Answer)) {
  game_connection_support.foe(
    strike_tell.Attacks(tell: strike_tell.Strike(
      key: strike_tell.Key(
        cast_id: 2_147_500_100,
        phase: 0,
        unit_id: game_connection_support.own_unit_id,
      ),
      from: game_connection_support.fighter(),
      striker: strike_tell.CreatureStriker,
      offence: spawn_support.dealing(
        offence: spawn_support.beast_attack().offence,
        damage:,
      ),
    )),
  )
}

fn property_bits(unit: UnitCreatePlayer, id id: Int) -> Int {
  let assert Ok(property) =
    list.find(unit.tail.properties, fn(property) { property.property_id == id })
    as "the player's 0x262 holds the shield item's property"
  property.value
}

pub fn a_player_entering_below_its_max_health_starts_its_health_timer_and_a_full_one_starts_none_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(_, hurt) = entering_saved(saved: 700)
  assert list.contains(started(hurt), #(health_timer, 500))
    as "below the maximum and out of combat: the first tick is health_regen_tick_ms away"
  let #(_, full) = game_connection_support.entered()
  assert started(full) |> list.filter(fn(timer) { timer.0 == health_timer })
    == []
    as "a player at full health starts no health timer"
}

pub fn a_health_tick_writes_0x92f_to_the_player_tells_its_viewers_and_asks_the_next_tick_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = entering_saved(saved: 700)
  let state = game_connection_support.watched_by(state:, viewers: [2])
  let #(state, tick) = fire(state:, timer: health_timer)
  assert game_connection_support.decoded(
      game_connection_support.heard(tick, game_connection_support.keyed()),
      0x092F,
      player_health.decode,
    )
    == [
      PlayerHealth(
        unit_id: game_connection_support.own_unit_id,
        health: 718,
        reason_mask: 0,
      ),
    ]
    as "700 and 18: 0x92f to the player's own client"
  assert list.map(game_connection_support.peer_tells(tick), fn(tell) {
      { tell.1 }.news
    })
    == [client_connection.Health(health: 718, dead: False)]
    as "its viewer is told the health (it writes 0x937)"
  assert started(tick) == [#(health_timer, 500)]
    as "below the maximum: the next tick"
  let #(_, second) = fire(state:, timer: health_timer)
  assert game_connection_support.decoded(
      game_connection_support.heard(second, game_connection_support.keyed()),
      0x092F,
      player_health.decode,
    )
    == [
      PlayerHealth(
        unit_id: game_connection_support.own_unit_id,
        health: 736,
        reason_mask: 0,
      ),
    ]
    as "718 and 18 is the maximum"
  assert started(second) == [] as "full: no next tick"
}

pub fn a_blow_starts_the_shield_timer_at_the_items_reboot_time_and_each_tick_after_adds_its_share_test() -> Nil {
  use <- owned_test.run(60_000)
  let state =
    game_connection_support.watched_by(game_connection_support.in_world(), [2])
  let unit =
    game_connection_support.player_in(game_connection_support.entered().1)
  assert property_bits(unit, id: 176) == float32.to_bits(0.15)
    && property_bits(unit, id: 178) == float32.to_bits(5125.0)
    as "the 0x262's ShieldRegenPct and ShieldRebootTime, the item's"
  let #(state, threat) =
    game_connection_support.feed(
      state,
      game_connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  assert started(threat) == [] && cancelled(threat) == []
    as "a full player starting a fight has no timer to change"
  let #(state, struck) = game_connection_support.feed(state, blow(damage: 1000))
  assert started(struck) == [#(shield_timer, 5125)]
    as "ShieldRebootTime from the blow, and no health tick in combat"
  let shield_of = fn(taken) {
    game_connection_support.decoded(
      game_connection_support.heard(taken, game_connection_support.keyed()),
      0x0938,
      unit_stat_changed.decode,
    )
  }
  let #(state, first) = fire(state:, timer: shield_timer)
  assert shield_of(first)
    == [
      UnitStatChanged(unit_id: game_connection_support.own_unit_id, value: 361),
    ]
    as "294 and 67: 0x938 stat 20, in combat"
  assert list.map(game_connection_support.peer_tells(first), fn(tell) {
      { tell.1 }.news
    })
    == [client_connection.Shield(shield: 361)]
    as "its viewer is told the shield (it writes 0x938)"
  assert started(first) == [#(shield_timer, 500)]
    as "ShieldTickTime, UnitProperty2 177's default"
  let #(state, second) = fire(state:, timer: shield_timer)
  assert shield_of(second)
    == [
      UnitStatChanged(unit_id: game_connection_support.own_unit_id, value: 428),
    ]
  let #(_, last) = fire(state:, timer: shield_timer)
  assert shield_of(last)
    == [
      UnitStatChanged(unit_id: game_connection_support.own_unit_id, value: 450),
    ]
    as "428 and 67 stops at the maximum"
  assert started(last) == [] as "full: no next tick"
}

pub fn a_second_blow_before_the_reboot_pushes_it_back_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) =
    game_connection_support.feed(
      game_connection_support.in_world(),
      game_connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, _) = game_connection_support.feed(state, blow(damage: 12))
  let #(_, again) = game_connection_support.feed(state, blow(damage: 12))
  assert cancelled(again) == [shield_timer]
    && started(again) == [#(shield_timer, 5125)]
    as "the first reboot is cancelled and starts over from the second blow"
}

pub fn timers_8_and_9_reach_the_life_rule_and_nothing_else_test() -> Nil {
  use <- owned_test.run(60_000)
  let state = game_connection_support.in_world()
  let #(after, fired) = fire(state:, timer: health_timer)
  assert support.effects_of(fired) == []
    as "a health timer with nothing to regenerate writes and starts nothing: it is not a claim's, a cast's or the class resource's"
  assert after == state
  let #(after, fired) = fire(state:, timer: shield_timer)
  assert support.effects_of(fired) == [] as "likewise the shield timer"
  assert after == state
}

pub fn leaving_the_world_cancels_the_running_regeneration_timers_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(state, _) = entering_saved(saved: 700)
  let #(state, _) = game_connection_support.feed(state, blow(damage: 12))
  let #(state, _) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.camp_request_message(True),
    )
  let #(_, finished) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.camp_finished_message(),
    )
  assert list.filter(cancelled(finished), fn(timer) {
      timer == health_timer || timer == shield_timer
    })
    == [health_timer, shield_timer]
    as "the camp cancels the health tick and the shield's reboot"
  Nil
}
