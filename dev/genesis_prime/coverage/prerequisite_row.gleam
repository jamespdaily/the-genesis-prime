//// Whether the server decides a Prerequisite row's gender and world conditions,
//// which the coverage measure counts rows by.
////
//// ```
//// Item2 rows ─▶ item_property.equip_requirements ─▶ the Prerequisite ids the equip
////                                                      check loads, and the rows they
////                                                      nest (type 11): decided
//// every other Prerequisite row: a cast reads it with no gender or world: not decided
//// ```
////
//// - The equip check gives its subject the wearer's gender and world; a cast gives
////   none (`genesis_prime/game/cast`), so a condition on either (`wearer_only_types`)
////   is decided only in a row an item's equip check loads.
//// - The rows an item's equip check loads are those `equip_requirements` names for
////   each Item2 row, with the rows they nest; the measure restates none of the
////   check's rules.

import genesis_prime/coverage/starting_ability.{type MissingRow}
import genesis_prime/game/item_property
import genesis_prime/game/prerequisite as game_prerequisite
import genesis_prime/table/id.{PrerequisiteId}
import genesis_prime/table/item2
import genesis_prime/table/loader/store
import genesis_prime/table/prerequisite
import gleam/dict.{type Dict}
import gleam/list
import gleam/option
import gleam/result
import gleam/set.{type Set}

/// How many conditions of the wearer-only types sit in rows no item's equip check
/// loads, by type. A type with no such condition has no entry.
pub fn unread_by_type(tables tables: store.Tables) -> Dict(Int, Int) {
  let equipped = equip_rows(tables:)
  list.fold(prerequisite.all(tables), dict.new(), fn(counts, row) {
    case set.contains(equipped, row.id) {
      True -> counts
      False ->
        counted(counts:, types: [
          row.prerequisite_type_id0,
          row.prerequisite_type_id1,
          row.prerequisite_type_id2,
        ])
    }
  })
}

/// How many conditions of the wearer-only types the starting abilities' casts
/// read, by type: a cast decides none of them. The rows the walk names that the
/// tables lack are the error.
pub fn unread_starting(
  tables tables: store.Tables,
) -> Result(Dict(Int, Int), List(MissingRow)) {
  use types <- result.map(starting_ability.prerequisite_types(tables))
  counted(counts: dict.new(), types:)
}

/// The counts with one more for each of the types that is a wearer-only type.
fn counted(
  counts counts: Dict(Int, Int),
  types types: List(Int),
) -> Dict(Int, Int) {
  list.fold(types, counts, fn(counts, type_id) {
    case list.contains(game_prerequisite.wearer_only_types, type_id) {
      True ->
        dict.upsert(counts, type_id, fn(found) { option.unwrap(found, 0) + 1 })
      False -> counts
    }
  })
}

/// The ids of the Prerequisite rows an item's equip check loads: those each
/// Item2 row's equip requirements name, and the rows they nest. An Item2 whose
/// rows the tables lack names none (the load requires them).
fn equip_rows(tables tables: store.Tables) -> Set(Int) {
  let named =
    list.flat_map(item2.all(tables), fn(item) {
      item_property.equip_requirements(tables:, item2_id: item.id)
      |> result.map(fn(required) { required.prerequisite_ids })
      |> result.unwrap([])
    })
  nested(tables:, found: set.new(), pending: named)
}

/// The found ids with the pending ones and every row they nest through a
/// condition of the nested type.
fn nested(
  tables tables: store.Tables,
  found found: Set(Int),
  pending pending: List(Int),
) -> Set(Int) {
  case pending {
    [] -> found
    [id, ..rest] ->
      case set.contains(found, id) {
        True -> nested(tables:, found:, pending: rest)
        False ->
          nested(
            tables:,
            found: set.insert(found, id),
            pending: list.append(nested_in(tables:, id:), rest),
          )
      }
  }
}

/// The ids the conditions of the nested type in the row name; none for a row the
/// table lacks.
fn nested_in(tables tables: store.Tables, id id: Int) -> List(Int) {
  prerequisite.get(tables:, id: PrerequisiteId(id))
  |> result.map(fn(row) {
    list.filter_map(game_prerequisite.kept_conditions(row:), fn(condition) {
      case condition.0 == game_prerequisite.nested_type {
        True -> Ok(condition.2)
        False -> Error(Nil)
      }
    })
  })
  |> result.unwrap([])
}
