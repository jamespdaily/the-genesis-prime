//// What the cast rule's tests share: the abilities as the plan holds them, built
//// from the client's rows the fact file records (each value named where it is
//// set), a caster, the bytes of the client's presses and cancels, and helpers
//// that find the writes, the tells and the timers in a step's effects.
////
//// Four spells are planted, not client rows, because no level-1 ability has
//// global cooldown kind 2, a cast bar that lets a press through, a cast time
//// with a cooldown of its own, or a cast method the rule does not cast:
//// `blocked_only` (kind 2), `exempt`, `slow` and `unbuilt` (PressHold).

import attacker_support
import class_resource_support
import client_tables
import fixture_tables
import game_client
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/game/cast
import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/cast/press as cast_press
import genesis_prime/game/cast/proc as cast_proc
import genesis_prime/game/cast/state.{type Caster, type Effect, type State} as cast_state
import genesis_prime/game/cast/tick as cast_tick
import genesis_prime/game/heal_split
import genesis_prime/game/quest_advance
import genesis_prime/game/start_place
import genesis_prime/message/cancel_cast.{CancelCast}
import genesis_prime/message/cast_result.{type CastResult}
import genesis_prime/message/client_side_interaction_result.{
  ClientSideInteractionResult,
}
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/float32
import genesis_prime/message/interaction_result
import genesis_prime/message/spell_cast_confirmed
import genesis_prime/message/spell_cast_refused
import genesis_prime/message/spell_damage_description.{
  type SpellDamageDescription, SpellDamageDescription,
}
import genesis_prime/message/spell_effect_bit.{SpellEffectBit}
import genesis_prime/message/spell_effect_damage
import genesis_prime/message/spell_effect_info.{
  type SpellEffectInfo, SpellEffectInfo,
}
import genesis_prime/message/spell_effect_result
import genesis_prime/message/spell_finished
import genesis_prime/message/spell_go
import genesis_prime/message/spell_stack_removed
import genesis_prime/message/spell_started
import genesis_prime/message/spell_target_info.{
  type SpellTargetInfo, SpellTargetInfo,
}
import genesis_prime/message/spell_targets_removed
import genesis_prime/shared/activate
import genesis_prime/shared/area.{type Pose}
import genesis_prime/shared/class_resource
import genesis_prime/shared/damage
import genesis_prime/shared/effect_kind
import genesis_prime/shared/hit
import genesis_prime/shared/lasting.{LastingRow}
import genesis_prime/shared/lasts
import genesis_prime/shared/look.{type Disguise, Disguise}
import genesis_prime/shared/player_change
import genesis_prime/shared/prerequisite
import genesis_prime/shared/spell_area
import genesis_prime/shared/spell_effect
import genesis_prime/shared/spell_plan.{
  type Plans, type Spell, Always, AtFirstGo, GlobalCooldown, KeepsStealth,
  NoWeaponNeeded, Normal, Spell, StealthRow,
}
import genesis_prime/shared/spend
import genesis_prime/shared/strike_tell
import genesis_prime/shared/target_mechanic
import genesis_prime/shared/ticking
import genesis_prime/shared/unit_news.{type News}
import genesis_prime/shared/unit_properties
import genesis_prime/shared/worn_visual.{WornVisual}
import genesis_prime/step.{type LogLevel, type Now, type TimerId, Now, TimerId}
import genesis_prime/table/creature2
import genesis_prime/table/id.{
  type Spell4BaseId, type Spell4EffectsId, Creature2Id, Item2Id, ItemDisplayId,
  ItemSlotId, Spell4BaseId, Spell4EffectsId, Spell4Id, UnitProperty2Id,
}
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import place_support
import quest_support
import spell_tables

/// A planted spell of the Spell4 and base given, holding the lasting rows of the client's
/// spell of that Spell4 that have these effect ids: the cast rule reads the rows, the
/// planted spell only gives them a base the bag holds.
pub fn client_lasting(
  spell4_id spell4_id: Int,
  base base: Int,
  effect_ids effect_ids: List(Int),
) -> Spell {
  let rows =
    list.filter(
      spell_plan.payloads(
        spell: spell_tables.client_spell(spell4_id:),
        as_kind: spell_plan.as_lasting,
      ),
      fn(row) { list.contains(effect_ids, row.effect_id.value) },
    )
  assert list.length(rows) == list.length(effect_ids)
    as "the client's spell holds each of the rows"
  with_effects(
    spell: child(spell4_id:, base:),
    kinds: list.map(rows, spell_plan.LastingEffect),
  )
}

/// The spell with its effects of the kinds given replaced by these, the effects of its other
/// kinds kept, all ranked as a plan's are. A kind is told by its rank, so an empty list
/// replaces nothing: a spell loses a kind with `without_effects`.
pub fn with_effects(
  spell spell: Spell,
  kinds kinds: List(spell_plan.Kind),
) -> Spell {
  let ranks = list.map(kinds, spell_plan.kind_rank)
  Spell(
    ..spell,
    effects: spell_plan.ranked(effects: list.append(
      list.filter(spell.effects, fn(planned) {
        !list.contains(ranks, spell_plan.kind_rank(planned.kind))
      }),
      list.map(kinds, spell_plan.effect_of),
    )),
  )
}

/// The spell without its effects of the kind `as_kind` reads.
pub fn without_effects(
  spell spell: Spell,
  as_kind as_kind: fn(spell_plan.Kind) -> Result(payload, Nil),
) -> Spell {
  Spell(
    ..spell,
    effects: list.filter(spell.effects, fn(planned) {
      result.is_error(as_kind(planned.kind))
    }),
  )
}

/// A child spell the client's row gives these ids: no cast time, no cooldown, no
/// range, kind 3 (`opcode.0x7ff.root_parent`: the global cooldown kind of every
/// child of the nine abilities), and the dead bit of caster condition row 1, which
/// most of those children name (`Spell4.spell4ConditionsIdCaster`).
pub fn child(spell4_id spell4_id: Int, base base: Int) -> Spell {
  Spell(
    spell4_id: Spell4Id(spell4_id),
    spell4_base_id: Spell4BaseId(base),
    school: 0,
    targeting: target_mechanic.at_the_caster,
    method: Normal,
    cast_time_ms: 0,
    cooldown_ms: 0,
    cast_bar: spell_plan.HidesCastBar,
    free_while_live: False,
    ignores_casting: False,
    longer_of_delay_and_duration: False,
    outlives_caster: False,
    aura_ms: None,
    weapon: NoWeaponNeeded,
    caster_death: spell_plan.CannotBeDead,
    target_death: spell_plan.AliveOrDead,
    caster_cc_mask: 0,
    target_cc_mask: 0,
    target_aim: spell_plan.TargetAim(
      limits: spell_plan.Limits(min: 0.0, max: 35.0, vertical: -1.0),
      combat: spell_plan.CombatAllowed,
      cast_group_id: 0,
      unread: None,
      pets: spell_plan.PetBits(must_be_pet: False, must_be_master: False),
      facing: spell_plan.FacesAnywhere,
    ),
    global_cooldown: GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: None,
    ),
    costs: [],
    requirements: [],
    caster_cast: spell_plan.NoCasterCast,
    target_cast: None,
    caster_persistence: None,
    target_persistence: None,
    phase_delays_ms: [],
    threshold_ms: 0,
    stages: [],
    channel: None,
    effects: [],
    groups: [],
    stack: lasting.Stack(group_id: 0, cap: 0),
    cooldown_groups: [],
    dropped_controls: [],
    stealth_change: spell_plan.EndsStealthAtEachGo,
    alternate: None,
    press_proxies: [],
    cooldown_start: AtFirstGo,
    cooldown_phase: None,
    struck_gates: [],
  )
}

/// The Spell4 Healing Salve's two Proc rows cast (`table_rows -- Spell4Effects 86457 86458`).
pub const salve_proc_spell4_id = 39_127

/// A Proc row held by `holder` as Healing Salve's 86457 and 86458 are (Spell4 39386, kind 16 takes
/// damage, chance 1.0, once in 2000 ms, casting Spell4 39127, targetFlags 4 and 1), living as
/// `row` says: the id, the unit that holds it and the life it gives.
pub fn held_proc_row(
  id id: Int,
  holder holder: spell_plan.ProcHolder,
  row row: lasting.LastingRow,
) -> spell_plan.ProcRow {
  spell_plan.ProcRow(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    holder:,
    trigger: spell_plan.TakesDamage,
    spell: child(spell4_id: salve_proc_spell4_id, base: salve_proc_spell4_id),
    chance: 1.0,
    limit: spell_plan.InWindow(window_ms: 2000, count: 1),
    filter: spell_plan.AnySpell,
    aim: spell_plan.AtHolder,
    event_gate: None,
    holder_gate: None,
    delay_ms: 0,
    row:,
    condition: Always,
    tag: spend.always,
  )
}

/// A planted spell with a cast time of 1000 ms and a cast bar whose live cast
/// leaves the caster free to press another (`0x1403afb10`).
pub fn exempt() -> Spell {
  Spell(
    ..child(spell4_id: 1, base: 1),
    cast_time_ms: 1000,
    cast_bar: spell_plan.ShowsCastBar,
    free_while_live: True,
  )
}

/// A Stealth row as 83834 holds it (until removed, no delay), with this effect id and
/// whether damage ends it.
pub fn stealth_row(
  id id: Int,
  breaks breaks: spell_plan.Breaks,
) -> spell_plan.StealthRow {
  StealthRow(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    breaks:,
    row: LastingRow(delay_ms: 0, lasts: lasts.UntilRemoved),
    condition: Always,
    tag: spend.always,
  )
}

/// A spell that holds these Stealth rows and, like the toggle's own spells, ends no
/// stealth (value 2).
pub fn stealthing(
  spell4_id spell4_id: Int,
  base base: Int,
  rows rows: List(spell_plan.StealthRow),
) -> Spell {
  Spell(
    ..with_effects(
      spell: child(spell4_id:, base:),
      kinds: list.map(rows, spell_plan.StealthEffect),
    ),
    stealth_change: KeepsStealth,
  )
}

/// A planted spell of global cooldown kind 2: refused while it runs, starting none.
pub fn blocked_only() -> Spell {
  Spell(
    ..child(spell4_id: 2, base: 2),
    global_cooldown: GlobalCooldown(
      refused_while_running: True,
      starts_for_ms: None,
    ),
  )
}

/// A planted spell with a cast time of 1000 ms and a cooldown of 5000 ms, kind 3,
/// for the rule that the spell's own cooldown runs from its first go.
pub fn slow() -> Spell {
  Spell(..child(spell4_id: 3, base: 3), cast_time_ms: 1000, cooldown_ms: 5000)
}

/// The abilities by bag index, as Spell4Base ids: 0 Telekinetic Strike, 1 Crush,
/// 2 Mind Burst, 3 Kick, 4 Stagger, 5 Gate, 6 Gamma Rays, 7 Electrocute, 8 the
/// exempt spell, 9 Zap, 10 the kind 2 spell, 11 the slow spell, 12 Pulse Blast,
/// 13 Quick Draw, 14 Discharge, 15 Shred, 16 Relentless Strikes, 17 Rampage,
/// 18 Charged Shot, 19 Impale and 20 the PressHold spell.
pub fn abilities() -> List(Spell4BaseId) {
  list.map(
    [
      19_102, 19_022, 19_019, 38_017, 23_173, 20_325, 16_322, 25_473, 1, 25_635,
      2, 3, 26_468, 27_638, 38_201, 23_148, 18_309, 37_968, 20_684, 23_161, 4,
    ],
    Spell4BaseId,
  )
}

pub const electrocute = 7

/// The bag index of the base 3 ability that `plans_starting_on_each_struck` plants.
pub const started_bag_index = 11

pub const pulse_blast = 12

pub const quick_draw = 13

pub const discharge = 14

pub const shred = 15

pub const relentless_strikes = 16

pub const rampage = 17

pub const charged_shot = 18

pub const impale = 19

pub const unbuilt_bag_index = 20

/// A planted spell of the PressHold method, which the rule does not cast
/// (`Spell.CodeEnumCastMethod`).
pub fn unbuilt() -> Spell {
  Spell(..child(spell4_id: 4, base: 4), method: spell_plan.PressHold)
}

/// The plans of the abilities above: the client's trees as `spell_plan.build`
/// makes them from the client's rows, and the three planted spells by hand.
pub fn plans() -> Plans {
  with_spells(plans: spell_tables.fixture_plans(), spells: [
    exempt(),
    blocked_only(),
    slow(),
    unbuilt(),
  ])
}

