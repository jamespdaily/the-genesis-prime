//// The game's settings that are the server's choice or the operator's: values
//// the client's own data does not fix. They are read once at start from the
//// environment (`from_environment`) into one `GameSettings`, which every game
//// connection is made with (genesis_prime/game/connection).
////
//// | Setting | Variable | Default and its source | Allowed |
//// | --- | --- | --- | --- |
//// | `camp_countdown_ms` | `GENESIS_CAMP_COUNTDOWN_MS` | 10,000: Jim's choice, 2026-11-03; no retail record, and the client has none (opcode.0x92.countdown_source) | 0 to 59,999: the exit window shows only seconds, as `00:SS`, with no minutes field (opcode.0x92.countdown_range) |
//// | `character_slots` | none | 2: the client's count for an account with no entitlement (lua.CharacterSelection.OnLoadFromCharacter) | |
////
//// - **A variable that is set** replaces its setting's default. A value that
////   is not a whole number, or lies outside the allowed range, is refused with
////   the variable, the value and the range, and the server stops at start with
////   that text, as it does for GENESIS_GAME_ADDRESS.
//// - **A variable that is not set** leaves the default.
//// - **A countdown of 0** is allowed: the client then runs a camp that is due
////   at once, with no window (opcode.0x92.countdown_range).

/// The game's settings. `camp_countdown_ms` is the countdown the server gives
/// a camp, in milliseconds; `character_slots` is the number of characters an
/// account may have.
pub type GameSettings {
  GameSettings(camp_countdown_ms: Int, character_slots: Int)
}

/// Why a variable's value is refused.
pub type SettingRefusal {
  /// The value is not a whole number.
  NotAWholeNumber(variable: String, value: String)
  /// The value is a whole number outside `least` to `most`, both allowed.
  OutOfRange(variable: String, value: Int, least: Int, most: Int)
}

/// The settings with no variable set.
pub fn defaults() -> GameSettings {
  GameSettings(camp_countdown_ms: 10_000, character_slots: 2)
}

/// The defaults, with each variable that `read` finds replacing its setting;
/// `read` gives a variable's text, or `Error(Nil)` when it is not set. The
/// first variable whose value is refused is the `Error`.
pub fn from_environment(
  read _read: fn(String) -> Result(String, Nil),
) -> Result(GameSettings, SettingRefusal) {
  panic as "built in the next commit: each GENESIS_ variable that is set replaces its default, a refused value is an Error"
}

/// A sentence that says which variable was refused, its value and what it may
/// be, for the log and the stop at start.
pub fn describe(refusal _refusal: SettingRefusal) -> String {
  panic as "built in the next commit: the variable, the value and the allowed range"
}
