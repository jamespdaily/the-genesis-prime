//// Prerequisite type 129, under a spell of a spell group (`genesis_prime/game/prerequisite`).
//// Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.129` (`0x1404a2b5a`): the first unit is a
////   target of a live cast whose Spell4 is in the spell group the objectId names;
////   comparison 1 passes when one is found, 2 when none is, any other fails; the
////   value is not read; group 0 matches no spell.
//// - Spell4GroupList 845: group 313's 11 spells (Spell4 1488, 1490, 1495, 38730,
////   39857, 40838, 40862, 72921, 75093, 75179 and 77132).

import genesis_prime/game/lasting
import genesis_prime/game/prerequisite.{type Subject, Fails, Passes, Subject}
import genesis_prime/table/id.{Spell4Id}
import gleam/list
import gleam/option.{None}
import owned_test
import prerequisite_support as support

/// A subject under a cast of the Spell4 40838 whose spell groups are these.
fn under_spell_of(groups groups: List(Int)) -> Subject {
  Subject(..support.holding(held: [], second_unit: None), under: [
    lasting.Held(spell4_id: Spell4Id(40_838), caster: 7, count: 0, groups:),
  ])
}

fn verdict(
  condition condition: #(Int, Int, Int, Int),
  subject subject: Subject,
) -> prerequisite.Verdict {
  prerequisite.check(prerequisite: support.single(id: 1, condition:), subject:)
}

pub fn under_a_cast_whose_spell_is_in_the_group_comparison_1_passes_and_2_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = under_spell_of(groups: [5, 313])
  assert verdict(condition: #(129, 1, 313, 0), subject:) == Passes
    as "40838 is in group 313 (Spell4GroupList 845): comparison 1 finds it"
  assert verdict(condition: #(129, 2, 313, 0), subject:) == Fails
    as "comparison 2 wants none"
}

pub fn under_a_cast_of_another_group_comparison_2_passes_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = under_spell_of(groups: [5, 6])
  assert verdict(condition: #(129, 2, 313, 0), subject:) == Passes
    as "none of the casts the unit is under is in group 313"
  assert verdict(condition: #(129, 1, 313, 0), subject:) == Fails
}

pub fn under_no_cast_comparison_2_passes_and_1_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = support.holding(held: [], second_unit: None)
  assert verdict(condition: #(129, 2, 313, 0), subject:) == Passes
    as "Prerequisite 12939: a unit under no cast is under none of group 313"
  assert verdict(condition: #(129, 1, 313, 0), subject:) == Fails
}

pub fn group_0_matches_no_spell_and_any_other_comparison_fails_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = under_spell_of(groups: [0, 313])
  assert verdict(condition: #(129, 1, 0, 0), subject:) == Fails
    as "group 0 matches no spell, whatever groups the cast lists"
  assert verdict(condition: #(129, 2, 0, 0), subject:) == Passes
  assert list.map([0, 3, 4, 5, 6, 7], fn(comparison) {
      verdict(condition: #(129, comparison, 313, 0), subject:)
    })
    == [Fails, Fails, Fails, Fails, Fails, Fails]
    as "0x1404a2bbd: a comparison other than 1 and 2 gives 0"
}

pub fn the_value_is_not_read_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = under_spell_of(groups: [313])
  assert list.map([0, 313, 796, 4_294_967_295], fn(value) {
      verdict(condition: #(129, 1, 313, value), subject:)
    })
    == [Passes, Passes, Passes, Passes]
    as "the value is not read (Prerequisite 12939 holds 796 in a dropped condition)"
}
