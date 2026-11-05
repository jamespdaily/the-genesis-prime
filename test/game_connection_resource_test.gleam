//// The class resource on the game connection (`genesis_prime/game/connection/resource`):
//// a press's cost paid at its accept and written to the player's own client as
//// 0x935, and the refill's timer run by the connection. Expected values come from
//// the client (`opcode.0x935`: a 32-bit unit, a 5-bit stat, a float; stat n + 2
//// is slot n, `opcode.0x262.resource_stats`), the client's row
//// (`table_rows -- Spell4 38779`: Impale costs 35 of type 8, slot 3) and the step's
//// design (issue 403: the Stalker's 100 Suit Power, +7 each second, paid at the
//// accept).

import cast_support
import character_tables
import connection_rule_support as support
import game_client
import game_connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/class_resource
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/loadout
import genesis_prime/game/strike_tell
import genesis_prime/message/float32
import genesis_prime/message/unit_float_stat_changed.{
  type UnitFloatStatChanged, UnitFloatStatChanged,
}
import genesis_prime/step.{
  type ConnectionStep, type TimerId, CancelTimer, OwnEffect, OwnEvent,
  StartTimer, TimerFired, Unwatch, Watch,
}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId, Spell4BaseId}
import gleam/int
import gleam/list
import owned_test

/// The 0x935s among the frames, decoded.
fn resource_changes(frames: List(Frame)) -> List(UnitFloatStatChanged) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id == unit_float_stat_changed.message_id {
      True -> {
        let assert Ok(changed) = unit_float_stat_changed.decode(frame.body)
          as "0x935 decodes"
        Ok(changed)
      }
      False -> Error(Nil)
    }
  })
}

/// The tests' player of this class in the world, its connection reading the
/// starting abilities' trees (`character_tables.shared_with_spell_trees`), with
/// its unit id and the bag index of the ability of this Spell4Base.
fn entered_with_trees(
  class_id class_id: Int,
  ability ability: Int,
) -> #(game_connection.State, Int, Int) {
  let fresh =
    game_connection_support.accepted(
      Settings(
        ..game_connection_support.settings(),
        tables: character_tables.shared_with_spell_trees(),
      ),
    ).0
  let #(state, entered) =
    game_connection_support.entered_from(
      in_character_select: game_connection_support.in_select_from(fresh),
      character: Character(
        ..game_connection_support.world_character(),
        class_id: ClassId(class_id),
      ),
    )
  let unit_id = game_connection_support.player_in(entered).unit_id
  let assert Ok(set) =
    loadout.of(
      tables: character_tables.shared(),
      class_id: ClassId(class_id),
      faction_id: 166,
    )
    as "the tables hold the class's Novice set"
  let assert Ok(bag_index) =
    list.index_map(set.abilities, fn(base, index) { #(base, index) })
    |> list.key_find(Spell4BaseId(ability))
    as "a level-1 player of the class holds the ability"
  #(state, unit_id, bag_index)
}

/// The press of the ability at this bag index, as a client sends it.
fn press(
  state state: game_connection.State,
  bag_index bag_index: Int,
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection_support.read(
    state:,
    bytes: game_connection_support.world_message(
      message_id: 0x009A,
      body: cast_support.press_body(
        client_cast_id: 9,
        bag_index:,
        target: 0,
        press: 1,
      ),
    ),
  )
}

/// The 0x935s a step writes, decoded.
fn changes_written(
  taken: ConnectionStep(Request),
) -> List(UnitFloatStatChanged) {
  resource_changes(game_connection_support.heard(
    taken,
    game_connection_support.keyed(),
  ))
}

/// The timers of the class resource a step starts, as (timer, after_ms).
fn resource_timers_started(
  taken: ConnectionStep(Request),
) -> List(#(TimerId, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer:, after_ms:)) ->
        case class_resource.owns(timer:) {
          True -> Ok(#(timer, after_ms))
          False -> Error(Nil)
        }
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The timers of the class resource a step cancels.
fn resource_timers_cancelled(taken: ConnectionStep(Request)) -> List(TimerId) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(CancelTimer(timer:)) ->
        case class_resource.owns(timer:) {
          True -> Ok(timer)
          False -> Error(Nil)
        }
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

pub fn a_stalkers_impale_writes_its_suit_power_at_65_as_0x935_and_the_refill_writes_72_a_second_later_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(state, unit_id, bag_index) =
    entered_with_trees(class_id: 5, ability: 23_161)
  let #(state, pressed) = press(state:, bag_index:)
  assert changes_written(pressed)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 5, value: float32.to_bits(65.0)),
    ]
    as "100 less 35, paid at the accept, as 0x935 of stat 5 (slot 3) to the player's own client"
  let #(_, ticked) =
    game_connection_support.feed(
      state,
      OwnEvent(TimerFired(timer: class_resource.regen_timer)),
    )
  assert changes_written(ticked)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 5, value: float32.to_bits(72.0)),
    ]
    as "the refill's tick, a timer of the connection: +7"
}

