//// Maps and the maps it starts (`genesis_prime/world_map/registry`), started under
//// a world supervisor as the server's tree starts them. Expected values come
//// from these places.
//// - The doc comment of `genesis_prime/world_map/registry`: the first find for
////   a map starts it, the next finds the same run; each start has an
////   incarnation, unique in the node's life; `find` answers only the run with
////   the incarnation it is given and never starts a map; a map that ended is
////   started again, with a new incarnation, by the next `find_or_start`; the
////   deadline of a find is the asker's, and Maps not running, or a start that
////   fails, is `Error(Nil)` for `find_or_start`; `find` says `NotFound` for a
////   map that is not running as that run (or Maps not running) and `NoReply`
////   for a Maps that gives no answer by the deadline, and `ask_run` sends only
////   to the run `find` finds: a map not running is `Error(Nil)`, and a Maps
////   that gives no answer is `NoReplyInTime` and never `NotRunning`.
//// - The map's doc comment (`genesis_prime/world_map/map`): a player's
////   connection is watched, and its end removes the player.
//// - OTP's supervisor: a child exits with `shutdown` when told to, and a
////   permanent child is restarted when it crashes.
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import character_support
import character_tables
import event_wait
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/server
import genesis_prime/service
import genesis_prime/step.{type Address, Connection, ConnectionId}
import genesis_prime/store.{type Character}
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId, MapId}
import genesis_prime/world_map/registry.{type MapProcess} as world_map_registry
import gleam/erlang/process.{type Name, type Pid}
import gleam/list
import gleam/otp/static_supervisor as supervisor
import owned_test
import place_support
import spawn_support

/// The world supervisor as the server builds it, with the names it was built
/// with, a registry the maps find their players' connections in, and, when the
/// test records, the folder of the maps' recordings.
type World {
  World(
    tree: Pid,
    maps: Name(world_map_registry.Message),
    map_supervisor: Name(world_map_registry.MapSupervisor),
    registry: Registry(Nil),
  )
}

fn start_world() -> World {
  let maps_name = process.new_name("maps")
  let map_supervisor_name = process.new_name("map_supervisor")
  let scope = registry.new()
  let world =
    server.World(
      maps: maps_name,
      map_supervisor: map_supervisor_name,
      maps_call_ms: 1000,
      map_shutdown_ms: 1000,
      creatures: creature_registry.new(),
      creature_supervisor: process.new_name("creature_supervisor"),
      creature_shutdown_ms: 1000,
      creature_restart_ms: 60_000,
      idle_stop_ms: 60_000,
      sweep_ms: 10_000,
      spawns: spawn_support.key_without_spawns(),
    )
  let tree =
    supervisor.new(supervisor.RestForOne)
    |> supervisor.restart_tolerance(intensity: 3, period: 10)
    |> supervisor.add(registry.supervised(scope))
  let assert Ok(started) =
    server.add_world(
      tree:,
      world:,
      realm_id: 1,
      tables: character_tables.shared(),
      reach: service.watch_only(locate: locate(scope, _)),
      to_connection: fn(_connection, _news) { Error(Nil) },
    )
    |> supervisor.start
    as "the world tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  World(
    tree: started.pid,
    maps: maps_name,
    map_supervisor: map_supervisor_name,
    registry: scope,
  )
}

fn locate(scope: Registry(Nil), address: Address) -> Result(Pid, Nil) {
  case address {
    Connection(connection:) -> registry.find(scope, connection)
    step.Sessions
    | step.HandOff
    | step.Store
    | step.Maps
    | step.Map(..)
    | step.Creature(..)
    | step.CharacterNamed(..)
    | step.ZoneChannel(..) -> Error(Nil)
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
    world_map_registry.find_or_start(world.maps, map, deadline_ms: deadline())
    as "Maps started the map or found it running"
  found
}

/// A deadline a passing test never reaches.
fn deadline() -> Int {
  ask_support.monotonic_ms() + ask_support.event_wait_ms
}

/// The join of the connection as `character`, at the live character's place.
fn join_of(id id: Int, character character: Character) -> map.Message {
  map.Join(
    connection: ConnectionId(id),
    character:,
    place: place_support.live_character_place(),
  )
}

/// What a join of the connection, as `character`, to the running map was
/// answered with.
fn joined_as(
  found found: MapProcess,
  id id: Int,
  character character: Character,
) -> map.Outgoing {
  let #(_, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(found.subject, join_of(id:, character:), reply)
    })
  answer
}

