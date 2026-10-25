//// The top of the server's supervision tree. Every process the server runs
//// is started under it.

import gleam/otp/actor
import gleam/otp/static_supervisor.{type Supervisor}

/// Starts the top supervisor. It has no children; each part of the server is
/// added here as a child, with its restart and shutdown settings.
pub fn start() -> Result(actor.Started(Supervisor), actor.StartError) {
  todo as "body in the build commit"
}
