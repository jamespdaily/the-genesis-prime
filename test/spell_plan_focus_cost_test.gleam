//// The plan of a Focus cost (`genesis_prime/game/spell_plan` `FocusCost`): every row of
//// the ability book whose Spell4 costs type 15 plans it as a `FocusCost` of its amount,
//// in its column's place among the row's costs, or is one the plans leave out
//// (`Later abilities, not planned`). Expected values come from the client's rows
//// (`table_rows -- Spell4`: `innateCostType0`, `innateCost0`, `innateCostEMMId0` and
//// their `1` columns; `SpellLevel`) and from `CheckInnateCost` 0x1403b3320 case 0xe, the
//// client's own reader of type 15.

import client_tables
import genesis_prime/game/spell_area
import genesis_prime/game/spell_plan.{FocusCost}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/spell4
import genesis_prime/table/spell_level
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import owned_test
import unitest

/// The Focus amount of each of the row's two innate cost columns, in column order, and
/// none for a column that holds no cost or another vital.
fn focus_columns(row row: spell4.Spell4) -> List(Option(Int)) {
  [
    #(row.innate_cost_type0, row.innate_cost0),
    #(row.innate_cost_type1, row.innate_cost1),
  ]
  |> list.filter(fn(column) { column.0 != 0 && column.1 != 0 })
  |> list.map(fn(column) {
    case column.0 {
      15 -> Some(column.1)
      _ -> None
    }
  })
}

pub fn every_book_row_with_a_focus_cost_plans_it_as_a_focus_cost_of_its_rows_amount_in_column_order_or_is_on_the_unplanned_list_test() -> Nil {
  use <- owned_test.run(120_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let assert Ok(unplanned) =
    spell_plan.unplanned(tables:, area_checked: spell_area.checker)
    as "the load's plans build"
  let left_out = list.map(unplanned, fn(one) { one.spell4_id }) |> set.from_list
  let sources = spell_plan.sources_of(tables:)
  let rows =
    list.filter_map(spell_level.all(tables), fn(grant) {
      let assert Ok(row) = spell4.get(tables:, id: spell_level.spell4_id(grant))
        as "a book row names a Spell4 row"
      case list.any(focus_columns(row:), option.is_some) {
        True -> Ok(row)
        False -> Error(Nil)
      }
    })
    |> list.unique
  assert rows != [] as "the book holds rows that cost Focus"
  let #(planned, left) =
    list.partition(rows, fn(row) { !set.contains(left_out, row.id) })
  assert planned != [] && left != []
    as "some rows plan and some are on the list: the rows of the Focus classes' trees"
  list.each(planned, fn(row) {
    let Spell4Id(spell4_id) = spell4.id(row)
    let assert Ok(spell) =
      spell_plan.spell_alone(tables:, sources:, spell4_id:, chain: [])
      as {
        "a book row off the unplanned list plans: " <> int.to_string(spell4_id)
      }
    let focus_emm_ids =
      [
        #(row.innate_cost_type0, row.innate_cost_emm_id0),
        #(row.innate_cost_type1, row.innate_cost_emm_id1),
      ]
      |> list.filter(fn(column) { column.0 == 15 })
      |> list.map(fn(column) { column.1 })
    assert list.all(focus_emm_ids, fn(emm_id) { emm_id == 0 })
      as {
        "every Focus cost of Spell4 "
        <> int.to_string(spell4_id)
        <> " holds EMM id 0, so no spend rule reads it"
      }
    let columns = focus_columns(row:)
    let innate =
      list.drop(spell.costs, list.length(spell.costs) - list.length(columns))
    assert list.map(innate, fn(cost) {
        case cost {
          FocusCost(amount:) -> Some(amount)
          spell_plan.SlotCost(..)
          | spell_plan.ClassVitalCost(..)
          | spell_plan.RowClassCost(..)
          | spell_plan.UnheldCost(..)
          | spell_plan.SpendAllCost(..)
          | spell_plan.UnreadSpendCost(..) -> None
        }
      })
      == columns
      as {
        "Spell4 "
        <> int.to_string(spell4_id)
        <> " plans each Focus column as a FocusCost of its amount, in its column's place among the row's innate costs"
      }
  })
}
