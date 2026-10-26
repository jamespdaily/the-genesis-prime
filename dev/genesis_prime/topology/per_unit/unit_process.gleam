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
import gleam/erlang/process.{type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/otp/factory_supervisor

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
pub type State {
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
pub fn start(start: Start) -> actor.StartResult(Subject(Message)) {
  todo as "body in the build commit"
}

/// A supervisor builder that starts unit processes, one per `Start`, each
/// restarted from the spawn list when it crashes.
pub fn factory() -> factory_supervisor.Builder(Start, Subject(Message)) {
  todo as "body in the build commit"
}
