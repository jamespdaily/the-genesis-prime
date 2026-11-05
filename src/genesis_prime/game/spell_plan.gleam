//// What the client's tables say a pressed ability does: for each ability a class
//// holds at level 1, the tree of casts it starts, built once when the tables
//// load. The cast rule (genesis_prime/game/cast) reads the tree and decides
//// nothing from the tables itself.
////
//// ```
//// SpellLevel (class, level 1, no prerequisite) ─▶ Spell4 (the ability) ─▶ Spell4Base
////      Spell4Effects (spellId = the Spell4 id), each effect of type Proxy (26) ─▶ the Spell4 it names, as a child
////      Spell4Thresholds (parent = the Spell4 id), by order index ─▶ the Spell4 each tap or charge level casts, as a stage
////      SpellPhase (owner = a Multiphase Spell4) ─▶ the phase delays and flags, in row order
////      SpellCoolDown (the global row) ─▶ the global cooldown's time
////      Class (vitalEnumResource0..) ─▶ the result a short vital gives
//// all of them, once, when the tables load ─▶ Plans ─▶ in_plans(base)
//// ```
////
//// - **The tree.** A Proxy effect (`Spell4Effects.effectType.26`, dataBits00 the
////   Spell4 id; 0 names none) starts that spell as a cast of its own, so a `Spell`
////   holds its `Proxy` children, each with the delay the effect gives after its
////   parent's go (`delayTime`) and the phases it fires in (`phaseFlags`: bit n is
////   phase n, every bit for -1, the reading `Spell4.38791` gives). A Proxy with a
////   target apply prerequisite is kept as `GatedOnTarget` and not started: the
////   server checks no target-side prerequisite. A Proxy with a caster apply
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
//// - **The lasting effects.** A Fluff effect (`Spell4Effects.effectType.17`) of a tree
////   is a `Lasting` row: the unit its targetFlags aim at, its delay, durationTime and
////   flags bit 2, which give its spell a life there (genesis_prime/game/lasting). A
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
////   `UnreadRequirement`. The waiver (propertyFlags bit 2 with a
////   prerequisiteIdCasterCast) is kept and never passes: the waiver's prerequisite
////   is not checked.
//// - **No target.** None of the 18 level-1 abilities needs a target the client
////   picks (`Spell4TargetMechanics.targetType`), so the plan holds no range and
////   no target rule.
//// - **The caster's death.** Bit 0 of the spell's caster condition row says
////   whether its caster must be alive, must be dead or may be either
////   (`Spell4.spell4ConditionsIdCaster`, `CasterDeath`); the row's other
////   conditions are not read.
//// - **What fails the load:** a Spell4, Spell4Base, Spell4Conditions, SpellCoolDown,
////   Class or Prerequisite row the tree names that the tables lack, a cost of a type
////   not read, a cycle of Proxy effects, a channel with no pulse time, a gain
////   aimed other than at the caster, of a vital other than 6 or 8, or behind a
////   target apply prerequisite, and an effect of a spell that spends every point
////   held with an emmComparison other than 0 or 1; a Fluff or SpellForceRemove effect
////   aimed other than at the caster, the primary target or the area; a type 80
////   effect with a dataBits00 other than 1 to 3, naming no group, Spell4 or
////   Spell4Base, or whose dataBits03 and dataBits04 differ; and a Spell4GroupList or
////   Spell4StackGroup row a spell names that the tables lack.

import genesis_prime/game/effect_kind
import genesis_prime/game/lasting
import genesis_prime/game/loadout
import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/game/spend
import genesis_prime/table/class
import genesis_prime/table/id.{
  type PrerequisiteId, type Spell4BaseId, type Spell4EffectsId, type Spell4Id,
  ClassId, PrerequisiteId, Spell4BaseId, Spell4ConditionsId, Spell4EffectsId,
  Spell4Id, Spell4StackGroupId, SpellCoolDownId,
}
import genesis_prime/table/loader/store as table_store
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
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
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
  /// The Proxy applies only behind this target apply prerequisite, which is not
  /// checked: the child is not started.
  GatedOnTarget(prerequisite_id: PrerequisiteId)
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
    /// The prerequisite that would waive a failed requirement: the spell's
    /// prerequisiteIdCasterCast when its propertyFlags has bit 2 (`0x1403b1780`).
    /// The waiver's prerequisite is not checked, so it never passes.
    requirement_waiver: Option(PrerequisiteId),
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
    /// The Fluff effects that give the spell a life on a unit.
    lasting: List(Lasting),
    /// The SpellForceRemove effects that take casts off a unit.
    removes: List(ForceRemove),
  )
}