/// The unit id and the incarnation a join of the connection, as the character
/// 100 more than its id, to the running map was answered with.
fn joined(found: MapProcess, id: Int) -> #(Int, Int) {
  let assert map.Joined(unit:, incarnation:, ..) =
    joined_as(
      found:,
      id:,
      character: character_support.character(number: 100 + id),
    )
  #(unit.unit_id, incarnation)
}

pub fn the_first_find_for_a_map_starts_it_and_the_second_finds_the_same_run_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world()
  assert world_map_registry.find(
      world.maps,
      ship,
      incarnation: 1,
      deadline_ms: deadline(),
    )
    == Error(world_map_registry.NotFound)
    as "find never starts a map: no map is running"
  let first = started(world, ship)
  let second = started(world, ship)
  assert second == first
    as "the second find answers the process, subject and incarnation of the first: the map is not started twice"
  assert world_map_registry.find(
      world.maps,
      ship,
      incarnation: first.incarnation,
      deadline_ms: deadline(),
    )
    == Ok(first)
    as "find with the incarnation of the run that is running answers it"
  assert world_map_registry.find(
      world.maps,
      ship,
      incarnation: first.incarnation + 1,
      deadline_ms: deadline(),
    )
    == Error(world_map_registry.NotFound)
    as "another incarnation is another run: a watch on a run that ended ends at once"
  let other = started(world, nexus)
  assert other.pid != first.pid && other.incarnation != first.incarnation
    as "each map is a process of its own, and each start has its own incarnation"
  assert started(world, ship) == first
    as "starting another map left the first running"
}

