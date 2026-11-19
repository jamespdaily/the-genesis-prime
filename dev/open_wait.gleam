//// A wait with no time limit of its own, named, for the test that runs it. A
//// test's only time limit is its deadline, which warns (`owned_test.run`); a
//// read, poll or call that stops the test body for the server runs inside
//// `named`, which tells the test that owns the process what the body is
//// waiting for, so the warning at the deadline names the wait that was still
//// open.
////
//// ```
//// body ──named("a frame")──▶ owned_test: open = ["a frame"]
////        (blocks, no limit)   ... the deadline warns: "waiting for: a frame"
//// body ◀── returns ───────── owned_test: open = []
//// ```
////
//// A process that is not a test body (a bot, a load player) runs the wait and
//// reports it to no one: it keeps the bound its own caller gives it.
////
//// A read that looks at its socket again after each empty look tells
//// `looked_and_found_nothing`. A test body that has a way to tell whether
//// anything can still end the wait (`judging`: a driven clock, which counts the
//// inputs the server takes) is told, once for each wait, when it cannot: the
//// test's owner warns and the wait goes on. The judgement only reads a count;
//// it never stops the read or the server.

import gleam/erlang/process.{type Selector, type Subject}

/// What a test body is told of: a wait for the server, a one-time build its
/// deadline does not count (`database_support_ffi:once/2`), or a wait that
/// can no longer end (`looked_and_found_nothing`; its `opened` is called with
/// the wait's name and its `closed` never).
pub type Slot {
  Wait
  Build
  Hopeless
}

/// Runs `wait`, and tells the test whose body this process is that it waits for
/// `what` until `wait` ends, by its return or by a crash.
pub fn named(what what: String, wait wait: fn() -> a) -> a {
  named_in_process(what, wait)
}

/// Receives the next message on `from`, with no limit of its own, and tells the
/// test that owns this process that it waits for `what` until the message comes.
pub fn received(from subject: Subject(a), what what: String) -> a {
  named(what:, wait: fn() { process.receive_forever(subject) })
}

/// Receives the next message `selector` selects, as `received` does.
pub fn selected(selector selector: Selector(a), what what: String) -> a {
  named(what:, wait: fn() { process.selector_receive_forever(selector) })
}

/// Makes the calling process a test body that can tell whether anything can
/// still end a wait it is in: `taken_inputs` counts the inputs the server has
/// taken so far, 0 while it has taken none.
pub fn judging(taken_inputs taken_inputs: fn() -> Int) -> Nil {
  judge_with(taken_inputs)
}

/// Tells the calling process that a look at the socket found nothing, which
/// the innermost wait it is in was waiting for. When the process judges
/// (`judging`) and the server has taken inputs, but none since this wait's last
/// empty look, nothing can still end the wait and the test's owner is told once
/// for that wait (the `Hopeless` slot of `reporting`). A wait's first empty look
/// has none to compare with. A process that does not judge, or is in no wait, is
/// not told anything.
pub fn looked_and_found_nothing() -> Nil {
  looked_without_finding()
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

@external(erlang, "open_wait_ffi", "judge_with")
fn judge_with(taken_inputs: fn() -> Int) -> Nil

@external(erlang, "open_wait_ffi", "looked_without_finding")
fn looked_without_finding() -> Nil

@external(erlang, "open_wait_ffi", "report_to")
fn report_to(slot: Slot, opened: fn(String) -> Nil, closed: fn() -> Nil) -> Nil
