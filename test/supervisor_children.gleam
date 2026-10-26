//// Reads the order a running supervisor started its children in, so a test
//// checks the running tree and not the code that built it.

import gleam/erlang/process.{type Pid}

/// The pids of the running children of the supervisor with this pid, in the
/// order they were started. A child that is not running is left out.
@external(erlang, "supervisor_children_ffi", "in_start_order")
pub fn in_start_order(supervisor: Pid) -> List(Pid)
