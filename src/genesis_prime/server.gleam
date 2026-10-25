//// The top of the server's supervision tree. Every process the server runs
//// is started under it.

import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}

/// Starts the top supervisor. It has no children; each part of the server is
/// added here as a child, with its restart and shutdown settings.
///
/// A child that fails is restarted alone. The supervisor allows 3 restarts in
/// 5 seconds, the server's choice for its top level: a fault that survives
/// three rebuilds from storage in that time is not transient, so the whole
/// server stops and its caller sees it.
pub fn start() -> Result(actor.Started(Supervisor), actor.StartError) {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
  |> static_supervisor.start
}
