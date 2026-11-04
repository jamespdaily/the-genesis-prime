//// The creatures a map starts and stops as players see spawns
//// (`genesis_prime/world_map/map`), run as the pure rule it is: inputs in, new
//// state and effects out. Expected values come from these places.
//// - The design of the world spawns (the Design artifact of issue 375, sections 3
////   and 6): a creature starts when its spawn gets its first viewer, with the
////   spawn's unit id and a life, its watch's number; it stops when no player has
////   seen it for the idle stop, found by a sweep every 10 s, so between 60 and 70
////   s after the last viewer left; a spawn seen while its creature retires waits
////   for its end; a creature that crashes while seen is `Gone` to every player and
////   its spawn restarts after the respawn time under a new unit id if a player
////   sees it then, and is dormant otherwise; a start that fails leaves the spawn
////   empty for the run.
//// - Sight (`genesis_prime/world_map/sight`): 1024 units, 3D, inclusive.
//// - Unit ids: never 0 (a 0x262 with unit id 0 becomes the controlled unit,
////   0x1403d9760), never given to two units at once, and below 2^20 (the cast id is
////   built from the unit id, issue 274's design, section 3); a unit id is reused
////   after a clean stop (`opcode.0x262`, `death.creature_respawn`) and never after
////   a crash, which sent `Gone`.
//// - The idle stop, the sweep and the respawn time are the server's choices
////   (design 375, section 4); the rule takes them as settings and the time as the
////   input's, so no test waits.

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId,
  CancelServiceTimer, Connection, ConnectionId, Creature, CreatureNotStarted,
  LogError, OwnEffect, OwnEvent, Reply, Send, ServiceTimerFired, StartCreature,
  StartServiceTimer, Started, Told, WatchEnded, WatchId,
}
import genesis_prime/world_map/map.{
  type State, Gone, Join, Leave, Moved, Watched,
}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import map_support
import owned_test
import place_support
import spawn_support

/// The time the map starts at on the monotonic clock.
const started_at_ms = 5000

const ship = MapId(world_id: 3460, instance: 0)

/// Far from every spawn the tests stand: no creature is in sight there.
const far = 50_000.0

/// A place `x` units along the world's x axis in Warfare Woods.
fn at(x: Float) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: spawn_support.warfare_woods,
    x:,
    y: 0.0,
    z: 0.0,
  )
}

fn feed(
  state state: State,
  at_ms at_ms: Int,
  event event: Event(ServiceEvent(map.Message)),
) -> #(State, ServiceStep(map.Outgoing)) {
  map.step(state, support.input_at_ms(ms: at_ms, event:))
}

/// A map with a spawn at each of these x positions, numbered from 1, started.
fn started(at xs: List(Float)) -> #(State, ServiceStep(map.Outgoing)) {
  let state =
    map_support.standing(
      incarnation: 1,
      spawns: list.index_map(xs, fn(x, index) {
        spawn_support.battle_beast(number: index + 1, x:)
      }),
    )
  feed(state:, at_ms: started_at_ms, event: OwnEvent(Started))
}

/// A join of connection `connection` at `x`, at time `at_ms`.
fn join(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  x x: Float,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(Asked(
      caller: CallerId(connection),
      message: Join(
        connection: ConnectionId(connection),
        character: map_support.character(100 + connection),
        place: at(x),
      ),
    )),
  )
}

/// A move of connection `connection` to `x`, at time `at_ms`.
fn move(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  x x: Float,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: Moved(connection: ConnectionId(connection), place: at(x))),
    ),
  )
}

/// A leave of connection `connection`, at time `at_ms`.
fn leave(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(Asked(
      CallerId(99),
      Leave(connection: ConnectionId(connection)),
    )),
  )
}

/// The sweep timer's firing, at time `at_ms`.
fn sweep(
  state state: State,
  at_ms at_ms: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(ServiceTimerFired(timer: map.sweep_timer)),
  )
}

