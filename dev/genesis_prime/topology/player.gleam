//// One simulated player: a process that sends its unit's moves and attacks
//// through an `Owner`, counts what comes back and records how long each move
//// took to reach it.

import genesis_prime/topology/latency.{type Histogram}
import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/unit.{type Unit}
import genesis_prime/topology/update.{type Delivery}
import genesis_prime/topology/workload.{type Workload}
import gleam/erlang/process.{type Subject}
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

/// The state of a player process: its unit, where its random walk is centred,
/// the owner once begun, and what it has counted.
pub type State {
  State(
    unit: Unit,
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
pub fn start(workload: Workload, unit: Unit) -> actor.StartResult(Player) {
  todo as "body in the build commit"
}

/// A supervisor builder that starts players, one per unit given to it. A
/// player that crashes is restarted at its unit's spawn position.
pub fn factory(workload: Workload) -> factory_supervisor.Builder(Unit, Player) {
  todo as "body in the build commit"
}

/// Tells a player to join its connection through an owner, then start moving
/// and attacking through it.
pub fn begin(player: Player, owner: Owner) -> Nil {
  todo as "body in the build commit"
}

/// Asks a player for its counts, waiting up to `waiting` milliseconds; a
/// player that does not answer crashes the asker.
pub fn report(player: Player, waiting waiting: Int) -> Report {
  todo as "body in the build commit"
}
