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
//// - **CrowdControl** (4) holds a crowd-control state on the unit it aims at for its
////   time (`Spell4Effects.effectType.4`).
//// - **PropertyModifier** (11) changes a property of the unit it aims at for its time;
////   the server reads the rows whose aim includes the caster
////   (`Spell4Effects.effectType.11.change`).
//// - **ForcedMove** (3) moves the unit it aims at; the server lists the rows aimed at
////   the caster in the go, and the client moves its own unit and reports the move
////   (`Spell4Effects.effectType.3.player`).
//// - **CooldownModifier** (73) changes the spell cooldowns of the unit it aims at; the
////   server reads the rows whose aim includes the caster
////   (`Spell4Effects.effectType.73`).
//// - **Unread** is any other type: the client's data holds it and no rule of the
////   server reads it.
////
//// Reading a row's columns stays with each rule; this decode looks at the type
//// only, and `is_row_read` adds the aim for the types a rule reads for some aims.

import gleam/int

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
  /// A CCStateSet effect (4): holds a crowd-control state, a stun or a knockdown, on
  /// the unit it aims at (`Spell4Effects.effectType.4`).
  CrowdControl
  /// A UnitPropertyModifier effect (11): changes a property of the unit it aims at
  /// for its time (`Spell4Effects.effectType.11.change`). A row is read when its
  /// targetFlags include the caster; a row aimed only at other units is not read
  /// (`is_row_read`).
  PropertyModifier
  /// A ForcedMove effect (3): moves the unit it aims at. A row is read when its
  /// targetFlags include the caster, whose client moves itself
  /// (`Spell4Effects.effectType.3.player`); a row aimed only at other units, which the
  /// server would move itself (`Spell4Effects.effectType.3.other_unit`), is not read
  /// (`is_row_read`).
  ForcedMove
  /// A ModifySpellCooldown effect (73): changes the spell cooldowns of the unit it aims
  /// at. A row is read when its targetFlags include the caster
  /// (`Spell4Effects.effectType.73`); a row aimed only at other units changes cooldowns
  /// no server rule keeps, and is not read (`is_row_read`).
  CooldownModifier
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
    4 -> CrowdControl
    11 -> PropertyModifier
    3 -> ForcedMove
    73 -> CooldownModifier
    other -> Unread(effect_type: other)
  }
}

/// Whether some rule reads the effect type: the coverage measure's "handled". A
/// PropertyModifier, ForcedMove or CooldownModifier counts as read for its rows aimed
/// at the caster, which `is_row_read` tells apart from the others.
pub fn is_read(effect_type effect_type: Int) -> Bool {
  case kind_of(effect_type:) {
    Proxy
    | Damage
    | VitalModifier
    | Fluff
    | ForceRemove
    | CrowdControl
    | PropertyModifier
    | ForcedMove
    | CooldownModifier -> True
    Unread(..) -> False
  }
}

/// Whether a row of the effect type with these `targetFlags` is read: every row of a
/// type `is_read` for, except that a PropertyModifier, ForcedMove or CooldownModifier
/// row is read only when its flags include the caster (bit 1,
/// `Spell4Effects.targetFlags`); a row aimed only at other units is left out.
pub fn is_row_read(
  effect_type effect_type: Int,
  target_flags target_flags: Int,
) -> Bool {
  case kind_of(effect_type:) {
    PropertyModifier | ForcedMove | CooldownModifier ->
      int.bitwise_and(target_flags, 1) == 1
    Proxy | Damage | VitalModifier | Fluff | ForceRemove | CrowdControl -> True
    Unread(..) -> False
  }
}
