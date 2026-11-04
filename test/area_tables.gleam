//// The planted tables of the spell areas' tests: Warrior Kick (Spell4 58591, base
//// 38017) with the rows `genesis_prime/game/spell_area` reads, each holding the value
//// the client's own row does (the fact file's `Spell4.58591.area`), and a load of just
//// those tables, so a test can change one value and meet the build with it.
////
//// What the client's rows hold, which `kick` plants:
//// - Spell4 58591: Spell4AoeTargetConstraints 640 (5 units, 0 to 8 m, 180 degrees,
////   Closest), global cooldown kind 3.
//// - Spell4Base 38017: Spell4ValidTargets 1, bitmask 0.
//// - Spell4Telegraph to TelegraphDamage 168: a cone from 1 to 7 m over 100 degrees,
////   placed on the caster (targetTypeFlags 1), flag 0x200, drawn while casting.
//// - Spell4Effects: one Physical damage effect aimed at the area (targetFlags 4).

import genesis_prime/game/spell_area.{type AreaError, type Areas}
import genesis_prime/game/spell_plan
import genesis_prime/message/float32
import genesis_prime/table/class
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/spell4
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_base
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_telegraph
import genesis_prime/table/spell4_valid_targets
import genesis_prime/table/spell_cool_down
import genesis_prime/table/spell_level
import genesis_prime/table/spell_phase
import genesis_prime/table/telegraph_damage
import gleam/erlang/reference
import planted_table.{Float, Integer}

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

fn files_of(kick kick: Kick) -> List(#(String, BitArray)) {
  [
    planted_table.file(spell_level.schema, [
      planted_table.row(spell_level.schema, [
        #("ID", Integer(925)),
        #("classId", Integer(1)),
        #("characterLevel", Integer(1)),
        #("prerequisiteId", Integer(0)),
        #("spell4Id", Integer(58_591)),
      ]),
    ]),
    planted_table.file(spell4.schema, [
      planted_table.row(spell4.schema, [
        #("ID", Integer(58_591)),
        #("spell4BaseIdBaseSpell", Integer(38_017)),
        #("spellCoolDown", Integer(20_000)),
        #("globalCooldownEnum", Integer(3)),
        #("spell4AoeTargetConstraintsId", Integer(640)),
        #("propertyFlags", Integer(0x4000102)),
      ]),
    ]),
    planted_table.file(spell4_base.schema, [
      planted_table.row(spell4_base.schema, [
        #("ID", Integer(38_017)),
        #("classIdPlayer", Integer(1)),
        #("spell4ValidTargetId", Integer(1)),
      ]),
    ]),
    planted_table.file(spell4_effects.schema, [
      planted_table.row(spell4_effects.schema, [
        #("ID", Integer(1)),
        #("spellId", Integer(58_591)),
        #("targetFlags", Integer(kick.effect_target_flags)),
        #("effectType", Integer(8)),
        #("damageType", Integer(1)),
        #("delayTime", Integer(166)),
        #("phaseFlags", Integer(-1)),
        #("dataBits00", Integer(kick.multiplier_bits)),
      ]),
    ]),
    planted_table.file(spell_phase.schema, []),
    planted_table.file(spell_cool_down.schema, []),
    planted_table.file(class.schema, []),
    planted_table.file(spell4_aoe_target_constraints.schema, [
      planted_table.row(spell4_aoe_target_constraints.schema, [
        #("ID", Integer(640)),
        #("angle", Float(180.0)),
        #("targetCount", Integer(5)),
        #("minRange", Float(0.0)),
        #("maxRange", Float(8.0)),
        #("targetSelection", Integer(kick.target_selection)),
      ]),
    ]),
    planted_table.file(spell4_valid_targets.schema, [
      planted_table.row(spell4_valid_targets.schema, [
        #("ID", Integer(1)),
        #("targetBitmask", Integer(kick.target_bitmask)),
      ]),
    ]),
    planted_table.file(spell4_telegraph.schema, case kick.has_telegraph {
      True -> [
        planted_table.row(spell4_telegraph.schema, [
          #("ID", Integer(1)),
          #("spell4Id", Integer(58_591)),
          #("telegraphDamageId", Integer(168)),
        ]),
      ]
      False -> []
    }),
    planted_table.file(telegraph_damage.schema, [
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
    ]),
  ]
}

fn entries() -> List(table_store.Entry) {
  [
    spell_level.entry(),
    spell4.entry(),
    spell4_base.entry(),
    spell4_effects.entry(),
    spell_phase.entry(),
    spell_cool_down.entry(),
    class.entry(),
    spell4_aoe_target_constraints.entry(),
    spell4_valid_targets.entry(),
    spell4_telegraph.entry(),
    telegraph_damage.entry(),
  ]
}

/// The planted tables, loaded with the ability trees' derivation, for the body to
/// run on; unloaded afterwards.
pub fn with_loaded(
  kick kick: Kick,
  body body: fn(table_store.Tables) -> a,
) -> a {
  use folder <- planted_table.in_folder(files_of(kick:))
  let assert Ok(tables) =
    table_store.load(
      under: reference.new(),
      from: folder,
      entries: entries(),
      requirements: [],
      derivations: [spell_plan.derivation()],
    )
    as "the planted tables load"
  let result = body(tables)
  table_store.unload(tables)
  result
}

/// What the areas' build makes of the planted Kick.
pub fn built(kick kick: Kick) -> Result(Areas, AreaError) {
  with_loaded(kick:, body: fn(tables) { spell_area.build(tables:) })
}
