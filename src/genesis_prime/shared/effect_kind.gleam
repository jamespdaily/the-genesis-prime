//// The kind of a Spell4Effects row, decoded once from its `effectType`: the one
//// place the server names the effect types it reads. Every rule that sorts effects
//// by type calls `kind_of`, and the coverage measure counts a type as handled when
//// `kind_of` does not give `Unread` for it.
////
////   `effectType` --`kind_of`--> `Kind`
////   `Kind` --`is_read`--> whether any rule reads the type
////   `Kind` + `targetFlags` --`is_row_read`--> whether a rule reads the row
////   Immunity `dataBits00` --`immune_to`--> the kind the unit is immune to
////
//// - `kind_of` decodes the effect type (`Spell4Effects.effectType`).
//// - `is_read` is the coverage measure's "handled": some rule reads the type.
//// - `is_row_read` adds the row's aim for the types a rule reads for some aims only
////   (`Spell4Effects.targetFlags`).
//// - `immune_to` reads an Immunity row's `dataBits00` as the effect type the unit is
////   immune to (`Spell4Effects.effectType.79`, enum `0x140c34140`).
////
//// Reading a row's columns stays with each rule. What each kind does, and its
//// evidence, sits on its `Kind` variant below.

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
  /// (genesis_prime/shared/spell_plan `proc_read`).
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
  /// A SummonPet effect (98): creates the creature `dataBits00` names for the caster
  /// (`Spell4Effects.effectType.98`). No rule reads it as an effect, so it is not read
  /// (`is_read`).
  SummonPet
  /// A DespawnUnit effect (97): removes the creatures it aims at past the caster after its
  /// delay (`Spell4Effects.effectType.97`).
  Despawn
  /// A UnitStateSet effect (15): holds the unit state `dataBits00` names on the unit it aims
  /// at for its duration (`Spell4Effects.effectType.15`).
  UnitState
  /// An NpcExecutionDelay effect (35): holds the creature that casts it still for its
  /// duration after the go its phases name (`Spell4Effects.effectType.35`).
  NpcExecutionDelay
  /// A QuestAdvanceObjective effect (42): adds `dataBits02` to the progress of the objective
  /// at index `dataBits01` of the quest `dataBits00` names (`Spell4Effects.effectType.42`).
  QuestAdvance
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
    98 -> SummonPet
    97 -> Despawn
    15 -> UnitState
    35 -> NpcExecutionDelay
    42 -> QuestAdvance
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
    | NpcExecutionDelay
    | QuestAdvance -> True
    Immunity | SummonPet | Unread(..) -> False
  }
}

/// Whether a row of the effect type with these `targetFlags` is read: every row of a
/// type `is_read` for, except that a PropertyConversion, CooldownModifier,
/// Stealth, RemoveStealth, DisguiseOutfit or FullScreenEffect row is read only when its flags
/// include the caster (bit 1, `Spell4Effects.targetFlags`), a Proc row only when they are the
/// caster, the primary target or the area alone (1, 2 or 4: the units a Proc row is held by,
/// `spell_plan.ProcHolder`), a PropertyModifier or
/// ForcedMove row when they include the caster or are 2, 4 or 6 (the units a strike
/// hits), a Heal,
/// InterruptArmor, Absorption or QuestAdvance row when they include the caster or are the
/// primary target alone (2), and a ShieldOverload row only when they are the area alone (4); a
/// row aimed at other units is left out. A plan of
/// a spell with a Stealth or RemoveStealth row aimed other than at the caster alone
/// fails to load (genesis_prime/shared/spell_plan `StealthAimNotRead`).
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
    | DisguiseOutfit
    | FullScreenEffect -> int.bitwise_and(target_flags, 1) == 1
    Proc -> target_flags == 1 || target_flags == 2 || target_flags == 4
    Heal(..) | InterruptArmor | Absorption | QuestAdvance ->
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
    Immunity | SummonPet | Unread(..) -> False
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
