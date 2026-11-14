//// Prerequisite types 13, 14, 246 and 143 (`genesis_prime/game/prerequisite`): what the
//// checker's own game object holds. Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.13`, `.14` and `.246` and `HoldsItemInLocations`
////   (0x1403ac590): bit n of the mask the type passes (1, 0x303 and 0x707) is inventory
////   location n; the locations the client's store holds are 0, 1, 2, 5, 8, 9 and 10, so
////   type 13 reads location 0, type 14 reads 0, 1, 8 and 9 and type 246 reads 0, 1, 2, 8, 9
////   and 10, and no mask sets bit 5. The item matches by its Item2 id, the value;
////   comparison 1 holds, 2 does not hold, any other fails. 84957 is the Item2 of the
////   condition of prerequisite 56311, End Table Penny Arcade's visibility.
//// - `Prerequisite.prerequisiteTypeId.143` (0x14049ef70): the world difficulty against the
////   value: comparison 1 equal, 2 different, any other fails; the rows hold (1, 0) Normal
////   and (1, 1) Veteran.
//// - The client's Prerequisite table, whose every condition of the nine types of this
////   step is decided for a caster.

import client_tables
import genesis_prime/game/prerequisite.{Fails, NotRead, Passes}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support
import unitest

pub fn an_item_condition_reads_the_locations_of_its_mask_test() -> Nil {
  use <- owned_test.run(5000)
  // Each type with the locations its mask names.
  let types = [#(13, [0]), #(14, [0, 1, 8, 9]), #(246, [0, 1, 2, 8, 9, 10])]
  list.each(types, fn(type_) {
    let #(type_id, locations) = type_
    list.each([0, 1, 2, 5, 8, 9, 10], fn(location) {
      let holds = list.contains(locations, location)
      let subject =
        prerequisite_support.holding(held: [], second_unit: None)
        |> prerequisite_support.checked_by(
          items: [#(84_957, location)],
          book: [],
          world_difficulty: 0,
        )
      let described =
        "type "
        <> int.to_string(type_id)
        <> " with the item at location "
        <> int.to_string(location)
      assert prerequisite_support.verdict(
          condition: #(type_id, 1, 0, 84_957),
          subject:,
        )
        == case holds {
          True -> Passes
          False -> Fails
        }
        as { described <> ", comparison 1" }
      assert prerequisite_support.verdict(
          condition: #(type_id, 2, 0, 84_957),
          subject:,
        )
        == case holds {
          True -> Fails
          False -> Passes
        }
        as { described <> ", comparison 2" }
      assert prerequisite_support.verdict(
          condition: #(type_id, 3, 0, 84_957),
          subject:,
        )
        == Fails
        as { described <> ", comparison 3" }
    })
    assert prerequisite_support.verdict(
        condition: #(type_id, 1, 0, 3),
        subject: prerequisite_support.holding(held: [], second_unit: None)
          |> prerequisite_support.checked_by(
            items: [#(84_957, 0)],
            book: [],
            world_difficulty: 0,
          ),
      )
      == Fails
      as "another Item2 than the one at location 0 is not held"
  })
}

pub fn a_world_difficulty_condition_compares_the_checkers_difficulty_test() -> Nil {
  use <- owned_test.run(5000)
  let on = fn(difficulty) {
    prerequisite_support.holding(held: [], second_unit: None)
    |> prerequisite_support.checked_by(
      items: [],
      book: [],
      world_difficulty: difficulty,
    )
  }
  // Each case: comparison, value, and whether it passes on difficulty 0.
  let cases = [
    #(1, 0, Passes),
    #(1, 1, Fails),
    #(2, 1, Passes),
    #(2, 0, Fails),
    #(3, 0, Fails),
  ]
  list.each(cases, fn(case_) {
    let #(comparison, value, expected) = case_
    assert prerequisite_support.verdict(
        condition: #(143, comparison, 0, value),
        subject: on(0),
      )
      == expected
      as {
        "type 143, comparison "
        <> int.to_string(comparison)
        <> ", value "
        <> int.to_string(value)
        <> " on difficulty 0"
      }
  })
  assert prerequisite_support.verdict(
      condition: #(143, 1, 0, 1),
      subject: on(1),
    )
    == Passes
    as "a checker in a Veteran world meets difficulty 1"
}

pub fn every_condition_of_the_nine_types_is_decided_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let types = [13, 14, 38, 47, 118, 130, 143, 214, 246]
  let conditions =
    prerequisite_table.all(tables)
    |> list.flat_map(fn(row) {
      [
        #(
          row.prerequisite_type_id0,
          row.prerequisite_comparison_id0,
          row.object_id0,
          row.value0,
        ),
        #(
          row.prerequisite_type_id1,
          row.prerequisite_comparison_id1,
          row.object_id1,
          row.value1,
        ),
        #(
          row.prerequisite_type_id2,
          row.prerequisite_comparison_id2,
          row.object_id2,
          row.value2,
        ),
      ]
    })
    |> list.filter(fn(condition) { list.contains(types, condition.0) })
  list.each(types, fn(type_id) {
    assert list.any(conditions, fn(condition) { condition.0 == type_id })
      as {
        "the client's Prerequisite table holds a condition of type "
        <> int.to_string(type_id)
      }
    assert prerequisite.is_read(type_id:)
      as { "the server reads type " <> int.to_string(type_id) }
  })
  let caster =
    prerequisite_support.holding(held: [], second_unit: Some(7))
    |> prerequisite_support.checked_by(items: [], book: [], world_difficulty: 0)
  list.each(conditions, fn(condition) {
    assert case prerequisite_support.verdict(condition:, subject: caster) {
      Passes | Fails -> True
      NotRead(..) -> False
    }
      as {
        "a caster decides the condition ("
        <> int.to_string(condition.0)
        <> ", "
        <> int.to_string(condition.1)
        <> ", "
        <> int.to_string(condition.2)
        <> ", "
        <> int.to_string(condition.3)
        <> ") of the client's table"
      }
  })
}