/// A Fluff effect (`Spell4Effects.effectType.17`) of a spell: it names the unit it
/// aims at in the go's target info and gives the spell a life there, from its
/// `row`, in the phases of `phase_flags`, when its `condition` holds (its caster
/// apply prerequisite against the caster; one behind a target apply prerequisite is
/// not applied), and when its `tag` holds for the points the cast spent
/// (genesis_prime/game/spend). Its dataBits need no handling.
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
  /// A Fluff or SpellForceRemove effect of a tree is aimed by a flag value that is
  /// not read (`Spell4Effects.targetFlags`).
  LastingAimNotRead(spell4_id: Int, effect_id: Int, target_flags: Int)
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
      <> " has a Fluff or SpellForceRemove effect "
      <> int.to_string(effect_id)
      <> " aimed by flags "
      <> int.to_string(target_flags)
      <> ", which are not read"
  }
}

fn string_of(chain: List(Int)) -> String {
  string.join(list.map(chain, int.to_string), " -> ")
}

/// Every class's level-1 abilities as trees, by Spell4BaseId, as the load keeps
/// them.
pub type Plans =
  Dict(Int, Spell)

const plans_key: table_store.DerivedKey(Plans) =
  table_store.DerivedKey("SpellPlans")

/// The plans as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`): a plan for the Spell4BaseId of
/// each class's level-1 ability. A missing row, a cost not read or a cycle fails
/// the load.
pub fn derivation() -> table_store.Derivation {
  table_store.derivation(key: plans_key, build: fn(tables) {
    build(tables:)
    |> result.map_error(fn(error) { describe(error:) })
  })
}

/// The rows the tree reads, grouped by the spell they belong to.
type Sources {
  Sources(
    effects: Dict(Int, List(spell4_effects.Spell4Effects)),
    phases: Dict(Int, List(Phase)),
    thresholds: Dict(Int, List(spell4_thresholds.Spell4Thresholds)),
    /// The spell group ids of each Spell4GroupList row, by the row's id.
    group_lists: Dict(Int, List(Int)),
  )
}

/// A SpellPhase row the client keeps.
type Phase {
  Phase(delay_ms: Int, flags: Int)
}