/// A step of the connection at the monotonic time `ms`.
fn at(
  state state: game_connection.State,
  ms ms: Int,
  event event: step.Event(
    step.ConnectionEvent(client_connection.Message, client_connection.Answer),
  ),
) -> #(game_connection.State, ConnectionStep(Request)) {
  game_connection.step(state, support.input_at_ms(ms:, event:))
}

/// The step, and each strike it and the steps after it tell a creature answered as
/// landed at `ms`, in order.
fn landing(
  state state: game_connection.State,
  ms ms: Int,
  taken taken: ConnectionStep(Request),
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  list.fold(
    game_connection_support.strikes_told(taken),
    #(state, [taken]),
    fn(so_far, strike) {
      let #(state, steps) = so_far
      let #(state, answered) =
        at(state:, ms:, event: game_connection_support.landed(key: strike.1))
      let #(state, more) = landing(state:, ms:, taken: answered)
      #(state, list.append(steps, more))
    },
  )
}

/// The cast rule's timers the steps start, due from `ms`, less those they cancel.
fn cast_timers(
  steps steps: List(ConnectionStep(Request)),
  ms ms: Int,
) -> List(#(Int, TimerId)) {
  let effects = list.flat_map(steps, support.effects_of)
  let cancelled =
    list.filter_map(effects, fn(effect) {
      case effect {
        OwnEffect(CancelTimer(timer:)) -> Ok(timer)
        OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
          Error(Nil)
      }
    })
  list.filter_map(effects, fn(effect) {
    case effect {
      OwnEffect(StartTimer(timer:, after_ms:)) ->
        case cast.owns(timer:) && !list.contains(cancelled, timer) {
          True -> Ok(#(ms + after_ms, timer))
          False -> Error(Nil)
        }
      OwnEffect(_) | Watch(..) | Unwatch(..) | step.Log(..) | step.Stop ->
        Error(Nil)
    }
  })
}

/// The cast rule's timers fired in time order up to `until_ms`, with every strike
/// landing: the connection and every step taken.
fn casts_run(
  state state: game_connection.State,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  steps steps: List(ConnectionStep(Request)),
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  case
    list.sort(pending, fn(first, second) { int.compare(first.0, second.0) })
  {
    [#(due, timer), ..rest] if due <= until_ms -> {
      let #(state, fired) =
        at(state:, ms: due, event: OwnEvent(TimerFired(timer:)))
      let #(state, more) = landing(state:, ms: due, taken: fired)
      casts_run(
        state:,
        pending: list.append(rest, cast_timers(steps: more, ms: due)),
        until_ms:,
        steps: list.append(steps, more),
      )
    }
    _ -> #(state, steps)
  }
}

/// A press of the bag index at `ms`, and the cast timers it leads to up to
/// `until_ms`, each strike landing.
fn pressed_until(
  state state: game_connection.State,
  bag_index bag_index: Int,
  client_cast_id client_cast_id: Int,
  ms ms: Int,
  until_ms until_ms: Int,
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  let #(state, pressed) =
    at(
      state:,
      ms:,
      event: OwnEvent(
        step.Read(game_connection_support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id:,
            bag_index:,
            target: 0,
            press: 1,
          ),
        )),
      ),
    )
  let #(state, steps) = landing(state:, ms:, taken: pressed)
  casts_run(state:, pending: cast_timers(steps:, ms:), until_ms:, steps:)
}

