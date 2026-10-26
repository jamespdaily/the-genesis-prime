//// A clock a test moves by hand, so a rate limit is tested without waiting.
//// It starts at a negative time on purpose: the monotonic clock can be
//// negative, so no rule may read 0 as no time.

import genesis_prime/connection/clock.{type Clock}

/// A time in whole milliseconds that only `advance` changes.
pub type FakeClock

/// A clock at the given time.
@external(erlang, "fake_clock_ffi", "new")
pub fn new(start_milliseconds: Int) -> FakeClock

/// The clock's time.
@external(erlang, "fake_clock_ffi", "read")
pub fn read(clock: FakeClock) -> Int

/// Moves the clock forward by `milliseconds`.
@external(erlang, "fake_clock_ffi", "advance")
pub fn advance(clock: FakeClock, milliseconds: Int) -> Nil

/// The clock as a source of time for a socket owner.
pub fn as_clock(fake: FakeClock) -> Clock {
  fn() { read(fake) }
}