/// The plans with these spells in place of the ability of the same Spell4Base id.
pub fn with_spells(plans plans: Plans, spells spells: List(Spell)) -> Plans {
  list.fold(spells, plans, fn(plans, spell) {
    dict.insert(plans, spell.spell4_base_id.value, spell)
  })
}

/// The plans with these spells in place of the ability of the same Spell4Base id.
pub fn plans_of(spells: List(Spell)) -> Plans {
  with_spells(plans: plans(), spells:)
}

/// The plans with this spell in place of the ability of the same Spell4Base id.
pub fn plans_with(spell spell: Spell) -> Plans {
  plans_of([spell])
}

/// The Spell4 id of the planted base 3 ability of `plans_starting_on_each_struck`.
pub const parent_spell4_id = 90_001

/// The plans in which the base 3 ability starts `started` on each unit its go struck,
/// through a Proxy aimed at each struck unit (`ProxyTarget.OnEachStruck`). A press gives a
/// cast no primary target but the caster (`Spell4TargetMechanics.targetType`), so a cast
/// whose primary target is another unit is a child a Proxy starts: its primary target is
/// the struck unit.
pub fn plans_starting_on_each_struck(started started: Spell) -> Plans {
  plans_with(
    spell: spell_plan.with_proxies(
      spell: child(spell4_id: parent_spell4_id, base: 3),
      proxies: [
        spell_plan.Proxy(
          period: None,
          effect_id: Spell4EffectsId(90_002),
          delay_ms: 0,
          phase_flags: -1,
          condition: Always,
          tag: spend.always,
          target: spell_plan.OnEachStruck,
          spell: started,
          gains: [],
        ),
      ],
    ),
  )
}

/// The effect ids each unit's entry lists in the go of the child that
/// `plans_starting_on_each_struck` started, by unit, in unit order: the one go of the effects
/// that is not the press's own.
pub fn child_go_listing(
  effects effects: List(Effect),
) -> List(#(Int, List(Int))) {
  let press = pressed_id(effects:)
  let decoded =
    list.map(frames_of(message_id: spell_go.message_id, effects:), fn(frame) {
      let assert Ok(go) = spell_go.decode(frame.body)
        as "a 0x7f4 the rule wrote decodes"
      go
    })
  let assert [child] = list.filter(decoded, fn(go) { go.cast_id != press })
    as "one go is the started child's"
  list.map(child.targets, fn(info) {
    #(
      info.unit_id,
      list.map(info.effects, fn(effect) { effect.spell4_effects_id })
        |> list.sort(int.compare),
    )
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

/// The plans the client's own tables build.
pub fn real_plans() -> Plans {
  spell_plan.plans(client_tables.shared())
}

/// A planted spell of Spell4 `spell4_id` and base `base` that goes at once and holds
/// these property rows.
pub fn spell_holding(
  spell4_id spell4_id: Int,
  base base: Int,
  modifiers modifiers: List(spell_plan.PropertyModifier),
) -> Spell {
  with_effects(
    spell: child(spell4_id:, base:),
    kinds: list.map(modifiers, spell_plan.ModifierEffect),
  )
}

/// The ability of the Spell4Base id as the plans hold it.
pub fn ability(base base: Int) -> Spell {
  ability_in(plans: plans(), base:)
}

/// The ability of the Spell4Base id in these plans.
pub fn ability_in(plans plans: Plans, base base: Int) -> Spell {
  let assert Ok(spell) = spell_plan.in_plans(plans:, base: Spell4BaseId(base))
    as "the plans hold the ability"
  spell
}

/// The plan of the Spell4Base as the one spell the player's standing spells become
/// (`cast.standing_changed`): what the entry's innate passive is.
pub fn standing_started(
  cast cast: State,
  caster caster: Caster,
  plans plans: Plans,
  base base: Spell4BaseId,
  now now: Now,
) -> #(State, List(Effect)) {
  let assert Ok(spell) = spell_plan.in_plans(plans:, base:)
    as "the plans hold the spell that stands"
  cast.standing_changed(
    cast:,
    caster:,
    wanted: without_item(spells: [spell]),
    now:,
  )
}

/// The spells as standing spells that come from no item, as the innate passive does.
pub fn without_item(spells spells: List(Spell)) -> List(cast_state.Standing) {
  list.map(spells, fn(spell) { cast_state.Standing(spell:, from: None) })
}

/// The effect id of the row `row` of the planted standing spell `spell4_id` (250000 to
/// 250999), which fits the 19 bits of a Spell4Effects id.
fn standing_effect_id(
  spell4_id spell4_id: Int,
  row row: Int,
) -> Spell4EffectsId {
  Spell4EffectsId(100_000 + { spell4_id - 250_000 } * 10 + row)
}

/// The effect id of the property modifier of the planted standing spell `spell4_id`
/// (`standing_spell`).
pub fn standing_modifier_id(spell4_id spell4_id: Int) -> Spell4EffectsId {
  standing_effect_id(spell4_id:, row: 1)
}

/// A planted spell that goes at once and holds one property modifier until removed, as
/// the innate passives do (Spell4Effects 103997): its cast lingers with its node.
pub fn standing_spell(spell4_id spell4_id: Int) -> Spell {
  spell_holding(spell4_id:, base: spell4_id, modifiers: [
    spell_plan.PropertyModifier(
      effect_id: standing_modifier_id(spell4_id:),
      phase_flags: -1,
      change: spell_plan.PropertyChange(unit_properties.Change(
        property: UnitProperty2Id(141),
        mode: 3,
        multiplier: 1.0,
        flat: 0.0,
        per_level: 0.0,
      )),
      row: LastingRow(delay_ms: 0, lasts: lasts.UntilRemoved),
      condition: spell_plan.Always,
      tag: spend.always,
      armor: None,
    ),
  ])
}

/// The planted standing spell with a Proc row until removed (effect row 2,
/// the trigger given, casting `casts`, once in 500 ms) and a Proxy to a child that waits
/// 5000 ms (effect row 3, Spell4 `spell4_id + 500`), the rows the Stalker's
/// passive holds (Spell4Effects 147119 and 147125).
pub fn standing_holder(
  spell4_id spell4_id: Int,
  fires_on trigger: spell_plan.Trigger,
  casts casts: Spell,
) -> Spell {
  with_effects(spell: standing_spell(spell4_id:), kinds: [
    spell_plan.ProcEffect(spell_plan.ProcRow(
      effect_id: standing_effect_id(spell4_id:, row: 2),
      phase_flags: -1,
      holder: spell_plan.HeldByCaster,
      trigger:,
      spell: casts,
      chance: 1.0,
      limit: spell_plan.InWindow(window_ms: 500, count: 1),
      filter: spell_plan.AnySpell,
      aim: spell_plan.AtHolder,
      event_gate: None,
      holder_gate: None,
      delay_ms: 0,
      row: LastingRow(delay_ms: 0, lasts: lasts.UntilRemoved),
      condition: spell_plan.Always,
      tag: spend.always,
    )),
    spell_plan.ProxyEffect(
      spell_plan.Proxy(
        period: None,
        effect_id: standing_effect_id(spell4_id:, row: 3),
        delay_ms: 5000,
        phase_flags: -1,
        condition: spell_plan.Always,
        tag: spend.always,
        target: spell_plan.OnCaster,
        spell: child(spell4_id: spell4_id + 500, base: spell4_id + 500),
        gains: [],
      ),
    ),
  ])
}

/// The player 7 with the abilities above and its weapon, standing at the live character's place, holding `full_slot_1`.
pub fn caster() -> Caster {
  let place = place_support.live_character_place()
  cast_state.Caster(
    unit_id: 7,
    place:,
    abilities: abilities(),
    book: list.append(abilities(), [Spell4BaseId(52_215), Spell4BaseId(20_685)]),
    surge_spell: Spell4Id(47_439),
    weapon: Some(Item2Id(81_351)),
    players_in_sight: dict.new(),
    other_players: dict.new(),
    hit_radius: place_support.player_hit_radius,
    pvp_flagged: False,
    group_id: 0,
    dead: False,
    resources: class_resource_support.new(resource: full_slot_1()),
    in_combat: False,
    life_vitals: dict.new(),
    factions: prerequisite.Factions(current: 167, base: 167),
    stats: attacker_support.fresh(),
    vitals: damage.Vitals(health: 0, max_health: 0, shield: 0, max_shield: 0),
    heal_scaling: heal_split.unscaled,
    quests: quest_support.view_of(rows: []),
    player: prerequisite.Player(
      race_id: 1,
      class_id: 1,
      level: 1,
      path: 0,
      gender: 0,
      world_id: 3460,
      zones: [],
    ),
    checker: prerequisite.Checker(items: [], book: [], world_difficulty: 0),
  )
}

/// What a unit is to a caster whose picture shows nothing: unseen.
pub fn nothing_shown(_unit_id: Int) -> activate.Target {
  activate.Unseen
}

/// The same player dead, as the connection builds it when it tells the rule of its
/// death (`genesis_prime/game/connection/casting.caster_of`).
pub fn dead_caster() -> Caster {
  cast_state.Caster(..caster(), dead: True)
}

/// A planted resource of 1000 points in slot 1, full: it meets every level-1 cost
/// and requirement of slot 1 (Mind Burst's 1, Electrocute's 8, Gamma Rays' 2,
/// Rampage's at least 250), so a test that is not about resources is not refused
/// for one, and holds nothing in slot 3 (Impale's 35). Its slots name the Medic's
/// vitals (Class 4), so a type 18 cost such as Gamma Rays' reads the same slots.
pub fn full_slot_1() -> class_resource.Resource {
  class_resource.Resource(
    slot: 1,
    vitals: class_resource_support.resource_of(4).vitals,
    max: 1000.0,
    start: 1000.0,
    regen: None,
    refill_after_combat_ms: None,
    drain: None,
    empty_after_combat_ms: None,
    focus: None,
  )
}

/// The caster holding `resources` in place of `full_slot_1`.
pub fn caster_holding(resources resources: class_resource.Resources) -> Caster {
  cast_state.Caster(..caster(), resources:)
}

/// The class's resource with its slot at `value`.
pub fn holding(
  class_id class_id: Int,
  value value: Float,
) -> class_resource.Resources {
  holding_changing(class_id:, value:, changes: [])
}

/// The class's resource holding `focus` points of Focus, a pool of that size (property 5
/// at `focus`), and its slot at its start; a class that holds no Focus holds none.
pub fn holding_focus(
  class_id class_id: Int,
  focus focus: Float,
) -> class_resource.Resources {
  class_resource_support.resources_with(
    class_id:,
    changes: [#(5, focus)],
    level: 1,
  )
}

/// The result of each 0x7fc the effects write, in order.
pub fn refusals(effects effects: List(Effect)) -> List(CastResult) {
  list.filter_map(writes(effects:), fn(frame) {
    case frame.message_id == spell_cast_refused.message_id {
      True -> {
        let assert Ok(refused) = spell_cast_refused.decode(frame.body)
          as "a 0x7fc the rule wrote decodes"
        Ok(refused.result)
      }
      False -> Error(Nil)
    }
  })
}

/// The same as the client's numbers.
pub fn refusal_results(effects effects: List(Effect)) -> List(Int) {
  list.map(refusals(effects:), cast_result.to_value)
}

/// What the presses of a step paid, in order.
pub fn payments(effects effects: List(Effect)) -> List(class_resource.Payment) {
  list.flat_map(effects, fn(effect) {
    case effect {
      cast_state.Pay(payments:) -> payments
      _ -> []
    }
  })
}

/// The `ShortcutCast` effects among the effects, each as the effect itself, in order.
pub fn shortcut_casts(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      cast_state.ShortcutCast(..) -> True
      _ -> False
    }
  })
}

/// The `QuestAdvanced` effects among the effects, each as its advances and the use or cast
/// they were made with, in order.
pub fn quest_advances(
  effects effects: List(Effect),
) -> List(#(List(quest_advance.Advance), cast_state.AdvanceWith)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.QuestAdvanced(advances:, with:) -> Ok(#(advances, with))
      _ -> Error(Nil)
    }
  })
}

/// The `Gain` effects of the steps, each its list of gains, in order.
pub fn gains(effects effects: List(Effect)) -> List(List(class_resource.Gain)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.Gain(gains:, ..) -> Ok(gains)
      _ -> Error(Nil)
    }
  })
}

/// The sources whose property modifier the effects end, in order.
pub fn caster_change_ends(
  effects effects: List(Effect),
) -> List(unit_properties.Source) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.CasterChangeEnds(source:) -> Ok(source)
      _ -> Error(Nil)
    }
  })
}