/// The creatures a step starts, each with the watch it is to be under, in the
/// order named.
fn starts(
  taken: ServiceStep(map.Outgoing),
) -> List(#(step.WatchId, step.CreatureStart)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartCreature(watch:, creature:)) -> Ok(#(watch, creature))
      OwnEffect(Reply(..))
      | OwnEffect(Send(..))
      | OwnEffect(StartServiceTimer(..))
      | OwnEffect(CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// The timers a step starts, each with its id's number and its delay.
fn timers(taken: ServiceStep(map.Outgoing)) -> List(#(Int, Int)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(StartServiceTimer(timer: step.TimerId(number), after_ms:)) ->
        Ok(#(number, after_ms))
      OwnEffect(Reply(..))
      | OwnEffect(Send(..))
      | OwnEffect(StartCreature(..))
      | OwnEffect(CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// What the step sends, to whom, in order.
fn sends(
  taken: ServiceStep(map.Outgoing),
) -> List(#(step.Address, map.Outgoing)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to:, message:)) -> Ok(#(to, message))
      OwnEffect(StartCreature(..))
      | OwnEffect(Reply(..))
      | OwnEffect(StartServiceTimer(..))
      | OwnEffect(CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// What the step sends to creatures, by the creature's unit id and what it says
/// (`Watched by 1`), in the order sent.
fn creature_sends(taken: ServiceStep(map.Outgoing)) -> List(#(Int, String)) {
  list.filter_map(sends(taken), fn(sent) {
    case sent.0 {
      Creature(unit_id:, ..) -> Ok(#(unit_id, said(sent.1)))
      Connection(..)
      | step.Sessions
      | step.HandOff
      | step.Store
      | step.Maps
      | step.Map(..)
      | step.CharacterNamed(..)
      | step.ZoneChannel(..) -> Error(Nil)
    }
  })
}

/// What the step sends to players' connections, by the connection's number and
/// what it says, in connection order.
fn player_sends(taken: ServiceStep(map.Outgoing)) -> List(#(Int, String)) {
  list.filter_map(sends(taken), fn(sent) {
    case sent.0 {
      Connection(ConnectionId(number)) -> Ok(#(number, said(sent.1)))
      Creature(..)
      | step.Sessions
      | step.HandOff
      | step.Store
      | step.Maps
      | step.Map(..)
      | step.CharacterNamed(..)
      | step.ZoneChannel(..) -> Error(Nil)
    }
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

fn said(message: map.Outgoing) -> String {
  case message {
    Watched(by: ConnectionId(number)) -> "Watched by " <> int.to_string(number)
    Gone(unit_id:) -> "Gone " <> int.to_string(unit_id)
    map.Unwatched(by: ConnectionId(number)) ->
      "Unwatched by " <> int.to_string(number)
    map.Retire -> "Retire"
    map.Joined(..) | map.Left -> "an answer"
  }
}

/// The one creature a step starts, with its watch.
fn the_start(
  taken: ServiceStep(map.Outgoing),
) -> #(step.WatchId, step.CreatureStart) {
  let assert [only] = starts(taken) as "exactly one creature starts"
  only
}

/// Whether the spawn is dormant: no creature, no wait, no failure.
fn dormant(state state: State, spawn spawn: Int) -> Bool {
  map.spawn_state(state:, spawn: SpawnId(spawn)) == Error(Nil)
}

pub fn a_started_map_starts_its_sweep_timer_and_no_creature_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = started(at: [0.0, 100.0])
  assert starts(taken) == []
    as "a map stands no creature until a player sees one"
  assert timers(taken) == [#(0, map_support.sweep_ms)]
    as "the sweep timer is TimerId(0): spawn numbers start at 1, so no spawn's timer is it"
  assert dormant(state:, spawn: 1) && dormant(state:, spawn: 2)
    as "every spawn is dormant"
}

pub fn a_join_starts_exactly_the_spawns_within_1024_each_told_watched_and_the_reply_comes_first_test() -> Nil {
  use <- owned_test.run(5000)
  // Sight is 1024 units, inclusive (`sight`): spawns 1 to 3 at 0, 500 and 1024
  // are seen from x 0; 1024.5 and 5000 are not.
  let #(state, _) = started(at: [0.0, 500.0, 1024.0, 1024.5, 5000.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let creatures = starts(taken)
  assert list.map(creatures, fn(start) { { start.1 }.spawn_id })
    == [SpawnId(1), SpawnId(2), SpawnId(3)]
    as "the three spawns in sight start, in the order of the spawns, and no other"
  let units = list.map(creatures, fn(start) { { start.1 }.unit_id })
  assert list.length(list.unique(list.prepend(units, 1))) == 4
    && list.all(units, fn(unit_id) { unit_id > 0 && unit_id < 1_048_576 })
    as "each creature is a unit of its own, and none is the player's unit 1"
  assert list.all(creatures, fn(start) {
    let WatchId(number) = start.0
    { start.1 }.life == number
  })
    as "a creature's life is the number of the watch it is started under"
  assert creature_sends(taken)
    == list.map(units, fn(unit_id) { #(unit_id, "Watched by 1") })
    as "each is told the player sees it, and it sends the 0x262"
  let labels =
    list.map(support.effects_of(taken), fn(effect) {
      case effect {
        step.Watch(..) -> "watch"
        OwnEffect(Reply(..)) -> "reply"
        OwnEffect(StartCreature(..)) -> "start"
        OwnEffect(Send(..)) -> "send"
        OwnEffect(StartServiceTimer(..)) | OwnEffect(CancelServiceTimer(..)) ->
          "timer"
        step.Unwatch(..) | step.Log(..) | step.Stop -> "other"
      }
    })
  assert list.take(labels, 2) == ["watch", "reply"]
    as "the Join is answered first"
  assert list.drop(labels, 2)
    == ["start", "start", "start", "send", "send", "send"]
    as "then the starts, then the Watched sends"
  assert dormant(state:, spawn: 4) && dormant(state:, spawn: 5)
    as "a spawn beyond sight has no process and no state"
}

pub fn a_move_into_sight_starts_the_creature_and_tells_it_the_player_sees_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: far)
  assert starts(taken) == [] as "far from every spawn, nothing starts"
  let #(_, taken) = move(state:, at_ms: 7000, connection: 1, x: 0.0)
  let #(_, creature) = the_start(taken)
  assert creature.spawn_id == SpawnId(1)
  assert creature_sends(taken) == [#(creature.unit_id, "Watched by 1")]
    as "the creature is told the player sees it and sends its one 0x262"
}

pub fn the_last_viewer_leaving_sends_an_unwatched_and_the_creature_stops_between_60_and_70_seconds_later_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(_, creature) = the_start(taken)
  let #(state, taken) = move(state:, at_ms: 7000, connection: 1, x: far)
  assert creature_sends(taken) == [#(creature.unit_id, "Unwatched by 1")]
    as "the player's loss of sight is told to the creature, which sends the 0x355"
  // The sweep timer started at 5000 fires every 10 s: 15000, 25000, ... The
  // creature has been idle since 7000, so it retires at the first sweep at or
  // after 67000, which is 75000: 68 s after the last viewer left.
  let sweeps =
    int.range(from: 1, to: 9, with: [], run: fn(times, count) {
      [started_at_ms + count * map_support.sweep_ms, ..times]
    })
    |> list.reverse
  let #(_, retired) =
    list.fold(sweeps, #(state, []), fn(held, at_ms) {
      let #(state, retired) = held
      let #(state, taken) = sweep(state:, at_ms:)
      case creature_sends(taken) {
        [] -> #(state, retired)
        [#(unit_id, "Retire")] -> #(state, [#(at_ms, unit_id), ..retired])
        _ -> panic as "a sweep sent something other than one Retire"
      }
    })
  assert retired == [#(75_000, creature.unit_id)]
    as "not at the sweep at 65000, when it has been idle 58 s, and at the first after 60 s"
}

pub fn a_spawn_seen_again_before_the_idle_stop_is_not_restarted_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(_, creature) = the_start(taken)
  let #(state, _) = move(state:, at_ms: 7000, connection: 1, x: far)
  let #(state, taken) = move(state:, at_ms: 30_000, connection: 1, x: 0.0)
  assert starts(taken) == [] as "the same creature runs: nothing starts"
  assert creature_sends(taken) == [#(creature.unit_id, "Watched by 1")]
    as "it is told the player sees it again, and sends its 0x262 once more"
  let #(_, taken) = sweep(state:, at_ms: 75_000)
  assert creature_sends(taken) == []
    as "a creature with a viewer is never retired, however long ago it was idle"
}

pub fn a_spawn_stopped_and_seen_again_keeps_its_unit_id_under_a_new_life_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(first_watch, first) = the_start(taken)
  let #(state, _) = move(state:, at_ms: 7000, connection: 1, x: far)
  let #(state, taken) = sweep(state:, at_ms: 75_000)
  assert creature_sends(taken) == [#(first.unit_id, "Retire")]
  let #(state, taken) =
    feed(state:, at_ms: 75_100, event: WatchEnded(first_watch))
  assert player_sends(taken) == []
    as "a clean stop sends no Gone: the 0x355 went with the last viewer"
  assert starts(taken) == [] && timers(taken) == []
    as "the spawn is dormant, with no restart timer"
  assert dormant(state:, spawn: 1)
  let #(_, taken) = move(state:, at_ms: 90_000, connection: 1, x: 0.0)
  let #(second_watch, second) = the_start(taken)
  assert second.unit_id == first.unit_id
    as "a spawn has one unit id for the run, reused after a clean stop (death.creature_respawn)"
  assert second_watch != first_watch && second.life != first.life
    as "under a new life, so its address is not the stopped creature's"
  assert creature_sends(taken) == [#(first.unit_id, "Watched by 1")]
}

pub fn a_spawn_seen_while_its_creature_retires_restarts_only_after_the_creatures_end_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(first_watch, first) = the_start(taken)
  let #(state, _) = move(state:, at_ms: 7000, connection: 1, x: far)
  let #(state, _) = sweep(state:, at_ms: 75_000)
  let #(state, taken) = move(state:, at_ms: 75_050, connection: 1, x: 0.0)
  assert starts(taken) == [] && creature_sends(taken) == []
    as "the creature has been told to stop: nothing starts and it is told nothing"
  let #(_, taken) = feed(state:, at_ms: 75_100, event: WatchEnded(first_watch))
  let #(second_watch, second) = the_start(taken)
  assert second.unit_id == first.unit_id && second_watch != first_watch
    as "at its end a creature starts under the same unit id and a new life"
  assert creature_sends(taken) == [#(first.unit_id, "Watched by 1")]
    as "and the player who was held is told to it"
}

pub fn a_creature_that_crashes_while_retiring_is_taken_as_retired_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, _) = the_start(taken)
  let #(state, _) = move(state:, at_ms: 7000, connection: 1, x: far)
  let #(state, _) = sweep(state:, at_ms: 75_000)
  let #(state, taken) = feed(state:, at_ms: 75_010, event: WatchEnded(watch))
  assert player_sends(taken) == [] && timers(taken) == []
    as "no client shows the unit: no Gone and no restart timer"
  assert dormant(state:, spawn: 1)
}

pub fn a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, first) = the_start(taken)
  let #(state, _) = join(state:, at_ms: 6100, connection: 2, x: far)
  let #(state, taken) = feed(state:, at_ms: 7000, event: WatchEnded(watch))
  assert player_sends(taken)
    == [
      #(1, "Gone " <> int.to_string(first.unit_id)),
      #(2, "Gone " <> int.to_string(first.unit_id)),
    ]
    as "every player in the map is told the unit is gone, also one that did not see it"
  assert timers(taken) == [#(1, map_support.creature_restart_ms)]
    as "the spawn waits the respawn time, under the timer of its own number"
  assert starts(taken) == [] as "and is not started again at once"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 67_000,
      event: OwnEvent(ServiceTimerFired(timer: step.TimerId(1))),
    )
  let #(_, second) = the_start(taken)
  assert second.unit_id != first.unit_id && second.unit_id > 0
    as "the unit id was given up with the Gone, so the new creature has another"
  assert creature_sends(taken) == [#(second.unit_id, "Watched by 1")]
    as "the player in sight is told to it"
}

pub fn a_restart_timer_that_fires_with_no_one_in_sight_leaves_the_spawn_dormant_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, _) = the_start(taken)
  let #(state, _) = feed(state:, at_ms: 7000, event: WatchEnded(watch))
  let #(state, _) = move(state:, at_ms: 8000, connection: 1, x: far)
  let #(state, taken) =
    feed(
      state:,
      at_ms: 67_000,
      event: OwnEvent(ServiceTimerFired(timer: step.TimerId(1))),
    )
  assert starts(taken) == [] as "no one sees the spawn: no creature starts"
  assert dormant(state:, spawn: 1)
}

pub fn a_creature_that_does_not_start_leaves_its_spawn_empty_for_the_run_and_the_others_appear_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0, 100.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(first_watch, first), #(_, second)] = starts(taken)
    as "two creatures start in the burst"
  assert creature_sends(taken)
    == [#(first.unit_id, "Watched by 1"), #(second.unit_id, "Watched by 1")]
    as "the other spawn's creature is told the player sees it whatever the first's start does"
  let #(state, taken) =
    feed(
      state:,
      at_ms: 6001,
      event: OwnEvent(CreatureNotStarted(
        watch: first_watch,
        reason: "the creature supervisor is not running",
      )),
    )
  let assert [line] = support.logs(taken)
    as "the map says that the creature did not start, once"
  assert line.level == LogError
    as "a creature that does not start is the server's failure, an error line"
  assert string.contains(line.text, "the creature supervisor is not running")
    as "the line gives the reason the supervisor reported"
  assert line.about.map == Some(ship)
  assert starts(taken) == [] && timers(taken) == []
    as "the spawn stays empty: no later creature is started for it"
  assert map.spawn_state(state:, spawn: SpawnId(1)) == Ok(map.Failed)
  let #(_, taken) = move(state:, at_ms: 7000, connection: 1, x: 10.0)
  assert starts(taken) == [] && creature_sends(taken) == []
    as "a move in sight of the failed spawn starts nothing and tells nothing"
}

pub fn a_leave_right_after_a_burst_sends_unwatched_to_each_creature_of_the_player_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = started(at: [0.0, 100.0, 200.0])
  let #(state, taken) = join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let units = list.map(starts(taken), fn(start) { { start.1 }.unit_id })
  let #(state, taken) = leave(state:, at_ms: 6001, connection: 1)
  assert creature_sends(taken)
    == list.map(units, fn(unit_id) { #(unit_id, "Unwatched by 1") })
    as "the player's creatures are told it no longer sees them, in the order of the spawns"
  let #(_, taken) = sweep(state:, at_ms: 75_000)
  assert creature_sends(taken)
    == list.map(units, fn(unit_id) { #(unit_id, "Retire") })
    as "and each stops at the first sweep after the idle stop"
}