/// Builds every plan from the loaded tables, or why one cannot be built; the
/// derivation's body, and the function a test of a missing row or a cycle runs
/// on planted tables.
pub fn build(tables tables: table_store.Tables) -> Result(Plans, PlanError) {
  let sources =
    Sources(
      effects: effects_by_spell(tables:),
      phases: phases_by_owner(tables:),
      thresholds: thresholds_by_parent(tables:),
      group_lists: group_lists_by_id(tables:),
    )
  spell_level.all(tables)
  |> list.filter(loadout.is_level_one_ability)
  |> list.try_fold(dict.new(), fn(plans, row) {
    use spell <- result.try(
      spell_of(
        tables:,
        sources:,
        spell4_id: row.spell4_id,
        chain: [],
        threshold_costs: [],
      ),
    )
    use Nil <- result.try(has_threshold_time(spell:))
    Ok(dict.insert(plans, spell.spell4_base_id.value, spell))
  })
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

fn spell_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  chain chain: List(Int),
  threshold_costs threshold_costs: List(#(Int, Int)),
) -> Result(Spell, PlanError) {
  let chain = list.append(chain, [spell4_id])
  use <- bool.guard(
    when: list.contains(list.take(chain, list.length(chain) - 1), spell4_id),
    return: Error(ProxyCycle(chain:)),
  )
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
  use caster_death <- result.try(caster_death_of(tables:, row:))
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
  use Nil <- result.try(spend_tags_read(spell4_id:, costs:, effects:))
  use gains <- result.try(gains_of(tables:, spell4_id:, effects:))
  use lasting <- result.try(lasting_of(tables:, spell4_id:, effects:))
  use removes <- result.try(removes_of(tables:, sources:, spell4_id:, effects:))
  use groups <- result.try(groups_of(sources:, row:))
  use stack <- result.try(stack_of(tables:, row:))
  use proxies <- result.try(
    effects
    |> list.filter(fn(effect) {
      effect_kind.kind_of(effect.effect_type) == effect_kind.Proxy
      && effect.data_bits00 != 0
    })
    |> list.try_map(fn(effect) {
      use target <- result.try(target_of(spell4_id:, effect:))
      use child <- result.try(
        spell_of(
          tables:,
          sources:,
          spell4_id: effect.data_bits00,
          chain:,
          threshold_costs: [],
        ),
      )
      // Every gain under a Proxy aimed at each struck unit in the client's level-1
      // trees fires in phase 0 only (`spell_plan_gain_test` reads them all), so
      // lifting by phase 0 loses none to a later phase.
      let #(lifted, kept) = case target {
        OnEachStruck ->
          list.partition(child.gains, fn(gain) {
            has_flag(flags: gain.phase_flags, bit: 1)
          })
        OnCaster -> #([], child.gains)
      }
      use condition <- result.try(condition_of(tables:, effect:))
      Ok(Proxy(
        effect_id: Spell4EffectsId(effect.id),
        delay_ms: effect.delay_time,
        phase_flags: effect.phase_flags,
        condition:,
        tag: tag_of(effect:),
        target:,
        spell: Spell(..child, gains: kept),
        gains: lifted,
      ))
    }),
  )
  use stages <- result.try(
    dict.get(sources.thresholds, spell4_id)
    |> result.unwrap([])
    |> list.try_map(fn(threshold) {
      use stage <- result.try(
        spell_of(
          tables:,
          sources:,
          spell4_id: threshold.spell4_id_to_cast,
          chain:,
          threshold_costs: [
            #(threshold.vital_enum_cost_type00, threshold.vital_cost_value00),
            #(threshold.vital_enum_cost_type01, threshold.vital_cost_value01),
          ],
        ),
      )
      Ok(Stage(duration_ms: threshold.threshold_duration, spell: stage))
    }),
  )
  let method = method_of(base.cast_method)
  let phases = dict.get(sources.phases, spell4_id) |> result.unwrap([])
  use delays <- result.try(phase_delays(phases:, method:, spell4_id:))
  use channel <- result.try(channel_of(row:, method:))
  Ok(Spell(
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
    requirement_waiver: case
      has_flag(flags: row.property_flags, bit: 0x4),
      row.prerequisite_id_caster_cast
    {
      True, prerequisite if prerequisite != 0 ->
        Some(PrerequisiteId(prerequisite))
      True, _ | False, _ -> None
    },
    phase_delays_ms: delays,
    threshold_ms: row.threshold_time,
    stages:,
    channel:,
    proxies:,
    gains:,
    groups:,
    stack:,
    lasting:,
    removes:,
  ))
}

/// The gains of a spell's effects: each VitalModifier, which must aim at the
/// caster, change vital 6 or 8, and have no target apply prerequisite; its caster
/// apply prerequisite is read from its row.
fn gains_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effects effects: List(spell4_effects.Spell4Effects),
) -> Result(List(Gain), PlanError) {
  effects
  |> list.filter(fn(effect) {
    effect_kind.kind_of(effect.effect_type) == effect_kind.VitalModifier
  })
  |> list.try_map(fn(effect) {
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
      _ ->
        Error(GainTargetPrerequisiteNotRead(spell4_id:, effect_id: effect.id))
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
  })
}

/// The Fluff effects of a spell: each aimed at a unit the plan reads, with the
/// columns that give its node a life (`Spell4Effects.effectType.17`).
fn lasting_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
  effects effects: List(spell4_effects.Spell4Effects),
) -> Result(List(Lasting), PlanError) {
  effects
  |> list.filter(fn(effect) {
    effect_kind.kind_of(effect.effect_type) == effect_kind.Fluff
  })
  |> list.try_map(fn(effect) {
    use aim <- result.try(lasting_aim_of(spell4_id:, effect:))
    use condition <- result.try(applied_when(tables:, effect:))
    Ok(Lasting(
      effect_id: Spell4EffectsId(effect.id),
      phase_flags: effect.phase_flags,
      aim:,
      row: lasting.LastingRow(
        delay_ms: effect.delay_time,
        duration_ms: effect.duration_time,
        until_removed: has_flag(flags: effect.flags, bit: 2),
      ),
      condition:,
      tag: tag_of(effect:),
    ))
  })
}

