//// The forced moves of the plan (`genesis_prime/game/spell_plan` `ForcedMove`,
//// `genesis_prime/game/effect_kind`). Expected values come from these places:
//// - `Spell4Effects.effectType.3`: the kit's one row is 67776 (Gate's blink: delay
////   200 ms, phaseFlags 1, aimed at the caster), from
////   `table_rows -- Spell4Effects 67776`, and its spell 34355 also holds 67777.
//// - `Spell4Effects.effectType.3.player`: the client moves its own unit for a row aimed
////   at the caster, so the plan reads those rows as a `ForcedMove`; the server moves the
////   creatures a row aimed at others names, so those rows are a `StruckMove`.
//// - `Spell4Effects.effectType.3.other_unit`: the columns of 73826 (spell 36010) are kind 4,
////   10.0 m, 375 ms, flags 1, apex 2.0 (`table_rows -- Spell4Effects 73826`).
//// - `Spell4Effects.targetFlags`: bit 1 is the caster, 2 the primary target, 4 the
////   area.

import client_tables
import genesis_prime/game/effect_kind
import genesis_prime/game/forced_move
import genesis_prime/game/lasting.{LastingRow}
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{Always, GatedOnCaster, GatedOnTarget}
import genesis_prime/game/spend
import genesis_prime/game/unit_properties.{Change}
import genesis_prime/table/id.{
  PrerequisiteId, Spell4BaseId, Spell4EffectsId, UnitProperty2Id,
}
import genesis_prime/table/spell4_effects
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import planted_table.{type Cell, Integer}
import spell_tables
import unitest

/// Telekinetic Strike's Spell4 and base, whose tree the planted rows hold
/// (`spell_tables`).
const strike = 32_893