/// The changes of the caster's own that the effects start, with their sources, in order.
pub fn caster_change_starts(
  effects effects: List(Effect),
) -> List(#(unit_properties.Source, cast_state.CasterChange)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.CasterChangeStarts(source:, change:) -> Ok(#(source, change))
      _ -> Error(Nil)
    }
  })
}

/// The source of the effect row `effect_id` of the cast `cast_id`.
pub fn source_of(
  cast_id cast_id: Int,
  effect_id effect_id: Int,
) -> unit_properties.Source {
  unit_properties.Source(cast_id:, effect_id: Spell4EffectsId(effect_id))
}

/// The property modifiers of the caster that the effects start, with their sources, in order.
pub fn property_starts(
  effects effects: List(Effect),
) -> List(#(unit_properties.Source, unit_properties.Modifier)) {
  list.filter_map(caster_change_starts(effects:), fn(start) {
    case start.1 {
      cast_state.HeldChange(player_change.Property(modifier:)) ->
        Ok(#(start.0, modifier))
      cast_state.Heal(..)
      | cast_state.Look(..)
      | cast_state.HeldChange(player_change.Absorb(..)) -> Error(Nil)
    }
  })
}

/// The property modifiers the effects start on creatures or end on them, in order.
pub fn target_changes(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      cast_state.TargetChangeStarts(..) | cast_state.TargetChangeEnds(..) ->
        True
      _ -> False
    }
  })
}

/// The time each step's effects were taken at, with each property modifier they start
/// on a creature or end on it, in order.
pub fn target_timeline(
  fired fired: List(#(Int, List(Effect))),
) -> List(#(Int, Effect)) {
  timeline_of(fired:, pick: target_changes)
}

/// The time each step's effects were taken at, with each item `pick` finds in them, in order.
pub fn timeline_of(
  fired fired: List(#(Int, List(Effect))),
  pick pick: fn(List(Effect)) -> List(a),
) -> List(#(Int, a)) {
  list.flat_map(fired, fn(step) {
    list.map(pick(step.1), fn(found) { #(step.0, found) })
  })
}

/// The throws the effects tell creatures, in order.
pub fn throws(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      cast_state.ForcedMoveStarts(..) -> True
      _ -> False
    }
  })
}

/// The removals the effects tell creatures, in order.
pub fn despawns(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      cast_state.CreatureDespawns(..) -> True
      _ -> False
    }
  })
}

/// The unit states the effects tell creatures to hold, in order.
pub fn unit_states_told(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      cast_state.CreatureHoldsUnitStates(..) -> True
      _ -> False
    }
  })
}

/// The crowd-control states the effects tell creatures to end, in order.
pub fn controls_ended(effects effects: List(Effect)) -> List(Effect) {
  list.filter(effects, fn(effect) {
    case effect {
      cast_state.CreatureControlsEnd(..) -> True
      _ -> False
    }
  })
}

/// The time each step's effects were taken at, with each throw they tell, in order.
pub fn throw_timeline(
  fired fired: List(#(Int, List(Effect))),
) -> List(#(Int, Effect)) {
  timeline_of(fired:, pick: throws)
}

/// The delay of each timer the effects start, in order.
pub fn delays_of(effects effects: List(Effect)) -> List(Int) {
  list.map(started_timers(effects:), fn(started) { started.1 })
}

/// The time each step's effects were taken at, with a change of the caster starting
/// ("start") or ending ("end"), in order.
pub fn timeline(
  fired fired: List(#(Int, List(Effect))),
) -> List(#(Int, String, unit_properties.Source)) {
  list.flat_map(fired, fn(step) {
    list.flatten([
      list.map(caster_change_starts(effects: step.1), fn(start) {
        #(step.0, "start", start.0)
      }),
      list.map(caster_change_ends(effects: step.1), fn(source) {
        #(step.0, "end", source)
      }),
    ])
  })
}

/// The numbers of these timers, sorted.
pub fn timer_numbers(timers timers: List(TimerId)) -> List(Int) {
  list.map(timers, timer_number) |> list.sort(int.compare)
}

/// The input time: a monotonic time, the system time 0.
pub fn at(ms ms: Int) -> Now {
  Now(monotonic_ms: ms, filetime: 0)
}

/// What the connection does after each input: the held procs fire for the events the input
/// raised (`cast.procs_fire`), every chance draw and gate roll the word 0, so a chance is
/// met and a roll is its lowest. The pass's effects follow the input's; a fire's own go is
/// the caller's to answer.
pub fn then_procs(
  step step: #(State, List(Effect)),
  caster caster: Caster,
  at ms: Int,
) -> #(State, List(Effect)) {
  then_procs_known(
    step:,
    caster:,
    at: ms,
    poses: dict.new(),
    units: dict.new(),
    drawn: None,
  )
}

/// The same, each chance draw and gate roll taken from these lists in the order the
/// procs are matched (`cast_proc.proc_draws_needed`).
pub fn then_procs_drawn(
  step step: #(State, List(Effect)),
  caster caster: Caster,
  at ms: Int,
  draws draws: List(Int),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  then_procs_known(
    step:,
    caster:,
    at: ms,
    poses: dict.new(),
    units: dict.new(),
    drawn: Some(#(draws, rolls)),
  )
}

/// The same, with the poses and the kinds the caster's picture knows the event units to
/// be; `drawn` is none for words of 0.
pub fn then_procs_known(
  step step: #(State, List(Effect)),
  caster caster: Caster,
  at ms: Int,
  poses poses: dict.Dict(Int, Pose),
  units units: dict.Dict(Int, prerequisite.FirstUnit),
  drawn drawn: Option(#(List(Int), List(Int))),
) -> #(State, List(Effect)) {
  let #(state, effects) = step
  case cast_proc.has_pending(cast: state) {
    False -> step
    True -> {
      let #(words, rolls) = cast_proc.proc_draws_needed(cast: state)
      let #(draws, rolls) = case drawn {
        Some(given) -> given
        None -> #(list.repeat(0, words), list.repeat(0, rolls))
      }
      let #(state, fired) =
        cast.procs_fire(
          cast: state,
          caster:,
          now: at(ms:),
          poses:,
          indexes: dict.new(),
          units:,
          draws:,
          rolls:,
        )
      #(state, list.append(effects, fired))
    }
  }
}

/// The body of the client's 0x9a (opcode.0x9a): its cast id, the bag index, the
/// target and the press bit.
pub fn press_body(
  client_cast_id client_cast_id: Int,
  bag_index bag_index: Int,
  target target: Int,
  press press: Int,
) -> BitArray {
  game_client.press_body(client_cast_id:, bag_index:, target:, press:)
}

/// The body of the client's 0x4db (opcode.0x4db): the bag index, the target and
/// the held bit.
pub fn hold_body(
  bag_index bag_index: Int,
  target target: Int,
  held held: Int,
) -> BitArray {
  game_client.hold_body(bag_index:, target:, held:)
}

/// The key of the bag index goes down (`held` 1) or up (`held` 0) at the time, for
/// the abilities of the plans given, taken by the rule; it must be taken, not
/// refused. A go it asks for is a `Strike` effect, not yet written.
pub fn key_raw_in(
  plans plans: Plans,
  state state: State,
  bag_index bag_index: Int,
  held held: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let assert Ok(taken) =
    cast.take(
      target_of: nothing_shown,
      cast: state,
      message: cast_state.KeyHeld,
      body: hold_body(bag_index:, target: 0, held:),
      caster: caster(),
      plans:,
      now: at(ms:),
    )
    as "a 0x4db that fits the message is taken"
  taken
}

/// The same, with each go answered as a round that struck nobody.
pub fn key_in(
  plans plans: Plans,
  state state: State,
  bag_index bag_index: Int,
  held held: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) = key_raw_in(plans:, state:, bag_index:, held:, at: ms)
  answered_with_no_targets(state:, effects:, at: ms)
}

/// The plans with Mind Burst (bag index 2) costless: it costs 1 Psi Point
/// (`Spell4CastResult.vital_cost`), and a test of the repeat is not about paying it.
/// Every other value is the client's row.
pub fn plans_with_costless_mind_burst() -> Plans {
  with_spells(plans: plans(), spells: [
    Spell(..ability(base: 19_019), costs: []),
  ])
}

/// The body of the client's 0x801 (opcode.0x801): the server's cast id, the
/// reason and the bit.
pub fn cancel_body(
  cast_id cast_id: Int,
  reason reason: CastResult,
  bit bit: Int,
) -> BitArray {
  let assert Ok(body) =
    cancel_cast.encode(CancelCast(cast_id:, reason:, cancelled: bit))
    as "the cancel fits the message"
  body
}

/// A press of the bag index at the time, with the client's cast id 9 and the
/// target given, taken by the rule; it must be taken, not refused.
pub fn pressed(
  state state: State,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_by(state:, caster: caster(), bag_index:, target:, at: ms)
}

pub fn pressed_by(
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_in(plans: plans(), state:, caster:, bag_index:, target:, at: ms)
}

/// A press at the time of an ability of the plans given, taken by the rule, and its
/// go answered as a round that struck nobody.
pub fn pressed_in(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    pressed_raw_in(plans:, state:, caster:, bag_index:, target:, at: ms)
  answered_with_no_targets(state:, effects:, at: ms)
}

/// The unit id of the one creature a press made by `pressed_counting` has in its picture.
pub const creature_in_sight_unit_id = 1000

/// A creature of the picture, which a press of a Targeted spell may name.
pub fn a_creature() -> activate.Target {
  activate.Usable(
    spawn_id: SpawnId(1),
    creature_id: 26_462,
    creature: activate.Creature(
      columns: [],
      cast_time_ms: 0,
      min_range: 0.0,
      max_range: 5.0,
      flags: 0,
    ),
    checklist_index: 0,
    link: activate.NoLink,
    body: activate.Body(place: caster().place, radius: 0.5),
    alive: True,
    in_combat: False,
    held: [],
    unit_states: [],
    withheld: None,
  )
}

/// What each unit is to a caster who sees one creature, `creature_in_sight_unit_id`, and
/// nothing else.
pub fn creature_in_sight(unit_id: Int) -> activate.Target {
  case unit_id == creature_in_sight_unit_id {
    True -> a_creature()
    False -> activate.Unseen
  }
}

/// The target unit id the client sends in a press of the ability at the bag index, for a
/// test that is not about the press's target. A spell that is not Targeted is sent with
/// none. A Targeted spell is sent with a unit, because the client refuses the press with 91
/// before sending when it has none (`CheckCast 0x1403ae8c0`, mask 0x12a): the caster's own
/// unit id when the spell's mechanics flags let the caster be its own target (the player
/// has themselves selected; picker `0x14055bdc0`, kinds 1, 3, 5 and 8 take the selected
/// target; `opcode.0x9d.target_checks`: refused 32 otherwise), else the creature in sight.
pub fn target_the_client_sends(
  caster caster: Caster,
  plans plans: Plans,
  bag_index bag_index: Int,
) -> Int {
  case cast_press.ability_at(caster:, plans:, bag_index:) {
    Ok(spell) ->
      case spell.targeting.kind {
        target_mechanic.Targeted ->
          case
            spell_effect.has_flag(
              flags: spell.targeting.mechanics_flags,
              bit: 2,
            )
          {
            True -> caster.unit_id
            False -> creature_in_sight_unit_id
          }
        target_mechanic.Caster
        | target_mechanic.Ground
        | target_mechanic.Unread(..) -> 0
      }
    Error(Nil) -> 0
  }
}

/// A press of the bag index by the default caster at the time, its go answered with
/// no unit struck.
pub fn press(
  plans plans: Plans,
  state state: State,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_in(
    plans:,
    state:,
    caster: caster(),
    bag_index: bag,
    target: 0,
    at: ms,
  )
}

/// A press of the bag index by the caster, its go answered with no unit struck, read
/// for the default caster.
pub fn press_by(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_in(plans:, state:, caster:, bag_index: bag, target: 0, at: ms)
}

/// A press of the bag index by the caster, its go answered with no unit struck, read
/// for the same caster.
pub fn press_as(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag bag: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    pressed_raw_in(plans:, state:, caster:, bag_index: bag, target: 0, at: ms)
  answered_as(caster:, state:, effects:, at: ms, struck: [], rolls: [])
}

/// The caster, in or out of combat.
pub fn caster_in_combat(in_combat in_combat: Bool) -> Caster {
  cast_state.Caster(..caster(), in_combat:)
}

/// Each struck unit as a hit on a creature's first life, struck at time 0, with no
/// descriptions and no controls.
pub fn hits(units: List(Int)) -> List(cast_state.Struck) {
  list.map(units, fn(unit_id) {
    cast_state.Hit(
      unit_id:,
      unit: first_life,
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    )
  })
}

/// A creature in its first life, struck by a go at time 0.
pub const first_life = cast_state.HitCreature(life: 1)

