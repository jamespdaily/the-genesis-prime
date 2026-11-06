//// Prerequisite type 116, the unit's stealth (`genesis_prime/game/prerequisite`).
//// Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.116` (`0x1404a2609`): the check reads the first
////   unit's stealth state; comparison 1 passes when it is above 1 (stealthed), 2 when it
////   is 1 or below, and any other comparison fails; the objectId and the value are not
////   read (every row's value is 28455 and plays no part).
//// - The client's rows (`gleam run -m genesis_prime/table_rows -- Prerequisite 6527 7050
////   8127 13653 24381 38585 38587`): 6527, 7050 and 8127 hold one condition of type 116
////   (comparisons 1, 2 and 1, value 28455); 13653 and 38585 hold (116, 1) and (15, 1) under
////   OR (flags 1); 24381 holds (116, 1) and (15, 1) under AND; 38587 holds (116, 2) and (50, 2)
////   under AND.
//// - The server's choice (the prerequisite module's doc): a subject that holds no stealth,
////   a creature's side, gives `NotRead(116)`.

import client_tables
import genesis_prime/game/prerequisite.{
  type Verdict, Fails, NotRead, Passes, Subject,
}
import genesis_prime/table/id.{PrerequisiteId}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support
import unitest

/// The comparison codes 0 to 7: the ones the client's check has a case for (1 and 2)
/// and the ones it fails.
const comparisons = [0, 1, 2, 3, 4, 5, 6, 7]

fn subject(stealthed stealthed: option.Option(Bool)) -> prerequisite.Subject {
  Subject(
    ..prerequisite_support.holding(held: [], second_unit: None),
    stealthed:,
  )
}

/// The verdict of a type 116 row with this comparison, objectId and value.
fn verdict_of(
  comparison comparison: Int,
  object_id object_id: Int,
  value value: Int,
  stealthed stealthed: option.Option(Bool),
) -> Verdict {
  prerequisite_support.check(
    row: prerequisite_support.row(id: 1, flags: 0, conditions: [
      #(116, comparison, object_id, value),
    ]),
    subject: subject(stealthed:),
  )
}

pub fn comparison_1_passes_a_stealthed_unit_and_2_one_that_is_not_and_any_other_fails_test() -> Nil {
  use <- owned_test.run(5000)
  assert list.map(comparisons, fn(comparison) {
      verdict_of(
        comparison:,
        object_id: 0,
        value: 28_455,
        stealthed: Some(True),
      )
    })
    == [Fails, Passes, Fails, Fails, Fails, Fails, Fails, Fails]
    as "a stealthed unit (state above 1): comparison 1 passes and 2 fails; 0, 3 to 7 have no case and fail (0x1404a2609)"
  assert list.map(comparisons, fn(comparison) {
      verdict_of(
        comparison:,
        object_id: 0,
        value: 28_455,
        stealthed: Some(False),
      )
    })
    == [Fails, Fails, Passes, Fails, Fails, Fails, Fails, Fails]
    as "a unit that is not stealthed (state 1 or below): comparison 2 passes and 1 fails"
}

pub fn the_objectid_and_the_value_change_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(0, 0),
      #(28_455, 0),
      #(0, 28_455),
      #(1004, 94),
      #(0xFFFFFFFF, 0xFFFFFFFF),
    ],
    fn(numbers) {
      assert verdict_of(
          comparison: 1,
          object_id: numbers.0,
          value: numbers.1,
          stealthed: Some(True),
        )
        == Passes
        as "the objectId and the value are not read (Prerequisite.prerequisiteTypeId.116)"
      assert verdict_of(
          comparison: 2,
          object_id: numbers.0,
          value: numbers.1,
          stealthed: Some(True),
        )
        == Fails
    },
  )
}

pub fn a_subject_that_holds_no_stealth_is_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([1, 2], fn(comparison) {
    assert verdict_of(comparison:, object_id: 0, value: 28_455, stealthed: None)
      == NotRead(prerequisite_type: 116)
      as "a creature's side holds no stealth, so the server cannot say what the client would"
  })
  assert prerequisite.is_read(type_id: 116)
    as "the type counts as read (Prerequisite.prerequisiteTypeId.116)"
}

fn client_row(id id: Int) -> prerequisite_table.Prerequisite {
  let assert Ok(row) =
    prerequisite_table.get(
      tables: client_tables.shared(),
      id: PrerequisiteId(id),
    )
    as "the client's table holds the row"
  row
}

pub fn the_clients_seven_rows_with_a_type_116_condition_decode_and_read_the_stealth_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  // Each row as (id, verdict when stealthed, verdict when not), from its conditions:
  // 6527 and 8127: (116, 1); 7050: (116, 2). 13653 and 38585: (116, 1) OR (15, 1 on
  // 39407), and no live cast of 39407 holds the unit. 24381: (116, 1) AND (15, 1 on
  // 45057). 38587: (116, 2) AND (50, 2 on 39407).
  list.each(
    [
      #(6527, Passes, Fails),
      #(7050, Fails, Passes),
      #(8127, Passes, Fails),
      #(13_653, Passes, Fails),
      #(24_381, Fails, Fails),
      #(38_585, Passes, Fails),
      #(38_587, Fails, Passes),
    ],
    fn(expected) {
      let #(id, stealthed, not_stealthed) = expected
      let row = client_row(id:)
      assert list.contains(prerequisite.condition_types(row:), 116)
        as "the row holds a type 116 condition"
      assert prerequisite_support.check(
          row:,
          subject: subject(stealthed: Some(True)),
        )
        == stealthed
        as "row checked against a stealthed unit that is under no cast"
      assert prerequisite_support.check(
          row:,
          subject: subject(stealthed: Some(False)),
        )
        == not_stealthed
        as "row checked against a unit that is not stealthed and under no cast"
    },
  )
}
