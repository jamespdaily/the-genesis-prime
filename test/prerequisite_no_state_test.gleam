//// Prerequisite types 118 and 47 (`genesis_prime/game/prerequisite`): the two that read
//// state the server holds none of, or that the client never meets. Expected values come
//// from these places:
//// - `Prerequisite.prerequisiteTypeId.118`: the status of the public event objective in
////   the objectId (0 for an objective the client does not know, and the server holds no
////   public event, so every objective) against the value: comparison 1 equal, 2
////   different, any other fails. The rows: 51502's CasterCast prerequisite 29089 (objective
////   2431 == 1) and the visibility prerequisite 35578 (objective 4382 == 1).
//// - `Prerequisite.prerequisiteTypeId.47`: the client's slot 0x2f8 is 0x140001ba0
////   (`xor eax,eax; ret`), so no comparison ever passes. The rows: 5744 (comparison 2) and
////   13046 (comparison 2).

import genesis_prime/game/prerequisite.{
  type Subject, Fails, NotRead, Passes, UnknownUnit,
}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import prerequisite_support
import quest_support

/// A subject of each builder the rule has, by name: a caster, a pressed creature, a
/// struck unit, a wearer and a creature's attack.
fn every_builder() -> List(#(String, Subject)) {
  let origin = prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0)
  [
    #(
      "a caster",
      prerequisite_support.holding(held: [], second_unit: None)
        |> prerequisite_support.checked_by(
          items: [],
          book: [],
          world_difficulty: 0,
        ),
    ),
    #(
      "a pressed creature",
      prerequisite.of_target(
        under: [],
        caster_unit: 7,
        in_combat: False,
        target: origin,
        caster: origin,
        quests: quest_support.log_of(rows: []),
        creature_id: 15_727,
        checker: prerequisite_support.empty_checker(),
      ),
    ),
    #(
      "a struck unit",
      prerequisite_support.struck(
        first: Some(origin),
        second: origin,
        player: prerequisite_support.player(),
        quests: quest_support.log_of(rows: []),
      ),
    ),
    #(
      "a wearer",
      prerequisite.of_wearer(
        factions: prerequisite.Factions(current: 0, base: 0),
        player: prerequisite_support.player(),
        checker: prerequisite_support.empty_checker(),
      ),
    ),
    #("a creature's attack", prerequisite.of_difficulty(difficulty: 1)),
    #(
      "a unit the check cannot name",
      prerequisite_support.of_unit(
        subject: prerequisite_support.holding(held: [], second_unit: None),
        unit: UnknownUnit,
      ),
    ),
  ]
}

pub fn an_objective_condition_reads_every_objective_as_inactive_test() -> Nil {
  use <- owned_test.run(5000)
  // Each case: comparison, value, and whether it passes against status 0.
  let cases = [
    #(1, 0, Passes),
    #(1, 1, Fails),
    #(2, 0, Fails),
    #(2, 1, Passes),
    #(3, 0, Fails),
    #(3, 1, Fails),
  ]
  list.each(every_builder(), fn(builder) {
    let #(name, subject) = builder
    list.each(cases, fn(case_) {
      let #(comparison, value, expected) = case_
      assert prerequisite_support.verdict(
          condition: #(118, comparison, 2431, value),
          subject:,
        )
        == expected
        as {
          "type 118 on "
          <> name
          <> ", comparison "
          <> int.to_string(comparison)
          <> ", value "
          <> int.to_string(value)
          <> " against status 0"
        }
    })
  })
  // The objective is not read: another objective gives the same status.
  assert prerequisite_support.verdict(
      condition: #(118, 1, 4382, 0),
      subject: prerequisite_support.holding(held: [], second_unit: None),
    )
    == Passes
    as "objective 4382 is inactive too"
}

pub fn a_type_47_condition_never_passes_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(every_builder(), fn(builder) {
    let #(name, subject) = builder
    list.each([1, 2, 3], fn(comparison) {
      assert prerequisite_support.verdict(
          condition: #(47, comparison, 0, 13_046),
          subject:,
        )
        == Fails
        as {
          "type 47 on "
          <> name
          <> ", comparison "
          <> int.to_string(comparison)
          <> " fails: the client's slot 0x140001ba0 returns false"
        }
    })
  })
  assert prerequisite_support.verdict(
      condition: #(47, 2, 0, 5744),
      subject: prerequisite_support.holding(held: [], second_unit: None),
    )
    != NotRead(prerequisite_type: 47)
    as "the server reads type 47"
}
