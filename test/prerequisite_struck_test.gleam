//// Prerequisite checks on a unit the caster struck (`genesis_prime/game/prerequisite`):
//// what type 39 reads from the first unit, and which types a struck unit's subject cannot
//// read. Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.39`: whether the first unit is a player (unit type
////   20): comparison 1 passes for a player, comparison 2 for any other unit, any other
////   comparison fails.
//// - The struck creature's own subject (`prerequisite.of_creature`) reads its level, class,
////   factions, combat, vitals and difficulty, so the types a struck unit leaves unread are
////   the three that read every caster's casts on it, 15, 59 and 129, which the creature
////   holds only once issue 569 moves the casts into it. Type 50 reads the caster's casts, which
////   the subject holds, and type 37 draws a roll for each test and reads none of the unit's
////   state (`Prerequisite.prerequisiteTypeId.15`, `.59`, `.129`, `.37`).

import genesis_prime/game/prerequisite.{
  type Subject, Fails, NonPlayer, NotRead, OtherPlayer, Passes, TheChecker,
  UnknownUnit,
}
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test
import prerequisite_support as support
import quest_support

fn struck_subject(first_unit first_unit: prerequisite.FirstUnit) -> Subject {
  let origin = support.pose(x: 0.0, z: 0.0, yaw: 0.0)
  support.struck(
    first: Some(origin),
    second: origin,
    player: support.player(),
    quests: quest_support.log_of(rows: []),
  )
  |> support.of_unit(unit: first_unit)
}

pub fn is_player_reads_the_first_unit_test() -> Nil {
  use <- owned_test.run(5000)
  // Each case: the first unit, then the verdicts of comparisons 1 and 2.
  let cases = [
    #(TheChecker, Passes, Fails),
    #(OtherPlayer, Passes, Fails),
    #(NonPlayer(creature2_id: 15_727), Fails, Passes),
    #(
      UnknownUnit,
      NotRead(prerequisite_type: 39),
      NotRead(prerequisite_type: 39),
    ),
  ]
  list.each(cases, fn(case_) {
    let #(first_unit, comparison_one, comparison_two) = case_
    let subject = struck_subject(first_unit:)
    assert support.verdict(condition: #(39, 1, 0, 0), subject:)
      == comparison_one
      as "type 39 comparison 1 passes for a player first unit"
    assert support.verdict(condition: #(39, 2, 0, 0), subject:)
      == comparison_two
      as "type 39 comparison 2 passes for a first unit that is not a player"
  })
  assert support.verdict(
      condition: #(39, 3, 0, 0),
      subject: struck_subject(first_unit: TheChecker),
    )
    == Fails
    as "any other comparison fails"
}

pub fn struck_unread_types_are_casts_only_test() -> Nil {
  use <- owned_test.run(5000)
  let listed = [15, 59, 129]
  list.each(listed, fn(type_id) {
    let direct =
      support.single(id: 1, condition: #(type_id, 1, 1, 1))
      |> prerequisite.struck_unread_types
    assert direct == [type_id]
      as { "type " <> int.to_string(type_id) <> " is unread on a struck unit" }
    let nesting =
      support.loaded(id: 1, rows: [
        support.row(id: 1, flags: 0, conditions: [#(11, 1, 2, 0)]),
        support.row(id: 2, flags: 0, conditions: [#(type_id, 1, 1, 1)]),
      ])
      |> prerequisite.struck_unread_types
    assert nesting == [type_id]
      as {
        "type "
        <> int.to_string(type_id)
        <> " is unread on a struck unit through a nested row"
      }
  })
  let read = [
    130,
    50,
    38,
    108,
    143,
    118,
    47,
    39,
    37,
    1,
    3,
    4,
    28,
    71,
    73,
    179,
    250,
  ]
  list.each(read, fn(type_id) {
    let row = support.row(id: 1, flags: 0, conditions: [#(type_id, 1, 53, 1)])
    let prerequisite =
      support.loaded_with_arcs(id: 1, rows: [row], arcs: [support.behind_arc()])
    assert prerequisite.struck_unread_types(prerequisite) == []
      as { "type " <> int.to_string(type_id) <> " is read on a struck unit" }
  })
}
