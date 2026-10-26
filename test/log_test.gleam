//// The logging module. Expected values come from two places.
//// - The designing-processes skill, Logging: logging goes through Erlang's
////   logger at the levels error, warning, info and debug, debug is off by
////   default, and every line carries who and where as metadata: account,
////   character or unit, process or map, message name and number.
//// - Erlang's logger, whose levels are the atoms `error`, `warning`, `info`
////   and `debug`, and whose handler is called in the process that wrote the
////   line, before the call returns, so a line is captured in the order the
////   process wrote it.
////
//// The message names and numbers are the client's: `login_request` is
//// message 0x0592 in `src/genesis_prime/message/schema.toml` (the client's
//// opcode.0x592), and 0x0715 is a message the client registers and ignores on
//// the realm-select connection, which the schema does not name. The ids in
//// the other fields are arbitrary. A test waits for the line it needs, as an
//// event from a capture, and never for a fixed time.

import genesis_prime/telemetry/log.{Who}
import gleam/dict
import gleam/erlang/process
import gleam/option.{None, Some}
import log_capture.{Text, Whole}
import owned_test

/// How long a test waits for a line its own process has already written, in
/// milliseconds. The line is delivered before the call that wrote it returns,
/// so the wait ends at once.
const line_wait_ms = 1000

pub fn a_line_carries_each_part_of_who_as_metadata_under_its_key_test() -> Nil {
  use <- owned_test.run(5000)
  let capture = log_capture.start()
  let who =
    Who(
      account: Some(7),
      actor: Some(log.Character(9)),
      place: Some(log.Process("login")),
      message: Some(log.Named("login_request", 0x0592)),
    )
  log.info(who, "a login")
  let assert Ok(event) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the line was not captured"
  assert event.text == "a login"
  assert dict.get(event.metadata, "account") == Ok(Whole(7))
  assert dict.get(event.metadata, "character") == Ok(Whole(9))
  assert dict.get(event.metadata, "process") == Ok(Text("login"))
  assert dict.get(event.metadata, "message_name") == Ok(Text("login_request"))
  assert dict.get(event.metadata, "message_number") == Ok(Whole(0x0592))
  assert dict.has_key(event.metadata, "unit") == False
  assert dict.has_key(event.metadata, "map") == False
}

pub fn a_unit_a_map_and_a_message_with_only_a_number_are_metadata_under_their_keys_test() -> Nil {
  use <- owned_test.run(5000)
  let capture = log_capture.start()
  let who =
    Who(
      account: None,
      actor: Some(log.Unit(31)),
      place: Some(log.Map(4)),
      message: Some(log.Numbered(0x0715)),
    )
  log.info(who, "a move")
  let assert Ok(event) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the line was not captured"
  assert dict.get(event.metadata, "unit") == Ok(Whole(31))
  assert dict.get(event.metadata, "map") == Ok(Whole(4))
  assert dict.get(event.metadata, "message_number") == Ok(Whole(0x0715))
  assert dict.has_key(event.metadata, "account") == False
  assert dict.has_key(event.metadata, "character") == False
  assert dict.has_key(event.metadata, "process") == False
  assert dict.has_key(event.metadata, "message_name") == False
}

pub fn a_line_about_nobody_has_none_of_the_keys_of_who_test() -> Nil {
  use <- owned_test.run(5000)
  let capture = log_capture.start()
  log.info(log.nobody, "the server started")
  let assert Ok(event) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the line was not captured"
  assert event.text == "the server started"
  let keys_of_who = [
    "account", "character", "unit", "process", "map", "message_name",
    "message_number",
  ]
  assert dict.take(event.metadata, keys_of_who) == dict.new()
}

pub fn the_error_warning_and_info_functions_write_at_their_own_levels_test() -> Nil {
  use <- owned_test.run(5000)
  let capture = log_capture.start()
  // Debug is written only when it is on, so its level is read in the test
  // after this one.
  log.error(log.nobody, "a bug")
  log.warning(log.nobody, "an outside failure")
  log.info(log.nobody, "a start")
  let assert Ok(first) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the error line was not captured"
  let assert Ok(second) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the warning line was not captured"
  let assert Ok(third) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the info line was not captured"
  assert #(first.level, first.text) == #("error", "a bug")
  assert #(second.level, second.text) == #("warning", "an outside failure")
  assert #(third.level, third.text) == #("info", "a start")
}

/// The one test that changes logger's level, which belongs to the whole node:
/// no other test calls `log.configure` after the capture's once-per-run
/// setting, which leaves info, and the end of this test leaves info again.
pub fn debug_is_off_by_default_and_on_when_the_start_argument_says_so_test() -> Nil {
  use <- owned_test.run(5000)
  let capture = log_capture.start()

  // Off: the debug line is not written, and the info line after it is, so the
  // first line the process wrote is the info line.
  log.configure(debug: False)
  log.debug(log.nobody, "per-message detail while off")
  log.info(log.nobody, "after the off debug line")
  let assert Ok(off) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the info line was not captured"
  assert #(off.level, off.text) == #("info", "after the off debug line")

  // On: the debug line is written, first.
  log.configure(debug: True)
  log.debug(log.nobody, "per-message detail while on")
  log.configure(debug: False)
  let assert Ok(on) =
    log_capture.next_from(capture, from: process.self(), within: line_wait_ms)
    as "the debug line was not captured"
  assert #(on.level, on.text) == #("debug", "per-message detail while on")
}
