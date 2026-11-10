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
//// - 1804: one type 2 objective (1889), flags 0, count 3: a percent kill objective.
//// - 1857: one type 2 objective (1961), flags 0, count 1.
//// - 4705: one type 8 objective (6486), flags 0x204, count 3: flag 0x200 keeps its
////   progress a count.
////
//// A percent kill objective (type 2, 8, 15, 16 or 46, count above 1, flag 0x200 clear)
//// has the needed count 100 (`0x140551840`) and its stored progress is shown as
//// trunc(100 x (stored x 0.001f)) in 32-bit floats (`0x1406113b0`), so its stored
//// progress is thousandths of completion and 1000 is done. How much one kill is worth
//// is no client fact: a kill is an equal share, stored floor(1000 x kills / count)
//// (Jim's decision on the step's issue), so count kills finish it.

import character_tables
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/store.{type QuestRow}
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test
import quest_support

const counted_use = 4290

const gated_chain = 3668

const skipped_then_gated = 3297

const talk_then_use = 9428

const optional_talk = 5622

const percent_kill = 1804

const one_kill = 1857

const counted_kill = 4705

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

/// The one-objective quest `one_kill` with this type 2 objective: the rule's input for
/// each count of the sweep, in the log's entry of that quest.
fn kill_objective(count count: Int) -> quest_log.Quest {
  quest_log.Quest(id: one_kill, objectives: [
    quest_log.Objective(
      type_: 2,
      flags: 0,
      count:,
      data: 5006,
      reward_pane: 0,
      checklist: False,
    ),
  ])
}

fn fresh(quest_id quest_id: Int, slots slots: Int) -> QuestLog {
  quest_support.log_of(rows: [
    quest_support.accepted(quest_id:, progress: list.repeat(0, slots)),
  ])
}

/// The log after `kills` kills of the quest's objective 0, one at a time, each of
/// which is taken.
fn killed(
  log log: QuestLog,
  quest quest: quest_log.Quest,
  kills kills: Int,
) -> quest_log.Progressed {
  let assert Ok(first) = quest_log.progressed(log:, quest:, index: 0, amount: 1)
    as "the first kill is taken"
  case kills {
    1 -> first
    _ -> killed(log: first.log, quest:, kills: kills - 1)
  }
}

pub fn a_percent_kill_stores_thousandths_and_finishes_on_its_count_test() -> Nil {
  use <- owned_test.run(60_000)
  let three = quest(id: percent_kill)
  let log = fresh(quest_id: percent_kill, slots: 1)
  let first = killed(log:, quest: three, kills: 1)
  let second = killed(log:, quest: three, kills: 2)
  let third = killed(log:, quest: three, kills: 3)
  assert [first.progress, second.progress, third.progress] == [333, 666, 1000]
    as "quest 1804's objective 1889 (type 2, count 3, flags 0) stores floor(1000 x kills / 3)"
  assert [first.became_achieved, second.became_achieved, third.became_achieved]
    == [False, False, True]
    as "the quest is Achieved by the third kill, not before"
  assert done_mask_of(row: saved(log: first.log, quest_id: percent_kill)) == 0
    as "the done bit is not set after one kill, though the stored value is above 1"
  assert done_mask_of(row: saved(log: second.log, quest_id: percent_kill)) == 0
    as "nor after two"
  assert done_mask_of(row: saved(log: third.log, quest_id: percent_kill)) == 1
    as "the done bit is set on the third kill (0x1406115a0 compares the shown progress with the needed 100)"
  assert list.map([first, second, third], fn(counted) {
      quest_log.objective_progress(log: counted.log, quest: three, index: 0)
    })
    == [33, 66, 100]
    as "0x1406113b0 shows trunc(100 x (stored x 0.001f)) of the stored thousandths"
  assert quest_log.progressed(log: third.log, quest: three, index: 0, amount: 1)
    == Error(Nil)
    as "a done objective takes no more kills"

  int.range(from: 2, to: 81, with: Nil, run: fn(_, count) {
    let quest = kill_objective(count:)
    let log = fresh(quest_id: one_kill, slots: 1)
    let before = killed(log:, quest:, kills: count - 1)
    assert before.progress > 1
      as {
        at(count:, text: "a stored 1 would show as the raw 1, not a percent")
      }
    assert quest_log.objective_progress(log: before.log, quest:, index: 0) < 100
      as { at(count:, text: "one kill short of the count shows below 100") }
    assert !before.became_achieved
      as { at(count:, text: "one kill short does not finish the quest") }
    assert done_mask_of(row: saved(log: before.log, quest_id: one_kill)) == 0
      as { at(count:, text: "one kill short leaves the done bit clear") }
    let after = killed(log:, quest:, kills: count)
    assert after.progress == 1000
      as { at(count:, text: "count kills reach 1000") }
    assert quest_log.objective_progress(log: after.log, quest:, index: 0) == 100
      as { at(count:, text: "1000 shows as 100, the needed count") }
    assert after.became_achieved
      as { at(count:, text: "count kills finish the quest") }
    assert done_mask_of(row: saved(log: after.log, quest_id: one_kill)) == 1
      as { at(count:, text: "count kills set the done bit") }
  })
}

fn at(count count: Int, text text: String) -> String {
  text <> " (count " <> int.to_string(count) <> ")"
}

pub fn a_counted_kill_adds_one_per_kill_test() -> Nil {
  use <- owned_test.run(60_000)
  // Flag 0x200 keeps the progress a count (objective 6486 of quest 4705, count 3;
  // the tutorial's objective 21288 holds flags 0x203 the same way).
  let counted = quest(id: counted_kill)
  let log = fresh(quest_id: counted_kill, slots: 1)
  let progress =
    list.map([1, 2, 3], fn(kills) {
      killed(log:, quest: counted, kills:).progress
    })
  assert progress == [1, 2, 3]
    as "a kill of a flag 0x200 objective adds one, not a share of a thousand"
  assert done_mask_of(row: saved(
      log: killed(log:, quest: counted, kills: 2).log,
      quest_id: counted_kill,
    ))
    == 0
    as "two of three is not done"
  let third = killed(log:, quest: counted, kills: 3)
  assert done_mask_of(row: saved(log: third.log, quest_id: counted_kill)) == 1
    as "the done bit is set at the count"
  assert third.became_achieved as "and the only objective's quest is Achieved"
  let assert Ok(capped) =
    quest_log.progressed(log:, quest: counted, index: 0, amount: 5)
    as "an amount past the count is taken"
  assert capped.progress == 3 as "and stops at the count (0x140551840)"

  // A count of 1 is a raw count too: the needed count is the count itself.
  let single = quest(id: one_kill)
  let log = fresh(quest_id: one_kill, slots: 1)
  let one = killed(log:, quest: single, kills: 1)
  assert one.progress == 1
    as "objective 1961 (type 2, count 1) stores 1, not 1000"
  assert one.became_achieved
    as "and one kill finishes it (0x140551840: a count of 1 is not a percent)"
}
