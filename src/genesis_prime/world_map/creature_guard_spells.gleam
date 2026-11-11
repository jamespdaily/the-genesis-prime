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

import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/table/loader/store as table_store
import gleam/int
import gleam/option.{type Option}

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
  guard_spell4_id _guard_spell4_id: Int,
  opening_spell4_id _opening_spell4_id: Int,
  tables _tables: table_store.Tables,
) -> Result(Guard, Unapplied) {
  panic as "shape: #655 guard_of reads Spell4 and Spell4Effects: type 79 immune to Damage for the guard; 81, 4, 80, 17 and 26 for the opening, its end from the Proxy's delay"
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
