//// The maps of the game: one map for each world that has a player on it,
//// started when the first character of the world enters and kept for the
//// next. A character enters a world through `enter`, which finds the world's
//// map, or starts it, and joins the character's unit to it.
////
//// The registry process holds which world has which map, and monitors each map
//// it started, so a map that ended is forgotten and started again on the next
//// entry. It only finds a world's map and answers with it: the character then
//// joins the map itself, so a join never holds the registry. The maps
//// themselves are children of a factory supervisor, each one map supervisor
//// (`world_map_process.start`), temporary: a map whose restarts are used up is
//// not started again by its supervisor but by the next entry. The registry
//// starts first and the factory after it, rest for one, so a registry that is
//// rebuilt stops every map, which no registry remembers.

import genesis_prime/connection/clock
import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/heap_limit.{type HeapLimits}
import genesis_prime/map/sender
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/map/world_map_process
import genesis_prime/telemetry/log
import genesis_prime/telemetry/snapshot
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Monitor, type Name, type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision.{type ChildSpecification}
import gleam/result

/// How many restarts the maps' subtree allows in `restart_period_seconds`: the
/// service subtrees' 3 in 5 seconds.
const restart_intensity = 3

/// The period of the subtree's restart limit, in seconds.
const restart_period_seconds = 5

/// How long the registry has to stop, in milliseconds: it saves nothing.
const registry_shutdown_milliseconds = 1000

/// How long a map's supervisor has to stop, in milliseconds. A supervisor
/// stops its children in turn, each of which has a second to stop, so this
/// is generous.
const map_shutdown_milliseconds = 10_000

/// How long the registry has to start, in milliseconds.
const start_deadline_milliseconds = 5000

/// What the maps start with, each made once by whoever starts the tree: the
/// registry's name, the name of the factory supervisor that starts the maps,
/// the snapshot process's name and the ceilings of the processes of every
/// map.
pub type Settings {
  Settings(
    registry: Name(Message),
    factory: Name(
      factory_supervisor.Message(world_map_process.Settings, Supervisor),
    ),
    snapshot: Name(snapshot.Message),
    heap_limits: HeapLimits,
  )
}

/// Every message the registry receives. Its selector covers all of them;
/// anything else is logged.
pub opaque type Message {
  /// Finds the map of a world, starting it when the world has none.
  Find(
    world_id: Int,
    reply: Subject(Result(Name(world_map_process.Message), actor.StartError)),
  )
  /// Gives the names of the maps that run.
  AllMaps(reply: Subject(List(Name(world_map_process.Message))))
  /// A map's supervisor ended.
  MapEnded(process.Down)
  Unexpected(received: Dynamic)
}

/// A character that entered a map: its unit, the map process that holds it,
/// which the character's connection watches so it ends when the map does, and
/// the subject to ask the map by, such as to leave.
pub type Entered {
  Entered(unit: PlayerUnit, map: Pid, via: Subject(world_map_process.Message))
}

/// Why a character did not enter a map.
pub type EnterError {
  /// The map of the world could not be started.
  MapNotStarted(actor.StartError)
  /// The map did not give the character a unit.
  MapRefused(world_map_process.JoinError)
  /// The registry did not answer within the time given.
  RegistryNotAnswering
}

/// A map the registry started: the name its process is reached by and its
/// supervisor, whose end the registry is told of.
type Running {
  Running(
    map: Name(world_map_process.Message),
    supervisor: Pid,
    monitor: Monitor,
  )
}

/// The names of the processes of one world's map. A name makes an atom the
/// runtime never frees, so they are made once, when the world's first map
/// starts, and every map the registry starts for the world takes them.
type Names {
  Names(
    map: Name(world_map_process.Message),
    senders: List(Name(sender.Message)),
  )
}

type State {
  State(settings: Settings, maps: Dict(Int, Running), names: Dict(Int, Names))
}

/// The maps' subtree as a child of the game's supervisor: the registry, then
/// the factory supervisor of the maps, rest for one, 3 restarts in 5 seconds.
pub fn supervised(
  settings settings: Settings,
  worlds _worlds: List(Int),
) -> ChildSpecification(Supervisor) {
  let registry =
    supervision.worker(fn() { start_registry(settings) })
    |> supervision.timeout(ms: registry_shutdown_milliseconds)
  let factory =
    factory_supervisor.worker_child(world_map_process.start)
    |> factory_supervisor.named(settings.factory)
    |> factory_supervisor.restart_tolerance(
      intensity: restart_intensity,
      period: restart_period_seconds,
    )
    |> factory_supervisor.timeout(ms: map_shutdown_milliseconds)
    |> factory_supervisor.restart_strategy(supervision.Temporary)
    |> factory_supervisor.supervised
  static_supervisor.new(static_supervisor.RestForOne)
  |> static_supervisor.restart_tolerance(
    intensity: restart_intensity,
    period: restart_period_seconds,
  )
  |> static_supervisor.add(registry)
  |> static_supervisor.add(factory)
  |> static_supervisor.supervised
}

fn start_registry(settings: Settings) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_deadline_milliseconds, fn(self) {
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(MapEnded)
      |> process.select_other(Unexpected)
    actor.initialised(State(settings:, maps: dict.new(), names: dict.new()))
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.named(settings.registry)
  |> actor.on_message(handle)
  |> actor.start
}

