//// Prototype B: one process owns every unit of the map, with a grid index in
//// its state. Moves and attacks are messages to it, and it thinks for the
//// creatures itself, a hundredth of them every 10 milliseconds, so each
//// creature thinks once a second and no one message holds the map for long.
////
//// The supervision tree is one supervisor with one child, the map process,
//// registered under a name made for the run. The map process is rebuilt from
//// the spawn list kept in the persistent term named by the start argument,
//// so a crash loses the whole map until the rebuild is done: every player
//// sees every unit stop, and each player's connection must join again.

import genesis_prime/topology/grid.{type Grid}
import genesis_prime/topology/measurement.{type Counter}
import genesis_prime/topology/owner.{type Owner, Owner}
import genesis_prime/topology/position.{type Position}
import genesis_prime/topology/unit.{type Unit}
import genesis_prime/topology/update.{type Delivery}
import genesis_prime/topology/workload.{type Workload}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/list
import gleam/option
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import gleam/result

/// How many restarts the supervisor allows in `restart_period_seconds`.
const restart_intensity = 3

/// The period of the supervisor's restart limit, in seconds.
const restart_period_seconds = 5

/// How long the map process has to stop when told to, in milliseconds.
const shutdown_milliseconds = 5000

/// How many parts the creatures' think is divided into, one part every
/// `slice_interval_milliseconds`: about 100 thinks a part at 10,000
/// creatures, so no one message holds the map, and the moves behind it, for
/// long.
const think_slices = 100

/// A cost planted in the prototype to show that the harness can see one.
pub type PlantedCost {
  /// The prototype as it is.
  NoPlantedCost
  /// One more grid-cell lookup on every move.
  ExtraGridLookupPerMove
}

/// Every message the map process can receive. Its selector covers all of
/// them; anything else is logged.
type Message {
  /// A player moves a unit: the unit, the position and the time the move was
  /// sent.
  Move(unit_id: Int, position: Position, sent_at: Int)
  /// A player's unit hits the nearest creature in visibility range, and the
  /// time the attack was sent.
  Attack(attacker_id: Int, sent_at: Int)
  /// The timer for the next slice of creature thinking is due.
  Slice
  /// A dead unit's return time has come.
  Return(unit_id: Int)
  /// A player's connection joins its unit: the unit's id and the connection.
  Join(unit_id: Int, connection: Subject(Delivery))
  /// Asks the process to answer, to show that it handles messages.
  Probe(reply_with: Subject(Nil))
}

/// The state of the map process: every unit, the grid over them, each
/// player's connection, the creatures split into the slices they think in, and
/// which slice is next.
type State {
  State(
    workload: Workload,
    units: Dict(Int, Unit),
    grid: Grid,
    connections: Dict(Int, Subject(Delivery)),
    slices: Dict(Int, List(Int)),
    next_slice: Int,
    planted: PlantedCost,
    handled: Counter,
    self: Subject(Message),
  )
}

/// How long the map process may take to build its state at start, in
/// milliseconds.
const initialisation_milliseconds = 60_000

/// The time between two slices of creature thinking, in milliseconds.
const slice_interval_milliseconds = 10

/// Starts the prototype: the supervisor and the map process, built from the
/// spawn list kept under `spawn_list_key`. Players' connections join
/// afterwards through the `Owner`. The supervisor is linked to the calling
/// process; the data is the `Owner` the players act through.
pub fn start(
  workload workload: Workload,
  spawn_list_key spawn_list_key: Reference,
  planted planted: PlantedCost,
) -> Result(actor.Started(Owner), actor.StartError) {
  use #(started, _name) <- result.map(start_named(
    workload:,
    spawn_list_key:,
    planted:,
  ))
  started
}

/// Kills the map process and returns the microseconds until the rebuilt
/// process handles a message again. It starts its own prototype with no
/// players from the spawn list kept under `spawn_list_key` and stops it.
pub fn crash_cost(
  workload workload: Workload,
  spawn_list_key spawn_list_key: Reference,
  planted planted: PlantedCost,
) -> Int {
  let assert Ok(#(started, name)) =
    start_named(workload:, spawn_list_key:, planted:)
    as "the prototype did not start"
  let assert Ok(victim) = process.named(name) as "the map process is running"
  let started_at = measurement.monotonic_microseconds()
  process.kill(victim)
  await_rebuilt(name, victim)
  let elapsed = measurement.monotonic_microseconds() - started_at
  owner.stop_supervisor(started.pid)
  elapsed
}

fn start_named(
  workload workload: Workload,
  spawn_list_key spawn_list_key: Reference,
  planted planted: PlantedCost,
) -> Result(#(actor.Started(Owner), process.Name(Message)), actor.StartError) {
  let name = process.new_name("topology_map")
  let handled = measurement.new_counter()
  let map_child =
    supervision.worker(fn() {
      start_map(workload:, spawn_list_key:, planted:, name:, handled:)
    })
    |> supervision.timeout(ms: shutdown_milliseconds)
  use supervisor <- result.map(
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(
      intensity: restart_intensity,
      period: restart_period_seconds,
    )
    |> static_supervisor.add(map_child)
    |> static_supervisor.start,
  )
  #(
    actor.Started(
      pid: supervisor.pid,
      data: door(supervisor: supervisor.pid, name:, handled:),
    ),
    name,
  )
}

