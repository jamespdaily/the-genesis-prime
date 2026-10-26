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
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom
import gleam/erlang/process.{type Pid}
import gleam/int
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
  let #(settings, subtree, _names) = start_maps_with_names()
  #(settings, subtree)
}

/// The maps, started for worlds 7 and 8, with the names they were given.
fn start_maps_with_names() -> #(maps.Settings, Pid, maps.Names) {
  let settings =
    maps.Settings(
      registry: process.new_name("maps"),
      factory: process.new_name("maps_factory"),
      snapshot: map_support.start_snapshot(),
      heap_limits: map_support.no_limits(),
    )
  let names = maps.new_names(worlds: [7, 8])
  let assert Ok(started) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(maps.supervised(settings:, names:))
    |> static_supervisor.start
    as "the maps did not start"
  let assert [subtree] = supervisor_children.in_start_order(started.pid)
    as "the maps' subtree is one child"
  #(settings, subtree, names)
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
    |> static_supervisor.add(maps.supervised(
      settings:,
      names: maps.new_names(worlds: [9]),
    ))
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
  // does, so each wait that has its own 1000 ms adds up to 1600 ms. The 600 ms
  // is the time the registry's step takes, which is what the test measures, so
  // a timer sends the word to resume it and the process that suspended it
  // waits for that word. A process resumes only what it suspended itself.
  let suspended = process.new_subject()
  process.spawn(fn() {
    map_support.suspend(registry)
    let resume = process.new_subject()
    process.send(suspended, resume)
    let assert Ok(Nil) = process.receive(resume, event_wait_ms)
      as "the test told the registry to resume"
    map_support.resume(registry)
  })
  let assert Ok(resume) = process.receive(suspended, event_wait_ms)
    as "the registry was suspended"
  let _timer = process.send_after(resume, 600, Nil)
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

/// Waits until the process is down, which is at once for one that is.
fn went_down(pid: Pid) -> Bool {
  let monitor = process.monitor(pid)
  process.new_selector()
  |> process.select_specific_monitor(monitor, fn(_down) { True })
  |> process.selector_receive(within: event_wait_ms)
  == Ok(True)
}

/// The pid the name is registered to once it is not `old`. A restarted
/// process registers its name as it starts, and nothing announces that, so the
/// name is looked up until it names a new process, for at most `event_wait_ms`.
fn wait_for_a_new_process(
  name: process.Name(message),
  old: Pid,
) -> Result(Pid, Nil) {
  let expired = process.new_subject()
  let _timer = process.send_after(expired, event_wait_ms, Nil)
  look_for_a_new_process(name:, old:, expired:)
}

fn look_for_a_new_process(
  name name: process.Name(message),
  old old: Pid,
  expired expired: process.Subject(Nil),
) -> Result(Pid, Nil) {
  case process.named(name), process.receive(expired, 0) {
    Ok(pid), _ if pid != old -> Ok(pid)
    _, Error(Nil) -> look_for_a_new_process(name:, old:, expired:)
    _, Ok(Nil) -> Error(Nil)
  }
}

pub fn a_registry_that_starts_again_gives_every_world_the_names_it_had_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, _) = start_maps()
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered"
  let names_before = names_of(processes_of_the_only_map(settings))
  let assert Ok(registry) = process.named(settings.registry)
    as "the registry is registered under its name"
  let assert Ok(factory) = process.named(settings.factory)
    as "the factory supervisor is registered under its name"
  process.kill(registry)
  let assert Ok(_) = wait_for_a_new_process(settings.factory, factory)
    as "the maps' subtree started the registry and then the factory again: rest for one"
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 12)
    as "the next entry started the world's map again"
  assert names_of(processes_of_the_only_map(settings)) == names_before
    as "designing-processes: names are start arguments made once, so a registry that starts again makes no new atoms: the names are the ones the tree was started with"
}

