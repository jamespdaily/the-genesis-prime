//// Captures what a process logs through Erlang's logger, so a test checks
//// the line a process wrote and not only that it ended.

import gleam/erlang/process.{type Pid}

/// The level of a log line.
pub type Level {
  InfoLevel
  WarningLevel
  ErrorLevel
  OtherLevel
}

/// A log line: its level and its text.
pub type Line {
  Line(level: Level, message: String)
}

/// Starts forwarding every log event to the calling process. The forwarding
/// stops when the calling process ends.
@external(erlang, "log_capture_ffi", "start")
pub fn start() -> Nil

/// Waits up to `within_ms` for the next line logged by the process, skipping
/// lines of other processes.
pub fn await(pid pid: Pid, within_ms within_ms: Int) -> Result(Line, Nil) {
  case await_event(pid, within_ms) {
    Ok(#(level, message)) -> Ok(Line(level:, message:))
    Error(Nil) -> Error(Nil)
  }
}

@external(erlang, "log_capture_ffi", "await")
fn await_event(pid: Pid, within_ms: Int) -> Result(#(Level, String), Nil)
