//// Reads a running supervisor's own settings, so a test checks what the
//// supervisor holds and not what the code that built it says.

import gleam/erlang/process.{type Pid}
import gleam/otp/static_supervisor.{type Strategy}

/// A supervisor's restart strategy, its restart intensity (the restarts it
/// allows) and its period (the seconds those restarts must fall in).
pub type Flags {
  Flags(strategy: Strategy, intensity: Int, period: Int)
}

/// The flags of the running supervisor with this pid. It reads the state of
/// OTP 29.1.2's `supervisor` module, whose record `state` holds the strategy,
/// intensity and period in fields 3, 6 and 7; any other shape stops the
/// caller with a message.
@external(erlang, "supervisor_flags_ffi", "read")
pub fn read(supervisor: Pid) -> Flags
