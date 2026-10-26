//// One simulated player: a process that sends its unit's moves and attacks
//// through an `Owner`, counts what comes back and records how long each move
//// took to reach it.

import genesis_prime/topology/latency.{type Histogram}
import genesis_prime/topology/measurement
import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/position.{type Position, Position}
import genesis_prime/topology/unit.{type Unit}
import genesis_prime/topology/update.{type Delivery}
import genesis_prime/topology/workload.{type Workload}
import gleam/erlang/process.{type Subject}
import gleam/float
import gleam/int
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/factory_supervisor

/// Every message a player process can receive. Its selector covers all of
/// them; anything else is logged.
pub type Message {
  /// Starts the player's timers and gives it the owner to act through.
  Begin(owner: Owner)
  /// The timer for the next move is due.
  MoveDue
  /// The timer for the next attack is due.
  AttackDue
  /// Something arrived on the player's connection.
  Delivered(Delivery)
  /// Sets the counts back to 0, so that a count covers only what follows.
  ResetCounts
  /// Asks the player for its counts.
  ReportTo(reply_with: Subject(Report))
}

/// What a player counted: moves it sent, updates and hit answers it received,
/// and how long each move update took from the send to the arrival.
pub type Report {
  Report(
    moves_sent: Int,
    updates_received: Int,
    hit_replies_received: Int,
    latency: Histogram,
  )
}

/// A running player: where to send it messages, and the connection a
/// prototype sends it updates on once the player has joined.
pub type Player {
  Player(unit_id: Int, control: Subject(Message), connection: Subject(Delivery))
}

/// The state of a player process: its unit as it spawned, which is where its
/// walk is centred, its connection, the owner once begun, and what it has
/// counted.
type State {
  State(
    unit: Unit,
    connection: Subject(Delivery),
    workload: Workload,
    owner: Option(Owner),
    moves_sent: Int,
    updates_received: Int,
    hit_replies_received: Int,
    latency: Histogram,
    self: Subject(Message),
  )
}

