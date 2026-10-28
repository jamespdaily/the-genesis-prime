//// Maps and the maps it starts (`genesis_prime/world_map/maps`), started under
//// a world supervisor as the server's tree starts them. Expected values come
//// from these places.
//// - The doc comment of `genesis_prime/world_map/maps`: the first find for
////   a map starts it, the next finds the same run; each start has an
////   incarnation, unique in the node's life; `find` answers only the run with
////   the incarnation it is given and never starts a map; a map that ended is
////   started again, with a new incarnation, by the next `find_or_start`; the
////   deadline of a find is the asker's, and Maps not running, or a start that
////   fails, is `Error(Nil)`.
//// - The map's doc comment (`genesis_prime/world_map/map`): a player's
////   connection is watched, and its end removes the player.
//// - OTP's supervisor: a child exits with `shutdown` when told to, and a
////   permanent child is restarted when it crashes.
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/rule_recording
import genesis_prime/server
import genesis_prime/service
import genesis_prime/step.{type Address, Connection, ConnectionId}
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId, MapId}
import genesis_prime/world_map/maps.{type MapProcess}
import gleam/erlang/process.{type Name, type Pid}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor as supervisor
import owned_test
import recording_support
import simplifile

/// The world supervisor as the server builds it, with the names it was built
/// with, a registry the maps find their players' connections in, and, when the
/// test records, the folder of the maps' recordings.
type World {
  World(tree: Pid, maps: Name(maps.Message), registry: Registry)
}

fn start_world(recording_folder: Option(String)) -> World {
  let maps_name = process.new_name("maps")
  let scope = registry.new()
  let world =
    server.World(
      maps: maps_name,
      map_supervisor: process.new_name("map_supervisor"),
      maps_call_ms: 1000,
      map_shutdown_ms: 1000,
      map_recordings: option.map(recording_folder, recording_support.recorder(
        _,
        map.rule_name,
      )),
    )
  let tree =
    supervisor.new(supervisor.RestForOne)
    |> supervisor.restart_tolerance(intensity: 3, period: 10)
    |> supervisor.add(registry.supervised(scope))
  let assert Ok(started) =
    server.add_world(tree:, world:, locate: locate(scope, _))
    |> supervisor.start
    as "the world tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  World(tree: started.pid, maps: maps_name, registry: scope)
}

fn locate(scope: Registry, address: Address) -> Result(Pid, Nil) {
  case address {
    Connection(connection:) -> registry.find(scope, connection)
    step.Sessions | step.HandOff | step.Store | step.Maps | step.Map(..) ->
      Error(Nil)
  }
}

/// A process that is the connection with this id until it is stopped.
fn connection(world: World, id: Int) -> Pid {
  let ready = process.new_subject()
  let pid =
    process.spawn_unlinked(fn() {
      registry.join(world.registry, connection: ConnectionId(id))
      process.send(ready, Nil)
      process.sleep_forever()
    })
  let assert Ok(Nil) = process.receive(ready, within: ask_support.event_wait_ms)
    as "the connection joined the registry"
  pid
}

const nexus = MapId(world_id: 426, instance: 0)

const ship = MapId(world_id: 3460, instance: 0)

fn started(world: World, map: MapId) -> MapProcess {
  let assert Ok(found) =
    maps.find_or_start(world.maps, map, deadline_ms: deadline())
    as "Maps started the map or found it running"
  found
}

/// A deadline a passing test never reaches.
fn deadline() -> Int {
  ask_support.monotonic_ms() + ask_support.event_wait_ms
}

/// What a join of the connection to the running map was answered with.
fn joined(found: MapProcess, id: Int) -> map.Outgoing {
  let #(_, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(
        found.subject,
        map.Join(connection: ConnectionId(id), character_id: 100 + id),
        reply,
      )
    })
  answer
}

