//// A creature's rule (`genesis_prime/world_map/creature`), run as the pure rule it
//// is: inputs in, new state and effects out. Expected values come from these
//// places.
//// - The doc comment of `genesis_prime/world_map/creature` (its sequence and its
////   failure table): told `Watched(by)` it sends that connection its 0x262 once it
////   shows itself; told `Unwatched(by)` its 0x355, if it showed itself; a creature
////   that waits `appear_after_ms` shows itself when its timer fires; it watches its
////   map run and stops with it.
//// - Design C (the Design artifact of issue 274, section 2): every message about a
////   unit comes from its owner's process, so the 0x262 and the 0x355 are the
////   creature's own sends, to the viewer's connection.
//// - The map's clock: `server_time_estimate_start` is the milliseconds since the
////   map started, from the origin the creature was given (`map.server_time`).

import connection_rule_support as support
import genesis_prime/client_connection.{
  type PeerNews, CreatureAppeared, PeerNews, Removed,
}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Connection, ConnectionId,
  CreatureStart, OwnEffect, OwnEvent, Reply, Send, ServiceTimerFired,
  StartCreature, StartServiceTimer, Started, Stop, TimerId, Told, WatchEnded,
  WatchId,
}
import genesis_prime/world_map/creature.{
  type State, Settings, Unwatched, Watched,
}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/list
import owned_test
import spawn_support

const ship = MapId(world_id: 3460, instance: 0)

/// The time the map's clock started at on the monotonic clock.
const clock_origin_ms = 5000

/// A creature standing at spawn 1 as unit 7 of the first run, that shows itself
/// `appear_after_ms` after it starts.
fn creature(appear_after_ms appear_after_ms: Int) -> State {
  creature.new(Settings(
    creature: CreatureStart(
      map: ship,
      incarnation: 1,
      unit_id: 7,
      spawn: SpawnId(1),
      appear_after_ms:,
      clock_origin_ms:,
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

pub fn a_creature_that_stands_from_the_start_watches_its_run_and_sends_its_0x262_to_each_player_who_sees_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    feed(
      state: creature(appear_after_ms: 0),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
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

pub fn a_creature_that_appears_later_sends_its_0x262_only_when_its_timer_fires_and_its_0x355_to_who_stops_seeing_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) =
    feed(
      state: creature(appear_after_ms: 60_000),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  assert list.contains(
    support.effects_of(taken),
    OwnEffect(StartServiceTimer(timer: TimerId(1), after_ms: 60_000)),
  )
    as "the creature waits the respawn time before it shows itself"
  let #(state, taken) =
    feed(
      state:,
      at_ms: 6000,
      event: OwnEvent(Told(Watched(by: ConnectionId(5)))),
    )
  assert sent(taken) == []
    as "a creature that has not shown itself sends nothing"
  let #(state, taken) =
    feed(state:, at_ms: 65_000, event: OwnEvent(ServiceTimerFired(TimerId(1))))
  let assert [#(5, PeerNews(unit_id: 7, news: CreatureAppeared(..), ..))] =
    sent(taken)
    as "it shows itself to the player who saw it by then"
  let #(state, taken) =
    feed(
      state:,
      at_ms: 66_000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(5)))),
    )
  let assert [#(5, PeerNews(unit_id: 7, news: Removed, ..))] = sent(taken)
    as "a player who stops seeing it is sent its 0x355"
  let #(_, taken) =
    feed(
      state:,
      at_ms: 67_000,
      event: OwnEvent(Told(Unwatched(by: ConnectionId(5)))),
    )
  assert sent(taken) == []
    as "a connection that is not a viewer is sent nothing"
}

pub fn a_creature_stops_when_its_run_ends_and_when_the_server_stops_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    feed(
      state: creature(appear_after_ms: 0),
      at_ms: 5000,
      event: OwnEvent(Started),
    )
  let #(_, taken) = feed(state:, at_ms: 6000, event: WatchEnded(WatchId(1)))
  assert support.stops(taken) as "the end of its run ends the creature"
  let #(_, taken) =
    feed(state:, at_ms: 6000, event: step.Stopping(deadline_ms: 11_000))
  assert support.stops(taken) as "the server stopping ends it"
}
