//// The quest log's rule for one objective's progress (`quest_log.progressed`).
//// Expected values come from these places.
//// - `opcode.0x361`, `0x1406115a0` and `GetObjectiveNeeded 0x140551840`: an objective
////   is done when its progress reaches its needed count, which is the QuestObjective
////   count itself for every type but the percent kinds (2, 8, 15, 16 and 46); the
////   done bit is bit `index + 2` of the 0x35f flags word and bit `index` of the saved
////   done mask (`opcode.0x35f`). The counts and flags below are the client's rows in
////   the fixture (`table_rows -- QuestObjective`).
//// - `0x1405510d0` and `0x140553790`: only an objective of a quest in the active list
////   that is not done and is reachable takes progress. `0x1405510d0` treats only state
////   3 (completed) as a quest with nothing left, so an Achieved quest is in the list and
////   takes progress too; `0x140553110` and `opcode.0x361` have no state test either.
//// - `0x1405fbc40`, `0x1405fbdc0` and `opcode.0x35c`: a quest whose every objective
////   without flag 0x20 is done is Achieved (state 2), and an Achieved quest is stored
////   as such and stays in the active list. Only the objectives with flag 0x20 are still
////   open in it, and finishing one leaves it Achieved: there is nothing to tell the
////   client again.
////
//// The quests, from the client's rows:
//// - 4290: one type 12 objective (5763), flags 0, count 5.
//// - 3668: objective 0 is 4744 (type 3, count 1), objective 1 is 4745 (flags 7, count
////   5), objective 2 is 4791 (flags 5, count 5).
//// - 3297: objective 0 is 7943 (flags 0x28, count 4), objective 1 is 4299 (type 5,
////   flags 18, count 1).
//// - 9428: objective 0 is 17988 (type 3, flags 3, count 1), objective 1 is 17989 (type
////   12, flags 3, count 1).
//// - 5622: objective 0 is 10263 (type 3, flags 0x20, count 1), objectives 1 and 2 are
////   8742 and 8305 (type 3, flags 3, count 1).

import character_tables
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/store.{type QuestRow}
import gleam/list
import gleam/option.{Some}
import owned_test
import quest_support

const counted_use = 4290

const gated_chain = 3668

const skipped_then_gated = 3297

const talk_then_use = 9428

const optional_talk = 5622

fn quest(id id: Int) -> quest_log.Quest {
  let assert Ok(quest) =
    quest_log.quest_of(tables: character_tables.shared(), id:)
    as "the fixture holds the quest's rows"
  quest
}

/// The saved row of the quest, as the place save writes it.
fn saved(log log: QuestLog, quest_id quest_id: Int) -> QuestRow {
  let assert Ok(row) =
    quest_log.rows(log:, now_ms: 0)
    |> list.find(fn(row) { row.quest_id == quest_id })
    as "the log holds the quest"
  row
}

fn done_mask_of(row row: QuestRow) -> Int {
  let assert Some(active) = row.active as "the quest is in the active list"
  active.done_mask
}

fn progress_of(row row: QuestRow) -> List(Int) {
  let assert Some(active) = row.active as "the quest is in the active list"
  active.progress
}