/// A press whose go, and each go it leads to at once, strikes these units.
pub fn pressed_striking(
  state state: State,
  bag_index bag_index: Int,
  struck struck: List(cast_state.Struck),
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_striking_in(plans: plans(), state:, bag_index:, struck:, at: ms)
}

/// The same with these plans.
pub fn pressed_striking_in(
  plans plans: Plans,
  state state: State,
  bag_index bag_index: Int,
  struck struck: List(cast_state.Struck),
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    pressed_raw_in(
      plans:,
      state:,
      caster: caster(),
      bag_index:,
      target: 0,
      at: ms,
    )
  answered_by(state:, effects:, at: ms, struck:)
}

/// A press of the bag index, as the rule gives it: a go it asks for is a `Strike`
/// effect, not yet written.
pub fn pressed_raw(
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  pressed_raw_in(plans: plans(), state:, caster:, bag_index:, target:, at: ms)
}

/// A press at the time of an ability of the plans given, as the rule gives it.
pub fn pressed_raw_in(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects, _) =
    pressed_counting(plans:, state:, caster:, bag_index:, target:, at: ms)
  #(state, effects)
}

/// The same, with how many `SpendsResource` events the press raised for the held procs
/// before the connection matched them.
pub fn pressed_counting(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  target target: Int,
  at ms: Int,
) -> #(State, List(Effect), Int) {
  let assert Ok(taken) =
    cast.take(
      target_of: creature_in_sight,
      cast: state,
      message: cast_state.Pressed,
      body: press_body(client_cast_id: 9, bag_index:, target:, press: 1),
      caster:,
      plans:,
      now: at(ms:),
    )
    as "the press is taken: a refusal of the client's own checks is a 0x7fc, never an error"
  let spends = spends_pending(state: taken.0)
  let #(state, effects) = then_procs(step: taken, caster:, at: ms)
  #(state, effects, spends)
}

/// The client's 0x801 at the time, taken by the rule.
pub fn cancelled(
  state state: State,
  cast_id cast_id: Int,
  reason reason: CastResult,
  bit bit: Int,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast_state.Refusal) {
  cancelled_in(plans: plans(), state:, cast_id:, reason:, bit:, at: ms)
}

/// The client's 0x801 at the time, taken by the rule with these plans.
pub fn cancelled_in(
  plans plans: Plans,
  state state: State,
  cast_id cast_id: Int,
  reason reason: CastResult,
  bit bit: Int,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast_state.Refusal) {
  cast.take(
    target_of: nothing_shown,
    cast: state,
    message: cast_state.Cancelled,
    body: cancel_body(cast_id:, reason:, bit:),
    caster: caster(),
    plans:,
    now: at(ms:),
  )
  |> result.map(fn(step) { then_procs(step:, caster: caster(), at: ms) })
}

/// What the client is written, in order.
pub fn writes(effects effects: List(Effect)) -> List(Frame) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.Send(frame:) -> Ok(frame)
      _ -> Error(Nil)
    }
  })
}

/// The frames of the effects written to the client that carry this message id.
pub fn frames_of(
  message_id message_id: Int,
  effects effects: List(Effect),
) -> List(Frame) {
  list.filter(writes(effects:), fn(frame) { frame.message_id == message_id })
}

/// The `Activated` effects among the effects, as the unit, its creature, whether it lived at
/// the press, whether the cast was an item's, and the cast that raised it.
pub fn activations(
  effects effects: List(Effect),
) -> List(#(Int, Int, Bool, Bool, Option(Int))) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.Activated(
        unit_id:,
        creature_id:,
        alive_at_press:,
        by_item:,
        cast_id:,
      ) -> Ok(#(unit_id, creature_id, alive_at_press, by_item, cast_id))
      _ -> Error(Nil)
    }
  })
}

/// How many `Activated` effects name the unit and its creature, which lived at the press,
/// whichever cast raised them.
pub fn activated_count(
  effects effects: List(Effect),
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  by_item by_item: Bool,
) -> Int {
  list.count(activations(effects:), fn(found) {
    found.0 == unit_id
    && found.1 == creature_id
    && found.2
    && found.3 == by_item
  })
}

/// The cast id of the first press the effects confirm: the server's id in its 0x7fd.
pub fn pressed_id(effects effects: List(Effect)) -> Int {
  let assert [frame, ..] =
    frames_of(message_id: spell_cast_confirmed.message_id, effects:)
    as "a press was confirmed"
  let assert Ok(confirmed) = spell_cast_confirmed.decode(frame.body)
    as "a 0x7fd the rule wrote decodes"
  confirmed.server_cast_id
}

/// The cast id of a 0x7fe frame.
pub fn finished_cast_id(frame: Frame) -> Int {
  let assert Ok(finished) = spell_finished.decode(frame.body)
    as "a 0x7fe the rule wrote decodes"
  finished.cast_id
}

/// The cast ids of the 0x7fe frames among the frames, in order.
pub fn finished_ids(frames: List(Frame)) -> List(Int) {
  list.filter(frames, fn(frame) {
    frame.message_id == spell_finished.message_id
  })
  |> list.map(finished_cast_id)
}

/// The 0x811 frames among the frames, each as the cast id and the unit ids.
pub fn removed_targets(frames: List(Frame)) -> List(#(Int, List(Int))) {
  list.filter(frames, fn(frame) {
    frame.message_id == spell_targets_removed.message_id
  })
  |> list.map(fn(frame) {
    let assert Ok(removed) = spell_targets_removed.decode(frame.body)
      as "a 0x811 the rule wrote decodes"
    #(removed.cast_id, removed.unit_ids)
  })
}

/// The 0x813 frames among the frames, each as the cast id and the unit id.
pub fn removed_stacks(frames: List(Frame)) -> List(#(Int, Int)) {
  list.filter(frames, fn(frame) {
    frame.message_id == spell_stack_removed.message_id
  })
  |> list.map(fn(frame) {
    let assert Ok(removed) = spell_stack_removed.decode(frame.body)
      as "a 0x813 the rule wrote decodes"
    #(removed.cast_id, removed.unit_id)
  })
}

/// What the map is told of the cast to relay to the viewers, in order.
pub fn tells(effects effects: List(Effect)) -> List(News) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.Broadcast(news:) -> Ok(news)
      _ -> Error(Nil)
    }
  })
}

/// The log lines written, with their levels, in order.
pub fn logs(effects effects: List(Effect)) -> List(#(LogLevel, String)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.Log(level:, text:) -> Ok(#(level, text))
      _ -> Error(Nil)
    }
  })
}

/// The goes the effects ask for, in order: the strikes the connection has not yet answered.
pub fn goes_asked(effects effects: List(Effect)) -> List(cast_state.GoAsked) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.Strike(asked:) -> Ok(asked)
      _ -> Error(Nil)
    }
  })
}

/// The timers started, with their delays, in order.
pub fn started_timers(effects effects: List(Effect)) -> List(#(TimerId, Int)) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.StartTimer(timer:, after_ms:) -> Ok(#(timer, after_ms))
      _ -> Error(Nil)
    }
  })
}

/// The timers cancelled, in order.
pub fn cancelled_timers(effects effects: List(Effect)) -> List(TimerId) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.CancelTimer(timer:) -> Ok(timer)
      _ -> Error(Nil)
    }
  })
}

/// Fires a timer at the time, and answers every go it asks for with no target, as a
/// caster with no foe in its area is answered: the rule's tests that are not about
/// targets read the go as written at once.
pub fn fired(
  state state: State,
  timer timer: TimerId,
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) = fired_raw(state:, timer:, at: ms)
  answered_with_no_targets(state:, effects:, at: ms)
}

/// Fires a timer at the time, as the rule gives it.
pub fn fired_raw(
  state state: State,
  timer timer: TimerId,
  at ms: Int,
) -> #(State, List(Effect)) {
  fired_raw_as(caster: caster(), state:, timer:, at: ms)
}

/// The same for this caster.
pub fn fired_raw_as(
  caster caster: Caster,
  state state: State,
  timer timer: TimerId,
  at ms: Int,
) -> #(State, List(Effect)) {
  cast.timer_fired(cast: state, timer:, caster:, now: at(ms:))
  |> then_procs(caster:, at: ms)
}

/// Each `Strike` effect replaced, in place, by what `went` gives for a round that struck
/// nobody; the effects it gives are answered the same way.
pub fn answered_with_no_targets(
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
) -> #(State, List(Effect)) {
  answered_by(state:, effects:, at: ms, struck: [])
}

/// `cast.went` for a round whose go checks no type 37 condition, so it takes no roll, and
/// whose spell the areas do not name: a cast the rule no longer holds raises no event.
pub fn went(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(cast_state.Struck),
) -> #(State, List(Effect)) {
  went_of_spell(
    cast:,
    caster:,
    now:,
    cast_id:,
    phase:,
    spell: Error(Nil),
    struck:,
    fired: False,
  )
}

/// The same for a go of `spell`, as the areas name it by the go's Spell4 id, asked of a cast
/// that was `fired` or not (`GoAsked.fired`).
pub fn went_of_spell(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  cast_id cast_id: Int,
  phase phase: Int,
  spell spell: Result(Spell, Nil),
  struck struck: List(cast_state.Struck),
  fired fired: Bool,
) -> #(State, List(Effect)) {
  cast.went(
    cast:,
    caster:,
    now:,
    cast_id:,
    phase:,
    spell:,
    struck:,
    poses: dict.new(),
    indexes: dict.new(),
    units: dict.new(),
    rolls: [],
    gates_passed: dict.new(),
    fired:,
  )
}

/// Each `Strike` effect replaced, in place, by what `went` gives for a round that struck
/// these units; the effects it gives are answered the same way.
pub fn answered_by(
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck struck: List(cast_state.Struck),
) -> #(State, List(Effect)) {
  answered_as(caster: caster(), state:, effects:, at: ms, struck:, rolls: [])
}

/// The same for this caster, each go taking these rolls for its type 37
/// conditions.
pub fn answered_as(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck struck: List(cast_state.Struck),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  answered_posed(
    caster:,
    state:,
    effects:,
    at: ms,
    struck:,
    rolls:,
    poses: dict.new(),
  )
}

/// The same, with the poses the Hit units had in the caster's picture when the round
/// closed, by unit id.
pub fn answered_posed(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck struck: List(cast_state.Struck),
  rolls rolls: List(Int),
  poses poses: dict.Dict(Int, Pose),
) -> #(State, List(Effect)) {
  answered_each(
    caster:,
    state:,
    effects:,
    at: ms,
    struck_of: fn(_) { struck },
    rolls:,
    poses:,
  )
}

/// The same, with the units each go struck chosen by the go asked: a spell that strikes
/// the area is answered with its foes and one with no area with none.
pub fn answered_each(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck_of struck_of: fn(cast_state.GoAsked) -> List(cast_state.Struck),
  rolls rolls: List(Int),
  poses poses: dict.Dict(Int, Pose),
) -> #(State, List(Effect)) {
  answered_known(
    caster:,
    state:,
    effects:,
    at: ms,
    struck_of:,
    rolls:,
    poses:,
    units: dict.new(),
  )
}

/// The same, with what the caster's picture knows each Hit unit to be (a creature of a
/// Creature2 row, another player, or the caster itself), by unit id; a unit it does not
/// name is unknown to the check.
pub fn answered_known(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck_of struck_of: fn(cast_state.GoAsked) -> List(cast_state.Struck),
  rolls rolls: List(Int),
  poses poses: dict.Dict(Int, Pose),
  units units: dict.Dict(Int, prerequisite.FirstUnit),
) -> #(State, List(Effect)) {
  answered_finding(
    caster:,
    state:,
    effects:,
    at: ms,
    struck_of:,
    rolls:,
    poses:,
    units:,
    found_by: None,
  )
}

