//// What can name an account. The client lower-cases the typed name before it
//// sends it (StartStsLogin 0x1400b4500) and the login request cannot hold a
//// name over 250 UTF-16 units (fact file opcode.0x592: "at most 250
//// characters", WriteCountedWideText 0x1400c2f70 refuses a name without a zero
//// in its first 251 units).

import genesis_prime/login/account
import gleam/string
import owned_test

pub fn a_name_is_kept_in_lower_case_test() -> Nil {
  use <- owned_test.run(5000)
  assert account.lower_case_name("Jim.Daily@Example.COM")
    == Ok("jim.daily@example.com")
    as "StartStsLogin 0x1400b4500 lower-cases the typed name before LoginStart"
}

pub fn an_empty_name_names_no_account_test() -> Nil {
  use <- owned_test.run(5000)
  assert account.lower_case_name("") == Error(account.NameEmpty)
    as "StsConnLib64.MT.dll!0x180006fb0: without a name the request is not sent"
}

pub fn a_name_of_250_units_is_the_longest_that_names_an_account_test() -> Nil {
  use <- owned_test.run(5000)
  let longest = string.repeat("a", 250)
  assert account.lower_case_name(longest) == Ok(longest)
    as "opcode.0x592: the account name is at most 250 characters"
  assert account.lower_case_name(longest <> "a")
    == Error(account.NameTooLong(251))
    as "opcode.0x592: an account name over 250 characters makes the request fail to serialise"
}

pub fn a_name_is_counted_in_utf_16_units_test() -> Nil {
  use <- owned_test.run(5000)
  let astral = string.repeat("😀", 126)
  assert account.lower_case_name(astral) == Error(account.NameTooLong(252))
    as "opcode.0x592: the count is of UTF-16 units, and a character above the basic plane is two"
}

pub fn the_limit_the_client_writes_is_250_test() -> Nil {
  use <- owned_test.run(5000)
  assert account.name_unit_limit == 250
    as "opcode.0x592: at most 250 characters"
}