pub fn progress_adds_and_marks_the_objective_done_at_its_count_test() -> Nil {
  use <- owned_test.run(60_000)
  let counted = quest(id: counted_use)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: counted_use, progress: [0]),
    ])
  let assert Ok(first) =
    quest_log.progressed(log:, quest: counted, index: 0, amount: 1)
    as "an open objective takes progress"
  assert first.progress == 1 as "one use adds one"
  assert progress_of(row: saved(log: first.log, quest_id: counted_use)) == [1]
    as "the saved progress is the new count"
  assert done_mask_of(row: saved(log: first.log, quest_id: counted_use)) == 0
    as "1 of 5 is not done: types 12 need their raw count of 5, not a percentage"
  assert !quest_log.objective_done(log: first.log, quest: counted, index: 0)
    as "the objective is not done below its count"

  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: counted_use, progress: [4]),
    ])
  let assert Ok(last) =
    quest_log.progressed(log:, quest: counted, index: 0, amount: 1)
    as "the objective is still open at 4 of 5"
  assert last.progress == 5 as "the fifth use makes the count"
  assert done_mask_of(row: saved(log: last.log, quest_id: counted_use)) == 0b1
    as "the done bit of index 0 is set at the needed count (0x1406115a0)"
  assert quest_log.objective_done(log: last.log, quest: counted, index: 0)
    as "the log reads the objective done"

  let assert Ok(capped) =
    quest_log.progressed(log:, quest: counted, index: 0, amount: 9)
    as "a larger amount still applies to an open objective"
  assert capped.progress == 5 as "progress is capped at the needed count of 5"
  assert progress_of(row: saved(log: capped.log, quest_id: counted_use)) == [5]
    as "the saved progress is capped too"
}

pub fn progress_reaches_only_open_objectives_test() -> Nil {
  use <- owned_test.run(60_000)
  let counted = quest(id: counted_use)
  let chain = quest(id: gated_chain)

  let done =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: counted_use,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [5],
      ),
    ])
  assert quest_log.progressed(log: done, quest: counted, index: 0, amount: 1)
    == Error(Nil)
    as "a done objective takes no progress (0x1405510d0)"
  assert quest_log.progressed(log: done, quest: counted, index: 1, amount: 1)
    == Error(Nil)
    as "an index past the quest's objectives takes none"

  let nothing_done =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: gated_chain, progress: [0, 0, 0]),
    ])
  assert quest_log.progressed(
      log: nothing_done,
      quest: chain,
      index: 1,
      amount: 1,
    )
    == Error(Nil)
    as "3668 objective 1 has flag 2 and waits for objective 0 (0x140553790)"
  assert quest_log.progressed(
      log: nothing_done,
      quest: chain,
      index: 2,
      amount: 1,
    )
    == Error(Nil)
    as "3668 objective 2 has flag 1 and follows objective 1, which is neither done nor reachable"
  let assert Ok(first) =
    quest_log.progressed(log: nothing_done, quest: chain, index: 0, amount: 1)
    as "3668 objective 0 has no flag and is open"
  assert first.progress == 1
  let assert Ok(second) =
    quest_log.progressed(log: first.log, quest: chain, index: 1, amount: 1)
    as "with objective 0 done, objective 1 is reachable"
  assert second.progress == 1

  let not_accepted = [
    #(
      "a completed quest",
      quest_support.log_of(rows: [
        quest_support.completed(quest_id: counted_use, at: 1000),
      ]),
    ),
    #(
      "a quest the client holds only a state of",
      quest_support.log_of(rows: [
        quest_support.known(quest_id: counted_use, state: 4),
      ]),
    ),
    #("a quest not in the log", quest_support.log_of(rows: [])),
  ]
  list.each(not_accepted, fn(case_) {
    assert quest_log.progressed(
        log: case_.1,
        quest: counted,
        index: 0,
        amount: 1,
      )
      == Error(Nil)
      as {
        case_.0
        <> " takes no progress: only a quest in the active list does (0x1405510d0)"
      }
  })
}

