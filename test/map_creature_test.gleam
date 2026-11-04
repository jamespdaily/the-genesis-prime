//// The creatures a map stands (`genesis_prime/world_map/map`), run as the pure
//// rule it is: inputs in, new state and effects out. Expected values come from
//// these places.
//// - The design of the combat core (the Design artifact of issue 274, section 2
////   and the failure table, step C): on `Started` the map starts one creature
////   for each spawn of its world, and the shell watches it; a creature that does
////   not start leaves its spawn empty for the run with an error line; a creature
////   that crashes while shown is `Gone` to every player in the map and its spawn
////   returns after the respawn time as a new unit, in sight of the players who
////   saw the creature that ended; the map decides who sees whom, so a player
////   that comes within 1024 units of a creature is told to it `Watched`, and the
////   creature sends the 0x262 itself.
//// - Unit ids: never 0 (a 0x262 with unit id 0 becomes the controlled unit,
////   0x1403d9760), never given twice in the map's life, and below 2^20 (the cast
////   id is built from the unit id, issue 274's design, section 3).
//// - The map's doc comment: a creature's address is `Creature(map, incarnation,
////   unit_id)`, and `Gone` goes to every player in the map, also one that does
////   not see the unit.

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId,
  CancelServiceTimer, Connection, ConnectionId, Creature, CreatureNotStarted,
  LogError, OwnEffect, OwnEvent, Reply, Send, StartCreature, StartServiceTimer,
  Started, WatchEnded,
}
import genesis_prime/world_map/map.{type State, Gone, Join, Watched}
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
  event event: Event(ServiceEvent(map.Message)),
) -> #(State, ServiceStep(map.Outgoing)) {
  map.step(state, support.input_at_ms(ms: started_at_ms, event:))
}

/// A map standing creatures at the spawns, started.
fn started(
  spawns spawns: List(spawn_id.SpawnId),
) -> #(State, ServiceStep(map.Outgoing)) {
  let state =
    map_support.standing(
      incarnation: 1,
      spawns: list.map(spawns, fn(spawn) {
        let SpawnId(number) = spawn
        spawn_support.battle_beast(number:, x: int.to_float(number * 100 - 100))
      }),
    )
  feed(state:, event: OwnEvent(Started))
}

/// A join of connection `connection` at `x`.
fn join(
  state state: State,
  connection connection: Int,
  x x: Float,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state:,
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
/// (`Watched by 1`).
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
    map.Joined(..) | map.Left -> "an answer"
  }
}

pub fn a_started_map_starts_one_creature_for_each_spawn_of_its_world_under_distinct_unit_ids_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = started(spawns: [SpawnId(1), SpawnId(2), SpawnId(3)])
  let creatures = starts(taken)
  assert list.map(creatures, fn(start) { { start.1 }.spawn })
    == [SpawnId(1), SpawnId(2), SpawnId(3)]
    as "one creature for each spawn, in the order of the spawns"
  let units = list.map(creatures, fn(start) { { start.1 }.unit_id })
  assert list.length(list.unique(units)) == 3 as "each creature is its own unit"
  assert list.all(units, fn(unit_id) { unit_id > 0 && unit_id < 1_048_576 })
    as "no unit id is 0 and each is below 2^20"
  let watches = list.map(creatures, fn(start) { start.0 })
  assert list.length(list.unique(watches)) == 3
    as "each creature is watched under a watch of its own"
  assert list.all(creatures, fn(start) {
    let creature = start.1
    creature.map == ship
    && creature.incarnation == 1
    && creature.appear_after_ms == 0
    && creature.clock_origin_ms == started_at_ms
  })
    as "each creature belongs to this run, stands from the start, and is stamped from the map's clock"
}

pub fn a_creature_that_does_not_start_leaves_its_spawn_empty_for_the_run_with_an_error_line_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = started(spawns: [SpawnId(1), SpawnId(2)])
  let assert [#(first_watch, first), #(_, second)] = starts(taken)
    as "two creatures start"
  let #(state, taken) =
    feed(
      state:,
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
  assert starts(taken) == []
    as "the spawn stays empty: no later creature is started for it"
  let #(_, taken) = join(state:, connection: 1, x: 0.0)
  assert creature_sends(taken) == [#(second.unit_id, "Watched by 1")]
    as "a player in sight is told to the creature that runs and to none for the spawn left empty"
  assert first.unit_id != second.unit_id
}

pub fn a_creature_that_crashes_while_shown_is_gone_and_its_spawn_returns_after_the_respawn_time_as_a_new_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = started(spawns: [SpawnId(1)])
  let assert [#(creature_watch, creature)] = starts(taken)
    as "the creature starts"
  let #(state, taken) = join(state:, connection: 1, x: 0.0)
  assert creature_sends(taken) == [#(creature.unit_id, "Watched by 1")]
    as "the player within 1024 units of the creature is told to it, and the creature sends the 0x262"
  let #(state, taken) = join(state:, connection: 2, x: 5000.0)
  assert creature_sends(taken) == []
    as "a player 5000 units away is told to no creature"
  let #(_, taken) = feed(state:, event: WatchEnded(creature_watch))
  assert player_sends(taken)
    == [
      #(1, "Gone " <> int.to_string(creature.unit_id)),
      #(2, "Gone " <> int.to_string(creature.unit_id)),
    ]
    as "every player in the map is told the unit is gone, also one that did not see it"
  let assert [#(new_watch, returned)] = starts(taken)
    as "the spawn is started again, once"
  assert returned.spawn == creature.spawn as "the new creature is the spawn's"
  assert returned.unit_id != creature.unit_id
    && returned.unit_id != 2
    && returned.unit_id != 3
    as "it is a new unit, whose id is none a player or the creature held"
  assert returned.unit_id > 0 && returned.unit_id < 1_048_576
  assert returned.appear_after_ms == map_support.creature_restart_ms
    as "it shows itself only after the respawn time"
  assert new_watch != creature_watch
  assert creature_sends(taken) == [#(returned.unit_id, "Watched by 1")]
    as "the player who saw the creature that ended is in sight of the new one, and no other"
}
