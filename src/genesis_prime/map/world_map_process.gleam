//// The process that owns one world's map: the state of `world_map` and the
//// connections of the players on it. A player's connection asks it to join; the
//// map gives the player's unit an id, holds it, and tells the players in range
//// through a pool of sender processes (one for each scheduler online), so no
//// one message holds the map for long.
////
//// The supervision tree of one map is one supervisor, restarting its children
//// rest for one: the senders first, then the map process. A sender that
//// crashes takes the map process down with it, because the map process starts
//// after the senders. The map process is registered under a name made by
//// whoever starts the map; the senders under names of their own, so a rebuilt
//// map process reaches the rebuilt senders. A restarted map starts empty:
//// every player on it is told nothing, and each connection must join again.
////
//// The map process monitors the connection of each player that joined and
//// takes the player's unit off the map when the connection ends.

import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/heap_limit.{type HeapLimits}
import genesis_prime/map/sender
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/map/world_map.{type JoinRefused, type WorldMap, Deliver}
import genesis_prime/telemetry/log
import genesis_prime/telemetry/snapshot
import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Monitor, type Name, type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision
import gleam/result

/// How many restarts the map's supervisor allows in `restart_period_seconds`:
/// a rebuild of a map takes milliseconds, so three are far inside the period,
/// and a fault that survives them ends the map, which the next entry starts
/// again.
const restart_intensity = 3

/// The period of the supervisor's restart limit, in seconds.
const restart_period_seconds = 5

/// How long the map process has to stop, in milliseconds. It saves nothing, so
/// it has the second every worker that flushes no saves has.
const shutdown_milliseconds = 1000

/// How long the map process has to build its state, in milliseconds.
const initialisation_milliseconds = 5000

/// What a map starts with. `world_id` is the World row the map is of. `map` is
/// the name the map process registers under, `senders` the names of its
/// senders, one for each scheduler online (`new_sender_names`), and `snapshot`
/// the name of the snapshot process the map registers its processes with, each
/// made once by whoever starts the tree and kept for a map that starts again.
/// `heap_limits` are the ceilings of the map process and each sender.
pub type Settings {
  Settings(
    world_id: Int,
    map: Name(Message),
    senders: List(Name(sender.Message)),
    snapshot: Name(snapshot.Message),
    heap_limits: HeapLimits,
  )
}

/// The names of the senders of one map: one for each scheduler online. A name
/// makes an atom the runtime never frees, so whoever starts maps makes a
/// world's names once and gives them to every map it starts for the world.
pub fn new_sender_names() -> List(Name(sender.Message)) {
  list.repeat(Nil, schedulers_online())
  |> list.map(fn(_) { process.new_name("map_sender") })
}

/// Every message the map process receives. Its selector covers all of them;
/// anything else is logged.
pub opaque type Message {
  Join(
    newcomer: Newcomer,
    connection: Subject(Delivery),
    reply: Subject(Result(PlayerUnit, JoinRefused)),
  )
  Units(reply: Subject(List(PlayerUnit)))
  /// A connection leaves: its unit comes off the map, and the reply says it
  /// has.
  Leave(connection: Subject(Delivery), reply: Subject(Nil))
  /// A monitored connection ended.
  ConnectionDown(process.Down)
  Unexpected(received: Dynamic)
}

/// Why a join did not give the player a unit.
pub type JoinError {
  /// The map refused the character.
  Refused(JoinRefused)
  /// The map did not answer within the time given.
  NotAnswering
}

/// The state of the map process: its settings, the map's rules' state, the
/// senders by number, each joined player's connection by unit id and the
/// monitor held on it.
type State {
  State(
    settings: Settings,
    map: WorldMap,
    senders: Dict(Int, Subject(sender.Message)),
    connections: Dict(Int, Subject(Delivery)),
    monitors: Dict(Monitor, Int),
  )
}

