//// The client's spell rows with Warrior Kick's damage, hit shape and valid targets
//// changed by a test, so a test can change one value and meet the build with it.
////
//// What the client's rows hold for Kick (Spell4 58591, base 38017), which `kick`
//// holds:
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
import genesis_prime/message/float32
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/table/loader/tbl_file
import genesis_prime/table/spell4_aoe_target_constraints
import genesis_prime/table/spell4_effects
import genesis_prime/table/spell4_telegraph
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
    /// The TelegraphDamage.telegraphDamageFlags of each telegraph row Kick has, in
    /// order; none for a Kick with no Spell4Telegraph row. The row at index 0 is the
    /// client's row 168; the row at index i after it is a copy with the x offset i,
    /// which tells the shapes apart.
    telegraph_flags: List(Int),
    /// Spell4Effects.dataBits00 of the damage effect: its multiplier as 32 float bits.
    multiplier_bits: Int,
    /// The formula's parameters of the damage effect as (type, value) pairs, at most
    /// four; the slots after them hold type 0 and value 0.
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
    parameters: [
      #(12, bits_value(0x3d86594b)),
      #(13, bits_value(0x3d86594b)),
      #(10, bits_value(0x40851eb8)),
    ],
  )
}

fn bits_value(number: Int) -> Float {
  let assert Ok(value) = float32.of_column(number:)
    as "a parameter of Kick is a finite float"
  value
}

/// The first id of the telegraph rows a test adds after the client's row 168.
const added_telegraph = 99_000

/// The client's rows with Kick's damage effect, hit shape and valid targets as `kick`
/// holds them.
fn kick_rows(kick kick: Kick) -> spell_tables.Rows {
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
  let telegraph_columns = fn(flags: Int) {
    [
      #("damageShapeEnum", Integer(kick.shape)),
      #("telegraphDamageFlags", Integer(flags)),
      #("targetTypeFlags", Integer(kick.telegraph_target_type_flags)),
    ]
  }
  let #(first, added) = case kick.telegraph_flags {
    [] -> #([], [])
    [first, ..rest] -> #(telegraph_columns(first), rest)
  }
  let damage =
    changed(
      rows: rows.telegraph_damage,
      schema: telegraph_damage.schema,
      id: 168,
      with: first,
    )
  let assert [client_damage] =
    list.filter(damage, fn(row) { id_of(row) == 168 })
    as "the client's rows hold TelegraphDamage 168"
  spell_tables.Rows(
    ..rows,
    spell4_effects: changed(
      rows: rows.spell4_effects,
      schema: spell4_effects.schema,
      id: 140_383,
      with: [
        #("targetFlags", Integer(kick.effect_target_flags)),
        #("dataBits00", Integer(kick.multiplier_bits)),
        ..parameters
      ],
    ),
    spell4_aoe_target_constraints: changed(
      rows: rows.spell4_aoe_target_constraints,
      schema: spell4_aoe_target_constraints.schema,
      id: 640,
      with: [#("targetSelection", Integer(kick.target_selection))],
    ),
    spell4_valid_targets: changed(
      rows: rows.spell4_valid_targets,
      schema: spell4_valid_targets.schema,
      id: 1,
      with: [#("targetBitmask", Integer(kick.target_bitmask))],
    ),
    spell4_telegraph: case kick.telegraph_flags {
      [] -> planted_table.without(rows: rows.spell4_telegraph, ids: [18_456])
      _ ->
        list.append(
          rows.spell4_telegraph,
          list.index_map(added, fn(_, index) {
            planted_table.row(spell4_telegraph.schema, [
              #("ID", Integer(added_telegraph + index + 1)),
              #("spell4Id", Integer(58_591)),
              #("telegraphDamageId", Integer(added_telegraph + index + 1)),
            ])
          }),
        )
    },
    telegraph_damage: list.append(
      damage,
      list.index_map(added, fn(flags, index) {
        let assert Ok(row) =
          fixture_tables.with_cells(
            schema: telegraph_damage.schema,
            row: client_damage,
            with: [
              #("ID", Integer(added_telegraph + index + 1)),
              #("xPositionOffset", Float(int.to_float(index + 1))),
              ..telegraph_columns(flags)
            ],
          )
          as "TelegraphDamage holds these columns"
        row
      }),
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
        spell4_effects.get(tables:, id: Spell4EffectsId(140_383))
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
