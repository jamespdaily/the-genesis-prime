//// What a shell reads from the node each time it takes an input: the time, a
//// number for a new connection or recording, and the logger. It is the one
//// place a shell's rule inputs get their time and its log lines their
//// metadata, so the connection shell and the service shell take them alike.
//// It also holds what the two shells do alike when a recording cannot be
//// written or ended and when a rule returns an effect the shell does not carry
//// out, and the reason they give a process they end.

import genesis_prime/rule_recording/file.{type FileError, type Writer}
import genesis_prime/step.{type About, type LogLevel, type Now, LogError, Now}
import gleam/option.{type Option}

/// Why a process is asked to exit; the atom `shutdown`.
pub type ExitReason {
  Shutdown
}

/// The time as one input carries it: the monotonic clock in milliseconds and
/// the system time as a FILETIME, both read now.
pub fn now() -> Now {
  Now(monotonic_ms: monotonic_ms(), filetime: filetime())
}

/// A number that is not given again while the node runs, for a connection's
/// id and the name of its recording.
@external(erlang, "step_runtime_ffi", "unique_id")
pub fn unique_id() -> Int

/// Writes a log line through Erlang's logger, each known field of its who and
/// where as a metadata key of its own.
@external(erlang, "step_runtime_ffi", "log")
pub fn log(level: LogLevel, text: String, about: About) -> Nil

/// Logs that a step's input could not be recorded, which ends the process
/// before the step's effects, so no input is carried out without its record.
pub fn log_recording_failure(error: FileError) -> Nil {
  log(
    LogError,
    "the recording could not be written: " <> file.describe(error),
    step.no_one,
  )
}

/// Ends the recording of a process that is stopping. A recording that cannot
/// be ended is logged, since the process ends either way.
pub fn finish_recording(writer: Option(Writer)) -> Nil {
  case file.finish_if(writer) {
    Ok(Nil) -> Nil
    Error(error) ->
      log(
        LogError,
        "the recording could not be finished: " <> file.describe(error),
        step.no_one,
      )
  }
}

/// Logs that a rule returned something the named shell does not carry out and
/// ends the process.
pub fn unsupported(shell shell: String, what what: String) -> a {
  log(
    LogError,
    "a rule returned "
      <> what
      <> ", which the "
      <> shell
      <> " does not carry out",
    step.no_one,
  )
  panic as "a rule returned an effect the shell does not carry out"
}

/// Sets the logger's primary level to info, so the info lines the shells
/// write (start, stop, login, logout) are not dropped; OTP's own primary
/// level is notice. OTP's progress reports, which it logs at info for every
/// supervisor and child it starts, stay out.
@external(erlang, "step_runtime_ffi", "show_info_lines")
pub fn show_info_lines() -> Nil

@external(erlang, "step_runtime_ffi", "monotonic_ms")
fn monotonic_ms() -> Int

@external(erlang, "step_runtime_ffi", "filetime")
fn filetime() -> Int
