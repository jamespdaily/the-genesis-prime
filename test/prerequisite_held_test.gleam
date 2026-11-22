//// Prerequisite types 50 and 59 (`genesis_prime/game/prerequisite`): what the casts of
//// the unit hold on it. Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.50`: the unit is under the Spell4 in the value
////   cast by the check's second unit; comparison 1 passes when such a cast holds a
////   node on it, 2 when none does, any other fails; with no second unit comparison 2
////   passes and any other fails; a second unit 0 or a value 0 matches no cast. The
////   rows: 23344 (Mind Burst's gate, 1, 57027) and 38587's second condition (2, 39407).
//// - `Prerequisite.prerequisiteTypeId.59`: the sum of the node instance counts of the
////   Spell4 in the objectId on the unit, compared with the value by the comparison.
////   The rows: 32921 (1, 42569, 2), 33154 (5, 42569, 2) and 43574 (4, 87353, 2).
//// - `Prerequisite.prerequisiteTypeId.60` (`0x1404a2c6c`, `0x14046a110`): type 59's count
////   over the casts whose caster is the check's second unit; with no second unit
////   comparison 2 passes and every other fails; a second unit 0 counts 0.

import genesis_prime/game/prerequisite.{Fails, Passes}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support
import qcheck

fn row_23344() -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 23_344, flags: 0, conditions: [
    #(50, 1, 0, 57_027),
  ])
}

pub fn type_50_passes_for_the_spell_cast_by_the_second_unit_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite_support.check(
      row: row_23344(),
      subject: prerequisite_support.holding(
        held: [#(57_027, 7, 1)],
        second_unit: Some(7),
      ),
    )
    == Passes
  assert prerequisite_support.check(
      row: row_23344(),
      subject: prerequisite_support.holding(held: [], second_unit: Some(7)),
    )
    == Fails
}

pub fn type_50_fails_for_the_spell_cast_by_another_unit_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite_support.check(
      row: row_23344(),
      subject: prerequisite_support.holding(
        held: [#(57_027, 8, 1)],
        second_unit: Some(7),
      ),
    )
    == Fails
    as "the cast is another caster's: comparison 1 fails"
  assert prerequisite_support.check(
      row: row_23344(),
      subject: prerequisite_support.holding(
        held: [#(1, 7, 1)],
        second_unit: Some(7),
      ),
    )
    == Fails
    as "the cast is of another spell"
}

pub fn type_50_comparison_2_is_the_reverse_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    prerequisite_support.row(id: 38_587, flags: 0, conditions: [
      #(50, 2, 0, 39_407),
    ])
  assert prerequisite_support.check(
      row: row,
      subject: prerequisite_support.holding(
        held: [#(39_407, 7, 1)],
        second_unit: Some(7),
      ),
    )
    == Fails
  assert prerequisite_support.check(
      row: row,
      subject: prerequisite_support.holding(
        held: [#(39_407, 8, 1)],
        second_unit: Some(7),
      ),
    )
    == Passes
  assert prerequisite_support.check(
      row: row,
      subject: prerequisite_support.holding(held: [], second_unit: Some(7)),
    )
    == Passes
}

pub fn type_50_with_no_second_unit_passes_only_comparison_2_test() -> Nil {
  use <- owned_test.run(5000)
  let held = [#(57_027, 7, 1)]
  assert prerequisite_support.check(
      row: row_23344(),
      subject: prerequisite_support.holding(held:, second_unit: None),
    )
    == Fails
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(50, 2, 0, 57_027),
      ]),
      subject: prerequisite_support.holding(held:, second_unit: None),
    )
    == Passes
}

pub fn type_50_matches_no_cast_for_a_second_unit_0_or_a_value_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite_support.check(
      row: row_23344(),
      subject: prerequisite_support.holding(
        held: [#(57_027, 0, 1)],
        second_unit: Some(0),
      ),
    )
    == Fails
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(50, 1, 0, 0),
      ]),
      subject: prerequisite_support.holding(
        held: [#(0, 7, 1)],
        second_unit: Some(7),
      ),
    )
    == Fails
}