fn start_map(
  workload workload: Workload,
  spawn_list_key spawn_list_key: Reference,
  planted planted: PlantedCost,
  name name: process.Name(Message),
  handled handled: Counter,
) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(initialisation_milliseconds, fn(self) {
    let units = measurement.spawn_list(spawn_list_key)
    let state =
      State(
        workload:,
        units:,
        grid: index(units, workload.visibility_range),
        connections: dict.new(),
        slices: divide_into_slices(units),
        next_slice: 0,
        planted:,
        handled:,
        self:,
      )
    schedule(
      self:,
      delay_milliseconds: slice_interval_milliseconds,
      message: Slice,
    )
    actor.initialised(state)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.named(name)
  |> actor.on_message(handle)
  |> actor.start
}

fn index(units: Dict(Int, Unit), cell_size: Float) -> Grid {
  dict.fold(units, grid.new(cell_size), fn(index, unit_id, unit) {
    grid.insert(index, unit_id, unit.position)
  })
}

/// The creatures' ids, divided by id into the slices they think in.
fn divide_into_slices(units: Dict(Int, Unit)) -> Dict(Int, List(Int)) {
  dict.fold(units, dict.new(), fn(slices, unit_id, unit) {
    case unit.kind {
      unit.Creature ->
        dict.upsert(slices, unit_id % think_slices, fn(unit_ids) {
          [unit_id, ..option.unwrap(unit_ids, [])]
        })
      unit.Player -> slices
    }
  })
}

fn schedule(
  self self: Subject(Message),
  delay_milliseconds delay_milliseconds: Int,
  message message: Message,
) -> Nil {
  let _timer = process.send_after(self, delay_milliseconds, message)
  Nil
}

/// The `Owner` of a running prototype, which reaches the map process through
/// its name, so a rebuilt process is reached too.
fn door(
  supervisor supervisor: Pid,
  name name: process.Name(Message),
  handled handled: Counter,
) -> Owner {
  let map = process.named_subject(name)
  let map_processes = fn() {
    case process.named(name) {
      Ok(pid) -> [pid]
      Error(Nil) -> []
    }
  }
  Owner(
    join: fn(unit_id, connection) {
      process.send(map, Join(unit_id:, connection:))
    },
    move: fn(unit_id, position, sent_at) {
      process.send(map, Move(unit_id:, position:, sent_at:))
    },
    attack_nearest_creature: fn(unit_id, sent_at) {
      process.send(map, Attack(attacker_id: unit_id, sent_at:))
    },
    owner_processes: map_processes,
    messages_handled: fn() { measurement.counter_value(handled) },
    memory_words: fn() {
      list.fold(map_processes(), 0, fn(words, pid) {
        words + result.unwrap(measurement.process_memory_words(pid), 0)
      })
    },
    stop: fn() { owner.stop_supervisor(supervisor) },
  )
}

/// Waits until a process other than `victim` holds the map's name and
/// answers a probe.
fn await_rebuilt(name: process.Name(Message), victim: Pid) -> Nil {
  case process.named(name) {
    Ok(pid) if pid != victim ->
      process.call(process.named_subject(name), 5000, Probe)
    Ok(_) | Error(Nil) -> await_rebuilt(name, victim)
  }
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  // A slice is counted by its thinks, in `think`, not as a message itself.
  case message {
    Slice -> Nil
    Move(..) | Attack(..) | Return(..) | Join(..) | Probe(..) ->
      measurement.increment(state.handled)
  }
  case message {
    Move(unit_id:, position:, sent_at:) ->
      actor.continue(move(state:, unit_id:, position:, sent_at:))
    Attack(attacker_id:, sent_at:) ->
      actor.continue(attack(state:, attacker_id:, sent_at:))
    Slice -> actor.continue(slice(state))
    Return(unit_id:) -> actor.continue(return(state, unit_id))
    Join(unit_id:, connection:) -> {
      process.send(connection, update.Joined(unit_id:))
      actor.continue(
        State(
          ..state,
          connections: dict.insert(state.connections, unit_id, connection),
        ),
      )
    }
    Probe(reply_with:) -> {
      process.send(reply_with, Nil)
      actor.continue(state)
    }
  }
}

fn unit_of(state: State, unit_id: Int) -> Unit {
  let assert Ok(unit) = dict.get(state.units, unit_id)
    as "the unit is not on the map"
  unit
}

/// Tells every other joined player in visibility range of the unit about each
/// effect, stamped with `sent_at`.
fn notify(
  state state: State,
  unit unit: Unit,
  effects effects: List(unit.Effect),
  sent_at sent_at: Int,
) -> Nil {
  case effects {
    [] -> Nil
    _ -> {
      let connections =
        grid.near(state.grid, unit.position, state.workload.visibility_range)
        |> list.filter_map(fn(unit_id) {
          case unit_id == unit.id {
            True -> Error(Nil)
            False -> dict.get(state.connections, unit_id)
          }
        })
      list.each(effects, fn(effect) {
        let delivery = update.Updated(update.from_effect(effect, sent_at))
        list.each(connections, fn(connection) {
          process.send(connection, delivery)
        })
      })
    }
  }
}

fn put(state: State, unit: Unit) -> State {
  State(
    ..state,
    units: dict.insert(state.units, unit.id, unit),
    grid: grid.move(state.grid, unit.id, unit.position),
  )
}

fn neighbours_near(
  state state: State,
  position position: Position,
  range range: Float,
) -> List(unit.Neighbour) {
  grid.near(state.grid, position, range)
  |> list.map(fn(unit_id) {
    let unit = unit_of(state, unit_id)
    unit.Neighbour(unit_id:, kind: unit.kind, position: unit.position)
  })
}

fn move(
  state state: State,
  unit_id unit_id: Int,
  position position: Position,
  sent_at sent_at: Int,
) -> State {
  let #(moved, effects) = unit.move(unit_of(state, unit_id), position)
  let state = put(state, moved)
  notify(state:, unit: moved, effects:, sent_at:)
  case state.planted {
    NoPlantedCost -> Nil
    ExtraGridLookupPerMove -> {
      let extra =
        grid.near(state.grid, moved.position, state.workload.visibility_range)
      assert list.length(extra) <= dict.size(state.units)
        as "a grid lookup holds each unit at most once"
    }
  }
  state
}

fn attack(
  state state: State,
  attacker_id attacker_id: Int,
  sent_at sent_at: Int,
) -> State {
  case dict.get(state.connections, attacker_id) {
    Error(Nil) -> state
    Ok(connection) -> {
      let attacker = unit_of(state, attacker_id)
      let target =
        unit.nearest(
          attacker.position,
          neighbours_near(
            state:,
            position: attacker.position,
            range: state.workload.visibility_range,
          ),
          unit.Creature,
        )
      case target {
        option.None -> state
        option.Some(target) ->
          strike(state:, connection:, target_id: target.unit_id, sent_at:)
      }
    }
  }
}

/// Hits a creature for an attacker: the observers are told, the attacker is
/// answered, and a creature that died is set to return.
fn strike(
  state state: State,
  connection connection: Subject(Delivery),
  target_id target_id: Int,
  sent_at sent_at: Int,
) -> State {
  let result =
    unit.hit(
      unit_of(state, target_id),
      state.workload.hit_damage,
      measurement.monotonic_microseconds(),
    )
  let state = put(state, result.unit)
  notify(state:, unit: result.unit, effects: result.effects, sent_at:)
  process.send(
    connection,
    update.Hit(update.HitReply(target_id:, outcome: result.outcome)),
  )
  case unit.died(result.effects) {
    True ->
      schedule(
        self: state.self,
        delay_milliseconds: unit.return_delay_microseconds / 1000,
        message: Return(unit_id: target_id),
      )
    False -> Nil
  }
  state
}

fn slice(state: State) -> State {
  schedule(
    self: state.self,
    delay_milliseconds: slice_interval_milliseconds,
    message: Slice,
  )
  let now = measurement.monotonic_microseconds()
  let unit_ids = dict.get(state.slices, state.next_slice) |> result.unwrap([])
  let state =
    list.fold(unit_ids, state, fn(state, unit_id) {
      think(state:, unit_id:, now:)
    })
  State(..state, next_slice: { state.next_slice + 1 } % think_slices)
}

fn think(state state: State, unit_id unit_id: Int, now now: Int) -> State {
  // Each creature's think counts as one message handled, as a think message
  // does in the one-process-per-unit prototype, so time per message compares.
  measurement.increment(state.handled)
  let creature = unit_of(state, unit_id)
  let target =
    unit.nearest(
      creature.position,
      neighbours_near(
        state:,
        position: creature.position,
        range: state.workload.aggro_range,
      ),
      unit.Player,
    )
    |> option.map(fn(neighbour) { neighbour.position })
  let #(thought, effects) =
    unit.think(creature, target, state.workload.creature_walk_speed, now)
  case effects {
    [] -> state
    _ -> {
      let state = put(state, thought)
      notify(state:, unit: thought, effects:, sent_at: now)
      state
    }
  }
}

fn return(state: State, unit_id: Int) -> State {
  let now = measurement.monotonic_microseconds()
  let #(returned, effects) = unit.return_if_due(unit_of(state, unit_id), now)
  let state = put(state, returned)
  case returned.status {
    unit.Dead(_) ->
      schedule(
        self: state.self,
        delay_milliseconds: 1,
        message: Return(unit_id:),
      )
    unit.Alive -> Nil
  }
  notify(state:, unit: returned, effects:, sent_at: now)
  state
}
