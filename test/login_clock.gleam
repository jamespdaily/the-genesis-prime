//// A clock a test moves by hand, so an expiry is tested without waiting. It
//// reads whole milliseconds like the monotonic clock a hand-off reads, and
//// stays where the test left it.

/// A clock the test owns: `read` is what a hand-off is given, `set` moves it.
pub type Clock

/// A clock at 0.
@external(erlang, "login_clock_ffi", "new")
pub fn new() -> Clock

/// The clock's time in milliseconds.
@external(erlang, "login_clock_ffi", "read")
pub fn read(clock: Clock) -> Int

/// Moves the clock to this time.
@external(erlang, "login_clock_ffi", "set")
pub fn set(clock: Clock, milliseconds: Int) -> Nil