fn all_changes(
  steps: List(ConnectionStep(Request)),
) -> List(UnitFloatStatChanged) {
  list.flat_map(steps, changes_written)
}

/// Relentless Strikes and Rampage, the Warrior's (Spell4Base 18309 and 37968).
const relentless_strikes_base = 18_309

const rampage_base = 37_968

pub fn a_warriors_relentless_strikes_on_a_beast_fills_kinetic_energy_and_rampage_then_casts_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(state, unit_id, strikes_index) =
    entered_with_trees(class_id: 1, ability: relentless_strikes_base)
  let #(_, _, rampage_index) =
    entered_with_trees(class_id: 1, ability: rampage_base)
  let #(state, _) =
    at(
      state:,
      ms: 1000,
      event: game_connection_support.beast_appears(unit_id: 40),
    )
  let #(state, first) =
    pressed_until(
      state:,
      bag_index: strikes_index,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 1749,
    )
  assert all_changes(first)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(180.0)),
    ]
    as "the first tap's stage spell 70033 strikes the Beast 3 m ahead and gives +180 Kinetic Energy (Spell4Effects 127603), one 0x935 of stat 3 (slot 1) to the Warrior's own client"
  let #(state, second) =
    pressed_until(
      state:,
      bag_index: strikes_index,
      client_cast_id: 2,
      ms: 1750,
      until_ms: 2499,
    )
  assert all_changes(second)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(360.0)),
    ]
    as "the second tap's 70045 strikes it again: 360"
  let #(_, rampage) =
    pressed_until(
      state:,
      bag_index: rampage_index,
      client_cast_id: 3,
      ms: 2500,
      until_ms: 2500,
    )
  let frames =
    list.flat_map(rampage, fn(taken) {
      game_connection_support.heard(taken, game_connection_support.keyed())
    })
  let events = game_client.casts_in(frames:)
  assert list.any(events, fn(event) {
      case event {
        game_client.CastConfirmed(client_cast_id: 3, ..) -> True
        game_client.CastRefused(..)
        | game_client.CastConfirmed(..)
        | game_client.CastStarted(..)
        | game_client.CastWent(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..)
        | game_client.CastFinished(..) -> False
      }
    })
    && !list.any(events, fn(event) {
      case event {
        game_client.CastRefused(..) -> True
        game_client.CastConfirmed(..)
        | game_client.CastStarted(..)
        | game_client.CastWent(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..)
        | game_client.CastFinished(..) -> False
      }
    })
    as "Rampage needs at least 250 of slot 1 (0x1403b1780, Spell4 58524): at 360 it is accepted with 0x7fd, not refused 51"
}

/// Gamma Rays, the Medic's first ability that costs Actuators (Spell4Base 16322,
/// 2 of type 18, `table_rows -- Spell4 29874`).
const gamma_rays_base = 16_322

