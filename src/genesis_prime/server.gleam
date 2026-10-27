//// The server's supervision tree. Each part of the server is added as a
//// child, in the order it starts; children stop in the reverse order, so
//// what starts first stops last.

import gleam/otp/actor
import gleam/otp/static_supervisor as supervisor

/// Starts the tree. A child that fails three times in ten seconds does not
/// recover by restarting, so the tree gives up, the node stops, and the
/// host starts it again.
pub fn start() -> actor.StartResult(supervisor.Supervisor) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.restart_tolerance(intensity: 3, period: 10)
  |> supervisor.start
}