pub fn the_last_open_objective_makes_the_quest_achieved_test() -> Nil {
  use <- owned_test.run(60_000)

  let chain = quest(id: gated_chain)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: gated_chain, progress: [0, 0, 0]),
    ])
  let assert Ok(first) =
    quest_log.progressed(log:, quest: chain, index: 0, amount: 1)
    as "3668 objective 0 is open"
  assert !first.became_achieved
    as "objectives 1 and 2 of 3668 are still open, so the quest is not achieved"
  assert quest_log.stored_state(log: first.log, quest_id: gated_chain) == 1
    as "the stored state stays Accepted"

  let skipped = quest(id: skipped_then_gated)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: skipped_then_gated, progress: [0, 0]),
    ])
  let assert Ok(only) =
    quest_log.progressed(log:, quest: skipped, index: 1, amount: 1)
    as "3297 objective 1 is reachable because objective 0 has flag 0x20"
  assert only.became_achieved
    as "objective 0 of 3297 has flag 0x20 and is skipped, so finishing objective 1 achieves it (0x1405fbdc0)"
  assert quest_log.stored_state(log: only.log, quest_id: skipped_then_gated)
    == 2
    as "the stored state becomes Achieved"
  assert quest_log.state(log: only.log, quest: skipped) == 2
    as "the state the client computes agrees with the stored one"
  assert saved(log: only.log, quest_id: skipped_then_gated).state == 2
    as "the place save writes the Achieved state"

  let pair = quest(id: talk_then_use)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: talk_then_use, progress: [0, 0]),
    ])
  let assert Ok(talked) =
    quest_log.progressed(log:, quest: pair, index: 0, amount: 1)
    as "9428 objective 0 is open"
  assert !talked.became_achieved as "9428 objective 1 is still open"
  let assert Ok(used) =
    quest_log.progressed(log: talked.log, quest: pair, index: 1, amount: 1)
    as "with objective 0 done, objective 1 (flag 2) is reachable"
  assert used.became_achieved as "the last open objective achieves the quest"
  assert quest_log.stored_state(log: used.log, quest_id: talk_then_use) == 2
    as "the stored state becomes Achieved"
  assert quest_log.state(log: used.log, quest: pair) == 2
    as "the state the client computes agrees with the stored one"
  assert done_mask_of(row: saved(log: used.log, quest_id: talk_then_use))
    == 0b11
    as "both done bits are saved"

  assert quest_log.progressed(log: used.log, quest: pair, index: 0, amount: 1)
    == Error(Nil)
    as "a done objective takes none, in an Achieved quest too (0x1405510d0)"
  an_achieved_quest_takes_progress_on_its_optional_objectives()
}

/// An Achieved quest takes progress on its optional objectives and stays Achieved.
fn an_achieved_quest_takes_progress_on_its_optional_objectives() -> Nil {
  let optional = quest(id: optional_talk)

  let accepted =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: optional_talk, progress: [0, 0, 0]),
    ])
  let assert Ok(skipped) =
    quest_log.progressed(log: accepted, quest: optional, index: 0, amount: 1)
    as "5622 objective 0 has flag 0x20 and is open in an Accepted quest"
  assert !skipped.became_achieved
    as "5622's objectives 1 and 2 are still open, and the optional one does not count (0x1405fbc40)"
  assert quest_log.stored_state(log: skipped.log, quest_id: optional_talk) == 1
    as "the quest stays Accepted"

  let achieved =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: optional_talk,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b110,
        progress: [0, 1, 1],
      ),
    ])
  assert quest_log.state(log: achieved, quest: optional) == 2
    as "objectives 1 and 2 are done, so 5622 is Achieved without objective 0"
  let assert Ok(late) =
    quest_log.progressed(log: achieved, quest: optional, index: 0, amount: 1)
    as "the optional objective of an Achieved quest is open, since only state 3 stops it (0x1405510d0)"
  assert late.progress == 1 as "the optional objective counts its one talk"
  assert !late.became_achieved
    as "the quest was Achieved already, so the client is not told again"
  assert quest_log.stored_state(log: late.log, quest_id: optional_talk) == 2
    as "the quest stays Achieved"
  assert saved(log: late.log, quest_id: optional_talk).state == 2
    as "the place save writes Achieved"
  assert done_mask_of(row: saved(log: late.log, quest_id: optional_talk))
    == 0b111
    as "the optional objective's done bit joins the others"
  assert quest_log.progressed(
      log: late.log,
      quest: optional,
      index: 0,
      amount: 1,
    )
    == Error(Nil)
    as "once done it takes no more"
}
