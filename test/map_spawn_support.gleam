//// What the tests of a map that starts and stops creatures share: the map's
//// inputs as a connection or a timer makes them, at a time of the test's choosing,
//// and the effects of a step by kind. A rule's test drives the clock through the
//// inputs' times, so no test waits.

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId,
  CancelServiceTimer, Connection, ConnectionId, Creature, OwnEffect, OwnEvent,
  Reply, Send, ServiceTimerFired, StartCreature, StartServiceTimer, Started,
  Told,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/world_map/creature_kind.{type Kinds, Kind, Kinds}
import genesis_prime/world_map/map.{type State, Join, Leave, Moved, Watched}
import genesis_prime/world_map/map_id.{MapId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/string
import map_support
import place_support
import spawn_support

/// The time the map starts at on the monotonic clock.
pub const started_at_ms = 5000

pub const ship = MapId(world_id: 3460, instance: 0)

/// Far from every spawn the tests stand: no creature is in sight there.
pub const far = 50_000.0

/// A place `x` units along the world's x axis in Warfare Woods.
pub fn at(x: Float) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: spawn_support.warfare_woods,
    x:,
    y: 0.0,
    z: 0.0,
  )
}

pub fn feed(
  state state: State,
  at_ms at_ms: Int,
  event event: Event(ServiceEvent(map.Message)),
) -> #(State, ServiceStep(map.Outgoing)) {
  map.step(state, support.input_at_ms(ms: at_ms, event:))
}

/// A map with a spawn at each of these x positions, numbered from 1, started.
pub fn started(at xs: List(Float)) -> #(State, ServiceStep(map.Outgoing)) {
  started_with(at: xs, kinds: default_kinds())
}

/// The kinds of the tests' maps: the server's 60 s default for every creature.
pub fn default_kinds() -> Kinds {
  Kinds(
    default: Kind(
      respawn_ms: map_support.respawn_ms,
      attack_spell4_id: Spell4Id(5649),
      attack_interval_ms: 1500,
    ),
    by_creature: dict.new(),
  )
}

/// The same with the kinds the test chooses.
pub fn started_with(
  at xs: List(Float),
  kinds kinds: Kinds,
) -> #(State, ServiceStep(map.Outgoing)) {
  let state =
    map_support.standing_with(
      incarnation: 1,
      spawns: list.index_map(xs, fn(x, index) {
        spawn_support.battle_beast(number: index + 1, x:)
      }),
      kinds:,
    )
  feed(state:, at_ms: started_at_ms, event: OwnEvent(Started))
}

/// A join of connection `connection` at `x`, at time `at_ms`.
pub fn join(
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
        stay: map_support.stay(count: 1),
      ),
    )),
  )
}

/// A move of connection `connection` to `x`, at time `at_ms`.
pub fn move(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  x x: Float,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: Moved(
        connection: ConnectionId(connection),
        place: at(x),
        seq: at_ms,
      )),
    ),
  )
}

