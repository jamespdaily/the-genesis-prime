//// What a shell reads from the node each time it takes an input: the time, a
//// number for a new connection or recording, and the logger. It is the one
//// place a shell's rule inputs get their time and its log lines their
//// metadata, so the connection shell and the service shell take them alike.
//// It also holds what the two shells do alike when a recording cannot be
//// written or ended, and the reason they give a process they end.

import genesis_prime/rule_recording/file.{type FileError, type Writer}
import genesis_prime/step.{type About, type LogLevel, type Now, LogError, Now}
import genesis_prime/wire_recording.{type Side}
import genesis_prime/wire_recording/recorder.{type WireWriter, type WriteError}
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/option.{type Option}

/// Why a process is asked to exit; the atom `shutdown`.
pub type ExitReason {
  Shutdown
}

/// Raises the exit that ends this process with `reason`; a process that traps
/// exits is not ended by an exit signal it sends itself.
@external(erlang, "erlang", "exit")
pub fn exit_now(reason: ExitReason) -> a

/// Why a monitored process or port ended.
pub fn down_reason(down: process.Down) -> process.ExitReason {
  case down {
    process.ProcessDown(reason:, ..) | process.PortDown(reason:, ..) -> reason
  }
}

/// The monitor of a monitored process or port that ended.
pub fn down_monitor(down: process.Down) -> process.Monitor {
  case down {
    process.ProcessDown(monitor:, ..) | process.PortDown(monitor:, ..) ->
      monitor
  }
}

/// The time as one input carries it: the monotonic clock in milliseconds and
/// the system time as a FILETIME, both read now.
pub fn now() -> Now {
  Now(monotonic_ms: monotonic_ms(), filetime: filetime())
}

/// A number that is not given again while the node runs and that grows with
/// each call, for a connection's id, the name of its recording and the sequence
/// number of each line of a wire recording, which orders the lines of every
/// connection of the node.
@external(erlang, "step_runtime_ffi", "unique_id")
pub fn unique_id() -> Int

/// Writes a log line through Erlang's logger, each known field of its who and
/// where as a metadata key of its own.
@external(erlang, "step_runtime_ffi", "log")
pub fn log(level: LogLevel, text: String, about: About) -> Nil

/// Sets the logger metadata of the calling process from the fields of `about`
/// that are known, so every line the process logs carries them, those of
/// OTP and gleam_otp (a crash report, a dropped stray message) as well as the
/// shell's own; a line's own `about` is added over them.
@external(erlang, "step_runtime_ffi", "set_about")
pub fn set_about(about: About) -> Nil

/// Logs at warning that the shell named `shell` dropped a message it does not
/// take. The line names the message's kind, its tag or its shape, and never
/// its contents, which could hold a secret.
@external(erlang, "step_runtime_ffi", "log_stray")
pub fn log_stray(message message: Dynamic, shell shell: String) -> Nil

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

/// Logs that a read or a write of the socket could not be recorded, which ends
/// the process before the input is taken or the next effect is carried out.
pub fn log_wire_recording_failure(error: WriteError) -> Nil {
  log(
    LogError,
    "the wire recording could not be written: " <> recorder.describe(error),
    step.no_one,
  )
}

/// Ends the wire recording of a process that is stopping, with the side that
/// closed the connection. A recording that cannot be ended is logged, since the
/// process ends either way.
pub fn finish_wire_recording(
  writer writer: Option(WireWriter),
  by by: Side,
) -> Nil {
  case recorder.close_if(writer:, sequence: unique_id(), by:) {
    Ok(Nil) -> Nil
    Error(error) ->
      log(
        LogError,
        "the wire recording could not be finished: " <> recorder.describe(error),
        step.no_one,
      )
  }
}

/// Sets the logger's primary level to info, so the info lines the shells
/// write (start, stop, login, logout) are not dropped; OTP's own primary
/// level is notice. OTP's progress reports, which it logs at info for every
/// supervisor and child it starts, stay out.
@external(erlang, "step_runtime_ffi", "show_info_lines")
pub fn show_info_lines() -> Nil

/// Keeps what waits in a process's mailbox out of the log: a primary logger
/// filter takes the `messages` out of every crash report OTP writes for a
/// process that ends abnormally, so a message that holds a secret and waits
/// when the process crashes never reaches the log.
@external(erlang, "step_runtime_ffi", "keep_mailboxes_out_of_crash_reports")
pub fn keep_mailboxes_out_of_crash_reports() -> Nil

/// The node's monotonic clock in milliseconds, read now. A wait on real time
/// counts from it; the time an input carries comes from the connection's script
/// (`now` in the server).
@external(erlang, "step_runtime_ffi", "monotonic_ms")
pub fn monotonic_ms() -> Int

@external(erlang, "step_runtime_ffi", "filetime")
fn filetime() -> Int