/// A type 3 row of a planted spell aimed by `target_flags`, in every phase, as Gate's
/// 67776 is but for its phase, with these columns beside its id, spell and type.
fn forced_move_row(
  id id: Int,
  target_flags target_flags: Int,
  columns columns: List(#(String, Cell)),
) -> List(Cell) {
  let defaults = [
    #("ID", Integer(id)),
    #("spellId", Integer(strike)),
    #("effectType", Integer(3)),
    #("targetFlags", Integer(target_flags)),
    #("phaseFlags", Integer(-1)),
    #("orderIndex", Integer(9)),
  ]
  planted_table.row(
    spell4_effects.schema,
    list.append(
      list.filter(defaults, fn(default) {
        !list.any(columns, fn(given) { given.0 == default.0 })
      }),
      columns,
    ),
  )
}

fn forced_moves_of(row row: List(Cell)) -> List(spell_plan.ForcedMove) {
  let assert Ok(spell) =
    spell_tables.planned_strike(rows: spell_tables.rows_with_effect(effect: row))
  spell.forced_moves
}

// ---- the rows of the plan ----

pub fn gates_row_aimed_at_the_caster_is_read_with_its_columns_test() -> Nil {
  use <- owned_test.run(60_000)
  // The shape of 67776 as the client holds it (delay 200, phase flags 1), planted under
  // an id no client row holds.
  assert forced_moves_of(
      row: forced_move_row(id: 99_068, target_flags: 1, columns: [
        #("delayTime", Integer(200)),
        #("phaseFlags", Integer(1)),
      ]),
    )
    == [
      spell_plan.ForcedMove(
        effect_id: Spell4EffectsId(99_068),
        phase_flags: 1,
        delay_ms: 200,
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
    as "the row's emmComparison 0 and emmValue 0 are the tag"
}

pub fn a_row_aimed_at_the_primary_target_or_the_area_is_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // The columns of Spell4Effects 73826 (spell 36010): kind 4 (away from a unit), 10.0 m
  // (bits 1092616192) from both distance columns, 375 ms, flags 1, apex 2.0 (bits
  // 1073741824); targetFlags 2 is the primary target, 4 the area and 6 both
  // (`Spell4Effects.targetFlags`), planted with a delay of 200 ms in phase 1.
  let move =
    forced_move.Move(
      way: forced_move.Away,
      mover: forced_move.Flight,
      min_distance: 10.0,
      max_distance: 10.0,
      flight_ms: 375,
      gravity: 0.0,
      flags: 1,
      height: 2.0,
    )
  list.each(
    [
      #(2, spell_plan.AimsAtPrimaryTarget),
      #(4, spell_plan.AimsAtArea),
      #(6, spell_plan.AimsAtBoth),
    ],
    fn(aimed) {
      let assert Ok(spell) =
        spell_tables.planned_strike(
          rows: spell_tables.rows_with_effect(
            effect: forced_move_row(id: 99_061, target_flags: aimed.0, columns: [
              #("phaseFlags", Integer(1)),
              #("delayTime", Integer(200)),
              #("dataBits00", Integer(4)),
              #("dataBits01", Integer(1_092_616_192)),
              #("dataBits02", Integer(1_092_616_192)),
              #("dataBits03", Integer(375)),
              #("dataBits05", Integer(1)),
              #("dataBits06", Integer(1_073_741_824)),
            ]),
          ),
        )
      assert spell.struck_moves
        == [
          spell_plan.StruckMove(
            effect_id: Spell4EffectsId(99_061),
            phase_flags: 1,
            delay_ms: 200,
            move:,
            aim: aimed.1,
            condition: Always,
            tag: spend.EqualTo(value: 0),
          ),
        ]
        as "a row aimed at the units a strike hits is a struck move, its columns decoded"
      assert spell.forced_moves == []
        as "and no move of the caster's: the caster is not an aim of the row"
    },
  )
  // 3, 5 and 7 include the caster: the caster's part is the `ForcedMove`, and the
  // struck units' part is not applied (the cast moves the creatures a row aimed
  // only at them names).
  list.each([3, 5, 7], fn(flags) {
    let assert Ok(spell) =
      spell_tables.planned_strike(
        rows: spell_tables.rows_with_effect(
          effect: forced_move_row(id: 99_063, target_flags: flags, columns: []),
        ),
      )
    assert spell.struck_moves == []
      as "a row that includes the caster moves the caster only"
    assert list.length(spell.forced_moves) == 1
  })
}

pub fn a_row_behind_a_target_apply_prerequisite_is_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  // Prerequisite 5 as the planted tables hold it: a row aimed at the units a strike hits
  // behind it would throw units that fail it, so the plan refuses the row until issue 815
  // reads the gate of a struck unit.
  assert spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: forced_move_row(id: 99_064, target_flags: 2, columns: [
          #("prerequisiteIdTargetApply", Integer(5)),
        ]),
      ),
    )
    == Error(spell_plan.StruckMoveBehindTargetPrerequisite(
      spell4_id: strike,
      effect_id: 99_064,
    ))
  let assert Error(error) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: forced_move_row(id: 99_064, target_flags: 2, columns: [
          #("prerequisiteIdTargetApply", Integer(5)),
        ]),
      ),
    )
  assert string.contains(spell_plan.describe(error:), "issue 815")
    as "the refusal names the issue that will read it"
}

pub fn a_row_aimed_at_the_caster_and_others_is_read_for_the_caster_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3, 5 and 7 include the caster: its part is read, the rest is not applied.
  list.each([3, 5, 7], fn(flags) {
    let assert [row] =
      forced_moves_of(
        row: forced_move_row(id: 99_062, target_flags: flags, columns: []),
      )
    assert row.effect_id == Spell4EffectsId(99_062)
  })
}

pub fn a_row_behind_a_caster_prerequisite_is_gated_on_the_caster_and_behind_a_target_one_is_not_applied_test() -> Nil {
  use <- owned_test.run(60_000)
  let assert [caster] =
    forced_moves_of(
      row: forced_move_row(id: 99_065, target_flags: 1, columns: [
        #("prerequisiteIdCasterApply", Integer(17_302)),
      ]),
    )
  let assert GatedOnCaster(gates: [_]) = caster.condition
  let assert [target] =
    forced_moves_of(
      row: forced_move_row(id: 99_066, target_flags: 1, columns: [
        #("prerequisiteIdTargetApply", Integer(5)),
      ]),
    )
  let assert GatedOnTarget(prerequisite: gate) = target.condition
  assert prerequisite.id(prerequisite: gate) == PrerequisiteId(5)
}

