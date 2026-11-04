//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of MissReason that `schema.toml` names, each with the evidence
//// for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type MissReason {
  /// The value 0, the fact file's `opcode.0x7fb`.
  Dodge
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: MissReason) -> Int {
  case value {
    Dodge -> 0
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> MissReason {
  case number {
    0 -> Dodge
    other -> Other(other)
  }
}
