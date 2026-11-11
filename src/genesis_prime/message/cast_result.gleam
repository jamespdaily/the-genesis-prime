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
  /// The value 11, the fact file's `opcode.0x801`.
  SpellInterrupted
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
  /// The value 22, the fact file's `0x1403998e0`.
  ItemBad
  /// The value 26, the fact file's `0x140398cc0`.
  ItemTooHighLevel
  /// The value 28, the fact file's `0x140398cc0`.
  ItemQuestRequirementsNotMet
  /// The value 29, the fact file's `0x140398cc0`.
  ItemObjectiveComplete
  /// The value 30, the fact file's `Spell.CodeEnumCastResult`.
  CasterUnknown
  /// The value 31, the fact file's `Spell.CodeEnumCastResult`.
  CasterMustHaveTarget
  /// The value 33, the fact file's `Spell.CodeEnumCastResult`.
  CasterNotIncontrolOfSelf
  /// The value 34, the fact file's `Spell.CodeEnumCastResult`.
  CasterMovement
  /// The value 51, the fact file's `Spell4CastResult.vital_cost`.
  CasterVitalCostResource1
  /// The value 53, the fact file's `Spell4CastResult.vital_cost`.
  CasterVitalCostResource3
  /// The value 55, the fact file's `Spell4CastResult.vital_cost`.
  CasterVitalCostResource5
  /// The value 57, the fact file's `Spell.CodeEnumCastResult`.
  CasterCannotBeDead
  /// The value 89, the fact file's `0x1403b44b0`.
  TargetGroup
  /// The value 90, the fact file's `Spell.CodeEnumCastResult`.
  TargetUnknown
  /// The value 91, the fact file's `Spell.CodeEnumCastResult`.
  NoTarget
  /// The value 99, the fact file's `Spell.CodeEnumCastResult`.
  TargetFaction
  /// The value 100, the fact file's `Spell.CodeEnumCastResult`.
  TargetIsNotUseable
  /// The value 101, the fact file's `Spell.CodeEnumCastResult`.
  TargetOrientation
  /// The value 104, the fact file's `Spell.CodeEnumCastResult`.
  TargetRangeMin
  /// The value 105, the fact file's `Spell.CodeEnumCastResult`.
  TargetRangeMax
  /// The value 106, the fact file's `Spell.CodeEnumCastResult`.
  TargetCannotBeDead
  /// The value 107, the fact file's `Spell.CodeEnumCastResult`.
  TargetMustBeDead
  /// The value 146, the fact file's `Spell.CodeEnumCastResult.146`.
  ClientSideInteractionFail
  /// The value 151, the fact file's `0x1405648a0`.
  PrereqCasterCast
  /// The value 166, the fact file's `Spell.CodeEnumCastResult`.
  CasterNeedsLos
  /// The value 169, the fact file's `Spell.CodeEnumCastResult`.
  WeaponSlot
  /// The value 182, the fact file's `Spell.CodeEnumCastResult`.
  SpellNoCharges
  /// The value 183, the fact file's `Spell.CodeEnumCastResult`.
  TargetRangeVertical
  /// The value 281, the fact file's `0x1405648a0`.
  PrereqTargetCast
  /// The value 282, the fact file's `0x1405648a0`.
  PrereqCasterPersistence
  /// The value 283, the fact file's `0x1405648a0`.
  PrereqTargetPersistence
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
    SpellInterrupted -> 11
    SpellAlreadyCasting -> 13
    SpellGlobalCooldown -> 14
    SpellCooldown -> 15
    SpellGroupCooldown -> 16
    SpellPreRequisites -> 17
    ItemBad -> 22
    ItemTooHighLevel -> 26
    ItemQuestRequirementsNotMet -> 28
    ItemObjectiveComplete -> 29
    CasterUnknown -> 30
    CasterMustHaveTarget -> 31
    CasterNotIncontrolOfSelf -> 33
    CasterMovement -> 34
    CasterVitalCostResource1 -> 51
    CasterVitalCostResource3 -> 53
    CasterVitalCostResource5 -> 55
    CasterCannotBeDead -> 57
    TargetGroup -> 89
    TargetUnknown -> 90
    NoTarget -> 91
    TargetFaction -> 99
    TargetIsNotUseable -> 100
    TargetOrientation -> 101
    TargetRangeMin -> 104
    TargetRangeMax -> 105
    TargetCannotBeDead -> 106
    TargetMustBeDead -> 107
    ClientSideInteractionFail -> 146
    PrereqCasterCast -> 151
    CasterNeedsLos -> 166
    WeaponSlot -> 169
    SpellNoCharges -> 182
    TargetRangeVertical -> 183
    PrereqTargetCast -> 281
    PrereqCasterPersistence -> 282
    PrereqTargetPersistence -> 283
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
    11 -> SpellInterrupted
    13 -> SpellAlreadyCasting
    14 -> SpellGlobalCooldown
    15 -> SpellCooldown
    16 -> SpellGroupCooldown
    17 -> SpellPreRequisites
    22 -> ItemBad
    26 -> ItemTooHighLevel
    28 -> ItemQuestRequirementsNotMet
    29 -> ItemObjectiveComplete
    30 -> CasterUnknown
    31 -> CasterMustHaveTarget
    33 -> CasterNotIncontrolOfSelf
    34 -> CasterMovement
    51 -> CasterVitalCostResource1
    53 -> CasterVitalCostResource3
    55 -> CasterVitalCostResource5
    57 -> CasterCannotBeDead
    89 -> TargetGroup
    90 -> TargetUnknown
    91 -> NoTarget
    99 -> TargetFaction
    100 -> TargetIsNotUseable
    101 -> TargetOrientation
    104 -> TargetRangeMin
    105 -> TargetRangeMax
    106 -> TargetCannotBeDead
    107 -> TargetMustBeDead
    146 -> ClientSideInteractionFail
    151 -> PrereqCasterCast
    166 -> CasterNeedsLos
    169 -> WeaponSlot
    182 -> SpellNoCharges
    183 -> TargetRangeVertical
    281 -> PrereqTargetCast
    282 -> PrereqCasterPersistence
    283 -> PrereqTargetPersistence
    285 -> IllegalSpellCast
    317 -> Queued
    other -> Other(other)
  }
}
