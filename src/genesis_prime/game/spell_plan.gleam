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
////   (`SpellPhase.phaseDelay`). Any other spell has one go, at the end of its cast
////   time.
//// - **The cooldowns.** The spell's own is `Spell4.spellCoolDown` in
////   milliseconds. The global one is the row `spellCoolDownIdGlobal` names, in
////   effect only for kinds 0 and 1 and a non-zero row (`0x14046afc0`); kinds 0
////   and 2 are refused while it runs (`0x1403b14c0`).
//// - **The cost.** An ability with an innate cost the unit cannot pay is refused
////   with 50 + the resource slot: types 5 to 11 are slots 0 to 6 (Mind Burst,
////   type 6, is 51), and type 18 goes to the class's slots, the last one holding
////   that vital giving the result and none passing (Gamma Rays is 55)
////   (`0x1403b3320`, `0x1405e7980`, `Spell4CastResult.vital_cost`). Every
////   resource a new unit holds is 0 (`0x140454380`). Health (1), shield (3), focus
////   (15) and 16 give their own results (44, 176, 167, 177); any other type is an
////   `UnreadCost`.
//// - **No target.** None of the 18 level-1 abilities needs a target the client
////   picks (`Spell4TargetMechanics.targetType`), so the plan holds no range and
////   no target rule.
//// - **What fails the load:** a Spell4, Spell4Base, SpellCoolDown or Class row the
////   tree names that the tables lack, a cost of a type not read, and a cycle of
////   Proxy effects.

