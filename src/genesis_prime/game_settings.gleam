//// The game's settings that are the server's choice or the operator's: values
//// the client's own data does not fix. They are read once at start from the
//// environment (`from_environment`) into one `GameSettings`, which every game
//// connection is made with (genesis_prime/game/connection).
////
//// | Setting | Variable | Default and its source | Allowed |
//// | --- | --- | --- | --- |
//// | `camp_countdown_ms` | `GENESIS_CAMP_COUNTDOWN_MS` | 10,000: Jim's choice, 2026-11-03; no retail record, and the client has none (opcode.0x92.countdown_source) | 0 to 59,999: the exit window shows only seconds, as `00:SS`, with no minutes field (opcode.0x92.countdown_range) |
//// | `character_slots` | `GENESIS_CHARACTER_SLOTS` | 2: the client's count for an account with no entitlement (lua.CharacterSelection.OnLoadFromCharacter) | 2 to 14: the client offers at least 2 and counts its most as 14 (RewardPropertyPremiumModifier rows 117 and 118, Entitlement 12's maxCount) |
//// | `dev_commands` | `GENESIS_DEV_COMMANDS` | 0, off: a server choice (the client has no development commands), so a `!` line is a Say line | 0 or 1: 1 turns the development chat commands on (genesis_prime/game/dev_command); the play container sets it (release/container_start), production does not |
////
//// - **A variable that is set** replaces its setting's default. A value that
////   is not a whole number, or lies outside the allowed range, is refused with
////   the variable, the value and the range, and the server stops at start with
////   that text, as it does for GENESIS_GAME_ADDRESS.
//// - **A variable that is not set** leaves the default.
//// - **A countdown of 0** is allowed: the client then runs a camp that is due
////   at once, with no window (opcode.0x92.countdown_range).

import gleam/int
import gleam/result

/// The slots the client offers an account with no BaseCharacterSlots
/// entitlement under the Hybrid premium system: the CharacterSlots reward
/// property, RewardPropertyPremiumModifier row 117 (modifierValueInt 2), which
/// `lua.CharacterSelection.OnLoadFromCharacter` starts its sum from.
pub const client_base_character_slots = 2

/// The most slots the client counts: the base and Entitlement 12's maxCount
/// (Entitlement.tbl: 12), which row 118 of RewardPropertyPremiumModifier adds
/// to the most.
const client_most_character_slots = 14

/// The game's settings. `camp_countdown_ms` is the countdown the server gives
/// a camp, in milliseconds; `character_slots` is the number of characters an
/// account may have; `dev_commands` is whether a Say line that starts with `!`
/// is a development command (genesis_prime/game/dev_command) and not a line to
/// say.
pub type GameSettings {
  GameSettings(camp_countdown_ms: Int, character_slots: Int, dev_commands: Bool)
}

/// Why a variable's value is refused.
pub type SettingRefusal {
  /// The value is not a whole number; the allowed numbers are `least` to
  /// `most`, both allowed.
  NotAWholeNumber(variable: String, value: String, least: Int, most: Int)
  /// The value is a whole number outside `least` to `most`, both allowed.
  OutOfRange(variable: String, value: Int, least: Int, most: Int)
}

/// The settings with no variable set.
pub fn defaults() -> GameSettings {
  GameSettings(
    camp_countdown_ms: 10_000,
    character_slots: client_base_character_slots,
    dev_commands: False,
  )
}

/// The defaults, with each variable that `read` finds replacing its setting;
/// `read` gives a variable's text, or `Error(Nil)` when it is not set. The
/// first variable whose value is refused is the `Error`.
pub fn from_environment(
  read read: fn(String) -> Result(String, Nil),
) -> Result(GameSettings, SettingRefusal) {
  let defaults = defaults()
  use camp_countdown_ms <- result.try(whole_number(
    read:,
    variable: "GENESIS_CAMP_COUNTDOWN_MS",
    default: defaults.camp_countdown_ms,
    least: 0,
    most: 59_999,
  ))
  use character_slots <- result.try(whole_number(
    read:,
    variable: "GENESIS_CHARACTER_SLOTS",
    default: defaults.character_slots,
    least: client_base_character_slots,
    most: client_most_character_slots,
  ))
  use dev_commands <- result.map(whole_number(
    read:,
    variable: "GENESIS_DEV_COMMANDS",
    default: 0,
    least: 0,
    most: 1,
  ))
  GameSettings(
    camp_countdown_ms:,
    character_slots:,
    dev_commands: dev_commands == 1,
  )
}

/// The whole number the variable holds, from `least` to `most`, or `default`
/// when it is not set.
fn whole_number(
  read read: fn(String) -> Result(String, Nil),
  variable variable: String,
  default default: Int,
  least least: Int,
  most most: Int,
) -> Result(Int, SettingRefusal) {
  case read(variable) {
    Error(Nil) -> Ok(default)
    Ok(text) ->
      case int.parse(text) {
        Error(Nil) ->
          Error(NotAWholeNumber(variable:, value: text, least:, most:))
        Ok(value) if value < least || value > most ->
          Error(OutOfRange(variable:, value:, least:, most:))
        Ok(value) -> Ok(value)
      }
  }
}

/// A sentence that says which variable was refused, its value and what it may
/// be, for the log and the stop at start.
pub fn describe(refusal refusal: SettingRefusal) -> String {
  case refusal {
    NotAWholeNumber(variable:, value:, least:, most:) ->
      variable
      <> " is \""
      <> value
      <> "\", which is not a whole number from "
      <> int.to_string(least)
      <> " to "
      <> int.to_string(most)
    OutOfRange(variable:, value:, least:, most:) ->
      variable
      <> " is "
      <> int.to_string(value)
      <> ", which is outside "
      <> int.to_string(least)
      <> " to "
      <> int.to_string(most)
  }
}