/// A process that holds the name of a world's map, as a map that is going down
/// holds it until it is gone. It ends when it is sent the subject it reports.
fn holding_the_name_of_the_map(
  name: process.Name(world_map_process.Message),
) -> #(process.Subject(Nil), Pid) {
  let ready = process.new_subject()
  let holder =
    process.spawn(fn() {
      let assert Ok(Nil) = process.register(process.self(), name)
        as "the name of the map is free"
      let release = process.new_subject()
      process.send(ready, release)
      let assert Ok(Nil) = process.receive(release, 30_000)
        as "the test let the name go"
      Nil
    })
  let assert Ok(release) = process.receive(ready, event_wait_ms)
    as "the process holds the name"
  #(release, holder)
}

/// A map whose supervisor has ended, and a process that still holds the name
/// of the map's process, as the map would while it goes down. Returns the
/// settings, what lets the name go and the process that holds it.
fn with_the_name_of_an_ended_map_still_held() -> #(
  maps.Settings,
  process.Subject(Nil),
  Pid,
) {
  let #(settings, _, names) = start_maps_with_names()
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 11)
    as "the character entered"
  let assert Ok(name) = maps.map_name(names:, world_id: 7)
    as "world 7 has names"
  let old_map = the_map_process(settings)
  let assert Ok(factory) = process.named(settings.factory)
    as "the factory supervisor is registered under its name"
  let assert [map_subtree] = supervisor_children.in_start_order(factory)
    as "the world has one map subtree"
  process.kill(map_subtree)
  assert went_down(map_subtree) && went_down(old_map)
    as "the map's subtree and its process ended"
  let #(release, holder) = holding_the_name_of_the_map(name)
  #(settings, release, holder)
}

pub fn a_map_that_starts_while_the_old_one_still_holds_the_names_waits_for_the_old_one_to_end_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, release, _) = with_the_name_of_an_ended_map_still_held()
  let answered = process.new_subject()
  process.spawn(fn() {
    process.send(answered, enter(settings:, world_id: 7, character_id: 12))
  })
  assert process.receive(answered, 300) == Error(Nil)
    as "the registry waits for the old map to end instead of starting a map that cannot register its name"
  process.send(release, Nil)
  let assert Ok(Ok(unit)) = process.receive(answered, event_wait_ms)
    as "once the old one is down the next map started, within the entry's deadline"
  assert unit.id == 1 && unit.character_id == 12
    as "a map that is started again starts empty"
}

pub fn an_old_map_that_never_ends_leaves_the_entry_an_answer_at_its_deadline_and_the_registry_free_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, release, _) = with_the_name_of_an_ended_map_still_held()
  let started = clock.monotonic_milliseconds()
  let result =
    maps.enter(
      registry: settings.registry,
      world_id: 7,
      newcomer: map_support.newcomer(character_id: 12, x: 0.0),
      connection: process.new_subject(),
      within_ms: 600,
    )
  let elapsed = clock.monotonic_milliseconds() - started
  let assert Error(_) = result
    as "the old map did not end, so no map started: an answer and not a crash"
  assert elapsed >= 500 && elapsed < 1500
    as "designing-processes: the wait for the old map is under the entry's one deadline, not for ever and not given up at once"
  process.send(release, Nil)
  let assert Ok(unit) = enter(settings:, world_id: 7, character_id: 13)
    as "the registry is free again and starts the map once the old one is gone"
  assert unit.id == 1
}

/// Waits until the registry monitors the process, which it does as it starts
/// to wait for the process to end. Nothing announces that, so the process's
/// watchers are read until the registry is one, for at most `event_wait_ms`.
fn wait_for_the_registry_to_watch(
  registry registry: Pid,
  process process: Pid,
) -> Bool {
  wait_until_the_registry_watches(registry:, process:, watching: True)
}

/// Waits until the registry no longer monitors the process, which it stops
/// doing when no asker waits for the process to end any more, for at most
/// `event_wait_ms`.
fn wait_for_the_registry_to_stop_watching(
  registry registry: Pid,
  process process: Pid,
) -> Bool {
  wait_until_the_registry_watches(registry:, process:, watching: False)
}

fn wait_until_the_registry_watches(
  registry registry: Pid,
  process process: Pid,
  watching watching: Bool,
) -> Bool {
  let expired = process.new_subject()
  let _timer = process.send_after(expired, event_wait_ms, Nil)
  look_for_the_registry(registry:, process:, watching:, expired:)
}

