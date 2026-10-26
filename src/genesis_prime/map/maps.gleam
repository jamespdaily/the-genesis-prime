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
//// rebuilt stops every map, which no registry remembers. The names of every
//// world's map processes are made once, when the server starts, and given to
//// the registry as a start argument, so a registry or a map that starts again
//// makes no new atoms. A map started while an earlier map of the world still
//// holds its names waits for the earlier one to end, but the registry does not:
//// it monitors the processes that hold the names, keeps the askers of the world
//// waiting, and goes on serving the other worlds. It starts the map and answers
//// the askers when the last holder is down, and answers an asker that is still
//// waiting at the asker's own deadline.

import genesis_prime/connection/clock
import genesis_prime/connection/named_send
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
import gleam/option.{None, Some}
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
  /// Finds the map of a world, starting it when the world has none. `by` is
  /// the monotonic time in milliseconds at which the asker gives up, which a
  /// wait for an old map to end is within.
  Find(world_id: Int, by: Int, reply: Subject(Found))
  /// A map's supervisor ended, or a process that held a name of a world's old
  /// map did.
  MapEnded(process.Down)
  /// The deadline of an asker that waits for the world's old map to end
  /// passed; the asker is told by its reply subject.
  AskerGaveUp(world_id: Int, reply: Subject(Found))
  Unexpected(received: Dynamic)
}

/// What the registry answers an asker: the name of the world's map, or why no
/// map could be started.
type Found =
  Result(Name(world_map_process.Message), actor.StartError)

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

/// The names of the processes of one world's map.
type WorldNames {
  WorldNames(
    map: Name(world_map_process.Message),
    senders: List(Name(sender.Message)),
  )
}

/// The names of the processes of every world's map that can start. A name makes
/// an atom the runtime never frees, so they are made once, when the server
/// starts, and every map the registry starts for a world takes the world's
/// names, however often the registry or the map starts again.
pub opaque type Names {
  Names(worlds: Dict(Int, WorldNames))
}

/// The names for the maps of the worlds, which whoever starts the tree makes
/// once.
pub fn new_names(worlds worlds: List(Int)) -> Names {
  Names(
    worlds: list.map(worlds, fn(world_id) {
      #(
        world_id,
        WorldNames(
          map: process.new_name("map"),
          senders: world_map_process.new_sender_names(),
        ),
      )
    })
    |> dict.from_list,
  )
}

/// The name the process of a world's map is registered under, or an error for
/// a world that has no names.
pub fn map_name(
  names names: Names,
  world_id world_id: Int,
) -> Result(Name(world_map_process.Message), Nil) {
  dict.get(names.worlds, world_id) |> result.map(fn(world) { world.map })
}

/// An asker that waits for the old map of a world to end: where to answer, and
/// the timer that tells the registry its deadline passed.
type Asker {
  Asker(reply: Subject(Found), deadline: process.Timer)
}

/// A world whose map cannot start yet because processes of an earlier map
/// still hold the names of the world's processes: the monitors of those
/// processes that are not down yet, and the askers waiting for them.
type Pending {
  Pending(holders: List(Monitor), askers: List(Asker))
}

/// The registry's state: its subject, which its timers send to, its settings,
/// the names it was started with, the map it started for each world and the
/// worlds that wait for an old map to end.
type State {
  State(
    self: Subject(Message),
    settings: Settings,
    names: Names,
    maps: Dict(Int, Running),
    pending: Dict(Int, Pending),
  )
}

