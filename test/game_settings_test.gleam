//// The game's settings (`genesis_prime/game_settings`), read from variables a
//// test supplies as a list. Expected values come from these places.
//// - The camp countdown's default, 10,000 ms: Jim's choice, with no retail
////   record and none in the client (opcode.0x92.countdown_source).
//// - The countdown's range, 0 to 59,999 ms: the exit window shows whole
////   seconds as `00:SS` with no minutes field, and a countdown of 0 is a camp
////   due at once (opcode.0x92.countdown_range).
//// - The character slots, 2: the client's count for an account with no
////   entitlement (lua.CharacterSelection.OnLoadFromCharacter): the reward
////   property CharacterSlots, row 117 of RewardPropertyPremiumModifier
////   (Hybrid, tier 0, modifierValueInt 2). Their most, 14: row 118 adds
////   Entitlement 12's maxCount, 12 (Entitlement.tbl), to the most.
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
    == Ok(GameSettings(
      camp_countdown_ms: 10_000,
      character_slots: 2,
      dev_commands: False,
    ))
    as "10 s is Jim's choice for the camp, and 2 slots is the client's count for an account with no entitlement"
  assert game_settings.defaults()
    == GameSettings(
      camp_countdown_ms: 10_000,
      character_slots: 2,
      dev_commands: False,
    )
}

pub fn a_countdown_of_0_and_of_59999_is_taken_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_settings.from_environment(
      environment([#("GENESIS_CAMP_COUNTDOWN_MS", "0")]),
    )
    == Ok(GameSettings(
      camp_countdown_ms: 0,
      character_slots: 2,
      dev_commands: False,
    ))
    as "opcode.0x92.countdown_range: a countdown of 0 after 0xBF 1 is a camp due at once"
  assert game_settings.from_environment(
      environment([#("GENESIS_CAMP_COUNTDOWN_MS", "59999")]),
    )
    == Ok(GameSettings(
      camp_countdown_ms: 59_999,
      character_slots: 2,
      dev_commands: False,
    ))
    as "the longest the exit window lays out: 00:59"
  assert game_settings.from_environment(
      environment([#("GENESIS_CAMP_COUNTDOWN_MS", "12345")]),
    )
    == Ok(GameSettings(
      camp_countdown_ms: 12_345,
      character_slots: 2,
      dev_commands: False,
    ))
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
        #("GENESIS_CHARACTER_SLOTS_EXTRA", "9"),
        #("GENESIS_CAMP_COUNTDOWN_MS_EXTRA", "1"),
      ]),
    )
    == Ok(game_settings.defaults())
    as "a variable that only starts with a setting's name is not it"
}

pub fn slots_of_2_and_14_are_taken_and_6_gives_6_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([#("2", 2), #("6", 6), #("14", 14)], fn(case_) {
    let #(text, slots) = case_
    assert game_settings.from_environment(
        environment([#("GENESIS_CHARACTER_SLOTS", text)]),
      )
      == Ok(GameSettings(
        camp_countdown_ms: 10_000,
        character_slots: slots,
        dev_commands: False,
      ))
      as "RewardPropertyPremiumModifier rows 117 and 118: the client offers 2 slots up to 14, its most"
  })
}

pub fn slots_below_2_or_above_14_or_not_a_whole_number_are_refused_with_their_variable_value_and_range_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([#("1", 1), #("0", 0), #("-3", -3), #("15", 15)], fn(case_) {
    let #(text, number) = case_
    assert game_settings.from_environment(
        environment([#("GENESIS_CHARACTER_SLOTS", text)]),
      )
      == Error(OutOfRange(
        variable: "GENESIS_CHARACTER_SLOTS",
        value: number,
        least: 2,
        most: 14,
      ))
      as "below 2 the client still offers 2 (its reward property), so a refusal at fewer would disagree with what it shows; above 14 the slots pass the client's own most, which its tooltip and buy-a-slot entry count against"
  })
  assert game_settings.from_environment(
      environment([#("GENESIS_CHARACTER_SLOTS", "six")]),
    )
    == Error(NotAWholeNumber(
      variable: "GENESIS_CHARACTER_SLOTS",
      value: "six",
      least: 2,
      most: 14,
    ))
}

pub fn the_development_commands_are_off_unset_and_on_only_for_1_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_settings.from_environment(environment([]))
    == Ok(GameSettings(..game_settings.defaults(), dev_commands: False))
    as "the module's doc comment: unset is 0, off, so production, which does not set it, runs no development command"
  assert !game_settings.defaults().dev_commands
  assert game_settings.from_environment(
      environment([#("GENESIS_DEV_COMMANDS", "0")]),
    )
    == Ok(GameSettings(..game_settings.defaults(), dev_commands: False))
    as "0 is off"
  assert game_settings.from_environment(
      environment([#("GENESIS_DEV_COMMANDS", "1")]),
    )
    == Ok(GameSettings(..game_settings.defaults(), dev_commands: True))
    as "1 is on, and changes no other setting"
}

pub fn a_development_commands_value_of_2_or_x_refuses_the_start_with_its_variable_and_range_test() -> Nil {
  use <- owned_test.run(5000)
  assert game_settings.from_environment(
      environment([#("GENESIS_DEV_COMMANDS", "2")]),
    )
    == Error(OutOfRange(
      variable: "GENESIS_DEV_COMMANDS",
      value: 2,
      least: 0,
      most: 1,
    ))
    as "the module's doc comment: a whole number outside 0 to 1 is refused with the range, so a typo never turns the commands on"
  assert game_settings.from_environment(
      environment([#("GENESIS_DEV_COMMANDS", "x")]),
    )
    == Error(NotAWholeNumber(
      variable: "GENESIS_DEV_COMMANDS",
      value: "x",
      least: 0,
      most: 1,
    ))
    as "a value that is not a whole number is refused with the range"
}
