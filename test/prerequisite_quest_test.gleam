//// The quest conditions of the prerequisite rule (`genesis_prime/game/prerequisite`):
//// types 6, 68, 43, 94 and 22 (with 23, 33, 34, 35 and 36, which are type 22 on
//// objective 1 to 5). Expected values come from these places, each named at its
//// assertion:
//// - `Prerequisite.prerequisiteTypeId.6`: the quest state `GetQuestState` (0x1405fbc40)
////   gives for quest objectId, states 4 to 7 counted as 0, against the value (comparison
////   1 equal, 2 not equal, any other fails). The state: a quest not in the log 0, an
////   Accepted one in the active list 2 when every objective without flag 0x20 is done
////   (a quest with no objective too) and else 1, a stored Achieved 2, a completed one 3.
//// - `Prerequisite.prerequisiteTypeId.68`: `IsQuestObjectiveDone` (0x1405510d0) of
////   objective `value` of quest objectId: a completed quest has every objective of its
////   count done, an active one has the bit of the done mask, an index at or past the
////   count is never done.
//// - `Prerequisite.prerequisiteTypeId.43`: in the active list, not done, and reachable
////   (0x140553790): flag 2 waits for every earlier objective without flag 0x20, else flag 1
////   for each earlier objective to be done or itself reachable, else nothing waits.
//// - `Prerequisite.prerequisiteTypeId.22`: `0x14049f4d0` compares the objective's progress
////   with the value as unsigned 32-bit numbers, progress on the left; completed quests read
////   the needed count (0x140551840), active ones the in-log progress (0x1406113b0), any
////   other 0. Types 22, 23, 33, 34, 35 and 36 read objective 0 to 5.
//// - `Prerequisite.prerequisiteTypeId.94` and `0x14049f5b0`: the creature is the first unit
////   unless it is a player and then the second; with none, or a quest the table lacks,
////   only comparison 2 passes; else the quest's objective `value` is read from the log:
////   the creature is counted when its index is a bit of the objective's mask (`0x140611680`).
//// - The client's rows, from the fixture (`table_rows -- Quest2 <id>`, `-- QuestObjective
////   <id>`, `-- Prerequisite 9207`): `quest_support` names each quest and its objectives.

import cast_support as support
import character_support
import character_tables
import fixture_tables
import genesis_prime/game/cast.{type Caster, type Effect}
import genesis_prime/game/connection/casting
import genesis_prime/game/prerequisite.{
  type Prerequisite, type Subject, type Verdict, Fails, NotRead, Passes, Subject,
}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/spell_plan.{
  type Plans, CastGate, GatedOnCasterAndTarget, Proxy, Spell,
}
import genesis_prime/game/spend
import genesis_prime/game/world_entry
import genesis_prime/message/spell_started
import genesis_prime/store.{type QuestRow}
import genesis_prime/table/id.{PrerequisiteId, Spell4EffectsId}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import owned_test
import planted_table.{Integer}
import prerequisite_support
import quest_support
import world_entry_support

// ---- the conditions and the logs ----

/// The prerequisite of one condition, as (type, comparison, objectId, value), loaded
/// against the fixture's quests.
fn gate(condition condition: #(Int, Int, Int, Int)) -> Prerequisite {
  let assert Ok(loaded) =
    prerequisite_support.load_with(
      id: 1,
      rows: [prerequisite_support.row(id: 1, flags: 0, conditions: [condition])],
      arcs: [],
      quests: prerequisite.table_quests(tables: character_tables.shared()),
    )
    as "the fixture holds each quest's objectives"
  loaded
}

/// A subject of a player whose quest log this is.
fn player_with(log log: QuestLog) -> Subject {
  Subject(
    ..prerequisite_support.holding(held: [], second_unit: None),
    quests: Some(log),
  )
}

fn verdict(
  condition condition: #(Int, Int, Int, Int),
  log log: QuestLog,
) -> Verdict {
  prerequisite.check(prerequisite: gate(condition:), subject: player_with(log:))
}

fn log_of(rows rows: List(QuestRow)) -> QuestLog {
  quest_support.log_of(rows:)
}

/// A quest in the active list, accepted, with this done mask and these progress values.
fn accepted(
  quest quest_id: Int,
  done_mask done_mask: Int,
  progress progress: List(Int),
) -> QuestRow {
  quest_support.active(
    quest_id:,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask:,
    progress:,
  )
}