pub fn a_medic_struck_and_spending_actuators_is_refilled_to_4_three_seconds_after_the_combat_flag_clears_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(state, unit_id, bag_index) =
    entered_with_trees(class_id: 4, ability: gamma_rays_base)
  let #(state, threatened) =
    game_connection_support.feed(
      state,
      game_connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  assert resource_timers_started(threatened) == []
    as "a Medic starts nothing while it is full"
  let #(state, pressed) = press(state:, bag_index:)
  assert changes_written(pressed)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(2.0)),
    ]
    as "4 Actuators less Gamma Rays' 2, as 0x935 of stat 3 (slot 1)"
  assert resource_timers_started(pressed) == []
    as "in combat the Medic's refill waits (500710: regenerate while out of combat)"
  let #(state, released) =
    game_connection_support.feed(
      state,
      game_connection_support.foe(strike_tell.Released(unit_id: 7)),
    )
  assert resource_timers_started(released)
    == [#(class_resource.refill_timer, 3000)]
    as "the combat flag clears: the refill starts, 3 seconds (Jim's choice at the design)"
  assert changes_written(released) == []
  let #(state, refilled) =
    game_connection_support.feed(
      state,
      OwnEvent(TimerFired(timer: class_resource.refill_timer)),
    )
  assert changes_written(refilled)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(4.0)),
    ]
    as "the timer fires: all 4 back, one 0x935"
  let #(_, again) =
    game_connection_support.feed(
      state,
      OwnEvent(TimerFired(timer: class_resource.refill_timer)),
    )
  assert changes_written(again) == [] as "a full slot sends nothing"
}

pub fn a_player_killed_and_brought_back_gets_each_slot_at_its_start_in_one_0x935_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(state, unit_id, bag_index) =
    entered_with_trees(class_id: 4, ability: gamma_rays_base)
  let #(state, _) =
    game_connection_support.feed(
      state,
      game_connection_support.foe(strike_tell.Threatened(unit_id: 7, life: 3)),
    )
  let #(state, _) = press(state:, bag_index:)
  let #(state, killed) =
    game_connection_support.feed(
      state,
      game_connection_support.a_killing_strike(),
    )
  assert changes_written(killed) == [] as "death writes no resource change"
  let #(state, back) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.wake_here(),
    )
  assert changes_written(back)
    == [
      UnitFloatStatChanged(unit_id:, stat_id: 3, value: float32.to_bits(4.0)),
    ]
    as "the Medic's slot 1 comes back to its start, 4 (500710), the one slot that moved"
  let #(_, warrior_back) = warrior_killed_and_back()
  assert changes_written(warrior_back) == []
    as "a Warrior spent nothing and its slot is at its start, 0 (500714): nothing moved"
  let #(_, refilled) =
    game_connection_support.feed(
      state,
      OwnEvent(TimerFired(timer: class_resource.refill_timer)),
    )
  assert changes_written(refilled) == []
    as "a refill timer that fires after the player came back changes nothing"
}

/// A Warrior struck dead and woken where its body lies.
fn warrior_killed_and_back() -> #(
  game_connection.State,
  ConnectionStep(Request),
) {
  let state =
    game_connection_support.entered_as(
      Character(
        ..game_connection_support.world_character(),
        class_id: ClassId(1),
      ),
    ).0
  let #(state, _) = game_connection_support.killed(state)
  game_connection_support.read(
    state:,
    bytes: game_connection_support.wake_here(),
  )
}

pub fn a_refill_timer_that_fires_after_the_player_left_sends_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(state, _, bag_index) =
    entered_with_trees(class_id: 4, ability: gamma_rays_base)
  let #(state, pressed) = press(state:, bag_index:)
  assert resource_timers_started(pressed)
    == [#(class_resource.refill_timer, 3000)]
    as "out of combat the Medic's payment starts the refill (the server's choice)"
  let #(state, camp_asked) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.camp_request_message(True),
    )
  let #(state, camped) =
    game_connection_support.read(
      state:,
      bytes: game_connection_support.camp_finished_message(),
    )
  assert list.contains(
    list.append(
      resource_timers_cancelled(camp_asked),
      resource_timers_cancelled(camped),
    ),
    class_resource.refill_timer,
  )
    as "leaving the stay cancels the refill timer"
  let #(_, late) =
    game_connection_support.feed(
      state,
      OwnEvent(TimerFired(timer: class_resource.refill_timer)),
    )
  assert changes_written(late) == []
  assert support.effects_of(late) == []
    as "a timer of a player no longer in the world is dropped"
}
