//// The clocks a connection reads. The monotonic clock measures its rate: a
//// time is whole milliseconds from an arbitrary start, and may be negative, so
//// 0 never means no time. The system clock gives the time the client is told
//// as a Windows FILETIME. A rule takes the time as an input; only a process
//// reads a clock.

/// A source of the current time in whole milliseconds, read by the process
/// that owns a connection. A test gives its own, so a rate limit is tested
/// without waiting.
pub type Clock =
  fn() -> Int

/// The runtime's monotonic time in milliseconds (`erlang:monotonic_time/1`).
@external(erlang, "genesis_prime_socket_ffi", "monotonic_milliseconds")
pub fn monotonic_milliseconds() -> Int

/// The system time as a Windows FILETIME: the number of 100-nanosecond
/// intervals since 1601-01-01 UTC, which is what the client reads the server's
/// time as (opcode.0x117).
pub fn system_filetime() -> Int {
  todo as "the system clock as a FILETIME"
}

/// The FILETIME of a time given as whole seconds since 1970-01-01 UTC and the
/// nanoseconds after them.
pub fn filetime_of(
  unix_seconds unix_seconds: Int,
  nanoseconds nanoseconds: Int,
) -> Int {
  todo as "a Unix time as a FILETIME"
}
