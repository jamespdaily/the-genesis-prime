//// The kind of a Spell4Effects row, decoded once from its `effectType`: the one
//// place the server names the effect types it reads. Every rule that sorts
//// effects by type calls `kind_of`, and the coverage measure counts a type as
//// handled when `kind_of` does not give `Unread` for it, so a rule and the
//// measure cannot disagree.
////
//// - **Proxy** (26) starts another spell (`Spell4Effects.effectType.26`).
//// - **Damage** (8) hits the units it aims at (`Spell.CodeEnumSpellEffectType.damage`).
//// - **VitalModifier** (1) changes a vital of its unit, which gives the caster a
////   resource (`Spell4Effects.effectType.1`).
//// - **Fluff** (17) gives its spell a life on a unit, shown as a buff
////   (`Spell4Effects.effectType.17`).
//// - **ForceRemove** (80) takes spells already on a unit off it
////   (`Spell4Effects.effectType.80`).
//// - **Unread** is any other type: the client's data holds it and no rule of the
////   server reads it.
////
//// Reading a row's columns stays with each rule; this decode looks at the type
//// only.

/// What a rule reads an effect as.
pub type Kind {
  Proxy
  Damage
  VitalModifier
  /// A Fluff effect (17): gives its spell a life on the unit it aims at, which
  /// shows as a buff (`Spell4Effects.effectType.17`).
  Fluff
  /// A SpellForceRemove effect (80): takes casts off the unit it aims at
  /// (`Spell4Effects.effectType.80`).
  ForceRemove
  /// A type no rule reads.
  Unread(effect_type: Int)
}

/// The kind of the effect type `effect_type` (`Spell4Effects.effectType`).
pub fn kind_of(effect_type effect_type: Int) -> Kind {
  case effect_type {
    26 -> Proxy
    8 -> Damage
    1 -> VitalModifier
    17 -> Fluff
    80 -> ForceRemove
    other -> Unread(effect_type: other)
  }
}

/// Whether some rule reads the effect type: the coverage measure's "handled".
pub fn is_read(effect_type effect_type: Int) -> Bool {
  case kind_of(effect_type:) {
    Proxy | Damage | VitalModifier | Fluff | ForceRemove -> True
    Unread(..) -> False
  }
}
