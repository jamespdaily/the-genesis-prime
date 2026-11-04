//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of CombatResult that `schema.toml` names, each with the evidence
//// for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type CombatResult {
  /// The value 0, the fact file's `GameLib.CodeEnumCombatResult`.
  Avoid
  /// The value 1, the fact file's `GameLib.CodeEnumCombatResult`.
  Critical
  /// The value 2, the fact file's `GameLib.CodeEnumCombatResult`.
  Hit
  /// The value 3, the fact file's `GameLib.CodeEnumCombatResult`.
  NeedsTelegraphEvaluation
  /// The value 4, the fact file's `GameLib.CodeEnumCombatResult`.
  OutsideTelegraph
  /// The value 5, the fact file's `GameLib.CodeEnumCombatResult`.
  OutsideTelegraphInvalid
  /// The value 6, the fact file's `GameLib.CodeEnumCombatResult`.
  InsideTelegraph
  /// The value 7, the fact file's `GameLib.CodeEnumCombatResult`.
  NeedsHitResultCalc
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: CombatResult) -> Int {
  case value {
    Avoid -> 0
    Critical -> 1
    Hit -> 2
    NeedsTelegraphEvaluation -> 3
    OutsideTelegraph -> 4
    OutsideTelegraphInvalid -> 5
    InsideTelegraph -> 6
    NeedsHitResultCalc -> 7
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> CombatResult {
  case number {
    0 -> Avoid
    1 -> Critical
    2 -> Hit
    3 -> NeedsTelegraphEvaluation
    4 -> OutsideTelegraph
    5 -> OutsideTelegraphInvalid
    6 -> InsideTelegraph
    7 -> NeedsHitResultCalc
    other -> Other(other)
  }
}
