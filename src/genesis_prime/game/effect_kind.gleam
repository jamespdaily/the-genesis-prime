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
////   the server reads the rows whose aim includes the caster, and the rows aimed at
////   the primary target, the area or both for the creatures a strike hits
////   (`Spell4Effects.effectType.11.change`).
//// - **ForcedMove** (3) moves the unit it aims at; the server lists the rows aimed at
////   the caster in the go, and the client moves its own unit and reports the move
////   (`Spell4Effects.effectType.3.player`), and throws the creatures a row aimed at the
////   primary target, the area or both strikes (`Spell4Effects.effectType.3.other_unit`).
//// - **CooldownModifier** (73) changes the spell cooldowns of the unit it aims at; the
////   server reads the rows whose aim includes the caster
////   (`Spell4Effects.effectType.73`).
//// - **Stealth** (83) holds the caster stealthed while the effect lasts, and
////   **RemoveStealth** (84) ends the stealth its unit holds; the client has no case
////   for either, so the server tells it with 0x8f5; the server reads the rows aimed at
////   the caster (`Spell4Effects.effectType.83`, `Spell4Effects.effectType.84`).
//// - **Heal** restores a vital of the unit it aims at: health for a Heal (10), shield
////   for a HealShields (118); the server reads the rows whose aim reaches the caster
////   (`Spell4Effects.effectType.10`, `Spell4Effects.effectType.118`).
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
//// - **Scale** (18) resizes the unit it lands on; the client does all of it, so the
////   server lists the row in the go with its life, as a Fluff row is
////   (`Spell4Effects.effectType.18`).
//// - **ItemVisualSwap** (76) swaps the visual of the unit it lands on for its time and
////   restores it when its node ends; the client does all of it, so the server lists the
////   row in the go with its delay and no lifetime, sends no 0x933 and keeps no look
////   (`Spell4Effects.effectType.76`).
//// - **RavelSignal** (81) signals a script the client does not hold; the client gives
////   it no class, so the server lists the row with its life and does no more
////   (`Spell4Effects.effectType.81`).
//// - **FullScreenEffect** (95) draws a full-screen visual over the player's view for its
////   life, for the player's own unit only; the client does all of it, so the server lists
////   the row aimed at the caster in the go with its life
////   (`Spell4Effects.effectType.95`).
//// - **PropertyConversion** (145) adds a share of one property of its holder to
////   another while it lasts; the client works out no property, so the server computes
////   the amount and sends the value; the server reads the rows aimed at the caster
////   (`Spell4Effects.effectType.145`).
//// - **DisguiseOutfit** (112) changes the look of the unit it aims at for its time; the
////   client has no class for it, so a look changes only by the server's 0x933 or 0x905
////   (`Spell4Effects.effectType.112`); the server reads the rows aimed at the caster.
//// - **Absorption** (29) gives the unit it lands on a pool that takes damage before its
////   shield and health; the client has no class for it, so the server keeps the pool and
////   sends its sum as stat 22; the server reads the rows whose aim reaches the caster
////   (`Spell4Effects.effectType.29`).
//// - **Activate** (7) is the effect a creature's activate spell has: the client's apply is
////   empty, so the server only names the activated unit in the go with the row's effect
////   id and raises `Activated` (`Spell4Effects.effectType.7`, genesis_prime/game/activate).
//// - **Immunity** (79) makes its unit immune to one effect type, named by `dataBits00`
////   (8 is Damage); the client has no class for it and reads nothing, so no rule of the
////   server reads it and the coverage measure counts it unhandled; only a creature's guard
////   spell is checked for it (`immune_to`, genesis_prime/world_map/creature_guard_spells;
////   `Spell4Effects.effectType.79`, enum `0x140c34140`).
//// - **Despawn** (97) removes the creatures it aims at past the caster after its delay; the
////   client reads no row of this type and sees the removal only as 0x355
////   (`Spell4Effects.effectType.97`). A row is read when its targetFlags name a unit past the
////   caster (`is_row_read`); the plan leaves out a row aimed at the caster alone, and one
////   whose dataBits00 or dataBits01 is not 0, by name (genesis_prime/game/spell_plan
////   `despawn_reading`).
//// - **UnitState** (15) holds a unit state on the unit it aims at for its time; the client
////   reads no row of this type (its effect switch has no case 15) and shows a held state
////   only through the cast results it gives (`Spell4Effects.effectType.15`). A row is read
////   when its targetFlags name a unit past the caster (`is_row_read`); the plan leaves out a
////   row aimed at the caster alone, one that lasts until removed, one behind a persistence
////   prerequisite and one whose dataBits01 to dataBits09 is not 0, by name
////   (genesis_prime/game/spell_plan `unit_state_reading`). The coverage measure counts a
////   row read only when a creature's held state of it refuses something: a row of a state
////   with no reading, with no duration or of a spell with no Spell4 row is held where it can
////   be and counted not read (dev/genesis_prime/coverage/effect_row).
//// - **NpcExecutionDelay** (35) holds the creature that casts it still for its duration after
////   the go its phases name; the client has no case for it (its effect switch skips 35), so
////   the meaning is the server's reading and the hold's start a guess. A row is read when its
////   targetFlags are the caster alone (1); the plan leaves out a row aimed at another unit,
////   and one with no duration, by name (genesis_prime/game/spell_plan `delay_reading`). A
////   player's cast reads none (`Spell4Effects.effectType.35`).
//// - **Unread** is any other type: the client's data holds it and no rule of the
////   server reads it.
////
//// Reading a row's columns stays with each rule; this decode looks at the type
//// only, and `is_row_read` adds the aim for the types a rule reads for some aims.

