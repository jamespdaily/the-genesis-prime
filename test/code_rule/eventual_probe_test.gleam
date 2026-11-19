//// The eventual-probe rule. Expected values are the rule of the writing-tests
//// skill: a test never asserts a state that becomes true later (a monitor set,
//// a message taken, a port closed) at the moment it looks; it waits for it
//// with `event_wait.until`, whose condition is looked at again until it holds.
//// A breach is a call of one of the probes that is not inside a closure given
//// to `event_wait.until`, reported at the probe's line. Every case is planted
//// in a made-up file.

import code_rule/eventual_probe
import code_rule/planted
import code_rule/repository
import gleam/list
import gleam/string
import owned_test
import unitest

/// The planted test file: the imports, then the body's lines inside one
/// function, so each case states only what differs. The first body line is
/// line 7.
fn planted_lines(body: List(String)) -> List(String) {
  list.flatten([
    [
      "import event_wait",
      "import login_client",
      "import mailbox_support",
      "import other",
      "",
      "pub fn planted() {",
    ],
    body,
    ["}"],
  ])
}

fn breach_lines(source_lines: List(String)) -> List(Int) {
  planted.file("test/planted_test.gleam", source_lines)
  |> eventual_probe.breaches
  |> planted.lines
}

pub fn a_probe_inside_an_event_wait_closure_is_not_a_breach_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // Each row: the planted file's lines, and why it is clean.
  let cases = [
    #(
      planted_lines([
        "  event_wait.until(\"the monitor\", fn() {",
        "    mailbox_support.monitored(pid) == []",
        "  })",
      ]),
      "a probe in the closure of the wait",
    ),
    #(
      planted_lines([
        "  event_wait.until(\"the queue\", fn() {",
        "    list.any(pids, fn(pid) { mailbox_support.queued(pid) == 0 })",
        "  })",
      ]),
      "a probe in a closure inside the wait's closure",
    ),
    #(
      planted_lines([
        "  event_wait.until(\"the port\", fn() { login_client.refused(port) })",
      ]),
      "the refused-port probe in the closure of the wait",
    ),
    #(
      [
        "import event_wait as waiting",
        "import mailbox_support as mailbox",
        "",
        "pub fn planted() {",
        "  waiting.until(\"x\", fn() { mailbox.queued(pid) == 0 })",
        "}",
      ],
      "both modules imported under an alias",
    ),
    #(
      [
        "import event_wait.{until}",
        "import mailbox_support.{queued}",
        "",
        "pub fn planted() {",
        "  until(\"x\", fn() { queued(pid) == 0 })",
        "}",
      ],
      "both functions imported unqualified",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(lines, reason) = case_
    assert breach_lines(lines) == [] as reason
  })
}

pub fn a_probe_outside_an_event_wait_closure_is_a_breach_at_its_line_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // Each row: the body's lines (the first is line 7), the breach lines, and why.
  let cases = [
    #(["  assert mailbox_support.monitored(pid) == []"], [7], "monitored"),
    #(["  assert mailbox_support.queued(pid) == 0"], [7], "queued"),
    #(["  assert mailbox_support.tagged(pid, tag) == 0"], [7], "tagged"),
    #(
      ["  assert mailbox_support.tagged_by_reference(pid) == 0"],
      [7],
      "tagged_by_reference",
    ),
    #(
      ["  assert mailbox_support.call_waiting_from(pid:, caller:)"],
      [7],
      "call_waiting_from",
    ),
    #(["  assert login_client.refused(port)"], [7], "refused"),
    #(
      [
        "  list.each(pids, fn(pid) {",
        "    assert mailbox_support.monitored(pid) == []",
        "  })",
      ],
      [8],
      "a closure given to another function",
    ),
    #(
      [
        "  event_wait.until(\"x\", fn() { True })",
        "  assert mailbox_support.tagged(pid, tag) == 0",
      ],
      [8],
      "a probe after the wait has ended",
    ),
    #(
      [
        "  let waiting = mailbox_support.call_waiting_from(pid:, caller:)",
        "  mailbox_support.queued(pid) + mailbox_support.queued(caller)",
      ],
      [7, 8, 8],
      "every probe, a line once for each",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(body, lines, reason) = case_
    assert breach_lines(planted_lines(body)) == lines as reason
  })
}

pub fn a_probe_in_a_helper_is_a_breach_since_the_caller_waits_for_the_helper_not_the_probe_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file("test/planted_test.gleam", [
      "import login_client",
      "",
      "fn gone(port) {",
      "  login_client.refused(port)",
      "}",
    ])
  assert planted.lines(eventual_probe.breaches(file)) == [4]
}

pub fn a_breach_names_the_file_and_the_rule_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let file =
    planted.file(
      "test/planted_test.gleam",
      planted_lines(["  assert mailbox_support.queued(pid) == 0"]),
    )
  let assert [breach] = eventual_probe.breaches(file)
    as "expected exactly one breach"
  assert breach.path == "test/planted_test.gleam"
  assert string.contains(breach.rule, "event_wait.until")
}

pub fn a_function_of_the_same_name_in_another_module_is_not_a_probe_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  // Each row: the body's lines, and why they are clean.
  let cases = [
    #(["  assert other.queued(pid) == 0"], "a module that is not the probe's"),
    #(["  assert queued(pid) == 0"], "a function of the file's own"),
    #(
      ["  assert mailbox_support.drain(subject) == []"],
      "a function of the probe's module that is no probe",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(body, reason) = case_
    assert breach_lines(planted_lines(body)) == [] as reason
  })
}

pub fn every_eventual_probe_in_the_test_directory_is_inside_an_event_wait_test() -> Nil {
  // Deadline: the body took under 200 ms in three runs alone, so 5 s is more
  // than 3 times that.
  use <- owned_test.run(5000)
  use <- unitest.tag("code_rule")
  let files = repository.sources(["test"])
  assert list.flat_map(files, eventual_probe.breaches) == []
}
