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
////   caster or target apply prerequisite is kept as `NeedsPrerequisite` and not
////   started: the server holds no prerequisite engine (`Spell4.38791`: 79220 and
////   79229 apply only behind prerequisite 37037).
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
////   are resource slots 0 to 6 (result 50 + the slot; Mind Burst, type 6, is 51),
////   16 slot 7 (177) and 27 to 29 slots 8 to 10 (327 to 329); type 18 goes to the
////   class's slots that hold that vital, the last one's result given when none
////   passes (Gamma Rays is 55). Health (1), shield (3) and focus (15) give their own
////   results (44, 176, 167) and are held by no rule of the server; any other type
////   is an `UnreadCost`.
//// - **The caster requirements.** A spell's two caster vital requirements
////   (`0x1403b1780`): types 5 to 11, 16 and 27 to 29 read the same slots with the
////   same results, compared with the value by the eval code (`0x1407a1750`: 0 to 4
////   on the amount, 5 to 9 the same on the percentage of the slot's maximum, any
////   other never passes); type 0 is none; any other type is an
////   `UnreadRequirement`. The waiver (propertyFlags bit 2 with a
////   prerequisiteIdCasterCast) is kept and never passes: the server holds no
////   prerequisite engine.
//// - **No target.** None of the 18 level-1 abilities needs a target the client
////   picks (`Spell4TargetMechanics.targetType`), so the plan holds no range and
////   no target rule.
//// - **The caster's death.** Bit 0 of the spell's caster condition row says
////   whether its caster must be alive, must be dead or may be either
////   (`Spell4.spell4ConditionsIdCaster`, `CasterDeath`); the row's other
////   conditions are not read.
//// - **What fails the load:** a Spell4, Spell4Base, Spell4Conditions, SpellCoolDown
////   or Class row the tree names that the tables lack, a cost of a type not read, a
////   cycle of Proxy effects, and a channel with no pulse time.

import genesis_prime/game/loadout
import genesis_prime/table/class
import genesis_prime/table/id.{
  type PrerequisiteId, type Spell4BaseId, type Spell4EffectsId, type Spell4Id,
  ClassId, PrerequisiteId, Spell4BaseId, Spell4ConditionsId, Spell4EffectsId,
  Spell4Id, SpellCoolDownId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_conditions
import genesis_prime/table/spell4_effects
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
  /// The Proxy applies only behind this prerequisite, which the server cannot
  /// check: the child is not started.
  NeedsPrerequisite(prerequisite_id: PrerequisiteId)
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
    /// The server holds no prerequisite engine, so it never passes.
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
    /// Which unit the child cast is made on, from the effect's `targetFlags`.
    target: ProxyTarget,
    spell: Spell,
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

/// The effect type of a Proxy (`Spell4Effects.effectType.26`).
const proxy_effect_type = 26

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
      #(row.innate_cost_type0, row.innate_cost0),
      #(row.innate_cost_type1, row.innate_cost1),
      ..threshold_costs
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
  use proxies <- result.try(
    dict.get(sources.effects, spell4_id)
    |> result.unwrap([])
    |> list.filter(fn(effect) {
      effect.effect_type == proxy_effect_type && effect.data_bits00 != 0
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
      Ok(Proxy(
        effect_id: Spell4EffectsId(effect.id),
        delay_ms: effect.delay_time,
        phase_flags: effect.phase_flags,
        condition: condition_of(effect:),
        target:,
        spell: child,
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
  ))
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

fn condition_of(effect effect: spell4_effects.Spell4Effects) -> Condition {
  case
    effect.prerequisite_id_caster_apply,
    effect.prerequisite_id_target_apply
  {
    0, 0 -> Always
    0, target -> NeedsPrerequisite(prerequisite_id: PrerequisiteId(target))
    caster, _ -> NeedsPrerequisite(prerequisite_id: PrerequisiteId(caster))
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

/// The spell's innate costs, as (vital type, amount): the Spell4 row's two, then
/// the two of the Spell4Thresholds row for a stage; a type of 0 or above 30, or an
/// amount of 0, is none (`0x1403b3320`).
fn costs_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
  costs costs: List(#(Int, Int)),
) -> Result(List(Cost), PlanError) {
  list.try_map(costs, fn(cost) {
    cost_of(tables:, row:, base:, cost_type: cost.0, amount: cost.1)
  })
  |> result.map(option.values)
}

fn cost_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
  cost_type cost_type: Int,
  amount amount: Int,
) -> Result(Option(Cost), PlanError) {
  case cost_type, slot_of(vital_type: cost_type) {
    0, _ -> Ok(None)
    _, _ if amount == 0 || cost_type > 30 -> Ok(None)
    1, _ -> Ok(Some(UnheldCost(result: 44)))
    3, _ -> Ok(Some(UnheldCost(result: 176)))
    15, _ -> Ok(Some(UnheldCost(result: 167)))
    _, Ok(#(slot, result)) -> Ok(Some(SlotCost(slot:, amount:, result:)))
    18, Error(Nil) ->
      class_cost_of(tables:, base:, vital: cost_type, amount:)
      |> result.map(Some)
    _, Error(Nil) -> Error(UnreadCost(spell4_id: row.id, cost_type:))
  }
}

/// The resource slot a cost or requirement type reads and the result its failure
/// gives: 5 to 11 slots 0 to 6 (50 to 56), 16 slot 7 (177), 27 to 29 slots 8 to 10
/// (327 to 329) (`0x1403b3320`, `0x1403b1780`).
fn slot_of(vital_type vital_type: Int) -> Result(#(Int, Int), Nil) {
  case vital_type {
    _ if vital_type >= 5 && vital_type <= 11 ->
      Ok(#(vital_type - 5, 50 + vital_type - 5))
    16 -> Ok(#(7, 177))
    _ if vital_type >= 27 && vital_type <= 29 ->
      Ok(#(vital_type - 19, 327 + vital_type - 27))
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

/// The Proxies of the spell that fire in phase `phase`.
pub fn proxies_in_phase(spell spell: Spell, phase phase: Int) -> List(Proxy) {
  let bit = int.bitwise_shift_left(1, phase)
  list.filter(spell.proxies, fn(proxy) {
    int.bitwise_and(proxy.phase_flags, bit) != 0
  })
}
