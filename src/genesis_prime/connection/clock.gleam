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

/// The options of `erlang:unique_integer/1` this module uses. A constructor
/// without a field is the atom of its name in lower case.
type UniqueOption {
  Monotonic
}

@external(erlang, "erlang", "unique_integer")
fn unique_integer(options: List(UniqueOption)) -> Int

/// A number that is greater than every number this function gave before in the
/// running node, so it orders what starts: two connections never share one.
/// It may be negative and means nothing outside the node.
pub fn start_order() -> Int {
  unique_integer([Monotonic])
}
