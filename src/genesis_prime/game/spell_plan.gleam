//// What the client's tables say a pressed ability does: for each ability a class
//// holds at level 1, and each class's innate active and passive spell, the tree of
//// casts it starts, built once when the tables load. The cast rule (genesis_prime/game/cast) reads the tree and decides
//// nothing from the tables itself.
////
//// ```
//// SpellLevel (class, level 1, no prerequisite) ─▶ Spell4 (the ability) ─▶ Spell4Base
//// Class (the first innate slot, genesis_prime/game/innate) ─▶ Spell4 (the innate's active and passive) ─▶ Spell4Base
////      Spell4Effects (spellId = the Spell4 id), each effect of type Proxy (26) ─▶ the Spell4 it names, as a child
////      Spell4Thresholds (parent = the Spell4 id), by order index ─▶ the Spell4 each tap or charge level casts, as a stage
////      SpellPhase (owner = a Multiphase Spell4) ─▶ the phase delays and flags, in row order
////      SpellCoolDown (the global row) ─▶ the global cooldown's time
////      Class (vitalEnumResource0..) ─▶ the result a short vital gives
//// all of them, once, when the tables load ─▶ Plans ─▶ in_plans(base)
//// ```
////
//// - **One decision for each effect row.** `read_row` says what the plan makes of a
////   Spell4Effects row in the place its spell is planned (`RowPlace`): in a list of its
////   spell and applied by a go (`Applied`), in a list and applied by none (`Held`: a
////   periodic gain or heal, a row behind a target apply prerequisite, which the cast rule
////   does not check, `cast.condition_gate`), in no list (`LeftOut`), a damage row the area
////   load reads (`ReadByArea`), or an error that fails the load. The lists of a spell are
////   made from these readings, and the coverage measure counts a row read exactly when it
////   is `Applied` (genesis_prime/coverage/effect_row), so the two cannot disagree. A spell
////   a Proxy starts on each struck unit refuses a heal, an Interrupt Armor row and an
////   absorb aimed at its primary target, and a spell that spends every point held refuses
////   an effect with a tag the rule does not read.
//// - **The tree.** A Proxy effect (`Spell4Effects.effectType.26`, dataBits00 the
////   Spell4 id; a row with dataBits00 0 names its spell in dataBits01 and ticks, which
////   the plan does not start: `Spell4Effects.effectType.26.periodic`) starts that spell
////   as a cast of its own, so a `Spell` holds its `Proxy` children, each with the delay
////   the effect gives after its
////   parent's go (`delayTime`) and the phases it fires in (`phaseFlags`: bit n is
////   phase n, every bit for -1, the reading `Spell4.38791` gives). A Proxy with a
////   target apply prerequisite is kept as `GatedOnCasterAndTarget`, with its caster
////   gates and the target gate decoded: the cast rule starts its child on a struck unit
////   when the caster gates pass against the caster and the target gate passes against
////   that unit (`Spell4Effects.prerequisiteIdTargetApply`: the struck unit first, the
////   caster second; Impale's four Proxies, 83818, 83819, 85673 and 85682, pick 39426 or
////   39427 by 38585 or 38587 and 5734 or 5735). A Proxy with a caster apply
////   prerequisite, or with a prerequisite in its dataBits06, is kept as
////   `GatedOnCaster` and started at its phase's go when each passes against the
////   caster (`Spell4.38791`: 79220 and 79229 apply only behind prerequisite 37037;
////   `Spell4Effects.effectType.26.dataBits06`, a reading of the rows that no client
////   code confirms, since the client applies no Proxy itself; the units of a check
////   are `Spell4Effects.prerequisiteIdTargetApply`). Five level-1 Proxies are gated
////   by their dataBits06 so: 177873 (53865 to 60947, 24582), 135961 (Mind Burst
////   32809 to 57030, 23344), 200542 (30900 to 41869, 35913), 212835 (80382 to
////   42569, 33154) and 212838 (80382 to 80383, 32921).
//// - **The gains.** A VitalModifier (`Spell4Effects.effectType.1`) of a tree gives
////   the caster dataBits02 points of the resource slot of its vital (6 is slot 1, 8
////   slot 3), behind its caster apply prerequisite, which the cast rule checks
////   (genesis_prime/game/prerequisite). A child started at each struck unit gives
////   its first phase's gains once per go of its parent, not once per unit (the
////   design of issue 418), so the plan moves them onto the `Proxy`. A gain with a
////   tickTime is a `TickingGain`, which the cast rule does not apply. The effect's
////   delayTime is not waited for (the server's choice: 10 ms in each kit row, under
////   a client frame).
//// - **The lasting effects.** A Fluff effect (`Spell4Effects.effectType.17`), a Scale
////   effect (18) and a RavelSignal effect (81) of a tree are each a `Lasting` row: the unit
////   its targetFlags aim at, its delay, durationTime and flags bit 2, which give its spell a life there (genesis_prime/game/lasting). A
////   SpellForceRemove effect (`Spell4Effects.effectType.80`) is a `ForceRemove` row:
////   dataBits00 picks a spell group (1), a Spell4 (2) or a Spell4Base (3) by
////   dataBits01, which must name a row, and the count of stacks is read only where
////   dataBits03 and dataBits04 agree. Each is applied when its caster apply
////   prerequisite passes against the caster, and one behind a target apply
////   prerequisite is not applied. Unlike a Proxy's, their dataBits06 is no
////   prerequisite. A `Spell` also holds its spell groups (`Spell4.spell4GroupListId`)
////   and its stack group with the group's cap (`Spell4.spell4StackGroupId`,
////   `Spell4StackGroup.stackCap`), and whether its lifetimes take the larger of delay
////   and duration (`Spell4.propertyFlags` 0x2000).
//// - **The crowd-control effects.** A CCStateSet effect (`Spell4Effects.effectType.4`)
////   of a tree is a `CrowdControl` row: the unit its targetFlags aim at (the primary
////   target, the area or both: a state on a caster is a player's, which no creature
////   casts), and its Stun (0) or Knockdown (8) state, delay, durationTime and the
////   Interrupt Armor it removes (genesis_prime/game/crowd_control). The strike
////   tells the units it selects the row's state, even when its phase has no damage
////   (genesis_prime/game/spell_area `phase`); the cast rule lists the states that
////   landed in the go and keeps a node for their life (genesis_prime/game/cast).
////   Each state's `Spell4Effects.emmComparison` tag chooses it by the points spent,
////   as a gain's does.
//// - **The property modifiers.** A UnitPropertyModifier effect
////   (`Spell4Effects.effectType.11`) whose targetFlags include the caster is a
////   `PropertyModifier` row: the property, mode, multiplier, flat amount and amount for
////   each level (genesis_prime/game/unit_properties), and its delay, durationTime and
////   flags bit 2, which start and end the change and give the caster's node of the cast
////   its life. A row aimed only at other units is not read. Its caster apply
////   prerequisite, phases and spend tag are a Fluff effect's. A UnitPropertyConversion
////   effect (`Spell4Effects.effectType.145`) whose targetFlags include the caster is a
////   `PropertyModifier` row too, whose change is a `Conversion` of property dataBits00
////   into dataBits01 at the 32-bit float dataBits02; both properties must have a
////   UnitProperty2 row. A DisguiseOutfit effect (`Spell4Effects.effectType.112`) whose
////   targetFlags include the caster is a `PropertyModifier` row too, whose change is a
////   `LookChange`: the displays it shows (genesis_prime/game/look), each in the slot of
////   its item type, from dataBits02 or dataBits01. It starts, ends and gives the node its
////   life as a property change does. A row with an outfit (dataBits00 or dataBits08), no
////   display, or a display whose item type has no slot fails the load
////   (`DisguiseNotRead`); dataBits03 is read as nothing, since no client code reads a
////   type 112 row.
//// - **The Interrupt Armor rows.** A ModifyInterruptArmor effect
////   (`Spell4Effects.effectType.52`) whose targetFlags include the caster (bit 1), or are
////   the primary target alone (2) in a spell cast on the caster, is a `PropertyModifier`
////   row whose `armor` is set: a change of UnitProperty2 44, the maximum, of x * 1.0 +
////   dataBits00, which the player's armor follows (genesis_prime/game/player_life
////   `armor_followed`); dataBits01 1 takes the points back at the end and 0 keeps them,
////   which matters only once armor is worn, and nothing wears a player's armor down yet.
////   Its delay, durationTime, flags bit 2, caster apply prerequisite, phases and spend
////   tag are a type 11 row's. A dataBits01 other than 0 and 1 fails the load. A row aimed
////   only at other units is not read. A child a Proxy starts on each struck unit that
////   holds a row aimed at its primary target fails the load: Interrupt Armor on a struck
////   unit is not built. 36 of the 38 type 52 rows are read.
//// - **The absorbs.** An Absorption effect (`Spell4Effects.effectType.29`) whose targetFlags
////   include the caster (bit 1), or are the primary target alone (2) in a spell cast on the
////   caster, is a `PropertyModifier` row whose change is an `AbsorbChange`: the formula of
////   the pool's amount (dataBits00 and dataBits01 as floats and the four parameters, whose
////   kinds must be those the caster's value reads, genesis_prime/game/damage
////   `absorption_formula_of`), the damage types it takes (dataBits04 as a mask) and its
////   aim. It starts, ends and gives the node its life as a type 11 row does. A row with a
////   tickTime, with neither a durationTime nor flags bit 2, with a non-finite number or a
////   parameter kind not read fails the load, as does one aimed at the primary target in a
////   child a Proxy starts on each struck unit (`AbsorptionPeriodic`,
////   `AbsorptionHasNoLifetime`, `AbsorptionNumberNotFinite`, `AbsorptionParameterNotRead`,
////   `AbsorptionOnStruckUnit`); a row aimed only at other units is not read.
//// - **The shield heals.** A HealShields effect (`Spell4Effects.effectType.118`) whose
////   targetFlags include the caster (bit 1), or are the primary target alone (2) in a spell
////   cast on the caster, is a `ShieldHeal` row: its formula (dataBits00 as a float,
////   dataBits01 and the four parameters, which must be kinds the caster's value reads,
////   genesis_prime/game/damage `caster_unread`), its delay, aim and caster apply
////   prerequisite, which the cast rule checks and which a target apply prerequisite
////   leaves not applied; a row with a tickTime is a `TickingShieldHeal`, held and not
////   applied, since each tick needs a 0x7f8. A row aimed only at other units (4 and 6) is
////   not read. A child a Proxy starts on each struck unit that holds a heal aimed at its
////   primary target fails the load: a shield heal on a struck unit is not built.
//// - **The shield overloads.** A ShieldOverload effect (`Spell4Effects.effectType.64`)
////   aimed at the area (targetFlags 4) is a `Lasting` row, listed on each struck unit for
////   its durationTime as a Fluff effect is: the client marks the unit overloaded and
////   clears the mark itself. A row aimed at the caster or the primary target is not read:
////   the server's hold of a player's shield at 0 is not built.
//// - **The procs.** A Proc effect (`Spell4Effects.effectType.14`) whose targetFlags are the
////   caster's and whose trigger kind (dataBits00) is one of the holder's own events is a
////   `ProcRow`: 217 entering stealth, 218 leaving it, 44 leaving combat and 0 dying
////   (`Spell4Effects.effectType.14.dataBits00.217_218`, `.0_44`), the spell it casts
////   (dataBits01), planned as a Proxy's child is and on the same chain, so a proc that leads
////   back to a spell on the way fails as a cycle, and its limit, dataBits05 fires in
////   dataBits04 ms (`Spell4Effects.effectType.14.limits`). Its chance is 1.0 and draws no
////   roll. Its delay, durationTime and flags bit 2 give the holder's node its life
////   (`Spell4Effects.effectType.14.lifetime`), and its caster apply prerequisite is a Fluff
////   effect's. A Proc row of another kind is in no list and the load goes on
////   (`proc_read`); a row of these kinds with a chance other than 1.0, a unit bit of the
////   event's other unit, a window or count at or below 0, a gate or filter column, a target
////   apply or persistence prerequisite or a delayTime fails the load naming the column
////   (`ProcNotRead`). The spells the procs cast are in the tree (`tree`).
//// - **The forced moves.** A ForcedMove effect (`Spell4Effects.effectType.3`) whose
////   targetFlags include the caster is a `ForcedMove` row: its delay. The go lists it
////   on the caster and the caster's client moves itself and reports the move
////   (`Spell4Effects.effectType.3.player`); the server works out no destination. A row aimed only at other units is not read. Its caster apply
////   prerequisite, phases and spend tag are a Fluff effect's.
//// - **The cooldown effects.** A ModifySpellCooldown effect
////   (`Spell4Effects.effectType.73`) whose targetFlags include the caster is a
////   `CooldownModifier` row: the selector (dataBits00 and the id of dataBits01, kept as
////   given and looked up in no table) and the operation with its 32-bit float
////   (genesis_prime/game/cooldown), and its delay, durationTime and flags bit 2, which
////   time the change and give the caster's node of the cast its life. A row aimed only
////   at other units is not read. A spell also holds its cooldown groups, the non-zero
////   spellCoolDownId00 to 02, each of which must be a SpellCoolDown row. Its caster
////   apply prerequisite, phases and spend tag are a Fluff effect's.
//// - **The phases** of a Multiphase spell (`Spell.CodeEnumCastMethod` 8) are the
////   SpellPhase rows of its owner kept by the client's rule (`0x14055e180`: order
////   index below 32, and index 0 or a non-zero delay), each delay the gap after
////   the phase before: the client sums the delays into the cast's duration when
////   its castTime is 0 (`0x14053d1f0`), which a gap reading fits, and schedules no
////   phase itself, so the go times are the server's choice
////   (`SpellPhase.phaseDelay`). A phase with the flag 0x200 moves the spell's
////   cooldown to its last phase (`0x14053e5a0`). Any other spell has one go, at
////   the end of its cast time, and a ChargeRelease ability that has stages has
////   none (below).
//// - **A channel** (`Spell.CodeEnumCastMethod` 1) gets (channelMaxTime -
////   channelInitialDelay + channelPulseTime) / channelPulseTime gos, in whole
////   numbers (`0x14053d1f0`); the pulses fall at the initial delay plus each pulse
////   time and the cast ends at channelMaxTime, which are the server's choice
////   (`Spell4.channelPulseTime`).
//// - **The stages** of a RapidTap or ChargeRelease ability are the Spell4Thresholds
////   rows whose parent it is, by order index, each a full tree with its
////   thresholdDuration (`Spell4Thresholds.spell4IdToCast`). A press resolves to the
////   row at the open threshold's index, the ability's own spell at -1, and is
////   refused past the last row (`0x1403bfd60`). The threshold lasts the ability's
////   thresholdTime (`opcode.0x816`).
//// - **The cast bar** is decided by the cast method, as the client does
////   (`cast.current_cast`): a spell that shows one is the caster's current cast from
////   its start.
//// - **The cooldowns.** The spell's own is `Spell4.spellCoolDown` in
////   milliseconds, started where the method says (`CooldownStart`,
////   `0x14053e5a0`). The global one is the row `spellCoolDownIdGlobal` names, in
////   effect only for kinds 0 and 1 and a non-zero row (`0x14046afc0`); kinds 0
////   and 2 are refused while it runs (`0x1403b14c0`).
//// - **The costs.** A spell's two innate costs, and a stage's row's two more, each
////   read once into a `Cost` the cast rule checks against the caster's resources
////   (`0x1403b3320`, `0x1405e7980`, `Spell4CastResult.vital_cost`): types 5 to 11
////   are resource slots 0 to 6 (result 50 + the slot; Mind Burst, type 6, is 51);
////   type 18 goes to the class's slots that hold that vital, the last one's result
////   given when none passes (Gamma Rays is 55). Health (1), shield (3), focus (15)
////   and 16 (slot 7) give their own results (44, 176, 167, 177) and are held by no
////   rule of the server; any other type, the client's slots 8 to 10 (types 27 to 29)
////   among them, is an `UnreadCost`.
//// - **The spend.** A cost's Spell4 EMM id (`Spell4.innateCostEMMId0`, genesis_prime/game/spend)
////   of 4 or 7 on a slot cost makes it a `SpendAllCost`, which takes every point the
////   slot holds; any other id, one on a cost that is not a slot cost and one on no
////   cost are an `UnreadSpendCost`. Each gain, Proxy and (in genesis_prime/game/spell_area)
////   damage effect keeps its row's tag (`Spell4Effects.emmComparison`), and the cast
////   rule chooses by it with the points spent.
//// - **The caster requirements.** A spell's two caster vital requirements
////   (`0x1403b1780`): types 5 to 11 read the same slots with the same results,
////   compared with the value by the eval code (`0x1407a1750`: 0 to 4
////   on the amount, 5 to 9 the same on the percentage of the slot's maximum, any
////   other never passes); type 0 is none; any other type is an
////   `UnreadRequirement`. A failed requirement is waived when the spell's
////   `RequirementWaiver` passes (below).
//// - **No target.** None of the 18 level-1 abilities nor the six innate actives needs a
////   target the client picks (`Spell4TargetMechanics.targetType`), so the plan holds
////   no range and no target rule.
//// - **A spell's own cast conditions** are its four Prerequisite columns, each loaded with
////   the rows it nests (genesis_prime/game/prerequisite `load`), and kept on every spell
////   of a tree, the stages and children too. The press checks the pressed or staged
////   spell's CasterCast (`CastGate`, failure 151) then its TargetCast (281), after every
////   other check (`0x1403ace00`); a spell whose propertyFlags has bit 2 and whose
////   casterInnateRequirement0, casterInnateRequirement1 or targetBeginInnateRequirement
////   is not 0 holds its CasterCast as a `RequirementWaiver`, which only waives a failed
////   requirement (`0x1403b1780`; Rampage 58524's 19750). The cast rule checks the other
////   two columns, CasterPersistence (282) and TargetPersistence (283), at the end of each
////   input while the cast lasts (genesis_prime/game/cast `persisted`), since the client
////   never evaluates them (`Spell4.prerequisiteIdCasterPersistence`). Four innate actives
////   hold a gate (Warrior 46867, Esper 58586, Stalker 46073, Spellslinger 47273) and
////   Spell Surge's buff 47439 a persistence.
//// - **The innates.** A slot-0 innate's active spell is held as an ability in the
////   bag at the index after the level-1 abilities (genesis_prime/game/loadout), so its
////   plan is the ability's. Its passive is never pressed: the server starts it itself
////   (genesis_prime/game/cast `passive_started`).
//// - **The caster's death.** Bit 0 of the spell's caster condition row says
////   whether its caster must be alive, must be dead or may be either
////   (`Spell4.spell4ConditionsIdCaster`, `CasterDeath`); the row's other
////   conditions are not read.
//// - **What fails the load:** a Spell4, Spell4Base, Spell4Conditions, SpellCoolDown,
////   Class or Prerequisite row the tree names that the tables lack (a Prerequisite
////   column of a Spell4 row included), a Prerequisite row that nests itself through the
////   rows it nests, a cost of a type
////   not read, a cycle of Proxy effects, a channel with no pulse time, a gain
////   aimed other than at the caster, of a vital other than 6 or 8, or behind a
////   target apply prerequisite, and an effect of a spell that spends every point
////   held with an emmComparison other than 0 or 1; a Fluff or SpellForceRemove effect
////   aimed other than at the caster, the primary target or the area; a type 80
////   effect with a dataBits00 other than 1 to 3, naming no group, Spell4 or
////   Spell4Base, or whose dataBits03 and dataBits04 differ; a Spell4GroupList or
////   Spell4StackGroup row a spell names that the tables lack; and a CCStateSet effect
////   of a state other than Stun and Knockdown, aimed at the caster or by other flags,
////   or behind an apply prerequisite.

import genesis_prime/game/cooldown
import genesis_prime/game/crowd_control
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/innate
import genesis_prime/game/lasting
import genesis_prime/game/loadout
import genesis_prime/game/look
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties
import genesis_prime/game/worn_visual
import genesis_prime/message/crowd_control_state
import genesis_prime/message/float32
import genesis_prime/table/class
import genesis_prime/table/id.{
  type ItemSlotId, type PrerequisiteId, type Spell4BaseId, type Spell4EffectsId,
  type Spell4Id, type UnitProperty2Id, ClassId, ItemDisplayId, PrerequisiteId,
  Spell4BaseId, Spell4ConditionsId, Spell4EffectsId, Spell4Id,
  Spell4StackGroupId, SpellCoolDownId, UnitProperty2Id,
}
import genesis_prime/table/item2_type
import genesis_prime/table/item_display
import genesis_prime/table/item_slot
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/positional_requirement
import genesis_prime/table/prerequisite as prerequisite_table
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_group_list
import genesis_prime/table/spell4_stack_group
import genesis_prime/table/spell4_thresholds
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import genesis_prime/table/unit_property2
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// How a spell is cast (`Spell.CodeEnumCastMethod`, Spell4Base.castMethod).
pub type CastMethod {
  Normal
  Channeled
  PressHold
  ChanneledField
  ClientSideInteraction
  RapidTap
  ChargeRelease
  Multiphase
  Transactional
  OtherMethod(id: Int)
}

/// Whether the client shows a cast bar for a spell (`SpellShowsCastBar`,
/// `cast.current_cast`), which the spell's cast method decides.
pub type CastBar {
  /// The spell has a cast bar: a Normal spell with a cast time and a castBarType, a
  /// Multiphase one with either, a Channeled one with a castBarType, a ChargeRelease
  /// one with a thresholdTime or else a cast time, and any other method with a cast
  /// time.
  ShowsCastBar
  HidesCastBar
  /// A Channeled spell with no castBarType: it shows the bar only as the pressed
  /// spell itself (the cast's root is the spell).
  ShowsWhenPressed
}

