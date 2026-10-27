//// Reads what one process logs through Erlang's logger, so a test sees the
//// error a process logged before it ended.

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
