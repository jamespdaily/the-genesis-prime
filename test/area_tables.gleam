//// The client's spell rows with Warrior Kick's damage, hit shape and valid targets
//// changed by a test, so a test can change one value and meet the refusal with it.
////
//// `kick` reads the values of Kick (Spell4 58591) from the client's rows, which are
//// these:
//// - Spell4AoeTargetConstraints 640: 5 units, 0 to 8 m, 180 degrees, Closest.
//// - Spell4ValidTargets 1: bitmask 0.
//// - Spell4Telegraph 18456 to TelegraphDamage 168: a cone from 1 to 7 m over 100
////   degrees, placed on the caster (targetTypeFlags 1), flag 0x200.
//// - Spell4Effects 140383: one Physical damage effect aimed at the area (targetFlags
////   4), multiplier 1.0, with the formula's parameters of kinds 12, 13 and 10.

import fixture_tables
import genesis_prime/coverage/effect_row
import genesis_prime/game/spell_area.{type AreaError, type Areas}
import genesis_prime/game/spell_plan
import genesis_prime/table/id.{
  Spell4AoeTargetConstraintsId, Spell4EffectsId, Spell4ValidTargetsId,
  TelegraphDamageId,
}
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_valid_targets
import genesis_prime/table/telegraph_damage
import gleam/int
import gleam/list
import planted_table.{type Cell, Float, Integer}
import spell_tables

/// The values of Kick that a test changes to meet a refusal.
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
    /// Spell4Effects.dataBits00 of the damage effect: its multiplier as 32 float bits.
    multiplier_bits: Int,
    /// The formula's parameters of the damage effect as (type, value) pairs, at most
    /// four; the slots after them hold type 0 and value 0.
    parameters: List(#(Int, Float)),
  )
}

/// The ids of the client's rows Kick's values are read from.
const area_row = 640

const valid_targets_row = 1

const telegraph_row = 168

const effect_row_id = 140_383

/// Kick as the client's rows hold it, read from the typed records of the shared
/// tables.
pub fn kick() -> Kick {
  let tables = fixture_tables.shared()
  let assert Ok(effect) =
    spell4_effects.get(tables:, id: Spell4EffectsId(effect_row_id))
    as "the rows hold Kick's damage effect"
  let assert Ok(area) =
    spell4_aoe_target_constraints.get(
      tables:,
      id: Spell4AoeTargetConstraintsId(area_row),
    )
    as "the rows hold Kick's area"
  let assert Ok(valid_targets) =
    spell4_valid_targets.get(
      tables:,
      id: Spell4ValidTargetsId(valid_targets_row),
    )
    as "the rows hold Kick's valid targets"
  let assert Ok(telegraph) =
    telegraph_damage.get(tables:, id: TelegraphDamageId(telegraph_row))
    as "the rows hold Kick's telegraph"
  Kick(
    target_selection: area.target_selection,
    target_bitmask: valid_targets.target_bitmask,
    telegraph_target_type_flags: telegraph.target_type_flags,
    shape: telegraph.damage_shape_enum,
    effect_target_flags: effect.target_flags,
    multiplier_bits: effect.data_bits00,
    parameters: list.filter(
      [
        #(effect.parameter_type00, effect.parameter_value00),
        #(effect.parameter_type01, effect.parameter_value01),
        #(effect.parameter_type02, effect.parameter_value02),
        #(effect.parameter_type03, effect.parameter_value03),
      ],
      fn(parameter) { parameter.0 != 0 },
    ),
  )
}

/// The client's rows with Kick's damage effect, hit shape and valid targets as `kick`
/// holds them.
pub fn kick_rows(kick kick: Kick) -> spell_tables.Rows {
  let rows = spell_tables.fixture_rows()
  let parameters =
    list.append(
      kick.parameters,
      list.repeat(#(0, 0.0), times: 4 - list.length(kick.parameters)),
    )
    |> list.index_map(fn(parameter, index) {
      let number = int.to_string(index)
      [
        #("parameterType0" <> number, Integer(parameter.0)),
        #("parameterValue0" <> number, Float(parameter.1)),
      ]
    })
    |> list.flatten
  spell_tables.Rows(
    ..rows,
    spell4_effects: changed(
      rows: rows.spell4_effects,
      schema: spell4_effects.schema,
      id: effect_row_id,
      with: [
        #("targetFlags", Integer(kick.effect_target_flags)),
        #("dataBits00", Integer(kick.multiplier_bits)),
        ..parameters
      ],
    ),
    spell4_aoe_target_constraints: changed(
      rows: rows.spell4_aoe_target_constraints,
      schema: spell4_aoe_target_constraints.schema,
      id: area_row,
      with: [#("targetSelection", Integer(kick.target_selection))],
    ),
    spell4_valid_targets: changed(
      rows: rows.spell4_valid_targets,
      schema: spell4_valid_targets.schema,
      id: valid_targets_row,
      with: [#("targetBitmask", Integer(kick.target_bitmask))],
    ),
    telegraph_damage: changed(
      rows: rows.telegraph_damage,
      schema: telegraph_damage.schema,
      id: telegraph_row,
      with: [
        #("damageShapeEnum", Integer(kick.shape)),
        #("targetTypeFlags", Integer(kick.telegraph_target_type_flags)),
      ],
    ),
  )
}

/// The rows with the named columns of row `id` replaced; the row must be held.
fn changed(
  rows rows: List(List(Cell)),
  schema schema: tbl_file.Schema,
  id id: Int,
  with changes: List(#(String, Cell)),
) -> List(List(Cell)) {
  assert list.any(rows, fn(row) { id_of(row) == id })
    as "the client's rows hold the row Kick changes"
  list.map(rows, fn(row) {
    case id_of(row) == id {
      True -> {
        let assert Ok(row) =
          fixture_tables.with_cells(schema:, row:, with: changes)
          as "the table holds the columns Kick changes"
        row
      }
      False -> row
    }
  })
}

fn id_of(row: List(Cell)) -> Int {
  let assert [Integer(id), ..] = row as "a client row holds its id first"
  id
}

/// What the areas' build makes of the client's rows with Kick as `kick` holds it.
pub fn built(kick kick: Kick) -> Result(Areas, AreaError) {
  spell_tables.with_loaded_deriving(
    rows: kick_rows(kick:),
    reaching: [#("SpellLevel", 925)],
    derivations: [spell_plan.derivation()],
    body: fn(tables) { spell_area.build(tables:) },
  )
}

/// Whether the coverage measure counts Kick's damage effect as read: the plan's
/// decision about the row in a spell nothing starts on each struck unit
/// (`genesis_prime/coverage/effect_row`).
pub fn read_by_the_measure(kick kick: Kick) -> Bool {
  spell_tables.with_loaded(
    reaching: [#("SpellLevel", 925)],
    rows: kick_rows(kick:),
    body: fn(tables) {
      let assert Ok(row) =
        spell4_effects.get(tables:, id: Spell4EffectsId(effect_row_id))
        as "Kick holds its damage effect, row 140383"
      effect_row.is_read(
        tables:,
        spell_groups: spell_plan.spell_groups(tables:),
        place: spell_tables.pressed,
        effect: row,
      )
    },
  )
}