/// Which go of a cast starts the spell's own cooldown (`0x14053e5a0`).
pub type CooldownStart {
  /// The first go: a Normal spell, and a Multiphase one with no phase of the flag
  /// 0x200.
  AtFirstGo
  /// The go that reaches the count: a Multiphase spell with a phase of the flag 0x200
  /// (its last phase) and a channel (its last pulse).
  AtLastGo
  /// No go: a RapidTap ability's cooldown starts when its threshold closes, and a
  /// ChargeRelease ability's at the first go of the stage the release casts.
  NotAtAGo
}

/// Whether the spell needs the weapon (Spell4Base.weaponSlot, `0x1403afb10`).
pub type WeaponSlot {
  /// 0: no weapon is needed.
  NoWeaponNeeded
  /// 1: an item in the equipped slot 16 is needed, or the press is refused 169.
  PrimaryWeapon
  /// 2: the press is always refused 169.
  Refused
  OtherWeaponSlot(id: Int)
}

/// What a spell does to the global cooldown (Spell4.globalCooldownEnum with the
/// SpellCoolDown row of `spellCoolDownIdGlobal`).
pub type GlobalCooldown {
  GlobalCooldown(
    /// A press is refused 14 while the global cooldown runs: kinds 0 and 2
    /// (`0x1403b14c0`).
    refused_while_running: Bool,
    /// The time the global cooldown runs for from the accept, in milliseconds:
    /// kinds 0 and 1 with a non-zero row (`0x14046afc0`); none for the others.
    starts_for_ms: Option(Int),
  )
}

/// Whether a Proxy is started.
pub type Condition {
  Always
  /// The Proxy starts at its phase's go when every one of these prerequisites
  /// passes against the caster: its caster apply prerequisite, then the one its
  /// dataBits06 names (`Spell4Effects.effectType.26.dataBits06`).
  GatedOnCaster(gates: List(Prerequisite))
  /// The effect applies only behind this target apply prerequisite, which is not
  /// checked: the effect is not applied. Only an effect that is not a Proxy has it.
  GatedOnTarget(prerequisite_id: PrerequisiteId)
  /// Only a Proxy has it. The Proxy starts its child on a unit when every one of these caster gates passes
  /// against the caster and the target gate passes against that unit, the struck unit for
  /// a Proxy aimed at the area and the caster for one aimed at the caster
  /// (`Spell4Effects.prerequisiteIdTargetApply`). The caster gates are its caster apply
  /// prerequisite, then the one its dataBits06 names.
  GatedOnCasterAndTarget(caster: List(Prerequisite), target: Prerequisite)
}

/// A resource gain of a spell: a VitalModifier aimed at the caster
/// (`Spell4Effects.effectType.1`), `amount` points of resource slot `slot`, in the
/// phases of `phase_flags`, given when its caster apply prerequisite passes or it
/// has none, and when its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend).
pub type Gain {
  Gain(
    effect_id: Spell4EffectsId,
    slot: Int,
    amount: Int,
    phase_flags: Int,
    prerequisite: Option(Prerequisite),
    tag: spend.Tag,
  )
  /// A gain each `tick_ms` for `duration_ms` (Spell4Effects.tickTime and
  /// durationTime), which the cast rule does not apply.
  TickingGain(
    effect_id: Spell4EffectsId,
    slot: Int,
    amount: Int,
    phase_flags: Int,
    prerequisite: Option(Prerequisite),
    tag: spend.Tag,
    tick_ms: Int,
    duration_ms: Int,
  )
}

/// Who an effect aims at (`Spell4Effects.targetFlags`), read once for the effects a
/// spell holds: the Proxies of the plan and the damage of the areas.
pub type Aim {
  AimsAtCaster
  AimsAtPrimaryTarget
  AimsAtArea
  AimsAtBoth
  /// A flag value no effect of a level-1 ability's tree holds: the load refuses an
  /// effect with it.
  OtherAim(flags: Int)
}

/// The aim of an effect's `targetFlags`: 1 the caster, 2 the primary target, 4 the area,
/// 6 the primary target and the area.
pub fn aim_of(target_flags target_flags: Int) -> Aim {
  case target_flags {
    1 -> AimsAtCaster
    2 -> AimsAtPrimaryTarget
    4 -> AimsAtArea
    6 -> AimsAtBoth
    flags -> OtherAim(flags:)
  }
}

/// Which unit a Proxy's child cast is made on.
pub type ProxyTarget {
  /// The caster of the spell whose Proxy fired.
  OnCaster
  /// Each unit the go struck: a Proxy whose effect aims at the area
  /// (`Spell4Effects.targetFlags` 4), which starts one child for each Hit unit
  /// (genesis_prime/game/cast `went`).
  OnEachStruck
}

/// The times of a Channeled spell, in milliseconds (Spell4.channelInitialDelay,
/// channelMaxTime and channelPulseTime).
pub type Channel {
  Channel(initial_delay_ms: Int, max_time_ms: Int, pulse_time_ms: Int)
}

/// What the spell's caster condition row says of a dead caster: bit 0 of its
/// Spell4Conditions mask, with the same bit of its value
/// (`Spell4.spell4ConditionsIdCaster`). The row's other bits are not read: the
/// rule checks no other condition of the caster.
pub type CasterDeath {
  /// The mask's bit 0 with the value's bit 0 clear: a dead caster is refused 57
  /// Caster_CannotBeDead.
  CannotBeDead
  /// The mask's bit 0 with the value's bit 0 set: a living caster is refused 58
  /// Caster_MustBeDead.
  MustBeDead
  /// No row (id 0), or a row without the mask's bit 0: never refused for death.
  AliveOrDead
}

/// The life of a caster that a spell's caster condition refuses.
pub type RefusedLife {
  /// A dead caster (`CannotBeDead`).
  RefusesDead
  /// A living caster (`MustBeDead`).
  RefusesLiving
}

/// The life of the caster, dead or alive, that the spell's caster condition refuses, when
/// it refuses it: the press (`cast.verdict`) and a proc's cast (`cast.proc_cast`) both ask
/// this (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`).
pub fn refused_life(
  spell spell: Spell,
  dead dead: Bool,
) -> Option(RefusedLife) {
  case spell.caster_death, dead {
    CannotBeDead, True -> Some(RefusesDead)
    MustBeDead, False -> Some(RefusesLiving)
    CannotBeDead, False | MustBeDead, True | AliveOrDead, _ -> None
  }
}

/// One stage of a RapidTap or ChargeRelease ability: the spell a tap or a charge
/// level casts, and the time the threshold takes to reach it from the stage before
/// (Spell4Thresholds.thresholdDuration).
pub type Stage {
  Stage(duration_ms: Int, spell: Spell)
}

/// A spell and what it starts. `spell4_id` is the id of the Spell4 row; the cast
/// ids a press makes are the cast rule's (genesis_prime/game/cast).
pub type Spell {
  Spell(
    spell4_id: Spell4Id,
    spell4_base_id: Spell4BaseId,
    method: CastMethod,
    /// Spell4.castTime; 0 goes at once.
    cast_time_ms: Int,
    /// Spell4.spellCoolDown: the spell's own cooldown, started where
    /// `cooldown_start` says.
    cooldown_ms: Int,
    cooldown_start: CooldownStart,
    /// The index of the first phase with the flag 0x200 of a Multiphase spell: a
    /// cast that has gone past it starts the cooldown at its 0x7fe even when it
    /// ends before its last phase (`0x14053e1b0`).
    cooldown_phase: Option(Int),
    /// Whether the client shows a cast bar for the spell, and so makes it the
    /// unit's current cast (`cast.current_cast`).
    cast_bar: CastBar,
    /// Whether a live cast of this spell leaves the caster free to press another:
    /// Spell4.propertyFlags 0x40 (`Spell4.propertyFlags`).
    free_while_live: Bool,
    /// Whether a press of this spell is never refused 13 for a live cast:
    /// Spell4.propertyFlags 0x10 or 0x1 (`Spell4.propertyFlags`).
    ignores_casting: Bool,
    /// Whether an effect's lifetime is the larger of its delay and durationTime
    /// rather than their sum: Spell4.propertyFlags 0x2000, the spell record's flag
    /// 0x10000000 (`opcode.0x7f4.effect_time`, `0x140568540`).
    longer_of_delay_and_duration: Bool,
    weapon: WeaponSlot,
    /// Whether the caster must be alive or dead to cast it.
    caster_death: CasterDeath,
    global_cooldown: GlobalCooldown,
    /// The innate costs a press pays, in the client's order: the Spell4 row's two,
    /// then a stage's Spell4Thresholds row's two (`0x1403b3320`).
    costs: List(Cost),
    /// The caster vital requirements a press is checked against
    /// (`0x1403b1780`).
    requirements: List(Requirement),
    /// What the spell's prerequisiteIdCasterCast is to a press (`0x1403ace00`,
    /// `0x1403b1780`).
    caster_cast: CasterCast,
    /// The spell's prerequisiteIdTargetCast, which the press checks after
    /// `caster_cast`: failure 281 (`0x1403ace00`).
    target_cast: Option(Prerequisite),
    /// The spell's prerequisiteIdCasterPersistence, which the server checks while the
    /// cast lasts: failure 282 (the client never evaluates it,
    /// `Spell4.prerequisiteIdCasterPersistence`).
    caster_persistence: Option(Prerequisite),
    /// The spell's prerequisiteIdTargetPersistence: failure 283.
    target_persistence: Option(Prerequisite),
    /// The gap before each phase's go, in order; empty for a spell that is not
    /// Multiphase.
    phase_delays_ms: List(Int),
    /// How long the threshold a RapidTap or ChargeRelease ability opens stays open:
    /// Spell4.thresholdTime; 0 for a spell that opens none.
    threshold_ms: Int,
    /// The spells a tap or charge level casts, in order.
    stages: List(Stage),
    /// The pulse times of a Channeled spell.
    channel: Option(Channel),
    proxies: List(Proxy),
    /// The spell's own resource gains, given at its gos; none of a child started
    /// at each struck unit, whose gains its Proxy holds.
    gains: List(Gain),
    /// The spell groups the spell belongs to (Spell4GroupList's spellGroupId values
    /// of `Spell4.spell4GroupListId`), which a type 80 row selects by.
    groups: List(Int),
    /// The spell's stack group and its cap (`Spell4.spell4StackGroupId`,
    /// `Spell4StackGroup.stackCap`).
    stack: lasting.Stack,
    /// The Fluff, Scale, RavelSignal and area ShieldOverload effects that give the spell a
    /// life on a unit.
    lasting: List(Lasting),
    /// The SpellForceRemove effects that take casts off a unit.
    removes: List(ForceRemove),
    /// The CCStateSet effects that hold a stun or a knockdown on a unit.
    controls: List(CrowdControl),
    /// The UnitPropertyModifier and UnitPropertyConversion effects aimed at the caster,
    /// which change its properties for their time.
    modifiers: List(PropertyModifier),
    /// The ForcedMove effects aimed at the caster, which the go lists and the caster's
    /// client carries out.
    forced_moves: List(ForcedMove),
    /// The non-zero cooldown groups of the Spell4 row (`spellCoolDownId00` to `02`),
    /// each a SpellCoolDown row, which a selector 3 of a cooldown effect tests.
    cooldown_groups: List(Int),
    /// The ModifySpellCooldown effects aimed at the caster, which change the
    /// caster's spell cooldowns.
    cooldown_modifiers: List(CooldownModifier),
    /// The Stealth effects aimed at the caster, each a stealth the cast holds on it.
    stealth: List(StealthRow),
    /// The RemoveStealth effects aimed at the caster, which end every stealth it holds.
    remove_stealth: List(RemoveStealthRow),
    /// The HealShields effects that reach the caster, which refill its shield.
    shield_heals: List(ShieldHeal),
    /// What the spell does to the caster's stealth, and at which go (`StealthChange`).
    stealth_change: StealthChange,
    /// The Proc effects aimed at the caster, whose kind is one of the holder's own
    /// events, each with the spell it casts (`ProcRow`).
    procs: List(ProcRow),
  )
}

/// What a spell's prerequisiteIdCasterCast is to a press (`0x1403ace00`,
/// `0x1403b1780`).
pub type CasterCast {
  NoCasterCast
  /// Checked at the press after every other check: 151 when it fails.
  CastGate(prerequisite: Prerequisite)
  /// propertyFlags bit 2 with a caster requirement block: it only waives a failed
  /// requirement.
  RequirementWaiver(prerequisite: Prerequisite)
}

/// Whether taking damage ends a stealth: a Stealth effect's dataBits02, 0 for
/// `BrokenByDamage` and 1 for `KeptOnDamage` (`Spell4Effects.effectType.83`).
pub type Breaks {
  BrokenByDamage
  KeptOnDamage
}

/// What a spell does to its caster's stealth, from `Spell4.spellCastStealthChange`: the
/// column is read nowhere by the client, so ending stealth on a cast is the server's rule
/// (`Spell4.spellCastStealthChange`, `Spell4.spellCastStealthChange.break`).
/// - 0 ends the stealth of other casts after the effects of a go, at each go.
/// - 1 ends it after the effects of the cast's last go, so effects of an earlier go
///   gated on the caster being stealthed (Impale's Proxies, phase 1) still see it.
/// - 2 leaves it.
/// The stealth a cast's own Stealth rows give is never ended by the cast.
pub type StealthChange {
  EndsStealthAtEachGo
  EndsStealthAfterLastGo
  KeepsStealth
}

