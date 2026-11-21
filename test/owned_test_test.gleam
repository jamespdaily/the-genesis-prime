//// A test's deadline warns and never fails (`owned_test.run`): a body that
//// passes it is waited for, and the warning names what is open. A deadline of
//// 0 ms is passed by any body, so each result is the same on any machine.

import ask_support
import fixed_seed
import genesis_prime/connection/script
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import mailbox_support
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

/// A script from the operating system, which a listener's seeded scripts wrap.
fn system_scripts() -> script.Scripts {
  script.operating_system
}

/// Takes two scripts from the sts listener's seeded scripts and one from the game's,
/// then crashes, and returns the end of the panic message a run under `salt` gives.
fn failure_report_under(salt salt: String) -> String {
  let ended =
    ask_support.ended_running(fn() {
      owned_test.run_under_salt(salt:, timeout_ms: 10_000, body: fn() {
        let sts = fixed_seed.scripts(listener: "sts", over: system_scripts())
        let game = fixed_seed.scripts(listener: "game", over: system_scripts())
        let assert Ok(_) = sts()
        let assert Ok(_) = game()
        let assert Ok(_) = game()
        panic as "the planted crash of the body"
      })
    })
  let message = ask_support.panic_message(ask_support.raised(ended))
  let assert Ok(#(_reason, report)) =
    string.split_once(message, "\nthe seeds of the connections of ")
    as "the failure ends with the seeds' report"
  "the seeds of the connections of " <> report
}

pub fn a_crashed_bodys_failure_names_the_seeds_its_listeners_were_given_test() -> Nil {
  use <- owned_test.run(60_000)
  // The body is written in `failure_report_under`, which is the name the report gives.
  let name = "owned_test_test:failure_report_under"
  // Each row: the salt, the line that names it, the command that repeats the run,
  // and the seeds of the sts connection 1, the game connections 1 and 2 (SHA-256 of
  // their parts, by Python's hashlib).
  let rows = [
    #(
      "b",
      "GENESIS_TEST_SEED_SALT: b",
      "GENESIS_TEST_SEED_SALT=b gleam test -- test/owned_test_test.gleam",
      [
        "D40164176F3ED8E811E2A4A1624E7CE97B467EFC0CC3AE5195EED08D2B172E82",
        "512A1C8BEFBE410CE4D880EC9062C7DB87B94964D944BF492A85432BA9A8738B",
        "89639719EAC576EC0B083651520B56E9D37AF6A70152448B4696CF60E51E181F",
      ],
    ),
    #(
      "",
      "GENESIS_TEST_SEED_SALT: unset",
      "gleam test -- test/owned_test_test.gleam",
      [
        "8B022FE713F9CFB1D2C8C11E80E278E46B6FACF70AA5D46D11408D38D2D163E1",
        "2605CF4AD7B6376625CD27C529882E1C25D837D90D59A764E66320FE1ADE0211",
        "A511334D97D55145419114C28037E751E0E0955CCFFA6F7A7955A317C980CAF6",
      ],
    ),
  ]
  use #(salt, salt_line, repeat, seeds) <- list.each(rows)
  let assert [sts_1, game_1, game_2] = seeds
  assert failure_report_under(salt:)
    == string.join(
      [
        "the seeds of the connections of " <> name <> ":",
        "  " <> salt_line,
        "  seed name: none",
        "  repeat it: " <> repeat,
        "connection 1 of the sts listener: " <> sts_1,
        "connection 1 of the game listener: " <> game_1,
        "connection 2 of the game listener: " <> game_2,
      ],
      "\n",
    )
    as {
      "salt "
      <> salt
      <> ": the report names the salt, the seed name, the command that repeats the run and each seed in the order issued"
    }
}

pub fn a_body_that_returns_leaves_no_seed_line_in_its_owners_mailbox_test() -> Nil {
  use <- owned_test.run(60_000)
  // A run leaves its own end in its owner's mailbox (the monitor's message), so
  // the count a body that takes no script adds is the one to compare with.
  let before = mailbox_support.queued(process.self())
  owned_test.run_under_salt(salt: "s", timeout_ms: 10_000, body: fn() { Nil })
  let after_a_body_that_took_no_script = mailbox_support.queued(process.self())
  let scripts =
    owned_test.run_under_salt(salt: "s", timeout_ms: 10_000, body: fn() {
      let scripts = fixed_seed.scripts(listener: "game", over: system_scripts())
      let assert Ok(_) = scripts()
      scripts
    })
  let after_a_body_that_took_one = mailbox_support.queued(process.self())
  assert after_a_body_that_took_one - after_a_body_that_took_no_script
    == after_a_body_that_took_no_script - before
    as "a seed issued inside the body adds no message to the mailbox of the process that ran it"
  let assert Ok(_) = scripts()
    as "a script issued after the body returned is still handed out"
  assert mailbox_support.queued(process.self()) == after_a_body_that_took_one
    as "a seed issued after the body returned is told to nothing"
}
