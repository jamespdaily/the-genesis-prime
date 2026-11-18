//// A test's deadline warns and never fails (`owned_test.run`): a body that
//// passes it is waited for, and the warning names what is open. A deadline of
//// 0 ms is passed by any body, so each result is the same on any machine.

import ask_support
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import open_wait
import owned_test
import recording_support
import simplifile

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
  assert string.starts_with(
    ask_support.panic_message(ask_support.raised(ended)),
    "the test body crashed: ",
  )
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

/// The lines of the progress file as the words each holds.
fn progress_lines(file: String) -> List(List(String)) {
  let assert Ok(text) = simplifile.read(file) as "the progress file reads"
  text
  |> string.split("\n")
  |> list.filter(fn(line) { line != "" })
  |> list.map(string.split(_, " "))
}

/// The file `./check` reads on a hang (`running_tests`): a test is listed with a
/// `start ID SECONDS module:function` line when it begins and an `end ID` line
/// when it ends, so a start with no end is a test still running.
pub fn a_test_is_listed_from_its_start_to_its_end_test() -> Nil {
  use <- owned_test.run(10_000)
  use folder <- recording_support.in_folder
  let file = folder <> "/running"
  owned_test.run_listed_in(
    progress_file: Some(file),
    timeout_ms: 10_000,
    body: fn() {
      let assert [["start", _, seconds, name]] = progress_lines(file)
        as "while the body runs, one line holds its start"
      assert name
        == "owned_test_test:a_test_is_listed_from_its_start_to_its_end_test"
        as "the line names the test's module and function"
      assert int.parse(seconds) != Error(Nil)
        as "the line holds the seconds of the wall clock"
    },
  )
  let assert [["start", id, _, _], ["end", ended]] = progress_lines(file)
    as "after the body, an end line follows the start"
  assert id == ended as "and carries the start's id"
}

/// A body that crashes is gone when the test ends, so it is not left listed as running.
pub fn a_test_whose_body_crashed_is_listed_as_ended_test() -> Nil {
  use <- owned_test.run(10_000)
  use folder <- recording_support.in_folder
  let file = folder <> "/running"
  let ended =
    ask_support.ended_running(fn() {
      owned_test.run_listed_in(
        progress_file: Some(file),
        timeout_ms: 10_000,
        body: fn() { panic as "the planted crash of the body" },
      )
    })
  assert string.starts_with(
    ask_support.panic_message(ask_support.raised(ended)),
    "the test body crashed: ",
  )
  let assert [["start", id, _, _], ["end", ended]] = progress_lines(file)
    as "the crashed test has its end line"
  assert id == ended
}
