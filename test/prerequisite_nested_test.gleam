//// Prerequisite type 11, a nested prerequisite (`genesis_prime/game/prerequisite`).
//// Rows are held in memory; the two rows the cast conditions reach are loaded from
//// the client's tables where the client is present. Expected values come from these
//// places:
//// - `Prerequisite.prerequisiteTypeId.11` (`0x1404a45df`, `0x1404a2100`): the
////   objectId is a Prerequisite id evaluated whole, with its own flags and with the
////   same two units; comparison 2 passes when the nested row fails and any other
////   comparison gives its result; the value is not read.
//// - `0x1404a1ca0`: an id with no row fails (so does id 0).
//// - `Prerequisite.prerequisiteTypeId.37`: a type 37 condition takes a roll of its
////   own in the order the conditions are tested, nested ones included.
//// - `Prerequisite.prerequisiteTypeId.50`: a type 50 condition reads the check's
////   second unit.
//// - The server's choice (the design of the step): the load follows the nested ids
////   and a cycle fails it, naming the ids on the way; the client has no guard and
////   the whole table has no cycle.
//// - The client's rows (`gleam run -m genesis_prime/table_rows -- Prerequisite
////   39321 12939 29484 20117`): 39321 nests 12939, 29484 nests 20117.

import client_tables
import genesis_prime/game/prerequisite.{
  type Subject, Fails, NotRead, Passes, PrerequisiteCycle, Subject,
}
import genesis_prime/table/id.{PrerequisiteId}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import owned_test
import prerequisite_support as support
import unitest

