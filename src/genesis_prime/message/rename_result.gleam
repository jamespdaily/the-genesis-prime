//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of RenameResult that `schema.toml` names, each with the evidence
//// for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type RenameResult {
  /// The value 13, the fact file's
  /// `lua.CharacterSelection.OnCharacterRenameResult`.
  RenameFailed
  /// The value 14, the fact file's
  /// `lua.CharacterSelection.OnCharacterRenameResult`.
  InternalError
  /// The value 15, the fact file's
  /// `lua.CharacterSelection.OnCharacterRenameResult`.
  NameLength
  /// The value 16, the fact file's
  /// `lua.CharacterSelection.OnCharacterRenameResult`.
  NameUnavailable
  /// The value 17, the fact file's
  /// `lua.CharacterSelection.OnCharacterRenameResult`.
  NoRename
  /// The value 18, the fact file's `opcode.0x14b`.
  RenameOk
  /// The value 43, the fact file's
  /// `lua.CharacterSelection.OnCharacterRenameResult`.
  CharactersOnline
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: RenameResult) -> Int {
  case value {
    RenameFailed -> 13
    InternalError -> 14
    NameLength -> 15
    NameUnavailable -> 16
    NoRename -> 17
    RenameOk -> 18
    CharactersOnline -> 43
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> RenameResult {
  case number {
    13 -> RenameFailed
    14 -> InternalError
    15 -> NameLength
    16 -> NameUnavailable
    17 -> NoRename
    18 -> RenameOk
    43 -> CharactersOnline
    other -> Other(other)
  }
}
