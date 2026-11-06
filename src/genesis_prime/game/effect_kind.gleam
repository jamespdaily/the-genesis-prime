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
//// - **Stealth** (83) holds the caster stealthed while the effect lasts, and
////   **RemoveStealth** (84) ends the stealth its unit holds; the client has no case
////   for either, so the server tells it with 0x8f5; the server reads the rows aimed at
////   the caster (`Spell4Effects.effectType.83`, `Spell4Effects.effectType.84`).
//// - **ShieldHeal** (118) restores the shield of the unit it aims at; the server reads
////   the rows whose aim reaches the caster (`Spell4Effects.effectType.118`).
//// - **ShieldOverload** (64) overloads the shield of the units it aims at for its time;
////   the client marks and clears the overload itself, so the server lists the rows aimed
////   at the area on each struck unit (`Spell4Effects.effectType.64`).
//// - **Proc** (14) casts a spell when the holder's trigger happens; the client has no
////   case for it, so the server decides every fire; the server reads the rows aimed at
////   the caster whose trigger is one of the holder's own events
////   (`Spell4Effects.effectType.14`).
//// - **InterruptArmor** (52) adds Interrupt Armor to the unit it lands on for its time; the
////   client has no case for it, so the server raises the player's maximum (property 44)
////   and armor (stat 21) itself and reads the rows aimed at the caster
////   (`Spell4Effects.effectType.52`).
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
  /// A Stealth effect (83): the unit it aims at is stealthed while it lasts
  /// (`Spell4Effects.effectType.83`). A row is read when its targetFlags include the
  /// caster (`is_row_read`).
  Stealth
  /// A RemoveStealth effect (84): ends the stealth of the unit it aims at
  /// (`Spell4Effects.effectType.84`). Read as Stealth is.
  RemoveStealth
  /// A HealShields effect (118): restores shield to the unit it aims at
  /// (`Spell4Effects.effectType.118`). A row is read when its targetFlags include the
  /// caster (bit 1) or name the primary target alone (2), which a spell cast on the
  /// caster makes the caster; a row aimed only at the area or at the primary target and
  /// the area is not read (`is_row_read`).
  ShieldHeal
  /// A ShieldOverload effect (64): the units it aims at are overloaded while it lasts
  /// (`Spell4Effects.effectType.64`). A row is read when it aims at the area alone
  /// (`is_row_read`).
  ShieldOverload
  /// A Proc effect (14): casts a spell at its holder when the holder's trigger happens
  /// (`Spell4Effects.effectType.14`). A row is read when its targetFlags include the
  /// caster (`is_row_read`); the plan reads only the kinds the holder's own events make
  /// (genesis_prime/game/spell_plan `proc_read`).
  Proc
  /// A ModifyInterruptArmor effect (52): adds Interrupt Armor to the unit it aims at for
  /// its time (`Spell4Effects.effectType.52`). A row is read when its targetFlags include
  /// the caster (bit 1) or name the primary target alone (2), which a spell cast on the
  /// caster makes the caster; a row aimed only at the area or at other units is not read
  /// (`is_row_read`).
  InterruptArmor
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
    83 -> Stealth
    84 -> RemoveStealth
    118 -> ShieldHeal
    64 -> ShieldOverload
    14 -> Proc
    52 -> InterruptArmor
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
    | CooldownModifier
    | Stealth
    | RemoveStealth
    | ShieldHeal
    | ShieldOverload
    | Proc
    | InterruptArmor -> True
    Unread(..) -> False
  }
}

/// Whether a row of the effect type with these `targetFlags` is read: every row of a
/// type `is_read` for, except that a PropertyModifier, ForcedMove, CooldownModifier,
/// Stealth, RemoveStealth or Proc row is read only when its flags include the caster (bit 1,
/// `Spell4Effects.targetFlags`), a ShieldHeal or InterruptArmor row when they include the
/// caster or are the primary target alone (2), and a ShieldOverload row only when they are the area
/// alone (4); a row aimed at other units is left out. A plan of
/// a spell with a Stealth or RemoveStealth row aimed other than at the caster alone
/// fails to load (genesis_prime/game/spell_plan `StealthAimNotRead`).
pub fn is_row_read(
  effect_type effect_type: Int,
  target_flags target_flags: Int,
) -> Bool {
  case kind_of(effect_type:) {
    PropertyModifier
    | ForcedMove
    | CooldownModifier
    | Stealth
    | RemoveStealth
    | Proc -> int.bitwise_and(target_flags, 1) == 1
    ShieldHeal | InterruptArmor ->
      int.bitwise_and(target_flags, 1) == 1 || target_flags == 2
    ShieldOverload -> target_flags == 4
    Proxy | Damage | VitalModifier | Fluff | ForceRemove | CrowdControl -> True
    Unread(..) -> False
  }
}
