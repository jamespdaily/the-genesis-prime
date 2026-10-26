//// Waits for a database pool to have finished starting, so a test that stops
//// the server stops a pool that is running and not one still opening its
//// connections. `pgo`, which `pog` runs the pool on, reports a pool that is
//// stopped while it starts as errors of its own supervisors
//// (`pgo_connection_starter.erl`: the starter opens every connection and
//// loads the types in its first event, and a stop that arrives meanwhile ends
//// it with the exit of the call it was making; `pgo_connection_sup.erl`: a
//// connection that is still opening is killed after 100 ms).

import gleam/erlang/process.{type Name}
import pog

/// Whether the pool registered as `name` has started within `within_ms`
/// milliseconds: its starter has started every connection and loaded the
/// types, and each connection has finished opening. A pool whose database is
/// away has not started, however long it waits.
@external(erlang, "pool_started_ffi", "await")
pub fn await(name name: Name(pog.Message), within_ms within_ms: Int) -> Bool