import gleam/bool
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
  /// A CCStateSet effect (4): holds any of the 28 crowd-control states on the unit it
  /// aims at, a creature or the caster (`Spell4Effects.effectType.4`).
  CrowdControl
  /// A UnitPropertyModifier effect (11): changes a property of the unit it aims at
  /// for its time (`Spell4Effects.effectType.11.change`). A row is read when its
  /// targetFlags include the caster (it changes the caster) or are 2, 4 or 6, the
  /// primary target, the area or both (it changes the creatures a strike hits); any
  /// other aim is not read (`is_row_read`).
  PropertyModifier
  /// A ForcedMove effect (3): moves the unit it aims at. A row is read when its
  /// targetFlags include the caster, whose client moves itself
  /// (`Spell4Effects.effectType.3.player`), or are 2, 4 or 6, the creatures a strike
  /// hits, which the server moves itself (`Spell4Effects.effectType.3.other_unit`); any
  /// other aim is not read (`is_row_read`).
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
  /// A Heal (10) or HealShields (118) effect: restores `vital` of the unit it aims at
  /// (`Spell4Effects.effectType.10`, `Spell4Effects.effectType.118`). A row is read when
  /// its targetFlags include the caster (bit 1) or name the primary target alone (2),
  /// which a spell cast on the caster makes the caster; a row aimed only at the area or
  /// at the primary target and the area is not read (`is_row_read`).
  Heal(vital: Vital)
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
  /// A Scale effect (18): resizes the unit it lands on, any unit
  /// (`Spell4Effects.effectType.18`).
  Scale
  /// An ItemVisualSwap effect (76): swaps the visual of the unit it lands on and restores
  /// it when the node ends, all in the client (`Spell4Effects.effectType.76`).
  ItemVisualSwap
  /// A RavelSignal effect (81): signals a script the client does not hold
  /// (`Spell4Effects.effectType.81`).
  RavelSignal
  /// A FullScreenEffect effect (95): draws a full-screen visual over the view of the
  /// player's own unit for its life (`Spell4Effects.effectType.95`). A row is read when
  /// its targetFlags include the caster (bit 1), the only unit the client draws it for
  /// (`is_row_read`).
  FullScreenEffect
  /// A UnitPropertyConversion effect (145): adds a share of one property of its holder to
  /// another (`Spell4Effects.effectType.145`). A row is read when its targetFlags include
  /// the caster (`is_row_read`).
  PropertyConversion
  /// A DisguiseOutfit effect (112): changes the look of the unit it aims at
  /// (`Spell4Effects.effectType.112`). A row is read when its targetFlags include the
  /// caster (`is_row_read`).
  DisguiseOutfit
  /// An Absorption effect (29): gives the unit it aims at a pool of damage that is taken
  /// before its shield and health (`Spell4Effects.effectType.29`). A row is read when its
  /// targetFlags include the caster (bit 1) or name the primary target alone (2), which a
  /// spell cast on the caster makes the caster; a row aimed only at the area or at the
  /// primary target and the area is not read (`is_row_read`).
  Absorption
  /// An Activate effect (7): the activate spell of a creature the player right-clicked
  /// (`Spell4Effects.effectType.7`). Every row is read, whatever it aims at; the activate
  /// plan lists it (genesis_prime/game/activate), no go of an ability applies it.
  Activate
  /// An Immunity effect (79): immune to the effect type `dataBits00` names
  /// (`Spell4Effects.effectType.79`). No rule reads it as an effect, so it is not read
  /// (`is_read`); `immune_to` names what a row is immune to.
  Immunity
  /// A DespawnUnit effect (97): removes the creatures it aims at past the caster after its
  /// delay (`Spell4Effects.effectType.97`).
  Despawn
  /// A UnitStateSet effect (15): holds the unit state `dataBits00` names on the unit it aims
  /// at for its duration (`Spell4Effects.effectType.15`).
  UnitState
  /// An NpcExecutionDelay effect (35): holds the creature that casts it still for its
  /// duration after the go its phases name (`Spell4Effects.effectType.35`).
  NpcExecutionDelay
  /// A type no rule reads.
  Unread(effect_type: Int)
}

