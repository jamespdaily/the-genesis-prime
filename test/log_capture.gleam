//// Reads what one process logs through Erlang's logger, so a test sees the
//// error a process logged before it ended, and the logger's primary level.

import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid, type Subject}

/// A running capture; `stop` removes it.
pub type Capture

/// Sends each log line the process `from` writes to `into`, as its level in
/// lower case and its text.
@external(erlang, "log_capture_ffi", "start")
pub fn start(from from: Pid, into into: Subject(#(String, String))) -> Capture

/// Stops the capture.
@external(erlang, "log_capture_ffi", "stop")
pub fn stop(capture: Capture) -> Nil

/// The logger's primary level: the lowest level it lets through.
@external(erlang, "log_capture_ffi", "primary_level")
pub fn primary_level() -> Atom

/// Sets the logger's primary level, for a test that restores what it found.
@external(erlang, "log_capture_ffi", "set_primary_level")
pub fn set_primary_level(level: Atom) -> Nil

/// Logs one progress report, as a supervisor does when it starts a child.
@external(erlang, "log_capture_ffi", "log_progress_report")
pub fn log_progress_report() -> Nil

/// Removes the filter the server's start adds against progress reports, for a
/// test that restores what it found.
@external(erlang, "log_capture_ffi", "remove_progress_filter")
pub fn remove_progress_filter() -> Nil