/// The SpellForceRemove effects of a spell (`Spell4Effects.effectType.80`): dataBits00
/// picks what is removed (1 a spell group, 2 a Spell4, 3 a Spell4Base) by dataBits01,
/// which must name a row; the count of stacks is read only where dataBits03 and
/// dataBits04 agree.
fn removes_of(
  tables tables: table_store.Tables,
  sources sources: Sources,
  spell4_id spell4_id: Int,
  effects effects: List(spell4_effects.Spell4Effects),
) -> Result(List(ForceRemove), PlanError) {
  effects
  |> list.filter(fn(effect) {
    effect_kind.kind_of(effect.effect_type) == effect_kind.ForceRemove
  })
  |> list.try_map(fn(effect) {
    use aim <- result.try(lasting_aim_of(spell4_id:, effect:))
    use selector <- result.try(selector_of(
      tables:,
      sources:,
      spell4_id:,
      effect:,
    ))
    use Nil <- result.try(case effect.data_bits03 == effect.data_bits04 {
      True -> Ok(Nil)
      False ->
        Error(ForceRemoveCountsDiffer(
          spell4_id:,
          effect_id: effect.id,
          data_bits03: effect.data_bits03,
          data_bits04: effect.data_bits04,
        ))
    })
    use condition <- result.try(applied_when(tables:, effect:))
    Ok(ForceRemove(
      effect_id: Spell4EffectsId(effect.id),
      phase_flags: effect.phase_flags,
      aim:,
      selector:,
      count: effect.data_bits03,
      condition:,
      tag: tag_of(effect:),
    ))
  })
}

/// The aim of a Fluff or SpellForceRemove effect: the caster, the primary target, the
/// area or both of those; any other flag value fails the load.
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
  sources sources: Sources,
  spell4_id spell4_id: Int,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(lasting.Selector, PlanError) {
  let named = effect.data_bits01
  case effect.data_bits00 {
    1 ->
      case list.any(dict.values(sources.group_lists), list.contains(_, named)) {
        True -> Ok(lasting.Group(spell_group_id: named))
        False -> Error(NoRow(table: "Spell4GroupList", id: named))
      }
    2 ->
      spell4.get(tables:, id: Spell4Id(named))
      |> result.map(fn(_) { lasting.Spell(spell4_id: Spell4Id(named)) })
      |> result.replace_error(NoRow(table: "Spell4", id: named))
    3 ->
      spell4_base.get(tables:, id: Spell4BaseId(named))
      |> result.map(fn(_) { lasting.Base(spell4_base_id: Spell4BaseId(named)) })
      |> result.replace_error(NoRow(table: "Spell4Base", id: named))
    selector ->
      Error(ForceRemoveSelectorNotRead(
        spell4_id:,
        effect_id: effect.id,
        selector:,
      ))
  }
}