/// The same, with each `FindProxyTickUnits` answered as the connection answers it
/// (`connection/casting.carried_out`) when a script `found_by` is given: the units it gives
/// for the ask go to `cast.proxy_tick_units_found`, and the answer's effects are answered in
/// the ask's place, so the order of the effects is the order the client gets. With none,
/// the ask stays among the effects. The poses and kinds given are what the answer's target
/// gate reads of the units.
pub fn answered_finding(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  at ms: Int,
  struck_of struck_of: fn(cast_state.GoAsked) -> List(cast_state.Struck),
  rolls rolls: List(Int),
  poses poses: dict.Dict(Int, Pose),
  units units: dict.Dict(Int, prerequisite.FirstUnit),
  found_by found_by: Option(fn(cast_state.ProxyTickAsked) -> List(Int)),
) -> #(State, List(Effect)) {
  list.fold(effects, #(state, []), fn(so_far, effect) {
    let #(state, done) = so_far
    case effect {
      cast_state.FindProxyTickUnits(asked:) ->
        case found_by {
          Some(found) -> {
            let #(state, answer) =
              cast.proxy_tick_units_found(
                cast: state,
                caster:,
                now: at(ms:),
                asked:,
                units: found(asked),
                poses:,
                indexes: dict.new(),
                first_units: units,
              )
            let #(state, more) =
              answered_finding(
                caster:,
                state:,
                effects: answer,
                at: ms,
                struck_of:,
                rolls:,
                poses:,
                units:,
                found_by:,
              )
            #(state, list.append(done, more))
          }
          None -> #(state, list.append(done, [effect]))
        }
      cast_state.Strike(asked:) -> {
        let #(state, going) =
          cast.went(
            cast: state,
            caster:,
            now: at(ms:),
            cast_id: asked.cast_id,
            phase: asked.phase,
            spell: Error(Nil),
            struck: struck_of(asked),
            poses:,
            indexes: dict.new(),
            units:,
            rolls:,
            gates_passed: dict.new(),
            fired: asked.fired,
          )
          |> then_procs_known(caster:, at: ms, poses:, units:, drawn: None)
        let #(state, more) =
          answered_finding(
            caster:,
            state:,
            effects: going,
            at: ms,
            struck_of:,
            rolls:,
            poses:,
            units:,
            found_by:,
          )
        #(state, list.append(done, more))
      }
      _ -> #(state, list.append(done, [effect]))
    }
  })
}

/// The message id of each frame the effects write to the client, in order.
pub fn written_ids(effects effects: List(Effect)) -> List(Int) {
  ids(frames: writes(effects:))
}

/// A frame's message id.
pub fn ids(frames frames: List(Frame)) -> List(Int) {
  list.map(frames, fn(frame) { frame.message_id })
}

/// One timer that fired: the time it fired at, the goes the rule asked for (before they
/// were answered), the `SpendsResource` events its step raised for the held procs (before
/// the connection matched them), the Proxy ticks that asked for their units (before they
/// were answered) and the effects of its answered step.
pub type Fired {
  Fired(
    at_ms: Int,
    asked: List(cast_state.GoAsked),
    spends: Int,
    found: List(cast_state.ProxyTickAsked),
    effects: List(Effect),
  )
}

/// Fires every timer a step started, earliest first, and each timer those steps
/// start, until none is left: the time each fired at (`from_ms` plus the delays
/// that led to it) with the effects of its step. The clock is the test's.
pub fn run_timers(
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
) -> #(State, List(#(Int, List(Effect)))) {
  run_timers_striking(state:, effects:, from_ms:, struck: [])
}

/// The same, with each go striking these units.
pub fn run_timers_striking(
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  struck struck: List(cast_state.Struck),
) -> #(State, List(#(Int, List(Effect)))) {
  run_timers_each(
    caster: caster(),
    state:,
    effects:,
    from_ms:,
    struck_of: fn(_) { struck },
  )
}

/// The same, with the units each go struck chosen by the go asked (`answered_each`).
pub fn run_timers_each(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  struck_of struck_of: fn(cast_state.GoAsked) -> List(cast_state.Struck),
) -> #(State, List(#(Int, List(Effect)))) {
  let #(state, fired) =
    run_timers_asking(
      caster:,
      state:,
      effects:,
      from_ms:,
      struck_at: fn(_, asked) { struck_of(asked) },
    )
  #(state, list.map(fired, fn(step) { #(step.at_ms, step.effects) }))
}

/// The same, with the goes each timer's step asked for kept beside its effects, and the
/// units each go struck chosen by the time it is answered at and the go asked.
pub fn run_timers_asking(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  struck_at struck_at: fn(Int, cast_state.GoAsked) -> List(cast_state.Struck),
) -> #(State, List(Fired)) {
  run_timers_posed(
    caster:,
    state:,
    effects:,
    from_ms:,
    struck_at:,
    poses: dict.new(),
    until_ms: None,
  )
}

/// The same, with the poses the struck units have in the caster's picture at each go, and,
/// when `until_ms` is given, only the timers due at it or before: the ones due later are
/// left, as the clock the test drives has not reached them.
pub fn run_timers_posed(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  struck_at struck_at: fn(Int, cast_state.GoAsked) -> List(cast_state.Struck),
  poses poses: dict.Dict(Int, Pose),
  until_ms until_ms: Option(Int),
) -> #(State, List(Fired)) {
  let #(state, fired, _, _) =
    run_pending(
      caster: cast_cost.after_payments(caster:, effects:),
      state:,
      pending: due_of(effects:, now_ms: from_ms),
      struck_at:,
      poses:,
      until_ms:,
      before: fn(_, caster) { caster },
      leaves_open: fn(_) { False },
      after: no_check,
      units: dict.new(),
      found_by: None,
    )
  #(state, fired)
}

/// The same, as a script: `before` changes the caster at the time a timer is due, before
/// it fires (another cast spending a vital, the vital regenerating), and a timer for which
/// `leaves_open` holds is not answered, so its go's strike round stays open (its effects
/// are the raw ones, with the `Strike`). Only the timers due at `until_ms` or before fire,
/// when it is given. Each step's payments and gains are taken into the caster the next
/// timer fires for, as the connection builds the caster again from the session after each
/// `Pay` (`genesis_prime/game/connection/casting.caster_of`); the caster after the last
/// step is returned.
pub fn run_timers_scripted(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  struck struck: List(cast_state.Struck),
  until_ms until_ms: Option(Int),
  before before: fn(Int, Caster) -> Caster,
  leaves_open leaves_open: fn(Int) -> Bool,
) -> #(State, List(Fired), Caster) {
  let #(state, fired, caster, _) =
    run_pending(
      caster: cast_cost.after_payments(caster:, effects:),
      state:,
      pending: due_of(effects:, now_ms: from_ms),
      struck_at: fn(_, _) { struck },
      poses: dict.new(),
      until_ms:,
      before:,
      leaves_open:,
      after: no_check,
      units: dict.new(),
      found_by: None,
    )
  #(state, fired, caster)
}

/// The same for a state that repeats, which never runs out of timers: only the
/// timers due at `until_ms` or before fire, and the ones due later are left, as the
/// clock the test drives has not reached them.
pub fn run_timers_until(
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  until_ms until_ms: Int,
) -> #(State, List(#(Int, List(Effect)))) {
  run_timers_until_as(caster: caster(), state:, effects:, from_ms:, until_ms:)
}

/// The same for this caster.
pub fn run_timers_until_as(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  until_ms until_ms: Int,
) -> #(State, List(#(Int, List(Effect)))) {
  let #(state, fired, _, _) =
    run_pending(
      caster: cast_cost.after_payments(caster:, effects:),
      state:,
      pending: due_of(effects:, now_ms: from_ms),
      struck_at: fn(_, _) { [] },
      poses: dict.new(),
      until_ms: Some(until_ms),
      before: fn(_, caster) { caster },
      leaves_open: fn(_) { False },
      after: no_check,
      units: dict.new(),
      found_by: None,
    )
  #(state, list.map(fired, fn(step) { #(step.at_ms, step.effects) }))
}

/// The caster with 1 health of a million and no shield: every heal of a press lands whole.
pub fn hurt(caster caster: Caster) -> Caster {
  cast_state.Caster(
    ..caster,
    vitals: damage.Vitals(
      health: 1,
      max_health: 1_000_000,
      shield: 0,
      max_shield: 0,
    ),
  )
}

/// Each 0x7ff of the spell `spell4_id` the steps write, with the time of its step.
pub fn starts_of(
  steps steps: List(#(Int, List(Effect))),
  spell4_id spell4_id: Int,
) -> List(#(Int, spell_started.SpellStarted)) {
  list.flat_map(steps, fn(step) {
    started_in(effects: step.1)
    |> list.filter(fn(start) { start.spell4_id == spell4_id })
    |> list.map(fn(start) { #(step.0, start) })
  })
}

/// The time of each start.
pub fn times_of(
  starts starts: List(#(Int, spell_started.SpellStarted)),
) -> List(Int) {
  list.map(starts, fn(start) { start.0 })
}

/// Each 0x7ff the effects write, decoded.
pub fn started_in(
  effects effects: List(Effect),
) -> List(spell_started.SpellStarted) {
  decoded_in(
    effects:,
    message_id: spell_started.message_id,
    decode: spell_started.decode,
  )
}

/// Each message of the id the effects write, decoded by `decode`; a frame the rule wrote
/// that does not decode stops the test.
pub fn decoded_in(
  effects effects: List(Effect),
  message_id message_id: Int,
  decode decode: fn(BitArray) -> Result(message, error),
) -> List(message) {
  list.map(frames_of(message_id:, effects:), fn(frame) {
    let assert Ok(message) = decode(frame.body)
      as "a message the rule wrote decodes"
    message
  })
}

/// A press of the spell as the planted base 3 ability by `caster` at `press_ms`, its go
/// answered by a round that struck nobody, and every timer it starts and each timer those
/// start, fired on the driven clock up to `until_ms`: the press's effects and each later
/// step's time and effects.
pub fn pressed_and_run(
  spell spell: Spell,
  caster caster: Caster,
  press_ms press_ms: Int,
  until_ms until_ms: Int,
) -> #(List(Effect), List(#(Int, List(Effect)))) {
  let #(state, effects) =
    press_as(
      plans: plans_of([Spell(..spell, spell4_base_id: Spell4BaseId(3))]),
      state: cast_state.new(),
      caster:,
      bag: started_bag_index,
      at: press_ms,
    )
  let #(_, steps) =
    run_timers_until_as(caster:, state:, effects:, from_ms: press_ms, until_ms:)
  #(effects, steps)
}

/// The ids of the state's timers whose due the predicate accepts; a count is its length.
pub fn timers_matching(
  state state: State,
  matching matching: fn(cast_state.Due) -> Bool,
) -> List(TimerId) {
  dict.to_list(state.timers)
  |> list.filter_map(fn(entry) {
    case matching(entry.1) {
      True -> Ok(entry.0)
      False -> Error(Nil)
    }
  })
}

/// The timers of the state that are a tick of a periodic row, on any unit.
pub fn tick_timers(state state: State) -> Int {
  list.length(
    timers_matching(state:, matching: fn(due) {
      case due {
        cast_state.Tick(..) -> True
        _ -> False
      }
    }),
  )
}

/// The timers of the state that are a tick of a periodic row on the unit `unit_id`.
pub fn tick_timers_on(state state: State, unit_id unit_id: Int) -> Int {
  list.length(
    timers_matching(state:, matching: fn(due) {
      case due {
        cast_state.Tick(unit_id: on, ..) -> on == unit_id
        _ -> False
      }
    }),
  )
}

/// The schedule of a periodic Proxy row with flags bit 2 and no durationTime (rows 210304,
/// 217944 and 210337), read as open by `ticking.open_schedule_of`.
pub fn open_schedule(
  delay_ms delay_ms: Int,
  tick_ms tick_ms: Int,
) -> ticking.Schedule {
  let assert Ok(schedule) =
    ticking.open_schedule_of(
      row: LastingRow(delay_ms:, lasts: lasts.UntilRemoved),
      tick_ms:,
    )
    as "an open Proxy row of a tickTime above 0 has a schedule"
  schedule
}

/// The timers the effects start, fired on the driven clock up to `until_ms` with each
/// `FindProxyTickUnits` answered from `found_by` (`answered_finding`) and each go answered as
/// a round that struck nobody: the state and each timer that fired.
pub fn run_timers_finding(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  until_ms until_ms: Int,
  units units: dict.Dict(Int, prerequisite.FirstUnit),
  found_by found_by: fn(cast_state.ProxyTickAsked) -> List(Int),
) -> #(State, List(Fired)) {
  run_timers_finding_striking(
    caster:,
    state:,
    effects:,
    from_ms:,
    until_ms:,
    units:,
    found_by:,
    struck_by: fn(_, _) { [] },
  )
}

/// The same with each go answered with the units `struck_by` gives for the time it is
/// answered at and the go asked, so a tick's child casts strike the units its tick found.
pub fn run_timers_finding_striking(
  caster caster: Caster,
  state state: State,
  effects effects: List(Effect),
  from_ms from_ms: Int,
  until_ms until_ms: Int,
  units units: dict.Dict(Int, prerequisite.FirstUnit),
  found_by found_by: fn(cast_state.ProxyTickAsked) -> List(Int),
  struck_by struck_by: fn(Int, cast_state.GoAsked) -> List(cast_state.Struck),
) -> #(State, List(Fired)) {
  let #(state, fired, _, _) =
    run_pending(
      caster: cast_cost.after_payments(caster:, effects:),
      state:,
      pending: due_of(effects:, now_ms: from_ms),
      struck_at: struck_by,
      poses: dict.new(),
      until_ms: Some(until_ms),
      before: fn(_, caster) { caster },
      leaves_open: fn(_) { False },
      after: no_check,
      units:,
      found_by: Some(found_by),
    )
  #(state, fired)
}

/// The timers the effects start, each due its delay after the time.
pub fn due_of(
  effects effects: List(Effect),
  now_ms now_ms: Int,
) -> List(#(Int, TimerId)) {
  list.map(started_timers(effects:), fn(started) {
    #(now_ms + started.1, started.0)
  })
}

/// How many `SpendsResource` events the state holds for the held procs.
pub fn spends_pending(state state: State) -> Int {
  list.count(state.pending, fn(event) {
    event.trigger == spell_plan.SpendsResource
  })
}

fn no_check(
  state: State,
  _caster: Caster,
  _due: Int,
) -> #(State, List(Effect)) {
  #(state, [])
}

