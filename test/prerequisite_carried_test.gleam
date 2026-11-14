//// Prerequisite type 130, carrying a cast of a spell group by the second unit
//// (`genesis_prime/game/prerequisite`). Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.130` (0x140469a70): the first unit carries a cast
////   whose caster is the second unit and whose Spell4 is in the spell group the objectId
////   names; comparison 1 passes when one is found, 2 when none is, any other fails; the
////   value is not read; group 0 matches no spell; with no second unit nothing is
////   carried by it, so comparison 2 passes and 1 fails.
//// - `Prerequisite.prerequisiteTypeId.129` and `.50` (0x1404a2b5a): they read every
////   caster's casts on the unit, which a struck unit's subject does not hold.
//// - Spell4GroupList 464 is the group of Cripple's first hit, the one Prerequisite 13148
////   asks the caster's own cast of.

import genesis_prime/game/lasting
import genesis_prime/game/prerequisite.{
  type Subject, Fails, NotRead, Passes, Subject,
}
import genesis_prime/table/id.{Spell4Id}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support as support
import quest_support

/// A subject under a cast of Spell4 40838 by caster 7 whose spell groups are these,
/// whose second unit is this one.
fn carrying(
  groups groups: List(Int),
  caster caster: Int,
  second_unit second_unit: option.Option(Int),
) -> Subject {
  Subject(..support.holding(held: [], second_unit:), under: [
    lasting.Held(spell4_id: Spell4Id(40_838), caster:, count: 0, groups:),
  ])
}

pub fn a_carried_group_condition_reads_only_the_second_units_casts_test() -> Nil {
  use <- owned_test.run(5000)
  let by_seven = carrying(groups: [464], caster: 7, second_unit: Some(7))
  assert support.verdict(condition: #(130, 1, 464, 0), subject: by_seven)
    == Passes
    as "a cast of group 464 by the second unit is carried"
  assert support.verdict(condition: #(130, 2, 464, 0), subject: by_seven)
    == Fails
  let by_another = carrying(groups: [464], caster: 7, second_unit: Some(8))
  assert support.verdict(condition: #(130, 1, 464, 0), subject: by_another)
    == Fails
    as "a cast of group 464 by caster 7 is not carried by unit 8"
  assert support.verdict(condition: #(130, 2, 464, 0), subject: by_another)
    == Passes
  let other_group = carrying(groups: [5, 313], caster: 7, second_unit: Some(7))
  assert support.verdict(condition: #(130, 1, 464, 0), subject: other_group)
    == Fails
    as "a cast of other groups is not of group 464"
  assert support.verdict(condition: #(130, 1, 0, 0), subject: by_seven) == Fails
    as "group 0 matches no cast"
  assert support.verdict(condition: #(130, 2, 0, 0), subject: by_seven)
    == Passes
  list.each([0, 3, 4], fn(comparison) {
    assert support.verdict(
        condition: #(130, comparison, 464, 0),
        subject: by_seven,
      )
      == Fails
      as {
        "comparison "
        <> int.to_string(comparison)
        <> " is neither has nor has not"
      }
  })
  assert support.verdict(condition: #(130, 1, 464, 99), subject: by_seven)
    == Passes
    as "the value is not read"
}

pub fn a_carried_group_condition_with_no_second_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let alone = carrying(groups: [464], caster: 7, second_unit: None)
  assert support.verdict(condition: #(130, 2, 464, 0), subject: alone) == Passes
    as "with no second unit nothing is carried by it"
  assert support.verdict(condition: #(130, 1, 464, 0), subject: alone) == Fails
  assert support.verdict(condition: #(130, 3, 464, 0), subject: alone) == Fails
}

pub fn a_struck_subject_decides_type_130_but_not_129_test() -> Nil {
  use <- owned_test.run(5000)
  let origin = support.pose(x: 0.0, z: 0.0, yaw: 0.0)
  let struck =
    prerequisite.of_struck(
      first: Some(origin),
      second: origin,
      player: support.player(),
      quests: quest_support.log_of(rows: []),
      unit: prerequisite.UnknownUnit,
      caster_unit: 7,
      under: [
        lasting.Held(spell4_id: Spell4Id(40_838), caster: 7, count: 0, groups: [
          464,
        ]),
      ],
      checker: support.empty_checker(),
    )
  assert support.verdict(condition: #(130, 1, 464, 0), subject: struck)
    == Passes
    as "the struck unit carries the caster's cast of group 464"
  assert support.verdict(condition: #(130, 2, 464, 0), subject: struck) == Fails
  assert support.verdict(condition: #(129, 1, 464, 0), subject: struck)
    == NotRead(prerequisite_type: 129)
    as "type 129 reads every caster's casts on the unit, which a struck subject does not hold"
  assert support.verdict(condition: #(50, 1, 0, 0), subject: struck)
    == NotRead(prerequisite_type: 50)
}
