//// Prerequisite types 38 and 214 (`genesis_prime/game/prerequisite`): what the check's
//// first unit is. Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.38` (0x14049ecc0): the first unit's Creature2 id,
////   0 for a unit with no Creature2 record, against the value: comparison 1 equal, 2
////   different, any other fails. The rows: 15727 and 5768 are values of the table's
////   conditions on Creature2 ids.
//// - `Prerequisite.prerequisiteTypeId.214` (0x14049d680, 0x1403bb170): a first unit that
////   is not a player (unit type 0x14 or 0x17) fails; else the checker's own ability book
////   holds the Spell4Base in the objectId (comparison 1) or does not (2). 8740 and 2823
////   are objectIds of the table's conditions.

import genesis_prime/game/prerequisite.{
  type Subject, Fails, NotRead, OtherPlayer, Passes, TheChecker, UnknownUnit,
}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support
import quest_support

/// A pressed creature of this Creature2 row, whose checker holds this book.
fn pressed(creature_id creature_id: Int, book book: List(Int)) -> Subject {
  let origin = prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0)
  prerequisite.of_target(
    under: [],
    caster_unit: 7,
    in_combat: False,
    target: origin,
    caster: origin,
    quests: quest_support.log_of(rows: []),
    creature_id:,
    checker: prerequisite_support.checker(items: [], book:, world_difficulty: 0),
  )
}

/// A subject whose first unit is this one and whose checker holds this book.
fn unit_of(unit unit: prerequisite.FirstUnit, book book: List(Int)) -> Subject {
  prerequisite_support.holding(held: [], second_unit: Some(7))
  |> prerequisite_support.checked_by(items: [], book:, world_difficulty: 0)
  |> prerequisite_support.of_unit(unit:)
}

pub fn an_is_creature_condition_compares_the_first_units_creature_test() -> Nil {
  use <- owned_test.run(5000)
  let subject = pressed(creature_id: 15_727, book: [])
  // Each case: comparison, value, and whether it passes against Creature2 15727.
  let cases = [
    #(1, 15_727, Passes),
    #(1, 5768, Fails),
    #(2, 15_727, Fails),
    #(2, 5768, Passes),
    #(3, 15_727, Fails),
    #(3, 5768, Fails),
  ]
  list.each(cases, fn(case_) {
    let #(comparison, value, expected) = case_
    assert prerequisite_support.verdict(
        condition: #(38, comparison, 0, value),
        subject:,
      )
      == expected
      as {
        "type 38, comparison "
        <> int.to_string(comparison)
        <> ", value "
        <> int.to_string(value)
        <> " on Creature2 15727"
      }
  })
  assert prerequisite_support.verdict(
      condition: #(38, 1, 9999, 15_727),
      subject:,
    )
    == Passes
    as "the objectId is not read"
}

pub fn a_player_first_unit_has_creature_id_zero_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([TheChecker, OtherPlayer], fn(unit) {
    let subject = unit_of(unit:, book: [])
    assert prerequisite_support.verdict(condition: #(38, 1, 0, 0), subject:)
      == Passes
      as "a player has no Creature2 record, so comparison 1 on value 0 passes"
    assert prerequisite_support.verdict(
        condition: #(38, 1, 0, 15_727),
        subject:,
      )
      == Fails
    assert prerequisite_support.verdict(
        condition: #(38, 2, 0, 15_727),
        subject:,
      )
      == Passes
      as "comparison 2 passes on any nonzero Creature2 id"
    assert prerequisite_support.verdict(condition: #(38, 2, 0, 0), subject:)
      == Fails
  })
}

pub fn a_spell_condition_reads_the_checkers_ability_book_test() -> Nil {
  use <- owned_test.run(5000)
  // Each case: comparison, objectId, and whether it passes against a book of 8740.
  let cases = [
    #(2, 8740, Fails),
    #(2, 2823, Passes),
    #(1, 8740, Passes),
    #(1, 2823, Fails),
    #(3, 8740, Fails),
    #(3, 2823, Fails),
  ]
  list.each([TheChecker, OtherPlayer], fn(unit) {
    list.each(cases, fn(case_) {
      let #(comparison, object_id, expected) = case_
      assert prerequisite_support.verdict(
          condition: #(214, comparison, object_id, 0),
          subject: unit_of(unit:, book: [8740]),
        )
        == expected
        as {
          "type 214, comparison "
          <> int.to_string(comparison)
          <> ", Spell4Base "
          <> int.to_string(object_id)
          <> " against the checker's book of 8740"
        }
    })
  })
}

pub fn a_spell_condition_fails_for_a_creature_test() -> Nil {
  use <- owned_test.run(5000)
  list.each([1, 2], fn(comparison) {
    list.each([[8740], []], fn(book) {
      assert prerequisite_support.verdict(
          condition: #(214, comparison, 8740, 0),
          subject: pressed(creature_id: 15_727, book:),
        )
        == Fails
        as "a first unit that is no player fails 214 whatever the book holds"
    })
  })
}

pub fn a_check_that_cannot_name_its_unit_or_checker_does_not_decide_test() -> Nil {
  use <- owned_test.run(5000)
  let nameless = unit_of(unit: UnknownUnit, book: [8740])
  assert prerequisite_support.verdict(
      condition: #(38, 1, 0, 0),
      subject: nameless,
    )
    == NotRead(prerequisite_type: 38)
    as "a unit the check cannot name has no Creature2 id to read"
  assert prerequisite_support.verdict(
      condition: #(214, 1, 8740, 0),
      subject: nameless,
    )
    == NotRead(prerequisite_type: 214)
    as "nor can it say whether the unit is a player"
  // A creature's attack and the world-entry check hold no checker.
  let checkerless = [
    prerequisite.of_difficulty(difficulty: 1),
    prerequisite_support.holding(held: [], second_unit: None),
  ]
  list.each(checkerless, fn(subject) {
    list.each(
      [#(13, 1, 0, 84_957), #(14, 1, 0, 84_957), #(246, 2, 0, 84_957)],
      fn(condition) {
        assert prerequisite_support.verdict(condition:, subject:)
          == NotRead(prerequisite_type: condition.0)
          as "the item types need the checker's items"
      },
    )
    assert prerequisite_support.verdict(condition: #(143, 1, 0, 0), subject:)
      == NotRead(prerequisite_type: 143)
      as "type 143 needs the checker's world difficulty"
  })
  assert prerequisite_support.verdict(
      condition: #(214, 1, 8740, 0),
      subject: prerequisite_support.holding(held: [], second_unit: None),
    )
    == NotRead(prerequisite_type: 214)
    as "type 214 needs the checker's book"
  assert prerequisite_support.verdict(
      condition: #(118, 1, 2431, 0),
      subject: prerequisite_support.holding(held: [], second_unit: None),
    )
    == Passes
    as "types 118 and 47 need neither"
  assert prerequisite_support.verdict(
      condition: #(47, 2, 0, 5744),
      subject: prerequisite_support.holding(held: [], second_unit: None),
    )
    == Fails
}
