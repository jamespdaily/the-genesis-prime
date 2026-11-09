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

/// QuestObjective 9461, of type 31, the placeholder of quest 6216.
pub const placeholder_objective = 9461

/// QuestObjective 1961, of type 2, the objective of quest 1857.
pub const ordinary_objective = 1961

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
