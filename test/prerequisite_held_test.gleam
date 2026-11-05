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

import genesis_prime/game/prerequisite.{Fails, Passes}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/option.{None, Some}
import owned_test
import prerequisite_support

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
