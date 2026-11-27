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
import genesis_prime/game/objective.{type SpawnedUnit, SpawnedUnit}
import genesis_prime/game/prerequisite
import genesis_prime/game/quest.{type Asker, Asker}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/target_group
import genesis_prime/shared/quest_row
import genesis_prime/shared/quest_view.{type QuestView}
import genesis_prime/store.{
  type HeldItem, type QuestRow, Accepted, ActiveQuest, ActiveRow, CompletedRow,
  KnownRow, UsedSpawn,
}
import genesis_prime/table/id
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2
import genesis_prime/world_map/spawn_id.{SpawnId}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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

/// The read-only view of the log of these rows (`log_of`), as the modules of the units
/// read quests.
pub fn view_of(rows rows: List(QuestRow)) -> QuestView {
  quest_log.view(log: log_of(rows:))
}

/// The unit of this id of the picture, standing at the spawn of the same number.
pub fn unit_ref(unit_id unit_id: Int) -> SpawnedUnit {
  SpawnedUnit(unit_id:, spawn_id: SpawnId(unit_id))
}

/// The lua QuestState a saved row holds.
pub fn state_of(row row: QuestRow) -> Int {
  store.quest_columns(row).0
}

/// The completed time a saved row holds: `Some` for a Completed row only.
pub fn completed_at_of(row row: QuestRow) -> Option(Int) {
  store.quest_columns(row).1
}

/// The active entry a saved row holds: `Some` for an Accepted or Achieved row only.
pub fn active_of(row row: QuestRow) -> Option(store.ActiveQuest) {
  store.quest_columns(row).2
}

/// A quest completed at this many Unix seconds.
pub fn completed(quest_id quest_id: Int, at at: Int) -> QuestRow {
  CompletedRow(quest_id:, at:)
}

/// A quest the client holds only a state of (4 to 7).
pub fn known(quest_id quest_id: Int, state state: Int) -> QuestRow {
  let assert Ok(row) =
    store.quest_row(quest_id:, state:, completed_at: None, active: None)
    as "the state is one of 4 to 7"
  row
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
  let assert Ok(row) =
    store.quest_row(
      quest_id:,
      state:,
      completed_at: None,
      active: Some(
        ActiveQuest(
          placeholder_objective_id:,
          tracked:,
          done_mask:,
          progress:,
          quest_ms_left: 0,
          objective_ms_left: list.map(progress, fn(_) { 0 }),
          kill_mask: no_kills(),
          used: [],
        ),
      ),
    )
    as "the state is 1 or 2"
  row
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
  let assert ActiveRow(active: entry, ..) = accepted
    as "an accepted quest holds its entry"
  ActiveRow(..accepted, active: ActiveQuest(..entry, kill_mask:))
}

