//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of CreateResult that `schema.toml` names, each with the evidence
//// for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type CreateResult {
  /// The value 3, the fact file's `opcode.0xdc`.
  CreateOk
  /// The value 4, the fact file's `lua.Character.OnCreateCharacterFailed`.
  CreateFailed
  /// The value 6, the fact file's `lua.Character.OnCreateCharacterFailed`.
  NameUnavailable
  /// The value 9, the fact file's `lua.Character.OnCreateCharacterFailed`.
  AccountFull
  /// The value 10, the fact file's `lua.Character.OnCreateCharacterFailed`.
  NameLength
  /// The value 11, the fact file's `lua.Character.OnCreateCharacterFailed`.
  OpposingFaction
  /// The value 44, the fact file's `lua.Character.OnCreateCharacterFailed`.
  CharactersOnline
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: CreateResult) -> Int {
  case value {
    CreateOk -> 3
    CreateFailed -> 4
    NameUnavailable -> 6
    AccountFull -> 9
    NameLength -> 10
    OpposingFaction -> 11
    CharactersOnline -> 44
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> CreateResult {
  case number {
    3 -> CreateOk
    4 -> CreateFailed
    6 -> NameUnavailable
    9 -> AccountFull
    10 -> NameLength
    11 -> OpposingFaction
    44 -> CharactersOnline
    other -> Other(other)
  }
}