pub fn the_first_find_for_a_map_starts_it_and_the_second_finds_the_same_run_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world(None)
  assert maps.find(world.maps, ship, incarnation: 1, call_ms: 1000)
    == Error(Nil)
    as "find never starts a map: no map is running"
  let first = started(world, ship)
  let second = started(world, ship)
  assert second == first
    as "the second find answers the process, subject and incarnation of the first: the map is not started twice"
  assert maps.find(
      world.maps,
      ship,
      incarnation: first.incarnation,
      call_ms: 1000,
    )
    == Ok(first)
    as "find with the incarnation of the run that is running answers it"
  assert maps.find(
      world.maps,
      ship,
      incarnation: first.incarnation + 1,
      call_ms: 1000,
    )
    == Error(Nil)
    as "another incarnation is another run: a watch on a run that ended ends at once"
  let other = started(world, nexus)
  assert other.pid != first.pid && other.incarnation != first.incarnation
    as "each map is a process of its own, and each start has its own incarnation"
  assert started(world, ship) == first
    as "starting another map left the first running"
}

pub fn concurrent_finds_for_one_map_start_it_once_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world(None)
  let results = process.new_subject()
  list.each([1, 2, 3, 4, 5, 6, 7, 8], fn(_) {
    process.spawn_unlinked(fn() {
      process.send(
        results,
        maps.find_or_start(world.maps, ship, deadline_ms: deadline()),
      )
    })
  })
  let found =
    list.map([1, 2, 3, 4, 5, 6, 7, 8], fn(_) {
      let assert Ok(Ok(found)) =
        process.receive(results, within: ask_support.event_wait_ms)
        as "each find was answered"
      found
    })
  assert list.unique(found) |> list.length == 1
    as "one actor serialises the finds, so two connections that enter a map at once never start it twice"
}

pub fn a_map_that_ended_is_started_again_with_a_new_incarnation_and_the_old_run_is_not_found_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world(None)
  let first = started(world, ship)
  let ended = process.monitor(first.pid)
  process.kill(first.pid)
  let _reason = ask_support.ended(ended)
  // Maps takes the end of the map from its monitor; the old run is not found
  // once it has.
  await_not_found(world:, map: ship, incarnation: first.incarnation)
  let again = started(world, ship)
  assert again.pid != first.pid && again.incarnation != first.incarnation
    as "the next find started the map again, empty, as another run"
  assert maps.find(
      world.maps,
      ship,
      incarnation: first.incarnation,
      call_ms: 1000,
    )
    == Error(Nil)
    as "a find with the old incarnation is an error: a player's connection that watches the old run learns it ended"
  assert maps.find(
      world.maps,
      ship,
      incarnation: again.incarnation,
      call_ms: 1000,
    )
    == Ok(again)
}

/// Waits until Maps no longer finds the run with the incarnation, which it
/// does within a moment of the map's end; the wait is bounded.
fn await_not_found(
  world world: World,
  map map: MapId,
  incarnation incarnation: Int,
) -> Nil {
  await_not_found_within(world:, map:, incarnation:, polls: 5000)
}

fn await_not_found_within(
  world world: World,
  map map: MapId,
  incarnation incarnation: Int,
  polls polls: Int,
) -> Nil {
  case maps.find(world.maps, map, incarnation:, call_ms: 1000) {
    Error(Nil) -> Nil
    Ok(_) ->
      case polls > 0 {
        True -> {
          process.sleep(1)
          await_not_found_within(world:, map:, incarnation:, polls: polls - 1)
        }
        False -> panic as "Maps still finds a map that ended"
      }
  }
}

pub fn an_ask_is_given_up_at_the_askers_deadline_and_maps_not_running_is_an_error_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world(None)
  assert maps.find_or_start(
      world.maps,
      ship,
      deadline_ms: ask_support.monotonic_ms() - 1,
    )
    == Error(Nil)
    as "a deadline that has passed leaves no time to wait for Maps' answer"
  let nobody = process.new_name("no_maps")
  assert maps.find_or_start(nobody, ship, deadline_ms: deadline()) == Error(Nil)
    as "Maps is not running: no process holds its name"
  assert maps.find(nobody, ship, incarnation: 1, call_ms: 1000) == Error(Nil)
}