/// What one fired timer leaves: the context the next timer fires with, the state, the
/// effects (which start and cancel the timers still to fire) and the record the caller
/// keeps for the step.
pub type Step(context, record) {
  Step(context: context, state: State, effects: List(Effect), record: record)
}

/// Fires the pending timers due at `until_ms` or before, earliest first, each through
/// `step`, which gets the context, the state, the time and the timer. The effects a step
/// returns cancel their timers and start theirs, due their delay after the step's time.
/// Returns the last context and state, each step's record and the timers left.
pub fn fire_pending(
  context context: context,
  state state: State,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  step step: fn(context, State, Int, TimerId) -> Step(context, record),
) -> #(context, State, List(record), List(#(Int, TimerId))) {
  fire_pending_loop(
    context:,
    state:,
    pending:,
    until_ms:,
    step:,
    records_so_far: [],
  )
}

fn fire_pending_loop(
  context context: context,
  state state: State,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  step step: fn(context, State, Int, TimerId) -> Step(context, record),
  records_so_far records_so_far: List(record),
) -> #(context, State, List(record), List(#(Int, TimerId))) {
  case
    list.sort(pending, fn(first, second) { int.compare(first.0, second.0) })
  {
    [#(due, timer), ..rest] if due <= until_ms -> {
      let fired = step(context, state, due, timer)
      let cancelled = cancelled_timers(effects: fired.effects)
      fire_pending_loop(
        context: fired.context,
        state: fired.state,
        pending: list.append(
          list.filter(rest, fn(other) { !list.contains(cancelled, other.1) }),
          due_of(effects: fired.effects, now_ms: due),
        ),
        until_ms:,
        step:,
        records_so_far: [fired.record, ..records_so_far],
      )
    }
    sorted -> #(context, state, list.reverse(records_so_far), sorted)
  }
}

/// The timers fire as in `fire_pending` with the caster as the context: each is answered
/// as the rule's go, then `after` runs for the state, the caster and the time (the check
/// of every cast's persistence, as the connection runs it after each input) and its
/// effects join the step's. Returns the state, the steps, the caster after the last step
/// and the timers left.
fn run_pending(
  caster caster: Caster,
  state state: State,
  pending pending: List(#(Int, TimerId)),
  struck_at struck_at: fn(Int, cast_state.GoAsked) -> List(cast_state.Struck),
  poses poses: dict.Dict(Int, Pose),
  until_ms until_ms: Option(Int),
  before before: fn(Int, Caster) -> Caster,
  leaves_open leaves_open: fn(Int) -> Bool,
  after after: fn(State, Caster, Int) -> #(State, List(Effect)),
  units units: dict.Dict(Int, prerequisite.FirstUnit),
  found_by found_by: Option(fn(cast_state.ProxyTickAsked) -> List(Int)),
) -> #(State, List(Fired), Caster, List(#(Int, TimerId))) {
  let #(caster, state, fired, left) =
    fire_pending(
      context: caster,
      state:,
      pending:,
      until_ms: option.unwrap(until_ms, 9_007_199_254_740_991),
      step: fn(caster, state, due, timer) {
        let caster = before(due, caster)
        let #(state, raw) =
          cast.timer_fired(cast: state, timer:, caster:, now: at(ms: due))
        let spends = spends_pending(state:)
        let #(state, raw) = then_procs(step: #(state, raw), caster:, at: due)
        let #(state, answered) = case leaves_open(due) {
          True -> #(state, raw)
          False ->
            answered_finding(
              caster:,
              state:,
              effects: raw,
              at: due,
              struck_of: fn(asked) { struck_at(due, asked) },
              rolls: [],
              poses:,
              units:,
              found_by:,
            )
        }
        let #(state, checked) = after(state, caster, due)
        let effects = list.append(answered, checked)
        Step(
          context: cast_cost.after_payments(caster:, effects:),
          state:,
          effects:,
          record: Fired(
            at_ms: due,
            asked: goes_asked(effects: raw),
            spends:,
            found: proxy_tick_asks(effects: raw),
            effects:,
          ),
        )
      },
    )
  #(state, fired, caster, left)
}

/// The timers a step started fire until `until_ms` as `run_pending` fires them, each
/// answered as a go that struck nobody and followed by `after` (the check of every
/// cast's persistence): the state, each step's time and effects, and the timers left.
pub fn run_timers_checked(
  caster caster: Caster,
  state state: State,
  pending pending: List(#(Int, TimerId)),
  until_ms until_ms: Int,
  after after: fn(State, Caster, Int) -> #(State, List(Effect)),
) -> #(State, List(#(Int, List(Effect))), List(#(Int, TimerId))) {
  let #(state, fired, _, left) =
    run_pending(
      caster:,
      state:,
      pending:,
      struck_at: fn(_, _) { [] },
      poses: dict.new(),
      until_ms: Some(until_ms),
      before: fn(_, caster) { caster },
      leaves_open: fn(_) { False },
      after:,
      units: dict.new(),
      found_by: None,
    )
  #(state, list.map(fired, fn(step) { #(step.at_ms, step.effects) }), left)
}

/// A spell and the stages and Proxies under it with no cooldown modifier: the plan as
/// if the rows that change a cooldown were not there.
pub fn without_cooldown_modifiers(spell spell: Spell) -> Spell {
  spell_plan.with_proxies(
    spell: spell_plan.Spell(
      ..spell,
      effects: list.filter(spell.effects, fn(planned) {
        result.is_error(spell_plan.as_cooldown_modifier(kind: planned.kind))
      }),
      stages: list.map(spell.stages, fn(stage) {
        spell_plan.Stage(
          ..stage,
          spell: without_cooldown_modifiers(spell: stage.spell),
        )
      }),
    ),
    proxies: list.map(
      spell_plan.payloads(spell:, as_kind: spell_plan.as_proxy),
      fn(proxy) {
        spell_plan.Proxy(
          ..proxy,
          spell: without_cooldown_modifiers(spell: proxy.spell),
        )
      },
    ),
  )
}

/// What a client reads of the casts among its frames, as one line each, the
/// casts named k1, k2 and so on in the order their ids first appear.
pub fn cast_lines(frames frames: List(Frame)) -> List(String) {
  let events = game_client.casts_in(frames:)
  let ids =
    list.filter_map(events, fn(event) {
      case event {
        game_client.CastConfirmed(server_cast_id:, ..) -> Ok(server_cast_id)
        game_client.CastStarted(cast_id:, ..)
        | game_client.CastWent(cast_id:, ..)
        | game_client.CastFinished(cast_id:) -> Ok(cast_id)
        game_client.CastRefused(..)
        | game_client.ThresholdOpened(..)
        | game_client.ThresholdIndex(..)
        | game_client.ThresholdClosed(..)
        | game_client.ThresholdEnded(..) -> Error(Nil)
      }
    })
    |> list.unique
  let label = fn(id) {
    let assert Ok(position) =
      list.index_map(ids, fn(known, position) { #(known, position) })
      |> list.key_find(id)
      as "every cast id of a line was read before"
    "k" <> int.to_string(position + 1)
  }
  list.map(events, fn(event) {
    case event {
      game_client.CastRefused(spell4_id:, result:, ..) ->
        "refused " <> int.to_string(spell4_id) <> " " <> int.to_string(result)
      game_client.CastConfirmed(server_cast_id:, ..) ->
        "confirmed " <> label(server_cast_id)
      game_client.CastStarted(
        cast_id:,
        spell4_id:,
        root_spell4_id:,
        parent_spell4_id:,
        ..,
      ) ->
        "started "
        <> label(cast_id)
        <> " "
        <> int.to_string(spell4_id)
        <> " root "
        <> int.to_string(root_spell4_id)
        <> " parent "
        <> int.to_string(parent_spell4_id)
      game_client.CastWent(cast_id:, phase:) ->
        "went " <> label(cast_id) <> " p" <> int.to_string(phase)
      game_client.CastFinished(cast_id:) -> "finished " <> label(cast_id)
      game_client.ThresholdOpened(spell4_id:, cancel_cast_id:) ->
        "opened " <> int.to_string(spell4_id) <> " " <> label(cancel_cast_id)
      game_client.ThresholdIndex(spell4_id:, index:) ->
        "index " <> int.to_string(spell4_id) <> " " <> int.to_string(index)
      game_client.ThresholdClosed(spell4_id:, start_cooldowns:) ->
        "closed "
        <> int.to_string(spell4_id)
        <> " "
        <> int.to_string(start_cooldowns)
      game_client.ThresholdEnded(spell4_id:) ->
        "ended " <> int.to_string(spell4_id)
    }
  })
}

/// 67777 as the client holds it: FallingDamageMultiplier set to 0.0 from 180 ms for
/// 400 ms, in phase 0 only.
pub fn falling_row() -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(67_777),
    phase_flags: 1,
    change: spell_plan.PropertyChange(unit_properties.Change(
      property: UnitProperty2Id(134),
      mode: 3,
      multiplier: 0.0,
      flat: 0.0,
      per_level: 0.0,
    )),
    row: LastingRow(delay_ms: 180, lasts: lasts.For(duration_ms: 400)),
    condition: Always,
    tag: spend.always,
    armor: None,
  )
}

/// The spell `spell4_id` in the tree of the innate of ability `base`, in the
/// client's plans.
pub fn planned_spell(
  base base: Int,
  spell4_id spell4_id: Int,
) -> spell_plan.Spell {
  let assert Ok(innate) =
    spell_plan.in_plans(plans: real_plans(), base: Spell4BaseId(base))
    as "the plans hold the innate"
  let assert Ok(spell) =
    list.find(
      spell_plan.tree(spell: innate, started: fn(_) { True }),
      fn(spell) { spell.spell4_id.value == spell4_id },
    )
    as "the innate's tree holds the spell"
  spell
}

/// A modifier that adds `points` flat to the interrupt armor threshold.
pub fn raising_interrupt_armor_threshold(
  points points: Float,
) -> unit_properties.Modifier {
  unit_properties.Change(
    property: unit_properties.interrupt_armor_threshold,
    mode: 0,
    multiplier: 1.0,
    flat: points,
    per_level: 0.0,
  )
}

/// An Interrupt Armor row (effectType 52): `points` of armor (dataBits00) kept at the end or,
/// with `takes_back`, taken back (dataBits01), the lasting `row` given, phaseFlags -1, no
/// gate, aimed as given.
pub fn interrupt_armor_row(
  id id: Int,
  aim aim: spell_plan.Aim,
  points points: Int,
  takes_back takes_back: Bool,
  row row: lasting.LastingRow,
) -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    change: spell_plan.PropertyChange(
      raising_interrupt_armor_threshold(points: int.to_float(points)),
    ),
    row:,
    condition: spell_plan.Always,
    tag: spend.always,
    armor: Some(spell_plan.InterruptArmor(points:, takes_back:, aim:)),
  )
}

/// Row 199192 of Spell4 76766 as the client holds it (`table_rows -- Spell4Effects
/// 199192`): Interrupt Armor, +1 point kept at the end for 5000 ms, aimed as given (its
/// targetFlags is 2, the primary target).
pub fn spectral_form_row(
  aim aim: spell_plan.Aim,
) -> spell_plan.PropertyModifier {
  interrupt_armor_row(
    id: 199_192,
    aim:,
    points: 1,
    takes_back: False,
    row: lasting.LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 5000)),
  )
}

