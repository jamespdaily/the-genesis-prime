//// Counting how many rows of the client's data use each type of one engine's
//// kind: the weight each type adds to the engine's work.

import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order

/// One type and the rows that use it.
pub type TypeCount {
  TypeCount(
    /// The type's number in the client's data.
    type_number: Int,
    /// How many values equal the type number.
    rows: Int,
    /// The part of all non-zero values that are this type, from 0.0 to 1.0.
    share: Float,
  )
}

/// The types in use, heaviest first.
pub type Count {
  Count(
    /// Each type with a row, most rows first, ties by the lower type number.
    types: List(TypeCount),
    /// The values that are not zero.
    rows: Int,
    /// The values that are zero. A zero names no type: it is a column with
    /// nothing in it, so it is left out of the types and the shares.
    zero_values: Int,
  )
}

/// Counts one value per row of the type column (a table with several type
/// columns gives every column's value of every row): each non-zero value is a
/// row of its type, and each zero is counted apart.
pub fn count(values: List(Int)) -> Count {
  let zero_values = list.count(values, fn(value) { value == 0 })
  let used = list.filter(values, fn(value) { value != 0 })
  let rows = list.length(used)
  let types =
    list.fold(used, dict.new(), fn(counts, value) {
      dict.upsert(counts, value, fn(found) {
        case found {
          Some(so_far) -> so_far + 1
          None -> 1
        }
      })
    })
    |> dict.to_list
    |> list.sort(fn(first, second) {
      case int.compare(second.1, first.1) {
        order.Eq -> int.compare(first.0, second.0)
        order.Lt -> order.Lt
        order.Gt -> order.Gt
      }
    })
    |> list.map(fn(entry) {
      TypeCount(
        type_number: entry.0,
        rows: entry.1,
        share: int.to_float(entry.1) /. int.to_float(rows),
      )
    })
  Count(types:, rows:, zero_values:)
}
