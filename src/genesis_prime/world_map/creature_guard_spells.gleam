//// The two Spell4s of a creature's guard as the creature applies them, read from the client's
//// tables once for a kind (genesis_prime/world_map/creature_kind): the guard that makes it take no
//// damage, and the opening that lifts it for a while. What the creature does with them is
//// genesis_prime/world_map/creature_guard's; this module holds only what the spells are, apart
//// from the casts, so the kind can hold them (the casts import the kind).
////
//// - **The guard** is a Spell4 with one effect of type 79 (SpellEffectImmunity) immune to Damage,
////   `dataBits00` 8, which the client reads nowhere (`Spell4Effects.effectType.79`).
//// - **The opening** is a Spell4 whose effects are of the types the creature applies only: 81
////   (RavelSignal), 4 (CCStateSet), 80 (SpellForceRemove), 17 (Fluff) and 26 (Proxy). Its length is the
////   delay of its Proxy effect that puts the guard back (`Spell4Effects.effectType.26`).

import genesis_prime/game/effect_kind
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result

/// What a creature with a guard has of it: the Spell4 that guards and the effect of it that
/// makes the immunity (type 79, which the creature applies to Damage only), and the opening.
pub type Guard {
  Guard(spell4_id: Int, effect_id: Int, opening: Opening)
}

/// The Spell4 that opens the creature: each effect it applies to the creature, in the order of the
/// spell's rows, and how long the opening lasts, the delay of its Proxy effect (type 26) that puts
/// the guard back.
pub type Opening {
  Opening(spell4_id: Int, effects: List(OpeningEffect), ends_after_ms: Int)
}

/// One effect of the opening that the cast's go lists for the creature: its row, the
/// crowd-control state it sets (a CCStateSet effect, type 4), and its lifetime in
/// milliseconds. Effects the client gives no behaviour (types 80, 81 and 26) are not listed; Fluff
/// (type 17) is, with no state, for the buff it makes.
pub type OpeningEffect {
  OpeningEffect(
    effect_id: Int,
    state: Option(CrowdControlState),
    lifetime_ms: Int,
  )
}

/// Why the creature cannot apply the two spells.
pub type Unapplied {
  /// The client's Spell4 holds no row of this id.
  SpellMissing(spell4_id: Int)
  /// The guard has no effect of type 79 that is immune to Damage.
  NoImmunityToDamage(spell4_id: Int)
  /// The opening has an effect of a type the creature does not apply (it applies 81, 4, 80, 17
  /// and 26 only).
  EffectNotApplied(spell4_id: Int, effect_id: Int, effect_type: Int)
  /// The opening has no Proxy effect that puts the guard back, so it would never end.
  NeverEnds(spell4_id: Int)
}

/// The guard of the two spells, or why the creature cannot apply them. The content load refuses
/// a kind with it and a spawn starts its creature with the guard (genesis_prime/world_map/creature_kind,
/// genesis_prime/world_map/spawn).
pub fn guard_of(
  guard_spell4_id guard_spell4_id: Int,
  opening_spell4_id opening_spell4_id: Int,
  tables tables: table_store.Tables,
) -> Result(Guard, Unapplied) {
  use Nil <- result.try(held(tables:, spell4_id: guard_spell4_id))
  use Nil <- result.try(held(tables:, spell4_id: opening_spell4_id))
  use immunity <- result.try(
    effects_of(tables:, spell4_id: guard_spell4_id)
    |> list.find(fn(effect) {
      effect.effect_type == immunity_type
      && effect.data_bits00 == damage_effect_type
    })
    |> result.replace_error(NoImmunityToDamage(spell4_id: guard_spell4_id)),
  )
  let rows = effects_of(tables:, spell4_id: opening_spell4_id)
  use Nil <- result.try(
    case
      list.find(rows, fn(effect) {
        !applied(kind: effect_kind.kind_of(effect.effect_type))
      })
    {
      Ok(effect) ->
        Error(EffectNotApplied(
          spell4_id: opening_spell4_id,
          effect_id: effect.id,
          effect_type: effect.effect_type,
        ))
      Error(Nil) -> Ok(Nil)
    },
  )
  use proxy <- result.try(
    list.find(rows, fn(effect) {
      effect_kind.kind_of(effect.effect_type) == effect_kind.Proxy
      && effect.data_bits00 == guard_spell4_id
    })
    |> result.replace_error(NeverEnds(spell4_id: opening_spell4_id)),
  )
  Ok(Guard(
    spell4_id: guard_spell4_id,
    effect_id: immunity.id,
    opening: Opening(
      spell4_id: opening_spell4_id,
      effects: list.filter_map(rows, listed),
      ends_after_ms: proxy.delay_time,
    ),
  ))
}