pub fn type_50_fails_a_comparison_other_than_1_and_2_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(50, 3, 0, 57_027),
      ]),
      subject: prerequisite_support.holding(
        held: [#(57_027, 7, 1)],
        second_unit: Some(7),
      ),
    )
    == Fails
}

fn fewer_than_2_stacks() -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 33_154, flags: 0, conditions: [
    #(59, 5, 42_569, 2),
  ])
}

fn exactly_2_stacks() -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 32_921, flags: 0, conditions: [
    #(59, 1, 42_569, 2),
  ])
}

pub fn type_59_counts_the_stacks_of_the_spell_on_the_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let none = prerequisite_support.holding(held: [], second_unit: Some(7))
  let one =
    prerequisite_support.holding(held: [#(42_569, 7, 1)], second_unit: Some(7))
  let two =
    prerequisite_support.holding(
      held: [#(42_569, 7, 1), #(42_569, 7, 1)],
      second_unit: Some(7),
    )
  assert prerequisite_support.check(row: fewer_than_2_stacks(), subject: none)
    == Passes
  assert prerequisite_support.check(row: fewer_than_2_stacks(), subject: one)
    == Passes
  assert prerequisite_support.check(row: fewer_than_2_stacks(), subject: two)
    == Fails
  assert prerequisite_support.check(row: exactly_2_stacks(), subject: one)
    == Fails
  assert prerequisite_support.check(row: exactly_2_stacks(), subject: two)
    == Passes
}

pub fn type_59_sums_the_counts_of_every_cast_and_ignores_other_spells_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite_support.check(
      row: exactly_2_stacks(),
      subject: prerequisite_support.holding(
        held: [#(42_569, 7, 2), #(99, 7, 5)],
        second_unit: Some(7),
      ),
    )
    == Passes
    as "one cast of count 2 is 2 stacks, as two casts of 1 are"
}

pub fn type_59_compares_by_its_comparison_and_fails_an_unknown_one_test() -> Nil {
  use <- owned_test.run(5000)
  let at_least_2 =
    prerequisite_support.row(id: 43_574, flags: 0, conditions: [
      #(59, 4, 87_353, 2),
    ])
  assert prerequisite_support.check(
      row: at_least_2,
      subject: prerequisite_support.holding(
        held: [#(87_353, 7, 2)],
        second_unit: Some(7),
      ),
    )
    == Passes
  assert prerequisite_support.check(
      row: at_least_2,
      subject: prerequisite_support.holding(
        held: [#(87_353, 7, 1)],
        second_unit: Some(7),
      ),
    )
    == Fails
  assert prerequisite_support.check(
      row: prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(59, 9, 87_353, 2),
      ]),
      subject: prerequisite_support.holding(
        held: [#(87_353, 7, 2)],
        second_unit: Some(7),
      ),
    )
    == Fails
}

fn type_60_row(
  comparison comparison: Int,
  value value: Int,
) -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 1, flags: 0, conditions: [
    #(60, comparison, 79_757, value),
  ])
}

/// Each case: a reason, the held casts (spell, caster, stack count), the second unit, the
/// comparison and value, and whether it passes. The unit 7 cast 2 stacks of 79757 and the
/// unit 8 cast 3 of them.
const type_60_cases = [
  #(
    "comparison 1 equals the second unit's own 2 stacks, not the 5 on the unit",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    1,
    2,
    True,
  ),
  #(
    "comparison 1 fails at the 5 stacks of both casters",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    1,
    5,
    False,
  ),
  #(
    "comparison 2 passes for a value that is not the 2",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    2,
    5,
    True,
  ),
  #(
    "comparison 3 passes above 1",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    3,
    1,
    True,
  ),
  #(
    "comparison 3 fails when the value is the 2",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    3,
    2,
    False,
  ),
  #(
    "comparison 4 passes at the 2",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    4,
    2,
    True,
  ),
  #(
    "comparison 4 fails at 3, which only the other caster's stacks would reach",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    4,
    3,
    False,
  ),
  #(
    "comparison 5 passes below 3",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    5,
    3,
    True,
  ),
  #(
    "comparison 5 fails below 2",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    5,
    2,
    False,
  ),
  #(
    "comparison 6 passes at the 2",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    6,
    2,
    True,
  ),
  #(
    "comparison 6 fails at 1",
    [#(79_757, 7, 2), #(79_757, 8, 3)],
    Some(7),
    6,
    1,
    False,
  ),
  #(
    "a second unit's stacks of another Spell4 are not counted",
    [#(79_758, 7, 4)],
    Some(7),
    3,
    0,
    False,
  ),
  #(
    "a second unit that cast none counts 0: comparison 4 value 1 fails",
    [#(79_757, 8, 3)],
    Some(7),
    4,
    1,
    False,
  ),
  #(
    "a second unit that cast none counts 0: comparison 5 value 1 passes",
    [#(79_757, 8, 3)],
    Some(7),
    5,
    1,
    True,
  ),
  #(
    "the stacks of several casts of the second unit sum",
    [#(79_757, 7, 2), #(79_757, 7, 1), #(79_757, 8, 3)],
    Some(7),
    1,
    3,
    True,
  ),
  #(
    "a second unit 0 counts 0 whatever is held: comparison 1 value 0 passes",
    [#(79_757, 0, 2)],
    Some(0),
    1,
    0,
    True,
  ),
  #(
    "no second unit fails comparison 1 value 0, which a count of 0 would pass",
    [],
    None,
    1,
    0,
    False,
  ),
]

