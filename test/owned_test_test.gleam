//// A test's deadline warns and never fails (`owned_test.run`): a body that
//// passes it is waited for, and the warning names what is open. A deadline of
//// 0 ms is passed by any body, so each result is the same on any machine.

import ask_support
import open_wait
import owned_test

pub fn a_body_past_its_deadline_returns_its_value_test() -> Nil {
  use <- owned_test.run(10_000)
  assert owned_test.run(0, fn() { 7 }) == 7
    as "a body that passed its deadline is judged by its end, not by the time"
}

pub fn a_body_past_its_deadline_inside_a_wait_returns_its_value_test() -> Nil {
  use <- owned_test.run(10_000)
  let value =
    owned_test.run(0, fn() {
      open_wait.named(what: "a frame", wait: fn() { 7 })
    })
  assert value == 7 as "a wait open at the deadline does not fail the test"
}

pub fn a_crashed_body_still_fails_test() -> Nil {
  use <- owned_test.run(10_000)
  let ended =
    ask_support.ended_running(fn() {
      owned_test.run(0, fn() { panic as "the planted crash of the body" })
    })
  assert ask_support.panic_message(ask_support.raised(ended))
    == "the test body crashed"
}

pub fn the_deadline_warning_names_the_open_waits_innermost_first_test() -> Nil {
  use <- owned_test.run(10_000)
  assert owned_test.deadline_warning(
      test_name: "m:f",
      timeout_ms: 5000,
      waiting: ["inner", "outer"],
    )
    == "check WARNING: test m:f passed its 5000 ms deadline while waiting for: inner > outer"
  assert owned_test.deadline_warning(
      test_name: "m:f",
      timeout_ms: 5000,
      waiting: [],
    )
    == "check WARNING: test m:f passed its 5000 ms deadline with no wait open"
}

pub fn the_build_warning_names_the_open_keys_test() -> Nil {
  use <- owned_test.run(10_000)
  assert owned_test.build_warning(test_name: "m:f", open: ["b", "a"])
    == "check WARNING: test m:f has a one-time build open past 120000 ms: a > b"
    as "build b opened inside build a, so the keys read outermost first"
}