import genesis_prime/game/loadout
import genesis_prime/table/class
import genesis_prime/table/id.{
  type PrerequisiteId, type Spell4BaseId, type Spell4EffectsId, type Spell4Id,
  ClassId, PrerequisiteId, Spell4BaseId, Spell4EffectsId, Spell4Id,
  SpellCoolDownId,
}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
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
/// `cast.current_cast`), decided here for the methods the server casts.
pub type CastBar {
  /// A Normal spell with a cast time and a castBarType, or a Multiphase one with
  /// either.
  ShowsCastBar
  HidesCastBar
  /// The method's rule (Channeled by its root or channel record, PressHold always,
  /// ChargeRelease by its threshold, and so on) is not built: a press of such a
  /// spell is refused 285, and a tree a Normal press starts may not hold one.
  UndecidedCastBar
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

/// Which unit a Proxy's child cast is made on.
pub type ProxyTarget {
  /// The caster of the spell whose Proxy fired.
  OnCaster
  /// Each unit the go struck: a Proxy whose effect aims at the area
  /// (`Spell4Effects.targetFlags` 4), which starts one child for each Hit unit
  /// (genesis_prime/game/cast `went`).
  OnEachStruck
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
  /// The Proxy effects of a spell lead back to a spell on the way to it: the
  /// Spell4 ids from the pressed ability to the one that repeats.
  ProxyCycle(chain: List(Int))
  /// A spell's innate cost is of a type whose check the client's code was not
  /// read for (`0x1403b3320`).
  UnreadCost(spell4_id: Int, cost_type: Int)
  /// A tree a Normal press starts holds a spell whose cast method's cast bar rule
  /// is not built, so the server cannot say which cast the client counts as
  /// current.
  UnbuiltCastBar(spell4_id: Int, cast_method: Int)
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
    UnbuiltCastBar(spell4_id:, cast_method:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has the cast method "
      <> int.to_string(cast_method)
      <> ", whose cast bar rule is not built, in the tree of a Normal ability"
    UnreadCost(spell4_id:, cost_type:) ->
      "the Spell4 row "
      <> int.to_string(spell4_id)
      <> " has an innate cost of type "
      <> int.to_string(cost_type)
      <> ", which the client's check was not read for"
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

/// Builds every plan from the loaded tables, or why one cannot be built; the
/// derivation's body, and the function a test of a missing row or a cycle runs
/// on planted tables.
pub fn build(tables tables: table_store.Tables) -> Result(Plans, PlanError) {
  let effects = effects_by_spell(tables:)
  let phases = phases_by_owner(tables:)
  spell_level.all(tables)
  |> list.filter(loadout.is_level_one_ability)
  |> list.try_fold(dict.new(), fn(plans, row) {
    use spell <- result.try(
      spell_of(tables:, effects:, phases:, spell4_id: row.spell4_id, chain: []),
    )
    use Nil <- result.try(checked_cast_bars(spell:))
    Ok(dict.insert(plans, spell.spell4_base_id.value, spell))
  })
}

/// A Normal ability's tree holds no spell whose cast bar rule is not built: the
/// cast rule needs each cast's bar to know which cast is current. An ability of
/// another method is never cast (it is refused 285), so its tree is not held to it.
fn checked_cast_bars(spell spell: Spell) -> Result(Nil, PlanError) {
  case spell.method {
    Normal -> children_decided(spell:)
    Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | RapidTap
    | ChargeRelease
    | Multiphase
    | Transactional
    | OtherMethod(..) -> Ok(Nil)
  }
}

fn children_decided(spell spell: Spell) -> Result(Nil, PlanError) {
  list.try_each(spell.proxies, fn(proxy) {
    case proxy.spell.cast_bar {
      UndecidedCastBar ->
        Error(UnbuiltCastBar(
          spell4_id: proxy.spell.spell4_id.value,
          cast_method: method_number(method: proxy.spell.method),
        ))
      ShowsCastBar | HidesCastBar -> children_decided(spell: proxy.spell)
    }
  })
}

fn method_number(method method: CastMethod) -> Int {
  case method {
    Normal -> 0
    Channeled -> 1
    PressHold -> 2
    ChanneledField -> 3
    ClientSideInteraction -> 5
    RapidTap -> 6
    ChargeRelease -> 7
    Multiphase -> 8
    Transactional -> 9
    OtherMethod(id:) -> id
  }
}

fn effects_by_spell(
  tables tables: table_store.Tables,
) -> Dict(Int, List(spell4_effects.Spell4Effects)) {
  spell4_effects.all(tables)
  |> list.filter(fn(effect) { effect.effect_type == proxy_effect_type })
  |> list.group(fn(effect) { effect.spell_id })
  |> dict.map_values(fn(_, effects) {
    list.sort(effects, fn(first, second) {
      int.compare(first.order_index, second.order_index)
      |> order.break_tie(int.compare(first.id, second.id))
    })
  })
}

fn phases_by_owner(tables tables: table_store.Tables) -> Dict(Int, List(Int)) {
  spell_phase.all(tables)
  |> list.filter(fn(phase) {
    phase.order_index < max_phases
    && { phase.order_index == 0 || phase.phase_delay != 0 }
  })
  |> list.group(fn(phase) { phase.spell4_id_owner })
  |> dict.map_values(fn(_, phases) {
    list.reverse(phases) |> list.map(fn(phase) { phase.phase_delay })
  })
}

/// The effect type of a Proxy (`Spell4Effects.effectType.26`).
const proxy_effect_type = 26

/// The client keeps phase rows with an order index below 32 (`0x14055e180`).
const max_phases = 32

fn spell_of(
  tables tables: table_store.Tables,
  effects effects: Dict(Int, List(spell4_effects.Spell4Effects)),
  phases phases: Dict(Int, List(Int)),
  spell4_id spell4_id: Int,
  chain chain: List(Int),
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
  use unpayable_cost <- result.try(unpayable_cost_of(tables:, row:, base:))
  use proxies <- result.try(
    dict.get(effects, spell4_id)
    |> result.unwrap([])
    |> list.filter(fn(effect) { effect.data_bits00 != 0 })
    |> list.try_map(fn(effect) {
      use child <- result.try(spell_of(
        tables:,
        effects:,
        phases:,
        spell4_id: effect.data_bits00,
        chain:,
      ))
      Ok(Proxy(
        effect_id: Spell4EffectsId(effect.id),
        delay_ms: effect.delay_time,
        phase_flags: effect.phase_flags,
        condition: condition_of(effect:),
        target: target_of(effect:),
        spell: child,
      ))
    }),
  )
  let method = method_of(base.cast_method)
  use delays <- result.try(phase_delays(phases:, method:, spell4_id:))
  Ok(Spell(
    spell4_id: Spell4Id(spell4_id),
    spell4_base_id: Spell4BaseId(row.spell4_base_id_base_spell),
    method:,
    cast_time_ms: row.cast_time,
    cooldown_ms: row.spell_cool_down,
    cast_bar: cast_bar_of(method:, row:, base:),
    free_while_live: has_flag(flags: row.property_flags, bit: 0x40),
    ignores_casting: has_flag(flags: row.property_flags, bit: 0x10)
      || has_flag(flags: row.property_flags, bit: 0x1),
    weapon: weapon_of(base.weapon_slot),
    global_cooldown:,
    unpayable_cost:,
    phase_delays_ms: delays,
    proxies:,
  ))
}

/// Whether the client shows a cast bar for the spell, by its method
/// (`cast.current_cast`): Normal needs a cast time and a castBarType, Multiphase
/// either; the other methods' rules are not built.
fn cast_bar_of(
  method method: CastMethod,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
) -> CastBar {
  let has_bar = base.cast_bar_type != 0
  let has_time = row.cast_time != 0
  case method {
    Normal -> bar_if(shows: has_bar && has_time)
    Multiphase -> bar_if(shows: has_bar || has_time)
    Channeled
    | PressHold
    | ChanneledField
    | ClientSideInteraction
    | RapidTap
    | ChargeRelease
    | Transactional
    | OtherMethod(..) -> UndecidedCastBar
  }
}

fn bar_if(shows shows: Bool) -> CastBar {
  use <- bool.guard(when: shows, return: ShowsCastBar)
  HidesCastBar
}

/// The phase delays of a spell: a Multiphase spell's SpellPhase rows the client
/// keeps, which it must have, and none for any other method.
fn phase_delays(
  phases phases: Dict(Int, List(Int)),
  method method: CastMethod,
  spell4_id spell4_id: Int,
) -> Result(List(Int), PlanError) {
  case method {
    Multiphase ->
      case dict.get(phases, spell4_id) {
        Ok([_, ..] as delays) -> Ok(delays)
        Ok([]) | Error(Nil) -> Error(NoRow(table: "SpellPhase", id: spell4_id))
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

/// A Proxy aimed at the area (`targetFlags` bit 4) starts its child on each struck
/// unit, any other on the caster (`Spell4Effects.targetFlags`).
fn target_of(effect effect: spell4_effects.Spell4Effects) -> ProxyTarget {
  use <- bool.guard(
    when: !has_flag(flags: effect.target_flags, bit: 4),
    return: OnCaster,
  )
  OnEachStruck
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

/// The result of the first of the spell's two innate costs that a unit holding
/// nothing cannot pay.
fn unpayable_cost_of(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
) -> Result(Option(Int), PlanError) {
  use first <- result.try(cost_result(
    tables:,
    row:,
    base:,
    cost_type: row.innate_cost_type0,
    cost: row.innate_cost0,
  ))
  case first {
    Some(_) -> Ok(first)
    None ->
      cost_result(
        tables:,
        row:,
        base:,
        cost_type: row.innate_cost_type1,
        cost: row.innate_cost1,
      )
  }
}

fn cost_result(
  tables tables: table_store.Tables,
  row row: spell4.Spell4,
  base base: spell4_base.Spell4Base,
  cost_type cost_type: Int,
  cost cost: Int,
) -> Result(Option(Int), PlanError) {
  case cost_type {
    0 -> Ok(None)
    _ if cost == 0 || cost_type > 30 -> Ok(None)
    1 -> Ok(Some(44))
    3 -> Ok(Some(176))
    15 -> Ok(Some(167))
    16 -> Ok(Some(177))
    slot if slot >= 5 && slot <= 11 -> Ok(Some(50 + slot - 5))
    18 -> class_cost_result(tables:, base:, vital: cost_type)
    _ -> Error(UnreadCost(spell4_id: row.id, cost_type:))
  }
}

/// The class mechanic's check of a cost in a vital that has no fixed slot: the
/// last of the class's slots holding the vital gives 50 + its number (177 for
/// slot 7), and a class with no slot for it passes (`0x1405e7980`).
fn class_cost_result(
  tables tables: table_store.Tables,
  base base: spell4_base.Spell4Base,
  vital vital: Int,
) -> Result(Option(Int), PlanError) {
  use class_row <- result.try(
    class.get(tables:, id: ClassId(base.class_id_player))
    |> result.replace_error(NoRow(table: "Class", id: base.class_id_player)),
  )
  let slots = [
    class_row.vital_enum_resource00,
    class_row.vital_enum_resource01,
    class_row.vital_enum_resource02,
    class_row.vital_enum_resource03,
    class_row.vital_enum_resource04,
    class_row.vital_enum_resource05,
    class_row.vital_enum_resource06,
    class_row.vital_enum_resource07,
  ]
  let matching =
    list.index_map(slots, fn(slot_vital, slot) { #(slot, slot_vital) })
    |> list.filter(fn(pair) { pair.1 == vital })
    |> list.map(fn(pair) { pair.0 })
  case list.last(matching) {
    Error(Nil) -> Ok(None)
    Ok(7) -> Ok(Some(177))
    Ok(slot) -> Ok(Some(50 + slot))
  }
}

fn has_flag(flags flags: Int, bit bit: Int) -> Bool {
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

/// The time of each phase's go after the start of a cast of the spell, in
/// milliseconds: the running sum of its phase delays; the cast time for a spell
/// that is not Multiphase, which has the one go.
pub fn go_times_ms(spell spell: Spell) -> List(Int) {
  case spell.phase_delays_ms {
    [] -> [spell.cast_time_ms]
    delays -> list.scan(delays, 0, fn(elapsed, delay) { elapsed + delay })
  }
}

/// The Proxies of the spell that fire in phase `phase`.
pub fn proxies_in_phase(spell spell: Spell, phase phase: Int) -> List(Proxy) {
  let bit = int.bitwise_shift_left(1, phase)
  list.filter(spell.proxies, fn(proxy) {
    int.bitwise_and(proxy.phase_flags, bit) != 0
  })
}
