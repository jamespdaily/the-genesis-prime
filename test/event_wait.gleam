//// Waits for an observable state of the server, for the tests that read what a
//// process has taken from its mailbox or whether a connection has ended: the
//// state is checked again every millisecond until the event deadline, so a
//// test waits for an event and never for a fixed time.

import ask_support
import gleam/erlang/process

/// Waits until `condition` holds, and fails the test, naming `what`, when it
/// does not within the event deadline.
pub fn until(what: String, condition: fn() -> Bool) -> Nil {
  check(what, condition, ask_support.event_wait_ms)
}

fn check(what: String, condition: fn() -> Bool, within_ms: Int) -> Nil {
  case condition(), within_ms > 0 {
    True, _ -> Nil
    False, True -> {
      process.sleep(1)
      check(what, condition, within_ms - 1)
    }
    False, False -> panic as { "this never happened in time: " <> what }
  }
}
