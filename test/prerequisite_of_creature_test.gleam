//// The subject of a creature that checks a gate of a strike
//// (`genesis_prime/game/prerequisite.of_creature`): what each type reads from the creature's
//// own facts. Expected values come from these places:
//// - The comparison codes of the numeric types (1, 71, 73, 179): 1 equal, 2 not equal, 3
////   greater, 4 at least, 5 less, 6 at most (`0x1404a2090`).
//// - `Prerequisite.prerequisiteTypeId.1` (the level, an unsigned number against the value),
////   `.3.creature` (a creature's class is 23, which no Class row has: comparison 1 fails for
////   every Class id, comparison 2 passes), `.4` and `.250` (the faction and the base faction
////   the 0x262 sets; comparison 1 equal, 2 different, any other fails), `.28` (the in-combat
////   flag), `.179` (the difficulty against the objectId, not the value), `.38` (the Creature2
////   id), `.39` (a creature is no player), `.118` (the server holds no public event).
//// - `Vital.1.unit` and `Vital.20.unit`: health and Interrupt Armor, each with its own
////   maximum; type 71 is the current times 100 over the maximum in 32-bit floats, type 73
////   the current cut to a whole number (`0x1404a4e30`, `Prerequisite.prerequisiteTypeId.73`).
////   The division is unguarded: 0 of 0 is NaN (equal only), above 0 of 0 is positive infinity
////   (comparisons 2, 3 and 4 pass), and a maximum of -1.0 gives a negative percent.
//// - `opcode.0x262.absent_stats` and `UnitBreathMax`: a creature sent without stat 20 has
////   no shield, and one sent without stat 19 has full breath, GameFormula 55's dataint0, 100.

import genesis_prime/game/prerequisite.{
  type CreatureFacts, type Verdict, CreatureFacts, Factions, Fails, Passes,
  Player, Vital,
}
import gleam/list
import gleam/option.{None}
import owned_test
import prerequisite_support as support

/// A creature of level 9 and class 23, with factions 1441 and 1500, out of combat, with 40
/// of 52 health, 2 of 3 Interrupt Armor, no shield maximum, difficulty 6 and the Creature2 row
/// 73464, struck by the unit 1.
fn facts() -> CreatureFacts {
  CreatureFacts(
    player: Player(
      race_id: 0,
      class_id: 23,
      level: 9,
      path: 0,
      gender: 0,
      world_id: 3460,
      zones: [],
    ),
    factions: Factions(current: 1441, base: 1500),
    in_combat: False,
    health: Vital(current: 40.0, maximum: 52.0),
    shield_maximum: 0.0,
    armor: Vital(current: 2.0, maximum: 3.0),
    difficulty: 6,
    creature_id: 73_464,
    under: [],
    caster_unit: 1,
    creature: support.pose(x: 0.0, z: 0.0, yaw: 0.0),
    caster: None,
  )
}

fn verdict(
  condition condition: #(Int, Int, Int, Int),
  facts facts: CreatureFacts,
) -> Verdict {
  support.verdict(condition:, subject: prerequisite.of_creature(facts:))
}

