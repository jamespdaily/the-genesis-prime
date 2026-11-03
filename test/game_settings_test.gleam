//// The game's settings (`genesis_prime/game_settings`), read from variables a
//// test supplies as a list. Expected values come from these places.
//// - The camp countdown's default, 10,000 ms: Jim's choice, with no retail
////   record and none in the client (opcode.0x92.countdown_source).
//// - The countdown's range, 0 to 59,999 ms: the exit window shows whole
////   seconds as `00:SS` with no minutes field, and a countdown of 0 is a camp
////   due at once (opcode.0x92.countdown_range).
//// - The character slots, 2: the client's count for an account with no
////   entitlement (lua.CharacterSelection.OnLoadFromCharacter); no variable
////   sets them yet.
//// - The module's doc comment: a variable that is set replaces its default, a
////   refused value names the variable, the value and the range.

import genesis_prime/game_settings.{GameSettings, NotAWholeNumber, OutOfRange}
import gleam/list
import owned_test

/// The environment `variables` make: a variable that is not in the list is not
/// set.
fn environment(
  variables: List(#(String, String)),
) -> fn(String) -> Result(String, Nil) {
  fn(name) { list.key_find(variables, name) }
}

pub fn no_variables_give_the_defaults_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_settings.from_environment(environment([]))
    == Ok(GameSettings(camp_countdown_ms: 10_000, character_slots: 2))
    as "10 s is Jim's choice for the camp, and 2 slots is the client's count for an account with no entitlement"
  assert game_settings.defaults()
    == GameSettings(camp_countdown_ms: 10_000, character_slots: 2)
}

pub fn a_countdown_of_0_and_of_59999_is_taken_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_settings.from_environment(
      environment([#("GENESIS_CAMP_COUNTDOWN_MS", "0")]),
    )
    == Ok(GameSettings(camp_countdown_ms: 0, character_slots: 2))
    as "opcode.0x92.countdown_range: a countdown of 0 after 0xBF 1 is a camp due at once"
  assert game_settings.from_environment(
      environment([#("GENESIS_CAMP_COUNTDOWN_MS", "59999")]),
    )
    == Ok(GameSettings(camp_countdown_ms: 59_999, character_slots: 2))
    as "the longest the exit window lays out: 00:59"
  assert game_settings.from_environment(
      environment([#("GENESIS_CAMP_COUNTDOWN_MS", "12345")]),
    )
    == Ok(GameSettings(camp_countdown_ms: 12_345, character_slots: 2))
    as "a value in between replaces the default"
}

pub fn a_countdown_outside_the_range_or_not_a_whole_number_is_refused_with_its_variable_value_and_range_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([#("-1", -1), #("60000", 60_000), #("100000", 100_000)], fn(case_) {
    let #(text, number) = case_
    assert game_settings.from_environment(
        environment([#("GENESIS_CAMP_COUNTDOWN_MS", text)]),
      )
      == Error(OutOfRange(
        variable: "GENESIS_CAMP_COUNTDOWN_MS",
        value: number,
        least: 0,
        most: 59_999,
      ))
      as "a whole number outside 0 to 59999 is refused with the range: a negative time is one the client could not handle, and the exit window has no minutes field"
  })
  list.each(["ten", "1.5", "", " 5", "5 ms"], fn(value) {
    assert game_settings.from_environment(
        environment([#("GENESIS_CAMP_COUNTDOWN_MS", value)]),
      )
      == Error(NotAWholeNumber(
        variable: "GENESIS_CAMP_COUNTDOWN_MS",
        value:,
        least: 0,
        most: 59_999,
      ))
      as "a value that is not a whole number is refused with the range"
  })
}

pub fn a_refusal_says_the_variable_the_value_and_the_range_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_settings.describe(OutOfRange(
      variable: "GENESIS_CAMP_COUNTDOWN_MS",
      value: 60_000,
      least: 0,
      most: 59_999,
    ))
    == "GENESIS_CAMP_COUNTDOWN_MS is 60000, which is outside 0 to 59999"
  assert game_settings.describe(NotAWholeNumber(
      variable: "GENESIS_CAMP_COUNTDOWN_MS",
      value: "ten",
      least: 0,
      most: 59_999,
    ))
    == "GENESIS_CAMP_COUNTDOWN_MS is \"ten\", which is not a whole number from 0 to 59999"
}

pub fn a_variable_no_setting_reads_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_settings.from_environment(
      environment([
        #("GENESIS_CHARACTER_SLOTS", "9"),
        #("GENESIS_CAMP_COUNTDOWN_MS_EXTRA", "1"),
      ]),
    )
    == Ok(game_settings.defaults())
    as "the slots have no variable yet, and a variable that only starts with a setting's name is not it"
}
