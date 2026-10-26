//// The maps of the game: one map for each world that has a player, started when
//// the first character of the world enters. The expected values come from the
//// step's plan (a map process started for a character's world), the supervision
//// choice (a map is one subtree, rest for one, 3 restarts in 5 seconds, and a map
//// subtree is started again when it ends) and the designing-processes skill
//// (one world can have many maps; a request carries a deadline).

import genesis_prime/connection/clock
import genesis_prime/map/maps.{MapNotStarted, MapRefused, RegistryNotAnswering}
import genesis_prime/map/unit.{type PlayerUnit}
import genesis_prime/map/world_map.{CharacterAlreadyOnMap}
import genesis_prime/map/world_map_process.{NotAnswering, Refused}
import genesis_prime/telemetry/snapshot
import gleam/dict
import gleam/erlang/process.{type Pid}
import gleam/list
import gleam/otp/static_supervisor
import gleam/result
import log_capture.{Fields}
import map_support
import owned_test
import supervisor_children
import supervisor_flags

const event_wait_ms = 5000

fn start_maps() -> #(maps.Settings, Pid) {
  let settings =
    maps.Settings(
      registry: process.new_name("maps"),
      factory: process.new_name("maps_factory"),
      snapshot: map_support.start_snapshot(),
      heap_limits: map_support.no_limits(),
    )
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(maps.supervised(settings))
    |> static_supervisor.start
    as "the maps did not start"
  let assert [subtree] = supervisor_children.in_start_order(started.pid)
    as "the maps' subtree is one child"
  #(settings, subtree)
}

fn entered(
  settings settings: maps.Settings,
  world_id world_id: Int,
  character_id character_id: Int,
) -> Result(maps.Entered, maps.EnterError) {
  maps.enter(
    registry: settings.registry,
    world_id:,
    newcomer: map_support.newcomer(character_id:, x: 0.0),
    connection: process.new_subject(),
    within_ms: event_wait_ms,
  )
}

fn enter(
  settings settings: maps.Settings,
  world_id world_id: Int,
  character_id character_id: Int,
) -> Result(PlayerUnit, maps.EnterError) {
  entered(settings:, world_id:, character_id:)
  |> result.map(fn(entered) { entered.unit })
}

pub fn a_character_entering_a_world_with_no_map_starts_the_map_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(unit) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered"
  assert unit.id == 1 && unit.character_id == 11
    as "the world's first map gives its first unit the id 1"
}

pub fn characters_entering_the_same_world_share_its_map_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(first) = enter(settings:, world_id: 7, character_id: 11)
    as "the first character entered"
  let assert Ok(second) = enter(settings:, world_id: 7, character_id: 12)
    as "the second character entered"
  assert first.id == 1 && second.id == 2
    as "one map gave both units their ids, in order"
}

pub fn each_world_has_a_map_of_its_own_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(in_seven) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered world 7"
  let assert Ok(in_eight) = enter(settings:, world_id: 8, character_id: 12)
    as "the character entered world 8"
  assert in_seven.id == 1 && in_eight.id == 1
    as "designing-processes: one world can have many maps; each map gives its own unit ids"
}

pub fn a_character_that_is_on_a_map_cannot_enter_it_again_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(first) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered"
  assert enter(settings:, world_id: 7, character_id: 11)
    == Error(MapRefused(Refused(CharacterAlreadyOnMap(unit_id: first.id))))
    as "the map refuses a second unit of one character"
}

pub fn a_map_that_ended_is_started_again_by_the_next_entry_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered"
  let assert Ok(factory) = process.named(settings.factory)
    as "the factory supervisor is registered under its name"
  let assert [map_subtree] = supervisor_children.in_start_order(factory)
    as "the world has one map subtree"
  let monitor = process.monitor(map_subtree)
  process.kill(map_subtree)
  let assert Ok(Nil) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(_down) { Nil })
    |> process.selector_receive(within: event_wait_ms)
    as "the map's subtree did not end"
  let assert Ok(unit) = enter(settings:, world_id: 7, character_id: 12)
    as "the next entry started the map again"
  assert unit.id == 1
    as "a map that is started again starts empty, so its first unit has the id 1"
}

