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

import genesis_prime/coverage/effect_row
import genesis_prime/game/spell_area.{type AreaError, type Areas}
import genesis_prime/game/spell_plan
import genesis_prime/message/float32
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/telegraph_damage
import gleam/int
import gleam/list
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
    /// The TelegraphDamage.telegraphDamageFlags of each telegraph row Kick has, in
    /// order; none for a Kick with no Spell4Telegraph row. The row at index i has id
    /// 168 + i and the x offset i, which tells the shapes apart.
    telegraph_flags: List(Int),
    /// Spell4Effects.dataBits00 of the damage effect: its multiplier as 32 float bits.
    multiplier_bits: Int,
    /// The formula's parameters of the damage effect as (type, value) pairs.
    parameters: List(#(Int, Float)),
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
    telegraph_flags: [0x200],
    multiplier_bits: float32.to_bits(1.0),
    parameters: [],
  )
}

/// The client's rows with Kick's damage effect, hit shape and valid targets as `kick`
/// holds them.
fn kick_rows(kick kick: Kick) -> spell_tables.Rows {
  let rows = spell_tables.fixture_rows()
  spell_tables.Rows(
    ..rows,
    spell4_effects: list.map(rows.spell4_effects, fn(row) {
      case row {
        [Integer(140_383), ..] ->
          spell_tables.damage_effect_row(
            id: 140_383,
            spell: 58_591,
            damage_type: 1,
            target_flags: kick.effect_target_flags,
            delay: 166,
            multiplier_bits: kick.multiplier_bits,
            parameters: kick.parameters,
          )
        other -> other
      }
    }),
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
    spell4_telegraph: list.index_map(kick.telegraph_flags, fn(_, index) {
      planted_table.row(spell4_telegraph.schema, [
        #("ID", Integer(index + 1)),
        #("spell4Id", Integer(58_591)),
        #("telegraphDamageId", Integer(168 + index)),
      ])
    }),
    telegraph_damage: list.index_map(kick.telegraph_flags, fn(flags, index) {
      planted_table.row(telegraph_damage.schema, [
        #("ID", Integer(168 + index)),
        #("damageShapeEnum", Integer(kick.shape)),
        #("param00", Float(1.0)),
        #("param01", Float(7.0)),
        #("param02", Float(100.0)),
        #("xPositionOffset", Float(int.to_float(index))),
        #("telegraphDamageFlags", Integer(flags)),
        #("targetTypeFlags", Integer(kick.telegraph_target_type_flags)),
        #("phaseFlags", Integer(-1)),
        #("displayFlags", Integer(4)),
      ])
    }),
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

/// Whether the coverage measure counts Kick's damage effect as read: the plan's
/// decision about the row in a spell nothing starts on each struck unit
/// (`genesis_prime/coverage/effect_row`).
pub fn read_by_the_measure(kick kick: Kick) -> Bool {
  spell_tables.with_loaded(rows: kick_rows(kick:), body: fn(tables) {
    let assert Ok(row) =
      spell4_effects.get(tables:, id: Spell4EffectsId(140_383))
      as "Kick holds its damage effect, row 140383"
    effect_row.is_read(
      tables:,
      spell_groups: spell_plan.spell_groups(tables:),
      place: spell_tables.pressed,
      effect: row,
    )
  })
}
