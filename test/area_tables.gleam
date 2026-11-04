//// The planted tables of the spell areas' tests: the planted spell rows
//// (`spell_tables`, each the client's own) with Warrior Kick's damage, hit shape and
//// valid targets added (Spell4 58591, base 38017; the fact file's `Spell4.58591.area`),
//// so a test can change one value and meet the build with it.
////
//// What the client's rows hold, which `kick` plants:
//// - Spell4 58591: Spell4AoeTargetConstraints 640 (5 units, 0 to 8 m, 180 degrees,
////   Closest), global cooldown kind 3 (from `spell_tables`).
//// - Spell4Base 38017: Spell4ValidTargets 1, bitmask 0.
//// - Spell4Telegraph to TelegraphDamage 168: a cone from 1 to 7 m over 100 degrees,
////   placed on the caster (targetTypeFlags 1), flag 0x200, drawn while casting.
//// - Spell4Effects: one Physical damage effect aimed at the area (targetFlags 4).

import genesis_prime/game/spell_area.{type AreaError, type Areas}
import genesis_prime/game/spell_plan
import genesis_prime/message/float32
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/telegraph_damage
import planted_table.{Float, Integer}
import spell_tables

/// The values of the planted Kick that a test changes to meet a refusal.
pub type Kick {
  Kick(
    /// Spell4AoeTargetConstraints.targetSelection.
    target_selection: Int,
    /// Spell4ValidTargets.targetBitmask.
    target_bitmask: Int,
    /// TelegraphDamage.targetTypeFlags.
    telegraph_target_type_flags: Int,
    /// TelegraphDamage.damageShapeEnum.
    shape: Int,
    /// Spell4Effects.targetFlags of the damage effect.
    effect_target_flags: Int,
    /// Whether the Spell4Telegraph row exists.
    has_telegraph: Bool,
    /// Spell4Effects.dataBits00 of the damage effect: its multiplier as 32 float bits.
    multiplier_bits: Int,
  )
}

/// Kick as the client's rows hold it.
pub fn kick() -> Kick {
  Kick(
    target_selection: 1,
    target_bitmask: 0,
    telegraph_target_type_flags: 1,
    shape: 4,
    effect_target_flags: 4,
    has_telegraph: True,
    multiplier_bits: float32.to_bits(1.0),
  )
}

/// The planted spell rows with Kick's damage, hit shape and valid targets as `kick`
/// holds them.
fn kick_rows(kick kick: Kick) -> spell_tables.Rows {
  let rows = spell_tables.rows()
  spell_tables.Rows(
    ..rows,
    spell4_effects: spell_tables.sorted_by_id([
      spell_tables.damage_effect_row(
        id: 1,
        spell: 58_591,
        damage_type: 1,
        target_flags: kick.effect_target_flags,
        delay: 166,
        multiplier_bits: kick.multiplier_bits,
        parameters: [],
      ),
      ..rows.spell4_effects
    ]),
    spell4_aoe_target_constraints: spell_tables.sorted_by_id([
      spell_tables.aoe_row_selecting(
        id: 640,
        angle: 180.0,
        count: 5,
        max_range: 8.0,
        selection: kick.target_selection,
      ),
      ..planted_table.without(rows: rows.spell4_aoe_target_constraints, ids: [
        640,
      ])
    ]),
    spell4_valid_targets: [
      spell_tables.valid_targets_row(bitmask: kick.target_bitmask),
    ],
    spell4_telegraph: case kick.has_telegraph {
      True -> [
        planted_table.row(spell4_telegraph.schema, [
          #("ID", Integer(1)),
          #("spell4Id", Integer(58_591)),
          #("telegraphDamageId", Integer(168)),
        ]),
      ]
      False -> []
    },
    telegraph_damage: [
      planted_table.row(telegraph_damage.schema, [
        #("ID", Integer(168)),
        #("damageShapeEnum", Integer(kick.shape)),
        #("param00", Float(1.0)),
        #("param01", Float(7.0)),
        #("param02", Float(100.0)),
        #("telegraphDamageFlags", Integer(0x200)),
        #("targetTypeFlags", Integer(kick.telegraph_target_type_flags)),
        #("phaseFlags", Integer(-1)),
        #("displayFlags", Integer(4)),
      ]),
    ],
  )
}

/// What the areas' build makes of the planted Kick.
pub fn built(kick kick: Kick) -> Result(Areas, AreaError) {
  spell_tables.with_loaded_deriving(
    rows: kick_rows(kick:),
    derivations: [spell_plan.derivation()],
    body: fn(tables) { spell_area.build(tables:) },
  )
}
