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
import fixture_tables
import genesis_prime/game/quest_log.{type QuestLog, type UnitRef, UnitRef}
import genesis_prime/store.{type QuestRow, ActiveQuest, QuestRow}
import genesis_prime/table/id
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/world_map/map_id.{MapId}
import gleam/list
import gleam/option.{None, Some}
import planted_table.{Integer}

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

/// The 40 quests of the fixture that hold no condition and no contract, which fill the
/// client's active list (GameFormula 655 dataint0, 40).
pub fn plain() -> List(Int) {
  list.flatten([
    [1804, 1805, 1807, 1808, 1809, 1812, 1822],
    [1854, 1855, 1856, 1859, 1860, 1861, 1862],
    [1873, 1875, 2018, 2020, 2025],
    [2042, 2043, 2044, 2045, 2046, 2047],
    [2050, 2051, 2052, 2058, 2059],
    [2073, 2074, 2075, 2076, 2077, 2078, 2079, 2080, 2081, 2082],
  ])
}

/// The log of these rows, each held to what the client would take
/// (`quest_log.from_rows`).
pub fn log_of(rows rows: List(QuestRow)) -> QuestLog {
  let assert Ok(log) =
    quest_log.from_rows(rows:, tables: character_tables.shared())
    as "the rows are ones the client takes"
  log
}

/// The unit of this id in the first run of the map the tests' players stand in (world 22,
/// instance 1, incarnation 1).
pub fn unit_ref(unit_id unit_id: Int) -> UnitRef {
  UnitRef(map: MapId(world_id: 22, instance: 1), incarnation: 1, unit_id:)
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
      kill_mask: no_kills(),
    )),
  )
}

/// The kill mask of an entry that has killed no member of any group: one 0 for each of the
/// six objective slots a quest has (`kQuestMaxObjective`, 0x1405510d0).
pub fn no_kills() -> List(Int) {
  list.repeat(0, 6)
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

/// An accepted quest with no placeholder, untracked, with these progress values and the
/// members of each objective's named group already killed (`kill_mask`, one 7-bit value for
/// each of the six objective slots).
pub fn accepted_with_kills(
  quest_id quest_id: Int,
  progress progress: List(Int),
  kill_mask kill_mask: List(Int),
) -> QuestRow {
  let accepted = accepted(quest_id:, progress:)
  let assert Some(entry) = accepted.active
    as "an accepted quest holds its entry"
  QuestRow(..accepted, active: Some(ActiveQuest(..entry, kill_mask:)))
}

/// The number of objectives the quest's Quest2 row names.
pub fn objective_count(quest_id quest_id: Int) -> Int {
  let assert Ok(row) =
    quest2.get(tables: character_tables.shared(), id: id.Quest2Id(quest_id))
    as "the fixture holds the quest"
  list.count(
    [
      row.objective0,
      row.objective01,
      row.objective02,
      row.objective03,
      row.objective04,
      row.objective05,
    ],
    fn(objective) { objective != 0 },
  )
}

/// The saved row of a quest the player holds accepted with nothing done: one progress
/// value of 0 for each objective the Quest2 row names.
pub fn untouched(quest_id quest_id: Int) -> QuestRow {
  accepted(quest_id:, progress: list.repeat(0, objective_count(quest_id:)))
}

/// Quest 4361: six objectives (QuestObjective 5871, 5907 to 5911, each of type 5 and
/// count 1), the only quest here whose objective index 5 is a real objective.
pub const six_objectives = 4361

/// An accepted quest with no placeholder, tracked, with these progress values and this
/// many milliseconds left of its time limit (`quest_ms_left`; 0 shows a full timer).
pub fn timed(
  quest_id quest_id: Int,
  progress progress: List(Int),
  quest_ms_left quest_ms_left: Int,
) -> QuestRow {
  QuestRow(
    quest_id:,
    state: 1,
    completed_at: None,
    active: Some(ActiveQuest(
      placeholder_objective_id: 0,
      tracked: True,
      done_mask: 0,
      progress:,
      quest_ms_left:,
      objective_ms_left: list.map(progress, fn(_) { 0 }),
      kill_mask: no_kills(),
    )),
  )
}

/// An accepted quest with no placeholder, tracked, with these progress values, done mask
/// and milliseconds left of each objective's time limit (`objective_ms_left`; 0 for an
/// objective whose timer is not started).
pub fn with_objective_time(
  quest_id quest_id: Int,
  progress progress: List(Int),
  done_mask done_mask: Int,
  objective_ms_left objective_ms_left: List(Int),
) -> QuestRow {
  QuestRow(
    quest_id:,
    state: 1,
    completed_at: None,
    active: Some(ActiveQuest(
      placeholder_objective_id: 0,
      tracked: True,
      done_mask:,
      progress:,
      quest_ms_left: 0,
      objective_ms_left:,
      kill_mask: no_kills(),
    )),
  )
}

/// Runs the body on the fixture's tables with these quests' time limits
/// (`Quest2.maxTimeAllowedMS`, in milliseconds) set, built on the body's heap. The
/// fixture holds none of the client's 14 timed quests, so a test that needs one
/// gives a quest of the fixture a limit.
pub fn with_time_limits(
  limits limits: List(#(Int, Int)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.fold(limits, fixture_tables.rows(), fn(rows, limit) {
      case
        fixture_tables.change(rows:, table: "Quest2", id: limit.0, with: [
          #("maxTimeAllowedMS", Integer(limit.1)),
        ])
      {
        Ok(changed) -> changed
        Error(refusal) -> panic as fixture_tables.describe(refusal)
      }
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}