/// The row `id` holds one condition of type 11 on `nested` with this comparison.
fn nesting(
  id id: Int,
  comparison comparison: Int,
  nested nested: Int,
) -> prerequisite_table.Prerequisite {
  support.row(id:, flags: 0, conditions: [#(11, comparison, nested, 0)])
}

/// A row that passes when the subject is under the Spell4 `spell4_id`.
fn under(
  id id: Int,
  spell4_id spell4_id: Int,
) -> prerequisite_table.Prerequisite {
  support.row(id:, flags: 0, conditions: [#(15, 1, 0, spell4_id)])
}

/// A subject under these Spell4 ids, with these rolls.
fn subject(under under: List(Int), rolls rolls: List(Int)) -> Subject {
  Subject(
    ..support.holding(
      held: list.map(under, fn(spell4_id) { #(spell4_id, 7, 0) }),
      second_unit: Some(7),
    ),
    rolls:,
  )
}

fn verdict(
  id id: Int,
  rows rows: List(prerequisite_table.Prerequisite),
  subject subject: Subject,
) -> prerequisite.Verdict {
  prerequisite.check(prerequisite: support.loaded(id:, rows:), subject:)
}

pub fn comparisons_0_and_1_give_the_nested_result_and_2_negates_it_test() -> Nil {
  use <- owned_test.run(5000)
  let verdicts = fn(comparison, under_100) {
    verdict(
      id: 1,
      rows: [
        nesting(id: 1, comparison:, nested: 2),
        under(id: 2, spell4_id: 100),
      ],
      subject: subject(
        under: case under_100 {
          True -> [100]
          False -> []
        },
        rolls: [],
      ),
    )
  }
  assert list.map([0, 1, 3, 7], verdicts(_, True))
    == [Passes, Passes, Passes, Passes]
    as "every comparison but 2 gives the nested result: the nested row passes"
  assert list.map([0, 1, 3, 7], verdicts(_, False))
    == [Fails, Fails, Fails, Fails]
    as "and fails when the nested row fails"
  assert #(verdicts(2, True), verdicts(2, False)) == #(Fails, Passes)
    as "comparison 2 negates it"
}

pub fn a_nested_row_that_is_not_read_stays_not_read_under_comparison_2_test() -> Nil {
  use <- owned_test.run(5000)
  // Type 43 (the quest log) is a type the server does not read.
  let unread = support.row(id: 2, flags: 0, conditions: [#(43, 1, 0, 0)])
  let verdicts =
    list.map([1, 2], fn(comparison) {
      verdict(
        id: 1,
        rows: [nesting(id: 1, comparison:, nested: 2), unread],
        subject: subject(under: [], rolls: []),
      )
    })
  assert verdicts
    == [NotRead(prerequisite_type: 43), NotRead(prerequisite_type: 43)]
    as "negating what is not known gives nothing known: comparison 2 keeps NotRead"
}

pub fn the_nested_rows_own_and_or_or_decides_inside_it_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = fn(flags) {
    [
      nesting(id: 1, comparison: 1, nested: 2),
      support.row(id: 2, flags:, conditions: [
        #(15, 1, 0, 100),
        #(15, 1, 0, 101),
      ]),
    ]
  }
  let under_101 = subject(under: [101], rolls: [])
  assert verdict(id: 1, rows: rows(0), subject: under_101) == Fails
    as "the nested row is AND (flags 0): one of its two conditions fails"
  assert verdict(id: 1, rows: rows(1), subject: under_101) == Passes
    as "the nested row is OR (flags 1): one of its two conditions passes, whatever the outer flags"
}

pub fn a_type_50_inside_a_nested_row_reads_the_same_second_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    nesting(id: 1, comparison: 1, nested: 2),
    support.row(id: 2, flags: 0, conditions: [#(50, 1, 0, 200)]),
  ]
  // A node of the Spell4 200 on the unit, cast by the unit 7.
  let held = [#(200, 7, 1)]
  assert verdict(
      id: 1,
      rows:,
      subject: support.holding(held:, second_unit: Some(7)),
    )
    == Passes
    as "the check's second unit 7 cast the node: the nested type 50 finds it"
  assert verdict(
      id: 1,
      rows:,
      subject: support.holding(held:, second_unit: Some(8)),
    )
    == Fails
    as "the second unit is 8: the nested row sees the same second unit and finds no node of its cast"
}

pub fn a_nested_type_37_takes_its_roll_in_order_and_rolls_needed_counts_it_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    support.row(id: 1, flags: 0, conditions: [#(37, 6, 0, 50), #(11, 1, 2, 0)]),
    support.row(id: 2, flags: 0, conditions: [#(37, 4, 0, 90)]),
  ]
  assert prerequisite.rolls_needed(prerequisite: support.loaded(id: 1, rows:))
    == 2
    as "the type 37 of the row and the one of the row it nests"
  assert verdict(id: 1, rows:, subject: subject(under: [], rolls: [10, 95]))
    == Passes
    as "the first roll 10 is at most 50; the nested one, the second roll 95, is at least 90"
  assert verdict(id: 1, rows:, subject: subject(under: [], rolls: [95, 10]))
    == Fails
    as "the rolls swapped: 95 is not at most 50, and 10 is not at least 90"
  assert verdict(id: 1, rows:, subject: subject(under: [], rolls: [10]))
    == NotRead(prerequisite_type: 37)
    as "a check given one roll has none for the nested type 37, which is not read"
}

pub fn a_nested_id_with_no_row_fails_with_comparison_1_and_passes_with_2_and_does_not_fail_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let verdicts = fn(nested) {
    list.map([1, 2], fn(comparison) {
      verdict(
        id: 1,
        rows: [nesting(id: 1, comparison:, nested:)],
        subject: subject(under: [], rolls: []),
      )
    })
  }
  assert verdicts(777) == [Fails, Passes]
    as "0x1404a1ca0: an id with no row fails; comparison 2 negates it"
  assert verdicts(0) == [Fails, Passes]
    as "id 0 names no row either (the whole table holds six such nested ids)"
}

pub fn a_cycle_of_nested_rows_fails_the_load_naming_the_ids_on_the_way_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    nesting(id: 10, comparison: 1, nested: 20),
    nesting(id: 20, comparison: 1, nested: 10),
  ]
  assert support.load_from(id: 10, rows:)
    == Error(
      PrerequisiteCycle(path: [
        PrerequisiteId(10),
        PrerequisiteId(20),
        PrerequisiteId(10),
      ]),
    )
    as "A nests B and B nests A: the load fails with A, B, A"
  assert support.load_from(id: 5, rows: [
      nesting(id: 5, comparison: 1, nested: 5),
    ])
    == Error(PrerequisiteCycle(path: [PrerequisiteId(5), PrerequisiteId(5)]))
    as "a row that nests itself is the shortest cycle"
}

pub fn a_row_nested_twice_without_a_cycle_loads_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    support.row(id: 1, flags: 0, conditions: [#(11, 1, 2, 0), #(11, 1, 3, 0)]),
    nesting(id: 2, comparison: 1, nested: 4),
    nesting(id: 3, comparison: 1, nested: 4),
    under(id: 4, spell4_id: 100),
  ]
  assert support.load_from(id: 1, rows:) |> result.is_ok
    as "two ways to the same row are no cycle: only a repeat on one path is"
}

pub fn the_clients_rows_39321_and_29484_load_with_their_nested_rows_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let tables = client_tables.shared()
  let rows = fn(wanted: id.PrerequisiteId) {
    prerequisite_table.get(tables:, id: wanted) |> result.replace_error(Nil)
  }
  list.each([39_321, 29_484], fn(row_id) {
    assert prerequisite.load(id: PrerequisiteId(row_id), rows:) |> result.is_ok
      as {
        "Prerequisite "
        <> int.to_string(row_id)
        <> " loads: it nests 12939 or 20117 and neither reaches a cycle"
      }
  })
  let assert Ok(stealth) = prerequisite.load(id: PrerequisiteId(39_321), rows:)
  assert prerequisite.check(
      prerequisite: stealth,
      subject: subject(under: [], rolls: []),
    )
    == Passes
    as "39321 nests 12939 (type 129, comparison 2, group 313): a caster under none of the group passes"
}
