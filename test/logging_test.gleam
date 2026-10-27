//// The server shows its info lines. Expected values come from the
//// designing-processes skill: info is the level of start, stop, login and
//// logout, so the server's log shows it; OTP's logger drops info by default
//// (its primary level is notice). At info, OTP also logs a progress report
//// for every supervisor and child it starts (logger_filters:progress), which
//// is noise the skill's levels give no place; those stay out. The logger's
//// level and filters are the node's, shared by every test, so these tests
//// are `serial`: they run one at a time, apart from the others.

import genesis_prime/step
import genesis_prime/step/runtime
import gleam/erlang/atom
import gleam/erlang/process
import log_capture
import owned_test
import unitest

pub fn the_servers_start_lets_info_lines_through_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("serial")
  let before = log_capture.primary_level()
  runtime.show_info_lines()
  let after = log_capture.primary_level()
  log_capture.set_primary_level(before)
  assert after == atom.create("info")
    as "the logger lets info lines through once the server starts"
}

pub fn the_servers_start_leaves_out_otps_progress_reports_test() -> Nil {
  use <- owned_test.run(5000)
  use <- unitest.tag("serial")
  let before = log_capture.primary_level()
  let lines = process.new_subject()
  let capture = log_capture.start(from: process.self(), into: lines)
  runtime.show_info_lines()
  log_capture.log_progress_report()
  runtime.log(step.LogInfo, "an info line", step.no_one)
  let first = process.receive(lines, 1000)
  log_capture.stop(capture)
  log_capture.remove_progress_filter()
  log_capture.set_primary_level(before)
  assert first == Ok(#("info", "an info line"))
    as "the info line is the first line the logger lets through, with no progress report before it"
}