/// The effect type of SpellEffectImmunity and the effect type of Damage that its dataBits00 names
/// (`Spell4Effects.effectType.79`).
const immunity_type = 79

const damage_effect_type = 8

/// Whether the creature applies an effect of this kind in an opening.
fn applied(kind kind: effect_kind.Kind) -> Bool {
  case kind {
    effect_kind.RavelSignal
    | effect_kind.CrowdControl
    | effect_kind.ForceRemove
    | effect_kind.Fluff
    | effect_kind.Proxy -> True
    effect_kind.Damage
    | effect_kind.VitalModifier
    | effect_kind.PropertyModifier
    | effect_kind.ForcedMove
    | effect_kind.CooldownModifier
    | effect_kind.Stealth
    | effect_kind.RemoveStealth
    | effect_kind.Heal(..)
    | effect_kind.ShieldOverload
    | effect_kind.Proc
    | effect_kind.InterruptArmor
    | effect_kind.Scale
    | effect_kind.PropertyConversion
    | effect_kind.DisguiseOutfit
    | effect_kind.Absorption
    | effect_kind.Activate
    | effect_kind.Unread(..) -> False
  }
}

/// The effect the go lists for the creature, if it is one: a CCStateSet with its state, or a Fluff.
fn listed(effect effect: Spell4Effects) -> Result(OpeningEffect, Nil) {
  case effect_kind.kind_of(effect.effect_type) {
    effect_kind.CrowdControl ->
      Ok(OpeningEffect(
        effect_id: effect.id,
        state: Some(crowd_control_state.from_value(effect.data_bits00)),
        lifetime_ms: effect.duration_time,
      ))
    effect_kind.Fluff ->
      Ok(OpeningEffect(
        effect_id: effect.id,
        state: None,
        lifetime_ms: effect.duration_time,
      ))
    effect_kind.RavelSignal
    | effect_kind.ForceRemove
    | effect_kind.Proxy
    | effect_kind.Damage
    | effect_kind.VitalModifier
    | effect_kind.PropertyModifier
    | effect_kind.ForcedMove
    | effect_kind.CooldownModifier
    | effect_kind.Stealth
    | effect_kind.RemoveStealth
    | effect_kind.Heal(..)
    | effect_kind.ShieldOverload
    | effect_kind.Proc
    | effect_kind.InterruptArmor
    | effect_kind.Scale
    | effect_kind.PropertyConversion
    | effect_kind.DisguiseOutfit
    | effect_kind.Absorption
    | effect_kind.Activate
    | effect_kind.Unread(..) -> Error(Nil)
  }
}

/// Whether the client's Spell4 holds the spell.
fn held(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> Result(Nil, Unapplied) {
  spell4.get(tables:, id: Spell4Id(spell4_id))
  |> result.replace(Nil)
  |> result.replace_error(SpellMissing(spell4_id:))
}

/// The spell's effects in the order they take effect (`Spell4Effects.orderIndex`, then the row id).
fn effects_of(
  tables tables: table_store.Tables,
  spell4_id spell4_id: Int,
) -> List(Spell4Effects) {
  spell4_effects.all(tables)
  |> list.filter(fn(effect) { effect.spell_id == spell4_id })
  |> list.sort(fn(first, second) {
    int.compare(first.order_index, second.order_index)
    |> order.break_tie(int.compare(first.id, second.id))
  })
}

/// The refusal's sentence: the spell and what the creature cannot do with it.
pub fn describe(unapplied unapplied: Unapplied) -> String {
  case unapplied {
    SpellMissing(spell4_id:) ->
      "Spell4 " <> int.to_string(spell4_id) <> " is not in the client's table"
    NoImmunityToDamage(spell4_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " as a guard has no effect of type 79 that is immune to Damage"
    EffectNotApplied(spell4_id:, effect_id:, effect_type:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " as an opening has effect "
      <> int.to_string(effect_id)
      <> " of type "
      <> int.to_string(effect_type)
      <> ", which the creature does not apply"
    NeverEnds(spell4_id:) ->
      "Spell4 "
      <> int.to_string(spell4_id)
      <> " as an opening has no Proxy effect that puts the guard back"
  }
}