/// Starts a player for a unit. It sends nothing until it is begun.
fn start(
  workload workload: Workload,
  unit unit: Unit,
) -> actor.StartResult(Player) {
  actor.new_with_initialiser(5000, fn(control) {
    let connection = process.new_subject()
    let selector =
      process.new_selector()
      |> process.select(control)
      |> process.select_map(connection, Delivered)
    actor.initialised(State(
      unit:,
      connection:,
      workload:,
      owner: option.None,
      moves_sent: 0,
      updates_received: 0,
      hit_replies_received: 0,
      latency: latency.new(),
      self: control,
    ))
    |> actor.selecting(selector)
    |> actor.returning(Player(unit_id: unit.id, control:, connection:))
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// A supervisor builder that starts players, one per unit given to it. A
/// player that crashes is restarted at its unit's spawn position.
pub fn factory(workload: Workload) -> factory_supervisor.Builder(Unit, Player) {
  factory_supervisor.worker_child(fn(unit) { start(workload:, unit:) })
}

/// Tells a player to join its connection through an owner, then start moving
/// and attacking through it.
pub fn begin(player player: Player, owner owner: Owner) -> Nil {
  process.send(player.control, Begin(owner:))
}

/// Sets a player's counts back to 0, so that its report covers only what
/// follows.
pub fn reset_counts(player: Player) -> Nil {
  process.send(player.control, ResetCounts)
}

/// Asks a player for its counts, waiting up to `waiting` milliseconds; a
/// player that does not answer crashes the asker.
pub fn report(player player: Player, waiting waiting: Int) -> Report {
  process.call(player.control, waiting, ReportTo)
}

fn schedule(
  self self: Subject(Message),
  delay_milliseconds delay_milliseconds: Int,
  message message: Message,
) -> Nil {
  let _timer = process.send_after(self, delay_milliseconds, message)
  Nil
}

fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    Begin(owner:) -> {
      owner.join(state.unit.id, state.connection)
      let interval = move_interval_milliseconds(state.workload)
      schedule(
        self: state.self,
        delay_milliseconds: int.random(interval) + 1,
        message: MoveDue,
      )
      schedule(
        self: state.self,
        delay_milliseconds: int.random(attack_interval_milliseconds) + 1,
        message: AttackDue,
      )
      actor.continue(State(..state, owner: option.Some(owner)))
    }
    MoveDue ->
      case state.owner {
        option.Some(owner) -> {
          let moves_sent = state.moves_sent + 1
          owner.move(
            state.unit.id,
            walk_position(
              spawn: state.unit.position,
              moves_sent:,
              workload: state.workload,
            ),
            measurement.monotonic_microseconds(),
          )
          schedule(
            self: state.self,
            delay_milliseconds: move_interval_milliseconds(state.workload),
            message: MoveDue,
          )
          actor.continue(State(..state, moves_sent:))
        }
        option.None -> actor.continue(state)
      }
    AttackDue ->
      case state.owner {
        option.Some(owner) -> {
          owner.attack_nearest_creature(
            state.unit.id,
            measurement.monotonic_microseconds(),
          )
          schedule(
            self: state.self,
            delay_milliseconds: attack_interval_milliseconds,
            message: AttackDue,
          )
          actor.continue(state)
        }
        option.None -> actor.continue(state)
      }
    Delivered(delivery) -> actor.continue(receive(state, delivery))
    ResetCounts ->
      actor.continue(
        State(
          ..state,
          moves_sent: 0,
          updates_received: 0,
          hit_replies_received: 0,
          latency: latency.new(),
        ),
      )
    ReportTo(reply_with:) -> {
      process.send(
        reply_with,
        Report(
          moves_sent: state.moves_sent,
          updates_received: state.updates_received,
          hit_replies_received: state.hit_replies_received,
          latency: state.latency,
        ),
      )
      actor.continue(state)
    }
  }
}

/// How long a player waits between two moves, in milliseconds.
fn move_interval_milliseconds(workload: Workload) -> Int {
  int.max(1, 1000 / int.max(1, workload.moves_per_second))
}

/// How long a player waits between two attacks, in milliseconds.
const attack_interval_milliseconds = 1000

/// Where the player's unit stands after `moves_sent` moves: it walks at its
/// run speed around the sides of a square, starting at its spawn position, the
/// square's south-west corner. The square's side is half the cluster's
/// radius, so the walk stays inside the cluster.
fn walk_position(
  spawn spawn: Position,
  moves_sent moves_sent: Int,
  workload workload: Workload,
) -> Position {
  let side = workload.cluster_radius /. 2.0
  let step =
    workload.player_run_speed
    /. int.to_float(int.max(1, workload.moves_per_second))
  let travelled = int.to_float(moves_sent) *. step
  let around =
    travelled -. float.floor(travelled /. { 4.0 *. side }) *. 4.0 *. side
  let side_number = float.truncate(around /. side)
  let along = around -. int.to_float(side_number) *. side
  let offset = case side_number {
    0 -> Position(x: along, y: 0.0)
    1 -> Position(x: side, y: along)
    2 -> Position(x: side -. along, y: side)
    _ -> Position(x: 0.0, y: side -. along)
  }
  Position(
    x: float.clamp(spawn.x +. offset.x, min: 0.0, max: workload.map_size),
    y: float.clamp(spawn.y +. offset.y, min: 0.0, max: workload.map_size),
  )
}

/// Counts what arrived on the connection, and for a move of a player's unit
/// records how long it took.
fn receive(state: State, delivery: Delivery) -> State {
  case delivery {
    update.Updated(update.Moved(unit_id:, sent_at:, ..))
      if unit_id <= state.workload.players
    ->
      State(
        ..state,
        updates_received: state.updates_received + 1,
        latency: latency.record(
          state.latency,
          measurement.monotonic_microseconds() - sent_at,
        ),
      )
    update.Updated(_) ->
      State(..state, updates_received: state.updates_received + 1)
    update.Hit(_) ->
      State(..state, hit_replies_received: state.hit_replies_received + 1)
    update.Joined(_) -> state
  }
}
