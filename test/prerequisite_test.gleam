//// The prerequisite evaluator (`genesis_prime/game/prerequisite`): a Prerequisite
//// row read as the client reads it, and checked against the Spell4 ids of the live
//// casts the unit is a target of. Expected values come from these places:
//// - The client's rows (`gleam run -m genesis_prime/table_rows -- Prerequisite 24581
////   24582 43811 43812`), copied into `row_24581` and the others below.
//// - The client's evaluator: `Prerequisite.flags` and `0x1404a5190` (conditions cut
////   at the first type 0; flags bit 0 makes OR; an empty row passes under AND and
////   fails under OR), `0x1404a1ca0` (AND or OR of the kept conditions),
////   `Prerequisite.prerequisiteTypeId.15` and `0x1404a4ec0` (type 15: comparison 1
////   passes when a live cast of the value's Spell4 targets the unit, 2 when none
////   does, any other fails), and `0x1404a2100` (a type with no case, such as 17,
////   fails).

import genesis_prime/game/prerequisite.{Fails, NotRead, Passes}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/list
import owned_test

/// A Prerequisite row with these conditions, as (type, comparison, objectId,
/// value), and these flags.
fn row(
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

/// Row 24581, Relentless Strikes' +180: (15, 2, 0, 42908), then type 0 with
/// comparison 2 and value 60947.
fn row_24581() -> prerequisite_table.Prerequisite {
  row(id: 24_581, flags: 0, conditions: [
    #(15, 2, 0, 42_908),
    #(0, 2, 0, 60_947),
  ])
}

/// Row 24582, the +200: (15, 2, 0, 42908), (15, 2, 0, 60947), (15, 1, 0, 59208).
fn row_24582() -> prerequisite_table.Prerequisite {
  row(id: 24_582, flags: 0, conditions: [
    #(15, 2, 0, 42_908),
    #(15, 2, 0, 60_947),
    #(15, 1, 0, 59_208),
  ])
}

/// Row 43811, Energize's +4: (15, 2, 732, 58999).
fn row_43811() -> prerequisite_table.Prerequisite {
  row(id: 43_811, flags: 0, conditions: [#(15, 2, 732, 58_999)])
}

/// Row 43812, Energize's ticking +1: (15, 1, 0, 58999).
fn row_43812() -> prerequisite_table.Prerequisite {
  row(id: 43_812, flags: 0, conditions: [#(15, 1, 0, 58_999)])
}

fn check(
  row: prerequisite_table.Prerequisite,
  under: List(Int),
) -> prerequisite.Verdict {
  prerequisite.check(
    prerequisite: prerequisite.of_row(row:),
    under: list.map(under, Spell4Id),
  )
}

// ---- 11 ----

pub fn row_24581_passes_with_no_live_cast_and_fails_under_overdrive_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row_24581(), []) == Passes
    as "comparison 2 on 42908: no cast of Overdrive targets the Warrior"
  assert check(row_24581(), [42_908]) == Fails
    as "a live cast of Overdrive 42908 targets the Warrior: comparison 2 fails"
}

// ---- 12 ----

pub fn row_24582_fails_with_none_live_and_passes_under_59208_alone_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row_24582(), []) == Fails
    as "its third condition, comparison 1 on 59208, finds no cast"
  assert check(row_24582(), [59_208]) == Passes
    as "not under 42908 nor 60947, and under 59208"
  assert check(row_24582(), [59_208, 60_947]) == Fails
    as "under 60947 its second condition fails"
}

// ---- 13 ----

pub fn rows_43811_and_43812_exclude_each_other_on_power_cadence_test() -> Nil {
  use <- owned_test.run(5000)
  assert #(check(row_43811(), []), check(row_43812(), [])) == #(Passes, Fails)
    as "not under Power Cadence 58999: the +4 passes, the ticking +1 fails"
  assert #(check(row_43811(), [58_999]), check(row_43812(), [58_999]))
    == #(Fails, Passes)
    as "under 58999: the other way round; objectId 732 is not read"
}

// ---- 14 ----

pub fn the_row_is_cut_at_its_first_type_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row_24581(), [60_947]) == Passes
    as "row 24581's second condition (comparison 2, value 60947) has type 0, so it is dropped (0x1404a5190): 60947 live changes nothing"
  let cut =
    row(id: 1, flags: 0, conditions: [
      #(15, 2, 0, 10),
      #(0, 0, 0, 0),
      #(15, 1, 0, 11),
    ])
  assert check(cut, []) == Passes
    as "a condition after a type 0 is dropped too, whatever it holds"
}

pub fn flags_bit_0_makes_the_row_pass_when_any_condition_does_test() -> Nil {
  use <- owned_test.run(5000)
  let conditions = [#(15, 1, 0, 10), #(15, 1, 0, 11)]
  assert check(row(id: 1, flags: 0, conditions:), [10]) == Fails
    as "AND: 11 is not live"
  assert check(row(id: 1, flags: 1, conditions:), [10]) == Passes
    as "flags bit 0: OR"
  assert check(row(id: 1, flags: 1, conditions:), []) == Fails
    as "OR with no condition passing"
  assert check(row(id: 1, flags: 2, conditions:), [10]) == Fails
    as "only bit 0 is read: flags 2 is AND"
}

pub fn a_row_with_no_kept_condition_passes_under_and_and_fails_under_or_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row(id: 1, flags: 0, conditions: []), []) == Passes
  assert check(row(id: 1, flags: 1, conditions: []), []) == Fails
}

pub fn an_unread_type_is_not_read_and_a_type_with_no_client_case_fails_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row(id: 1, flags: 0, conditions: [#(28, 1, 0, 0)]), [])
    == NotRead(prerequisite_type: 28)
    as "type 28 has a case in the client (0x1404a2100) that the server does not read"
  assert check(row(id: 1, flags: 0, conditions: [#(17, 1, 0, 0)]), []) == Fails
    as "type 17 has no case in the client: it fails (0x1404a2100)"
  assert check(row(id: 1, flags: 0, conditions: [#(296, 1, 0, 0)]), []) == Fails
    as "a type above 295 fails (0x1404a2100)"
  assert check(
      row(id: 1, flags: 0, conditions: [#(15, 1, 0, 10), #(28, 1, 0, 0)]),
      [],
    )
    == Fails
    as "under AND a failed condition decides the row whatever an unread one would give"
  assert check(
      row(id: 1, flags: 1, conditions: [#(28, 1, 0, 0), #(15, 1, 0, 10)]),
      [10],
    )
    == Passes
    as "under OR a passing condition decides the row whatever an unread one would give"
}

pub fn a_type_15_comparison_other_than_1_or_2_fails_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(row(id: 1, flags: 0, conditions: [#(15, 3, 0, 10)]), [10])
    == Fails
  assert check(row(id: 1, flags: 0, conditions: [#(15, 0, 0, 10)]), []) == Fails
}
