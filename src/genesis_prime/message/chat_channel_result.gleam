//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of ChatChannelResult that `schema.toml` names, each with the
//// evidence for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type ChatChannelResult {
  /// The value 1, the fact file's `lua.ChatSystemLib.ChatChannelResult`.
  DoesntExist
  /// The value 3, the fact file's `lua.ChatSystemLib.ChatChannelResult`.
  NoPermissions
  /// The value 8, the fact file's `lua.ChatSystemLib.ChatChannelResult`.
  NotInGroup
  /// The value 17, the fact file's `lua.ChatSystemLib.ChatChannelResult`.
  InvalidMessageText
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: ChatChannelResult) -> Int {
  case value {
    DoesntExist -> 1
    NoPermissions -> 3
    NotInGroup -> 8
    InvalidMessageText -> 17
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> ChatChannelResult {
  case number {
    1 -> DoesntExist
    3 -> NoPermissions
    8 -> NotInGroup
    17 -> InvalidMessageText
    other -> Other(other)
  }
}