pub fn an_ask_past_its_deadline_is_never_sent_to_maps_test() -> Nil {
  use <- owned_test.run(30_000)
  let stand_in = process.new_name("stand_in_maps")
  let assert Ok(Nil) = process.register(process.self(), stand_in)
    as "the test process holds the name Maps would"
  assert maps.find_or_start(
      stand_in,
      ship,
      deadline_ms: ask_support.monotonic_ms() - 1,
    )
    == Error(Nil)
  let anything =
    process.new_selector() |> process.select_other(fn(message) { message })
  assert process.selector_receive(anything, within: 0) == Error(Nil)
    as "the asker's deadline had passed before it sent, so Maps is never asked: the find would start a map nobody waits for"
}

pub fn a_map_gives_each_player_a_unit_id_and_never_gives_one_twice_after_a_leave_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world(None)
  let found = started(world, ship)
  let first_connection = connection(world, 1)
  assert joined(found, 1)
    == map.Joined(unit_id: 1, incarnation: found.incarnation)
    as "the first player of the map is unit 1, in the run Maps started"
  assert joined(found, 2)
    == map.Joined(unit_id: 2, incarnation: found.incarnation)
    as "the second joins as a connection that is not in the map's registry: its watch ends at once, and it is still a unit of its own"
  let ended = process.monitor(first_connection)
  process.kill(first_connection)
  let _reason = ask_support.ended(ended)
  // The next joiner is another connection: a rejoin by the killed one's id
  // would race the map's taking of its end, which comes from another sender
  // than this test's join. That the end removes the player is the rule's,
  // tested in map_test.
  let _next = connection(world, 4)
  assert joined(found, 4)
    == map.Joined(unit_id: 3, incarnation: found.incarnation)
    as "a player that joins after one has left is a new unit, never unit 1 again"
}

pub fn a_restart_of_maps_ends_every_map_and_the_map_supervisor_restarts_with_it_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world(None)
  let first = started(world, ship)
  let assert Ok(maps_pid) = process.named(world.maps) as "Maps is registered"
  let ended = process.monitor(first.pid)
  process.kill(maps_pid)
  let _reason = ask_support.ended(ended)
  let new_maps = ask_support.await_new_pid(world.maps, maps_pid, 5000)
  assert new_maps != maps_pid as "the supervisor restarted Maps"
  let again = started(world, ship)
  assert again.pid != first.pid && again.incarnation != first.incarnation
    as "rest_for_one: the map supervisor restarted with Maps, so every map ended, and a registry that lost its list never starts a second copy of a running map"
}

pub fn the_recording_of_a_map_run_is_named_by_its_world_instance_and_incarnation_and_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(30_000)
  use folder <- recording_support.in_folder
  let world = start_world(Some(folder))
  let found = started(world, ship)
  // Both joiners are connection ids no process holds, so each watch ends as
  // the map's next input, in its own mailbox order. A live connection killed
  // here would race the tree's stop: its end comes from another sender than
  // the stop, so the map may stop before it takes it.
  let _joined = joined(found, 2)
  let _joined = joined(found, 3)
  let _reason = ask_support.stop_tree(world.tree)
  let bytes = recording_support.recording_in(folder)
  assert simplifile.read_bits(
      folder
      <> "/genesis_prime.world_map.map-world-3460-instance-0-incarnation-"
      <> int.to_string(found.incarnation)
      <> ".recording",
    )
    == Ok(bytes)
    as "the file is named by the map's world, instance and incarnation, as the server names it"
  let assert Ok(#(header, records)) = rule_recording.read(bytes)
    as "the recording reads"
  assert header.rule == map.rule_name
  assert header.settings
    == map.Settings(map: ship, incarnation: found.incarnation)
    as "the header holds the map and the run the recording is of"
  let assert Ok(rule_recording.End(count:)) = list.last(records)
    as "the stop of the tree ended the recording"
  assert rule_recording.replay(
      bytes,
      step.Rule(
        name: map.rule_name,
        settings: header.settings,
        new: map.new,
        step: map.step,
      ),
      recording_support.types_digest(map.rule_name),
      None,
    )
    == Ok(count)
    as "every recorded step is the step the rule gives again: the first input, the two joins, the two watches' ends and the stop"
  assert count == 6
    as "Started, two Asked, each followed by the WatchEnded of its joiner's watch, and Stopping"
}