/// When a Fluff or SpellForceRemove effect applies: its caster apply prerequisite
/// passes against the caster, and a target apply prerequisite leaves it unapplied
/// (the server checks no target-side prerequisite). Unlike a Proxy's, its dataBits06
/// is no prerequisite.
fn applied_when(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Condition, PlanError) {
  case
    effect.prerequisite_id_target_apply,
    effect.prerequisite_id_caster_apply
  {
    0, 0 -> Ok(Always)
    0, caster ->
      prerequisite_of(tables:, id: caster)
      |> result.map(fn(gate) { GatedOnCaster(gates: [gate]) })
    target, _ -> Ok(GatedOnTarget(prerequisite_id: PrerequisiteId(target)))
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

/// A spell that spends every point held has an n, which each of its effects' tags
/// chooses by, so each must be one the rule reads (emmComparison 0 or 1). A spell
/// with no such cost chooses nothing and its tags are not looked at.
fn spend_tags_read(
  spell4_id spell4_id: Int,
  costs costs: List(Cost),
  effects effects: List(spell4_effects.Spell4Effects),
) -> Result(Nil, PlanError) {
  let spends =
    list.any(costs, fn(cost) {
      case cost {
        SpendAllCost(..) -> True
        SlotCost(..)
        | ClassVitalCost(..)
        | UnheldCost(..)
        | UnreadSpendCost(..) -> False
      }
    })
  use <- bool.guard(when: !spends, return: Ok(Nil))
  case list.find(effects, fn(effect) { !spend.tag_is_read(tag_of(effect:)) }) {
    Ok(effect) ->
      Error(SpendComparisonNotRead(
        spell4_id:,
        effect_id: effect.id,
        comparison: effect.emm_comparison,
      ))
    Error(Nil) -> Ok(Nil)
  }
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

/// The gains of the spell given at its go of phase `phase`, those whose tag holds
/// for the points the cast spent (genesis_prime/game/spend `applies`).
pub fn gains_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(Gain) {
  list.filter(spell.gains, fn(gain) {
    has_flag(flags: gain.phase_flags, bit: int.bitwise_shift_left(1, phase))
    && spend.applies(tag: gain.tag, spent:)
  })
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

/// A Proxy's condition: a target apply prerequisite, which the server does not
/// check, else its caster apply prerequisite and the one its dataBits06 names
/// (`Spell4Effects.effectType.26.dataBits06`: a reading of the rows, since the
/// client applies no Proxy itself), both checked against the caster. A prerequisite
/// the table lacks fails the load.
fn condition_of(
  tables tables: table_store.Tables,
  effect effect: spell4_effects.Spell4Effects,
) -> Result(Condition, PlanError) {
  case effect.prerequisite_id_target_apply {
    0 -> {
      use gates <- result.try(
        [effect.prerequisite_id_caster_apply, effect.data_bits06]
        |> list.filter(fn(id) { id != 0 })
        |> list.try_map(fn(id) { prerequisite_of(tables:, id:) }),
      )
      Ok(case gates {
        [] -> Always
        [_, ..] -> GatedOnCaster(gates:)
      })
    }
    target -> Ok(GatedOnTarget(prerequisite_id: PrerequisiteId(target)))
  }
}

/// The Prerequisite row with this id as the client keeps it.
fn prerequisite_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Prerequisite, PlanError) {
  prerequisite_table.get(tables:, id: PrerequisiteId(id))
  |> result.map(fn(row) { prerequisite.of_row(row:) })
  |> result.replace_error(NoRow(table: "Prerequisite", id:))
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
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
) -> Result(CasterDeath, PlanError) {
  case row.spell4_conditions_id_caster {
    0 -> Ok(AliveOrDead)
    id -> {
      use condition <- result.try(
        spell4_conditions.get(tables:, id: Spell4ConditionsId(id))
        |> result.replace_error(NoRow(table: "Spell4Conditions", id:)),
      )
      Ok(
        case
          has_flag(flags: condition.condition_mask, bit: 1),
          has_flag(flags: condition.condition_value, bit: 1)
        {
          False, _ -> AliveOrDead
          True, False -> CannotBeDead
          True, True -> MustBeDead
        },
      )
    }
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

/// The spell, the stage spells a RapidTap or ChargeRelease ability casts and the
/// spell of each Proxy that `started` accepts, below them, each with its own tree
/// the same way.
pub fn tree(
  spell spell: Spell,
  started started: fn(Proxy) -> Bool,
) -> List(Spell) {
  let stages = list.map(spell.stages, fn(stage) { stage.spell })
  let proxied =
    list.filter(spell.proxies, started)
    |> list.map(fn(proxy) { proxy.spell })
  [
    spell,
    ..list.flat_map(list.append(stages, proxied), fn(below) {
      tree(spell: below, started:)
    })
  ]
}

/// The Fluff effects of the spell that apply in phase `phase`, those whose tag holds
/// for the points the cast spent.
pub fn lasting_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(Lasting) {
  list.filter(spell.lasting, fn(lasting) {
    has_flag(flags: lasting.phase_flags, bit: int.bitwise_shift_left(1, phase))
    && spend.applies(tag: lasting.tag, spent:)
  })
}

/// The SpellForceRemove effects of the spell that apply in phase `phase`, those
/// whose tag holds for the points the cast spent.
pub fn removes_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(ForceRemove) {
  list.filter(spell.removes, fn(remove) {
    has_flag(flags: remove.phase_flags, bit: int.bitwise_shift_left(1, phase))
    && spend.applies(tag: remove.tag, spent:)
  })
}

/// The Proxies of the spell that fire in phase `phase`, those whose tag holds for
/// the points the cast spent (genesis_prime/game/spend `applies`).
pub fn proxies_in_phase(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
) -> List(Proxy) {
  list.filter(spell.proxies, fn(proxy) {
    has_flag(flags: proxy.phase_flags, bit: int.bitwise_shift_left(1, phase))
    && spend.applies(tag: proxy.tag, spent:)
  })
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
