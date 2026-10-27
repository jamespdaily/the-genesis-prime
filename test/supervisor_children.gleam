//// Reads the order a running supervisor started its children in, so a test
//// checks the running tree and not the code that built it.

import gleam/erlang/process.{type Pid}
import gleam/option.{type Option}
import gleam/otp/supervision.{type Restart}

/// The pids of the running children of the supervisor with this pid, in the
/// order they were started. A child that is not running is left out.
@external(erlang, "supervisor_children_ffi", "in_start_order")
pub fn in_start_order(supervisor: Pid) -> List(Pid)

/// A running child's restart setting and its shutdown time in milliseconds,
/// `None` for no limit.
pub type ChildSettings {
  ChildSettings(restart: Restart, shutdown_ms: Option(Int))
}

/// The settings of the running supervisor's children, in the order they were
/// started, as the supervisor holds them.
@external(erlang, "supervisor_children_ffi", "settings_in_start_order")
pub fn settings_in_start_order(supervisor: Pid) -> List(ChildSettings)