pub fn the_rows_of_a_phase_are_those_whose_phase_flags_name_it_test() -> Nil {
  use <- owned_test.run(60_000)
  // phaseFlags bit n is phase n (`Spell4Effects.phaseFlags`).
  let assert Ok(spell) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: forced_move_row(id: 99_067, target_flags: 1, columns: [
          #("phaseFlags", Integer(2)),
        ]),
      ),
    )
  assert spell_plan.forced_moves_in_phase(spell:, phase: 0, spent: None) == []
  assert list.length(spell_plan.forced_moves_in_phase(
      spell:,
      phase: 1,
      spent: None,
    ))
    == 1
}

// ---- the effect kind ----

pub fn type_3_is_read_for_the_rows_aimed_at_the_caster_or_the_struck_units_test() -> Nil {
  use <- owned_test.run(5000)
  assert effect_kind.kind_of(effect_type: 3) == effect_kind.ForcedMove
  assert effect_kind.is_read(effect_type: 3)
  list.each([1, 2, 3, 4, 5, 6, 7], fn(flags) {
    assert effect_kind.is_row_read(effect_type: 3, target_flags: flags)
      as "bit 1 of targetFlags is the caster, 2 the primary target and 4 the area"
  })
  list.each([0, 8, 16], fn(flags) {
    assert !effect_kind.is_row_read(effect_type: 3, target_flags: flags)
      as "any other aim is no unit the server moves"
  })
  assert effect_kind.is_row_read(effect_type: 11, target_flags: 1)
    && effect_kind.is_row_read(effect_type: 11, target_flags: 2)
    && !effect_kind.is_row_read(effect_type: 11, target_flags: 8)
    as "type 11 keeps its own reading: the caster's rows and the struck units' rows"
  assert !effect_kind.is_row_read(effect_type: 90, target_flags: 1)
    as "an unread type stays unread"
}

// ---- the client's own rows ----

pub fn gates_two_caster_rows_are_read_from_the_clients_tables_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let plans = spell_plan.plans(tables: client_tables.shared())
  // Gate, 20325, whose own spell 34355 holds 67776 and 67777.
  let assert Ok(gate) = spell_plan.in_plans(plans:, base: Spell4BaseId(20_325))
  assert gate.forced_moves
    == [
      spell_plan.ForcedMove(
        effect_id: Spell4EffectsId(67_776),
        phase_flags: 1,
        delay_ms: 200,
        condition: Always,
        tag: spend.EqualTo(value: 0),
      ),
    ]
  let assert [falling] = gate.modifiers
  assert falling.effect_id == Spell4EffectsId(67_777)
  assert falling.change
    == spell_plan.PropertyChange(Change(
      property: UnitProperty2Id(134),
      mode: 3,
      multiplier: 0.0,
      flat: 0.0,
      per_level: 0.0,
    ))
  assert falling.row
    == LastingRow(delay_ms: 180, duration_ms: 400, until_removed: False)
}

pub fn every_type_3_row_aimed_at_another_unit_decodes_to_a_move_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.tags(["coverage"])
  use <- unitest.guard(client_tables.present())
  // Spell4Effects.targetFlags 2, 4 and 6 aim at the primary target, the area or both,
  // and a row with no target apply prerequisite has no gate the plan must check first.
  let rows =
    list.filter(spell4_effects.all(client_tables.shared()), fn(row) {
      row.effect_type == 3
      && list.contains([2, 4, 6], row.target_flags)
      && row.prerequisite_id_target_apply == 0
    })
  assert list.length(rows) == 2267
    as "scratch count over `table_rows -- Spell4Effects effectType=3`: targetFlags 2 972, 4 1,222 and 6 73, with no target apply prerequisite"
  let refused =
    list.filter_map(rows, fn(row) {
      case forced_move.of_row(row:) {
        Ok(_) -> Error(Nil)
        Error(error) -> Ok(#(row.id, error))
      }
    })
  assert refused == []
    as "every such row names a kind the client's own mover has (kinds 0 to 15) and finite distances, so each is a move"
}
