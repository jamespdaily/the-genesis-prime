//// The server shows its info lines. Expected values come from the
//// designing-processes skill: info is the level of start, stop, login and
//// logout, so the server's log shows it; OTP's logger drops info by default
//// (its primary level is notice).

import genesis_prime
import gleam/erlang/atom.{type Atom}
import owned_test

pub fn the_servers_start_lets_info_lines_through_test() -> Nil {
  use <- owned_test.run(5000)
  let before = primary_level()
  genesis_prime.show_info_lines()
  let after = primary_level()
  set_primary_level(before)
  assert after == atom.create("info")
    as "the logger lets info lines through once the server starts"
}

@external(erlang, "logging_test_ffi", "primary_level")
fn primary_level() -> Atom

@external(erlang, "logging_test_ffi", "set_primary_level")
fn set_primary_level(level: Atom) -> Nil