/// A Stealth effect (`Spell4Effects.effectType.83`) of a spell, aimed at the caster:
/// whether damage ends the stealth it gives (`breaks`), its `row` (which holds the
/// caster's node of the cast until it is removed: durationTime 0 holds a stealth until it
/// is removed, and a Stealth effect with a delayTime or durationTime is not built), the
/// phases of `phase_flags` it applies in,
/// when its `condition` holds (its caster apply prerequisite against the caster), and
/// when its `tag` holds for the points the cast spent (genesis_prime/game/spend).
pub type StealthRow {
  StealthRow(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    breaks: Breaks,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A RemoveStealth effect (`Spell4Effects.effectType.84`) of a spell, aimed at the
/// caster: it ends every stealth the caster holds, in the phases of `phase_flags`, when
/// its `condition` holds and its `tag` holds for the points the cast spent.
pub type RemoveStealthRow {
  RemoveStealthRow(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// The event of its holder that fires a Proc effect (`Spell4Effects.effectType.14`,
/// dataBits00; the readings are `Spell4Effects.effectType.14.dataBits00.217_218` and
/// `Spell4Effects.effectType.14.dataBits00.0_44`, none of them in the client's code).
pub type Trigger {
  /// 217: the holder enters stealth.
  EnteredStealth
  /// 218: the holder leaves stealth.
  LeftStealth
  /// 44: the holder leaves combat.
  LeftCombat
  /// 0: the holder dies.
  Died
}

/// A Proc effect (`Spell4Effects.effectType.14`) of a spell, aimed at the caster: when
/// the holder's `trigger` happens, the holder casts `spell` at itself. At most `count`
/// fires in any `window_ms` (dataBits05 in dataBits04 milliseconds,
/// `Spell4Effects.effectType.14.limits`); the chance is 1.0 and draws no roll. Its `row`
/// gives the caster's node of the holding cast its life (a Proc with no durationTime and
/// flags bit 2 lasts until removed, `Spell4Effects.effectType.14.lifetime`), in the
/// phases of `phase_flags`, when its `condition` holds (its caster apply prerequisite
/// against the caster) and its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend). The proc's `spell` is planned as a Proxy's child is.
pub type ProcRow {
  ProcRow(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    trigger: Trigger,
    spell: Spell,
    window_ms: Int,
    count: Int,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// What a Proc row's columns say without a table: its trigger and its limit.
pub type ProcReading {
  ProcReading(trigger: Trigger, window_ms: Int, count: Int)
}

/// A ModifySpellCooldown effect (`Spell4Effects.effectType.73`) of a spell whose
/// targetFlags include the caster: the change it makes to the running and later
/// cooldowns (`modifier`), its delay, durationTime and flags bit 2 (`row`, which also
/// give the caster's node of the cast its life, as a Fluff effect's do), the phases of
/// `phase_flags` it applies in, when its `condition` holds (its caster apply
/// prerequisite against the caster; one behind a target apply prerequisite is not
/// applied), and when its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend). A row aimed only at other units is not read, and the
/// part of a row's aim that is not the caster is not applied (`effect_kind.is_row_read`).
pub type CooldownModifier {
  CooldownModifier(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    modifier: cooldown.Modifier,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A ForcedMove effect (`Spell4Effects.effectType.3`) of a spell whose targetFlags
/// include the caster: the `delay_ms` the go lists it with (the move itself, its kind
/// and distance, the caster's client works out and carries out
/// (`Spell4Effects.effectType.3.player`) and no rule of the server reads), the phases of `phase_flags` it applies in, when its `condition`
/// holds (its caster apply prerequisite against the caster; one behind a target apply
/// prerequisite is not applied), and when its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend). A row aimed only at other units is not read, and the part
/// of a row's aim that is not the caster is not applied (`effect_kind.is_row_read`).
pub type ForcedMove {
  ForcedMove(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    delay_ms: Int,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// What a timed row of a spell changes on its caster: a property of the unit
/// (`unit_properties`), the unit's look (`look`) or the pool of damage the unit absorbs.
pub type Change {
  /// A UnitPropertyModifier or UnitPropertyConversion row's change.
  PropertyChange(modifier: unit_properties.Modifier)
  /// A DisguiseOutfit row's change (`Spell4Effects.effectType.112`).
  LookChange(disguise: look.Disguise)
  /// An Absorption row's change (`Spell4Effects.effectType.29`).
  AbsorbChange(absorption: Absorption)
}

/// What an Absorption row (`Spell4Effects.effectType.29`) gives the unit it lands on: a pool
/// of the amount its `formula` gives the caster at the go, which takes the damage types
/// `mask` holds (dataBits04: bit 1 Physical, 2 Tech, 4 Magic), on the unit its targetFlags
/// aim at (`aim`: the caster, or the primary target, which a spell cast on the caster
/// makes the caster).
pub type Absorption {
  Absorption(formula: damage.Formula, mask: Int, aim: Aim)
}

/// A UnitPropertyModifier effect (`Spell4Effects.effectType.11`), a
/// UnitPropertyConversion effect (`Spell4Effects.effectType.145`), a DisguiseOutfit
/// effect (`Spell4Effects.effectType.112`) or an Absorption effect
/// (`Spell4Effects.effectType.29`) of a spell whose
/// targetFlags include the caster: the change it makes to the caster (`change`), its delay, durationTime and flags bit 2 (`row`, which also give the
/// caster's node of the cast its life, as a Fluff effect's do), the phases of
/// `phase_flags` it applies in, when its `condition` holds (its caster apply
/// prerequisite against the caster; one behind a target apply prerequisite is not
/// applied), and when its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend). A row aimed only at other units is not read, and the
/// part of a row's aim that is not the caster is not applied (`effect_kind.is_row_read`).
pub type PropertyModifier {
  PropertyModifier(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    change: Change,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
    armor: Option(InterruptArmor),
  )
}

/// What a ModifyInterruptArmor row (`Spell4Effects.effectType.52`) adds to the change of
/// property 44 it makes, which the player's armor follows. `points` is dataBits00,
/// `takes_back` is dataBits01 (1 takes the points back when the row ends, 0 keeps the
/// armor: it matters only once armor is worn, and nothing wears a player's armor down yet)
/// and `aim` is the unit the row's targetFlags name: the caster, or the primary target,
/// which a spell cast on the caster makes the caster.
pub type InterruptArmor {
  InterruptArmor(points: Int, takes_back: Bool, aim: Aim)
}

/// A CCStateSet effect (`Spell4Effects.effectType.4`) of a spell: the unit it aims
/// at (the primary target, the area or both), its `row` (state, delay, duration and
/// the armor it removes), the phases of `phase_flags` it fires in, and the `tag` that
/// chooses it by the points the cast spent (genesis_prime/game/spend). Its dataBits
/// beyond the state and the armor need no handling (`Spell4Effects.effectType.4`),
/// and it has no apply prerequisite.
pub type CrowdControl {
  CrowdControl(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    row: crowd_control.Row,
    tag: spend.Tag,
  )
}

/// A Fluff effect (`Spell4Effects.effectType.17`), Scale effect (18), RavelSignal effect
/// (81) or area ShieldOverload effect (64) of a spell: it names the unit it aims at in the go's target info and gives the
/// spell a life there, from its `row`, in the phases of `phase_flags`, when its
/// `condition` holds (its caster apply prerequisite against the caster; one behind a
/// target apply prerequisite is not applied), and when its `tag` holds for the points
/// the cast spent (genesis_prime/game/spend). Its dataBits need no handling: the client
/// resizes the unit of a Scale effect itself (`Spell4Effects.effectType.18`), and a
/// RavelSignal effect is only a life (`Spell4Effects.effectType.81`); the client marks a
/// ShieldOverload unit itself (`Spell4Effects.effectType.64`).
pub type Lasting {
  Lasting(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    row: lasting.LastingRow,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// A HealShields effect (`Spell4Effects.effectType.118`) of a spell whose targetFlags
/// reach the caster (`effect_kind.is_row_read`): the unit it heals (`aim`: the caster,
/// or the primary target of a spell cast on the caster), the phases of `phase_flags` it
/// applies in, when its `condition` holds (its caster apply prerequisite against the
/// caster; one behind a target apply prerequisite is not applied), and when its `tag`
/// holds for the points the cast spent (genesis_prime/game/spend). The part of a row's
/// aim that is not the caster is not applied (`effect_kind.is_row_read`).
pub type ShieldHeal {
  /// A heal that lands once, `delay_ms` after its go, by `formula` read for the caster
  /// (genesis_prime/game/damage `value_on_caster`).
  ShieldHeal(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    condition: Condition,
    tag: spend.Tag,
    formula: damage.Formula,
    delay_ms: Int,
  )
  /// A heal each `tick_ms` for `duration_ms` (Spell4Effects.tickTime and durationTime),
  /// which the cast rule does not apply: each tick needs its own 0x7f8
  /// (`Spell4Effects.effectType.118`).
  TickingShieldHeal(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    condition: Condition,
    tag: spend.Tag,
    tick_ms: Int,
    duration_ms: Int,
  )
}

/// A SpellForceRemove effect (`Spell4Effects.effectType.80`) of a spell: it takes
/// `count` stacks of the casts `selector` names off the unit it aims at, in the
/// phases of `phase_flags`, when its `condition` holds (as a Fluff effect's does), and
/// when its `tag` holds for the points the cast spent (genesis_prime/game/spend).
pub type ForceRemove {
  ForceRemove(
    effect_id: Spell4EffectsId,
    phase_flags: Int,
    aim: Aim,
    selector: lasting.Selector,
    count: Int,
    condition: Condition,
    tag: spend.Tag,
  )
}

/// One innate cost of a spell, as the client's check reads its type
/// (`0x1403b3320`).
pub type Cost {
  /// `amount` points of resource slot `slot`: refused with `result` when the slot,
  /// as a whole number, holds less (both as absolute values).
  SlotCost(slot: Int, amount: Int, result: Int)
  /// `amount` points of a vital the class mechanic finds among the class's slots,
  /// `slots` in order: it passes at the first slot whose value less `amount` lies
  /// between 0 and the slot's maximum, else is refused with `result`, the last such
  /// slot's; with no such slot it passes and pays nothing (`0x1405e7980`).
  ClassVitalCost(slots: List(Int), amount: Int, result: Int)
  /// A cost in a vital no rule of the server holds (health, shield or focus):
  /// refused with `result`, and logged once.
  UnheldCost(result: Int)
  /// A slot cost whose Spell4 EMM id the server reads as a spend of every point
  /// held (genesis_prime/game/spend `AllHeld`): refused with `result` when the slot
  /// holds fewer whole points than the base `amount`, else it takes every whole
  /// point held, and the points above `amount` are the cast's n.
  SpendAllCost(slot: Int, amount: Int, result: Int)
  /// A cost with an EMM id no rule reads, on a cost that is not a slot cost, or on no
  /// cost at all: refused with `result` (the cost's own, 285 for no cost), and logged
  /// once.
  UnreadSpendCost(result: Int, emm_id: Int)
}

/// One caster vital requirement (`0x1403b1780`): resource slot `slot`, or its
/// percentage of its maximum, compared with `value`; refused with `result`.
pub type Requirement {
  Requirement(
    slot: Int,
    measure: Measure,
    comparison: Comparison,
    value: Int,
    result: Int,
  )
}

/// What a requirement compares: the slot's amount (evals 0 to 4) or its
/// percentage of its maximum (above 4) (`0x1403b1780`).
pub type Measure {
  Amount
  PercentOfMax
}

/// How a requirement compares, by its eval code (`0x1407a1750`).
pub type Comparison {
  /// 0 and 5.
  Equal
  /// 1 and 6.
  Greater
  /// 2 and 7.
  AtLeast
  /// 3 and 8.
  Less
  /// 4 and 9.
  AtMost
  /// Any other code, which never passes.
  NeverPasses(eval: Int)
}

/// One Proxy effect of a spell: the effect row that names the child, when the
/// child starts, and the child's own tree.
pub type Proxy {
  Proxy(
    effect_id: Spell4EffectsId,
    /// Spell4Effects.delayTime: after the go of the phase it fires in.
    delay_ms: Int,
    /// Spell4Effects.phaseFlags: bit n is phase n; -1 every phase.
    phase_flags: Int,
    condition: Condition,
    /// The Proxy starts when its tag holds for the points the cast spent
    /// (genesis_prime/game/spend).
    tag: spend.Tag,
    /// Which unit the child cast is made on, from the effect's `targetFlags`.
    target: ProxyTarget,
    spell: Spell,
    /// The first phase's gains of a child started at each struck unit, given once
    /// at the go of the parent whose units it struck; none for a child on the
    /// caster.
    gains: List(Gain),
  )
}

/// Where a spell is planned, which two of an effect row's refusals depend on: a spell a
/// Proxy starts on each struck unit (`struck_by`) and a spell that spends every point held
/// (`spends_all`).
pub type RowPlace {
  RowPlace(struck_by: Option(StruckBy), spends_all: Bool)
}

/// The Proxy that starts a spell as a child on each unit its area strikes: `spell4_id`
/// is the spell with the Proxy effect `proxy_effect_id`. The child's primary target is
/// then a struck unit (`target_of`).
pub type StruckBy {
  StruckBy(spell4_id: Int, proxy_effect_id: Int)
}

/// What the plan makes of one Spell4Effects row (`read_row`), the one decision the plan's
/// lists and the coverage measure both take from.
pub type RowReading {
  /// The row is in a list of its spell and a go applies it: the coverage measure counts
  /// it read.
  Applied(row: PlannedRow)
  /// The row is in a list of its spell and no go applies it: a periodic gain or heal
  /// (`TickingGain`, `TickingShieldHeal`), a row behind a target apply prerequisite
  /// (`cast.condition_gate`), a property change or disguise with no life
  /// (`lasting.has_life`) and a row whose phaseFlags is 0, which no phase selects
  /// (`in_phase`). The measure counts it not read.
  Held(row: PlannedRow)
  /// The row is in no list of its spell and the load goes on.
  LeftOut(why: LeftOutReason)
  /// A damage row: the area load reads it (genesis_prime/game/spell_area `damage_row_of`),
  /// and the plan holds it in no list.
  ReadByArea
}

/// Why a row is in no list of its spell.
pub type LeftOutReason {
  /// No rule of the server reads the effect type (`effect_kind.Unread`).
  TypeNotRead
  /// The type is read for the rows that reach the caster (or, for an overload, the area)
  /// and this row's targetFlags do not (`effect_kind.is_row_read`).
  AimedAtOtherUnits
  /// A Proc of a kind the holder's own events do not make (`proc_read`).
  ProcOfAnotherKind(kind: Int)
  /// A Proxy whose dataBits00 names no spell.
  ProxyNamesNoSpell
  /// A damage row whose phaseFlags is 0: no phase selects it (`spell_area` `phase`).
  InNoPhase
}

/// A row as the list of its spell holds it. A Proxy's child and a Proc's spell are planned
/// from the reading, by the spell that holds the row.
pub type PlannedRow {
  PlannedGain(gain: Gain)
  PlannedLasting(lasting: Lasting)
  PlannedRemove(remove: ForceRemove)
  PlannedControl(control: CrowdControl)
  PlannedModifier(modifier: PropertyModifier)
  PlannedForcedMove(forced_move: ForcedMove)
  PlannedCooldownModifier(modifier: CooldownModifier)
  PlannedStealth(stealth: StealthRow)
  PlannedRemoveStealth(remove: RemoveStealthRow)
  PlannedShieldHeal(heal: ShieldHeal)
  PlannedProc(reading: ProcReading, condition: Condition)
  PlannedProxy(target: ProxyTarget, condition: Condition)
}

/// Why a DisguiseOutfit row cannot be drawn with 0x933 (`Spell4Effects.effectType.112`).
pub type DisguiseGap {
  /// dataBits00 or dataBits08 names an outfit, which only 0x905 draws.
  OutfitNeedsMessage0x905
  /// Neither dataBits01 nor dataBits02 names an ItemDisplay.
  NamesNoDisplay
  /// The display's item type has no ItemSlot (itemSlotId 0).
  DisplayHasNoSlot(item_display_id: Int)
}

/// Why the plans cannot be built from the tables.
pub type PlanError {
  /// A table row the tree names is missing: the table, and the id.
  NoRow(table: String, id: Int)
  /// A Proxy effect of a tree is aimed by a flag value that is not read.
  ProxyAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// The Proxy effects of a spell lead back to a spell on the way to it: the
  /// Spell4 ids from the pressed ability to the one that repeats.
  ProxyCycle(chain: List(Int))
  /// A spell's innate cost is of a type whose check the client's code was not
  /// read for (`0x1403b3320`).
  UnreadCost(spell4_id: Int, cost_type: Int)
  /// A spell's caster vital requirement is of a type whose vital the server does
  /// not read (`0x1403b1780`).
  UnreadRequirement(spell4_id: Int, requirement_type: Int)
  /// A Channeled spell's channelPulseTime is 0, which gives no count of gos
  /// (`0x14053d1f0`).
  ChannelWithoutPulse(spell4_id: Int)
  /// A RapidTap or ChargeRelease ability's thresholdTime is 0, which the client
  /// refuses a press of with 285 (`0x1403bfd60`).
  NoThresholdTime(spell4_id: Int)
  /// A VitalModifier of a tree is aimed other than at the caster, which is not read.
  GainAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A VitalModifier of a tree changes a vital other than 6 or 8, which is not read.
  GainVitalNotRead(spell4_id: Int, effect_id: Int, vital: Int)
  /// A VitalModifier of a tree has a target apply prerequisite, which is not read.
  GainTargetPrerequisiteNotRead(spell4_id: Int, effect_id: Int)
  /// An effect of a spell that spends every point held holds an emmComparison other
  /// than 0 or 1, which chooses nothing (`Spell4Effects.emmComparison`).
  SpendComparisonNotRead(spell4_id: Int, effect_id: Int, comparison: Int)
  /// A SpellForceRemove effect of a tree has a dataBits00 other than 1, 2 or 3,
  /// which names no group, Spell4 or Spell4Base to take off
  /// (`Spell4Effects.effectType.80`).
  ForceRemoveSelectorNotRead(spell4_id: Int, effect_id: Int, selector: Int)
  /// A SpellForceRemove effect of a tree has a dataBits03 that differs from its
  /// dataBits04: which is the count of stacks is not settled
  /// (`Spell4Effects.effectType.80`).
  ForceRemoveCountsDiffer(
    spell4_id: Int,
    effect_id: Int,
    data_bits03: Int,
    data_bits04: Int,
  )
  /// A Fluff, SpellForceRemove, Scale or RavelSignal effect of a tree is aimed by a flag
  /// value that is not read (`Spell4Effects.targetFlags`).
  LastingAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A CCStateSet effect of a tree holds a state other than Stun and Knockdown,
  /// which no rule of the server holds on a creature (`Unit.CodeEnumCCState`).
  ControlStateNotRead(spell4_id: Int, effect_id: Int, state: Int)
  /// A CCStateSet effect of a tree is aimed at the caster or by a flag value that is
  /// not read: only the primary target, the area or both are
  /// (`Spell4Effects.targetFlags`).
  ControlAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A CCStateSet effect of a tree has an apply prerequisite, which is not read.
  ControlPrerequisiteNotRead(spell4_id: Int, effect_id: Int)
  /// A UnitPropertyModifier or UnitPropertyConversion effect of a tree names a property
  /// that UnitProperty2 has no row for, which the client's 0x93a refuses from id 197
  /// (`opcode.0x93a`).
  ModifierPropertyHasNoRow(spell4_id: Int, effect_id: Int, property: Int)
  /// A UnitPropertyModifier effect of a tree has a multiplier, flat amount or per-level
  /// amount, or a UnitPropertyConversion effect a share, that is not a finite number:
  /// `column` is its dataBits column.
  ModifierNumberNotFinite(spell4_id: Int, effect_id: Int, column: String)
  /// A ModifySpellCooldown effect of a tree has a dataBits03 that is not a finite
  /// number, for an operation that reads it (`Spell4Effects.effectType.73`).
  CooldownNumberNotFinite(spell4_id: Int, effect_id: Int)
  /// A Stealth or RemoveStealth effect of a tree is aimed other than at the caster
  /// alone, which is not read (`Spell4Effects.targetFlags`).
  StealthAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
  /// A Stealth or RemoveStealth effect of a tree has a target apply prerequisite, which
  /// is not read.
  StealthTargetPrerequisiteNotRead(spell4_id: Int, effect_id: Int)
  /// A Stealth effect of a tree has a delayTime or durationTime: timed stealth is not
  /// built (`Spell4Effects.effectType.83`).
  StealthTimedNotRead(spell4_id: Int, effect_id: Int)
  /// A Stealth effect of a tree has a dataBits02 that is not 0 or 1, the two values that
  /// say whether damage ends it (`Spell4Effects.effectType.83`).
  StealthBreaksNotRead(spell4_id: Int, effect_id: Int, value: Int)
  /// A spell of a tree has a caster or target Spell4Conditions row whose mask holds bit
  /// 16, the client's stealth test, whose refusals 65 and 114 are not checked
  /// (`Spell4Conditions.conditionMask.16`).
  StealthConditionNotRead(spell4_id: Int, spell4_conditions_id: Int)
  /// A spell of a tree has a spellCastStealthChange that is not 0, 1 or 2
  /// (`Spell4.spellCastStealthChange`).
  StealthChangeNotRead(spell4_id: Int, value: Int)
  /// A HealShields effect of a tree has a parameter type the formula for an effect on
  /// its caster does not read (`damage.caster_unread`).
  ShieldHealParameterNotRead(
    spell4_id: Int,
    effect_id: Int,
    parameter_kind: Int,
  )
  /// A HealShields effect of a tree has a dataBits00 that is not a finite 32-bit float.
  ShieldHealNumberNotFinite(spell4_id: Int, effect_id: Int)
  /// A Proxy of a tree starts a child on each unit its area strikes, and the child holds
  /// a HealShields effect aimed at its primary target, a struck unit: `spell4_id` is the
  /// spell with the Proxy `proxy_effect_id`, and `effect_id` the heal's row.
  ShieldHealOnStruckUnit(spell4_id: Int, proxy_effect_id: Int, effect_id: Int)
  /// A ModifyInterruptArmor effect of a tree has a dataBits01 that is not 0 or 1, the two
  /// values that say whether the armor is taken back when it ends
  /// (`Spell4Effects.effectType.52`).
  InterruptArmorTakeBackNotRead(spell4_id: Int, effect_id: Int, value: Int)
  /// A Proxy of a tree starts a child on each unit its area strikes, and the child holds a
  /// ModifyInterruptArmor effect aimed at its primary target, a struck unit: `spell4_id` is
  /// the spell with the Proxy `proxy_effect_id`, and `effect_id` the row.
  InterruptArmorOnStruckUnit(
    spell4_id: Int,
    proxy_effect_id: Int,
    effect_id: Int,
  )
  /// An Absorption effect of a tree has a parameter type the formula for an effect on its
  /// caster does not read (`damage.caster_unread`).
  AbsorptionParameterNotRead(
    spell4_id: Int,
    effect_id: Int,
    parameter_kind: Int,
  )
  /// An Absorption effect of a tree has a dataBits00 or dataBits01 that is not a finite
  /// 32-bit float.
  AbsorptionNumberNotFinite(spell4_id: Int, effect_id: Int)
  /// An Absorption effect of a tree gives 0 to every caster (`damage.gives_nothing`): which
  /// of dataBits00 and dataBits01 is the amount when the other is 0 is not known
  /// (`Spell4Effects.effectType.29`).
  AbsorptionAmountNotRead(spell4_id: Int, effect_id: Int)
  /// An Absorption effect of a tree has a tickTime: a periodic absorb's reading is not known
  /// (`Spell4Effects.effectType.29`).
  AbsorptionPeriodic(spell4_id: Int, effect_id: Int, tick_ms: Int)
  /// An Absorption effect of a tree has neither a durationTime nor flags bit 2: an absorb
  /// with no lifetime is not known (`Spell4Effects.effectType.29`).
  AbsorptionHasNoLifetime(spell4_id: Int, effect_id: Int)
  /// A Proxy of a tree starts a child on each unit its area strikes, and the child holds an
  /// Absorption effect aimed at its primary target, a struck unit: `spell4_id` is the spell
  /// with the Proxy `proxy_effect_id`, and `effect_id` the row.
  AbsorptionOnStruckUnit(spell4_id: Int, proxy_effect_id: Int, effect_id: Int)
  /// A Proc effect of a kind the server does not read (`proc_read`): the row is in no
  /// list of its spell and the load goes on, so this error is a skip, never a failure.
  ProcKindNotRead(spell4_id: Int, effect_id: Int, kind: Int)
  /// A Proc effect of a kind the server reads has a column the plan does not read: its
  /// name and value. The load fails (`proc_read`).
  ProcNotRead(spell4_id: Int, effect_id: Int, column: String, value: Int)
  /// A DisguiseOutfit effect of a tree aimed at the caster shows nothing the server can
  /// draw with 0x933 (`Spell4Effects.effectType.112`).
  DisguiseNotRead(spell4_id: Int, effect_id: Int, reason: DisguiseGap)
  /// A class's innate cannot be held (genesis_prime/game/innate).
  InnateFailed(error: innate.InnateError)
  /// A Prerequisite row a spell or effect names nests itself through the rows it
  /// nests (type 11): the ids from the named row to the one that repeats.
  PrerequisiteCycle(path: List(Int))
}

/// A sentence that says why the plans cannot be built, naming the table and the
/// row, for the message the server stops with.
pub fn describe(error error: PlanError) -> String {
  case error {
    NoRow(table:, id:) ->
      "the table "
      <> table
      <> " has no row "
      <> int.to_string(id)
      <> ", which an ability's tree of casts names"
    ProxyCycle(chain:) ->
      "the Proxy effects of an ability lead round a cycle of spells: "
      <> string_of(chain)
    ProxyAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proxy effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", which are not read"
    UnreadCost(spell4_id:, cost_type:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an innate cost of type "
      <> int.to_string(cost_type)
      <> ", which the client's check was not read for"
    UnreadRequirement(spell4_id:, requirement_type:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a caster vital requirement of type "
      <> int.to_string(requirement_type)
      <> ", whose vital the server does not read"
    ChannelWithoutPulse(spell4_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " is Channeled with a channelPulseTime of 0, which gives no count of pulses"
    NoThresholdTime(spell4_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " is a RapidTap or ChargeRelease ability with a thresholdTime of 0, which the client refuses"
    GainAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a VitalModifier effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", and only one aimed at the caster is read"
    GainVitalNotRead(spell4_id:, effect_id:, vital:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a VitalModifier effect "
      <> int.to_string(effect_id)
      <> " of vital "
      <> int.to_string(vital)
      <> ", and only vitals 6 and 8 are read"
    GainTargetPrerequisiteNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a VitalModifier effect "
      <> int.to_string(effect_id)
      <> " behind a target prerequisite, which is not read"
    SpendComparisonNotRead(spell4_id:, effect_id:, comparison:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " spends every point held and has an effect "
      <> int.to_string(effect_id)
      <> " of emmComparison "
      <> int.to_string(comparison)
      <> ", and only 0 and 1 are read"
    ForceRemoveSelectorNotRead(spell4_id:, effect_id:, selector:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a SpellForceRemove effect "
      <> int.to_string(effect_id)
      <> " of selector "
      <> int.to_string(selector)
      <> ", and only 1, 2 and 3 are read"
    ForceRemoveCountsDiffer(spell4_id:, effect_id:, data_bits03:, data_bits04:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a SpellForceRemove effect "
      <> int.to_string(effect_id)
      <> " whose dataBits03 "
      <> int.to_string(data_bits03)
      <> " differs from its dataBits04 "
      <> int.to_string(data_bits04)
      <> ", and only a row where they agree is read"
    LastingAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Fluff, SpellForceRemove, Scale or RavelSignal effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", which are not read"
    ControlStateNotRead(spell4_id:, effect_id:, state:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a CCStateSet effect "
      <> int.to_string(effect_id)
      <> " of state "
      <> int.to_string(state)
      <> ", and only Stun (0) and Knockdown (8) are read"
    ControlAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a CCStateSet effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", and only the primary target, the area or both are read"
    ControlPrerequisiteNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a CCStateSet effect "
      <> int.to_string(effect_id)
      <> " behind an apply prerequisite, which is not read"
    ModifierPropertyHasNoRow(spell4_id:, effect_id:, property:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a UnitPropertyModifier or UnitPropertyConversion effect "
      <> int.to_string(effect_id)
      <> " of property "
      <> int.to_string(property)
      <> ", which UnitProperty2 has no row for"
    ModifierNumberNotFinite(spell4_id:, effect_id:, column:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a UnitPropertyModifier or UnitPropertyConversion effect "
      <> int.to_string(effect_id)
      <> " whose "
      <> column
      <> " is not a finite number"
    CooldownNumberNotFinite(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a ModifySpellCooldown effect "
      <> int.to_string(effect_id)
      <> " whose dataBits03 is not a finite number"
    StealthAimNotRead(spell4_id:, effect_id:, target_flags:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Stealth or RemoveStealth effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", and only the caster alone is read"
    StealthTargetPrerequisiteNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Stealth or RemoveStealth effect "
      <> int.to_string(effect_id)
      <> " behind a target apply prerequisite, which is not read"
    StealthTimedNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Stealth effect "
      <> int.to_string(effect_id)
      <> " with a delayTime or durationTime, and timed stealth is not built"
    StealthBreaksNotRead(spell4_id:, effect_id:, value:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Stealth effect "
      <> int.to_string(effect_id)
      <> " whose dataBits02 is "
      <> int.to_string(value)
      <> ", and only 0 and 1 say whether damage ends it"
    StealthConditionNotRead(spell4_id:, spell4_conditions_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has the Spell4Conditions row "
      <> int.to_string(spell4_conditions_id)
      <> ", whose mask tests stealth, and the client's refusals 65 and 114 are not checked"
    StealthChangeNotRead(spell4_id:, value:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a spellCastStealthChange of "
      <> int.to_string(value)
      <> ", and only 0, 1 and 2 are read"
    ShieldHealParameterNotRead(spell4_id:, effect_id:, parameter_kind:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a HealShields effect "
      <> int.to_string(effect_id)
      <> " with a parameter of type "
      <> int.to_string(parameter_kind)
      <> ", which the caster's formula does not read"
    ShieldHealNumberNotFinite(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a HealShields effect "
      <> int.to_string(effect_id)
      <> " whose dataBits00 is not a finite number"
    ShieldHealOnStruckUnit(spell4_id:, proxy_effect_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proxy effect "
      <> int.to_string(proxy_effect_id)
      <> " that starts a child on each struck unit, which holds the HealShields effect "
      <> int.to_string(effect_id)
      <> " aimed at that unit, and a shield heal on a struck unit is not built"
    InterruptArmorTakeBackNotRead(spell4_id:, effect_id:, value:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a ModifyInterruptArmor effect "
      <> int.to_string(effect_id)
      <> " whose dataBits01 is "
      <> int.to_string(value)
      <> ", and only 0 and 1 say whether the armor is taken back"
    InterruptArmorOnStruckUnit(spell4_id:, proxy_effect_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proxy effect "
      <> int.to_string(proxy_effect_id)
      <> " that starts a child on each struck unit, which holds the ModifyInterruptArmor effect "
      <> int.to_string(effect_id)
      <> " aimed at that unit, and Interrupt Armor on a struck unit is not built"
    AbsorptionParameterNotRead(spell4_id:, effect_id:, parameter_kind:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " with a parameter of type "
      <> int.to_string(parameter_kind)
      <> ", which the caster's formula does not read"
    AbsorptionNumberNotFinite(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " whose dataBits00 or dataBits01 is not a finite number"
    AbsorptionAmountNotRead(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " whose multiplier or base is 0 and no parameter gives it a value, so its amount is not read"
    AbsorptionPeriodic(spell4_id:, effect_id:, tick_ms:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " with a tickTime of "
      <> int.to_string(tick_ms)
      <> ", and a periodic absorb is not read"
    AbsorptionHasNoLifetime(spell4_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an Absorption effect "
      <> int.to_string(effect_id)
      <> " with no durationTime and no flags bit 2, and an absorb with no lifetime is not read"
    AbsorptionOnStruckUnit(spell4_id:, proxy_effect_id:, effect_id:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proxy effect "
      <> int.to_string(proxy_effect_id)
      <> " that starts a child on each struck unit, which holds the Absorption effect "
      <> int.to_string(effect_id)
      <> " aimed at that unit, and an absorb on a struck unit is not built"
    ProcKindNotRead(spell4_id:, effect_id:, kind:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proc effect "
      <> int.to_string(effect_id)
      <> " of kind "
      <> int.to_string(kind)
      <> ", which is not read"
    ProcNotRead(spell4_id:, effect_id:, column:, value:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a Proc effect "
      <> int.to_string(effect_id)
      <> " whose "
      <> column
      <> " is "
      <> int.to_string(value)
      <> ", which is not read"
    DisguiseNotRead(spell4_id:, effect_id:, reason:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has a DisguiseOutfit effect "
      <> int.to_string(effect_id)
      <> case reason {
        OutfitNeedsMessage0x905 -> " with an outfit, which only 0x905 draws"
        NamesNoDisplay -> " that names no ItemDisplay"
        DisplayHasNoSlot(item_display_id:) ->
          " whose ItemDisplay "
          <> int.to_string(item_display_id)
          <> " has an item type with no ItemSlot"
      }
    InnateFailed(error:) -> innate.describe(error:)
    PrerequisiteCycle(path:) ->
      "the Prerequisite rows nest each other round a cycle: " <> string_of(path)
  }
}

fn string_of(chain: List(Int)) -> String {
  string.join(list.map(chain, int.to_string), " -> ")
}

/// Every class's level-1 abilities and slot-0 innate spells as trees, by
/// Spell4BaseId, as the load keeps them.
pub type Plans =
  Dict(Int, Spell)

const plans_key: table_store.DerivedKey(Plans) =
  table_store.DerivedKey("SpellPlans")

/// The plans as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`): a plan for the Spell4BaseId of
/// each class's level-1 ability and of each class's innate active and passive spell.
/// A missing row, a cost not read or a cycle fails the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: plans_key, build: fn(tables) {
    build(tables:)
    |> result.map_error(fn(error) { describe(error:) })
  })
}

/// The rows the tree reads, grouped by the spell they belong to.
pub opaque type Sources {
  Sources(
    effects: Dict(Int, List(spell4_effects.Spell4Effects)),
    phases: Dict(Int, List(Phase)),
    thresholds: Dict(Int, List(spell4_thresholds.Spell4Thresholds)),
    /// The spell group ids of each Spell4GroupList row, by the row's id.
    group_lists: Dict(Int, List(Int)),
    /// Every spell group id some Spell4GroupList row holds.
    known_groups: Set(Int),
  )
}

/// The rows the plan reads from the loaded tables, grouped once: what `build` and
/// `spell_alone` plan from.
pub fn sources_of(tables tables: table_store.Tables) -> Sources {
  let group_lists = group_lists_by_id(tables:)
  Sources(
    effects: effects_by_spell(tables:),
    phases: phases_by_owner(tables:),
    thresholds: thresholds_by_parent(tables:),
    group_lists:,
    known_groups: known_groups(group_lists:),
  )
}

/// Every spell group id some Spell4GroupList row holds, which a SpellForceRemove selector
/// may name (`read_row`).
pub fn spell_groups(tables tables: table_store.Tables) -> Set(Int) {
  known_groups(group_lists: group_lists_by_id(tables:))
}

fn known_groups(group_lists group_lists: Dict(Int, List(Int))) -> Set(Int) {
  set.from_list(list.flatten(dict.values(group_lists)))
}

/// A SpellPhase row the client keeps.
type Phase {
  Phase(delay_ms: Int, flags: Int)
}

/// Builds every plan from the loaded tables, or why one cannot be built; the
/// derivation's body, and the function a test of a missing row or a cycle runs
/// on planted tables.
pub fn build(tables tables: table_store.Tables) -> Result(Plans, PlanError) {
  let sources = sources_of(tables:)
  use held <- result.try(innate.held(tables:) |> result.map_error(InnateFailed))
  let abilities =
    spell_level.all(tables)
    |> list.filter(loadout.is_level_one_ability)
    |> list.map(fn(row) { row.spell4_id })
  let innates =
    dict.to_list(held)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.flat_map(fn(entry) {
      let innate = entry.1
      [
        innate.active.value,
        ..case innate.passive {
          Some(passive) -> [passive.spell4_id.value]
          None -> []
        }
      ]
    })
  list.try_fold(
    list.append(abilities, innates),
    dict.new(),
    fn(plans, spell4_id) {
      use spell <- result.try(spell_of(
        tables:,
        sources:,
        spell4_id:,
        chain: [],
        threshold_costs: [],
        struck_by: None,
      ))
      use Nil <- result.try(has_threshold_time(spell:))
      Ok(dict.insert(plans, spell.spell4_base_id.value, spell))
    },
  )
}

/// A Proxy the server adds to a tree, which starts `child` on the caster at once at
/// each go of the phases `phase_flags` names, with no gate and no gain lifted. It
/// stands for no Spell4Effects row, so its effect id is 0
/// (genesis_prime/game/server_proxy).
pub fn server_proxy(child child: Spell, phase_flags phase_flags: Int) -> Proxy {
  Proxy(
    effect_id: Spell4EffectsId(0),
    delay_ms: 0,
    phase_flags:,
    condition: Always,
    tag: spend.always,
    target: OnCaster,
    spell: child,
    gains: [],
  )
}

/// A RapidTap or ChargeRelease ability opens a threshold of its thresholdTime, so
/// a press of one with none is refused by the client (`0x1403bfd60`).
fn has_threshold_time(spell spell: Spell) -> Result(Nil, PlanError) {
  case spell.method {
    RapidTap | ChargeRelease if spell.threshold_ms == 0 ->
      Error(NoThresholdTime(spell4_id: spell.spell4_id.value))
    RapidTap
    | ChargeRelease
    | Normal
    | Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | Multiphase
    | Transactional
    | OtherMethod(..) -> Ok(Nil)
  }
}

/// The effects of each spell, of every type, in the order they take effect
/// (`Spell4Effects.orderIndex`, then the row id): the plans read the Proxies among
/// them and the areas the damage, so the table is grouped once.
pub fn effects_by_spell(
  tables tables: table_store.Tables,
) -> Dict(Int, List(spell4_effects.Spell4Effects)) {
  spell4_effects.all(tables)
  |> list.group(fn(effect) { effect.spell_id })
  |> dict.map_values(fn(_, effects) {
    list.sort(effects, fn(first, second) {
      int.compare(first.order_index, second.order_index)
      |> order.break_tie(int.compare(first.id, second.id))
    })
  })
}

fn phases_by_owner(
  tables tables: table_store.Tables,
) -> Dict(Int, List(Phase)) {
  spell_phase.all(tables)
  |> list.filter(fn(phase) {
    phase.order_index < max_phases
    && { phase.order_index == 0 || phase.phase_delay != 0 }
  })
  |> list.group(fn(phase) { phase.spell4_id_owner })
  |> dict.map_values(fn(_, phases) {
    list.reverse(phases)
    |> list.map(fn(phase) {
      Phase(delay_ms: phase.phase_delay, flags: phase.phase_flags)
    })
  })
}

/// The spell group ids each Spell4GroupList row names, by the row's id: its
/// spellGroupId00 to 31 values that are not 0.
fn group_lists_by_id(
  tables tables: table_store.Tables,
) -> Dict(Int, List(Int)) {
  spell4_group_list.all(tables)
  |> list.map(fn(row) {
    #(row.id, list.filter(group_ids_of(row:), fn(group) { group != 0 }))
  })
  |> dict.from_list
}

/// The Spell4Thresholds rows of each spell, by order index
/// (`Spell4Thresholds.spell4IdToCast`: the client sorts them by the row's order
/// index, `0x140566940`).
fn thresholds_by_parent(
  tables tables: table_store.Tables,
) -> Dict(Int, List(spell4_thresholds.Spell4Thresholds)) {
  spell4_thresholds.all(tables)
  |> list.group(fn(row) { row.spell4_id_parent })
  |> dict.map_values(fn(_, rows) {
    list.sort(rows, fn(first, second) {
      int.compare(first.order_index, second.order_index)
      |> order.break_tie(int.compare(first.id, second.id))
    })
  })
}

/// The client keeps phase rows with an order index below 32 (`0x14055e180`).
const max_phases = 32

/// The phase flag that moves a Multiphase spell's cooldown to its last phase
/// (`0x14053e5a0`).
const cooldown_at_last_phase_flag = 0x200

/// The chain of spells from the pressed ability to `spell4_id`, which fails as a
/// `ProxyCycle` naming the whole chain when `spell4_id` is already on it: a Proxy or a
/// Proc effect that leads back to a spell on the way would start it for ever.
pub fn chain_extended(
  chain chain: List(Int),
  spell4_id spell4_id: Int,
) -> Result(List(Int), PlanError) {
  let chain = list.append(chain, [spell4_id])
  case list.contains(list.take(chain, list.length(chain) - 1), spell4_id) {
    True -> Error(ProxyCycle(chain:))
    False -> Ok(chain)
  }
}

/// One Proxy row of the spell `spell4_id` as a `Proxy`: the child it names planned on the
/// same chain, and the gains of a child started on each struck unit lifted onto it.
fn proxy_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  chain chain: List(Int),
  effect effect: spell4_effects.Spell4Effects,
  target target: ProxyTarget,
  condition condition: Condition,
) -> Result(Proxy, PlanError) {
  use child <- result.map(
    spell_of(
      tables:,
      sources:,
      spell4_id: effect.data_bits00,
      chain:,
      threshold_costs: [],
      struck_by: case target {
        OnEachStruck -> Some(StruckBy(spell4_id:, proxy_effect_id: effect.id))
        OnCaster -> None
      },
    ),
  )
  // Every gain under a Proxy aimed at each struck unit in the client's level-1 trees fires
  // in phase 0 only (`spell_plan_gain_test` reads them all), so lifting by phase 0 loses
  // none to a later phase.
  let #(lifted, kept) = case target {
    OnEachStruck ->
      list.partition(child.gains, fn(gain) {
        has_flag(flags: gain.phase_flags, bit: 1)
      })
    OnCaster -> #([], child.gains)
  }
  Proxy(
    effect_id: Spell4EffectsId(effect.id),
    delay_ms: effect.delay_time,
    phase_flags: effect.phase_flags,
    condition:,
    tag: tag_of(effect:),
    target:,
    spell: Spell(..child, gains: kept),
    gains: lifted,
  )
}

fn spell_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  chain chain: List(Int),
  threshold_costs threshold_costs: List(#(Int, Int)),
  struck_by struck_by: Option(StruckBy),
) -> Result(Spell, PlanError) {
  use chain <- result.try(chain_extended(chain:, spell4_id:))
  use row <- result.try(
    spell4.get(tables:, id: Spell4Id(spell4_id))
    |> result.replace_error(NoRow(table: "Spell4", id: spell4_id)),
  )
  use base <- result.try(
    spell4_base.get(tables:, id: Spell4BaseId(row.spell4_base_id_base_spell))
    |> result.replace_error(NoRow(
      table: "Spell4Base",
      id: row.spell4_base_id_base_spell,
    )),
  )
  use global_cooldown <- result.try(global_cooldown_of(tables:, row:))
  let rows = prerequisite.table_rows(tables:)
  let arcs = prerequisite.table_arcs(tables:)
  use caster_cast <- result.try(caster_cast_of(
    prerequisite_id: row.prerequisite_id_caster_cast,
    property_flags: row.property_flags,
    requirement_block: #(
      row.caster_innate_requirement0,
      row.caster_innate_requirement1,
      row.target_begin_innate_requirement,
    ),
    rows:,
    arcs:,
  ))
  use target_cast <- result.try(column_of(
    id: row.prerequisite_id_target_cast,
    rows:,
    arcs:,
  ))
  use caster_persistence <- result.try(column_of(
    id: row.prerequisite_id_caster_persistence,
    rows:,
    arcs:,
  ))
  use target_persistence <- result.try(column_of(
    id: row.prerequisite_id_target_persistence,
    rows:,
    arcs:,
  ))
  use caster_conditions <- result.try(conditions_row_of(
    tables:,
    id: row.spell4_conditions_id_caster,
  ))
  use target_conditions <- result.try(conditions_row_of(
    tables:,
    id: row.spell4_conditions_id_target,
  ))
  let caster_death = caster_death_of(conditions: caster_conditions)
  use costs <- result.try(
    costs_of(tables:, row:, base:, costs: [
      #(row.innate_cost_type0, row.innate_cost0, row.innate_cost_emm_id0),
      #(row.innate_cost_type1, row.innate_cost1, row.innate_cost_emm_id1),
      ..list.map(threshold_costs, fn(cost) { #(cost.0, cost.1, 0) })
    ]),
  )
  use requirements <- result.try(
    requirements_of(spell4_id:, requirements: [
      #(
        row.caster_innate_requirement0,
        row.caster_innate_requirement_eval0,
        row.caster_innate_requirement_value0,
      ),
      #(
        row.caster_innate_requirement1,
        row.caster_innate_requirement_eval1,
        row.caster_innate_requirement_value1,
      ),
    ]),
  )
  let effects = dict.get(sources.effects, spell4_id) |> result.unwrap([])
  let place = RowPlace(struck_by:, spends_all: spends_all_of(costs:))
  use Nil <- result.try(
    list.try_each(effects, spend_tag_read(place:, effect: _)),
  )
  let readings =
    list.map(effects, fn(effect) {
      #(
        effect,
        read_row(tables:, spell_groups: sources.known_groups, place:, effect:),
      )
    })
  // The rows of each list are read in the order the lists were once built, so a spell with
  // two refused rows names the same one first.
  use Nil <- result.try(
    list.try_each(
      [
        [effect_kind.VitalModifier],
        [
          effect_kind.Fluff,
          effect_kind.Scale,
          effect_kind.RavelSignal,
          effect_kind.ShieldOverload,
        ],
        [effect_kind.ForceRemove],
        [effect_kind.CrowdControl],
        [
          effect_kind.PropertyModifier,
          effect_kind.PropertyConversion,
          effect_kind.DisguiseOutfit,
          effect_kind.Absorption,
        ],
        [effect_kind.InterruptArmor],
        [effect_kind.ForcedMove],
        [effect_kind.CooldownModifier],
        [effect_kind.Stealth],
        [effect_kind.RemoveStealth],
        [effect_kind.ShieldHeal],
      ],
      fn(kinds) { rows_read(readings:, kinds:) },
    ),
  )
  let lists = lists_of(readings:)
  use stealth_change <- result.try(stealth_change_of(
    spell4_id:,
    value: row.spell_cast_stealth_change,
  ))
  use procs <- result.try(procs_of(tables:, sources:, readings:, chain:))
  use Nil <- result.try(
    stealth_conditions_read(spell4_id:, conditions: [
      caster_conditions,
      target_conditions,
    ]),
  )
  use cooldown_groups <- result.try(cooldown_groups_of(tables:, row:))
  use groups <- result.try(groups_of(sources:, row:))
  use stack <- result.try(stack_of(tables:, row:))
  use proxies <- result.try(
    rows_of_kind(readings:, kind: effect_kind.Proxy)
    |> list.try_map(fn(row) {
      let #(effect, reading) = row
      use reading <- result.try(reading)
      case reading {
        Applied(PlannedProxy(target:, condition:))
        | Held(PlannedProxy(target:, condition:)) ->
          proxy_of(
            tables:,
            sources:,
            spell4_id:,
            chain:,
            effect:,
            target:,
            condition:,
          )
          |> result.map(fn(proxy) { [proxy] })
        Applied(..) | Held(..) | LeftOut(..) | ReadByArea -> Ok([])
      }
    })
    |> result.map(list.flatten),
  )
  use stages <- result.try(
    dict.get(sources.thresholds, spell4_id)
    |> result.unwrap([])
    |> list.try_map(fn(threshold) {
      use stage <- result.try(spell_of(
        tables:,
        sources:,
        spell4_id: threshold.spell4_id_to_cast,
        chain:,
        threshold_costs: [
          #(threshold.vital_enum_cost_type00, threshold.vital_cost_value00),
          #(threshold.vital_enum_cost_type01, threshold.vital_cost_value01),
        ],
        struck_by: None,
      ))
      Ok(Stage(duration_ms: threshold.threshold_duration, spell: stage))
    }),
  )
  let method = method_of(base.cast_method)
  let phases = dict.get(sources.phases, spell4_id) |> result.unwrap([])
  use delays <- result.try(phase_delays(phases:, method:, spell4_id:))
  use channel <- result.try(channel_of(row:, method:))
  let spell =
    Spell(
      spell4_id: Spell4Id(spell4_id),
      spell4_base_id: Spell4BaseId(row.spell4_base_id_base_spell),
      method:,
      cast_time_ms: row.cast_time,
      cooldown_ms: row.spell_cool_down,
      cooldown_start: cooldown_start_of(method:, phases:),
      cooldown_phase: cooldown_phase_of(method:, phases:),
      cast_bar: cast_bar_of(method:, row:, base:),
      free_while_live: has_flag(flags: row.property_flags, bit: 0x40),
      ignores_casting: has_flag(flags: row.property_flags, bit: 0x10)
        || has_flag(flags: row.property_flags, bit: 0x1),
      longer_of_delay_and_duration: has_flag(
        flags: row.property_flags,
        bit: 0x2000,
      ),
      weapon: weapon_of(base.weapon_slot),
      caster_death:,
      global_cooldown:,
      costs:,
      requirements:,
      caster_cast:,
      target_cast:,
      caster_persistence:,
      target_persistence:,
      phase_delays_ms: delays,
      threshold_ms: row.threshold_time,
      stages:,
      channel:,
      proxies:,
      gains: lists.gains,
      groups:,
      stack:,
      lasting: lists.lasting,
      removes: lists.removes,
      controls: lists.controls,
      modifiers: list.append(lists.modifiers, lists.armors),
      forced_moves: lists.forced_moves,
      cooldown_groups:,
      cooldown_modifiers: lists.cooldown_modifiers,
      stealth: lists.stealth,
      remove_stealth: lists.remove_stealth,
      shield_heals: lists.shield_heals,
      stealth_change:,
      procs:,
    )
  Ok(spell)
}

/// One VitalModifier row as a gain, which must aim at the caster, change vital 6 or 8, and
/// have no target apply prerequisite; its caster apply prerequisite is read from its row.
/// A row with a tickTime is a `TickingGain`, which the cast rule does not apply.
fn gain_row_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Gain, PlanError) {
  use slot <- result.try(case aim_of(target_flags: effect.target_flags) {
    AimsAtCaster -> gain_slot_of(spell4_id:, effect:)
    AimsAtPrimaryTarget | AimsAtArea | AimsAtBoth | OtherAim(..) ->
      Error(GainAimNotRead(
        spell4_id:,
        effect_id: effect.id,
        target_flags: effect.target_flags,
      ))
  })
  use Nil <- result.try(case effect.prerequisite_id_target_apply {
    0 -> Ok(Nil)
    _ -> Error(GainTargetPrerequisiteNotRead(spell4_id:, effect_id: effect.id))
  })
  use prerequisite <- result.try(case effect.prerequisite_id_caster_apply {
    0 -> Ok(None)
    id ->
      prerequisite_of(tables:, id:)
      |> result.map(Some)
  })
  let effect_id = Spell4EffectsId(effect.id)
  let amount = effect.data_bits02
  let phase_flags = effect.phase_flags
  let tag = tag_of(effect:)
  Ok(case effect.tick_time {
    0 -> Gain(effect_id:, slot:, amount:, phase_flags:, prerequisite:, tag:)
    tick_ms ->
      TickingGain(
        effect_id:,
        slot:,
        amount:,
        phase_flags:,
        prerequisite:,
        tag:,
        tick_ms:,
        duration_ms: effect.duration_time,
      )
  })
}

/// One HealShields row that reaches the caster as a heal, or the error that fails the
/// load: its dataBits00 must be a finite 32-bit float and its formula must read only the
/// parameter types an effect on its caster reads (genesis_prime/game/damage
/// `caster_unread`). It aims at the caster when its targetFlags include it and else at
/// the primary target. A row with a tickTime is periodic, a `TickingShieldHeal`.
pub fn shield_heal_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  condition condition: Condition,
) -> Result(ShieldHeal, PlanError) {
  use formula <- result.try(
    caster_formula_read(
      formula: damage.formula_of(effect:),
      not_finite: ShieldHealNumberNotFinite(spell4_id:, effect_id: effect.id),
      not_read: fn(parameter_kind) {
        ShieldHealParameterNotRead(
          spell4_id:,
          effect_id: effect.id,
          parameter_kind:,
        )
      },
    ),
  )
  let effect_id = Spell4EffectsId(effect.id)
  let aim = reached_aim_of(effect:)
  let phase_flags = effect.phase_flags
  let tag = tag_of(effect:)
  Ok(case effect.tick_time {
    0 ->
      ShieldHeal(
        effect_id:,
        phase_flags:,
        aim:,
        condition:,
        tag:,
        formula:,
        delay_ms: effect.delay_time,
      )
    tick_ms ->
      TickingShieldHeal(
        effect_id:,
        phase_flags:,
        aim:,
        condition:,
        tag:,
        tick_ms:,
        duration_ms: effect.duration_time,
      )
  })
}

/// One Fluff, Scale, RavelSignal or area ShieldOverload row as a lasting row: aimed at a
/// unit the plan reads, with the columns that give its node a life (`Spell4Effects.effectType.17`,
/// `.18` and `.81`).
fn lasting_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Lasting, PlanError) {
  use aim <- result.try(lasting_aim_of(spell4_id:, effect:))
  use condition <- result.map(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  Lasting(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    aim:,
    row: lasting_row_of(effect:),
    condition:,
    tag: tag_of(effect:),
  )
}

/// The columns of a row that give its node a life: its delay and durationTime and whether
/// its flags have bit 2, until removed (`Spell4Effects.effectType.17`).
fn lasting_row_of(
  effect effect: spell4_effects.Spell4Effects,
) -> lasting.LastingRow {
  lasting.LastingRow(
    delay_ms: effect.delay_time,
    duration_ms: effect.duration_time,
    until_removed: has_flag(flags: effect.flags, bit: 2),
  )
}

/// One SpellForceRemove row (`Spell4Effects.effectType.80`): dataBits00 picks what is
/// removed (1 a spell group, 2 a Spell4, 3 a Spell4Base) by dataBits01, which must name a
/// row; the count of stacks is read only where dataBits03 and dataBits04 agree.
fn remove_of(
  tables tables: table_store.Tables,
  spell_groups spell_groups: Set(Int),
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ForceRemove, PlanError) {
  use aim <- result.try(lasting_aim_of(spell4_id:, effect:))
  use selector <- result.try(selector_of(
    tables:,
    spell_groups:,
    spell4_id:,
    effect:,
  ))
  use Nil <- result.try(force_remove_counts_read(spell4_id:, effect:))
  use condition <- result.map(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  ForceRemove(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    aim:,
    selector:,
    count: effect.data_bits03,
    condition:,
    tag: tag_of(effect:),
  )
}

/// A type 80 row's count of stacks is read only where dataBits03 and dataBits04 agree
/// (`Spell4Effects.effectType.80`); a row where they differ fails the load.
fn force_remove_counts_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Nil, PlanError) {
  use <- bool.guard(
    when: effect.data_bits03 == effect.data_bits04,
    return: Ok(Nil),
  )
  Error(ForceRemoveCountsDiffer(
    spell4_id:,
    effect_id: effect.id,
    data_bits03: effect.data_bits03,
    data_bits04: effect.data_bits04,
  ))
}

/// One CCStateSet row (`Spell4Effects.effectType.4`): dataBits00 must be Stun or
/// Knockdown, the effect must aim at the primary target, the area or both, and it must
/// have no apply prerequisite. Its delayTime, durationTime and the armor it removes
/// (dataBits03) are read as they are.
fn control_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(CrowdControl, PlanError) {
  use state <- result.try(case effect.data_bits00 {
    0 | 8 -> Ok(crowd_control_state.from_value(effect.data_bits00))
    other ->
      Error(ControlStateNotRead(spell4_id:, effect_id: effect.id, state: other))
  })
  use aim <- result.try(case aim_of(target_flags: effect.target_flags) {
    AimsAtPrimaryTarget -> Ok(AimsAtPrimaryTarget)
    AimsAtArea -> Ok(AimsAtArea)
    AimsAtBoth -> Ok(AimsAtBoth)
    AimsAtCaster | OtherAim(..) ->
      Error(ControlAimNotRead(
        spell4_id:,
        effect_id: effect.id,
        target_flags: effect.target_flags,
      ))
  })
  use Nil <- result.map(
    case
      effect.prerequisite_id_caster_apply,
      effect.prerequisite_id_target_apply
    {
      0, 0 -> Ok(Nil)
      _, _ ->
        Error(ControlPrerequisiteNotRead(spell4_id:, effect_id: effect.id))
    },
  )
  CrowdControl(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    aim:,
    row: crowd_control.Row(
      state:,
      delay_ms: effect.delay_time,
      duration_ms: effect.duration_time,
      armor_removed: effect.data_bits03,
    ),
    tag: tag_of(effect:),
  )
}

/// One UnitPropertyModifier, UnitPropertyConversion, DisguiseOutfit or Absorption row as a
/// `PropertyModifier` that holds the caster `condition` it was given, or the error that
/// fails the load. A type 11 row (`Spell4Effects.effectType.11.change`): dataBits00 is the
/// property, which UnitProperty2 must have a row for, dataBits01 the mode, dataBits02 the
/// multiplier, dataBits03 the flat amount and dataBits04 the amount for each level, all
/// three as the 32-bit floats their columns hold, which must be finite. A type 145 row
/// (`conversion_of`).
pub fn modifier_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  condition condition: Condition,
) -> Result(PropertyModifier, PlanError) {
  use change <- result.map(case effect_kind.kind_of(effect.effect_type) {
    effect_kind.DisguiseOutfit ->
      disguise_of(tables:, spell4_id:, effect:)
      |> result.map(LookChange)
    effect_kind.Absorption ->
      absorption_read(spell4_id:, effect:)
      |> result.map(AbsorbChange)
    effect_kind.PropertyConversion ->
      conversion_of(tables:, spell4_id:, effect:)
      |> result.map(PropertyChange)
    effect_kind.PropertyModifier
    | effect_kind.Proxy
    | effect_kind.Damage
    | effect_kind.VitalModifier
    | effect_kind.Fluff
    | effect_kind.ForceRemove
    | effect_kind.CrowdControl
    | effect_kind.ForcedMove
    | effect_kind.CooldownModifier
    | effect_kind.Stealth
    | effect_kind.RemoveStealth
    | effect_kind.ShieldHeal
    | effect_kind.ShieldOverload
    | effect_kind.InterruptArmor
    | effect_kind.Proc
    | effect_kind.Scale
    | effect_kind.RavelSignal
    | effect_kind.Unread(..) ->
      change_of(tables:, spell4_id:, effect:)
      |> result.map(PropertyChange)
  })
  PropertyModifier(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    change:,
    row: lasting_row_of(effect:),
    condition:,
    tag: tag_of(effect:),
    armor: None,
  )
}

/// A DisguiseOutfit row's change (`Spell4Effects.effectType.112`): dataBits02 is an
/// ItemDisplay worn in its item type's slot and dataBits01 an ItemDisplay of a
/// WeaponPrimary item, each shown in the ItemSlot of its ItemDisplay's item2TypeId. A row
/// with dataBits00 or dataBits08 set is an outfit (`OutfitNeedsMessage0x905`), one with
/// neither display `NamesNoDisplay`, a display with no ItemDisplay, Item2Type or ItemSlot
/// row `NoRow` and a type with no slot `DisplayHasNoSlot`. dataBits03 is not read.
fn disguise_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(look.Disguise, PlanError) {
  use displays <- result.try(disguise_displays_of(spell4_id:, effect:))
  use shown <- result.map(
    list.try_map(displays, fn(display) {
      use item_slot <- result.map(display_slot(
        tables:,
        spell4_id:,
        effect:,
        display:,
      ))
      worn_visual.WornVisual(slot: item_slot, display: ItemDisplayId(display))
    }),
  )
  look.Disguise(shown:)
}

/// The ItemDisplay ids a DisguiseOutfit row shows, dataBits01 then dataBits02, or why
/// 0x933 cannot draw it: dataBits00 or dataBits08 set is an outfit, which only 0x905 draws,
/// and a row with neither display names nothing to show.
fn disguise_displays_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(List(Int), PlanError) {
  let refused = fn(reason) {
    Error(DisguiseNotRead(spell4_id:, effect_id: effect.id, reason:))
  }
  use <- bool.guard(
    when: effect.data_bits00 != 0 || effect.data_bits08 != 0,
    return: refused(OutfitNeedsMessage0x905),
  )
  case list.filter([effect.data_bits01, effect.data_bits02], fn(d) { d != 0 }) {
    [] -> refused(NamesNoDisplay)
    displays -> Ok(displays)
  }
}

/// The ItemSlot an ItemDisplay is worn in: its row's item type's itemSlotId, which
/// must name an ItemSlot row (`0x140466d20`: the slot of an item visual is an ItemSlot
/// id). A missing row fails the load, and an item type with itemSlotId 0 has no slot.
fn display_slot(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  display display: Int,
) -> Result(ItemSlotId, PlanError) {
  use row <- result.try(
    item_display.get(tables:, id: ItemDisplayId(display))
    |> result.replace_error(NoRow(table: "ItemDisplay", id: display)),
  )
  let item_type = item_display.item2_type_id(row)
  use item_type_row <- result.try(
    item2_type.get(tables:, id: item_type)
    |> result.replace_error(NoRow(table: "Item2Type", id: item_type.value)),
  )
  let slot = item2_type.item_slot_id(item_type_row)
  use <- bool.guard(
    when: slot.value == 0,
    return: Error(DisguiseNotRead(
      spell4_id:,
      effect_id: effect.id,
      reason: DisplayHasNoSlot(item_display_id: display),
    )),
  )
  item_slot.get(tables:, id: slot)
  |> result.replace(slot)
  |> result.replace_error(NoRow(table: "ItemSlot", id: slot.value))
}

/// One ModifyInterruptArmor row as the change of property 44 and the armor it makes, or
/// the error that fails the load: dataBits00 is the points, dataBits01 0 or 1 says
/// whether the end takes them back (`Spell4Effects.effectType.52`), and the row's delay,
/// durationTime and flags bit 2 time it as a type 11 row's do. It aims at the caster when
/// its targetFlags include it and else at the primary target.
pub fn interrupt_armor_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  condition condition: Condition,
) -> Result(PropertyModifier, PlanError) {
  use armor <- result.map(interrupt_armor_read(spell4_id:, effect:))
  PropertyModifier(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    change: PropertyChange(modifier: unit_properties.interrupt_armor_modifier(
      points: armor.points,
    )),
    row: lasting_row_of(effect:),
    condition:,
    tag: tag_of(effect:),
    armor: Some(armor),
  )
}

/// The armor a ModifyInterruptArmor row gives: its points, whether the end takes them
/// back, and the unit its targetFlags aim at.
fn interrupt_armor_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(InterruptArmor, PlanError) {
  use takes_back <- result.map(case effect.data_bits01 {
    0 -> Ok(False)
    1 -> Ok(True)
    value ->
      Error(InterruptArmorTakeBackNotRead(
        spell4_id:,
        effect_id: effect.id,
        value:,
      ))
  })
  InterruptArmor(
    points: effect.data_bits00,
    takes_back:,
    aim: reached_aim_of(effect:),
  )
}

/// The unit a timed row aims at: the caster for a type 11, type 145 or type 112 row, which
/// the plan reads only when its targetFlags include the caster, and for a type 52 or type
/// 29 row what its targetFlags name, the primary target of a cast on the caster being the
/// caster. Only the caster is changed: the server gives no other unit a property, an
/// armor or a pool.
pub fn modifier_aim(modifier modifier: PropertyModifier) -> Aim {
  case modifier.armor, modifier.change {
    Some(armor), _ -> armor.aim
    None, AbsorbChange(absorption:) -> absorption.aim
    None, PropertyChange(..) | None, LookChange(..) -> AimsAtCaster
  }
}

/// The unit a row aims at when its targetFlags reach the caster or the primary target: the
/// caster when they include it (bit 1), else the primary target, which a spell cast on the
/// caster makes the caster.
fn reached_aim_of(effect effect: spell4_effects.Spell4Effects) -> Aim {
  use <- bool.guard(
    when: has_flag(flags: effect.target_flags, bit: 1),
    return: AimsAtCaster,
  )
  AimsAtPrimaryTarget
}

/// A formula the caster's own value reads: `formula` as the row gave it, or `not_finite`
/// when a number is not finite, or `not_read` of the first parameter type an effect on its
/// caster does not read (genesis_prime/game/damage `caster_unread`).
fn caster_formula_read(
  formula formula: Result(damage.Formula, Nil),
  not_finite not_finite: PlanError,
  not_read not_read: fn(Int) -> PlanError,
) -> Result(damage.Formula, PlanError) {
  use formula <- result.try(result.replace_error(formula, not_finite))
  case damage.caster_unread(formula:) {
    Some(damage.Unread(parameter_kind:)) -> Error(not_read(parameter_kind))
    None -> Ok(formula)
  }
}

/// The pool an Absorption row gives (`Spell4Effects.effectType.29`), or the error that
/// fails the load: dataBits00 and dataBits01 must be finite 32-bit floats, the formula
/// must read only the parameter types an effect on its caster reads
/// (genesis_prime/game/damage `caster_unread`), the row must not be periodic (a tickTime)
/// and must have a life (a durationTime or flags bit 2). dataBits04 is the damage types it
/// takes, as a mask, and its targetFlags aim it at the caster when they include it and
/// else at the primary target.
fn absorption_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Absorption, PlanError) {
  use formula <- result.try(
    caster_formula_read(
      formula: damage.absorption_formula_of(effect:),
      not_finite: AbsorptionNumberNotFinite(spell4_id:, effect_id: effect.id),
      not_read: fn(parameter_kind) {
        AbsorptionParameterNotRead(
          spell4_id:,
          effect_id: effect.id,
          parameter_kind:,
        )
      },
    ),
  )
  use Nil <- result.try(case effect.tick_time {
    0 -> Ok(Nil)
    tick_ms ->
      Error(AbsorptionPeriodic(spell4_id:, effect_id: effect.id, tick_ms:))
  })
  use Nil <- result.try(case lasting.has_life(row: lasting_row_of(effect:)) {
    True -> Ok(Nil)
    False -> Error(AbsorptionHasNoLifetime(spell4_id:, effect_id: effect.id))
  })
  use Nil <- result.map(case damage.gives_nothing(formula:) {
    False -> Ok(Nil)
    True -> Error(AbsorptionAmountNotRead(spell4_id:, effect_id: effect.id))
  })
  Absorption(formula:, mask: effect.data_bits04, aim: reached_aim_of(effect:))
}

/// A spell a Proxy starts on each unit its area strikes has that unit as its primary
/// target, so a shield heal, an Interrupt Armor row or an absorb of the spell aimed at it
/// fails the load: none is built on a struck unit. A spell started on the caster, and a row
/// that includes the caster, are read (`place`).
fn not_on_a_struck_unit(
  place place: RowPlace,
  aim aim: Aim,
  refused refused: fn(StruckBy) -> PlanError,
) -> Result(Nil, PlanError) {
  case place.struck_by, aim {
    Some(by), AimsAtPrimaryTarget -> Error(refused(by))
    Some(..), AimsAtCaster
    | Some(..), AimsAtArea
    | Some(..), AimsAtBoth
    | Some(..), OtherAim(..)
    | None, _
    -> Ok(Nil)
  }
}

/// The refusal of a property row on a struck unit: an absorb gives `AbsorptionOnStruckUnit`
/// and an Interrupt Armor row `InterruptArmorOnStruckUnit`.
fn modifier_not_on_a_struck_unit(
  place place: RowPlace,
  modifier modifier: PropertyModifier,
) -> Result(Nil, PlanError) {
  not_on_a_struck_unit(place:, aim: modifier_aim(modifier:), refused: fn(by) {
    let effect_id = modifier.effect_id.value
    case modifier.change {
      AbsorbChange(..) ->
        AbsorptionOnStruckUnit(
          spell4_id: by.spell4_id,
          proxy_effect_id: by.proxy_effect_id,
          effect_id:,
        )
      PropertyChange(..) | LookChange(..) ->
        InterruptArmorOnStruckUnit(
          spell4_id: by.spell4_id,
          proxy_effect_id: by.proxy_effect_id,
          effect_id:,
        )
    }
  })
}

/// A UnitPropertyModifier row's change (`Spell4Effects.effectType.11.change`): dataBits00
/// is the property, which UnitProperty2 must have a row for.
fn change_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(unit_properties.Modifier, PlanError) {
  use property <- result.try(property_of(
    tables:,
    spell4_id:,
    effect:,
    id: effect.data_bits00,
  ))
  use multiplier <- result.try(modifier_number(
    spell4_id:,
    effect:,
    column: "dataBits02",
    bits: effect.data_bits02,
  ))
  use flat <- result.try(modifier_number(
    spell4_id:,
    effect:,
    column: "dataBits03",
    bits: effect.data_bits03,
  ))
  use per_level <- result.try(modifier_number(
    spell4_id:,
    effect:,
    column: "dataBits04",
    bits: effect.data_bits04,
  ))
  Ok(unit_properties.Change(
    property:,
    mode: effect.data_bits01,
    multiplier:,
    flat:,
    per_level:,
  ))
}

/// A UnitPropertyConversion row's change (`Spell4Effects.effectType.145`): property
/// dataBits01 gains the 32-bit float dataBits02, which must be finite, times property
/// dataBits00; UnitProperty2 must have a row for each property.
fn conversion_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(unit_properties.Modifier, PlanError) {
  use from <- result.try(property_of(
    tables:,
    spell4_id:,
    effect:,
    id: effect.data_bits00,
  ))
  use to <- result.try(property_of(
    tables:,
    spell4_id:,
    effect:,
    id: effect.data_bits01,
  ))
  use share <- result.try(modifier_number(
    spell4_id:,
    effect:,
    column: "dataBits02",
    bits: effect.data_bits02,
  ))
  Ok(unit_properties.Conversion(from:, to:, share:))
}

/// The UnitProperty2 id a modifier row names, which the table must have a row for.
fn property_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  id id: Int,
) -> Result(UnitProperty2Id, PlanError) {
  let property = UnitProperty2Id(id)
  unit_property2.get(tables:, id: property)
  |> result.replace(property)
  |> result.replace_error(ModifierPropertyHasNoRow(
    spell4_id:,
    effect_id: effect.id,
    property: id,
  ))
}

/// One ForcedMove row whose targetFlags include the caster (`effect_kind.is_row_read`;
/// `Spell4Effects.effectType.3.player`). Its caster apply prerequisite is read as a Fluff
/// effect's is (`condition_of`).
fn forced_move_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ForcedMove, PlanError) {
  use condition <- result.map(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  ForcedMove(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    delay_ms: effect.delay_time,
    condition:,
    tag: tag_of(effect:),
  )
}

/// One ModifySpellCooldown row whose targetFlags include the caster
/// (`effect_kind.is_row_read`; `Spell4Effects.effectType.73`): dataBits00 picks the
/// spells (0 a Spell4Base, 1 a Spell4, 2 a spell group, 3 a cooldown group, any other
/// value every spell), dataBits01 is the id it compares, dataBits02 the operation and
/// dataBits03 its float, which must be finite where the operation reads it. The id is
/// kept as given and no row is looked up: the client compares it and looks nothing up
/// (`0x14046b920`), so an id no row holds matches nothing on both sides, where a type
/// 80 row's selector must name a row. Its caster apply prerequisite is read as a Fluff
/// effect's is (`condition_of`).
fn cooldown_modifier_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(CooldownModifier, PlanError) {
  use operation <- result.try(cooldown_operation_of(spell4_id:, effect:))
  use condition <- result.map(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  CooldownModifier(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    modifier: cooldown.Modifier(
      selector: case effect.data_bits00 {
        0 -> cooldown.Base(Spell4BaseId(effect.data_bits01))
        1 -> cooldown.Spell(Spell4Id(effect.data_bits01))
        2 -> cooldown.SpellGroup(effect.data_bits01)
        3 -> cooldown.CooldownGroup(effect.data_bits01)
        selector -> cooldown.EverySpell(selector:)
      },
      operation:,
    ),
    row: lasting_row_of(effect:),
    condition:,
    tag: tag_of(effect:),
  )
}

/// One Stealth effect (`Spell4Effects.effectType.83`) as a row, or the error that fails the
/// load. It must aim at the caster alone (`Spell4Effects.targetFlags` 1), have no target
/// apply prerequisite and no delayTime or durationTime; its dataBits02 is whether damage
/// ends it (`Breaks`), and its caster apply prerequisite is read as a Fluff effect's is
/// (`condition_of`). With no durationTime the stealth lasts until it is removed whatever
/// the row's flags say (`Spell4Effects.effectType.83`), so the row's node never ends by
/// time.
fn stealth_row_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(StealthRow, PlanError) {
  use breaks <- result.try(stealth_read(spell4_id:, effect:))
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  Ok(StealthRow(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    breaks:,
    row: lasting.LastingRow(delay_ms: 0, duration_ms: 0, until_removed: True),
    condition:,
    tag: tag_of(effect:),
  ))
}

/// What a Stealth row says without a table: whether damage ends it, or the error that
/// fails the load: it must aim at the caster alone, have no target apply prerequisite
/// and no delayTime or durationTime, and hold a dataBits02 of 0 or 1.
pub fn stealth_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Breaks, PlanError) {
  use Nil <- result.try(stealth_on_the_caster(spell4_id:, effect:))
  use Nil <- result.try(
    case effect.delay_time != 0 || effect.duration_time != 0 {
      True -> Error(StealthTimedNotRead(spell4_id:, effect_id: effect.id))
      False -> Ok(Nil)
    },
  )
  case effect.data_bits02 {
    0 -> Ok(BrokenByDamage)
    1 -> Ok(KeptOnDamage)
    value ->
      Error(StealthBreaksNotRead(spell4_id:, effect_id: effect.id, value:))
  }
}

/// A Stealth or RemoveStealth effect must aim at the caster alone and have no target
/// apply prerequisite, or the load fails (`Spell4Effects.targetFlags`).
pub fn stealth_on_the_caster(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Nil, PlanError) {
  case
    aim_of(target_flags: effect.target_flags),
    effect.prerequisite_id_target_apply
  {
    AimsAtCaster, 0 -> Ok(Nil)
    AimsAtCaster, _ ->
      Error(StealthTargetPrerequisiteNotRead(spell4_id:, effect_id: effect.id))
    AimsAtPrimaryTarget, _ | AimsAtArea, _ | AimsAtBoth, _ | OtherAim(..), _ ->
      Error(StealthAimNotRead(
        spell4_id:,
        effect_id: effect.id,
        target_flags: effect.target_flags,
      ))
  }
}

/// One RemoveStealth effect (`Spell4Effects.effectType.84`) as a row, or the error that fails
/// the load: it must aim at the caster alone and have no target apply prerequisite.
fn remove_stealth_row_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RemoveStealthRow, PlanError) {
  use Nil <- result.try(stealth_on_the_caster(spell4_id:, effect:))
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  Ok(RemoveStealthRow(
    effect_id: Spell4EffectsId(effect.id),
    phase_flags: effect.phase_flags,
    condition:,
    tag: tag_of(effect:),
  ))
}

/// The Proc effects of a spell (`Spell4Effects.effectType.14`) whose kind the server
/// reads, each with its spell planned as a Proxy's child is, on the same chain, so a
/// proc that leads back to a spell on the way fails as a cycle. A row of another kind is
/// in no list; a row of a kind read with a column the plan does not read fails the load
/// (`proc_read`).
fn procs_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
  chain chain: List(Int),
) -> Result(List(ProcRow), PlanError) {
  rows_of_kind(readings:, kind: effect_kind.Proc)
  |> list.try_map(fn(row) {
    let #(effect, reading) = row
    use reading <- result.try(reading)
    case reading {
      Applied(PlannedProc(reading: proc, condition:))
      | Held(PlannedProc(reading: proc, condition:)) -> {
        use spell <- result.try(spell_of(
          tables:,
          sources:,
          spell4_id: effect.data_bits01,
          chain:,
          threshold_costs: [],
          struck_by: None,
        ))
        Ok([
          ProcRow(
            effect_id: Spell4EffectsId(effect.id),
            phase_flags: effect.phase_flags,
            trigger: proc.trigger,
            spell:,
            window_ms: proc.window_ms,
            count: proc.count,
            row: lasting_row_of(effect:),
            condition:,
            tag: tag_of(effect:),
          ),
        ])
      }
      Applied(..) | Held(..) | LeftOut(..) | ReadByArea -> Ok([])
    }
  })
  |> result.map(list.flatten)
}

/// 1.0 as the 32 float bits a Proc row's chance column (dataBits02) holds.
const chance_of_one_bits = 1_065_353_216

/// What a Proc row says without a table: its trigger and its limit, or why it is not
/// read. A row of a kind the server does not read is `ProcKindNotRead`, which the load
/// skips; any other error fails the load, naming the first column the plan does not read:
/// targetFlags other than the caster, a chance other than 1.0 (no roll is drawn), a unit
/// bit of the event's other unit (4) or beyond the five the texts name, a window or count
/// that is not above 0, a gate, a filter, a target apply or persistence prerequisite and
/// a delay, and a row with no durationTime and no flags bit 2, which gives its holder's
/// node no life (`Spell4Effects.effectType.14.dataBits03`, `.limits`, `.prerequisites`,
/// `.dataBits07`, `.lifetime`).
pub fn proc_read(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ProcReading, PlanError) {
  use trigger <- result.try(case effect.data_bits00 {
    217 -> Ok(EnteredStealth)
    218 -> Ok(LeftStealth)
    44 -> Ok(LeftCombat)
    0 -> Ok(Died)
    kind -> Error(ProcKindNotRead(spell4_id:, effect_id: effect.id, kind:))
  })
  let unit_bits = effect.data_bits03
  let refusals = [
    #("targetFlags", effect.target_flags, effect.target_flags != 1),
    #(
      "dataBits02",
      effect.data_bits02,
      effect.data_bits02 != chance_of_one_bits,
    ),
    #(
      "dataBits03",
      unit_bits,
      int.bitwise_and(unit_bits, 4) != 0 || unit_bits >= 32 || unit_bits < 0,
    ),
    #("dataBits04", effect.data_bits04, effect.data_bits04 <= 0),
    #("dataBits05", effect.data_bits05, effect.data_bits05 <= 0),
    #("dataBits06", effect.data_bits06, effect.data_bits06 != 0),
    #("dataBits07", effect.data_bits07, effect.data_bits07 != 0),
    #("dataBits08", effect.data_bits08, effect.data_bits08 != 0),
    #("dataBits09", effect.data_bits09, effect.data_bits09 != 0),
    #(
      "prerequisiteIdTargetApply",
      effect.prerequisite_id_target_apply,
      effect.prerequisite_id_target_apply != 0,
    ),
    #(
      "prerequisiteIdCasterPersistence",
      effect.prerequisite_id_caster_persistence,
      effect.prerequisite_id_caster_persistence != 0,
    ),
    #(
      "prerequisiteIdTargetPersistence",
      effect.prerequisite_id_target_persistence,
      effect.prerequisite_id_target_persistence != 0,
    ),
    #("delayTime", effect.delay_time, effect.delay_time != 0),
    #(
      "flags",
      effect.flags,
      effect.duration_time <= 0 && !has_flag(flags: effect.flags, bit: 2),
    ),
  ]
  case list.find(refusals, fn(refusal) { refusal.2 }) {
    Ok(#(column, value, _)) ->
      Error(ProcNotRead(spell4_id:, effect_id: effect.id, column:, value:))
    Error(Nil) ->
      Ok(ProcReading(
        trigger:,
        window_ms: effect.data_bits04,
        count: effect.data_bits05,
      ))
  }
}

/// The Spell4 ids among `effects` that a Proxy starts as a child on each struck unit: a
/// Proxy aimed at the area, or at the area and the primary target (`target_of`), each with
/// the first such Proxy in `effects` order.
pub fn struck_unit_children(
  effects effects: List(spell4_effects.Spell4Effects),
) -> Dict(Int, StruckBy) {
  list.fold(effects, dict.new(), fn(found, effect) {
    case
      effect_kind.kind_of(effect.effect_type) == effect_kind.Proxy
      && effect.data_bits00 != 0
    {
      True ->
        case aim_of(target_flags: effect.target_flags) {
          AimsAtArea | AimsAtBoth ->
            case dict.has_key(found, effect.data_bits00) {
              True -> found
              False ->
                dict.insert(
                  found,
                  effect.data_bits00,
                  StruckBy(
                    spell4_id: effect.spell_id,
                    proxy_effect_id: effect.id,
                  ),
                )
            }
          AimsAtCaster | AimsAtPrimaryTarget | OtherAim(..) -> found
        }
      False -> found
    }
  })
}

/// Whether a spell with these innate costs spends every point held, which gives each of
/// its effect rows a tag the rule must read (`spend_tag_read`).
fn spends_all_of(costs costs: List(Cost)) -> Bool {
  list.any(costs, fn(cost) {
    case cost {
      SpendAllCost(..) -> True
      SlotCost(..)
      | ClassVitalCost(..)
      | UnheldCost(..)
      | UnreadSpendCost(..) -> False
    }
  })
}

/// Whether the Spell4 row spends every point held, by its two innate costs, as the plan of
/// the spell reads them; false when a cost or its class row is not one the plan reads, since
/// that spell fails its own plan. A stage's threshold costs carry no EMM id, so they never
/// make a spell spend every point.
pub fn spends_all(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Bool {
  case
    spell4_base.get(tables:, id: Spell4BaseId(row.spell4_base_id_base_spell))
  {
    Error(Nil) -> False
    Ok(base) ->
      case
        costs_of(tables:, row:, base:, costs: [
          #(row.innate_cost_type0, row.innate_cost0, row.innate_cost_emm_id0),
          #(row.innate_cost_type1, row.innate_cost1, row.innate_cost_emm_id1),
        ])
      {
        Ok(costs) -> spends_all_of(costs:)
        Error(..) -> False
      }
  }
}

/// Plans one spell on its own, as a pressed ability, and every spell below it, or why it
/// cannot be planned: the plan's load of a spell, whichever Spell4 row names it. `chain`
/// holds the Spell4 ids from the pressed ability to the spell that casts it, none for a
/// spell planned as an ability, so a tree that leads back to one of them fails as a
/// `ProxyCycle` (genesis_prime/game/server_proxy).
pub fn spell_alone(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  chain chain: List(Int),
) -> Result(Spell, PlanError) {
  spell_of(
    tables:,
    sources:,
    spell4_id:,
    chain:,
    threshold_costs: [],
    struck_by: None,
  )
}

/// A row's reading or the error that fails the load of its spell.
type Reading =
  Result(RowReading, PlanError)

/// The readings of the rows of these kinds, in row order.
fn rows_of_kind(
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
  kind kind: effect_kind.Kind,
) -> List(#(spell4_effects.Spell4Effects, Reading)) {
  list.filter(readings, fn(row) {
    effect_kind.kind_of({ row.0 }.effect_type) == kind
  })
}

/// Whether no row of these kinds is refused: the first error among their readings, in
/// row order.
fn rows_read(
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
  kinds kinds: List(effect_kind.Kind),
) -> Result(Nil, PlanError) {
  list.try_each(readings, fn(row) {
    case list.contains(kinds, effect_kind.kind_of({ row.0 }.effect_type)) {
      True -> result.replace(row.1, Nil)
      False -> Ok(Nil)
    }
  })
}

/// The rows of a spell's lists, in row order, taken from the readings of its effects.
type RowLists {
  RowLists(
    gains: List(Gain),
    lasting: List(Lasting),
    removes: List(ForceRemove),
    controls: List(CrowdControl),
    modifiers: List(PropertyModifier),
    armors: List(PropertyModifier),
    forced_moves: List(ForcedMove),
    cooldown_modifiers: List(CooldownModifier),
    stealth: List(StealthRow),
    remove_stealth: List(RemoveStealthRow),
    shield_heals: List(ShieldHeal),
  )
}

/// Each row an `Applied` or `Held` reading holds, in the list of its kind. A Proxy's and a
/// Proc's row are made by the spell itself, which plans the spell each names.
fn lists_of(
  readings readings: List(#(spell4_effects.Spell4Effects, Reading)),
) -> RowLists {
  let empty = RowLists([], [], [], [], [], [], [], [], [], [], [])
  let lists =
    list.fold(readings, empty, fn(lists, row) {
      case row.1 {
        Ok(Applied(planned)) | Ok(Held(planned)) ->
          case planned {
            PlannedGain(gain:) ->
              RowLists(..lists, gains: [gain, ..lists.gains])
            PlannedLasting(lasting:) ->
              RowLists(..lists, lasting: [lasting, ..lists.lasting])
            PlannedRemove(remove:) ->
              RowLists(..lists, removes: [remove, ..lists.removes])
            PlannedControl(control:) ->
              RowLists(..lists, controls: [control, ..lists.controls])
            PlannedModifier(modifier:) ->
              case modifier.armor {
                Some(..) ->
                  RowLists(..lists, armors: [modifier, ..lists.armors])
                None ->
                  RowLists(..lists, modifiers: [modifier, ..lists.modifiers])
              }
            PlannedForcedMove(forced_move:) ->
              RowLists(..lists, forced_moves: [
                forced_move,
                ..lists.forced_moves
              ])
            PlannedCooldownModifier(modifier:) ->
              RowLists(..lists, cooldown_modifiers: [
                modifier,
                ..lists.cooldown_modifiers
              ])
            PlannedStealth(stealth:) ->
              RowLists(..lists, stealth: [stealth, ..lists.stealth])
            PlannedRemoveStealth(remove:) ->
              RowLists(..lists, remove_stealth: [remove, ..lists.remove_stealth])
            PlannedShieldHeal(heal:) ->
              RowLists(..lists, shield_heals: [heal, ..lists.shield_heals])
            PlannedProc(..) | PlannedProxy(..) -> lists
          }
        Ok(LeftOut(..)) | Ok(ReadByArea) | Error(..) -> lists
      }
    })
  RowLists(
    gains: list.reverse(lists.gains),
    lasting: list.reverse(lists.lasting),
    removes: list.reverse(lists.removes),
    controls: list.reverse(lists.controls),
    modifiers: list.reverse(lists.modifiers),
    armors: list.reverse(lists.armors),
    forced_moves: list.reverse(lists.forced_moves),
    cooldown_modifiers: list.reverse(lists.cooldown_modifiers),
    stealth: list.reverse(lists.stealth),
    remove_stealth: list.reverse(lists.remove_stealth),
    shield_heals: list.reverse(lists.shield_heals),
  )
}

/// An effect of a spell that spends every point held must hold an emmComparison the rule
/// reads (0 or 1), since each effect's tag chooses by the points spent; a spell with no
/// such cost chooses nothing and its tags are not looked at.
fn spend_tag_read(
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Nil, PlanError) {
  use <- bool.guard(
    when: !place.spends_all || spend.tag_is_read(tag_of(effect:)),
    return: Ok(Nil),
  )
  Error(SpendComparisonNotRead(
    spell4_id: effect.spell_id,
    effect_id: effect.id,
    comparison: effect.emm_comparison,
  ))
}

/// The row as `Held` when its condition is behind a target apply prerequisite, which no go
/// applies (`cast.condition_gate`), and else `Applied`.
fn by_condition(
  row row: PlannedRow,
  condition condition: Condition,
) -> RowReading {
  case condition {
    GatedOnTarget(..) -> Held(row)
    Always | GatedOnCaster(..) | GatedOnCasterAndTarget(..) -> Applied(row)
  }
}

/// What the plan makes of one Spell4Effects row, in the place its spell is planned: the
/// one decision the plan's lists are made from and the coverage measure counts by.
///
/// - `Applied` and `Held` rows are in a list of their spell (`Held`: no go applies them,
///   among them a row with no life or with phaseFlags 0), `LeftOut` rows are in none and
///   the load goes on, and a damage row is `ReadByArea`.
/// - An error is what fails the load of the row's spell: a row the tables lack, a column
///   the plan does not read, a spell that spends every point with a tag the rule does not
///   read, or a heal, armor or absorb on the primary target of a spell a Proxy starts on
///   each struck unit (`place`).
/// - Each row is read by the rule of its type: `gain_row_of`, `lasting_of`, `remove_of`,
///   `control_of`, `modifier_of`, `interrupt_armor_of`, `forced_move_of`,
///   `cooldown_modifier_of`, `stealth_row_of`, `remove_stealth_row_of`, `shield_heal_of`,
///   `proc_read`, and for a Proxy `target_of` and `proxy_condition_of`.
///
/// A Proxy's child and a Proc's spell are planned by the spell that holds the row; a
/// refused child is counted on the child's own rows.
pub fn read_row(
  tables tables: table_store.Tables,
  spell_groups spell_groups: Set(Int),
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  use Nil <- result.try(spend_tag_read(place:, effect:))
  use reading <- result.map(kind_reading(
    tables:,
    spell_groups:,
    place:,
    effect:,
  ))
  held_without_a_phase(reading:, effect:)
}

/// A row whose phaseFlags is 0 is selected by no phase, so no go applies it
/// (`in_phase`): an `Applied` row is `Held`, and a damage row is left out. What the client
/// means by phaseFlags 0 is not known.
fn held_without_a_phase(
  reading reading: RowReading,
  effect effect: spell4_effects.Spell4Effects,
) -> RowReading {
  use <- bool.guard(when: effect.phase_flags != 0, return: reading)
  case reading {
    Applied(row) -> Held(row)
    ReadByArea -> LeftOut(why: InNoPhase)
    Held(..) | LeftOut(..) -> reading
  }
}

/// What the rule of the row's type makes of it, before the phases are looked at.
fn kind_reading(
  tables tables: table_store.Tables,
  spell_groups spell_groups: Set(Int),
  place place: RowPlace,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  let spell4_id = effect.spell_id
  let reaches =
    effect_kind.is_row_read(
      effect_type: effect.effect_type,
      target_flags: effect.target_flags,
    )
  case effect_kind.kind_of(effect.effect_type) {
    effect_kind.VitalModifier ->
      gain_row_of(tables:, spell4_id:, effect:)
      |> result.map(fn(gain) {
        case gain {
          Gain(..) -> Applied(PlannedGain(gain:))
          TickingGain(..) -> Held(PlannedGain(gain:))
        }
      })
    effect_kind.Fluff | effect_kind.Scale | effect_kind.RavelSignal ->
      lasting_reading(tables:, spell4_id:, effect:)
    effect_kind.ShieldOverload -> {
      use <- when_reached(reaches:)
      lasting_reading(tables:, spell4_id:, effect:)
    }
    effect_kind.ForceRemove ->
      remove_of(tables:, spell_groups:, spell4_id:, effect:)
      |> result.map(fn(remove) {
        by_condition(row: PlannedRemove(remove:), condition: remove.condition)
      })
    effect_kind.CrowdControl ->
      control_of(spell4_id:, effect:)
      |> result.map(fn(control) { Applied(PlannedControl(control:)) })
    effect_kind.PropertyModifier
    | effect_kind.PropertyConversion
    | effect_kind.DisguiseOutfit
    | effect_kind.Absorption -> {
      use <- when_reached(reaches:)
      modifier_reading(tables:, place:, spell4_id:, effect:)
    }
    effect_kind.InterruptArmor -> {
      use <- when_reached(reaches:)
      interrupt_armor_reading(tables:, place:, spell4_id:, effect:)
    }
    effect_kind.ForcedMove -> {
      use <- when_reached(reaches:)
      forced_move_of(tables:, effect:)
      |> result.map(fn(forced_move) {
        by_condition(
          row: PlannedForcedMove(forced_move:),
          condition: forced_move.condition,
        )
      })
    }
    effect_kind.CooldownModifier -> {
      use <- when_reached(reaches:)
      cooldown_modifier_of(tables:, spell4_id:, effect:)
      |> result.map(fn(modifier) {
        by_condition(
          row: PlannedCooldownModifier(modifier:),
          condition: modifier.condition,
        )
      })
    }
    effect_kind.Stealth ->
      stealth_row_of(tables:, spell4_id:, effect:)
      |> result.map(fn(stealth) {
        by_condition(
          row: PlannedStealth(stealth:),
          condition: stealth.condition,
        )
      })
    effect_kind.RemoveStealth ->
      remove_stealth_row_of(tables:, spell4_id:, effect:)
      |> result.map(fn(remove) {
        by_condition(
          row: PlannedRemoveStealth(remove:),
          condition: remove.condition,
        )
      })
    effect_kind.ShieldHeal -> {
      use <- when_reached(reaches:)
      shield_heal_reading(tables:, place:, spell4_id:, effect:)
    }
    effect_kind.Proc -> proc_reading(tables:, spell4_id:, effect:)
    effect_kind.Proxy ->
      case effect.data_bits00 {
        0 -> Ok(LeftOut(why: ProxyNamesNoSpell))
        _ -> {
          use target <- result.try(target_of(spell4_id:, effect:))
          use condition <- result.map(proxy_condition_of(tables:, effect:))
          Applied(PlannedProxy(target:, condition:))
        }
      }
    effect_kind.Damage -> Ok(ReadByArea)
    effect_kind.Unread(..) -> Ok(LeftOut(why: TypeNotRead))
  }
}

/// The row as `LeftOut` when its targetFlags do not reach a unit the type is read for
/// (`effect_kind.is_row_read`), and else what `then` makes of it.
fn when_reached(
  reaches reaches: Bool,
  then then: fn() -> Result(RowReading, PlanError),
) -> Result(RowReading, PlanError) {
  use <- bool.guard(when: !reaches, return: Ok(LeftOut(why: AimedAtOtherUnits)))
  then()
}

/// A Fluff, Scale, RavelSignal or area ShieldOverload row as a lasting row.
fn lasting_reading(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  lasting_of(tables:, spell4_id:, effect:)
  |> result.map(fn(lasting) {
    by_condition(row: PlannedLasting(lasting:), condition: lasting.condition)
  })
}

/// A UnitPropertyModifier, UnitPropertyConversion, DisguiseOutfit or Absorption row that
/// reaches the caster: held when it stands behind a target apply prerequisite or, for a
/// disguise, has no life, which no go applies (`lasting.has_life`).
fn modifier_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  use modifier <- result.try(modifier_of(
    tables:,
    spell4_id:,
    effect:,
    condition:,
  ))
  use Nil <- result.map(modifier_not_on_a_struck_unit(place:, modifier:))
  by_condition_with_life(modifier:, condition:)
}

/// A property row as `Held` when it has no life (`lasting.has_life`), which the cast rule
/// drops, and else by its condition.
fn by_condition_with_life(
  modifier modifier: PropertyModifier,
  condition condition: Condition,
) -> RowReading {
  let planned = PlannedModifier(modifier:)
  case lasting.has_life(row: modifier.row) {
    True -> by_condition(row: planned, condition:)
    False -> Held(planned)
  }
}

/// A ModifyInterruptArmor row that reaches the caster or the primary target.
fn interrupt_armor_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  use modifier <- result.try(interrupt_armor_of(spell4_id:, effect:, condition:))
  use Nil <- result.map(modifier_not_on_a_struck_unit(place:, modifier:))
  by_condition_with_life(modifier:, condition:)
}

/// A HealShields row that reaches the caster or the primary target: a periodic heal is
/// held.
fn shield_heal_reading(
  tables tables: table_store.Tables,
  place place: RowPlace,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  use condition <- result.try(condition_of(
    tables:,
    effect:,
    data_bits06_names_a_gate: False,
  ))
  use heal <- result.try(shield_heal_of(spell4_id:, effect:, condition:))
  use Nil <- result.map(
    not_on_a_struck_unit(place:, aim: heal.aim, refused: fn(by) {
      ShieldHealOnStruckUnit(
        spell4_id: by.spell4_id,
        proxy_effect_id: by.proxy_effect_id,
        effect_id: effect.id,
      )
    }),
  )
  case heal {
    ShieldHeal(..) -> by_condition(row: PlannedShieldHeal(heal:), condition:)
    TickingShieldHeal(..) -> Held(PlannedShieldHeal(heal:))
  }
}

/// A Proc row: left out when its kind is one the holder's own events do not make
/// (`proc_read`), else its reading with its caster condition.
fn proc_reading(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(RowReading, PlanError) {
  case proc_read(spell4_id:, effect:) {
    Error(ProcKindNotRead(kind:, ..)) ->
      Ok(LeftOut(why: ProcOfAnotherKind(kind:)))
    Error(error) -> Error(error)
    Ok(reading) -> {
      use condition <- result.map(condition_of(
        tables:,
        effect:,
        data_bits06_names_a_gate: False,
      ))
      Applied(PlannedProc(reading:, condition:))
    }
  }
}

/// What the spell does to the caster's stealth, from the spell's spellCastStealthChange:
/// 0 is `EndsStealthAtEachGo`, 1 is `EndsStealthAfterLastGo`, 2 is `KeepsStealth`, and
/// any other value fails the load (`Spell4.spellCastStealthChange`).
pub fn stealth_change_of(
  spell4_id spell4_id: Int,
  value value: Int,
) -> Result(StealthChange, PlanError) {
  case value {
    0 -> Ok(EndsStealthAtEachGo)
    1 -> Ok(EndsStealthAfterLastGo)
    2 -> Ok(KeepsStealth)
    value -> Error(StealthChangeNotRead(spell4_id:, value:))
  }
}

/// A spell whose caster or target Spell4Conditions row tests stealth (mask bit 16) fails
/// the load: the client refuses such a cast with 65 or 114, and the server does not
/// check those results (`Spell4Conditions.conditionMask.16`). The place for the check,
/// when a spell needs it, is `cast.verdict` after the dead test.
pub fn stealth_conditions_read(
  spell4_id spell4_id: Int,
  conditions conditions: List(Option(spell4_conditions.Spell4Conditions)),
) -> Result(Nil, PlanError) {
  list.try_each(conditions, fn(conditions) {
    case conditions {
      Some(condition) ->
        case has_flag(flags: condition.condition_mask, bit: 16) {
          True ->
            Error(StealthConditionNotRead(
              spell4_id:,
              spell4_conditions_id: condition.id,
            ))
          False -> Ok(Nil)
        }
      None -> Ok(Nil)
    }
  })
}

/// A cooldown effect's operation (dataBits02) with its float (dataBits03): the 32-bit
/// float its column holds, which must be finite. An operation the client has no case for
/// reads no float (`0x14046b920`).
fn cooldown_operation_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(cooldown.Operation, PlanError) {
  let number = fn() {
    float32.of_column(number: effect.data_bits03)
    |> result.replace_error(CooldownNumberNotFinite(
      spell4_id:,
      effect_id: effect.id,
    ))
  }
  case effect.data_bits02 {
    0 -> result.map(number(), cooldown.NoLonger)
    1 -> result.map(number(), cooldown.Multiply)
    2 -> result.map(number(), cooldown.AddMs)
    3 -> result.map(number(), cooldown.SetMs)
    operation -> Ok(cooldown.Unchanged(operation:))
  }
}

/// The cooldown groups of a spell: the non-zero of spellCoolDownId00 to 02, each of
/// which must be a SpellCoolDown row, as the client's StartSpellCooldowns reports an
/// error for a group it finds none for (`0x14046b1e0`).
fn cooldown_groups_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(List(Int), PlanError) {
  [row.spell_cool_down_id00, row.spell_cool_down_id01, row.spell_cool_down_id02]
  |> list.filter(fn(group) { group != 0 })
  |> list.try_map(fn(group) {
    spell_cool_down.get(tables:, id: SpellCoolDownId(group))
    |> result.replace_error(NoRow(table: "SpellCoolDown", id: group))
    |> result.replace(group)
  })
}

/// A modifier row's multiplier, flat amount or per-level amount: the 32-bit float its
/// column holds (`float32.of_column`), which must be finite.
fn modifier_number(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
  column column: String,
  bits bits: Int,
) -> Result(Float, PlanError) {
  float32.of_column(number: bits)
  |> result.replace_error(ModifierNumberNotFinite(
    spell4_id:,
    effect_id: effect.id,
    column:,
  ))
}

/// The aim of a Fluff, SpellForceRemove, Scale or RavelSignal effect: the caster, the
/// primary target, the area or both of those; any other flag value fails the load.
fn lasting_aim_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Aim, PlanError) {
  case aim_of(target_flags: effect.target_flags) {
    OtherAim(flags:) ->
      Error(LastingAimNotRead(
        spell4_id:,
        effect_id: effect.id,
        target_flags: flags,
      ))
    AimsAtCaster -> Ok(AimsAtCaster)
    AimsAtPrimaryTarget -> Ok(AimsAtPrimaryTarget)
    AimsAtArea -> Ok(AimsAtArea)
    AimsAtBoth -> Ok(AimsAtBoth)
  }
}

/// The selector of a type 80 row, whose dataBits01 must name a spell group (one that
/// some Spell4GroupList row holds), a Spell4 or a Spell4Base the tables have.
fn selector_of(
  tables tables: table_store.Tables,
  spell_groups spell_groups: Set(Int),
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(lasting.Selector, PlanError) {
  let named = effect.data_bits01
  case effect.data_bits00 {
    1 ->
      case set.contains(spell_groups, named) {
        True -> Ok(lasting.Group(spell_group_id: named))
        False -> Error(NoRow(table: "Spell4GroupList", id: named))
      }
    2 ->
      spell4.get(tables:, id: Spell4Id(named))
      |> result.replace(lasting.Spell(spell4_id: Spell4Id(named)))
      |> result.replace_error(NoRow(table: "Spell4", id: named))
    3 ->
      spell4_base.get(tables:, id: Spell4BaseId(named))
      |> result.replace(lasting.Base(spell4_base_id: Spell4BaseId(named)))
      |> result.replace_error(NoRow(table: "Spell4Base", id: named))
    selector ->
      Error(ForceRemoveSelectorNotRead(
        spell4_id:,
        effect_id: effect.id,
        selector:,
      ))
  }
}

/// The spell groups of a spell: the group ids of its Spell4GroupList row, none for
/// the id 0; a row the tables lack fails the load.
fn groups_of(
  sources sources: Sources,
  row row: spell4.Spell4,
) -> Result(List(Int), PlanError) {
  case row.spell4_group_list_id {
    0 -> Ok([])
    list_id ->
      dict.get(sources.group_lists, list_id)
      |> result.replace_error(NoRow(table: "Spell4GroupList", id: list_id))
  }
}

/// The spell's stack group and its cap (Spell4StackGroup.stackCap): no group, cap 0
/// for the id 0; a row the tables lack fails the load.
fn stack_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(lasting.Stack, PlanError) {
  case row.spell4_stack_group_id {
    0 -> Ok(lasting.Stack(group_id: 0, cap: 0))
    group_id ->
      spell4_stack_group.get(tables:, id: Spell4StackGroupId(group_id))
      |> result.map(fn(group) { lasting.Stack(group_id:, cap: group.stack_cap) })
      |> result.replace_error(NoRow(table: "Spell4StackGroup", id: group_id))
  }
}

/// The tag an effect row holds on the points a cast spent: its emmComparison and
/// emmValue (`Spell4Effects.emmComparison`).
pub fn tag_of(effect effect: spell4_effects.Spell4Effects) -> spend.Tag {
  spend.tag_of(comparison: effect.emm_comparison, value: effect.emm_value)
}

/// The resource slot of a gain's vital: 6 (Resource1) is slot 1 and 8 (Resource3)
/// slot 3, the innate cost types' numbering (`Spell4Effects.effectType.1`); the
/// kit holds no other.
fn gain_slot_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Int, PlanError) {
  case effect.data_bits00 {
    6 | 8 -> Ok(effect.data_bits00 - 5)
    vital -> Error(GainVitalNotRead(spell4_id:, effect_id: effect.id, vital:))
  }
}

/// The rows that apply in phase `phase`: bit n of their `phase_flags` is phase n (every
/// bit for -1), and their tag holds for the points the cast spent
/// (genesis_prime/game/spend `applies`).
fn in_phase(
  rows rows: List(row),
  phase_flags phase_flags: fn(row) -> Int,
  tag tag: fn(row) -> spend.Tag,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(row) {
  list.filter(rows, fn(row) {
    has_flag(flags: phase_flags(row), bit: phase_bit(phase:))
    && spend.applies(tag: tag(row), spent:)
  })
}

/// The gains of the spell given at its go of phase `phase`, those whose tag holds
/// for the points the cast spent (genesis_prime/game/spend `applies`).
pub fn gains_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(Gain) {
  in_phase(
    rows: spell.gains,
    phase_flags: fn(gain) { gain.phase_flags },
    tag: fn(gain) { gain.tag },
    phase:,
    spent:,
  )
}

/// Whether the client shows a cast bar for the spell, by its method
/// (`cast.current_cast`, `SpellShowsCastBar`).
fn cast_bar_of(
  method method: CastMethod,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
) -> CastBar {
  let has_bar = base.cast_bar_type != 0
  let has_time = row.cast_time != 0
  case method {
    Normal | OtherMethod(10) -> bar_if(shows: has_bar && has_time)
    Multiphase -> bar_if(shows: has_bar || has_time)
    Channeled ->
      case has_bar {
        True -> ShowsCastBar
        False -> ShowsWhenPressed
      }
    PressHold -> ShowsCastBar
    ChanneledField | Transactional -> HidesCastBar
    ChargeRelease -> bar_if(shows: row.threshold_time != 0 || has_time)
    ClientSideInteraction | RapidTap | OtherMethod(..) ->
      bar_if(shows: has_time)
  }
}

fn bar_if(shows shows: Bool) -> CastBar {
  use <- bool.guard(when: shows, return: ShowsCastBar)
  HidesCastBar
}

/// Whether the client shows a cast bar for a cast of the spell, which makes it
/// the caster's current cast from its start (`cast.current_cast`): `pressed` is
/// whether the cast's root is the spell itself.
pub fn shows_cast_bar(spell spell: Spell, pressed pressed: Bool) -> Bool {
  case spell.cast_bar {
    ShowsCastBar -> True
    HidesCastBar -> False
    ShowsWhenPressed -> pressed
  }
}

/// Where the spell's own cooldown starts (`0x14053e5a0`): a Multiphase spell with a
/// phase of the flag 0x200 at its last phase, a channel at its last pulse, a
/// RapidTap, ChargeRelease or PressHold spell at no go.
fn cooldown_start_of(
  method method: CastMethod,
  phases phases: List(Phase),
) -> CooldownStart {
  case method {
    Multiphase ->
      case
        list.any(phases, fn(phase) {
          has_flag(flags: phase.flags, bit: cooldown_at_last_phase_flag)
        })
      {
        True -> AtLastGo
        False -> AtFirstGo
      }
    Channeled -> AtLastGo
    RapidTap | ChargeRelease | PressHold -> NotAtAGo
    Normal
    | ChanneledField
    | ClientSideInteraction
    | Transactional
    | OtherMethod(..) -> AtFirstGo
  }
}

/// The first phase of a Multiphase spell that moves its cooldown to the end
/// (`0x14053e5a0`).
fn cooldown_phase_of(
  method method: CastMethod,
  phases phases: List(Phase),
) -> Option(Int) {
  case method {
    Multiphase ->
      list.index_map(phases, fn(phase, index) { #(index, phase) })
      |> list.find(fn(pair) {
        has_flag(flags: { pair.1 }.flags, bit: cooldown_at_last_phase_flag)
      })
      |> result.map(fn(pair) { pair.0 })
      |> option.from_result
    Normal
    | Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | RapidTap
    | ChargeRelease
    | Transactional
    | OtherMethod(..) -> None
  }
}

/// The phase delays of a spell: a Multiphase spell's SpellPhase rows the client
/// keeps, which it must have, and none for any other method.
fn phase_delays(
  phases phases: List(Phase),
  method method: CastMethod,
  spell4_id spell4_id: Int,
) -> Result(List(Int), PlanError) {
  case method {
    Multiphase ->
      case phases {
        [_, ..] -> Ok(list.map(phases, fn(phase) { phase.delay_ms }))
        [] -> Error(NoRow(table: "SpellPhase", id: spell4_id))
      }
    Normal
    | Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | RapidTap
    | ChargeRelease
    | Transactional
    | OtherMethod(..) -> Ok([])
  }
}

/// The channel of a Channeled spell: its pulse time must give a count of pulses.
fn channel_of(
  row row: spell4.Spell4,
  method method: CastMethod,
) -> Result(Option(Channel), PlanError) {
  case method {
    Channeled ->
      case row.channel_pulse_time > 0 {
        True ->
          Ok(
            Some(Channel(
              initial_delay_ms: row.channel_initial_delay,
              max_time_ms: row.channel_max_time,
              pulse_time_ms: row.channel_pulse_time,
            )),
          )
        False -> Error(ChannelWithoutPulse(spell4_id: row.id))
      }
    Normal
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | RapidTap
    | ChargeRelease
    | Multiphase
    | Transactional
    | OtherMethod(..) -> Ok(None)
  }
}

fn method_of(cast_method: Int) -> CastMethod {
  case cast_method {
    0 -> Normal
    1 -> Channeled
    2 -> PressHold
    3 -> ChanneledField
    5 -> ClientSideInteraction
    6 -> RapidTap
    7 -> ChargeRelease
    8 -> Multiphase
    9 -> Transactional
    other -> OtherMethod(id: other)
  }
}

fn weapon_of(weapon_slot: Int) -> WeaponSlot {
  case weapon_slot {
    0 -> NoWeaponNeeded
    1 -> PrimaryWeapon
    2 -> Refused
    other -> OtherWeaponSlot(id: other)
  }
}

/// A Proxy aimed at the area (`aim_of`: 4 or 6) starts its child on each struck unit,
/// one aimed at the caster or the primary target on the caster
/// (`Spell4Effects.targetFlags`); another value is refused.
fn target_of(
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(ProxyTarget, PlanError) {
  case aim_of(target_flags: effect.target_flags) {
    AimsAtArea | AimsAtBoth -> Ok(OnEachStruck)
    AimsAtCaster | AimsAtPrimaryTarget -> Ok(OnCaster)
    OtherAim(flags:) ->
      Error(ProxyAimNotRead(
        spell4_id:,
        effect_id: effect.id,
        target_flags: flags,
      ))
  }
}

/// An effect's condition: a target apply prerequisite, which the server does not
/// check, else its caster apply prerequisite and, for a Proxy (`names_a_gate`), the one
/// its dataBits06 names (`Spell4Effects.effectType.26.dataBits06`: a reading of the
/// rows, since the client applies no Proxy itself), checked against the caster. The
/// dataBits06 of a Fluff or SpellForceRemove effect is no prerequisite. A prerequisite
/// the table lacks fails the load.
fn condition_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
  data_bits06_names_a_gate names_a_gate: Bool,
) -> Result(Condition, PlanError) {
  case effect.prerequisite_id_target_apply {
    0 -> {
      use gates <- result.try(caster_gates_of(
        tables:,
        effect:,
        data_bits06_names_a_gate: names_a_gate,
      ))
      Ok(case gates {
        [] -> Always
        [_, ..] -> GatedOnCaster(gates:)
      })
    }
    target -> Ok(GatedOnTarget(prerequisite_id: PrerequisiteId(target)))
  }
}

/// A Proxy's condition: its caster gates as `condition_of` reads them and, behind a target
/// apply prerequisite, that prerequisite decoded too, which the cast rule checks against
/// each unit the child is made on (`GatedOnCasterAndTarget`).
fn proxy_condition_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Condition, PlanError) {
  case effect.prerequisite_id_target_apply {
    0 -> condition_of(tables:, effect:, data_bits06_names_a_gate: True)
    target -> {
      use caster <- result.try(caster_gates_of(
        tables:,
        effect:,
        data_bits06_names_a_gate: True,
      ))
      use target <- result.try(prerequisite_of(tables:, id: target))
      Ok(GatedOnCasterAndTarget(caster:, target:))
    }
  }
}

/// The prerequisites a row is gated on against the caster: its caster apply prerequisite
/// and, for a Proxy, the one its dataBits06 names, in that order.
fn caster_gates_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
  data_bits06_names_a_gate names_a_gate: Bool,
) -> Result(List(Prerequisite), PlanError) {
  [
    effect.prerequisite_id_caster_apply,
    ..case names_a_gate {
      True -> [effect.data_bits06]
      False -> []
    }
  ]
  |> list.filter(fn(id) { id != 0 })
  |> list.try_map(fn(id) { prerequisite_of(tables:, id:) })
}

/// The Prerequisite row with this id as the client keeps it.
fn prerequisite_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Prerequisite, PlanError) {
  prerequisite_in(
    rows: prerequisite.table_rows(tables:),
    arcs: prerequisite.table_arcs(tables:),
    id:,
  )
}

/// The Prerequisite with this id, nested rows loaded, from the rows given: a row
/// the rows lack and a cycle fail the load.
fn prerequisite_in(
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
  id id: Int,
) -> Result(Prerequisite, PlanError) {
  prerequisite.load(id: PrerequisiteId(id), rows:, arcs:)
  |> result.map_error(fn(error) {
    case error {
      prerequisite.NoPrerequisiteRow(id: missing) ->
        NoRow(table: "Prerequisite", id: missing.value)
      prerequisite.PrerequisiteCycle(path:) ->
        PrerequisiteCycle(
          path: list.map(path, fn(on_the_way) { on_the_way.value }),
        )
      prerequisite.NoPositionalRequirementRow(id: missing) ->
        NoRow(table: "PositionalRequirement", id: missing)
    }
  })
}

/// What a Spell4 row's prerequisite column holds: none for 0, else the row it names,
/// which the rows must hold.
pub fn column_of(
  id id: Int,
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
) -> Result(Option(Prerequisite), PlanError) {
  case id {
    0 -> Ok(None)
    _ -> prerequisite_in(rows:, arcs:, id:) |> result.map(Some)
  }
}

/// What a spell's prerequisiteIdCasterCast is to a press (`0x1403ace00`): a waiver
/// when propertyFlags has bit 2 and its caster requirement block is set
/// (casterInnateRequirement0, casterInnateRequirement1 or targetBeginInnateRequirement
/// is not 0, the block the client tests), else a gate.
pub fn caster_cast_of(
  prerequisite_id prerequisite_id: Int,
  property_flags property_flags: Int,
  requirement_block block: #(Int, Int, Int),
  rows rows: fn(PrerequisiteId) -> Result(prerequisite_table.Prerequisite, Nil),
  arcs arcs: fn(Int) ->
    Result(positional_requirement.PositionalRequirement, Nil),
) -> Result(CasterCast, PlanError) {
  use column <- result.map(column_of(id: prerequisite_id, rows:, arcs:))
  let has_block = block.0 != 0 || block.1 != 0 || block.2 != 0
  case column {
    None -> NoCasterCast
    Some(prerequisite) ->
      case has_flag(flags: property_flags, bit: 0x4) && has_block {
        True -> RequirementWaiver(prerequisite:)
        False -> CastGate(prerequisite:)
      }
  }
}

fn global_cooldown_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(GlobalCooldown, PlanError) {
  let kind = row.global_cooldown_enum
  let refused_while_running = kind == 0 || kind == 2
  case { kind == 0 || kind == 1 } && row.spell_cool_down_id_global != 0 {
    False -> Ok(GlobalCooldown(refused_while_running:, starts_for_ms: None))
    True -> {
      use cool_down <- result.try(
        spell_cool_down.get(
          tables:,
          id: SpellCoolDownId(row.spell_cool_down_id_global),
        )
        |> result.replace_error(NoRow(
          table: "SpellCoolDown",
          id: row.spell_cool_down_id_global,
        )),
      )
      Ok(GlobalCooldown(
        refused_while_running:,
        starts_for_ms: Some(cool_down.cooldown_time),
      ))
    }
  }
}

/// The bit 0 of the spell's caster condition row: CheckCastCaster tests it
/// against the caster before a cast is sent (`Spell4.spell4ConditionsIdCaster`).
/// A row the Spell4 row names and the table lacks is a `NoRow`.
fn caster_death_of(
  conditions conditions: Option(spell4_conditions.Spell4Conditions),
) -> CasterDeath {
  case conditions {
    None -> AliveOrDead
    Some(condition) ->
      case
        has_flag(flags: condition.condition_mask, bit: 1),
        has_flag(flags: condition.condition_value, bit: 1)
      {
        False, _ -> AliveOrDead
        True, False -> CannotBeDead
        True, True -> MustBeDead
      }
  }
}

/// The Spell4Conditions row an id names, none for the id 0; a row the table lacks fails
/// the load.
fn conditions_row_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Option(spell4_conditions.Spell4Conditions), PlanError) {
  case id {
    0 -> Ok(None)
    id ->
      spell4_conditions.get(tables:, id: Spell4ConditionsId(id))
      |> result.map(Some)
      |> result.replace_error(NoRow(table: "Spell4Conditions", id:))
  }
}

/// The spell's innate costs, as (vital type, amount, EMM id): the Spell4 row's two,
/// then the two of the Spell4Thresholds row for a stage, which hold no EMM id; a type
/// of 0 or above 30, or an amount of 0, is none (`0x1403b3320`), unless the cost has
/// an EMM id (`spent_by`).
fn costs_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
  costs costs: List(#(Int, Int, Int)),
) -> Result(List(Cost), PlanError) {
  list.try_map(costs, fn(cost) {
    use fixed <- result.map(cost_of(
      tables:,
      row:,
      base:,
      cost_type: cost.0,
      amount: cost.1,
    ))
    spent_by(cost: fixed, emm_id: cost.2)
  })
  |> result.map(option.values)
}

/// The cost as its Spell4 EMM id spends it (genesis_prime/game/spend): a slot cost
/// with an id read as a spend of every point held becomes a `SpendAllCost`; any other
/// cost with an id, or no cost with one, is an `UnreadSpendCost` with the result the
/// cost gives, or 285 when there is none (`Spell4.innateCostEMMId0`: three rows hold
/// an id with no cost, and a cost has no result of its own to give).
fn spent_by(cost cost: Option(Cost), emm_id emm_id: Int) -> Option(Cost) {
  case spend.spend_of(emm_id:), cost {
    None, cost -> cost
    Some(spend.AllHeld), Some(SlotCost(slot:, amount:, result:)) ->
      Some(SpendAllCost(slot:, amount:, result:))
    Some(spend.AllHeld), other -> Some(unread_spend(cost: other, emm_id:))
    Some(spend.Unread(emm_id:)), other ->
      Some(unread_spend(cost: other, emm_id:))
  }
}

fn unread_spend(cost cost: Option(Cost), emm_id emm_id: Int) -> Cost {
  let result = case cost {
    Some(SlotCost(result:, ..))
    | Some(SpendAllCost(result:, ..))
    | Some(ClassVitalCost(result:, ..))
    | Some(UnheldCost(result:))
    | Some(UnreadSpendCost(result:, ..)) -> result
    None -> 285
  }
  UnreadSpendCost(result:, emm_id:)
}

/// The EMM id beside each of the Spell4 row's two innate costs, 0 for a cost that holds
/// none: an id with no cost is no spend (`has_cost`), which `cost_of` refuses the press
/// of, so the measure does not count it as a use.
pub fn spent_emm_ids(row row: spell4.Spell4) -> List(Int) {
  [
    #(row.innate_cost_type0, row.innate_cost0, row.innate_cost_emm_id0),
    #(row.innate_cost_type1, row.innate_cost1, row.innate_cost_emm_id1),
  ]
  |> list.map(fn(cost) {
    case has_cost(cost_type: cost.0, amount: cost.1) {
      True -> cost.2
      False -> 0
    }
  })
}

/// Whether a Spell4 cost column pair holds a cost: a type of 0 or above 30, or an
/// amount of 0, is none (`0x1403b3320`).
fn has_cost(cost_type cost_type: Int, amount amount: Int) -> Bool {
  cost_type != 0 && amount != 0 && cost_type <= 30
}

fn cost_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
  cost_type cost_type: Int,
  amount amount: Int,
) -> Result(Option(Cost), PlanError) {
  use <- bool.guard(when: !has_cost(cost_type:, amount:), return: Ok(None))
  case cost_type, slot_of(vital_type: cost_type) {
    1, _ -> Ok(Some(UnheldCost(result: 44)))
    3, _ -> Ok(Some(UnheldCost(result: 176)))
    15, _ -> Ok(Some(UnheldCost(result: 167)))
    16, _ -> Ok(Some(UnheldCost(result: 177)))
    _, Ok(#(slot, result)) -> Ok(Some(SlotCost(slot:, amount:, result:)))
    18, Error(Nil) ->
      class_cost_of(tables:, base:, vital: cost_type, amount:)
      |> result.map(Some)
    _, Error(Nil) -> Error(UnreadCost(spell4_id: row.id, cost_type:))
  }
}

/// The resource slot a cost or requirement type reads and the result its failure
/// gives: 5 to 11 are slots 0 to 6 (50 to 56) (`0x1403b3320`, `0x1403b1780`). The
/// client's types 16 and 27 to 29 read slots 7 to 10, which no class resource of
/// the server uses.
fn slot_of(vital_type vital_type: Int) -> Result(#(Int, Int), Nil) {
  case vital_type {
    _ if vital_type >= 5 && vital_type <= 11 ->
      Ok(#(vital_type - 5, 50 + vital_type - 5))
    _ -> Error(Nil)
  }
}

/// The class mechanic's cost in a vital that has no fixed slot: the class's slots
/// holding the vital, in order, and the last one's result, 50 + its number (177
/// for slot 7) (`0x1405e7980`).
fn class_cost_of(
  tables tables: table_store.Tables,
  base base: spell4_base.Spell4Base,
  vital vital: Int,
  amount amount: Int,
) -> Result(Cost, PlanError) {
  use class_row <- result.try(
    class.get(tables:, id: ClassId(base.class_id_player))
    |> result.replace_error(NoRow(table: "Class", id: base.class_id_player)),
  )
  let slots =
    [
      class_row.vital_enum_resource00,
      class_row.vital_enum_resource01,
      class_row.vital_enum_resource02,
      class_row.vital_enum_resource03,
      class_row.vital_enum_resource04,
      class_row.vital_enum_resource05,
      class_row.vital_enum_resource06,
      class_row.vital_enum_resource07,
    ]
    |> list.index_map(fn(slot_vital, slot) { #(slot, slot_vital) })
    |> list.filter(fn(pair) { pair.1 == vital })
    |> list.map(fn(pair) { pair.0 })
  Ok(
    ClassVitalCost(slots:, amount:, result: case list.last(slots) {
      Ok(7) -> 177
      Ok(slot) -> 50 + slot
      Error(Nil) -> 0
    }),
  )
}

/// The spell's caster vital requirements, as (type, eval, value): type 0 is none
/// (`0x1403b1780`).
fn requirements_of(
  spell4_id spell4_id: Int,
  requirements requirements: List(#(Int, Int, Int)),
) -> Result(List(Requirement), PlanError) {
  list.try_map(requirements, fn(requirement) {
    let #(requirement_type, eval, value) = requirement
    case requirement_type, slot_of(vital_type: requirement_type) {
      0, _ -> Ok(None)
      _, Ok(#(slot, result)) ->
        Ok(
          Some(Requirement(
            slot:,
            measure: case eval > 4 {
              True -> PercentOfMax
              False -> Amount
            },
            comparison: comparison_of(eval:),
            value:,
            result:,
          )),
        )
      _, Error(Nil) -> Error(UnreadRequirement(spell4_id:, requirement_type:))
    }
  })
  |> result.map(option.values)
}

/// How an eval code compares (`0x1407a1750`).
fn comparison_of(eval eval: Int) -> Comparison {
  case eval {
    0 | 5 -> Equal
    1 | 6 -> Greater
    2 | 7 -> AtLeast
    3 | 8 -> Less
    4 | 9 -> AtMost
    other -> NeverPasses(eval: other)
  }
}

/// The Spell4Effects phase flag of a go: bit n is phase n.
pub fn phase_bit(phase phase: Int) -> Int {
  int.bitwise_shift_left(1, phase)
}

/// Whether the flags hold the bit.
pub fn has_flag(flags flags: Int, bit bit: Int) -> Bool {
  int.bitwise_and(flags, bit) != 0
}

/// The plans the tables' load built, which a rule reads by `in_plans`.
pub fn plans(tables tables: table_store.Tables) -> Plans {
  table_store.derived(tables:, key: plans_key)
}

/// The tree of the ability held as this Spell4BaseId among the plans, or
/// `Error(Nil)` for a base no class's level-1 ability has.
pub fn in_plans(
  plans plans: Plans,
  base spell4_base_id: Spell4BaseId,
) -> Result(Spell, Nil) {
  dict.get(plans, spell4_base_id.value)
}

/// The time of each go after the start of a cast of the spell, in milliseconds: a
/// channel's pulses, the running sum of a Multiphase spell's phase delays, none
/// for a ChargeRelease ability with stages, whose cast is held until its release
/// (`cast.charge_release_base`), and else the cast time, the one go.
pub fn go_times_ms(spell spell: Spell) -> List(Int) {
  case spell.channel, spell.phase_delays_ms {
    Some(channel), _ -> channel_go_times_ms(channel:)
    None, [] ->
      case opens_threshold(spell:) && spell.method == ChargeRelease {
        True -> []
        False -> [spell.cast_time_ms]
      }
    None, delays -> list.scan(delays, 0, fn(elapsed, delay) { elapsed + delay })
  }
}

/// How many gos a cast of the spell has: a channel's pulses, a Multiphase spell's
/// phases, none for a ChargeRelease ability held until its release, else one
/// (`go_times_ms`).
pub fn go_count(spell spell: Spell) -> Int {
  list.length(go_times_ms(spell:))
}

/// The times of a channel's pulses: (channelMaxTime - channelInitialDelay +
/// channelPulseTime) / channelPulseTime of them, in whole numbers
/// (`0x14053d1f0`), at the initial delay plus each pulse time (the times are the
/// server's choice).
pub fn channel_go_times_ms(channel channel: Channel) -> List(Int) {
  let count =
    { channel.max_time_ms - channel.initial_delay_ms + channel.pulse_time_ms }
    / channel.pulse_time_ms
  list.repeat(Nil, count)
  |> list.index_map(fn(_, pulse) {
    channel.initial_delay_ms + pulse * channel.pulse_time_ms
  })
}

/// The time a channel ends at when that is after its last pulse: the cast ends at
/// channelMaxTime from a timer of its own. A channel whose last pulse is at
/// channelMaxTime, and every spell that is not Channeled, ends with its last go.
pub fn finish_after_ms(spell spell: Spell) -> Option(Int) {
  case spell.channel {
    None -> None
    Some(channel) ->
      case list.last(channel_go_times_ms(channel:)) {
        Ok(last) if last >= channel.max_time_ms -> None
        Ok(_) | Error(Nil) -> Some(channel.max_time_ms)
      }
  }
}

/// How long a cast of the spell lasts, in milliseconds, which is what the client
/// counts the current cast's time left from (`cast.press_queue`): a channel's
/// channelMaxTime, else the cast time, else the sum of a Multiphase spell's phase
/// delays; none for a ChargeRelease ability that holds its cast until the release.
pub fn duration_ms(spell spell: Spell) -> Option(Int) {
  case spell.channel, spell.phase_delays_ms {
    Some(channel), _ -> Some(channel.max_time_ms)
    None, [] ->
      case go_times_ms(spell:) {
        [] -> None
        [_, ..] -> Some(spell.cast_time_ms)
      }
    None, delays ->
      case spell.cast_time_ms {
        0 -> Some(int.sum(delays))
        cast_time -> Some(cast_time)
      }
  }
}

/// Whether a press of the ability opens a threshold: a RapidTap or ChargeRelease
/// spell with stages.
pub fn opens_threshold(spell spell: Spell) -> Bool {
  case spell.method {
    RapidTap | ChargeRelease -> spell.stages != []
    Normal
    | Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | Multiphase
    | Transactional
    | OtherMethod(..) -> False
  }
}

/// The spell a press casts through the ability's open threshold at `index`: the
/// stage's at 0 or more, the ability's own at -1, and none past the last stage or
/// below -1, which the press is refused for (4) (`0x1403bfd60`).
pub fn stage_at(spell spell: Spell, index index: Int) -> Result(Spell, Nil) {
  use <- bool.guard(when: index == -1, return: Ok(spell))
  use <- bool.guard(when: index < 0, return: Error(Nil))
  list.drop(spell.stages, index)
  |> list.first
  |> result.map(fn(stage) { stage.spell })
}

/// The spell, the stage spells a RapidTap or ChargeRelease ability casts, the spell of
/// each Proxy that `started` accepts and the spell each Proc effect casts, below them,
/// each with its own tree the same way. A proc's spell may be cast whenever its holder
/// holds the proc, so every one is in the tree.
pub fn tree(
  spell spell: Spell,
  started started: fn(Proxy) -> Bool,
) -> List(Spell) {
  let stages = list.map(spell.stages, fn(stage) { stage.spell })
  let proxied =
    list.filter(spell.proxies, started)
    |> list.map(fn(proxy) { proxy.spell })
  let procced = list.map(spell.procs, fn(proc) { proc.spell })
  [
    spell,
    ..list.flat_map(list.flatten([stages, proxied, procced]), fn(below) {
      tree(spell: below, started:)
    })
  ]
}

/// The units an effect aimed by `aim` reaches (`Spell4Effects.targetFlags`): the caster,
/// the cast's primary target, the units of the area, or the primary target and those.
/// One rule for the cast's lasting rows and the strike's crowd-control states.
pub fn units_aimed_at(
  aim aim: Aim,
  caster caster: Int,
  primary_target primary_target: Int,
  area area: List(Int),
) -> List(Int) {
  case aim {
    AimsAtCaster -> [caster]
    AimsAtPrimaryTarget -> [primary_target]
    AimsAtArea -> area
    AimsAtBoth -> list.unique([primary_target, ..area])
    OtherAim(..) -> []
  }
}

/// The Proc effects of the spell that apply in phase `phase`, those whose tag holds for
/// the points the cast spent.
pub fn procs_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(ProcRow) {
  in_phase(
    rows: spell.procs,
    phase_flags: fn(proc) { proc.phase_flags },
    tag: fn(proc) { proc.tag },
    phase:,
    spent:,
  )
}

/// The Fluff effects of the spell that apply in phase `phase`, those whose tag holds
/// for the points the cast spent.
pub fn lasting_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(Lasting) {
  in_phase(
    rows: spell.lasting,
    phase_flags: fn(lasting) { lasting.phase_flags },
    tag: fn(lasting) { lasting.tag },
    phase:,
    spent:,
  )
}

/// The HealShields effects of the spell that apply in phase `phase`, those whose tag
/// holds for the points the cast spent.
pub fn shield_heals_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(ShieldHeal) {
  in_phase(
    rows: spell.shield_heals,
    phase_flags: fn(heal) { heal.phase_flags },
    tag: fn(heal) { heal.tag },
    phase:,
    spent:,
  )
}

/// The UnitPropertyModifier effects of the spell that apply in phase `phase`, those
/// whose tag holds for the points the cast spent.
pub fn modifiers_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(PropertyModifier) {
  in_phase(
    rows: spell.modifiers,
    phase_flags: fn(modifier) { modifier.phase_flags },
    tag: fn(modifier) { modifier.tag },
    phase:,
    spent:,
  )
}

/// The ForcedMove effects of the spell that apply in phase `phase`, those whose tag
/// holds for the points the cast spent.
pub fn forced_moves_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(ForcedMove) {
  in_phase(
    rows: spell.forced_moves,
    phase_flags: fn(forced_move) { forced_move.phase_flags },
    tag: fn(forced_move) { forced_move.tag },
    phase:,
    spent:,
  )
}

/// The ModifySpellCooldown effects of the spell that apply in phase `phase`, those
/// whose tag holds for the points the cast spent.
pub fn cooldown_modifiers_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(CooldownModifier) {
  in_phase(
    rows: spell.cooldown_modifiers,
    phase_flags: fn(row) { row.phase_flags },
    tag: fn(row) { row.tag },
    phase:,
    spent:,
  )
}

/// The SpellForceRemove effects of the spell that apply in phase `phase`, those
/// whose tag holds for the points the cast spent.
pub fn removes_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(ForceRemove) {
  in_phase(
    rows: spell.removes,
    phase_flags: fn(remove) { remove.phase_flags },
    tag: fn(remove) { remove.tag },
    phase:,
    spent:,
  )
}

/// The Stealth effects of the spell that apply in phase `phase`, those whose tag holds
/// for the points the cast spent.
pub fn stealth_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(StealthRow) {
  in_phase(
    rows: spell.stealth,
    phase_flags: fn(stealth) { stealth.phase_flags },
    tag: fn(stealth) { stealth.tag },
    phase:,
    spent:,
  )
}

/// The RemoveStealth effects of the spell that apply in phase `phase`, those whose tag
/// holds for the points the cast spent.
pub fn remove_stealth_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(RemoveStealthRow) {
  in_phase(
    rows: spell.remove_stealth,
    phase_flags: fn(remove) { remove.phase_flags },
    tag: fn(remove) { remove.tag },
    phase:,
    spent:,
  )
}

/// The CCStateSet effects of the spell that apply in phase `phase`, those whose tag
/// holds for the points the cast spent.
pub fn controls_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(CrowdControl) {
  in_phase(
    rows: spell.controls,
    phase_flags: fn(control) { control.phase_flags },
    tag: fn(control) { control.tag },
    phase:,
    spent:,
  )
}

/// The Proxies of the spell that fire in phase `phase`, those whose tag holds for
/// the points the cast spent (genesis_prime/game/spend `applies`).
pub fn proxies_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(Proxy) {
  in_phase(
    rows: spell.proxies,
    phase_flags: fn(proxy) { proxy.phase_flags },
    tag: fn(proxy) { proxy.tag },
    phase:,
    spent:,
  )
}

/// The spellGroupId00 to 31 columns of a Spell4GroupList row, in order.
fn group_ids_of(row row: spell4_group_list.Spell4GroupList) -> List(Int) {
  [
    row.spell_group_id00,
    row.spell_group_id01,
    row.spell_group_id02,
    row.spell_group_id03,
    row.spell_group_id04,
    row.spell_group_id05,
    row.spell_group_id06,
    row.spell_group_id07,
    row.spell_group_id08,
    row.spell_group_id09,
    row.spell_group_id10,
    row.spell_group_id11,
    row.spell_group_id12,
    row.spell_group_id13,
    row.spell_group_id14,
    row.spell_group_id15,
    row.spell_group_id16,
    row.spell_group_id17,
    row.spell_group_id18,
    row.spell_group_id19,
    row.spell_group_id20,
    row.spell_group_id21,
    row.spell_group_id22,
    row.spell_group_id23,
    row.spell_group_id24,
    row.spell_group_id25,
    row.spell_group_id26,
    row.spell_group_id27,
    row.spell_group_id28,
    row.spell_group_id29,
    row.spell_group_id30,
    row.spell_group_id31,
  ]
}
