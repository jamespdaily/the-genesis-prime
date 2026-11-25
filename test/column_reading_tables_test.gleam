//// What the plan makes of a client column's values over the client's whole tables
//// (`genesis_prime/game/column_reading`): each value a row holds is read, or names a
//// question the fact file records, and none is left unexplained. Each test reads the
//// client's files and passes only where they are on the machine.
//// - The stat modifier's parameters: `table_rows -- Spell4Effects effectType=11`
////   (`Spell4Effects.effectType.11.change`). Row 86849 holds the parameters 12, 13 and 10
////   with factors and is refused for 12, the first in column order; rows 128380 and
////   128381 (Spell4 54291) hold a factor of 0.1 on type 0, which names no parameter.

import client_tables
import coverage_support
import genesis_prime/game/column_reading
import genesis_prime/game/damage
import genesis_prime/game/spell_plan
import genesis_prime/table/spell4_effects.{type Spell4Effects}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import owned_test
import spell_tables
import unitest

/// The first parameter of the row, in column order, that has a factor and a type but 0,
/// read from the row's four slots as the table holds them.
fn first_kind_with_a_factor(row row: Spell4Effects) -> Option(Int) {
  [
    #(row.parameter_type00, row.parameter_value00),
    #(row.parameter_type01, row.parameter_value01),
    #(row.parameter_type02, row.parameter_value02),
    #(row.parameter_type03, row.parameter_value03),
  ]
  |> list.find(fn(slot) { slot.0 != 0 && slot.1 != 0.0 })
  |> result.map(fn(slot) { slot.0 })
  |> option.from_result
}

pub fn every_stat_modifier_row_of_the_real_tables_reads_or_names_an_open_question_and_the_refusal_names_the_first_kind_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.tag("real_tables")
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let read = spell_tables.rows_read(tables:, effect_type: 11)
  assert read != [] as "the client's tables hold stat modifier rows"
  list.each(read, fn(found) {
    let #(row, reading) = found
    let label = "the stat modifier row " <> int.to_string(row.id)
    let expected = first_kind_with_a_factor(row:)
    let verdict = damage.modifier_parameter_reading(effect: row)
    assert verdict.kind == option.unwrap(expected, 0)
      as { label <> ": the reading names the first parameter with a factor" }
    case expected, verdict.verdict {
      None, column_reading.Reads -> Nil
      Some(_), column_reading.Open(question:) ->
        coverage_support.assert_question_recorded(question:, label:)
      _, column_reading.Unexplained ->
        panic as { label <> " holds a parameter no record or case explains" }
      _, _ ->
        panic as {
          label
          <> ": a factor on a named kind is an open question, and none is not"
        }
    }
    case expected, reading {
      Some(kind),
        Error(spell_plan.ParameterNotRead(
          row: spell_plan.ModifierRow,
          parameter_kind:,
          ..,
        ))
      -> {
        assert parameter_kind == kind
          as { label <> ": the refusal names the first kind with a factor" }
      }
      Some(_), Error(earlier) -> {
        assert spell_plan.refusal_of(error: earlier).outcome
          == spell_plan.LeavesOut
          as { label <> " is left out by an error that comes first" }
      }
      Some(_), Ok(_) ->
        panic as { label <> " has a factor on a named kind and is read" }
      None, Error(spell_plan.ParameterNotRead(row: spell_plan.ModifierRow, ..))
      ->
        panic as {
          label <> " has no factor on a named kind and is refused for one"
        }
      None, _ -> Nil
    }
  })
  let held = fn(id) {
    let assert Ok(#(row, _)) =
      list.find(read, fn(found) { { found.0 }.id == id })
      as { "the tables hold the stat modifier row " <> int.to_string(id) }
    row
  }
  assert first_kind_with_a_factor(row: held(86_849)) == Some(12)
    as "row 86849 holds 12, 13 and 10 with factors and is named by 12"
  list.each([128_380, 128_381], fn(id) {
    let row = held(id)
    assert first_kind_with_a_factor(row:) == None
      as "a factor on type 0 names no parameter"
    assert row.parameter_type00 == 0 && row.parameter_value00 != 0.0
      as "rows 128380 and 128381 hold the factor on type 0"
  })
}
