//// A creature's rule (`genesis_prime/world_map/creature`), run as the pure rule it
//// is: inputs in, new state and effects out. Expected values come from these
//// places.
//// - The doc comment of `genesis_prime/world_map/creature` (its sequence and its
////   failure table): told `Watched(by)` it sends that connection its 0x262; told
////   `Unwatched(by)` its 0x355, if that connection was a viewer; it watches its
////   map run and stops with it.
//// - Design C (the Design artifact of issue 274, section 2): every message about a
////   unit comes from its owner's process, so the 0x262 and the 0x355 are the
////   creature's own sends, to the viewer's connection.
//// - The map's clock: `server_time_estimate_start` is the milliseconds since the
////   map started, from the origin the creature was given (`map.server_time`).
//// - The creature's values are the Virtual Battle Beast's (`spawn_support`).

import connection_rule_support as support
import genesis_prime/client_connection.{
  type PeerNews, CreatureAppeared, PeerNews, Removed,
}
import genesis_prime/step.{
  type ConnectionId, type Event, type ServiceEvent, type ServiceStep, Connection,
  ConnectionId, CreatureStart, OwnEffect, OwnEvent, Reply, Send, StartCreature,
  StartServiceTimer, Started, Stop, Told, WatchEnded, WatchId,
}
import genesis_prime/world_map/creature.{
  type State, Retire, Settings, Unwatched, Watched,
}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/list
import owned_test
import spawn_support

const ship = MapId(world_id: 3460, instance: 0)

/// The time the map's clock started at on the monotonic clock.
const clock_origin_ms = 5000

/// A creature standing at a Battle Beast spawn as unit 7 of the first run.
fn creature() -> State {
  creature_for(viewers: [])
}

/// The same creature, started for these players, who see the spawn.
fn creature_for(viewers viewers: List(ConnectionId)) -> State {
  creature.new(Settings(
    creature: CreatureStart(
      map: ship,
      incarnation: 1,
      unit_id: 7,
      life: 3,
      spawn_id: SpawnId(1),
      clock_origin_ms:,
      viewers:,
    ),
    spawn: spawn_support.battle_beast(number: 1, x: 0.0),
  ))
}

fn feed(
  state state: State,
  at_ms at_ms: Int,
  event event: Event(ServiceEvent(creature.Message)),
) -> #(State, ServiceStep(PeerNews)) {
  creature.step(state, support.input_at_ms(ms: at_ms, event:))
}

/// What the step sends, to the connection's number: the news it carries.
fn sent(taken: ServiceStep(PeerNews)) -> List(#(Int, PeerNews)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: Connection(ConnectionId(number)), message:)) ->
        Ok(#(number, message))
      OwnEffect(Send(..))
      | OwnEffect(Reply(..))
      | OwnEffect(StartCreature(..))
      | OwnEffect(StartServiceTimer(..))
      | OwnEffect(step.CancelServiceTimer(..))
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | Stop -> Error(Nil)
    }
  })
}

pub fn a_creature_watches_its_run_and_sends_its_0x262_to_each_player_who_sees_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  assert support.watches(taken) == [#(WatchId(1), step.Map(ship, 1))]
    as "the creature watches the run that started it, so it ends with it"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 6500,
      event: OwnEvent(Told(Watched(by: ConnectionId(5)))),
    )
  let assert [
    #(5, PeerNews(map:, incarnation:, unit_id:, news: CreatureAppeared(unit))),
  ] = sent(taken)
    as "one 0x262, to the connection of the player who sees the creature"
  assert map == ship && incarnation == 1 && unit_id == 7
    as "the news names the creature's unit in this run of the map"
  assert unit.unit_id == 7 && unit.creature_id == 73_464
  assert unit.tail.server_time_estimate_start == 1500
    as "stamped from the map's clock: 6500 ms on the monotonic clock, 1500 after the map started"
}

pub fn a_creature_sends_its_0x355_once_to_a_player_who_stops_seeing_it_and_nothing_to_one_that_never_saw_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(state, _) =
    feed(
      state:,
      at_ms: 6000,
      event: OwnEvent(Told(Watched(by: ConnectionId(5)))),
    )
  let #(state, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(5)))),
    )
  let assert [#(5, PeerNews(unit_id: 7, news: Removed, ..))] = sent(taken)
    as "a player who stops seeing it is sent its 0x355"
  let #(state, taken) =
    feed(
      state:,
      at_ms: 8000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(5)))),
    )
  assert sent(taken) == []
    as "a connection that is not a viewer is sent nothing"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 9000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(6)))),
    )
  assert sent(taken) == [] as "a connection that never saw it is sent nothing"
}

pub fn a_creature_stops_when_its_run_ends_and_when_the_server_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(_, taken) = feed(state:, at_ms: 6000, event: WatchEnded(WatchId(1)))
  assert support.stops(taken) as "the end of its run ends the creature"
  let #(_, taken) =
    feed(state:, at_ms: 6000, event: step.Stopping(deadline_ms: 11_000))
  assert support.stops(taken) as "the server stopping ends it"
}

pub fn a_creature_told_to_retire_stops_with_nothing_to_send_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(state: creature(), at_ms: 5000, event: OwnEvent(Started))
  let #(_, taken) = feed(state:, at_ms: 80_000, event: OwnEvent(Told(Retire)))
  assert support.stops(taken)
    as "the map's Retire ends the creature: no player has seen it for the idle stop"
  assert sent(taken) == []
    as "its viewers went with their Unwatched, so there is no 0x355 left to send"
}

pub fn a_creature_started_for_players_sends_each_its_0x262_as_it_starts_test() -> Nil {
  use <- owned_test.run(5000)
  // The map's start of a creature names its first viewers (CreatureStart), so a
  // burst of starts is not followed by a burst of Watched sends.
  let #(state, taken) =
    feed(
      state: creature_for(viewers: [ConnectionId(2), ConnectionId(5)]),
      at_ms: 6500,
      event: OwnEvent(Started),
    )
  let assert [
    #(2, PeerNews(unit_id: 7, news: CreatureAppeared(first), ..)),
    #(5, PeerNews(unit_id: 7, news: CreatureAppeared(second), ..)),
  ] = sent(taken)
    as "one 0x262 for each first viewer, in the order the map gave them"
  assert first.tail.server_time_estimate_start == 1500
    && second.tail.server_time_estimate_start == 1500
    as "stamped from the map's clock at the creature's start"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(2)))),
    )
  let assert [#(2, PeerNews(news: Removed, ..))] = sent(taken)
    as "a first viewer is a viewer: it is sent the 0x355 when it stops seeing the creature"
  Nil
}