/// Joins a character's unit to the map of the world, starting the map when the
/// world has none, and waits up to `within_ms` milliseconds for the unit and
/// the map process that holds it. The connection receives the map's deliveries
/// on `connection`.
pub fn enter(
  registry registry: Name(Message),
  world_id world_id: Int,
  newcomer newcomer: Newcomer,
  connection connection: Subject(Delivery),
  within_ms within_ms: Int,
) -> Result(Entered, EnterError) {
  let deadline = clock.monotonic_milliseconds() + within_ms
  use name <- result.try(find(registry:, world_id:, within_ms:))
  // The process is looked up before the join, so a map that starts again
  // between the two is a process the connection watches and finds gone.
  use pid <- result.try(
    process.named(name)
    |> result.replace_error(MapRefused(world_map_process.NotAnswering)),
  )
  use unit <- result.try(
    world_map_process.join(
      map: process.named_subject(name),
      newcomer:,
      connection:,
      within_ms: int.max(0, deadline - clock.monotonic_milliseconds()),
    )
    |> result.map_error(MapRefused),
  )
  Ok(Entered(unit:, map: pid, via: process.named_subject(name)))
}

/// The first of the characters that is on a map, which a map in any world
/// holds, or none: asked of the registry for the maps that run and then of each
/// map, each within `within_ms` milliseconds. A registry or a map that does not
/// answer holds no character the caller knows of.
pub fn character_on_a_map(
  registry registry: Name(Message),
  character_ids character_ids: List(Int),
  within_ms within_ms: Int,
) -> Option(Int) {
  option.from_result({
    use _ <- result.try(process.named(registry))
    let reply = process.new_subject()
    process.send(process.named_subject(registry), AllMaps(reply:))
    use names <- result.try(
      process.receive(reply, within_ms) |> result.replace_error(Nil),
    )
    list.find_map(names, fn(name) {
      character_on_the_map(name:, character_ids:, within_ms:)
    })
  })
}

/// The first of the characters that the map holds a unit of.
fn character_on_the_map(
  name name: Name(world_map_process.Message),
  character_ids character_ids: List(Int),
  within_ms within_ms: Int,
) -> Result(Int, Nil) {
  use units <- result.try(world_map_process.units(
    map: process.named_subject(name),
    within_ms:,
  ))
  list.find(list.map(units, fn(unit) { unit.character_id }), list.contains(
    character_ids,
    _,
  ))
}

/// The name of the map of a world, which the registry starts when the world
/// has none.
fn find(
  registry registry: Name(Message),
  world_id world_id: Int,
  within_ms within_ms: Int,
) -> Result(Name(world_map_process.Message), EnterError) {
  use _ <- result.try(
    process.named(registry) |> result.replace_error(RegistryNotAnswering),
  )
  let reply = process.new_subject()
  process.send(process.named_subject(registry), Find(world_id:, reply:))
  case process.receive(reply, within_ms) {
    Ok(Ok(map)) -> Ok(map)
    Ok(Error(why)) -> Error(MapNotStarted(why))
    Error(Nil) -> Error(RegistryNotAnswering)
  }
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Find(world_id:, reply:) -> {
      let #(state, found) = running_map(state:, world_id:)
      process.send(reply, found)
      actor.continue(state)
    }
    AllMaps(reply:) -> {
      process.send(
        reply,
        dict.values(state.maps)
          |> list.filter(fn(running) { process.is_alive(running.supervisor) })
          |> list.map(fn(running) { running.map }),
      )
      actor.continue(state)
    }
    MapEnded(process.ProcessDown(monitor:, ..)) ->
      actor.continue(
        State(
          ..state,
          maps: dict.filter(state.maps, fn(_world_id, running) {
            running.monitor != monitor
          }),
        ),
      )
    MapEnded(process.PortDown(..)) -> actor.continue(state)
    Unexpected(..) -> {
      log.error(
        log.Who(
          account: None,
          actor: None,
          place: Some(log.Process("maps")),
          message: None,
          peer: None,
        ),
        "the maps' registry received a message it does not handle",
      )
      actor.continue(state)
    }
  }
}

/// The map of a world that is running, or a new one. A map whose supervisor has
/// ended but whose end the registry has not been told of yet is no map that
/// is running.
fn running_map(
  state state: State,
  world_id world_id: Int,
) -> #(State, Result(Name(world_map_process.Message), actor.StartError)) {
  case dict.get(state.maps, world_id) {
    Ok(running) ->
      case process.is_alive(running.supervisor) {
        True -> #(state, Ok(running.map))
        False -> start_map(state:, world_id:)
      }
    Error(Nil) -> start_map(state:, world_id:)
  }
}

/// Starts a map for the world with the names the world's maps have. A factory
/// that is not running, as when its supervisor is being rebuilt, is a map that
/// could not start, which the next entry tries again.
fn start_map(
  state state: State,
  world_id world_id: Int,
) -> #(State, Result(Name(world_map_process.Message), actor.StartError)) {
  let names = case dict.get(state.names, world_id) {
    Ok(names) -> names
    Error(Nil) ->
      Names(
        map: process.new_name("map"),
        senders: world_map_process.new_sender_names(),
      )
  }
  let state = State(..state, names: dict.insert(state.names, world_id, names))
  let settings =
    world_map_process.Settings(
      world_id:,
      map: names.map,
      senders: names.senders,
      snapshot: state.settings.snapshot,
      heap_limits: state.settings.heap_limits,
    )
  case process.named(state.settings.factory) {
    Error(Nil) -> #(
      state,
      Error(actor.InitFailed("the factory of the maps is not running")),
    )
    Ok(_) ->
      case
        factory_supervisor.start_child(
          factory_supervisor.get_by_name(state.settings.factory),
          settings,
        )
      {
        Ok(started) -> {
          let running =
            Running(
              map: settings.map,
              supervisor: started.pid,
              monitor: process.monitor(started.pid),
            )
          #(
            State(..state, maps: dict.insert(state.maps, world_id, running)),
            Ok(settings.map),
          )
        }
        Error(why) -> #(state, Error(why))
      }
  }
}