fn look_for_the_registry(
  registry registry: Pid,
  process process: Pid,
  watching watching: Bool,
  expired expired: process.Subject(Nil),
) -> Bool {
  case
    list.contains(map_support.monitored_by(process), registry) == watching,
    process.receive(expired, 0)
  {
    True, _ -> True
    False, Error(Nil) ->
      look_for_the_registry(registry:, process:, watching:, expired:)
    False, Ok(Nil) -> False
  }
}

/// What a process that asked to enter world 7 and kept listening is asked
/// for: the messages that reached it after its entry was answered.
type Listening {
  Asked(reply: process.Subject(List(Bool)))
  Heard(carried_a_map: Bool)
}

/// Asks to enter world 7 as `asking_to_enter_world_7` does, in a process that
/// then keeps what else reaches it: a reply of the registry to an asker that
/// gave up and was answered, such as the map that started later. The answer
/// of the entry comes on the first subject; sending a subject on the second
/// gets, on it, whether each message that reached the process carried a map,
/// oldest first.
fn asking_to_enter_world_7_and_listening(
  settings settings: maps.Settings,
  character_id character_id: Int,
  within_ms within_ms: Int,
) -> #(
  process.Subject(Result(maps.Entered, maps.EnterError)),
  process.Subject(process.Subject(process.Subject(List(Bool)))),
) {
  let answered = process.new_subject()
  let listening = process.new_subject()
  process.spawn(fn() {
    process.send(
      answered,
      maps.enter(
        registry: settings.registry,
        world_id: 7,
        newcomer: map_support.newcomer(character_id:, x: 0.0),
        connection: process.new_subject(),
        within_ms:,
      ),
    )
    let asked = process.new_subject()
    process.send(listening, asked)
    let selector =
      process.new_selector()
      |> process.select_map(asked, Asked)
      |> process.select_other(fn(message) { Heard(carries_a_map(message)) })
    listen(selector:, heard: [])
  })
  #(answered, listening)
}

fn listen(
  selector selector: process.Selector(Listening),
  heard heard: List(Bool),
) -> Nil {
  case process.selector_receive_forever(selector) {
    Heard(carried_a_map:) -> listen(selector:, heard: [carried_a_map, ..heard])
    Asked(reply:) -> process.send(reply, list.reverse(heard))
  }
}

/// What reached a process that `asking_to_enter_world_7_and_listening`
/// started, after its entry was answered: whether each message carried a map.
fn what_reached(
  listening listening: process.Subject(
    process.Subject(process.Subject(List(Bool))),
  ),
) -> List(Bool) {
  let assert Ok(asked) = process.receive(listening, event_wait_ms)
    as "the asker finished its entry and listens"
  let reply = process.new_subject()
  process.send(asked, reply)
  let assert Ok(heard) = process.receive(reply, event_wait_ms)
    as "the asker reported what reached it"
  heard
}

/// Whether a message is the registry's answer to an asker with a map: a
/// message to a subject is the subject's tag and the registry's `Found`, which
/// is `Ok` for a map.
fn carries_a_map(message: Dynamic) -> Bool {
  decode.run(message, decode.at([1, 0], atom.decoder()))
  == Ok(atom.create("ok"))
}

/// Asks to enter world 7 from a process of its own, with `within_ms`
/// milliseconds to give up in; the answer comes on the subject.
fn asking_to_enter_world_7(
  settings settings: maps.Settings,
  character_id character_id: Int,
  within_ms within_ms: Int,
) -> process.Subject(Result(maps.Entered, maps.EnterError)) {
  let answered = process.new_subject()
  process.spawn(fn() {
    process.send(
      answered,
      maps.enter(
        registry: settings.registry,
        world_id: 7,
        newcomer: map_support.newcomer(character_id:, x: 0.0),
        connection: process.new_subject(),
        within_ms:,
      ),
    )
  })
  answered
}

