//// What the client's tables say a pressed ability does: for each ability a class
//// holds at level 1, the tree of casts it starts, built once when the tables
//// load. The cast rule (genesis_prime/game/cast) reads the tree and decides
//// nothing from the tables itself.
////
//// ```
//// SpellLevel (class, level 1, no prerequisite) ─▶ Spell4 (the ability) ─▶ Spell4Base
////      Spell4Effects (spellId = the Spell4 id), each effect of type Proxy (26) ─▶ the Spell4 it names, as a child
////      SpellPhase (owner = a Multiphase Spell4) ─▶ the phase delays, in row order
////      SpellCoolDown (the global row) ─▶ the global cooldown's time
////      Class (vitalEnumResource0..) ─▶ the result a short vital gives
//// all of them, once, when the tables load ─▶ Plans ─▶ of(base)
//// ```
////
//// - **The tree.** A Proxy effect (`Spell4Effects.effectType.26`, dataBits00 the
////   Spell4 id) starts that spell as a cast of its own, so a `Spell` holds its
////   `Proxy` children, each with the delay the effect gives after its parent's go
////   (`delayTime`), the phases it fires in (`phaseFlags`: bit n is phase n, all
////   bits for -1, the reading `Spell4.38791` gives) and the unit it names
////   (`targetFlags`: 1 the caster, by the tooltip of `Spell4.32893`; any other
////   the parent's primary target, a server choice, since a child's effects are
////   not applied here). A Proxy with a caster or target apply prerequisite is
////   kept as `NeedsPrerequisite` and not started: the server holds no
////   prerequisite engine (`Spell4.38791`: 79220 and 79229 apply only behind
////   prerequisite 37037).
//// - **The phases** of a Multiphase spell (`Spell.CodeEnumCastMethod` 8) are the
////   SpellPhase rows of its owner kept by the client's rule (`0x14055e180`: order
////   index below 32, and index 0 or a non-zero delay), each delay the gap after
////   the phase before (`SpellPhase.phaseDelay`: the server's timing, which the
////   rows suggest). Any other spell has one go, at the end of its cast time.
//// - **The cooldowns.** The spell's own is `Spell4.spellCoolDown` in
////   milliseconds. The global one is the row `spellCoolDownIdGlobal` names, in
////   effect only for kinds 0 and 1 and a non-zero row (`0x14046afc0`); kinds 0
////   and 2 are refused while it runs (`0x1403b14c0`).
//// - **The cost.** An ability with an innate cost the unit cannot pay is refused
////   with 50 + the resource slot: types 5 to 11 are slots 0 to 6 (Mind Burst,
////   type 6, is 51), and any other type goes to the class's slots, the last one
////   holding that vital giving the result (Gamma Rays, type 18, is 55), none
////   passing (`0x1403b3320`, `0x1405e7980`, `Spell4CastResult.vital_cost`): every
////   resource a new unit holds is 0 (`0x140454380`). The plan holds that result.
//// - **What fails the load:** a Spell4, Spell4Base, SpellCoolDown or Class row the
////   tree names that the tables lack, and a cycle of Proxy effects. A
////   class whose level-1 ability cannot be built stops the server's start.

import genesis_prime/table/id.{
  type PrerequisiteId, type Spell4BaseId, type Spell4EffectsId, type Spell4Id,
}
import genesis_prime/table/loader/store as table_store
import gleam/dict.{type Dict}
import gleam/option.{type Option}

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

/// Which unit a child cast is about, which the 0x7ff names as its primary
/// target.
pub type ProxyTarget {
  /// targetFlags 1.
  OnCaster
  /// Any other targetFlags: the parent's primary target.
  OnPrimaryTarget
}

/// Whether a Proxy is started.
pub type Condition {
  Always
  /// The Proxy applies only behind this prerequisite, which the server cannot
  /// check: the child is not started.
  NeedsPrerequisite(prerequisite_id: PrerequisiteId)
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
    /// Spell4.spellCoolDown: the spell's own cooldown, from its first go.
    cooldown_ms: Int,
    /// Spell4.targetMaxRange.
    max_range: Float,
    /// Whether the spell needs a target the client picks: Spell4TargetMechanics
    /// targetType 1, 3, 5 or 8 (`Spell4TargetMechanics.targetType`). Any other
    /// kind makes the caster the spell's target in the client, which then sends
    /// the caster's own unit id or 0, and is never refused 91; none of the 18
    /// level-1 abilities needs one.
    needs_target: Bool,
    weapon: WeaponSlot,
    global_cooldown: GlobalCooldown,
    /// The 0x7fc result of a press the caster cannot pay the innate cost of,
    /// when the spell has a cost (`Spell4CastResult.vital_cost`).
    unpayable_cost: Option(Int),
    /// The gap before each phase's go, in order; empty for a spell that is not
    /// Multiphase.
    phase_delays_ms: List(Int),
    proxies: List(Proxy),
  )
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
    on: ProxyTarget,
    condition: Condition,
    spell: Spell,
  )
}

/// Why the plans cannot be built from the tables.
pub type PlanError {
  /// A table row the tree names is missing: the table, and the id.
  NoRow(table: String, id: Int)
  /// The Proxy effects of a spell lead back to a spell on the way to it: the
  /// Spell4 ids from the pressed ability to the one that repeats.
  ProxyCycle(chain: List(Int))
  /// A spell's innate cost is of a type whose check the client's code was not
  /// read for (`0x1403b3320` gives the rules of types 0, 5 to 11 and 18).
  UnreadCost(spell4_id: Int, cost_type: Int)
}

/// A sentence that says why the plans cannot be built, naming the table and the
/// row, for the message the server stops with.
pub fn describe(error error: PlanError) -> String {
  unbuilt(inputs: error)
}

/// The plans as a value the tables' load builds once, under the tables' key
/// (genesis_prime/table/loader/store `derived`): a plan for the Spell4BaseId of
/// each class's level-1 ability. A missing row or a cycle fails the load.
pub fn derivation() -> table_store.Derivation {
  unbuilt(inputs: Nil)
}

/// Every class's level-1 abilities as trees, by Spell4BaseId, as the load keeps
/// them.
pub type Plans =
  Dict(Int, Spell)

/// Builds every plan from the loaded tables, or why one cannot be built; the
/// derivation's body, and the function a test of a missing row or a cycle runs
/// on planted tables.
pub fn build(tables tables: table_store.Tables) -> Result(Plans, PlanError) {
  unbuilt(inputs: tables)
}

/// The plans the tables' load built, which a rule reads by `in_plans`.
pub fn plans(tables tables: table_store.Tables) -> Plans {
  unbuilt(inputs: tables)
}

/// The tree of the ability held as this Spell4BaseId among the plans, or
/// `Error(Nil)` for a base no class's level-1 ability has.
pub fn in_plans(
  plans plans: Plans,
  base spell4_base_id: Spell4BaseId,
) -> Result(Spell, Nil) {
  unbuilt(inputs: #(plans, spell4_base_id))
}

/// The time of each phase's go after the start of a cast of the spell, in
/// milliseconds: the running sum of its phase delays; the cast time for a spell
/// that is not Multiphase, which has the one go.
pub fn go_times_ms(spell spell: Spell) -> List(Int) {
  unbuilt(inputs: spell)
}

/// The Proxies of the spell that fire in phase `phase`.
pub fn proxies_in_phase(spell spell: Spell, phase phase: Int) -> List(Proxy) {
  unbuilt(inputs: #(spell, phase))
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
