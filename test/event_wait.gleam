//// Waits for an observable state of the server, for the tests that read what a
//// process has taken from its mailbox or whether a connection has ended: the
//// state is checked again every millisecond, so a test waits for an event and
//// never for a fixed time. The wait has no limit of its own: the test's
//// deadline ends it, and names it (`open_wait`, `owned_test.run`).

import gleam/bool
import gleam/erlang/process
import open_wait

/// Waits until `condition` holds. A state that never comes ends the test at its
/// deadline, with `what` named as the wait still open.
pub fn until(what: String, condition: fn() -> Bool) -> Nil {
  open_wait.named("this to happen: " <> what, fn() { check(condition) })
}

fn check(condition: fn() -> Bool) -> Nil {
  use <- bool.guard(when: condition(), return: Nil)
  process.sleep(1)
  check(condition)
}
