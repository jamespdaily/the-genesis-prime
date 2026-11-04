//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of DamageType that `schema.toml` names, each with the evidence
//// for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type DamageType {
  /// The value 1, the fact file's `GameLib.CodeEnumDamageType`.
  Physical
  /// The value 2, the fact file's `GameLib.CodeEnumDamageType`.
  Tech
  /// The value 3, the fact file's `GameLib.CodeEnumDamageType`.
  Magic
  /// The value 4, the fact file's `GameLib.CodeEnumDamageType`.
  Heal
  /// The value 5, the fact file's `GameLib.CodeEnumDamageType`.
  HealShields
  /// The value 6, the fact file's `GameLib.CodeEnumDamageType`.
  Fall
  /// The value 7, the fact file's `GameLib.CodeEnumDamageType`.
  Suffocate
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: DamageType) -> Int {
  case value {
    Physical -> 1
    Tech -> 2
    Magic -> 3
    Heal -> 4
    HealShields -> 5
    Fall -> 6
    Suffocate -> 7
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> DamageType {
  case number {
    1 -> Physical
    2 -> Tech
    3 -> Magic
    4 -> Heal
    5 -> HealShields
    6 -> Fall
    7 -> Suffocate
    other -> Other(other)
  }
}
