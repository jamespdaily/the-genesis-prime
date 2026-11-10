//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of InteractionResult that `schema.toml` names, each with the
//// evidence for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type InteractionResult {
  /// The value 0, the fact file's `opcode.0x805.fields`.
  Failed
  /// The value 1, the fact file's `opcode.0x805.fields`.
  Succeeded
  /// The value 2, the fact file's `opcode.0x805.fields`.
  CancelledBeforeStart
  /// The value 3, the fact file's `opcode.0x805.fields`.
  Started
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: InteractionResult) -> Int {
  case value {
    Failed -> 0
    Succeeded -> 1
    CancelledBeforeStart -> 2
    Started -> 3
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> InteractionResult {
  case number {
    0 -> Failed
    1 -> Succeeded
    2 -> CancelledBeforeStart
    3 -> Started
    other -> Other(other)
  }
}
