//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of StaticUnitType that `schema.toml` names, each with the
//// evidence for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type StaticUnitType {
  /// The value 10, the fact file's `world_data.entity_type`.
  Simple
  /// The value 11, the fact file's `world_data.entity_type`.
  Platform
  /// The value 32, the fact file's `world_data.entity_type`.
  SimpleCollidable
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: StaticUnitType) -> Int {
  case value {
    Simple -> 10
    Platform -> 11
    SimpleCollidable -> 32
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> StaticUnitType {
  case number {
    10 -> Simple
    11 -> Platform
    32 -> SimpleCollidable
    other -> Other(other)
  }
}
