//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of PlayRefusal that `schema.toml` names, each with the evidence
//// for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type PlayRefusal {
  /// The value 1, the fact file's `opcode.0x162`.
  FailedRename
  /// The value 2, the fact file's `opcode.0x162`.
  Failed
  /// The value 3, the fact file's `opcode.0x162`.
  FailedDisabled
  /// The value 4, the fact file's `opcode.0x162`.
  CharacterInWorld
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: PlayRefusal) -> Int {
  case value {
    FailedRename -> 1
    Failed -> 2
    FailedDisabled -> 3
    CharacterInWorld -> 4
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> PlayRefusal {
  case number {
    1 -> FailedRename
    2 -> Failed
    3 -> FailedDisabled
    4 -> CharacterInWorld
    other -> Other(other)
  }
}
