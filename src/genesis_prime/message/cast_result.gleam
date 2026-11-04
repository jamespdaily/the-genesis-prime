//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// The values of CastResult that `schema.toml` names, each with the evidence
//// for its meaning, and `Other` for any value it does not name.

/// The values of a field, as the client's code names them.
pub type CastResult {
  /// The value 1, the fact file's `Spell.CodeEnumCastResult`.
  UnableToCreateSpell
  /// The value 4, the fact file's `Spell.CodeEnumCastResult`.
  SpellUnknown
  /// The value 5, the fact file's `Spell.CodeEnumCastResult`.
  SpellBad
  /// The value 6, the fact file's `opcode.0x801`.
  SpellCancelled
  /// The value 13, the fact file's `Spell.CodeEnumCastResult`.
  SpellAlreadyCasting
  /// The value 14, the fact file's `Spell.CodeEnumCastResult`.
  SpellGlobalCooldown
  /// The value 15, the fact file's `Spell.CodeEnumCastResult`.
  SpellCooldown
  /// The value 16, the fact file's `Spell.CodeEnumCastResult`.
  SpellGroupCooldown
  /// The value 17, the fact file's `Spell.CodeEnumCastResult`.
  SpellPreRequisites
  /// The value 30, the fact file's `Spell.CodeEnumCastResult`.
  CasterUnknown
  /// The value 31, the fact file's `Spell.CodeEnumCastResult`.
  CasterMustHaveTarget
  /// The value 33, the fact file's `Spell.CodeEnumCastResult`.
  CasterNotIncontrolOfSelf
  /// The value 34, the fact file's `Spell.CodeEnumCastResult`.
  CasterMovement
  /// The value 57, the fact file's `Spell.CodeEnumCastResult`.
  CasterCannotBeDead
  /// The value 90, the fact file's `Spell.CodeEnumCastResult`.
  TargetUnknown
  /// The value 91, the fact file's `Spell.CodeEnumCastResult`.
  NoTarget
  /// The value 99, the fact file's `Spell.CodeEnumCastResult`.
  TargetFaction
  /// The value 101, the fact file's `Spell.CodeEnumCastResult`.
  TargetOrientation
  /// The value 104, the fact file's `Spell.CodeEnumCastResult`.
  TargetRangeMin
  /// The value 105, the fact file's `Spell.CodeEnumCastResult`.
  TargetRangeMax
  /// The value 106, the fact file's `Spell.CodeEnumCastResult`.
  TargetCannotBeDead
  /// The value 166, the fact file's `Spell.CodeEnumCastResult`.
  CasterNeedsLos
  /// The value 169, the fact file's `Spell.CodeEnumCastResult`.
  WeaponSlot
  /// The value 182, the fact file's `Spell.CodeEnumCastResult`.
  SpellNoCharges
  /// The value 183, the fact file's `Spell.CodeEnumCastResult`.
  TargetRangeVertical
  /// The value 285, the fact file's `Spell.CodeEnumCastResult`.
  IllegalSpellCast
  /// The value 317, the fact file's `Spell.CodeEnumCastResult`.
  Queued
  /// A value the schema does not name.
  Other(Int)
}

/// The number the encoder writes for a value.
pub fn to_value(value: CastResult) -> Int {
  case value {
    UnableToCreateSpell -> 1
    SpellUnknown -> 4
    SpellBad -> 5
    SpellCancelled -> 6
    SpellAlreadyCasting -> 13
    SpellGlobalCooldown -> 14
    SpellCooldown -> 15
    SpellGroupCooldown -> 16
    SpellPreRequisites -> 17
    CasterUnknown -> 30
    CasterMustHaveTarget -> 31
    CasterNotIncontrolOfSelf -> 33
    CasterMovement -> 34
    CasterCannotBeDead -> 57
    TargetUnknown -> 90
    NoTarget -> 91
    TargetFaction -> 99
    TargetOrientation -> 101
    TargetRangeMin -> 104
    TargetRangeMax -> 105
    TargetCannotBeDead -> 106
    CasterNeedsLos -> 166
    WeaponSlot -> 169
    SpellNoCharges -> 182
    TargetRangeVertical -> 183
    IllegalSpellCast -> 285
    Queued -> 317
    Other(number) -> number
  }
}

/// The value for a number the decoder read.
pub fn from_value(number: Int) -> CastResult {
  case number {
    1 -> UnableToCreateSpell
    4 -> SpellUnknown
    5 -> SpellBad
    6 -> SpellCancelled
    13 -> SpellAlreadyCasting
    14 -> SpellGlobalCooldown
    15 -> SpellCooldown
    16 -> SpellGroupCooldown
    17 -> SpellPreRequisites
    30 -> CasterUnknown
    31 -> CasterMustHaveTarget
    33 -> CasterNotIncontrolOfSelf
    34 -> CasterMovement
    57 -> CasterCannotBeDead
    90 -> TargetUnknown
    91 -> NoTarget
    99 -> TargetFaction
    101 -> TargetOrientation
    104 -> TargetRangeMin
    105 -> TargetRangeMax
    106 -> TargetCannotBeDead
    166 -> CasterNeedsLos
    169 -> WeaponSlot
    182 -> SpellNoCharges
    183 -> TargetRangeVertical
    285 -> IllegalSpellCast
    317 -> Queued
    other -> Other(other)
  }
}
