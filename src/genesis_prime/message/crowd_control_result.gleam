//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of CrowdControlResult that `schema.toml` names, each with the
//// evidence for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type CrowdControlResult {
  /// The value 0, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  Ok
  /// The value 1, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  InvalidCcState
  /// The value 2, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  NoTargetSpecified
  /// The value 3, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  TargetImmune
  /// The value 4, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  TargetInfiniteInterruptArmor
  /// The value 5, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  TargetInterruptArmorReduced
  /// The value 6, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  TargetInterruptArmorBlocked
  /// The value 7, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  StackingDoesNotStack
  /// The value 8, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  StackingShorterDuration
  /// The value 9, the fact file's `Unit.CodeEnumCCStateApplyRulesResult`.
  DiminishingReturnsTriggerCap
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: CrowdControlResult) -> Int {
  case value {
    Ok -> 0
    InvalidCcState -> 1
    NoTargetSpecified -> 2
    TargetImmune -> 3
    TargetInfiniteInterruptArmor -> 4
    TargetInterruptArmorReduced -> 5
    TargetInterruptArmorBlocked -> 6
    StackingDoesNotStack -> 7
    StackingShorterDuration -> 8
    DiminishingReturnsTriggerCap -> 9
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> CrowdControlResult {
  case number {
    0 -> Ok
    1 -> InvalidCcState
    2 -> NoTargetSpecified
    3 -> TargetImmune
    4 -> TargetInfiniteInterruptArmor
    5 -> TargetInterruptArmorReduced
    6 -> TargetInterruptArmorBlocked
    7 -> StackingDoesNotStack
    8 -> StackingShorterDuration
    9 -> DiminishingReturnsTriggerCap
    other -> Other(other)
  }
}
