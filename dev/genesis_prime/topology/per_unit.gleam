//// Prototype A: every creature and every player's unit is a process of its
//// own, with its position in a shared ETS table that other processes read to
//// find who is near.
////
//// The supervision tree is one supervisor with two children, started in this
//// order and restarted together (rest for one): the table owner, which owns
//// the table and cleans up after dead units, and a factory supervisor of
//// unit processes. A unit process that crashes is restarted alone from the
//// spawn list and writes its rows again; its players see it vanish and
//// reappear. A table owner that crashes loses every row, and nothing
//// rebuilds the units already running, so a run in which it crashed is
//// discarded.

import genesis_prime/topology/owner.{type Owner}
import genesis_prime/topology/workload.{type Workload}
import gleam/erlang/reference.{type Reference}
import gleam/otp/actor

/// How many restarts the top supervisor allows in `restart_period_seconds`.
pub const restart_intensity = 100

/// The period of the top supervisor's restart limit, in seconds.
pub const restart_period_seconds = 5

/// How long a unit process has to stop when told to, in milliseconds.
pub const unit_shutdown_milliseconds = 1000

/// Starts the prototype: the table owner, the unit supervisor and one unit
/// process for every unit of the spawn list kept under `spawn_list_key`.
/// Players' connections join afterwards through the `Owner`. The supervisor
/// is linked to the calling process; the data is the `Owner` the players act
/// through.
pub fn start(
  workload: Workload,
  spawn_list_key: Reference,
) -> Result(actor.Started(Owner), actor.StartError) {
  todo as "body in the build commit"
}

/// Kills one creature's process and returns the microseconds until the
/// rebuilt process handles a message again. It starts its own prototype with
/// no players from the spawn list kept under `spawn_list_key` and stops it.
pub fn crash_cost(workload: Workload, spawn_list_key: Reference) -> Int {
  todo as "body in the build commit"
}