pub fn an_entry_into_a_running_world_does_not_wait_behind_the_old_map_of_another_world_test() -> Nil {
  use <- owned_test.run(30_000)
  // World 7's map ended and a process still holds its name, so the registry
  // waits for that process to end before it starts world 7's map again.
  let #(settings, release, holder) = with_the_name_of_an_ended_map_still_held()
  let assert Ok(_) = enter(settings:, world_id: 8, character_id: 21)
    as "world 8 has a running map"
  let assert Ok(registry) = process.named(settings.registry)
    as "the registry is registered under its name"
  let _waiting =
    asking_to_enter_world_7(settings:, character_id: 12, within_ms: 5000)
  assert wait_for_the_registry_to_watch(registry:, process: holder)
    as "the registry waits for the old map of world 7 to end"
  let started = clock.monotonic_milliseconds()
  let result =
    maps.enter(
      registry: settings.registry,
      world_id: 8,
      newcomer: map_support.newcomer(character_id: 22, x: 0.0),
      connection: process.new_subject(),
      within_ms: 1000,
    )
  let elapsed = clock.monotonic_milliseconds() - started
  process.send(release, Nil)
  let assert Ok(entered) = result
    as "designing-processes: one process owns the registry and every world asks it, so a wait for one world's old map must not hold the others: the entry into world 8 is answered while the registry waits"
  assert entered.unit.id == 2
    as "world 8's running map gave the second unit its id"
  assert elapsed < 500
    as "the entry is answered at once, not after the other world's wait"
}

pub fn the_askers_of_a_world_whose_old_map_is_ending_each_get_their_own_deadline_and_the_rest_the_new_map_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, release, holder) = with_the_name_of_an_ended_map_still_held()
  let assert Ok(registry) = process.named(settings.registry)
    as "the registry is registered under its name"
  let #(impatient, listening) =
    asking_to_enter_world_7_and_listening(
      settings:,
      character_id: 12,
      within_ms: 300,
    )
  let patient =
    asking_to_enter_world_7(settings:, character_id: 13, within_ms: 5000)
  let also_patient =
    asking_to_enter_world_7(settings:, character_id: 14, within_ms: 5000)
  assert wait_for_the_registry_to_watch(registry:, process: holder)
    as "the registry waits for the old map of world 7 to end"
  let assert Ok(Error(_)) = process.receive(impatient, 2000)
    as "an asker whose deadline passes is answered at its own deadline, not at the others'"
  process.send(release, Nil)
  let assert Ok(Ok(first)) = process.receive(patient, event_wait_ms)
    as "an asker with time left gets the map once the old one is down"
  let assert Ok(Ok(second)) = process.receive(also_patient, event_wait_ms)
    as "so does the other"
  assert list.sort([first.unit.id, second.unit.id], int.compare) == [1, 2]
    as "both joined the one map that was started, a map that starts again starts empty"
  // The registry answers a later entry after it has answered every asker it
  // still held, so the map's answer to the one that gave up would have been
  // sent by now.
  let assert Ok(_) = enter(settings:, world_id: 7, character_id: 15)
    as "a later asker for the same world is served"
  assert !list.contains(what_reached(listening:), True)
    as "designing-processes: an asker that gave up is dropped from the wait, so the map that starts later is not answered to it"
}

pub fn an_asker_that_gives_up_while_it_is_the_only_one_ends_the_registrys_wait_and_is_not_answered_with_the_map_test() -> Nil {
  use <- owned_test.run(30_000)
  let #(settings, release, holder) = with_the_name_of_an_ended_map_still_held()
  let assert Ok(registry) = process.named(settings.registry)
    as "the registry is registered under its name"
  let #(only, listening) =
    asking_to_enter_world_7_and_listening(
      settings:,
      character_id: 12,
      within_ms: 300,
    )
  assert wait_for_the_registry_to_watch(registry:, process: holder)
    as "the registry waits for the old map of world 7 to end"
  let assert Ok(Error(_)) = process.receive(only, 2000)
    as "the asker is answered at its deadline"
  assert wait_for_the_registry_to_stop_watching(registry:, process: holder)
    as "designing-processes: the registry dropped the asker that gave up, and with no asker left stopped waiting for the old map"
  process.send(release, Nil)
  let assert Ok(unit) = enter(settings:, world_id: 7, character_id: 13)
    as "a later asker for the same world is served by a new map"
  assert unit.id == 1
    as "the map that started is empty, so the asker that gave up joined nothing"
  assert !list.contains(what_reached(listening:), True)
    as "the map that started is not answered to the asker that gave up"
}
