//// Prototype B: one process owns every unit of the map, with a grid index in
//// its state. Moves and attacks are messages to it, and it thinks for the
//// creatures itself, a tenth of them every 100 milliseconds, so each creature
//// thinks once a second.
////
//// The supervision tree is one supervisor with one child, the map process,
//// registered under a name made for the run. The map process is rebuilt from
//// the spawn list kept in the persistent term named by the start argument,
//// so a crash loses the whole map until the rebuild is done: every player
//// sees every unit stop, and each player's connection must join again.

import genesis_prime/topology/grid.{type Grid}
import genesis_prime/topology/measurement.{type Counter}
import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/position.{type Position}
import genesis_prime/topology/unit.{type Unit}
import genesis_prime/topology/update.{type Delivery}
import genesis_prime/topology/workload.{type Workload}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/erlang/reference.{type Reference}
import gleam/otp/actor

/// How many restarts the supervisor allows in `restart_period_seconds`.
pub const restart_intensity = 3

/// The period of the supervisor's restart limit, in seconds.
pub const restart_period_seconds = 5

/// How long the map process has to stop when told to, in milliseconds.
pub const shutdown_milliseconds = 5000

/// How many parts the creatures' think is divided into, one part every
/// 100 milliseconds.
pub const think_slices = 10

/// A cost planted in the prototype to show that the harness can see one.
pub type PlantedCost {
  /// The prototype as it is.
  NoPlantedCost
  /// One more grid-cell lookup on every move.
  ExtraGridLookupPerMove
}

/// Every message the map process can receive. Its selector covers all of
/// them; anything else is logged.
pub type Message {
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
pub type State {
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

/// Starts the prototype: the supervisor and the map process, built from the
/// spawn list kept under `spawn_list_key`. Players' connections join
/// afterwards through the `Owner`. The supervisor is linked to the calling
/// process; the data is the `Owner` the players act through.
pub fn start(
  workload: Workload,
  spawn_list_key: Reference,
  planted: PlantedCost,
) -> Result(actor.Started(Owner), actor.StartError) {
  todo as "body in the build commit"
}

/// Kills the map process and returns the microseconds until the rebuilt
/// process handles a message again. It starts its own prototype with no
/// players from the spawn list kept under `spawn_list_key` and stops it.
pub fn crash_cost(
  workload: Workload,
  spawn_list_key: Reference,
  planted: PlantedCost,
) -> Int {
  todo as "body in the build commit"
}