/// The Proxies of a go aimed at the caster, ticking on the caster as a go at its own start
/// arms them.
pub fn proxies_ticking_on_the_caster(
  proxies proxies: List(spell_plan.Proxy),
  caster caster: Caster,
) -> List(cast_state.TickingOn) {
  cast_tick.proxies_ticking(
    proxies:,
    caster:,
    primary_target: caster.unit_id,
    named_player: None,
    phase: 0,
    started_at: area.pose_of(place: caster.place),
    primary_pose: None,
  )
}

/// The Proxy ticks that ask for their units among `effects`, in order.
pub fn proxy_tick_asks(
  effects effects: List(Effect),
) -> List(cast_state.ProxyTickAsked) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.FindProxyTickUnits(asked:) -> Ok(asked)
      _ -> Error(Nil)
    }
  })
}

/// Each tick strike among the effects closed by `close`, the effects each close writes
/// following all the effects given.
pub fn ticks_closed(
  state state: State,
  effects effects: List(Effect),
  close close: fn(State, cast_state.TickAsked) -> #(State, List(Effect)),
) -> #(State, List(Effect)) {
  list.fold(tick_strikes(effects:), #(state, effects), fn(so_far, asked) {
    let #(state, done) = so_far
    let #(state, closed) = close(state, asked)
    #(state, list.append(done, closed))
  })
}

/// The tick strikes among `effects`, in order.
pub fn tick_strikes(
  effects effects: List(Effect),
) -> List(cast_state.TickAsked) {
  list.filter_map(effects, fn(effect) {
    case effect {
      cast_state.TickStrike(asked:) -> Ok(asked)
      _ -> Error(Nil)
    }
  })
}

// ---- what a unit create lists of a cast ----

/// The effect info of an effect that tells no value, as a unit create (0x262) lists it:
/// the bit's own value is read by no client code (`opcode.0x7f4.effect_time`). Written out
/// here, not built by `target_info`, which is the code these expected values check.
pub fn listed_effect_info(
  effect_id effect_id: Int,
  instance_id instance_id: Int,
  delay_ms delay_ms: Int,
  lifetime_ms lifetime_ms: Int,
) -> SpellEffectInfo {
  SpellEffectInfo(
    spell4_effects_id: effect_id,
    instance_id:,
    delay_ms:,
    lifetime_ms:,
    result: spell_effect_result.Bit(SpellEffectBit(unread_2: 0)),
  )
}

/// The target info of one unit as a unit create lists it: target flags 0 and a Hit
/// (`opcode.0x7f4.target_info`).
pub fn listed_target_info(
  unit_id unit_id: Int,
  index index: Int,
  count count: Int,
  effects effects: List(SpellEffectInfo),
) -> SpellTargetInfo {
  SpellTargetInfo(
    unit_id:,
    index:,
    flags: 0,
    instance_count: count,
    combat_result: combat_result.Hit,
    effects:,
  )
}

/// The state with each live cast holding one node, on the unit 7, kept until 4000 by a
/// crowd-control state, with these effects.
pub fn live_casts_holding_only_a_node(
  state state: State,
  effects effects: List(lasting.NodeEffect),
) -> State {
  cast_state.State(
    ..state,
    casts: dict.map_values(state.casts, fn(_, live) {
      cast_state.Live(
        ..live,
        nodes: dict.from_list([
          #(
            7,
            lasting.Node(
              unit_id: 7,
              count: 1,
              life: lasting.EndsAt(ms: 4000),
              effects:,
              armed_ms: 1000,
              held_until_ms: Some(4000),
              struck: None,
            ),
          ),
        ]),
      )
    }),
  )
}

// ---- what the tests of several rules decode, find and build the same way ----

/// Each 0x7f4 the effects write, decoded.
pub fn goes_in(effects effects: List(Effect)) -> List(spell_go.SpellGo) {
  decoded_in(effects:, message_id: spell_go.message_id, decode: spell_go.decode)
}

/// Each 0x7fc the effects write, decoded.
pub fn refused_in(
  effects effects: List(Effect),
) -> List(spell_cast_refused.SpellCastRefused) {
  decoded_in(
    effects:,
    message_id: spell_cast_refused.message_id,
    decode: spell_cast_refused.decode,
  )
}

/// What the effects refuse: each 0x7fc's client cast id, Spell4 id and result.
pub fn refused_with(effects effects: List(Effect)) -> List(#(Int, Int, Int)) {
  list.map(refused_in(effects:), fn(refused) {
    #(
      refused.client_cast_id,
      refused.spell4_id,
      cast_result.to_value(refused.result),
    )
  })
}

/// Each 0x7fd the effects write, decoded.
pub fn confirmed_in(
  effects effects: List(Effect),
) -> List(spell_cast_confirmed.SpellCastConfirmed) {
  decoded_in(
    effects:,
    message_id: spell_cast_confirmed.message_id,
    decode: spell_cast_confirmed.decode,
  )
}

/// The targets of the one 0x7f4 the effects write.
pub fn go_targets(effects effects: List(Effect)) -> List(SpellTargetInfo) {
  let assert [go] = goes_in(effects:) as "the effects write one 0x7f4"
  go.targets
}

/// A heal with this row id, vital, aim, delay, condition and formula, in every phase.
pub fn heal_row(
  id id: Int,
  vital vital: effect_kind.Vital,
  aim aim: spell_plan.Aim,
  delay_ms delay_ms: Int,
  condition condition: spell_plan.Condition,
  formula formula: damage.Formula,
) -> spell_plan.Heal {
  spell_plan.Heal(
    effect_id: Spell4EffectsId(id),
    vital:,
    phase_flags: -1,
    aim:,
    condition:,
    tag: spend.always,
    formula:,
    delay_ms:,
  )
}

/// The formula of Mind Over Body's heal row (Spell4Effects 62019, parameters 13 x 0.3281 and
/// 10 x 17.51): 0.3281 of the Support Rating and 17.51 a level, multiplier 1, no flat part.
pub fn mind_over_body_formula() -> damage.Formula {
  damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
    damage.Parameter(kind: 13, value: 0.3281),
    damage.Parameter(kind: 10, value: 17.51),
    damage.Parameter(kind: 0, value: 0.0),
    damage.Parameter(kind: 0, value: 0.0),
  ])
}

/// The effects the one 0x7f4 the effects write lists on the unit `unit_id`, each as its
/// Spell4Effects id and its result, in the order listed; none when the unit is not a target.
pub fn listed_on(
  effects effects: List(Effect),
  unit_id unit_id: Int,
) -> List(#(Int, spell_effect_result.SpellEffectResult)) {
  list.filter(go_targets(effects:), fn(target) { target.unit_id == unit_id })
  |> list.flat_map(fn(target) {
    list.map(target.effects, fn(effect) {
      #(effect.spell4_effects_id, effect.result)
    })
  })
}

/// The result of a go's effect that lists a heal of `kind` the client logs as a heal of
/// `amount` with `overkill` overheal (`spell.heal_result_log`): a Hit with the amount as the
/// raw, the scaled raw and the health change, and nothing absorbed, glanced or killed.
pub fn heal_result(
  amount amount: Int,
  kind kind: damage_type.DamageType,
  overkill overkill: Int,
) -> spell_effect_result.SpellEffectResult {
  spell_effect_result.Damage(spell_effect_damage.SpellEffectDamage(
    description: SpellDamageDescription(
      ..landed_damage(
        amount:,
        killed: 0,
        combat_result: combat_result.Hit,
        damage_type: kind,
      ),
      overkill:,
    ),
  ))
}

/// The effect id of each effect of each target of each 0x7f4 the effects write, in order.
pub fn listed_effect_ids(effects effects: List(Effect)) -> List(Int) {
  list.flat_map(goes_in(effects:), fn(go) {
    list.flat_map(go.targets, fn(target) {
      list.map(target.effects, fn(effect) { effect.spell4_effects_id })
    })
  })
}

/// The effect id of each effect each 0x7f4 the effects write lists on the unit, in order.
pub fn listed_on_unit(
  effects effects: List(Effect),
  unit_id unit_id: Int,
) -> List(Int) {
  list.flat_map(goes_in(effects:), fn(go) { listed_by_go(go:, unit_id:) })
}

/// The effect id of each effect the 0x7f4 of the cast the effects write lists on the unit,
/// in order.
pub fn listed_on_unit_by_cast(
  effects effects: List(Effect),
  cast_id cast_id: Int,
  unit_id unit_id: Int,
) -> List(Int) {
  list.filter(goes_in(effects:), fn(go) { go.cast_id == cast_id })
  |> list.flat_map(fn(go) { listed_by_go(go:, unit_id:) })
}

fn listed_by_go(go go: spell_go.SpellGo, unit_id unit_id: Int) -> List(Int) {
  list.filter(go.targets, fn(target) { target.unit_id == unit_id })
  |> list.flat_map(fn(target) {
    list.map(target.effects, fn(effect) { effect.spell4_effects_id })
  })
}

/// The one 0x7f4 the effects write, as each target unit with the ids of its effects, both
/// by id.
pub fn listed_by_unit(
  effects effects: List(Effect),
) -> List(#(Int, List(Int))) {
  list.map(go_targets(effects:), fn(info) {
    #(
      info.unit_id,
      list.map(info.effects, fn(effect) { effect.spell4_effects_id })
        |> list.sort(int.compare),
    )
  })
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
}

/// The one 0x7f4 the effects write, as each target unit in the go's order with the id and
/// delay of each of its effects, by id.
pub fn listed_with_delays(
  effects effects: List(Effect),
) -> List(#(Int, List(#(Int, Int)))) {
  list.map(go_targets(effects:), fn(info) {
    #(
      info.unit_id,
      list.map(info.effects, fn(effect) {
        #(effect.spell4_effects_id, effect.delay_ms)
      })
        |> list.sort(fn(first, second) { int.compare(first.0, second.0) }),
    )
  })
}

/// The Spell4 id and the root and parent Spell4 ids of each 0x7ff told to the map, in order.
pub fn started_told(effects effects: List(Effect)) -> List(#(Int, Int, Int)) {
  list.filter_map(tells(effects:), fn(tell) {
    case tell {
      unit_news.CastStarted(start:) ->
        Ok(#(start.spell4_id, start.root_spell4_id, start.parent_spell4_id))
      _ -> Error(Nil)
    }
  })
}

/// The first 0x7ff the effects write for the Spell4.
pub fn first_started(
  effects effects: List(Effect),
  spell4_id spell4_id: Int,
) -> spell_started.SpellStarted {
  let assert Ok(start) =
    list.find(started_in(effects:), fn(start) { start.spell4_id == spell4_id })
    as "the effects start a cast of the Spell4"
  start
}

/// The cast id of the first 0x7ff the effects write for the Spell4.
pub fn started_cast_id(
  effects effects: List(Effect),
  spell4_id spell4_id: Int,
) -> Int {
  first_started(effects:, spell4_id:).cast_id
}

/// The lines the effects log at the debug level, in order.
pub fn debug_lines(effects effects: List(Effect)) -> List(String) {
  lines_at(effects:, level: step.LogDebug)
}

/// The lines the effects log at the level, in order.
pub fn lines_at(
  effects effects: List(Effect),
  level level: LogLevel,
) -> List(String) {
  list.filter_map(logs(effects:), fn(line) {
    case line.0 == level {
      True -> Ok(line.1)
      False -> Error(Nil)
    }
  })
}

/// The lines the effects log at the warning level, in order.
pub fn warning_lines(effects effects: List(Effect)) -> List(String) {
  lines_at(effects:, level: step.LogWarning)
}

/// The first timer the effects start, with its delay.
pub fn first_timer(effects effects: List(Effect)) -> #(TimerId, Int) {
  let assert [first, ..] = started_timers(effects:)
    as "the effects start a timer"
  first
}

/// The number inside a timer id.
pub fn timer_number(timer timer: TimerId) -> Int {
  let TimerId(number) = timer
  number
}

/// A hit on a unit as the rule's strike reports it, with no interrupt armor taken.
pub fn hit_with(
  unit_id unit_id: Int,
  unit unit: cast_state.HitUnit,
  descriptions descriptions: List(hit.Description),
  controls controls: List(strike_tell.ControlLanded),
  ticking ticking: List(spell_area.TickingDamage),
) -> cast_state.Struck {
  cast_state.Hit(
    unit_id:,
    unit:,
    descriptions:,
    controls:,
    armor_removed: 0,
    ticking:,
  )
}

/// A hit on a creature in the life given, with no controls and no ticking damage.
pub fn creature_hit(unit_id unit_id: Int, life life: Int) -> cast_state.Struck {
  hit_with(
    unit_id:,
    unit: cast_state.HitCreature(life:),
    descriptions: [],
    controls: [],
    ticking: [],
  )
}