/// What a heal restores: the health of type 10, the shield of type 118.
pub type Vital {
  Health
  Shield
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
    10 -> Heal(vital: Health)
    118 -> Heal(vital: Shield)
    64 -> ShieldOverload
    14 -> Proc
    52 -> InterruptArmor
    18 -> Scale
    76 -> ItemVisualSwap
    81 -> RavelSignal
    95 -> FullScreenEffect
    145 -> PropertyConversion
    112 -> DisguiseOutfit
    29 -> Absorption
    7 -> Activate
    79 -> Immunity
    97 -> Despawn
    15 -> UnitState
    35 -> NpcExecutionDelay
    other -> Unread(effect_type: other)
  }
}

/// Whether some rule reads the effect type: the coverage measure's "handled". A
/// PropertyModifier, PropertyConversion, DisguiseOutfit, ForcedMove or CooldownModifier
/// counts as read for its rows aimed at the caster (a PropertyModifier also for those
/// aimed at struck units), which `is_row_read` tells apart from the others.
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
    | Proc
    | Scale
    | ItemVisualSwap
    | RavelSignal
    | FullScreenEffect
    | PropertyConversion
    | Heal(..)
    | ShieldOverload
    | InterruptArmor
    | DisguiseOutfit
    | Absorption
    | Activate
    | Despawn
    | UnitState
    | NpcExecutionDelay -> True
    Immunity | Unread(..) -> False
  }
}

/// Whether a row of the effect type with these `targetFlags` is read: every row of a
/// type `is_read` for, except that a PropertyConversion, CooldownModifier,
/// Stealth, RemoveStealth, Proc, DisguiseOutfit or FullScreenEffect row is read only when its flags
/// include the caster (bit 1, `Spell4Effects.targetFlags`), a PropertyModifier or
/// ForcedMove row when they include the caster or are 2, 4 or 6 (the units a strike
/// hits), a Heal,
/// InterruptArmor or Absorption row when they include the caster or are the primary
/// target alone (2), and a ShieldOverload row only when they are the area alone (4); a
/// row aimed at other units is left out. A plan of
/// a spell with a Stealth or RemoveStealth row aimed other than at the caster alone
/// fails to load (genesis_prime/game/spell_plan `StealthAimNotRead`).
pub fn is_row_read(
  effect_type effect_type: Int,
  target_flags target_flags: Int,
) -> Bool {
  case kind_of(effect_type:) {
    PropertyModifier | ForcedMove ->
      int.bitwise_and(target_flags, 1) == 1
      || target_flags == 2
      || target_flags == 4
      || target_flags == 6
    PropertyConversion
    | CooldownModifier
    | Stealth
    | RemoveStealth
    | Proc
    | DisguiseOutfit
    | FullScreenEffect -> int.bitwise_and(target_flags, 1) == 1
    Heal(..) | InterruptArmor | Absorption ->
      int.bitwise_and(target_flags, 1) == 1 || target_flags == 2
    ShieldOverload -> target_flags == 4
    Despawn | UnitState -> target_flags >= 2 && target_flags <= 7
    NpcExecutionDelay -> target_flags == 1
    Proxy
    | Damage
    | VitalModifier
    | Fluff
    | ForceRemove
    | CrowdControl
    | Scale
    | ItemVisualSwap
    | RavelSignal
    | Activate -> True
    Immunity | Unread(..) -> False
  }
}

/// The kind of effect an Immunity row (type 79) makes its unit immune to, from its
/// `dataBits00` read as an effect type (`Spell4Effects.effectType.79`, enum
/// `0x140c34140`), or `Error(Nil)` when the effect type is not 79.
pub fn immune_to(
  effect_type effect_type: Int,
  data_bits00 data_bits00: Int,
) -> Result(Kind, Nil) {
  use <- bool.guard(when: kind_of(effect_type:) != Immunity, return: Error(Nil))
  Ok(kind_of(effect_type: data_bits00))
}
