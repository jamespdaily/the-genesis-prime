//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of CrowdControlState that `schema.toml` names, each with the
//// evidence for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type CrowdControlState {
  /// The value 0, the fact file's `Unit.CodeEnumCCState`.
  Stun
  /// The value 1, the fact file's `Unit.CodeEnumCCState`.
  Sleep
  /// The value 2, the fact file's `Unit.CodeEnumCCState`.
  Root
  /// The value 3, the fact file's `Unit.CodeEnumCCState`.
  Disarm
  /// The value 4, the fact file's `Unit.CodeEnumCCState`.
  Silence
  /// The value 5, the fact file's `Unit.CodeEnumCCState`.
  Polymorph
  /// The value 6, the fact file's `Unit.CodeEnumCCState`.
  Fear
  /// The value 7, the fact file's `Unit.CodeEnumCCState`.
  Hold
  /// The value 8, the fact file's `Unit.CodeEnumCCState`.
  Knockdown
  /// The value 9, the fact file's `Unit.CodeEnumCCState`.
  Vulnerability
  /// The value 10, the fact file's `Unit.CodeEnumCCState`.
  VulnerabilityWithAct
  /// The value 11, the fact file's `Unit.CodeEnumCCState`.
  Disorient
  /// The value 12, the fact file's `Unit.CodeEnumCCState`.
  Disable
  /// The value 13, the fact file's `Unit.CodeEnumCCState`.
  Taunt
  /// The value 14, the fact file's `Unit.CodeEnumCCState`.
  Detaunt
  /// The value 15, the fact file's `Unit.CodeEnumCCState`.
  Blind
  /// The value 16, the fact file's `Unit.CodeEnumCCState`.
  Knockback
  /// The value 17, the fact file's `Unit.CodeEnumCCState`.
  Pushback
  /// The value 18, the fact file's `Unit.CodeEnumCCState`.
  Pull
  /// The value 19, the fact file's `Unit.CodeEnumCCState`.
  PositionSwitch
  /// The value 20, the fact file's `Unit.CodeEnumCCState`.
  Tether
  /// The value 21, the fact file's `Unit.CodeEnumCCState`.
  Snare
  /// The value 22, the fact file's `Unit.CodeEnumCCState`.
  Interrupt
  /// The value 23, the fact file's `Unit.CodeEnumCCState`.
  Daze
  /// The value 24, the fact file's `Unit.CodeEnumCCState`.
  Subdue
  /// The value 25, the fact file's `Unit.CodeEnumCCState`.
  Grounded
  /// The value 26, the fact file's `Unit.CodeEnumCCState`.
  DisableCinematic
  /// The value 27, the fact file's `Unit.CodeEnumCCState`.
  AbilityRestriction
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: CrowdControlState) -> Int {
  case value {
    Stun -> 0
    Sleep -> 1
    Root -> 2
    Disarm -> 3
    Silence -> 4
    Polymorph -> 5
    Fear -> 6
    Hold -> 7
    Knockdown -> 8
    Vulnerability -> 9
    VulnerabilityWithAct -> 10
    Disorient -> 11
    Disable -> 12
    Taunt -> 13
    Detaunt -> 14
    Blind -> 15
    Knockback -> 16
    Pushback -> 17
    Pull -> 18
    PositionSwitch -> 19
    Tether -> 20
    Snare -> 21
    Interrupt -> 22
    Daze -> 23
    Subdue -> 24
    Grounded -> 25
    DisableCinematic -> 26
    AbilityRestriction -> 27
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> CrowdControlState {
  case number {
    0 -> Stun
    1 -> Sleep
    2 -> Root
    3 -> Disarm
    4 -> Silence
    5 -> Polymorph
    6 -> Fear
    7 -> Hold
    8 -> Knockdown
    9 -> Vulnerability
    10 -> VulnerabilityWithAct
    11 -> Disorient
    12 -> Disable
    13 -> Taunt
    14 -> Detaunt
    15 -> Blind
    16 -> Knockback
    17 -> Pushback
    18 -> Pull
    19 -> PositionSwitch
    20 -> Tether
    21 -> Snare
    22 -> Interrupt
    23 -> Daze
    24 -> Subdue
    25 -> Grounded
    26 -> DisableCinematic
    27 -> AbilityRestriction
    other -> Other(other)
  }
}