/// A hit on a player, with no controls and no ticking damage.
pub fn player_hit(unit_id unit_id: Int) -> cast_state.Struck {
  hit_with(
    unit_id:,
    unit: cast_state.HitPlayer,
    descriptions: [],
    controls: [],
    ticking: [],
  )
}

/// The damage of a landed blow of `amount` as a description holds it: the damage taken whole,
/// no absorption, no overkill and no glance.
pub fn landed_damage(
  amount amount: Int,
  killed killed: Int,
  combat_result combat_result: combat_result.CombatResult,
  damage_type damage_type: damage_type.DamageType,
) -> SpellDamageDescription {
  SpellDamageDescription(
    raw_damage: amount,
    scaled_raw_damage: amount,
    absorbed: 0,
    shield_absorbed: 0,
    health_damage_with_overkill: amount,
    overkill: 0,
    glance: 0,
    killed:,
    combat_result:,
    damage_type:,
    hits: [],
  )
}

/// A press of the bag index as the rule gives it, the go left asked for, whose effects the
/// step gives and not its state.
pub fn pressed_effects(
  plans plans: Plans,
  state state: State,
  caster caster: Caster,
  bag_index bag_index: Int,
  at ms: Int,
) -> List(Effect) {
  let #(_, effects) =
    pressed_raw_in(plans:, state:, caster:, bag_index:, target: 0, at: ms)
  effects
}

/// A press of the spell, as the ability at the bag index, aimed at the target by the
/// default caster at `ms` on a new state, and its go answered by a round that struck these
/// units: the state, and the press's effects followed by the answer's.
pub fn pressed_and_answered(
  spell spell: Spell,
  bag_index bag_index: Int,
  target target: Int,
  struck struck: List(cast_state.Struck),
  at ms: Int,
) -> #(State, List(Effect)) {
  let #(state, effects) =
    pressed_raw_in(
      plans: plans_with(spell:),
      state: cast_state.new(),
      caster: caster(),
      bag_index:,
      target:,
      at: ms,
    )
  let #(state, answered) = answered_by(state:, effects:, at: ms, struck:)
  #(state, list.append(effects, answered))
}

/// The default caster standing at this place of the world 3460's zone 6009.
pub fn standing_at(
  caster caster: Caster,
  x x: Float,
  y y: Float,
  z z: Float,
) -> Caster {
  cast_state.Caster(
    ..caster,
    place: place_support.at(world_id: 3460, world_zone_id: 6009, x:, y:, z:),
  )
}

/// The caster moved to this east and south, at the height it stands at.
pub fn caster_at(x x: Float, z z: Float) -> Caster {
  let caster = caster()
  cast_state.Caster(
    ..caster,
    place: start_place.moved(
      place: caster.place,
      x:,
      y: start_place.y(caster.place),
      z:,
    ),
  )
}

/// The caster of a healing: support rating 400 and these health points of 736, with the
/// shield 250 of 450.
pub fn healing_caster(health health: Int) -> Caster {
  cast_state.Caster(
    ..caster(),
    stats: damage.Attacker(
      ..attacker_support.fresh(),
      level: 5,
      assault_rating: 0.0,
      support_rating: 400.0,
    ),
    vitals: damage.Vitals(
      health:,
      max_health: 736,
      shield: 250,
      max_shield: 450,
    ),
  )
}

/// The spell with no global cooldown.
pub fn without_global_cooldown(spell spell: Spell) -> Spell {
  Spell(
    ..spell,
    global_cooldown: GlobalCooldown(
      refused_while_running: False,
      starts_for_ms: None,
    ),
  )
}

/// The spell with no global cooldown and its `free_while_live` set.
pub fn free_while_live(spell spell: Spell) -> Spell {
  Spell(..without_global_cooldown(spell:), free_while_live: True)
}

/// A planted spell of the Spell4 and base given that goes at once and removes, aimed at the
/// caster, the lasting effects of the selector.
pub fn removing(
  spell4_id spell4_id: Int,
  base base: Int,
  effect_id effect_id: Int,
  selector selector: lasting.Selector,
  count count: Int,
  condition condition: spell_plan.Condition,
) -> Spell {
  with_effects(spell: child(spell4_id:, base:), kinds: [
    spell_plan.RemoveEffect(spell_plan.ForceRemove(
      effect_id: Spell4EffectsId(effect_id),
      phase_flags: -1,
      aim: spell_plan.AimsAtCaster,
      selector:,
      count:,
      condition:,
      tag: spend.always,
    )),
  ])
}

/// A lasting row that never ends, of the effect id and aim given.
pub fn marker_row(id id: Int, aim aim: spell_plan.Aim) -> spell_plan.Lasting {
  spell_plan.Lasting(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    aim:,
    row: LastingRow(delay_ms: 0, lasts: lasts.UntilRemoved),
    condition: Always,
    tag: spend.always,
  )
}

/// The resources of a class holding `value` in its slot 1, and these changes to its unit
/// properties.
pub fn holding_changing(
  class_id class_id: Int,
  value value: Float,
  changes changes: List(#(Int, Float)),
) -> class_resource.Resources {
  class_resource.new(
    resource: class_resource.Resource(
      ..class_resource_support.resource_of(class_id),
      start: value,
    ),
    properties: class_resource_support.properties_of(
      class_id:,
      changes:,
      level: 1,
    ),
  )
}

/// A creature of the client's rows, as the activation reads it.
pub fn creature_of(creature_id creature_id: Int) -> activate.Creature {
  let assert Ok(row) =
    creature2.get(tables: fixture_tables.shared(), id: Creature2Id(creature_id))
    as "the creature is a root of the fixture"
  activate.creature_of(row:)
}

/// A usable creature, alive and out of combat, whose body of radius `radius` stands this
/// far east of the unit at 4096.0, 0.0, 512.0.
pub fn usable_at(
  creature_id creature_id: Int,
  x x: Float,
  radius radius: Float,
) -> activate.Target {
  activate.Usable(
    spawn_id: SpawnId(1),
    creature_id:,
    creature: creature_of(creature_id:),
    checklist_index: 0,
    link: activate.NoLink,
    body: activate.Body(
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 6009,
        x:,
        y: 0.0,
        z: 512.0,
      ),
      radius:,
    ),
    alive: True,
    in_combat: False,
    held: [],
    unit_states: [],
    withheld: None,
  )
}

/// The cast's answer to an interaction (0x95): the client's result and word, taken by the
/// rule for this caster at `ms`.
pub fn interaction_answered(
  state state: State,
  cast_id cast_id: Int,
  result result: interaction_result.InteractionResult,
  word word: Int,
  caster caster: Caster,
  at ms: Int,
) -> Result(#(State, List(Effect)), cast_state.Refusal) {
  let assert Ok(body) =
    client_side_interaction_result.encode(ClientSideInteractionResult(
      cast_id:,
      result:,
      spell4_base_id_plus_one: word,
    ))
    as "the answer fits the message"
  cast.take(
    target_of: nothing_shown,
    cast: state,
    message: cast_state.Answered,
    body:,
    caster:,
    plans: plans(),
    now: at(ms:),
  )
}

/// A place a creature of `radius` stands at, `gap` east of the live character's place,
/// edge to edge.
pub fn place_beside_the_player(
  radius radius: Float,
  gap gap: Float,
) -> start_place.Place {
  let live = place_support.live_character_place()
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: start_place.x(live) +. place_support.player_hit_radius +. radius +. gap,
    y: start_place.y(live),
    z: start_place.z(live),
  )
}

/// The spell of the Spell4 id among the spells the trees of the client's plans reach.
pub fn real_spell(spell4_id spell4_id: Int) -> Spell {
  let assert Ok(spell) =
    list.flat_map(dict.values(real_plans()), fn(ability) {
      spell_plan.tree(spell: ability, started: fn(_) { True })
    })
    |> list.find(fn(spell) { spell.spell4_id.value == spell4_id })
    as "a tree of the plans holds the spell"
  spell
}

/// A disguise of one worn visual in slot 64.
pub fn disguise_of(display display: Int) -> Disguise {
  Disguise(shown: [
    WornVisual(slot: ItemSlotId(64), display: ItemDisplayId(display)),
  ])
}

/// A change of unit property 100, mode 2, by the factor 0.5.
pub fn slowing_change() -> unit_properties.Modifier {
  unit_properties.Change(
    property: UnitProperty2Id(100),
    mode: 2,
    multiplier: 0.5,
    flat: 0.0,
    per_level: 0.0,
  )
}

/// The number of 0x7ff the effects write for the Spell4.
pub fn started_count(
  effects effects: List(Effect),
  spell4_id spell4_id: Int,
) -> Int {
  list.count(started_in(effects:), fn(start) { start.spell4_id == spell4_id })
}

/// Phantasmal Armor tier 9's Absorption row and its UnitPropertyModifier row
/// (`table_rows -- Spell4Effects 130470 130474`).
pub const armor_absorb_id = 130_470

pub const armor_modifier_id = 130_474

/// Phantasmal Armor tier 9 as its rows plan it, holding these rows, which no level-1
/// ability's tree holds, so the committed fixture has no row of it: a Targeted spell (Mind
/// Over Body's mechanics, Spell4TargetMechanics row 4) that goes at once, in the stack group
/// 387 with a cap of 1, of the planted base 3.
pub fn armor_spell(
  rows rows: List(spell_plan.PropertyModifier),
) -> spell_plan.Spell {
  spell_plan.Spell(
    ..with_effects(
      spell: spell_plan.Spell(
        ..child(spell4_id: 54_806, base: 3),
        targeting: spell_tables.client_spell(spell4_id: 32_820).targeting,
        cooldown_ms: 0,
      ),
      kinds: list.map(rows, spell_plan.ModifierEffect),
    ),
    outlives_caster: True,
    stack: lasting.Stack(group_id: 387, cap: 1),
  )
}

/// The two rows of the armor, each aimed at the primary target.
pub fn armor_rows() -> List(spell_plan.PropertyModifier) {
  [
    armor_absorb_row(
      id: armor_absorb_id,
      support_factor: 2.605299949645996,
      aim: spell_plan.AimsAtPrimaryTarget,
    ),
    armor_modifier_row(
      id: armor_modifier_id,
      aim: spell_plan.AimsAtPrimaryTarget,
    ),
  ]
}

/// Phantasmal Armor's Absorption row as the client holds it (`table_rows -- Spell4Effects
/// 62024 130470`): effectType 29, mask 7 (dataBits04), a formula of 1.0 times `support_factor`
/// of the Support Power (parameter kind 13: 1.9388999938964844 in tier 1's row 62024,
/// 2.605299949645996 in tier 9's row 130470) and 103.41000366210938 a level (kind 10),
/// durationTime 10000, delayTime 0, phaseFlags 1, no gate; the aim is the one given (the
/// rows' own targetFlags is 2, the primary target).
pub fn armor_absorb_row(
  id id: Int,
  support_factor support_factor: Float,
  aim aim: spell_plan.Aim,
) -> spell_plan.PropertyModifier {
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(id),
    phase_flags: 1,
    change: spell_plan.AbsorbChange(spell_plan.Absorption(
      formula: damage.Formula(multiplier: 1.0, base: 0.0, parameters: [
        damage.Parameter(kind: 13, value: support_factor),
        damage.Parameter(kind: 10, value: 103.41000366210938),
        damage.Parameter(kind: 0, value: 0.0),
        damage.Parameter(kind: 0, value: 0.0),
      ]),
      mask: 7,
      aim:,
    )),
    row: LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 10_000)),
    condition: spell_plan.Always,
    tag: spend.always,
    armor: None,
  )
}

/// Phantasmal Armor's damage-reduction row, Spell4Effects 130474 (`table_rows --
/// Spell4Effects 130474`): effectType 11 on UnitProperty2 161, mode 3, multiplier
/// dataBits02 1062836634 (0.86f), flat 0, targetFlags 2 (a `StruckChange` aimed at the
/// primary target), durationTime 10000, delayTime 0, phaseFlags -1, no gate.
pub fn armor_modifier_row(
  id id: Int,
  aim aim: spell_plan.Aim,
) -> spell_plan.PropertyModifier {
  let assert Ok(multiplier) = float32.of_column(1_062_836_634)
    as "dataBits02 of row 130474 is a finite float"
  spell_plan.PropertyModifier(
    effect_id: Spell4EffectsId(id),
    phase_flags: -1,
    change: spell_plan.StruckChange(
      modifier: unit_properties.Change(
        property: UnitProperty2Id(161),
        mode: 3,
        multiplier:,
        flat: 0.0,
        per_level: 0.0,
      ),
      aim:,
    ),
    row: LastingRow(delay_ms: 0, lasts: lasts.For(duration_ms: 10_000)),
    condition: spell_plan.Always,
    tag: spend.always,
    armor: None,
  )
}