/// Starts one map: its supervisor, which starts the senders and then the map
/// process, restarting them rest for one, 3 restarts in 5 seconds: a rebuild
/// of a map takes milliseconds, so three are far inside that period, and a
/// fault that survives them ends the map, which the next entry starts again.
/// The supervisor is linked to the calling process.
pub fn start(settings settings: Settings) -> actor.StartResult(Supervisor) {
  let sender_names = settings.senders
  let map_child =
    supervision.worker(fn() { start_map(settings:, sender_names:) })
    |> supervision.timeout(ms: shutdown_milliseconds)
  list.fold(
    sender_names,
    static_supervisor.new(static_supervisor.RestForOne)
      |> static_supervisor.restart_tolerance(
        intensity: restart_intensity,
        period: restart_period_seconds,
      ),
    fn(builder, name) {
      static_supervisor.add(
        builder,
        sender.supervised(
          name:,
          limit: settings.heap_limits.sender,
          world_id: settings.world_id,
        ),
      )
    },
  )
  |> static_supervisor.add(map_child)
  |> static_supervisor.start
}

fn start_map(
  settings settings: Settings,
  sender_names sender_names: List(Name(sender.Message)),
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(initialisation_milliseconds, fn(self) {
    heap_limit.apply(settings.heap_limits.map)
    snapshot.register(
      snapshot: settings.snapshot,
      kind: snapshot.Kind(
        name: "map_" <> int.to_string(settings.world_id),
        processes: fn() { processes_of(settings:, sender_names:) },
      ),
    )
    let selector =
      process.new_selector()
      |> process.select(self)
      |> process.select_monitors(ConnectionDown)
      |> process.select_other(Unexpected)
    let state =
      State(
        settings:,
        map: world_map.new(settings.world_id),
        senders: dict.from_list(
          list.index_map(sender_names, fn(name, number) {
            #(number, process.named_subject(name))
          }),
        ),
        connections: dict.new(),
        monitors: dict.new(),
      )
    actor.initialised(state)
    |> actor.selecting(selector)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.named(settings.map)
  |> actor.on_message(handle)
  |> actor.start
}

/// The processes of a map that are running when it is called: the map process
/// and each sender, which the snapshot reports as one kind.
fn processes_of(
  settings settings: Settings,
  sender_names sender_names: List(Name(sender.Message)),
) -> List(Pid) {
  let senders = result.values(list.map(sender_names, process.named))
  case process.named(settings.map) {
    Ok(map) -> [map, ..senders]
    Error(Nil) -> senders
  }
}

/// Asks the map to join a character's unit, with the subject its connection
/// receives deliveries on, and waits up to `within_ms` milliseconds for the
/// unit. A map whose name has no process, as while it starts again, does not
/// answer.
pub fn join(
  map map: Subject(Message),
  newcomer newcomer: Newcomer,
  connection connection: Subject(Delivery),
  within_ms within_ms: Int,
) -> Result(PlayerUnit, JoinError) {
  use <- bool.guard(when: !registered(map), return: Error(NotAnswering))
  let reply = process.new_subject()
  process.send(map, Join(newcomer:, connection:, reply:))
  case process.receive(reply, within_ms) {
    Ok(Ok(unit)) -> Ok(unit)
    Ok(Error(refused)) -> Error(Refused(refused))
    Error(Nil) -> Error(NotAnswering)
  }
}

/// Whether a request to the map can be sent: a map reached by its name has a
/// process under the name, which a map between two lives does not, and sending
/// to a name with none is a crash of the sender.
fn registered(map: Subject(Message)) -> Bool {
  case process.subject_name(map) {
    Ok(name) -> result.is_ok(process.named(name))
    Error(Nil) -> True
  }
}

/// Takes the unit of a connection off the map and waits up to `within_ms`
/// milliseconds for the map to say it has, so the connection can end knowing
/// the unit is gone. A connection that has no unit on the map has left already.
/// The map that does not answer, or has no process under its name, is an
/// error.
pub fn leave(
  map map: Subject(Message),
  connection connection: Subject(Delivery),
  within_ms within_ms: Int,
) -> Result(Nil, Nil) {
  use <- bool.guard(when: !registered(map), return: Error(Nil))
  let reply = process.new_subject()
  process.send(map, Leave(connection:, reply:))
  process.receive(reply, within_ms)
}

/// The units the map holds, waiting up to `within_ms` milliseconds for the
/// answer.
pub fn units(
  map map: Subject(Message),
  within_ms within_ms: Int,
) -> Result(List(PlayerUnit), Nil) {
  use <- bool.guard(when: !registered(map), return: Error(Nil))
  let reply = process.new_subject()
  process.send(map, Units(reply:))
  process.receive(reply, within_ms)
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Join(newcomer:, connection:, reply:) ->
      actor.continue(join_unit(state:, newcomer:, connection:, reply:))
    Units(reply:) -> {
      process.send(reply, world_map.units(state.map))
      actor.continue(state)
    }
    Leave(connection:, reply:) -> {
      let state = connection_left(state:, connection:)
      process.send(reply, Nil)
      actor.continue(state)
    }
    ConnectionDown(process.ProcessDown(monitor:, ..)) ->
      actor.continue(connection_ended(state:, monitor:))
    ConnectionDown(process.PortDown(..)) -> actor.continue(state)
    Unexpected(..) -> {
      log.error(
        map_who(state),
        "the map process received a message it does not handle",
      )
      actor.continue(state)
    }
  }
}

fn map_who(state: State) -> log.Who {
  log.Who(
    account: None,
    actor: None,
    place: Some(log.Map(world_map.world_id(state.map))),
    message: None,
    peer: None,
  )
}

/// Joins a character's unit, answers the connection and tells the players in
/// range. The map monitors the connection, so the unit leaves with it.
fn join_unit(
  state state: State,
  newcomer newcomer: Newcomer,
  connection connection: Subject(Delivery),
  reply reply: Subject(Result(PlayerUnit, JoinRefused)),
) -> State {
  case world_map.join(state.map, newcomer) {
    Error(refused) -> {
      process.send(reply, Error(refused))
      state
    }
    Ok(#(map, unit, effects)) -> {
      let assert Ok(owner) = process.subject_owner(connection)
        as "a connection's subject belongs to its process"
      let monitor = process.monitor(owner)
      let state =
        State(
          ..state,
          map:,
          connections: dict.insert(state.connections, unit.id, connection),
          monitors: dict.insert(state.monitors, monitor, unit.id),
        )
      process.send(reply, Ok(unit))
      carry_out(state:, effects:)
      state
    }
  }
}

/// Takes the unit of a connection that said it leaves off the map, stops
/// watching the connection and tells the players in range.
fn connection_left(
  state state: State,
  connection connection: Subject(Delivery),
) -> State {
  let held =
    dict.to_list(state.connections)
    |> list.find(fn(entry) { entry.1 == connection })
  case held {
    Error(Nil) -> state
    Ok(#(unit_id, _)) -> {
      let watching =
        dict.to_list(state.monitors)
        |> list.find(fn(entry) { entry.1 == unit_id })
      case watching {
        Error(Nil) -> state
        Ok(#(monitor, _)) -> {
          process.demonitor_process(monitor)
          connection_ended(state:, monitor:)
        }
      }
    }
  }
}

/// Takes the unit of an ended connection off the map and tells the players in
/// range.
fn connection_ended(state state: State, monitor monitor: Monitor) -> State {
  case dict.get(state.monitors, monitor) {
    Error(Nil) -> state
    Ok(unit_id) -> {
      let #(map, effects) = world_map.leave(state.map, unit_id)
      let state =
        State(
          ..state,
          map:,
          connections: dict.delete(state.connections, unit_id),
          monitors: dict.delete(state.monitors, monitor),
        )
      carry_out(state:, effects:)
      state
    }
  }
}

/// Hands each delivery, with the connections of the players it is for, to the
/// sender chosen by the id of the unit the delivery is about.
fn carry_out(
  state state: State,
  effects effects: List(world_map.Effect),
) -> Nil {
  list.each(effects, fn(effect) {
    let Deliver(delivery:, about:, to:) = effect
    let recipients =
      list.filter_map(to, fn(unit_id) { dict.get(state.connections, unit_id) })
    case recipients {
      [] -> Nil
      [_, ..] -> {
        let assert Ok(chosen) =
          dict.get(state.senders, about % dict.size(state.senders))
          as "a sender is stored under each number below the pool size"
        sender.send(chosen, delivery, recipients)
      }
    }
  })
}

/// The schedulers online, one sender for each.
@external(erlang, "world_map_ffi", "schedulers_online")
fn schedulers_online() -> Int