pub fn entering_when_no_registry_runs_is_an_error_not_a_crash_test() -> Nil {
  use <- owned_test.run(30_000)
  let settings =
    maps.Settings(
      registry: process.new_name("no_maps"),
      factory: process.new_name("no_maps_factory"),
      snapshot: process.new_name("no_snapshot"),
      heap_limits: map_support.no_limits(),
    )
  assert enter(settings:, world_id: 7, character_id: 11)
    == Error(RegistryNotAnswering)
    as "designing-processes: a request to a process that is away is an error the asker handles"
}

pub fn the_maps_subtree_starts_the_registry_before_the_factory_rest_for_one_3_in_5_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, subtree) = start_maps()
  let assert Ok(registry) = process.named(settings.registry)
    as "the registry is registered under its name"
  let assert Ok(factory) = process.named(settings.factory)
    as "the factory is registered under its name"
  assert supervisor_children.in_start_order(subtree) == [registry, factory]
    as "the registry starts first, so a registry that is rebuilt stops every map no registry remembers"
  assert supervisor_flags.read(subtree)
    == supervisor_flags.Flags(
      strategy: static_supervisor.RestForOne,
      intensity: 3,
      period: 5,
    )
    as "#34: a service subtree states its restart limit; rest for one so the maps follow the registry"
  assert supervisor_children.in_start_order(factory) == []
    as "no map runs until a character enters a world"
}

pub fn the_map_of_a_world_registers_with_the_snapshot_under_its_world_test() -> Nil {
  use <- owned_test.run(30_000)
  let capture = log_capture.start()
  let snapshot_name = process.new_name("snapshot_of_the_maps_world")
  let assert Ok(snapshot_started) =
    snapshot.start(snapshot.Settings(
      name: snapshot_name,
      interval_milliseconds: 50,
    ))
    as "the snapshot process did not start"
  let settings =
    maps.Settings(
      registry: process.new_name("maps_for_snapshot"),
      factory: process.new_name("maps_factory_for_snapshot"),
      snapshot: snapshot_name,
      heap_limits: map_support.no_limits(),
    )
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(maps.supervised(settings))
    |> static_supervisor.start
    as "the maps did not start"
  let assert Ok(_) = enter(settings:, world_id: 9, character_id: 11)
    as "the character entered"
  let assert Ok(_) =
    next_line_with(
      capture:,
      snapshot: snapshot_started.pid,
      key: "map_9_largest_queue",
    )
    as "#44: a snapshot line after the map started reports the map of world 9"
  Nil
}

fn next_line_with(
  capture capture: log_capture.Capture,
  snapshot pid: Pid,
  key key: String,
) -> Result(log_capture.Event, Nil) {
  case log_capture.next_from(capture, from: pid, within: event_wait_ms) {
    Ok(line) ->
      case dict.get(line.metadata, "numbers") {
        Ok(Fields(numbers)) ->
          case dict.has_key(numbers, key) {
            True -> Ok(line)
            False -> next_line_with(capture:, snapshot: pid, key:)
          }
        _ -> next_line_with(capture:, snapshot: pid, key:)
      }
    Error(Nil) -> Error(Nil)
  }
}

/// The processes of the only map the factory runs: its senders, then the map
/// process, as the map's supervisor started them.
fn processes_of_the_only_map(settings: maps.Settings) -> List(Pid) {
  let assert Ok(factory) = process.named(settings.factory)
    as "the factory supervisor is registered under its name"
  let assert [map_subtree] = supervisor_children.in_start_order(factory)
    as "the world has one map subtree"
  supervisor_children.in_start_order(map_subtree)
}

fn the_map_process(settings: maps.Settings) -> Pid {
  let assert Ok(map) = list.last(processes_of_the_only_map(settings))
    as "a map's supervisor runs the map process after its senders"
  map
}

fn names_of(pids: List(Pid)) -> List(String) {
  list.map(pids, fn(pid) {
    let assert Ok(name) = map_support.registered_name(pid)
      as "a process of a map is registered under a name"
    name
  })
}

pub fn a_character_that_entered_is_given_the_map_process_that_holds_its_unit_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(entered) = entered(settings:, world_id: 7, character_id: 11)
    as "the character entered"
  assert entered.map == the_map_process(settings)
    as "the connection watches this process: a map that starts again is empty"
}

