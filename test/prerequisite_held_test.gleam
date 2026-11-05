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

import genesis_prime/game/lasting
import genesis_prime/game/prerequisite.{
  type Subject, Fails, Passes, Subject, Vital,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/table/prerequisite as prerequisite_table
import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}
import owned_test
import prerequisite_support

/// A subject holding these nodes (spell, caster, stack count), whose second unit is
/// `second_unit`.
fn holding(
  held held: List(#(Int, Int, Int)),
  second_unit second_unit: Option(Int),
) -> Subject {
  Subject(
    under: list.map(held, fn(node) {
      lasting.Held(spell4_id: Spell4Id(node.0), caster: node.1, count: node.2)
    }),
    second_unit:,
    in_combat: False,
    vitals: dict.new() |> dict.insert(1, Vital(current: 1.0, maximum: 1.0)),
    rolls: [],
    difficulty: None,
  )
}

fn check(
  row: prerequisite_table.Prerequisite,
  subject: Subject,
) -> prerequisite.Verdict {
  prerequisite.check(prerequisite: prerequisite.of_row(row:), subject:)
}

fn row_23344() -> prerequisite_table.Prerequisite {
  prerequisite_support.row(id: 23_344, flags: 0, conditions: [
    #(50, 1, 0, 57_027),
  ])
}

pub fn type_50_passes_for_the_spell_cast_by_the_second_unit_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(
      row_23344(),
      holding(held: [#(57_027, 7, 1)], second_unit: Some(7)),
    )
    == Passes
  assert check(row_23344(), holding(held: [], second_unit: Some(7))) == Fails
}

pub fn type_50_fails_for_the_spell_cast_by_another_unit_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(
      row_23344(),
      holding(held: [#(57_027, 8, 1)], second_unit: Some(7)),
    )
    == Fails
    as "the cast is another caster's: comparison 1 fails"
  assert check(row_23344(), holding(held: [#(1, 7, 1)], second_unit: Some(7)))
    == Fails
    as "the cast is of another spell"
}

pub fn type_50_comparison_2_is_the_reverse_test() -> Nil {
  use <- owned_test.run(5000)
  let row =
    prerequisite_support.row(id: 38_587, flags: 0, conditions: [
      #(50, 2, 0, 39_407),
    ])
  assert check(row, holding(held: [#(39_407, 7, 1)], second_unit: Some(7)))
    == Fails
  assert check(row, holding(held: [#(39_407, 8, 1)], second_unit: Some(7)))
    == Passes
  assert check(row, holding(held: [], second_unit: Some(7))) == Passes
}

pub fn type_50_with_no_second_unit_passes_only_comparison_2_test() -> Nil {
  use <- owned_test.run(5000)
  let held = [#(57_027, 7, 1)]
  assert check(row_23344(), holding(held:, second_unit: None)) == Fails
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(50, 2, 0, 57_027),
      ]),
      holding(held:, second_unit: None),
    )
    == Passes
}

pub fn type_50_matches_no_cast_for_a_second_unit_0_or_a_value_0_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(
      row_23344(),
      holding(held: [#(57_027, 0, 1)], second_unit: Some(0)),
    )
    == Fails
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [#(50, 1, 0, 0)]),
      holding(held: [#(0, 7, 1)], second_unit: Some(7)),
    )
    == Fails
}

pub fn type_50_fails_a_comparison_other_than_1_and_2_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(50, 3, 0, 57_027),
      ]),
      holding(held: [#(57_027, 7, 1)], second_unit: Some(7)),
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
  let none = holding(held: [], second_unit: Some(7))
  let one = holding(held: [#(42_569, 7, 1)], second_unit: Some(7))
  let two =
    holding(held: [#(42_569, 7, 1), #(42_569, 7, 1)], second_unit: Some(7))
  assert check(fewer_than_2_stacks(), none) == Passes
  assert check(fewer_than_2_stacks(), one) == Passes
  assert check(fewer_than_2_stacks(), two) == Fails
  assert check(exactly_2_stacks(), one) == Fails
  assert check(exactly_2_stacks(), two) == Passes
}

pub fn type_59_sums_the_counts_of_every_cast_and_ignores_other_spells_test() -> Nil {
  use <- owned_test.run(5000)
  assert check(
      exactly_2_stacks(),
      holding(held: [#(42_569, 7, 2), #(99, 7, 5)], second_unit: Some(7)),
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
  assert check(
      at_least_2,
      holding(held: [#(87_353, 7, 2)], second_unit: Some(7)),
    )
    == Passes
  assert check(
      at_least_2,
      holding(held: [#(87_353, 7, 1)], second_unit: Some(7)),
    )
    == Fails
  assert check(
      prerequisite_support.row(id: 1, flags: 0, conditions: [
        #(59, 9, 87_353, 2),
      ]),
      holding(held: [#(87_353, 7, 2)], second_unit: Some(7)),
    )
    == Fails
}
