//// The server shows its info lines. Expected values come from the
//// designing-processes skill: info is the level of start, stop, login and
//// logout, so the server's log shows it; OTP's logger drops info by default
//// (its primary level is notice).

import genesis_prime/step/runtime
import gleam/erlang/atom
import log_capture
import owned_test

pub fn the_servers_start_lets_info_lines_through_test() -> Nil {
  use <- owned_test.run(5000)
  let before = log_capture.primary_level()
  runtime.show_info_lines()
  let after = log_capture.primary_level()
  log_capture.set_primary_level(before)
  assert after == atom.create("info")
    as "the logger lets info lines through once the server starts"
}
