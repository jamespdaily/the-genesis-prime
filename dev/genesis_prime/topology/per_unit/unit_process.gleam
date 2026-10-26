//// One unit of the one-process-per-unit prototype: a creature or a player's
//// character that is a process of its own. It writes only its own rows in the
//// shared table, changes only on a message and tells the players in range
//// what happened. A creature thinks on a timer of its own, once a second,
//// from a random phase.
////
//// A restart rebuilds the unit from the spawn list kept in the persistent
//// term named by the start argument; nothing else is kept.

import genesis_prime/topology/measurement.{type Counter}
import genesis_prime/topology/per_unit/table.{type Table}
import genesis_prime/topology/per_unit/table_owner
import genesis_prime/topology/position.{type Position}
import genesis_prime/topology/unit.{type Unit}
import genesis_prime/topology/update.{type Delivery}
import genesis_prime/topology/workload.{type Workload}
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/result

/// How long a creature waits between thinks, in milliseconds.
const think_interval_milliseconds = 1000

/// Every message a unit process can receive. Its selector covers all of them;
/// anything else is logged.
pub type Message {
  /// A player moves this unit: the position and the time the move was sent.
  Move(position: Position, sent_at: Int)
  /// This player's unit hits the nearest creature in visibility range, found
  /// by reading the table, and the creature is told by message.
  Attack(sent_at: Int)
  /// This unit is hit: the damage, where to send the outcome and the time the
  /// attack was sent.
  Hit(damage: Int, reply_to: Subject(Delivery), sent_at: Int)
  /// The creature's timer for its next think is due.
  Think
  /// The unit's return time has come.
  Return
  /// A player's connection joins this unit, and goes in its row.
  Join(connection: Subject(Delivery))
  /// Asks the process to answer, to show that it handles messages.
  Probe(reply_with: Subject(Nil))
}

/// What every unit process shares and none changes: the run's settings, where
/// the spawn list is kept, the table and its owner, and the count of messages
/// handled.
pub type Shared {
  Shared(
    workload: Workload,
    spawn_list_key: Reference,
    table: Table(Message),
    table_owner: Subject(table_owner.Message),
    handled: Counter,
  )
}

/// The argument a unit process is started with, and restarted with: its unit
/// and the shared data.
pub type Start {
  Start(unit_id: Int, shared: Shared)
}

/// The state of a unit process: its unit, its player's connection once one
/// has joined (none for a creature), and its own mailbox for the timers it
/// sets. A restart loses the connection, so the player must join again.
type State {
  State(
    unit: Unit,
    connection: Option(Subject(Delivery)),
    start: Start,
    self: Subject(Message),
  )
}