/// The maps' subtree as a child of the game's supervisor: the registry, then
/// the factory supervisor of the maps, rest for one, 3 restarts in 5 seconds.
/// `names` are the names of every world's map processes, made once by whoever
/// starts the tree, so a registry that starts again takes the names it had.
pub fn supervised(
  settings settings: Settings,
  names names: Names,
) -> ChildSpecification(Supervisor) {
  let registry =
    supervision.worker(fn() { start_registry(settings, names) })
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

fn start_registry(
  settings: Settings,
  names: Names,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(start_deadline_milliseconds, fn(self) {
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(MapEnded)
      |> process.select_other(Unexpected)
    actor.initialised(State(
      self:,
      settings:,
      names:,
      maps: dict.new(),
      pending: dict.new(),
    ))
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
  named_send.send(
    process.named_subject(registry),
    Find(world_id:, by: clock.monotonic_milliseconds() + within_ms, reply:),
  )
  case process.receive(reply, within_ms) {
    Ok(Ok(map)) -> Ok(map)
    Ok(Error(why)) -> Error(MapNotStarted(why))
    Error(Nil) -> Error(RegistryNotAnswering)
  }
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Find(world_id:, by:, reply:) ->
      actor.continue(find_map(state:, world_id:, by:, reply:))
    MapEnded(process.ProcessDown(monitor:, ..)) ->
      actor.continue(
        State(
          ..state,
          maps: dict.filter(state.maps, fn(_world_id, running) {
            running.monitor != monitor
          }),
        )
        |> holder_ended(monitor),
      )
    MapEnded(process.PortDown(..)) -> actor.continue(state)
    AskerGaveUp(world_id:, reply:) ->
      actor.continue(asker_gave_up(state:, world_id:, reply:))
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

/// Answers an asker with the map of its world when it is running, starts the
/// map when no process of an earlier map holds a name of it, and otherwise
/// keeps the asker waiting for the old map to end. A map whose supervisor has
/// ended but whose end the registry has not been told of yet is no map that is
/// running.
fn find_map(
  state state: State,
  world_id world_id: Int,
  by by: Int,
  reply reply: Subject(Found),
) -> State {
  case dict.get(state.pending, world_id) {
    Ok(pending) -> wait_with(state:, world_id:, pending:, by:, reply:)
    Error(Nil) ->
      case dict.get(state.maps, world_id) {
        Ok(running) ->
          case process.is_alive(running.supervisor) {
            True -> {
              process.send(reply, Ok(running.map))
              state
            }
            False -> start_or_wait(state:, world_id:, by:, reply:)
          }
        Error(Nil) -> start_or_wait(state:, world_id:, by:, reply:)
      }
  }
}

/// Starts a map for the world with the names the world's maps have, once no
/// process of an earlier map of the world holds one of them. A map whose
/// supervisor ended can still be going down, with its processes registered, and
/// a map started while they hold the names could not register its own; the
/// registry monitors those processes and the asker waits, without the registry
/// holding up any other world. A world with no names, and a factory that is not
/// running, as when its supervisor is being rebuilt, are a map that could not
/// start, which the next entry tries again.
fn start_or_wait(
  state state: State,
  world_id world_id: Int,
  by by: Int,
  reply reply: Subject(Found),
) -> State {
  case dict.get(state.names.worlds, world_id) {
    Error(Nil) -> {
      process.send(
        reply,
        Error(actor.InitFailed("the world has no names for a map")),
      )
      state
    }
    Ok(names) ->
      case holders_of(names) {
        [] -> {
          let #(state, started) = start_map_with(state:, world_id:, names:)
          process.send(reply, started)
          state
        }
        holders ->
          wait_with(
            state:,
            world_id:,
            pending: Pending(
              holders: list.map(holders, process.monitor),
              askers: [],
            ),
            by:,
            reply:,
          )
      }
  }
}

/// The processes that hold a name of the world's map.
fn holders_of(names: WorldNames) -> List(Pid) {
  list.append(
    result.values([process.named(names.map)]),
    result.values(list.map(names.senders, process.named)),
  )
}

/// Adds an asker to the world's wait, with a timer that tells the registry when
/// its deadline `by` passes.
fn wait_with(
  state state: State,
  world_id world_id: Int,
  pending pending: Pending,
  by by: Int,
  reply reply: Subject(Found),
) -> State {
  let deadline =
    process.send_after(
      state.self,
      int.max(0, by - clock.monotonic_milliseconds()),
      AskerGaveUp(world_id:, reply:),
    )
  State(
    ..state,
    pending: dict.insert(
      state.pending,
      world_id,
      Pending(..pending, askers: [Asker(reply:, deadline:), ..pending.askers]),
    ),
  )
}

/// A process that was monitored is down. When it was the last one a world
/// waited for, the world's map starts and every asker is answered.
fn holder_ended(state: State, monitor: Monitor) -> State {
  dict.fold(state.pending, state, fn(state, world_id, pending) {
    case list.contains(pending.holders, monitor) {
      False -> state
      True ->
        case list.filter(pending.holders, fn(holder) { holder != monitor }) {
          [] -> start_for_the_askers(state:, world_id:, pending:)
          holders ->
            State(
              ..state,
              pending: dict.insert(
                state.pending,
                world_id,
                Pending(..pending, holders:),
              ),
            )
        }
    }
  })
}

/// Starts the map of a world whose old map has ended and gives each asker the
/// answer.
fn start_for_the_askers(
  state state: State,
  world_id world_id: Int,
  pending pending: Pending,
) -> State {
  let state = State(..state, pending: dict.delete(state.pending, world_id))
  let #(state, started) = case dict.get(state.names.worlds, world_id) {
    Ok(names) -> start_map_with(state:, world_id:, names:)
    Error(Nil) -> #(
      state,
      Error(actor.InitFailed("the world has no names for a map")),
    )
  }
  list.each(pending.askers, fn(asker) {
    process.cancel_timer(asker.deadline)
    process.send(asker.reply, started)
  })
  state
}

/// An asker's deadline passed while it waited for the old map of its world to
/// end: it is answered that no map started and no longer waited for. A world
/// that no asker waits for is no longer monitored. An asker that was answered
/// already is not found, and its timer's message is dropped.
fn asker_gave_up(
  state state: State,
  world_id world_id: Int,
  reply reply: Subject(Found),
) -> State {
  case dict.get(state.pending, world_id) {
    Error(Nil) -> state
    Ok(pending) ->
      case list.partition(pending.askers, fn(asker) { asker.reply == reply }) {
        #([], _) -> state
        #(_, []) -> {
          list.each(pending.holders, process.demonitor_process)
          answer_gave_up(reply)
          State(..state, pending: dict.delete(state.pending, world_id))
        }
        #(_, askers) -> {
          answer_gave_up(reply)
          State(
            ..state,
            pending: dict.insert(
              state.pending,
              world_id,
              Pending(..pending, askers:),
            ),
          )
        }
      }
  }
}

fn answer_gave_up(reply: Subject(Found)) -> Nil {
  process.send(
    reply,
    Error(actor.InitFailed(
      "the earlier map of the world still holds the names of its processes",
    )),
  )
}

fn start_map_with(
  state state: State,
  world_id world_id: Int,
  names names: WorldNames,
) -> #(State, Found) {
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