pub fn a_map_whose_name_is_not_registered_is_no_answer_and_not_a_crash_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered"
  // A map that is between two lives has no process under its name, while the
  // registry still holds it because the map's supervisor runs.
  map_support.unregister_name(the_map_process(settings))
  assert entered(settings:, world_id: 7, character_id: 12)
    == Error(MapRefused(NotAnswering))
    as "designing-processes: a request to a process that is away is an answer the asker handles, not a crash of the asker, which sending to an unregistered name would be"
}

pub fn a_factory_that_is_not_registered_is_a_map_that_could_not_start_and_the_registry_goes_on_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(registry) = process.named(settings.registry)
    as "the registry is registered under its name"
  let assert Ok(factory) = process.named(settings.factory)
    as "the factory supervisor is registered under its name"
  map_support.unregister_name(factory)
  let assert Error(MapNotStarted(_)) =
    entered(settings:, world_id: 7, character_id: 11)
    as "a factory that is away is a map that could not start"
  assert process.is_alive(registry)
    && process.named(settings.registry) == Ok(registry)
    as "the registry is not harmed by a start it could not make"
}

pub fn a_map_started_again_reuses_the_names_of_its_processes_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered"
  let names_before = names_of(processes_of_the_only_map(settings))
  let assert Ok(factory) = process.named(settings.factory)
    as "the factory supervisor is registered under its name"
  let assert [map_subtree] = supervisor_children.in_start_order(factory)
    as "the world has one map subtree"
  let monitor = process.monitor(map_subtree)
  process.kill(map_subtree)
  let assert Ok(Nil) =
    process.new_selector()
    |> process.select_specific_monitor(monitor, fn(_down) { Nil })
    |> process.selector_receive(within: event_wait_ms)
    as "the map's subtree did not end"
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 12)
    as "the next entry started the map again"
  assert names_of(processes_of_the_only_map(settings)) == names_before
    as "designing-processes: process names are start arguments made once; each name makes an atom the runtime never frees, so a world's names are made once and a map that starts again takes them. The atom count of the whole runtime is no measure here, because tests that run beside this one make atoms too"
}

pub fn the_maps_of_two_worlds_have_names_of_their_own_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered world 7"
  let in_seven = names_of(processes_of_the_only_map(settings))
  let assert Ok(factory) = process.named(settings.factory)
    as "the factory supervisor is registered under its name"
  let assert Ok(_) = enter(settings:, world_id: 8, character_id: 12)
    as "the character entered world 8"
  let assert [_, _] = supervisor_children.in_start_order(factory)
    as "two worlds have two maps"
  let all =
    list.flat_map(supervisor_children.in_start_order(factory), fn(subtree) {
      names_of(supervisor_children.in_start_order(subtree))
    })
  assert list.length(list.unique(all)) == list.length(all)
    && list.all(in_seven, fn(name) { list.contains(all, name) })
    as "two maps that run at once cannot share a name"
}

pub fn entering_gives_up_at_one_deadline_not_at_one_wait_for_each_step_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered, so the world has a map"
  let assert Ok(registry) = process.named(settings.registry)
    as "the registry is registered under its name"
  let map = the_map_process(settings)
  map_support.suspend(map)
  // The registry answers after 600 ms of the 1000 the entry has; the map never
  // does, so each wait that has its own 1000 ms adds up to 1600 ms. A process
  // resumes only what it suspended itself.
  let suspended = process.new_subject()
  process.spawn(fn() {
    map_support.suspend(registry)
    process.send(suspended, Nil)
    process.sleep(600)
    map_support.resume(registry)
  })
  let assert Ok(Nil) = process.receive(suspended, event_wait_ms)
    as "the registry was suspended"
  let started = clock.monotonic_milliseconds()
  let result =
    maps.enter(
      registry: settings.registry,
      world_id: 7,
      newcomer: map_support.newcomer(character_id: 12, x: 0.0),
      connection: process.new_subject(),
      within_ms: 1000,
    )
  let elapsed = clock.monotonic_milliseconds() - started
  map_support.resume(map)
  assert result == Error(MapRefused(NotAnswering))
    as "the map did not answer in time"
  assert elapsed < 1400
    as "designing-processes: a connection waits at most the one deadline it was given for the registry and the map together; each step with its own wait would hold it for 1600 ms"
}
