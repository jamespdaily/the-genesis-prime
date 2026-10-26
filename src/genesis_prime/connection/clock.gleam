//// The monotonic clock a connection measures its rate by. A time is whole
//// milliseconds from an arbitrary start, and may be negative, so 0 never
//// means no time. A rule takes the time as an input; only a process reads the
//// clock.

/// A source of the current time in whole milliseconds, read by the process
/// that owns a connection. A test gives its own, so a rate limit is tested
/// without waiting.
pub type Clock =
  fn() -> Int

/// The runtime's monotonic time in milliseconds (`erlang:monotonic_time/1`).
@external(erlang, "genesis_prime_socket_ffi", "monotonic_milliseconds")
pub fn monotonic_milliseconds() -> Int