pub fn type_60_counts_the_stacks_the_second_unit_cast_and_no_one_elses_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(type_60_cases, fn(case_) {
    let #(reason, held, second_unit, comparison, value, passes) = case_
    assert prerequisite_support.check(
        row: type_60_row(comparison:, value:),
        subject: prerequisite_support.holding(held:, second_unit:),
      )
      == case passes {
        True -> Passes
        False -> Fails
      }
      as reason
  })
}

pub fn type_60_equals_type_59_over_the_second_units_casts_for_any_held_list_and_any_second_unit_above_0_test() -> Nil {
  use <- owned_test.run(30_000)
  qcheck.given(
    qcheck.tuple4(
      qcheck.list_from(qcheck.tuple3(
        qcheck.bounded_int(from: 79_756, to: 79_758),
        qcheck.bounded_int(from: 1, to: 4),
        qcheck.bounded_int(from: 0, to: 5),
      )),
      qcheck.bounded_int(from: 1, to: 4),
      qcheck.bounded_int(from: 1, to: 6),
      qcheck.bounded_int(from: 0, to: 12),
    ),
    fn(drawn) {
      let #(held, second_unit, comparison, value) = drawn
      let by_the_second_unit =
        list.filter(held, fn(node) { node.1 == second_unit })
      let type_60 =
        prerequisite_support.check(
          row: type_60_row(comparison:, value:),
          subject: prerequisite_support.holding(
            held:,
            second_unit: Some(second_unit),
          ),
        )
      let type_59 =
        prerequisite_support.check(
          row: prerequisite_support.row(id: 1, flags: 0, conditions: [
            #(59, comparison, 79_757, value),
          ]),
          subject: prerequisite_support.holding(
            held: by_the_second_unit,
            second_unit: Some(second_unit),
          ),
        )
      assert type_60 == type_59
    },
  )
}

pub fn type_60_with_no_second_unit_passes_comparison_2_and_fails_every_other_comparison_test() -> Nil {
  use <- owned_test.run(5000)
  let subject =
    prerequisite_support.holding(held: [#(79_757, 7, 2)], second_unit: None)
  assert prerequisite_support.check(
      row: type_60_row(comparison: 2, value: 2),
      subject:,
    )
    == Passes
    as "comparison 2 passes with no second unit, whatever the value"
  list.each([1, 3, 4, 5, 6, 9], fn(comparison) {
    assert prerequisite_support.check(
        row: type_60_row(comparison:, value: 1),
        subject:,
      )
      == Fails
      as "every comparison but 2 fails with no second unit"
  })
  let nothing = prerequisite_support.holding(held: [], second_unit: None)
  assert prerequisite_support.check(
      row: type_60_row(comparison: 4, value: 0),
      subject: nothing,
    )
    == Fails
    as "at least 0 would pass over a count of 0, which type 59 gives"
  assert prerequisite_support.check(
      row: type_60_row(comparison: 5, value: 1),
      subject: nothing,
    )
    == Fails
    as "less than 1 would pass over a count of 0, which type 59 gives"
}
