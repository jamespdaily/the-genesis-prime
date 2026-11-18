//// Prerequisite type 288 (`genesis_prime/game/prerequisite`): whether the client's own set
//// of owned titles holds a title. Expected values come from these places:
//// - `Prerequisite.prerequisiteTypeId.288` (0x1404a1830): a first unit of unit type 0x14
////   or 0x17 (a player) is looked up in the client's one title set, comparison 1 passes
////   when the title is owned and 2 when it is not, any other comparison fails; any other
////   unit type fails, and the value is not read.
//// - `opcode.0x18a` and `opcode.0x18b`: the client's title set is filled only by those two
////   messages, which the server never sends, so the set is empty and no title is owned.
//// - Prerequisite 43305 (`table_rows -- Prerequisite 43305`): the table's one condition of
////   the type, comparison 2 on title 400, value 0.

import genesis_prime/game/prerequisite.{
  type Verdict, Fails, NonPlayer, NotRead, OtherPlayer, Passes, TheChecker,
  UnknownUnit,
}
import gleam/list
import gleam/option.{None}
import owned_test
import prerequisite_support

pub fn a_character_title_condition_reads_the_clients_own_title_set_test() -> Nil {
  use <- owned_test.run(5000)
  let creature = NonPlayer(creature2_id: 73_334)
  // Each case: first unit, comparison, value, the verdict, and why.
  let cases = [
    #(
      TheChecker,
      1,
      0,
      Fails,
      "comparison 1 asks for an owned title, and none is",
    ),
    #(
      TheChecker,
      2,
      0,
      Passes,
      "comparison 2 passes when the title is not owned",
    ),
    #(TheChecker, 2, 7, Passes, "the value is not read"),
    #(TheChecker, 0, 0, Fails, "comparison 0 is neither 1 nor 2"),
    #(TheChecker, 3, 0, Fails, "comparison 3 is neither 1 nor 2"),
    #(TheChecker, 4, 0, Fails, "comparison 4 is neither 1 nor 2"),
    #(TheChecker, 6, 0, Fails, "comparison 6 is neither 1 nor 2"),
    #(
      OtherPlayer,
      1,
      0,
      Fails,
      "the client reads its own set for any player unit",
    ),
    #(
      OtherPlayer,
      2,
      0,
      Passes,
      "the client reads its own set for any player unit",
    ),
    #(creature, 1, 0, Fails, "a unit that is no player fails"),
    #(
      creature,
      2,
      0,
      Fails,
      "a unit that is no player fails whatever the comparison",
    ),
    #(
      UnknownUnit,
      1,
      0,
      NotRead(prerequisite_type: 288),
      "its unit type is unknown",
    ),
    #(
      UnknownUnit,
      2,
      0,
      NotRead(prerequisite_type: 288),
      "its unit type is unknown",
    ),
  ]
  list.each(cases, fn(case_) {
    let #(unit, comparison, value, expected, reason) = case_
    // The set is not the checker's: an item, a spell and a difficulty numbered 400 change nothing.
    let subjects = [
      prerequisite_support.holding(held: [], second_unit: None),
      prerequisite_support.holding(held: [], second_unit: None)
        |> prerequisite_support.checked_by(
          items: [#(400, 0)],
          book: [400],
          world_difficulty: 400,
        ),
    ]
    list.each(subjects, fn(subject) {
      assert verdict_of(
          subject: prerequisite_support.of_unit(subject:, unit:),
          comparison:,
          value:,
        )
        == expected
        as reason
    })
  })
}

pub fn a_title_condition_is_read_and_loads_without_an_unread_type_test() -> Nil {
  use <- owned_test.run(5000)
  assert prerequisite.is_read(type_id: 288)
    as "the server decides type 288, as the client's check does"
  let row_43305 =
    prerequisite_support.prerequisite_of(
      row: prerequisite_support.row(id: 43_305, flags: 0, conditions: [
        #(288, 2, 400, 0),
      ]),
    )
  assert prerequisite.unread_types(prerequisite: row_43305) == []
    as "Prerequisite 43305 holds no condition the server leaves unread"
  assert prerequisite.check(
      prerequisite: row_43305,
      subject: prerequisite_support.holding(held: [], second_unit: None),
    )
    == Passes
    as "the row's comparison 2 on title 400 passes for a character who owns none"
}

fn verdict_of(
  subject subject: prerequisite.Subject,
  comparison comparison: Int,
  value value: Int,
) -> Verdict {
  prerequisite_support.verdict(
    condition: #(288, comparison, 400, value),
    subject:,
  )
}