/// A leave of connection `connection`, at time `at_ms`.
pub fn leave(
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
pub fn sweep(
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
pub fn starts(
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
pub fn timers(taken: ServiceStep(map.Outgoing)) -> List(#(Int, Int)) {
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
pub fn sends(
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
pub fn creature_sends(
  taken: ServiceStep(map.Outgoing),
) -> List(#(Int, String)) {
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

/// What the step tells creatures of the rings, by the creature's unit id and what
/// it says (`Approached by 1`, `Withdrew by 1`), in the order sent.
pub fn ring_sends(taken: ServiceStep(map.Outgoing)) -> List(#(Int, String)) {
  creature_sends(taken)
  |> list.filter(fn(sent) {
    case sent.1 {
      "Approached by " <> _ | "Withdrew by " <> _ -> True
      _ -> False
    }
  })
}

/// What the step sends to players' connections, by the connection's number and
/// what it says, in connection order.
pub fn player_sends(taken: ServiceStep(map.Outgoing)) -> List(#(Int, String)) {
  support.sends(taken)
  |> list.map(fn(sent) { #(sent.0, said(sent.1)) })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

pub fn said(message: map.Outgoing) -> String {
  case message {
    Watched(by: ConnectionId(number), ..)
    | map.Noticed(notice: map.SeenBy(by: ConnectionId(number), ..), ..) ->
      "Watched by " <> int.to_string(number)
    map.Noticed(notice: map.Gone(unit_id:), ..) ->
      "Gone " <> int.to_string(unit_id)
    map.Noticed(notice: map.ObjectsSeen(units:), ..) ->
      "Objects seen "
      <> string.join(
        list.map(units, fn(unit) { int.to_string(unit.unit_id) }),
        " ",
      )
    map.Noticed(notice: map.ObjectsUnseen(unit_ids:), ..) ->
      "Objects unseen " <> string.join(list.map(unit_ids, int.to_string), " ")
    map.Unwatched(by: ConnectionId(number))
    | map.Noticed(notice: map.UnseenBy(by: ConnectionId(number)), ..) ->
      "Unwatched by " <> int.to_string(number)
    map.Retire -> "Retire"
    map.Approached(by: ConnectionId(number), ..) ->
      "Approached by " <> int.to_string(number)
    map.Withdrew(by: ConnectionId(number)) ->
      "Withdrew by " <> int.to_string(number)
    map.Joined(..)
    | map.NotJoined(..)
    | map.Summoned(..)
    | map.NotSummoned(..)
    | map.Left -> "an answer"
  }
}

/// A move of connection `connection` to `place`, which holds a facing, at time
/// `at_ms`.
pub fn move_to(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  place place: Place,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: Moved(
        connection: ConnectionId(connection),
        place:,
        seq: at_ms,
      )),
    ),
  )
}

/// The first 0xF2 of connection `connection`'s client, at time `at_ms`.
pub fn ready(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map.Ready(connection: ConnectionId(connection), seq: 0)),
    ),
  )
}

/// The connection's tell that its player entered stealth (`stealthed` True) or left
/// it, at time `at_ms`.
pub fn stealth(
  state state: State,
  at_ms at_ms: Int,
  connection connection: Int,
  stealthed stealthed: Bool,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map.StealthChanged(
        connection: ConnectionId(connection),
        stealthed:,
      )),
    ),
  )
}

/// A development summon of Creature2 `creature_id` by connection `connection`'s
/// player, asked by caller `caller`, at time `at_ms`.
pub fn summon(
  state state: State,
  at_ms at_ms: Int,
  caller caller: Int,
  connection connection: Int,
  creature_id creature_id: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(Asked(
      caller: CallerId(caller),
      message: map.Summon(
        connection: ConnectionId(connection),
        creature_id: id.Creature2Id(creature_id),
      ),
    )),
  )
}

/// The firing of the timer the map starts for the run-only spawn `spawn`: the
/// shell gives it after the summon's start is carried out, and a failure of the
/// start before it.
pub fn start_settled(
  state state: State,
  at_ms at_ms: Int,
  spawn spawn: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(ServiceTimerFired(timer: step.TimerId(spawn))),
  )
}

/// The end of the creature watched under `watch`, at time `at_ms`: its corpse
/// timer's stop, a crash or any other end ends the watch the same way.
pub fn creature_ended(
  state state: State,
  at_ms at_ms: Int,
  watch watch: step.WatchId,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(state:, at_ms:, event: step.WatchEnded(watch:))
}

/// The start of a creature the shell could not carry out, as it gives the rule
/// that, at time `at_ms`.
pub fn creature_not_started(
  state state: State,
  at_ms at_ms: Int,
  watch watch: step.WatchId,
  reason reason: String,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
    at_ms:,
    event: OwnEvent(step.CreatureNotStarted(watch:, reason:)),
  )
}