pub fn concurrent_finds_for_one_map_start_it_once_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world()
  let results = process.new_subject()
  list.each([1, 2, 3, 4, 5, 6, 7, 8], fn(_) {
    process.spawn_unlinked(fn() {
      process.send(
        results,
        world_map_registry.find_or_start(
          world.maps,
          ship,
          deadline_ms: deadline(),
        ),
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
  let world = start_world()
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
  assert world_map_registry.find(
      world.maps,
      ship,
      incarnation: first.incarnation,
      deadline_ms: deadline(),
    )
    == Error(world_map_registry.NotFound)
    as "a find with the old incarnation is an error: a player's connection that watches the old run learns it ended"
  assert world_map_registry.find(
      world.maps,
      ship,
      incarnation: again.incarnation,
      deadline_ms: deadline(),
    )
    == Ok(again)
}

pub fn a_map_that_ended_keeps_no_player_so_the_same_connection_joins_the_new_run_as_unit_1_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world()
  let first = started(world, ship)
  let _connection = connection(world, 1)
  let assert map.Joined(unit: before, ..) =
    joined_as(
      found: first,
      id: 1,
      character: character_support.character(number: 101),
    )
  assert before.unit_id == 1 && before.character_id == 101
    as "the connection is unit 1 of the first run, as character 101"
  let ended = process.monitor(first.pid)
  process.kill(first.pid)
  let _reason = ask_support.ended(ended)
  await_not_found(world:, map: ship, incarnation: first.incarnation)
  let again = started(world, ship)
  let assert map.Joined(unit: after, incarnation:, ..) =
    joined_as(
      found: again,
      id: 1,
      character: character_support.character(number: 900),
    )
  assert after.unit_id == 1 && after.character_id == 900
    as "the new run holds no player of the old one: the same connection joins it as a new player, unit 1, built from the new Join, where a kept player would answer the old unit of character 101"
  assert incarnation == again.incarnation
}

/// Waits until Maps no longer finds the run with the incarnation, which it
/// does within a moment of the map's end; the wait is bounded.
fn await_not_found(
  world world: World,
  map map: MapId,
  incarnation incarnation: Int,
) -> Nil {
  event_wait.until("Maps stops finding a map that ended", fn() {
    world_map_registry.find(
      world.maps,
      map,
      incarnation:,
      deadline_ms: deadline(),
    )
    == Error(world_map_registry.NotFound)
  })
}

pub fn an_ask_is_given_up_at_the_askers_deadline_and_maps_not_running_is_an_error_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world()
  assert world_map_registry.find_or_start(
      world.maps,
      ship,
      deadline_ms: ask_support.monotonic_ms() - 1,
    )
    == Error(Nil)
    as "a deadline that has passed leaves no time to wait for Maps' answer"
  let nobody = process.new_name("no_maps")
  assert world_map_registry.find_or_start(nobody, ship, deadline_ms: deadline())
    == Error(Nil)
    as "Maps is not running: no process holds its name"
  assert world_map_registry.find(
      nobody,
      ship,
      incarnation: 1,
      deadline_ms: deadline(),
    )
    == Error(world_map_registry.NotFound)
}

pub fn an_ask_past_its_deadline_is_never_sent_to_maps_test() -> Nil {
  use <- owned_test.run(30_000)
  let stand_in = process.new_name("stand_in_maps")
  let assert Ok(Nil) = process.register(process.self(), stand_in)
    as "the test process holds the name Maps would"
  assert world_map_registry.find_or_start(
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
  let world = start_world()
  let found = started(world, ship)
  let first_connection = connection(world, 1)
  assert joined(found, 1) == #(1, found.incarnation)
    as "the first player of the map is unit 1, in the run Maps started"
  assert joined(found, 2) == #(2, found.incarnation)
    as "the second joins as a connection that is not in the map's registry: its watch ends at once, and it is still a unit of its own"
  let ended = process.monitor(first_connection)
  process.kill(first_connection)
  let _reason = ask_support.ended(ended)
  // The next joiner is another connection: a rejoin by the killed one's id
  // would race the map's taking of its end, which comes from another sender
  // than this test's join. That the end removes the player is the rule's,
  // tested in map_test.
  let _next = connection(world, 4)
  assert joined(found, 4) == #(3, found.incarnation)
    as "a player that joins after one has left is a new unit, never unit 1 again"
}

pub fn a_restart_of_maps_ends_every_map_and_the_map_supervisor_restarts_with_it_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world()
  let first = started(world, ship)
  let assert Ok(maps_pid) = process.named(world.maps) as "Maps is registered"
  let assert Ok(supervisor_pid) = process.named(world.map_supervisor)
    as "the map supervisor is registered"
  let ended = process.monitor(first.pid)
  process.kill(maps_pid)
  let _reason = ask_support.ended(ended)
  let new_maps =
    ask_support.await_new_pid(
      name: world.maps,
      not: maps_pid,
      within_ms: ask_support.event_wait_ms,
    )
  assert new_maps != maps_pid as "the supervisor restarted Maps"
  // Under rest_for_one the map supervisor restarts after Maps, so a request
  // that reaches the new Maps before the new map supervisor is answered
  // `Error(Nil)`, since the start fails: a handled gap, so the test asks only
  // once the map supervisor runs again.
  let new_supervisor =
    ask_support.await_new_pid(
      name: world.map_supervisor,
      not: supervisor_pid,
      within_ms: ask_support.event_wait_ms,
    )
  assert new_supervisor != supervisor_pid
    as "the supervisor restarted the map supervisor"
  let again = started(world, ship)
  assert again.pid != first.pid && again.incarnation != first.incarnation
    as "rest_for_one: the map supervisor restarted with Maps, so every map ended, and a registry that lost its list never starts a second copy of a running map"
}

// ---- the typed find and the ask of a run ----

/// The join of the connection as the character 100 more than its id, as
/// `joined` sends it.
fn join_message(id: Int) -> map.Message {
  join_of(id:, character: character_support.character(number: 100 + id))
}

pub fn a_find_that_maps_does_not_answer_by_its_deadline_is_no_reply_and_not_not_found_test() -> Nil {
  use <- owned_test.run(30_000)
  let stand_in = process.new_name("stand_in_maps")
  let assert Ok(Nil) = process.register(process.self(), stand_in)
    as "the test process holds the name Maps would and never answers"
  assert world_map_registry.find(
      stand_in,
      ship,
      incarnation: 1,
      deadline_ms: ask_support.monotonic_ms() + 50,
    )
    == Error(world_map_registry.NoReply)
    as "Maps was asked and gave no answer: a live map may still hold the player, so the find does not say the map is not running"
  assert world_map_registry.find(
      stand_in,
      ship,
      incarnation: 1,
      deadline_ms: ask_support.monotonic_ms() - 1,
    )
    == Error(world_map_registry.NoReply)
    as "a deadline that has passed leaves no time to ask, and says nothing about the map"
}

pub fn an_ask_of_a_run_that_is_not_the_running_one_or_of_a_map_not_running_is_not_running_and_starts_no_map_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world()
  assert world_map_registry.ask_run(
      world.maps,
      ship,
      incarnation: 1,
      message: join_message(7),
      deadline_ms: deadline(),
      reply: fn(_) { Nil },
    )
    == Error(Nil)
    as "no map is running: the asker's shell gives its rule NotRunning"
  assert world_map_registry.find(
      world.maps,
      ship,
      incarnation: 1,
      deadline_ms: deadline(),
    )
    == Error(world_map_registry.NotFound)
    as "the ask started no map, as an ask of find_or_start would"
  let first = started(world, ship)
  assert world_map_registry.ask_run(
      world.maps,
      ship,
      incarnation: first.incarnation + 1,
      message: join_message(7),
      deadline_ms: deadline(),
      reply: fn(_) { Nil },
    )
    == Error(Nil)
    as "another incarnation is another run: the player the asker had is not in the running one"
  assert joined(first, 7) == #(1, first.incarnation)
    as "the refused ask's join never reached the running map: the next join is its first unit"
  let nobody = process.new_name("no_maps")
  assert world_map_registry.ask_run(
      nobody,
      ship,
      incarnation: 1,
      message: join_message(7),
      deadline_ms: deadline(),
      reply: fn(_) { Nil },
    )
    == Error(Nil)
    as "Maps is not running, so no map is"
}

pub fn an_ask_of_the_running_run_reaches_it_and_its_answer_goes_to_the_reply_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = start_world()
  let first = started(world, ship)
  let #(sent, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      world_map_registry.ask_run(
        world.maps,
        ship,
        incarnation: first.incarnation,
        message: join_message(3),
        deadline_ms: deadline(),
        reply:,
      )
    })
  assert sent == service.ToService(first.pid)
    as "the ask went to the run it names, which the asker watches"
  let assert map.Joined(unit:, incarnation:, ..) = answer
  assert unit.unit_id == 1 && incarnation == first.incarnation
}

pub fn an_ask_of_a_run_when_maps_does_not_answer_in_time_is_sent_nowhere_and_left_to_time_out_never_not_running_test() -> Nil {
  use <- owned_test.run(30_000)
  let stand_in = process.new_name("stand_in_maps")
  let assert Ok(Nil) = process.register(process.self(), stand_in)
    as "the test process holds the name Maps would and never answers"
  assert world_map_registry.ask_run(
      stand_in,
      ship,
      incarnation: 1,
      message: join_message(7),
      deadline_ms: ask_support.monotonic_ms() + 50,
      reply: fn(_) { Nil },
    )
    == Ok(service.NoReplyInTime)
    as "Maps gave no answer, so the ask is not NotRunning, which would let a live map keep a stale unit: the directory says so, and the shell gives its rule NoAnswerInTime"
}