/// The verdicts of comparisons 1 to 6 of this type on this object and value.
fn comparisons(
  type_id type_id: Int,
  object_id object_id: Int,
  value value: Int,
  facts facts: CreatureFacts,
) -> List(Verdict) {
  list.map([1, 2, 3, 4, 5, 6], fn(code) {
    verdict(condition: #(type_id, code, object_id, value), facts:)
  })
}

pub fn creature_subject_reads_its_level_test() -> Nil {
  use <- owned_test.run(5000)
  assert comparisons(type_id: 1, object_id: 0, value: 9, facts: facts())
    == [Passes, Fails, Fails, Passes, Fails, Passes]
    as "a level of 9 is equal to 9, at least 9 and at most 9, and no more"
  assert comparisons(type_id: 1, object_id: 0, value: 8, facts: facts())
    == [Fails, Passes, Passes, Passes, Fails, Fails]
    as "9 is above 8"
}

pub fn creature_subject_class_is_23_test() -> Nil {
  use <- owned_test.run(5000)
  // The ids of the Class rows (`table_rows -- Class`): no row has 23.
  let class_ids = [1, 2, 3, 4, 5, 7]
  list.each(class_ids, fn(class_id) {
    assert verdict(condition: #(3, 1, 0, class_id), facts: facts()) == Fails
      as "comparison 1 fails for every Class id: the creature is of none"
    assert verdict(condition: #(3, 2, 0, class_id), facts: facts()) == Passes
      as "comparison 2 passes for every Class id"
  })
  assert verdict(condition: #(3, 3, 0, 1), facts: facts()) == Fails
    as "any other comparison fails"
}

pub fn creature_subject_reads_its_factions_test() -> Nil {
  use <- owned_test.run(5000)
  let verdicts = fn(type_id, value) {
    list.map([1, 2, 3], fn(code) {
      verdict(condition: #(type_id, code, 0, value), facts: facts())
    })
  }
  assert verdicts(4, 1441) == [Passes, Fails, Fails]
    as "type 4 reads the current faction: equal passes under 1, different under 2, any other fails"
  assert verdicts(4, 1500) == [Fails, Passes, Fails]
    as "type 4 does not read the base faction"
  assert verdicts(250, 1500) == [Passes, Fails, Fails]
    as "type 250 reads the base faction"
  assert verdicts(250, 1441) == [Fails, Passes, Fails]
    as "type 250 does not read the current faction"
}

pub fn creature_subject_reads_in_combat_test() -> Nil {
  use <- owned_test.run(5000)
  let fighting = CreatureFacts(..facts(), in_combat: True)
  let resting = CreatureFacts(..facts(), in_combat: False)
  let verdicts = fn(facts) {
    list.map([1, 2, 3], fn(code) {
      verdict(condition: #(28, code, 0, 0), facts:)
    })
  }
  assert verdicts(fighting) == [Passes, Fails, Fails]
    as "in a fight: comparison 1 passes, 2 fails, any other fails"
  assert verdicts(resting) == [Fails, Passes, Fails]
    as "at home: comparison 1 fails, 2 passes"
}

pub fn creature_subject_reads_health_and_interrupt_armor_test() -> Nil {
  use <- owned_test.run(5000)
  assert comparisons(type_id: 73, object_id: 1, value: 40, facts: facts())
    == [Passes, Fails, Fails, Passes, Fails, Passes]
    as "type 73 on vital 1 reads the 40 health"
  assert comparisons(type_id: 73, object_id: 20, value: 2, facts: facts())
    == [Passes, Fails, Fails, Passes, Fails, Passes]
    as "type 73 on vital 20 reads the 2 armor, not its maximum of 3"
  assert verdict(condition: #(71, 3, 1, 76), facts: facts()) == Passes
    as "40 of 52 is 76.9 percent, above 76"
  assert verdict(condition: #(71, 3, 1, 77), facts: facts()) == Fails
    as "and not above 77"
  assert verdict(condition: #(71, 3, 20, 66), facts: facts()) == Passes
    as "2 of 3 is 66.7 percent, above 66"
  assert verdict(condition: #(71, 3, 20, 67), facts: facts()) == Fails
    as "and not above 67"
  let infinite =
    CreatureFacts(..facts(), armor: Vital(current: 0.0, maximum: -1.0))
  assert verdict(condition: #(73, 1, 20, 0), facts: infinite) == Passes
    as "a creature of infinite armor, whose maximum reads -1.0, holds 0 armor"
}

pub fn creature_subject_shield_is_0_and_breath_full_test() -> Nil {
  use <- owned_test.run(5000)
  // Whatever the facts hold, the shield and the breath are what the unit starts with.
  let shielded = CreatureFacts(..facts(), shield_maximum: 10.0)
  list.each([facts(), shielded], fn(facts) {
    assert verdict(condition: #(73, 1, 3, 0), facts:) == Passes
      as "vital 3, the shield, is 0"
    assert verdict(condition: #(73, 3, 3, 0), facts:) == Fails
      as "and above no value"
    assert verdict(condition: #(73, 1, 2, 100), facts:) == Passes
      as "vital 2, the breath, is the breath maximum, 100"
    assert verdict(condition: #(71, 1, 2, 100), facts:) == Passes
      as "that is 100 percent of its maximum of 100"
  })
  assert verdict(condition: #(71, 4, 3, 0), facts: shielded) == Passes
    as "a shield of 0 of 10 is 0 percent, at least 0"
  assert verdict(condition: #(71, 3, 3, 0), facts: shielded) == Fails
    as "and not above 0"
}

pub fn vital_percent_with_a_zero_maximum_passes_only_equal_test() -> Nil {
  use <- owned_test.run(5000)
  // A creature with no Interrupt Armor holds 0 of a maximum of 0, and the shield of one with
  // no shield capacity is the same.
  let bare =
    CreatureFacts(
      ..facts(),
      armor: Vital(current: 0.0, maximum: 0.0),
      shield_maximum: 0.0,
    )
  list.each([20, 3], fn(vital) {
    assert comparisons(type_id: 71, object_id: vital, value: 50, facts: bare)
      == [Passes, Fails, Fails, Fails, Fails, Fails]
      as "0x1404a4e30: 0 of 0 is not a number, which counts as equal and fails every other comparison"
  })
}

pub fn vital_percent_above_zero_over_a_zero_maximum_is_infinite_test() -> Nil {
  use <- owned_test.run(5000)
  // `divss` by a maximum of 0 with the SSE exceptions masked: 5 * 100 / 0 is positive
  // infinity, above every value, so comparisons 2, 3 and 4 pass and 1, 5 and 6 fail.
  let held = CreatureFacts(..facts(), armor: Vital(current: 5.0, maximum: 0.0))
  assert comparisons(type_id: 71, object_id: 20, value: 50, facts: held)
    == [Fails, Passes, Passes, Passes, Fails, Fails]
    as "0x1404a4e30: 5 of 0 is infinite, above 50"
  assert comparisons(
      type_id: 71,
      object_id: 20,
      value: 4_294_967_295,
      facts: held,
    )
    == [Fails, Passes, Passes, Passes, Fails, Fails]
    as "and above the greatest value a row can hold"
}

pub fn vital_percent_over_a_negative_maximum_is_negative_test() -> Nil {
  use <- owned_test.run(5000)
  // Interrupt Armor with property 44 at -1 has a maximum of -1.0 (`Vital.20.unit`): 5 of it
  // is -500 percent, below every value, and 0 of it is -0.0, equal to 0.
  let worn = CreatureFacts(..facts(), armor: Vital(current: 5.0, maximum: -1.0))
  assert comparisons(type_id: 71, object_id: 20, value: 50, facts: worn)
    == [Fails, Passes, Fails, Fails, Passes, Passes]
    as "a negative percent is below 50"
  let none = CreatureFacts(..facts(), armor: Vital(current: 0.0, maximum: -1.0))
  assert comparisons(type_id: 71, object_id: 20, value: 0, facts: none)
    == [Passes, Fails, Fails, Passes, Fails, Passes]
    as "-0.0 equals 0"
}

pub fn creature_subject_reads_difficulty_test() -> Nil {
  use <- owned_test.run(5000)
  // Type 179 compares the difficulty with the objectId, and ignores the value.
  assert comparisons(type_id: 179, object_id: 6, value: 99, facts: facts())
    == [Passes, Fails, Fails, Passes, Fails, Passes]
    as "difficulty 6 is equal to the objectId 6"
  assert comparisons(type_id: 179, object_id: 5, value: 6, facts: facts())
    == [Fails, Passes, Passes, Passes, Fails, Fails]
    as "difficulty 6 is above the objectId 5, whatever the value"
}

pub fn creature_subject_is_a_creature_of_its_row_that_is_no_player_test() -> Nil {
  use <- owned_test.run(5000)
  assert verdict(condition: #(38, 1, 0, 73_464), facts: facts()) == Passes
    as "type 38 reads its Creature2 row"
  assert verdict(condition: #(38, 1, 0, 73_465), facts: facts()) == Fails
    as "and no other"
  assert verdict(condition: #(39, 1, 0, 0), facts: facts()) == Fails
    as "type 39: a creature is no player"
  assert verdict(condition: #(39, 2, 0, 0), facts: facts()) == Passes
    as "comparison 2 passes for a unit that is not a player"
  assert verdict(condition: #(118, 1, 53, 0), facts: facts()) == Passes
    as "type 118: the server holds no public event, so every objective has status 0"
}

pub fn a_creature_subject_holds_vital_15_as_0_of_0_test() -> Nil {
  use <- owned_test.run(5000)
  // `Vital.15.unit`: a creature's 0x262 sends no stat 1, so its Focus word is the 0
  // ConstructUnit leaves and property 5 defaults to 0. Type 71 of 0 over 0 is no number,
  // which only the equal comparison passes; type 73 reads the 0 points.
  assert comparisons(type_id: 71, object_id: 15, value: 30, facts: facts())
    == [Passes, Fails, Fails, Fails, Fails, Fails]
    as "0 of 0 percent is no number: equal passes and every other comparison fails"
  assert comparisons(type_id: 73, object_id: 15, value: 0, facts: facts())
    == [Passes, Fails, Fails, Passes, Fails, Passes]
    as "0 points against 0: equal, at least and at most"
  assert comparisons(type_id: 73, object_id: 15, value: 5, facts: facts())
    == [Fails, Passes, Fails, Fails, Passes, Passes]
    as "0 points against 5: not equal, less and at most"
  assert support.verdict(
      condition: #(71, 1, 15, 30),
      subject: prerequisite.of_difficulty(difficulty: 6),
    )
    == prerequisite.NotRead(prerequisite_type: 71)
    as "a subject with no unit holds no Focus to read: the check stays unread"
}