/// Starts a unit process: it reads its unit from the spawn list, writes its
/// rows, asks the table owner to watch it and, for a creature, sets its first
/// think after a random delay under one second.
fn start(start: Start) -> actor.StartResult(Subject(Message)) {
  actor.new_with_initialiser(5000, fn(self) {
    let shared = start.shared
    use unit <- result.try(
      measurement.spawn_list(shared.spawn_list_key)
      |> dict.get(start.unit_id)
      |> result.replace_error("the unit is not in the spawn list"),
    )
    let state = State(unit:, connection: option.None, start:, self:)
    write_row(state)
    process.send(
      shared.table_owner,
      table_owner.Track(unit_id: unit.id, owner: process.self()),
    )
    case unit.kind {
      unit.Creature ->
        schedule(
          self:,
          delay_milliseconds: int.random(think_interval_milliseconds),
          message: Think,
        )
      unit.Player -> Nil
    }
    actor.initialised(state)
    |> actor.returning(self)
    |> Ok
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// A supervisor builder that starts unit processes, one per `Start`, each
/// restarted from the spawn list when it crashes.
pub fn factory() -> factory_supervisor.Builder(Start, Subject(Message)) {
  factory_supervisor.worker_child(start)
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
  measurement.increment(state.start.shared.handled)
  case message {
    Move(position:, sent_at:) ->
      actor.continue(move(state:, position:, sent_at:))
    Attack(sent_at:) -> {
      attack(state:, sent_at:)
      actor.continue(state)
    }
    Hit(damage:, reply_to:, sent_at:) ->
      actor.continue(be_hit(state:, damage:, reply_to:, sent_at:))
    Think -> actor.continue(think(state))
    Return -> actor.continue(return(state))
    Join(connection:) -> {
      let state = State(..state, connection: option.Some(connection))
      write_row(state)
      process.send(connection, update.Joined(unit_id: state.unit.id))
      actor.continue(state)
    }
    Probe(reply_with:) -> {
      process.send(reply_with, Nil)
      actor.continue(state)
    }
  }
}

fn cell_size(state: State) -> Float {
  state.start.shared.workload.visibility_range
}

/// Writes the unit's rows in the shared table, as they stand in its state.
fn write_row(state: State) -> Nil {
  table.write(
    state.start.shared.table,
    table.Row(
      unit_id: state.unit.id,
      kind: state.unit.kind,
      position: state.unit.position,
      owner: state.self,
      connection: state.connection,
    ),
    cell_size(state),
  )
}

/// Tells every other player in visibility range of `position` about each
/// effect, stamped with `sent_at`.
fn notify(
  state state: State,
  position position: Position,
  effects effects: List(unit.Effect),
  sent_at sent_at: Int,
) -> Nil {
  case effects {
    [] -> Nil
    _ -> {
      let shared = state.start.shared
      let connections =
        table.near(
          table: shared.table,
          centre: position,
          range: shared.workload.visibility_range,
          cell_size: cell_size(state),
          kind: unit.Player,
        )
        |> list.filter_map(fn(row) {
          case row.connection {
            option.Some(connection) if row.unit_id != state.unit.id ->
              Ok(connection)
            option.Some(_) | option.None -> Error(Nil)
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

fn move(
  state state: State,
  position position: Position,
  sent_at sent_at: Int,
) -> State {
  let #(moved, effects) = unit.move(state.unit, position)
  let state = State(..state, unit: moved)
  write_row(state)
  notify(state:, position: moved.position, effects:, sent_at:)
  state
}

fn attack(state state: State, sent_at sent_at: Int) -> Nil {
  case state.connection {
    option.None -> Nil
    option.Some(connection) ->
      hit_nearest_creature(state:, connection:, sent_at:)
  }
}

fn hit_nearest_creature(
  state state: State,
  connection connection: Subject(Delivery),
  sent_at sent_at: Int,
) -> Nil {
  let shared = state.start.shared
  let rows =
    table.near(
      table: shared.table,
      centre: state.unit.position,
      range: shared.workload.visibility_range,
      cell_size: cell_size(state),
      kind: unit.Creature,
    )
  let neighbours =
    list.map(rows, fn(row) {
      unit.Neighbour(
        unit_id: row.unit_id,
        kind: row.kind,
        position: row.position,
      )
    })
  let target =
    unit.nearest(state.unit.position, neighbours, unit.Creature)
    |> option.to_result(Nil)
    |> result.try(fn(target) {
      list.find(rows, fn(row) { row.unit_id == target.unit_id })
    })
  case target {
    Ok(row) ->
      process.send(
        row.owner,
        Hit(damage: shared.workload.hit_damage, reply_to: connection, sent_at:),
      )
    Error(Nil) -> Nil
  }
}

fn be_hit(
  state state: State,
  damage damage: Int,
  reply_to reply_to: Subject(Delivery),
  sent_at sent_at: Int,
) -> State {
  let result =
    unit.hit(state.unit, damage, measurement.monotonic_microseconds())
  let state = State(..state, unit: result.unit)
  notify(
    state:,
    position: state.unit.position,
    effects: result.effects,
    sent_at:,
  )
  process.send(
    reply_to,
    update.Hit(update.HitReply(
      target_id: state.unit.id,
      outcome: result.outcome,
    )),
  )
  case unit.died(result.effects) {
    True ->
      schedule(
        self: state.self,
        delay_milliseconds: unit.return_delay_microseconds / 1000,
        message: Return,
      )
    False -> Nil
  }
  state
}

fn think(state: State) -> State {
  let shared = state.start.shared
  schedule(
    self: state.self,
    delay_milliseconds: think_interval_milliseconds,
    message: Think,
  )
  let now = measurement.monotonic_microseconds()
  let neighbours =
    table.near(
      table: shared.table,
      centre: state.unit.position,
      range: shared.workload.aggro_range,
      cell_size: cell_size(state),
      kind: unit.Player,
    )
    |> list.map(fn(row) {
      unit.Neighbour(
        unit_id: row.unit_id,
        kind: row.kind,
        position: row.position,
      )
    })
  let target =
    unit.nearest(state.unit.position, neighbours, unit.Player)
    |> option.map(fn(neighbour) { neighbour.position })
  let #(thought, effects) =
    unit.think(state.unit, target, shared.workload.creature_walk_speed, now)
  let state = State(..state, unit: thought)
  case effects {
    [] -> Nil
    _ -> {
      write_row(state)
      notify(state:, position: thought.position, effects:, sent_at: now)
    }
  }
  state
}

fn return(state: State) -> State {
  let now = measurement.monotonic_microseconds()
  let #(returned, effects) = unit.return_if_due(state.unit, now)
  let state = State(..state, unit: returned)
  case returned.status {
    unit.Dead(_) ->
      schedule(self: state.self, delay_milliseconds: 1, message: Return)
    unit.Alive -> Nil
  }
  notify(state:, position: returned.position, effects:, sent_at: now)
  state
}
