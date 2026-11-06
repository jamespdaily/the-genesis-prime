//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of StatKind that `schema.toml` names, each with the evidence for
//// its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type StatKind {
  /// The value 10, the fact file's `opcode.0x938`.
  Level
  /// The value 20, the fact file's `opcode.0x938.resource_stats`.
  Shield
  /// The value 21, the fact file's `opcode.0x938.interrupt_armor`.
  InterruptArmor
  /// The value 22, the fact file's `opcode.0x938`.
  Absorption
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: StatKind) -> Int {
  case value {
    Level -> 10
    Shield -> 20
    InterruptArmor -> 21
    Absorption -> 22
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> StatKind {
  case number {
    10 -> Level
    20 -> Shield
    21 -> InterruptArmor
    22 -> Absorption
    other -> Other(other)
  }
}