/// An accepted quest with no placeholder, untracked, with these progress values and these
/// objects already counted (`used`: objective index and spawn id), in the order given.
pub fn accepted_with_used(
  quest_id quest_id: Int,
  progress progress: List(Int),
  used used: List(#(Int, Int)),
) -> QuestRow {
  let accepted = accepted(quest_id:, progress:)
  let assert ActiveRow(active: entry, ..) = accepted
    as "an accepted quest holds its entry"
  ActiveRow(
    ..accepted,
    active: ActiveQuest(
      ..entry,
      used: list.map(used, fn(one) {
        UsedSpawn(objective_index: one.0, spawn_id: one.1)
      }),
    ),
  )
}

/// The objects the log's rows say the quest's objectives have counted, as objective index
/// and spawn id in the order the rows hold them: none for a quest that is not active.
pub fn used_of(log log: QuestLog, quest_id quest_id: Int) -> List(#(Int, Int)) {
  case
    list.find(quest_log.rows(log:, now_ms: 0), fn(row) {
      row.quest_id == quest_id
    })
  {
    Ok(ActiveRow(active: ActiveQuest(used:, ..), ..)) ->
      list.map(used, fn(one) { #(one.objective_index, one.spawn_id) })
    Ok(CompletedRow(..)) | Ok(KnownRow(..)) | Error(Nil) -> []
  }
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
  ActiveRow(
    quest_id:,
    state: Accepted,
    active: ActiveQuest(
      placeholder_objective_id: 0,
      tracked: True,
      done_mask: 0,
      progress:,
      quest_ms_left:,
      objective_ms_left: list.map(progress, fn(_) { 0 }),
      kill_mask: no_kills(),
      used: [],
    ),
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
  ActiveRow(
    quest_id:,
    state: Accepted,
    active: ActiveQuest(
      placeholder_objective_id: 0,
      tracked: True,
      done_mask:,
      progress:,
      quest_ms_left: 0,
      objective_ms_left:,
      kill_mask: no_kills(),
      used: [],
    ),
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

/// The asker holding these items, which the checker carries for the quest checks and the
/// item prerequisites alike.
pub fn with_items(asker asker: Asker, items items: List(HeldItem)) -> Asker {
  Asker(..asker, checker: prerequisite.Checker(..asker.checker, items:))
}

/// Runs the body on the fixture's tables with these QuestObjective cells changed (the
/// objective's id, the column and its new value), built on the body's heap.
pub fn with_objectives(
  edits edits: List(#(Int, String, Int)),
  body body: fn(table_store.Tables) -> a,
) -> a {
  let rows =
    list.fold(edits, fixture_tables.rows(), fn(rows, edit) {
      case
        fixture_tables.change(rows:, table: "QuestObjective", id: edit.0, with: [
          #(edit.1, Integer(edit.2)),
        ])
      {
        Ok(changed) -> changed
        Error(refusal) -> panic as fixture_tables.describe(refusal)
      }
    })
  fixture_tables.on_rows(rows:, reaching: [], body:)
}

/// A log of the quest, accepted, with these objectives (by index) done: each at its count
/// and its done bit set, read from the tables' rows of the quest.
pub fn logged(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  done done: List(Int),
) -> QuestLog {
  let assert Ok(quest) = quest_row.quest_of(tables:, id: quest_id)
    as "the tables hold the quest"
  let progress =
    list.index_map(quest.objectives, fn(objective, index) {
      case list.contains(done, index) {
        True -> objective.count
        False -> 0
      }
    })
  let assert Ok(log) =
    quest_log.from_rows(
      rows: [
        active(
          quest_id:,
          state: 1,
          placeholder: 0,
          tracked: False,
          done_mask: list.fold(done, 0, fn(mask, index) {
            int.bitwise_or(mask, int.bitwise_shift_left(1, index))
          }),
          progress:,
        ),
      ],
      tables:,
    )
    as "the saved rows are ones the client takes"
  log
}

/// The quest `id` as the fixture's tables hold it.
pub fn quest_of(id id: Int) -> quest_row.Quest {
  let assert Ok(quest) =
    quest_row.quest_of(tables: character_tables.shared(), id:)
    as "the fixture holds the quest's rows"
  quest
}

/// The saved row of the quest, as the place save writes it.
pub fn saved_row(log log: QuestLog, quest_id quest_id: Int) -> QuestRow {
  let assert Ok(row) =
    quest_log.rows(log:, now_ms: 0)
    |> list.find(fn(row) { row.quest_id == quest_id })
    as "the log holds the quest"
  row
}

/// The quest as the log reads it, with the objective at `index`.
pub fn objective_at(
  tables tables: table_store.Tables,
  quest_id quest_id: Int,
  index index: Int,
) -> quest_row.Objective {
  let assert Ok(quest) = quest_row.quest_of(tables:, id: quest_id)
    as "the fixture holds the quest"
  let assert Ok(found) = list.drop(quest.objectives, index) |> list.first
    as "the quest has an objective at the index"
  found
}

/// A unit of this creature, of faction 0 and race 0: a type 1 pane reads only the creature.
pub fn unit_of(creature creature: Int) -> target_group.Unit {
  target_group.Unit(
    creature_id: id.Creature2Id(creature),
    faction_id: id.Faction2Id(0),
    unit_race_id: id.UnitRaceId(0),
  )
}
