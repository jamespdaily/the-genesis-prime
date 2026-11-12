//// The tutorial chain (genesis_prime/game/tutorial): which giver-less tutorial quest a
//// character is due next, and the rows the load refuses. The expected quests come from
//// the client's tables and text (the Client trace of the step).
//// - `Quest2.questPlayerFactionEnum`: 10513, 10527, 10518 and 10529 are 0 (Exile only),
////   10521, 10532, 10524 and 10533 are 1 (Dominion only).
//// - The order is the objectives' own text, which no table links: 10513 teaches the
////   movement keys and ends on the Direction Arrow, 10527 starts "jump onto the high
////   platform" and ends on the Combat Projector, 10518 starts "kill Virtual Battle
////   Beasts", and 10529 is "Accept the Quest from Dorian Walker to continue".
//// - Creature2 73491 gives quest 10525 (`questIdGiven02`), so a row naming it has a giver.

import character_tables
import genesis_prime/content/refusal.{type Refusal, RowId}
import genesis_prime/game/tutorial.{Row}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import owned_test
import quest_support
import quest_turn_in_support
import tutorial_support

pub fn a_new_exile_is_due_10513_test() -> Nil {
  use <- owned_test.run(5000)
  let chain = tutorial_support.chain()
  let new = quest_support.log_of(rows: [])
  assert tutorial.due(chain:, log: new, faction_enum: 0) == Some(10_513)
    as "Quest2 10513 is Exile only and follows no quest"
  assert tutorial.due(chain:, log: new, faction_enum: 1) == Some(10_521)
    as "Quest2 10521 is Dominion only and follows no quest"
}

pub fn the_next_quest_is_due_once_its_predecessor_is_completed_test() -> Nil {
  use <- owned_test.run(5000)
  let chain = tutorial_support.chain()
  list.each(
    [
      #([10_513], Some(10_527)),
      #([10_513, 10_527], Some(10_518)),
      #([10_513, 10_527, 10_518], Some(10_529)),
      #([10_513, 10_527, 10_518, 10_529], None),
    ],
    fn(completed_and_due) {
      let #(completed, due) = completed_and_due
      assert tutorial.due(
          chain:,
          log: tutorial_support.completed(quests: completed),
          faction_enum: 0,
        )
        == due
        as "the order of the objectives' text: 10513, 10527, 10518, 10529"
    },
  )
  assert tutorial.due(
      chain:,
      log: tutorial_support.completed(quests: [10_521, 10_532, 10_524]),
      faction_enum: 1,
    )
    == Some(10_533)
    as "the Dominion's order is 10521, 10532, 10524, 10533"
}

pub fn a_quest_held_in_any_state_is_not_due_again_test() -> Nil {
  use <- owned_test.run(5000)
  let chain = tutorial_support.chain()
  assert tutorial.due(
      chain:,
      log: quest_support.log_of(rows: [
        quest_support.untouched(quest_id: 10_513),
      ]),
      faction_enum: 0,
    )
    == None
    as "10513 is Accepted: a relog gives no second copy and 10527 waits for its completion"
  assert tutorial.due(
      chain:,
      log: quest_support.log_of(rows: [
        quest_turn_in_support.achieved(quest_id: 10_513),
      ]),
      faction_enum: 0,
    )
    == None
    as "10513 is Achieved, awaiting the server's completion"
  assert tutorial.due(
      chain:,
      log: quest_support.log_of(rows: [
        quest_support.completed(quest_id: 10_513, at: 1_700_000_000),
        quest_support.untouched(quest_id: 10_527),
      ]),
      faction_enum: 0,
    )
    == None
    as "10527 is Accepted after 10513 is Completed: 10518 waits for it"
}

/// The refusals the rows give over the client's committed tables.
fn refused(rows rows: List(tutorial.Row)) -> List(Refusal) {
  let assert Error(refusals) =
    tutorial.select(rows:, tables: character_tables.content_tables())
    as "the rows are refused"
  refusals
}

pub fn a_chain_row_with_a_giver_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let refusals =
    refused(
      rows: list.append(tutorial_support.rows(), [
        Row(quest_id: 10_525, follows_quest_id: Some(10_529)),
      ]),
    )
  let assert [refusal.Refusal(table:, row:, rule:)] = refusals
    as "one refusal: the row of quest 10525, which Creature2 73491 gives"
  assert table == "tutorial_quest"
  assert row == RowId(10_525)
  assert string.contains(rule, "73491")
    as "the rule names the creature that gives the quest"
}

pub fn a_chain_with_two_starts_for_one_faction_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let refusals =
    refused(rows: [
      Row(quest_id: 10_513, follows_quest_id: None),
      Row(quest_id: 10_527, follows_quest_id: None),
    ])
  assert list.map(refusals, fn(refusal) { #(refusal.table, refusal.row) })
    == [
      #("tutorial_quest", RowId(10_513)),
      #("tutorial_quest", RowId(10_527)),
    ]
    as "both rows of faction enum 0 with no predecessor are named"
  assert list.all(refusals, fn(refusal) {
    string.contains(refusal.rule, "start")
  })
}

pub fn a_chain_row_with_no_quest2_row_fails_the_load_test() -> Nil {
  use <- owned_test.run(5000)
  let assert [refusal.Refusal(table:, row:, rule:)] =
    refused(rows: [Row(quest_id: 1, follows_quest_id: None)])
    as "one refusal: the row of quest 1, which the client's table lacks"
  assert table == "tutorial_quest"
  assert row == RowId(1)
  assert string.contains(rule, "Quest2")
}