/// The numbers from 0 to `up_to` for which the condition the function builds passes.
fn passing(
  condition condition: fn(Int) -> #(Int, Int, Int, Int),
  log log: QuestLog,
  up_to up_to: Int,
) -> List(Int) {
  int.range(from: 0, to: up_to + 1, with: [], run: fn(numbers, number) {
    [number, ..numbers]
  })
  |> list.reverse
  |> list.filter(fn(number) {
    verdict(condition: condition(number), log:) == Passes
  })
}

/// The state type 6 reads for the quest: the one value of 0 to 7 that comparison 1 passes.
fn state_of(quest quest: Int, log log: QuestLog) -> List(Int) {
  passing(condition: fn(value) { #(6, 1, quest, value) }, log:, up_to: 7)
}

/// The objective indexes 0 to 5 of the quest that type 68 reads done.
fn done_indexes(quest quest: Int, log log: QuestLog) -> List(Int) {
  passing(condition: fn(index) { #(68, 1, quest, index) }, log:, up_to: 5)
}

/// The objective indexes 0 to 5 of the quest that type 43 reads open.
fn open_indexes(quest quest: Int, log log: QuestLog) -> List(Int) {
  passing(condition: fn(index) { #(43, 1, quest, index) }, log:, up_to: 5)
}

/// The prerequisite type that reads this objective index (22 reads 0, 23 reads 1, then
/// 33 to 36 read 2 to 5).
fn type_of_index(index index: Int) -> Int {
  case index {
    0 -> 22
    1 -> 23
    other -> 31 + other
  }
}

/// The progress the condition of the index reads, as the one value of 0 to 120 that
/// comparison 1 passes.
fn progress_of(
  index index: Int,
  quest quest: Int,
  log log: QuestLog,
) -> List(Int) {
  passing(
    condition: fn(value) { #(type_of_index(index:), 1, quest, value) },
    log:,
    up_to: 120,
  )
}

// ---- 1: type 6 ----

pub fn a_quest_state_condition_reads_the_state_the_client_derives_test() -> Nil {
  use <- owned_test.run(60_000)
  let quest = quest_support.skipped_first
  assert state_of(quest:, log: log_of(rows: [])) == [0]
    as "a quest not in the log is Unknown, 0 (0x1405fbc40: no entry in any list)"
  assert state_of(
      quest:,
      log: log_of(rows: [accepted(quest:, done_mask: 0, progress: [0, 0])]),
    )
    == [1]
    as "Accepted with objective 1 not done is 1: objective 0 has flag 0x20 and is skipped, objective 1 has not (Saved C 0x1405fbc40)"
  assert state_of(
      quest:,
      log: log_of(rows: [accepted(quest:, done_mask: 0b10, progress: [0, 12])]),
    )
    == [2]
    as "Accepted with objective 1 done reads 2, not the stored 1 (0x1405fbc40: every objective without flag 0x20 is done)"
  assert state_of(
      quest:,
      log: log_of(rows: [
        quest_support.active(
          quest_id: quest,
          state: 2,
          placeholder: 0,
          tracked: False,
          done_mask: 0,
          progress: [0, 0],
        ),
      ]),
    )
    == [2]
    as "a stored Achieved is 2 (0x1405fbd36 returns a state other than 1 as it is)"
  assert state_of(
      quest:,
      log: log_of(rows: [quest_support.completed(quest_id: quest, at: 1000)]),
    )
    == [3]
    as "a completed quest is 3 (0x1405fbcef)"
  let abandoned = log_of(rows: [quest_support.known(quest_id: quest, state: 6)])
  assert state_of(quest:, log: abandoned) == [0]
    as "Known Abandoned counts as 0 (Prerequisite.prerequisiteTypeId.6: states 4 to 7 become 0): value 0 passes, 6 does not"
  assert verdict(condition: #(6, 1, quest, 6), log: abandoned) == Fails
    as "value 6 fails for Abandoned: the state compared is 0"
  assert state_of(
      quest: quest_support.weekly,
      log: log_of(rows: [
        accepted(quest: quest_support.weekly, done_mask: 0, progress: []),
      ]),
    )
    == [2]
    as "a quest with no objective is 2 once it is accepted (Saved C 0x1405fbc40)"
  assert state_of(quest: 999_999, log: log_of(rows: [])) == [0]
    as "a quest with no Quest2 row is the client's unknown quest, state 0 (0x1405a8a40 gives none)"
  let in_log =
    log_of(rows: [accepted(quest:, done_mask: 0b10, progress: [0, 12])])
  assert verdict(condition: #(6, 1, quest, 2), log: in_log) == Passes
    as "comparison 1 passes on equal"
  assert verdict(condition: #(6, 2, quest, 2), log: in_log) == Fails
    as "comparison 2 fails on equal"
  assert verdict(condition: #(6, 2, quest, 3), log: in_log) == Passes
    as "comparison 2 passes on not equal"
  assert verdict(condition: #(6, 3, quest, 0), log: in_log) == Fails
    as "comparison 3 fails: only 1 and 2 are cases (Prerequisite.prerequisiteTypeId.6)"
}

// ---- 2: type 68 ----

pub fn an_objective_done_condition_reads_the_done_mask_test() -> Nil {
  use <- owned_test.run(60_000)
  let quest = quest_support.skipped_first
  assert done_indexes(
      quest:,
      log: log_of(rows: [accepted(quest:, done_mask: 0b10, progress: [0, 12])]),
    )
    == [1]
    as "objective 1 is done when its mask bit is set (0x1405510d0)"
  assert done_indexes(
      quest:,
      log: log_of(rows: [accepted(quest:, done_mask: 0, progress: [0, 0])]),
    )
    == []
    as "no bit set, none done"
  assert done_indexes(
      quest:,
      log: log_of(rows: [accepted(quest:, done_mask: 0b111, progress: [0, 0])]),
    )
    == [0, 1]
    as "index 2 is past the quest's two objectives: never done, whatever the mask"
  assert done_indexes(
      quest:,
      log: log_of(rows: [quest_support.completed(quest_id: quest, at: 1000)]),
    )
    == [0, 1]
    as "a completed quest has every objective done, index 2 and above not (0x1405510d0)"
  assert done_indexes(
      quest:,
      log: log_of(rows: [quest_support.known(quest_id: quest, state: 5)]),
    )
    == []
    as "a Known quest has no done mask: nothing is done"
  assert done_indexes(quest:, log: log_of(rows: [])) == []
    as "a quest not in the log: nothing is done"
  assert done_indexes(quest: 999_999, log: log_of(rows: [])) == []
    as "a quest unknown to the client: nothing is done"
  let one_done =
    log_of(rows: [accepted(quest:, done_mask: 0b10, progress: [0, 12])])
  assert verdict(condition: #(68, 1, quest, 1), log: one_done) == Passes
    as "comparison 1 passes on done"
  assert verdict(condition: #(68, 2, quest, 1), log: one_done) == Fails
    as "comparison 2 fails on done"
  assert verdict(condition: #(68, 2, quest, 0), log: one_done) == Passes
    as "comparison 2 passes on not done"
  assert verdict(condition: #(68, 3, quest, 1), log: one_done) == Fails
    as "comparison 3 fails: only 1 and 2 are cases (Prerequisite.prerequisiteTypeId.68)"
}

// ---- 3: type 43 ----

pub fn an_objective_open_condition_needs_the_log_not_done_and_reachable_test() -> Nil {
  use <- owned_test.run(60_000)
  let chain = quest_support.gated_chain
  let nothing_done =
    log_of(rows: [accepted(quest: chain, done_mask: 0, progress: [0, 0, 0])])
  assert open_indexes(quest: chain, log: nothing_done) == [0]
    as "3668 with nothing done: index 0 has no flag and is open; index 1 (flag 2) waits for index 0; index 2 (flag 1) follows index 1, which is neither done nor reachable (0x140553790)"
  let first_done =
    log_of(rows: [accepted(quest: chain, done_mask: 0b1, progress: [0, 0, 0])])
  assert open_indexes(quest: chain, log: first_done) == [1, 2]
    as "with index 0 done: it is no longer open, index 1 is reachable, and index 2 follows a reachable index 1"
  let skipped_then_gated = quest_support.skipped_then_gated
  assert open_indexes(
      quest: skipped_then_gated,
      log: log_of(rows: [
        accepted(quest: skipped_then_gated, done_mask: 0, progress: [0, 0]),
      ]),
    )
    == [0, 1]
    as "3297 with nothing done: index 1 (flag 2) is open because index 0 has flag 0x20 and does not count; index 0 (flags 0x28, neither 1 nor 2) is reachable too"
  assert open_indexes(
      quest: chain,
      log: log_of(rows: [quest_support.completed(quest_id: chain, at: 1000)]),
    )
    == []
    as "a completed quest is not in the active list: nothing is open (0x140552f50)"
  assert open_indexes(
      quest: chain,
      log: log_of(rows: [quest_support.known(quest_id: chain, state: 4)]),
    )
    == []
    as "a Known quest is not in the active list"
  assert open_indexes(quest: 999_999, log: log_of(rows: [])) == []
    as "an unknown quest has no open objective"
  assert verdict(condition: #(43, 1, chain, 3), log: nothing_done) == Fails
    as "index 3 is past the quest's three objectives: never open"
  assert verdict(condition: #(43, 2, chain, 3), log: nothing_done) == Passes
    as "so comparison 2 (not open) passes there"
  assert verdict(condition: #(43, 2, chain, 1), log: nothing_done) == Passes
    as "comparison 2 passes on an objective that is not open"
  assert verdict(condition: #(43, 2, chain, 0), log: nothing_done) == Fails
    as "comparison 2 fails on an open one"
  assert verdict(condition: #(43, 3, chain, 0), log: nothing_done) == Fails
    as "comparison 3 fails: only 1 and 2 are cases (Prerequisite.prerequisiteTypeId.43)"
}

// ---- 4: types 22, 23, 33 to 36 ----

pub fn an_objective_progress_condition_compares_the_client_progress_test() -> Nil {
  use <- owned_test.run(60_000)
  let kill = quest_support.skipped_first
  let completed = fn(quest) {
    log_of(rows: [quest_support.completed(quest_id: quest, at: 1000)])
  }
  assert progress_of(index: 1, quest: kill, log: completed(kill)) == [100]
    as "a completed quest reads the needed count: objective 2073 is a kill (type 2) of count 12 without flag 0x200, which is shown as a percent, 100 (0x140551840)"
  assert progress_of(
      index: 0,
      quest: quest_support.counted_kill,
      log: completed(quest_support.counted_kill),
    )
    == [3]
    as "objective 6486 has flag 0x200: its needed count is its count, 3"
  assert progress_of(
      index: 0,
      quest: quest_support.visit_pair,
      log: completed(quest_support.visit_pair),
    )
    == [1]
    as "objective 9045 (type 12, count 1) needs 1"
  assert progress_of(
      index: 1,
      quest: kill,
      log: log_of(rows: [
        accepted(quest: kill, done_mask: 0, progress: [0, 500]),
      ]),
    )
    == [50]
    as "in the log, a percent kill with raw 500 reads trunc(100 x (500 x 0.001)) = 50 (0x1406113b0)"
  assert progress_of(
      index: 1,
      quest: kill,
      log: log_of(rows: [accepted(quest: kill, done_mask: 0, progress: [0, 1])]),
    )
    == [1]
    as "a raw value of 1 is not scaled (0x140611403: at most 1 is raw)"
  assert progress_of(
      index: 0,
      quest: quest_support.counted_kill,
      log: log_of(rows: [
        accepted(quest: quest_support.counted_kill, done_mask: 0, progress: [2]),
      ]),
    )
    == [2]
    as "flag 0x200 keeps a kill's progress a count: raw 2 is 2"
  assert progress_of(
      index: 0,
      quest: quest_support.checklist,
      log: log_of(rows: [
        accepted(quest: quest_support.checklist, done_mask: 0, progress: [0b101]),
      ]),
    )
    == [2]
    as "objective 1915 is type 14, a checklist: its progress is the number of set bits of 0b101 (0x1405517a0, 0x1406113b0)"
  assert progress_of(
      index: 0,
      quest: quest_support.soldier_checklist,
      log: log_of(rows: [
        accepted(
          quest: quest_support.soldier_checklist,
          done_mask: 0,
          progress: [0b111],
        ),
      ]),
    )
    == [3]
    as "objective 7647 is type 28 whose PathSoldierActivate row 37 has mode 1: a checklist, 3 bits"
  assert progress_of(
      index: 0,
      quest: quest_support.soldier_row_missing,
      log: log_of(rows: [
        accepted(
          quest: quest_support.soldier_row_missing,
          done_mask: 0,
          progress: [5, 0],
        ),
      ]),
    )
    == [5]
    as "objective 14973 is type 28 whose PathSoldierActivate row 159 the client's table lacks: not a checklist, so raw 5 (0x1405517a0)"
  // Each type reads its own objective.
  let six = quest_support.six_objectives
  let counting_up =
    log_of(rows: [
      accepted(quest: six, done_mask: 0, progress: [5, 6, 7, 8, 9, 10]),
    ])
  assert list.map([0, 1, 2, 3, 4, 5], fn(index) {
      progress_of(index:, quest: six, log: counting_up)
    })
    == [[5], [6], [7], [8], [9], [10]]
    as "types 22, 23, 33, 34, 35 and 36 read objective 0 to 5 (cases 0x16, 0x17, 0x21 to 0x24 of 0x1404a2100 pass the index)"
  // Where the progress is 0.
  assert progress_of(index: 1, quest: 999_999, log: log_of(rows: [])) == [0]
    as "a quest unknown to the client has progress 0 (0x14049f4e5 xor ebx, ebx)"
  assert progress_of(
      index: 1,
      quest: kill,
      log: log_of(rows: [quest_support.known(quest_id: kill, state: 6)]),
    )
    == [0]
    as "a Known quest has progress 0"
  assert progress_of(index: 1, quest: kill, log: log_of(rows: [])) == [0]
    as "a quest not in the log has progress 0"
  assert progress_of(
      index: 2,
      quest: kill,
      log: log_of(rows: [
        accepted(quest: kill, done_mask: 0, progress: [0, 500]),
      ]),
    )
    == [0]
    as "index 2 is past 1949's two objectives: 0"
  assert progress_of(index: 2, quest: kill, log: completed(kill)) == [0]
    as "and a completed quest has no needed count there either: 0"
  // The comparison.
  let fifty =
    log_of(rows: [accepted(quest: kill, done_mask: 0, progress: [0, 500])])
  assert verdict(condition: #(23, 3, kill, 49), log: fifty) == Passes
    as "progress 50 is greater than 49: the progress is the left operand (0x14049f58c, 0x1404a2090)"
  assert verdict(condition: #(23, 3, kill, 50), log: fifty) == Fails
    as "50 is not greater than 50"
  assert verdict(condition: #(23, 4, kill, 50), log: fifty) == Passes
    as "50 is at least 50"
  assert verdict(condition: #(23, 5, kill, 51), log: fifty) == Passes
    as "50 is less than 51"
  assert verdict(condition: #(23, 6, kill, 50), log: fifty) == Passes
    as "50 is at most 50"
  assert verdict(condition: #(23, 2, kill, 49), log: fifty) == Passes
    as "50 is not 49"
  assert verdict(condition: #(23, 5, kill, -1), log: fifty) == Passes
    as "a value of -1 is 4294967295 as an unsigned 32-bit number (0x1404a2090): 50 is less than it"
  assert verdict(condition: #(23, 3, kill, -1), log: fifty) == Fails
    as "and 50 is not greater than it"
  assert verdict(condition: #(23, 7, kill, 0), log: fifty) == Fails
    as "comparison 7 is no case of 0x1404a2090: it fails"
  // The client's row 9207: type 22 on 5857 is 1, or type 6 on 5857 is 3.
  let tables = character_tables.shared()
  let assert Ok(row_9207) =
    prerequisite.load(
      id: PrerequisiteId(9207),
      rows: prerequisite.table_rows(tables:),
      arcs: prerequisite.table_arcs(tables:),
      quests: prerequisite.table_quests(tables:),
    )
    as "the client's table holds Prerequisite 9207 and the quests it names"
  let row_9207_for = fn(log) {
    prerequisite.check(prerequisite: row_9207, subject: player_with(log:))
  }
  let visits = quest_support.visit_pair
  assert row_9207_for(completed(visits)) == Passes
    as "row 9207 (type 22 on 5857 equal to 1, or type 6 equal to 3) passes for a completed quest: needed 1, and state 3"
  assert row_9207_for(
      log_of(rows: [accepted(quest: visits, done_mask: 0, progress: [1, 0])]),
    )
    == Passes
    as "it passes for an accepted quest whose objective 0 is at 1"
  assert row_9207_for(
      log_of(rows: [accepted(quest: visits, done_mask: 0, progress: [0, 0])]),
    )
    == Fails
    as "it fails for an accepted quest whose objective 0 is at 0: not at 1, and not state 3"
  assert row_9207_for(log_of(rows: [])) == Fails
    as "it fails when the quest is not in the log"
}

pub fn a_percent_objective_of_count_one_or_less_still_scales_its_raw_progress_test() -> Nil {
  use <- owned_test.run(60_000)
  let quest = quest_support.daily
  let in_log = fn(raw) {
    log_of(rows: [accepted(quest:, done_mask: 0, progress: [raw])])
  }
  assert progress_of(index: 0, quest:, log: in_log(1000)) == [1]
    as "objective 1961 is a kill (type 2, count 1, flag 0x200 clear): the client scales raw 1000 by 0.001 and its needed count 1 (0x1406113b0 scales above raw 1 with no count test; 0x140551840 gives the count when it is 1 or less)"
  assert progress_of(index: 0, quest:, log: in_log(999)) == [0]
    as "raw 999 reads trunc(1 x 0.999) = 0"
  // No client row holds a percent kind objective of count 0, so one is made by
  // editing objective 1961.
  use tables <- fixture_tables.changed(
    table: "QuestObjective",
    id: quest_support.ordinary_objective,
    with: [#("count", Integer(0))],
  )
  let assert Ok(counting_nothing) = quest_log.quest_of(tables:, id: quest)
    as "the edited tables hold the quest"
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [accepted(quest:, done_mask: 0, progress: [1000])],
      tables:,
    )
    as "the log is one the client takes"
  assert quest_log.objective_progress(log:, quest: counting_nothing, index: 0)
    == 0
    as "a count of 0 needs 0: raw 1000 scales to trunc(0 x 1) = 0"
}

pub fn an_entry_placeholder_replaces_the_quests_type_31_slot_test() -> Nil {
  use <- owned_test.run(60_000)
  let quest = quest_support.daily_with_a_placeholder
  let named = fn(placeholder, raw) {
    log_of(rows: [
      quest_support.active(
        quest_id: quest,
        state: 1,
        placeholder:,
        tracked: False,
        done_mask: 0,
        progress: [raw],
      ),
    ])
  }
  assert progress_of(index: 0, quest:, log: named(0, 100)) == [100]
    as "with no placeholder the slot is the table's objective 9461 (type 31): raw 100 is read as it is"
  assert progress_of(index: 0, quest:, log: named(2073, 100)) == [10]
    as "an entry naming objective 2073 (a kill, type 2, count 12, flag 0x200 clear) puts that row in the slot (0x1405fbdc0: the QuestObjective row replaces the placeholder), so raw 100 scales to 100 x 0.1 = 10"
  assert progress_of(index: 0, quest:, log: named(6486, 2)) == [2]
    as "an entry naming objective 6486 (flag 0x200) keeps a count"
  assert state_of(quest:, log: named(0, 0)) == [1]
    as "the table's slot has no flag 0x20 and is not done"
  assert state_of(quest:, log: named(2072, 0)) == [2]
    as "an entry naming objective 2072 (flags 0x20, which the client's state skips) puts it in the slot, so every objective that counts is done and the state reads 2 (0x1405fbc40)"
}

// ---- 5: type 94 ----

/// The struck unit as a target-side check holds it: the caster's quest log, and the
/// checklist index its 0x262 carried when it has a creature.
fn struck_with(log log: QuestLog, index index: option.Option(Int)) -> Subject {
  let subject =
    prerequisite.of_struck(
      first: Some(prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0)),
      second: prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0),
      player: prerequisite_support.player(),
      quests: log,
    )
  case index {
    Some(index) -> prerequisite.counting(subject:, checklist_index: index)
    None -> subject
  }
}

/// Quest 10520's objective 0 is 21294, a type 14 checklist (TargetGroup 14425, count 3),
/// so its stored progress is the mask of the indexes counted.
pub fn prerequisite_94_passes_comparison_1_only_when_the_creature_is_counted_test() -> Nil {
  use <- owned_test.run(60_000)
  let quest = 10_520
  let counted =
    log_of(rows: [accepted(quest:, done_mask: 0, progress: [4, 0, 0, 0, 0])])
  let clear =
    log_of(rows: [accepted(quest:, done_mask: 0, progress: [0, 0, 0, 0, 0])])
  let checked = fn(subject, condition) {
    prerequisite.check(prerequisite: gate(condition:), subject:)
  }

  let set = struck_with(log: counted, index: Some(2))
  assert checked(set, #(94, 1, quest, 0)) == Passes
    as "the objective's mask 0b100 holds the creature's index 2: counted, so comparison 1 passes (0x140611680)"
  assert checked(set, #(94, 2, quest, 0)) == Fails as "and comparison 2 fails"
  assert checked(set, #(94, 3, quest, 0)) == Fails as "comparison 3 is no case"

  let other = struck_with(log: counted, index: Some(3))
  assert checked(other, #(94, 1, quest, 0)) == Fails
    as "index 3 has no bit in 0b100: not counted, comparison 1 fails"
  assert checked(other, #(94, 2, quest, 0)) == Passes
    as "and comparison 2 passes"

  let none_yet = struck_with(log: clear, index: Some(2))
  assert checked(none_yet, #(94, 1, quest, 0)) == Fails
    as "a clear mask counts nothing"
  assert checked(none_yet, #(94, 2, quest, 0)) == Passes
    as "so comparison 2 passes"

  let not_logged = struck_with(log: log_of(rows: []), index: Some(2))
  assert checked(not_logged, #(94, 1, quest, 0)) == Fails
    as "a quest not in the log counts nothing (0x140552f50)"
  assert checked(not_logged, #(94, 2, quest, 0)) == Passes
    as "so comparison 2 passes"

  let no_creature = struck_with(log: counted, index: None)
  assert checked(no_creature, #(94, 1, quest, 0)) == Fails
    as "a check with no creature has no bit to read: comparison 1 fails (0x14049f5b0)"
  assert checked(no_creature, #(94, 2, quest, 0)) == Passes
    as "and comparison 2 passes, though the mask holds bit 2"

  let unknown_quest = 999_999_999
  assert checked(set, #(94, 1, unknown_quest, 0)) == Fails
    as "a quest the table lacks is the client's unknown quest: comparison 1 fails"
  assert checked(set, #(94, 2, unknown_quest, 0)) == Passes
    as "and comparison 2 passes"

  assert checked(set, #(94, 1, quest, 1)) == Fails
    as "the condition's value is the objective: objective 1 of quest 10520 is no checklist"
}

// ---- 6: a subject with no quest log ----

pub fn a_subject_with_no_quest_log_leaves_quest_conditions_not_read_test() -> Nil {
  use <- owned_test.run(60_000)
  let quest = quest_support.skipped_first
  let creature = prerequisite.of_difficulty(difficulty: 1)
  let checked = fn(condition) {
    prerequisite.check(prerequisite: gate(condition:), subject: creature)
  }
  assert checked(#(6, 1, quest, 0)) == NotRead(prerequisite_type: 6)
    as "a creature's side holds no player's quest log, which the client's check reads from its own player (0x140c65b80): type 6 is not read"
  assert checked(#(68, 1, quest, 0)) == NotRead(prerequisite_type: 68)
    as "type 68 is not read"
  assert checked(#(43, 1, quest, 0)) == NotRead(prerequisite_type: 43)
    as "type 43 is not read"
  assert checked(#(22, 1, quest, 0)) == NotRead(prerequisite_type: 22)
    as "type 22 is not read"
  assert checked(#(36, 1, quest, 0)) == NotRead(prerequisite_type: 36)
    as "type 36 is not read"
  assert checked(#(94, 2, quest, 0)) == Passes
    as "type 94 has no creature here: comparison 2 passes"
  assert checked(#(94, 1, quest, 0)) == Fails as "and comparison 1 fails"
}

// ---- 7: the load ----

pub fn the_load_resolves_each_quest_and_refuses_a_missing_objective_row_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  let quests = prerequisite.table_quests(tables:)
  let row = fn(condition) {
    [prerequisite_support.row(id: 1, flags: 0, conditions: [condition])]
  }
  // A quest with no Quest2 row loads as the client's unknown quest.
  let assert Ok(unknown) =
    prerequisite_support.load_with(
      id: 1,
      rows: row(#(6, 1, 999_999, 0)),
      arcs: [],
      quests:,
    )
    as "a Quest2 id with no row loads: the client reads it as an unknown quest (0x1405a8a40), and 254 type 6 conditions of its table name one"
  assert prerequisite.check(
      prerequisite: unknown,
      subject: player_with(log: log_of(rows: [])),
    )
    == Passes
    as "the unknown quest is state 0"
  // A type 28 objective whose PathSoldierActivate row is missing loads as not a checklist.
  let assert Ok(missing_soldier) =
    quest_log.quest_of(tables:, id: quest_support.soldier_row_missing)
    as "quest 8256 has a Quest2 row and a QuestObjective row for each slot"
  assert list.map(missing_soldier.objectives, fn(objective) {
      objective.checklist
    })
    == [False, False]
    as "PathSoldierActivate row 159 is not in the client's table, so objective 14973 is not a checklist (0x1405517a0), and 14987 is type 32"
  let assert Ok(soldier) =
    quest_log.quest_of(tables:, id: quest_support.soldier_checklist)
    as "quest 5261 has its rows"
  assert list.map(soldier.objectives, fn(objective) { objective.checklist })
    == [True]
    as "row 37 has mode 1: a checklist"
  let assert Ok(_) =
    prerequisite_support.load_with(
      id: 1,
      rows: row(#(22, 1, quest_support.soldier_row_missing, 5)),
      arcs: [],
      quests:,
    )
    as "a condition on that quest loads"
  assert quest_log.quest_of(tables:, id: 999_999) == Error(quest_log.NoQuestRow)
    as "no Quest2 row is the lookup's own answer"
  // A QuestObjective row the quest names but the table lacks fails the load.
  let assert Ok(rows) =
    fixture_tables.remove(
      rows: fixture_tables.rows(),
      table: "QuestObjective",
      id: 2073,
    )
    as "the fixture holds QuestObjective 2073"
  let assert Ok(without) = fixture_tables.load(rows:)
    as "the tables load without the one objective row: nothing else requires it"
  assert quest_log.quest_of(tables: without, id: quest_support.skipped_first)
    == Error(quest_log.NoObjectiveRow(objective_id: 2073))
    as "quest 1949 names objective 2073, which the table lacks"
  assert prerequisite_support.load_with(
      id: 1,
      rows: row(#(6, 1, quest_support.skipped_first, 1)),
      arcs: [],
      quests: prerequisite.table_quests(tables: without),
    )
    == Error(prerequisite.NoQuestObjectiveRow(objective_id: 2073))
    as "a condition on that quest fails the load: a row a table names that is missing is an error, and the game has none (CLAUDE.md)"
}

// ---- 8: the cast ----

pub fn a_cast_gate_reads_the_caster_quest_log_test() -> Nil {
  use <- owned_test.run(60_000)
  let quest = quest_support.skipped_first
  let in_log = log_of(rows: [accepted(quest:, done_mask: 0, progress: [0, 0])])
  // The player's cast rule is given the entered log.
  let #(_, entered) =
    world_entry_support.entry(
      tables: character_tables.shared(),
      character: character_support.character(number: 1),
    )
  assert casting.caster_of(
      tables: character_tables.shared(),
      entered: world_entry.Entered(..entered, quests: in_log),
    ).quests
    == in_log
    as "the caster carries the quest log of the entered player"
  assert casting.caster_of(tables: character_tables.shared(), entered:).quests
    == entered.quests
    as "and the log it holds when none was changed"
  // A caster-side gate.
  let accepted_caster = cast.Caster(..support.caster(), quests: in_log)
  let empty_caster = cast.Caster(..support.caster(), quests: log_of(rows: []))
  assert refusals_of_press(caster: accepted_caster) == []
    as "type 6 on 1949 with value 1 passes while 1949 is Accepted and not done (0x1405fbc40)"
  assert refusals_of_press(caster: empty_caster) == [151]
    as "it fails once 1949 is not in the log: CasterCast refuses with 151 (0x1403ace00)"
  // A target-side gate, through of_struck.
  assert struck_children(caster: accepted_caster) == [#(39_427, 20)]
    as "the target gate of a Proxy reads the caster's log: the child starts on the struck creature"
  assert struck_children(caster: empty_caster) == []
    as "and starts nothing once 1949 is not in the log"
}

/// The condition of both gates: type 6, comparison 1, on quest 1949, value 1.
fn accepted_gate() -> Prerequisite {
  gate(condition: #(6, 1, quest_support.skipped_first, 1))
}

/// The plans with a spell of base 1 (bag index 8) whose cast condition is the gate.
fn plans_gated() -> Plans {
  support.with_spells(plans: support.plans(), spells: [
    Spell(
      ..support.child(spell4_id: 5001, base: 1),
      caster_cast: CastGate(prerequisite: accepted_gate()),
    ),
  ])
}

fn refusals_of_press(caster caster: Caster) -> List(Int) {
  let #(_, effects): #(cast.State, List(Effect)) =
    support.pressed_in(
      plans: plans_gated(),
      state: cast.new(),
      caster:,
      bag_index: 8,
      target: 0,
      at: 1000,
    )
  support.refusal_results(effects:)
}

/// The children a press of base 2 starts, each as (Spell4 id, primary target unit id),
/// when it strikes creature 20 and the Proxy's target gate is the quest gate.
fn struck_children(caster caster: Caster) -> List(#(Int, Int)) {
  let proxy =
    Proxy(
      effect_id: Spell4EffectsId(83_818),
      delay_ms: 0,
      phase_flags: -1,
      condition: GatedOnCasterAndTarget(caster: [], target: accepted_gate()),
      tag: spend.always,
      target: spell_plan.OnEachStruck,
      spell: support.child(spell4_id: 39_427, base: 39_427),
      gains: [],
    )
  let plans =
    support.with_spells(plans: support.plans(), spells: [
      Spell(..support.child(spell4_id: 38_779, base: 2), proxies: [proxy]),
    ])
  let #(state, raw) =
    support.pressed_raw_in(
      plans:,
      state: cast.new(),
      caster:,
      bag_index: 10,
      target: 0,
      at: 2000,
    )
  let #(_, effects) =
    support.answered_posed(
      caster:,
      state:,
      effects: raw,
      at: 2000,
      struck: [
        cast.Hit(
          unit_id: 20,
          unit: cast.HitCreature(life: 1, struck_at_ms: 0),
          descriptions: [],
          controls: [],
        ),
      ],
      rolls: [],
      poses: dict.from_list([
        #(20, prerequisite_support.pose(x: 0.0, z: 0.0, yaw: 0.0)),
      ]),
    )
  list.map(
    support.frames_of(message_id: spell_started.message_id, effects:),
    fn(frame) {
      let assert Ok(decoded) = spell_started.decode(frame.body)
        as "a 0x7ff the rule wrote decodes"
      #(decoded.spell4_id, decoded.primary_target_unit_id)
    },
  )
}
