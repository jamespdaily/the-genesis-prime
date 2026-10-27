//// What a shell reads from the node each time it takes an input: the time, a
//// number for a new connection or recording, and the logger. It is the one
//// place a shell's rule inputs get their time and its log lines their
//// metadata, so the connection shell and the service shell take them alike.

import genesis_prime/step.{type About, type LogLevel, type Now, Now}

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

/// Sets the logger's primary level to info, so the info lines the shells
/// write (start, stop, login, logout) are not dropped; OTP's own primary
/// level is notice.
@external(erlang, "step_runtime_ffi", "show_info_lines")
pub fn show_info_lines() -> Nil

@external(erlang, "step_runtime_ffi", "monotonic_ms")
fn monotonic_ms() -> Int

@external(erlang, "step_runtime_ffi", "filetime")
fn filetime() -> Int
