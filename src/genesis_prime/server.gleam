//// The top of the server's supervision tree. Every process the server runs
//// is started under it.

import genesis_prime/database/pool
import gleam/otp/actor
import gleam/otp/static_supervisor.{type Builder, type Supervisor}

/// The top supervisor before any child is added: one for one, so a child that
/// fails is restarted alone, and 3 restarts in 5 seconds, the server's choice
/// for its top level: a fault that survives three rebuilds from storage in
/// that time is not transient, so the whole server stops and its caller sees
/// it. A test that plants children under the same settings starts from it.
pub fn supervisor() -> Builder {
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
}

/// The top supervisor with the database pool as its first child, so the pool
/// starts before every child added after it and stops after them. A rebuilt
/// pool keeps the name in `pool_settings`, so a child that queries through
/// that name carries on across a restart. `start` starts it, and a test that
/// plants children after the pool starts from it.
pub fn supervisor_with_pool(pool_settings: pool.Settings) -> Builder {
  todo as "the top supervisor with the pool as its first child"
}

/// Starts the top supervisor with the database pool and every other child
/// the server runs, each added here with its restart and shutdown settings.
/// The pool is given by `pool_settings`; it opens its connections in the
/// background, so the tree starts whether or not Postgres is reachable.
pub fn start(
  pool_settings: pool.Settings,
) -> Result(actor.Started(Supervisor), actor.StartError) {
  supervisor_with_pool(pool_settings) |> static_supervisor.start
}
