//// A wait with no time limit of its own, named, for the test that runs it. A
//// test's only time limit is its deadline (`owned_test.run`); a read, poll or
//// call that stops the test body for the server runs inside `named`, which
//// tells the test that owns the process what the body is waiting for, so the
//// failure at the deadline names the wait that was still open.
////
//// ```
//// body ──named("a frame")──▶ owned_test: open = ["a frame"]
////        (blocks, no limit)   ... the deadline ends the test: "waiting for: a frame"
//// body ◀── returns ───────── owned_test: open = []
//// ```
////
//// A process that is not a test body (a bot, a load player) runs the wait and
//// reports it to no one: it keeps the bound its own caller gives it.

/// What a test body is told of: a wait for the server, or a one-time build its
/// deadline does not count (`database_support_ffi:once/2`).
pub type Slot {
  Wait
  Build
}

/// Runs `wait`, and tells the test whose body this process is that it waits for
/// `what` until `wait` ends, by its return or by a crash.
pub fn named(what what: String, wait wait: fn() -> a) -> a {
  named_in_process(what, wait)
}

/// Makes the calling process a test body that is told of each `slot` it runs:
/// `opened` is called with the name when one starts and `closed` when it has
/// ended.
pub fn reporting(
  slot slot: Slot,
  opened opened: fn(String) -> Nil,
  closed closed: fn() -> Nil,
) -> Nil {
  report_to(slot, opened, closed)
}

@external(erlang, "open_wait_ffi", "named")
fn named_in_process(what: String, wait: fn() -> a) -> a

@external(erlang, "open_wait_ffi", "report_to")
fn report_to(slot: Slot, opened: fn(String) -> Nil, closed: fn() -> Nil) -> Nil
