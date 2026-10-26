//// The top of the server's supervision tree. Every process the server runs
//// is started under it.

import gleam/otp/actor
import gleam/otp/static_supervisor.{type Builder, type Supervisor}

/// The top supervisor before any child is added: one for one, so a child that
/// fails is restarted alone, and 3 restarts in 5 seconds, the server's choice
/// for its top level: a fault that survives three rebuilds from storage in
/// that time is not transient, so the whole server stops and its caller sees
/// it. `start` starts it, and a test that plants children under the same
/// settings starts from it too.
pub fn supervisor() -> Builder {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
}

/// Starts the top supervisor. It has no children; each part of the server is
/// added here as a child, with its restart and shutdown settings.
pub fn start() -> Result(actor.Started(Supervisor), actor.StartError) {
  supervisor() |> static_supervisor.start
}
