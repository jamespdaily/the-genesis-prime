//// The clocks a connection reads. The monotonic clock measures its rate: a
//// time is whole milliseconds from an arbitrary start, and may be negative, so
//// 0 never means no time. The system clock gives the time the client is told
//// as a Windows FILETIME. A rule takes the time as an input; only a process
//// reads a clock.

import gleam/time/timestamp

/// A source of the current time in whole milliseconds, read by the process
/// that owns a connection. A test gives its own, so a rate limit is tested
/// without waiting.
pub type Clock =
  fn() -> Int

/// The runtime's monotonic time in milliseconds (`erlang:monotonic_time/1`).
@external(erlang, "genesis_prime_socket_ffi", "monotonic_milliseconds")
pub fn monotonic_milliseconds() -> Int

/// The system time as a Windows FILETIME: the number of 100-nanosecond
/// intervals since the start of the year 1601 in UTC, which is what the client
/// reads the server's time as (opcode.0x117).
pub fn system_filetime() -> Int {
  let #(seconds, nanoseconds) =
    timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
  filetime_of(unix_seconds: seconds, nanoseconds:)
}

/// The seconds between the start of the year 1601 and the Unix epoch
/// (Microsoft's definition of FILETIME, which counts from 1601 in UTC).
const seconds_from_1601_to_1970 = 11_644_473_600

/// The 100-nanosecond intervals in a second.
const intervals_per_second = 10_000_000

/// The FILETIME of a time given as whole seconds since the Unix epoch and the
/// nanoseconds after them.
pub fn filetime_of(
  unix_seconds unix_seconds: Int,
  nanoseconds nanoseconds: Int,
) -> Int {
  { unix_seconds + seconds_from_1601_to_1970 }
  * intervals_per_second
  + nanoseconds
  / 100
}
