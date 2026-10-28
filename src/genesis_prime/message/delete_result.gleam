//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of DeleteResult that `schema.toml` names, each with the evidence
//// for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type DeleteResult {
  /// The value 0, the fact file's `opcode.0xe6`.
  DeleteOk
  /// The value 1, the fact file's
  /// `lua.CharacterSelection.OnCharacterDeleteResult`.
  DeleteFailed
  /// The value 2, the fact file's
  /// `lua.CharacterSelection.OnCharacterDeleteResult`.
  GuildMaster
  /// The value 42, the fact file's
  /// `lua.CharacterSelection.OnCharacterDeleteResult`.
  CharactersOnline
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: DeleteResult) -> Int {
  case value {
    DeleteOk -> 0
    DeleteFailed -> 1
    GuildMaster -> 2
    CharactersOnline -> 42
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> DeleteResult {
  case number {
    0 -> DeleteOk
    1 -> DeleteFailed
    2 -> GuildMaster
    42 -> CharactersOnline
    other -> Other(other)
  }
}
