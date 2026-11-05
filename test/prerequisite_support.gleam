//// Prerequisite rows for tests that check a prerequisite
//// (`genesis_prime/game/prerequisite`), built as the client's table holds them.

import genesis_prime/game/prerequisite.{type Prerequisite}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/list

/// A Prerequisite row with these conditions, as (type, comparison, objectId,
/// value), and these flags.
pub fn row(
  id id: Int,
  flags flags: Int,
  conditions conditions: List(#(Int, Int, Int, Int)),
) -> prerequisite_table.Prerequisite {
  let at = fn(index) {
    case list.drop(conditions, index) {
      [condition, ..] -> condition
      [] -> #(0, 0, 0, 0)
    }
  }
  let #(type0, comparison0, object0, value0) = at(0)
  let #(type1, comparison1, object1, value1) = at(1)
  let #(type2, comparison2, object2, value2) = at(2)
  prerequisite_table.Prerequisite(
    id:,
    flags:,
    prerequisite_type_id0: type0,
    prerequisite_type_id1: type1,
    prerequisite_type_id2: type2,
    prerequisite_comparison_id0: comparison0,
    prerequisite_comparison_id1: comparison1,
    prerequisite_comparison_id2: comparison2,
    object_id0: object0,
    object_id1: object1,
    object_id2: object2,
    value0:,
    value1:,
    value2:,
    localized_text_id_failure: 0,
  )
}

/// The prerequisite of a row with one condition, as (type, comparison, objectId,
/// value), under AND.
pub fn single(
  id id: Int,
  condition condition: #(Int, Int, Int, Int),
) -> Prerequisite {
  prerequisite.of_row(row: row(id:, flags: 0, conditions: [condition]))
}
