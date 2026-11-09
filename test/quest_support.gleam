//// What the quest log tests share: the saved rows of a character's quests, and
//// the quests of the client's rows that the fixture tables hold (`roots.tsv`).
////
//// - **One-time, 2347:** three objectives (QuestObjective 2709, 2710, 2711).
//// - **Daily, 1857 and 3204:** one objective (1961) and two (4182, 4183).
//// - **Daily with a placeholder, 6216:** its first objective 9461 is QuestObjective
////   type 31, and it has no other.
//// - **Weekly 9713, monthly 9714, yearly 9715:** no objective, repeat periods 2, 3
////   and 4 (`Quest2.questRepeatPeriodEnum`).
//// - **No row:** 32000, which fits the 15 bits of the message and names no Quest2 row.

import character_tables
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/store.{type QuestRow, ActiveQuest, QuestRow}
import gleam/list
import gleam/option.{None, Some}

pub const one_time = 2347

pub const daily = 1857

pub const daily_two_objectives = 3204

pub const daily_with_a_placeholder = 6216

pub const weekly = 9713

pub const monthly = 9714

pub const yearly = 9715

pub const no_row = 32_000

/// Quest 1949: objective 0 is QuestObjective 2072 (type 9, flags 0x20, which the
/// client's state and reachability skip) and objective 1 is 2073 (a kill, type 2, count
/// 12, no flag 0x200).
pub const skipped_first = 1949

/// Quest 3668: objective 0 is 4744 (type 3, no flags), objective 1 is 4745 (flags 7,
/// whose bit 2 waits for every earlier objective) and objective 2 is 4791 (flags 5, whose
/// bit 1 follows the earlier ones).
pub const gated_chain = 3668

/// Quest 3297: objective 0 is 7943 (flags 0x28, skipped as an earlier objective) and
/// objective 1 is 4299 (flags 18, bit 2 set).
pub const skipped_then_gated = 3297

/// Quest 4705: one kill objective (6486, type 8, flags 0x204, count 3), whose flag 0x200
/// keeps its progress a count.
pub const counted_kill = 4705

/// Quest 1823: one checklist objective (1915, type 14, count 3).
pub const checklist = 1823

/// Quest 5261: one type 28 objective (7647) whose data names PathSoldierActivate row 37,
/// of mode 1, which makes it a checklist.
pub const soldier_checklist = 5261

/// Quest 8256: objective 0 is 14973 (type 28), whose data names PathSoldierActivate row
/// 159, which the client's table lacks, so it is not a checklist; objective 1 is 14987
/// (type 32).
pub const soldier_row_missing = 8256

/// Quest 5857: objective 0 is 9045 (type 12, count 1), objective 1 is 8784.
pub const visit_pair = 5857

/// QuestObjective 9461, of type 31, the placeholder of quest 6216.
pub const placeholder_objective = 9461

/// QuestObjective 1961, of type 2, the objective of quest 1857.
pub const ordinary_objective = 1961

/// The log of these rows, each held to what the client would take
/// (`quest_log.from_rows`).
pub fn log_of(rows rows: List(QuestRow)) -> QuestLog {
  let assert Ok(log) =
    quest_log.from_rows(rows:, tables: character_tables.shared())
    as "the rows are ones the client takes"
  log
}

/// A quest completed at this many Unix seconds.
pub fn completed(quest_id quest_id: Int, at at: Int) -> QuestRow {
  QuestRow(quest_id:, state: 3, completed_at: Some(at), active: None)
}

/// A quest the client holds only a state of (4 to 7).
pub fn known(quest_id quest_id: Int, state state: Int) -> QuestRow {
  QuestRow(quest_id:, state:, completed_at: None, active: None)
}

/// A quest in the active list (state 1 or 2) with this entry.
pub fn active(
  quest_id quest_id: Int,
  state state: Int,
  placeholder placeholder_objective_id: Int,
  tracked tracked: Bool,
  done_mask done_mask: Int,
  progress progress: List(Int),
) -> QuestRow {
  QuestRow(
    quest_id:,
    state:,
    completed_at: None,
    active: Some(ActiveQuest(
      placeholder_objective_id:,
      tracked:,
      done_mask:,
      progress:,
      quest_ms_left: 0,
      objective_ms_left: list.map(progress, fn(_) { 0 }),
    )),
  )
}

/// An accepted quest with no placeholder, untracked, with these progress values.
pub fn accepted(
  quest_id quest_id: Int,
  progress progress: List(Int),
) -> QuestRow {
  active(
    quest_id:,
    state: 1,
    placeholder: 0,
    tracked: False,
    done_mask: 0,
    progress:,
  )
}

/// Quest 4361: six objectives (QuestObjective 5871, 5907 to 5911, each of type 5 and
/// count 1), the only quest here whose objective index 5 is a real objective.
pub const six_objectives = 4361
