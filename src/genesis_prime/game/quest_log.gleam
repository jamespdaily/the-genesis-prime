//// The player's quest log: the quests the character has a record of, which the
//// client is sent at every play entry (0x35F, opcode.0x35f) and the periodic reset
//// it is sent when a daily or weekly reset passes during play (0x362,
//// opcode.0x362). Like the player's life it is a feature of the game connection's
//// rule (genesis_prime/game/connection): a pure value the rule keeps in `Entered`,
//// saved with the place (`rows`, genesis_prime/game/movement `save`) and read from
//// the store's rows at the load (`from_rows`).
////
//// ```
//// store rows (CharacterLoaded.quests) ─▶ from_rows  ─▶ the log, or the quest the client would refuse
//// the log, the clock, the tables      ─▶ login      ─▶ 0x35F: completed, known and active lists, the reset time
//// the log and the clock               ─▶ reset_due  ─▶ NotYet(wait), or 0x362 with every period that reset since
//// the log                             ─▶ rows       ─▶ the store's rows (SavePlace.quests)
//// ```
////
//// - **One entry for each quest.** The client applies its three lists in order and
////   the last wins (opcode.0x35f.adds_not_replaces), and its state setter moves a
////   quest between them (0x1405fbdc0), so a quest is `Active` (states 1 and 2, the
////   active list), `Completed` (state 3) or `Known` (states 4 to 7, the second
////   list), never two.
//// - **A row the client would refuse** fails the load, before anything is sent: an
////   id with no Quest2 row is answered with the Client/Server Data Mismatch
////   disconnect (opcode.0x35f.unknown_quest), and more progress values than the
////   quest has objectives, or a placeholder that is not a type 31 QuestObjective row
////   of the quest, crash or confuse the client (opcode.0x35f.active_state_crash,
////   0x1405fbdc0).
//// - **The send** follows 0x25E in every play entry, an empty log included, and the
////   Holocrypt's rejoin sends none (opcode.0x35f.entry_order,
////   quest_log.process_wide). The lists run in quest id order. A completed quest
////   with a period (Quest2.questRepeatPeriodEnum 1 to 4) carries the bit set only
////   when it was completed at or after the start of its current period
////   (0x1405fb350.completed_bit); the bit is computed here from the time the quest
////   was completed, never stored.
//// - **What a prerequisite reads** is the quest as the client keeps it beside its log
////   (`quest_of`: the quest's objectives with their QuestObjective type, flags and
////   count, read once) and the log's entry for it: `state` (0x1405fbc40),
////   `objective_done` (0x1405510d0), `objective_open` (0x140552f50, 0x140553790) and
////   `objective_progress` (0x14049f4d0, 0x1406113b0, 0x140551840, 0x1405517a0). The
////   client derives a quest's state from its done objectives rather than storing it,
////   so the read derives it the same way.
//// - **The reset time** is the Unix seconds of the latest reset instant. The client
////   seeds its offer picks with it and compares it only for change
////   (0x140611e30, 0x14048a580); it fixes no unit (reset_schedule).
//// - **The resets** are the server's choice, in the `game_number` rows
////   `daily_quest_reset_ms` and `weekly_quest_reset_ms` (genesis_prime/world_map/
////   game_number): daily at the time of day, weekly on the day and time after
////   Monday 00:00 UTC, monthly and yearly at the first daily reset of the month and
////   of the year. The connection's reset timer fires at the next one; a firing before
////   it starts the timer again and sends nothing, and one after several missed sends
////   one 0x362 with the latest time and the bit of every period that reset since the
////   time the client was last told (0x140489aa0).

import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/message/float32
import genesis_prime/message/quest_active.{type QuestActive, QuestActive}
import genesis_prime/message/quest_completed.{
  type QuestCompleted, QuestCompleted,
}
import genesis_prime/message/quest_known.{QuestKnown}
import genesis_prime/message/quest_log as quest_message
import genesis_prime/message/quest_periodic_reset.{QuestPeriodicReset}
import genesis_prime/step.{type Now}
import genesis_prime/store.{type QuestRow, ActiveQuest, QuestRow}
import genesis_prime/table/id.{PathSoldierActivateId, Quest2Id, QuestObjectiveId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/path_soldier_activate
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/table/quest_objective
import genesis_prime/world_map/game_number.{type GameNumbers}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/calendar.{Date, January, TimeOfDay}
import gleam/time/duration
import gleam/time/timestamp

/// The quests a character has a record of, by Quest2 id, and the reset time the
/// client was last told (the Unix seconds, 0 before the log is sent). It is built
/// only by `from_rows`, which holds every entry to what the client would take, so a
/// log is never one it would refuse.
pub opaque type QuestLog {
  QuestLog(entries: Dict(Int, Entry), told_reset: Int)
}

/// What the character has of one quest.
type Entry {
  /// In the client's active list (opcode.0x35f): accepted or achieved, with the
  /// placeholder objective's id (0 for none) and, for a quest with a type 31 slot,
  /// that objective's row, which stands in the slot (0x1405fbdc0), whether it is
  /// tracked, the done mask (a bit for each of the six objectives), the progress of
  /// each objective and the time left of the quest and of each objective, in
  /// milliseconds. A quest whose Quest2 row has a time limit (`maxTimeAllowedMS`) also
  /// holds the connection's monotonic time, in milliseconds, at which its time runs
  /// out; `quest_ms_left` is the time the client was last told.
  Active(
    state: ActiveState,
    placeholder_objective_id: Int,
    placeholder: Option(Objective),
    tracked: Bool,
    done_mask: Int,
    progress: List(Int),
    quest_ms_left: Int,
    objective_ms_left: List(Int),
    deadline_ms: Option(Int),
  )
  /// Completed, at this many Unix seconds.
  Completed(at: Int)
  /// In the client's second list: a quest it holds only a state of.
  Known(state: KnownState)
}

/// The two states the client's active list holds (lua QuestState 1 and 2; any other
/// crashes it, opcode.0x35f.active_state_crash).
type ActiveState {
  Accepted
  Achieved
}

/// The states of the client's second list (lua QuestState 4 to 7).
pub type KnownState {
  Botched
  Mentioned
  Abandoned
  Ignored
}

/// Why the client would refuse a saved entry: the quest and what is wrong with it.
pub type Refused {
  Refused(quest_id: Int, reason: Reason)
}

/// What is wrong with a saved entry.
pub type Reason {
  /// The client has no Quest2 row for the id and answers with the Client/Server
  /// Data Mismatch disconnect (opcode.0x35f.unknown_quest).
  NoQuest2Row
  /// The saved state does not go with the saved columns of a quest the client's
  /// lists hold.
  StateDoesNotGoWithColumns(state: Int)
  /// The entry holds this many progress values for a quest with this many
  /// objectives: the client takes one for each (0x1405fbdc0).
  ProgressCountIsNotObjectiveCount(progress: Int, objectives: Int)
  /// The placeholder objective is no QuestObjective row, which the client looks up
  /// for a quest with a type 31 objective slot and would refuse (0x1405fbdc0).
  NoPlaceholderRow(objective_id: Int)
}

/// What the connection's reset timer firing leads to.
pub type ResetDue {
  /// No reset has passed: the timer starts again, to fire in this many
  /// milliseconds, and nothing is sent.
  NotYet(after_ms: Int)
  /// A reset passed: the log that remembers the time it told, the 0x362 to send and
  /// the milliseconds to the next reset, which the timer starts again for.
  Reset(log: QuestLog, frame: Frame, after_ms: Int)
}

/// The log of the saved rows, or the first quest the client would refuse.
pub fn from_rows(
  rows rows: List(QuestRow),
  tables tables: table_store.Tables,
) -> Result(QuestLog, Refused) {
  use entries <- result.map(
    list.try_fold(rows, dict.new(), fn(entries, row) {
      use entry <- result.map(entry_of(row:, tables:))
      dict.insert(entries, row.quest_id, entry)
    }),
  )
  QuestLog(entries:, told_reset: 0)
}

/// The entry one saved row is, when the client would take it.
fn entry_of(
  row row: QuestRow,
  tables tables: table_store.Tables,
) -> Result(Entry, Refused) {
  let refuse = fn(reason) { Refused(quest_id: row.quest_id, reason:) }
  use quest <- result.try(
    quest2.get(tables:, id: Quest2Id(row.quest_id))
    |> result.replace_error(refuse(NoQuest2Row)),
  )
  case row.state, row.completed_at, row.active {
    1, None, Some(active) | 2, None, Some(active) -> {
      let state = case row.state {
        1 -> Accepted
        _ -> Achieved
      }
      use placeholder <- result.map(active_taken(
        quest:,
        active:,
        tables:,
        refuse:,
      ))
      Active(
        state:,
        placeholder_objective_id: active.placeholder_objective_id,
        placeholder:,
        tracked: active.tracked,
        done_mask: active.done_mask,
        progress: active.progress,
        quest_ms_left: active.quest_ms_left,
        objective_ms_left: active.objective_ms_left,
        deadline_ms: None,
      )
    }
    3, Some(at), None -> Ok(Completed(at:))
    4, None, None -> Ok(Known(state: Botched))
    5, None, None -> Ok(Known(state: Mentioned))
    6, None, None -> Ok(Known(state: Abandoned))
    7, None, None -> Ok(Known(state: Ignored))
    state, _, _ -> Error(refuse(StateDoesNotGoWithColumns(state:)))
  }
}

/// The objectives of the quest, in the order of its six slots, left out where a
/// slot is empty (0).
fn objectives(quest quest: Quest2) -> List(Int) {
  [
    quest.objective0,
    quest.objective01,
    quest.objective02,
    quest.objective03,
    quest.objective04,
    quest.objective05,
  ]
  |> list.filter(fn(objective) { objective != 0 })
}

/// The QuestObjective type of the placeholder slot (0x1405fbdc0).
const placeholder_type = 31

/// Whether a QuestObjective row is of the placeholder type.
fn is_placeholder(
  objective objective: Int,
  tables tables: table_store.Tables,
) -> Bool {
  case quest_objective.get(tables:, id: QuestObjectiveId(objective)) {
    Ok(row) -> row.type_ == placeholder_type
    Error(Nil) -> False
  }
}

/// The row the client's state setter puts in the quest's type 31 slot, when it takes
/// the active columns for the quest: one progress value for each of its objectives,
/// and, for a quest with a type 31 slot, a placeholder that is 0 (no row) or a
/// QuestObjective row. For a quest with no such slot it does not look at the
/// placeholder (0x1405fbdc0).
fn active_taken(
  quest quest: Quest2,
  active active: store.ActiveQuest,
  tables tables: table_store.Tables,
  refuse refuse: fn(Reason) -> Refused,
) -> Result(Option(Objective), Refused) {
  let slots = objectives(quest:)
  use <- bool.guard(
    list.length(active.progress) != list.length(slots),
    Error(
      refuse(ProgressCountIsNotObjectiveCount(
        progress: list.length(active.progress),
        objectives: list.length(slots),
      )),
    ),
  )
  case active.placeholder_objective_id {
    0 -> Ok(None)
    placeholder -> {
      let has_slot =
        list.any(slots, fn(slot) { is_placeholder(objective: slot, tables:) })
      case
        has_slot,
        quest_objective.get(tables:, id: QuestObjectiveId(placeholder))
      {
        True, Error(Nil) ->
          Error(refuse(NoPlaceholderRow(objective_id: placeholder)))
        True, Ok(row) -> Ok(Some(objective_of(tables:, row:)))
        False, _ -> Ok(None)
      }
    }
  }
}

/// What a refusal says, for the fault the connection logs.
pub fn describe(refused refused: Refused) -> String {
  "quest "
  <> int.to_string(refused.quest_id)
  <> ": "
  <> reason_text(reason: refused.reason)
}

fn reason_text(reason reason: Reason) -> String {
  case reason {
    NoQuest2Row ->
      "the client has no Quest2 row for it and answers with the Client/Server Data Mismatch disconnect (opcode.0x35f.unknown_quest)"
    StateDoesNotGoWithColumns(state:) ->
      "the saved state "
      <> int.to_string(state)
      <> " does not go with the saved columns of a quest the client's lists hold"
    ProgressCountIsNotObjectiveCount(progress:, objectives:) ->
      int.to_string(progress)
      <> " progress values for a quest of "
      <> int.to_string(objectives)
      <> " objectives, which the client would refuse (0x1405fbdc0)"
    NoPlaceholderRow(objective_id:) ->
      "the placeholder objective "
      <> int.to_string(objective_id)
      <> " is no QuestObjective row, which the client looks up for a quest with a type 31 objective slot and would refuse (0x1405fbdc0)"
  }
}

/// The reset time the client was last told, in Unix seconds: 0 before the log is
/// sent.
pub fn told_reset(log log: QuestLog) -> Int {
  log.told_reset
}

/// The rows the log is saved as at this monotonic time in milliseconds, in quest id
/// order. A running timed quest is saved with the time it has left, and never 0, which
/// the client's 0x35F shows as a full timer (`opcode.0x35f`, `0x1406118a0`).
pub fn rows(log log: QuestLog, now_ms now_ms: Int) -> List(QuestRow) {
  in_quest_order(log:)
  |> list.map(fn(pair) {
    let #(quest_id, entry) = pair
    case entry {
      Active(
        state:,
        placeholder_objective_id:,
        tracked:,
        done_mask:,
        progress:,
        quest_ms_left: told_ms_left,
        objective_ms_left:,
        deadline_ms:,
        ..,
      ) -> {
        let quest_ms_left = case deadline_ms {
          Some(deadline_ms) -> int.max(1, deadline_ms - now_ms)
          None -> told_ms_left
        }
        QuestRow(
          quest_id:,
          state: active_state_number(state:),
          completed_at: None,
          active: Some(ActiveQuest(
            placeholder_objective_id:,
            tracked:,
            done_mask:,
            progress:,
            quest_ms_left:,
            objective_ms_left:,
          )),
        )
      }
      Completed(at:) ->
        QuestRow(quest_id:, state: 3, completed_at: Some(at), active: None)
      Known(state:) ->
        QuestRow(
          quest_id:,
          state: known_state_number(state:),
          completed_at: None,
          active: None,
        )
    }
  })
}

/// The entries with their quest ids, in quest id order.
fn in_quest_order(log log: QuestLog) -> List(#(Int, Entry)) {
  dict.to_list(log.entries)
  |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
}

/// The lua QuestState of an active quest.
fn active_state_number(state state: ActiveState) -> Int {
  case state {
    Accepted -> 1
    Achieved -> 2
  }
}

/// The lua QuestState of a quest of the second list.
fn known_state_number(state state: KnownState) -> Int {
  case state {
    Botched -> 4
    Mentioned -> 5
    Abandoned -> 6
    Ignored -> 7
  }
}

/// The log as the client is sent it at a play entry, and the log that remembers the
/// reset time the message carried.
pub fn login(
  log log: QuestLog,
  numbers numbers: GameNumbers,
  tables tables: table_store.Tables,
  now now: Now,
) -> #(QuestLog, Frame) {
  let latest = latest_resets(numbers:, at_ms: step.unix_milliseconds(now:))
  let reset_time = latest_of(latest:) / 1000
  let entries = in_quest_order(log:)
  let completed =
    list.filter_map(entries, fn(pair) {
      case pair.1 {
        Completed(at:) ->
          Ok(completed_entry(quest_id: pair.0, at:, tables:, latest:))
        Active(..) | Known(..) -> Error(Nil)
      }
    })
  let known =
    list.filter_map(entries, fn(pair) {
      case pair.1 {
        Known(state:) ->
          Ok(QuestKnown(quest_id: pair.0, state: known_state_number(state:)))
        Active(..) | Completed(..) -> Error(Nil)
      }
    })
  let active =
    list.filter_map(entries, fn(pair) {
      case pair.1 {
        Active(..) as entry -> Ok(active_entry(quest_id: pair.0, entry:))
        Completed(..) | Known(..) -> Error(Nil)
      }
    })
  let assert Ok(body) =
    quest_message.encode(quest_message.QuestLog(
      completed:,
      known:,
      active:,
      reset_time:,
    ))
    as "the saved quest ids fit 15 bits, the lists and the Unix seconds fit the message"
  #(
    QuestLog(
      entries: dict.map_values(log.entries, fn(quest_id, entry) {
        started_running(entry:, quest_id:, tables:, now_ms: now.monotonic_ms)
      }),
      told_reset: reset_time,
    ),
    Frame(message_id: quest_message.message_id, body:),
  )
}

/// The entry with its time running from this monotonic time, when its Quest2 row has a
/// time limit: the time the client was told is left, and 0 is a full timer, which is
/// what the client shows for 0 (`opcode.0x35f`, `0x1406118a0`).
fn started_running(
  entry entry: Entry,
  quest_id quest_id: Int,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
) -> Entry {
  case entry {
    Active(quest_ms_left:, ..) ->
      case quest2.get(tables:, id: Quest2Id(quest_id)) {
        Ok(quest) if quest.max_time_allowed_ms > 0 ->
          Active(
            ..entry,
            deadline_ms: Some(
              now_ms
              + case quest_ms_left {
                0 -> quest.max_time_allowed_ms
                left -> left
              },
            ),
          )
        Ok(_) | Error(Nil) -> entry
      }
    Completed(..) | Known(..) -> entry
  }
}

/// One entry of the completed list: flagged when the quest has a period and was
/// completed at or after the start of its current period (0x1405fb350.completed_bit).
fn completed_entry(
  quest_id quest_id: Int,
  at at: Int,
  tables tables: table_store.Tables,
  latest latest: Resets,
) -> QuestCompleted {
  let assert Ok(quest) = quest2.get(tables:, id: Quest2Id(quest_id))
    as "from_rows refused a quest the table has no row for"
  let period_start_ms = case quest.quest_repeat_period_enum {
    1 -> Ok(latest.daily)
    2 -> Ok(latest.weekly)
    3 -> Ok(latest.monthly)
    4 -> Ok(latest.yearly)
    _ -> Error(Nil)
  }
  let in_current_period = case period_start_ms {
    Ok(start_ms) if at * 1000 >= start_ms -> 1
    Ok(_) | Error(Nil) -> 0
  }
  QuestCompleted(quest_id:, in_current_period:)
}

/// One entry of the active list. The flags word is the tracked bit shifted by 1 and
/// the done mask shifted by 2 (opcode.0x35f).
fn active_entry(quest_id quest_id: Int, entry entry: Entry) -> QuestActive {
  let assert Active(
    state:,
    placeholder_objective_id:,
    tracked:,
    done_mask:,
    progress:,
    quest_ms_left:,
    objective_ms_left:,
    ..,
  ) = entry
    as "only active entries are listed"
  let tracked_bit = case tracked {
    True -> 1
    False -> 0
  }
  QuestActive(
    quest_id:,
    state: active_state_number(state:),
    placeholder_objective_id:,
    flags: int.bitwise_or(
      int.bitwise_shift_left(tracked_bit, 1),
      int.bitwise_shift_left(done_mask, 2),
    ),
    progress:,
    quest_ms_left:,
    objective_ms_left:,
  )
}

/// The milliseconds a day and a week last.
const day_ms = 86_400_000

const week_ms = 604_800_000

/// The first Monday after the Unix epoch, Thursday 1970-01-01, in milliseconds: the
/// weekly reset is this far from the epoch plus whole weeks plus its offset in the
/// week.
const first_monday_ms = 345_600_000

/// The latest reset instant of each period at some time, in Unix milliseconds.
type Resets {
  Resets(daily: Int, weekly: Int, monthly: Int, yearly: Int)
}

/// The remainder of a division that is never negative.
fn modulo(value value: Int, by by: Int) -> Int {
  let assert Ok(remainder) = int.modulo(value, by)
    as "the divisor is a constant above zero"
  remainder
}

/// The latest instant of each period's reset at or before `at_ms`.
fn latest_resets(numbers numbers: GameNumbers, at_ms at_ms: Int) -> Resets {
  let daily_ms = numbers.daily_quest_reset_ms
  let latest_daily = at_ms - modulo(value: at_ms - daily_ms, by: day_ms)
  let latest_weekly =
    at_ms
    - modulo(
      value: at_ms - first_monday_ms - numbers.weekly_quest_reset_ms,
      by: week_ms,
    )
  // The month and the year start at the first daily reset: before it the previous
  // month's period still runs, so the month and the year are those of the time of
  // day of the reset earlier.
  let #(date, _) =
    timestamp.to_calendar(
      timestamp.from_unix_seconds({ at_ms - daily_ms } / 1000),
      calendar.utc_offset,
    )
  Resets(
    daily: latest_daily,
    weekly: latest_weekly,
    monthly: daily_reset_on(date: Date(..date, day: 1), daily_ms:),
    yearly: daily_reset_on(date: Date(date.year, January, 1), daily_ms:),
  )
}

/// The Unix milliseconds of the daily reset on a date.
fn daily_reset_on(date date: calendar.Date, daily_ms daily_ms: Int) -> Int {
  let midnight =
    timestamp.from_calendar(
      date:,
      time: TimeOfDay(hours: 0, minutes: 0, seconds: 0, nanoseconds: 0),
      offset: duration.empty,
    )
  let #(seconds, _) = timestamp.to_unix_seconds_and_nanoseconds(midnight)
  seconds * 1000 + daily_ms
}

/// The latest of the four instants.
fn latest_of(latest latest: Resets) -> Int {
  int.max(
    int.max(latest.daily, latest.weekly),
    int.max(latest.monthly, latest.yearly),
  )
}

/// The milliseconds from `at_ms` to the next daily or weekly reset: an instant at
/// `at_ms` has passed.
fn until_next(numbers numbers: GameNumbers, at_ms at_ms: Int) -> Int {
  let latest = latest_resets(numbers:, at_ms:)
  int.min(latest.daily + day_ms, latest.weekly + week_ms) - at_ms
}

/// What the reset timer firing at `now` leads to.
pub fn reset_due(
  log log: QuestLog,
  numbers numbers: GameNumbers,
  now now: Now,
) -> ResetDue {
  let at_ms = step.unix_milliseconds(now:)
  let latest = latest_resets(numbers:, at_ms:)
  let reset_time = latest_of(latest:) / 1000
  let after_ms = until_next(numbers:, at_ms:)
  case reset_time <= log.told_reset {
    True -> NotYet(after_ms:)
    False -> {
      let periods =
        [
          #(latest.daily, 1),
          #(latest.weekly, 2),
          #(latest.monthly, 4),
          #(latest.yearly, 8),
        ]
        |> list.filter(fn(period) { period.0 / 1000 > log.told_reset })
        |> list.fold(0, fn(bits, period) { int.bitwise_or(bits, period.1) })
      let assert Ok(body) =
        quest_periodic_reset.encode(QuestPeriodicReset(reset_time:, periods:))
        as "the Unix seconds fit 64 bits and the period bits fit 4"
      Reset(
        log: QuestLog(..log, told_reset: reset_time),
        frame: Frame(message_id: quest_periodic_reset.message_id, body:),
        after_ms:,
      )
    }
  }
}

// ---- the client's reads of a quest ----

/// One objective of a quest as the client keeps it (`0x1405a8a40`, the quest record's
/// words 0x18 and after): its QuestObjective type, flags, count and data (the id of
/// the row its type names, a Creature2 id for types 3 and 12), the TargetGroup row of
/// its reward pane (0 for none), and whether it counts its progress as bits
/// (`0x1405517a0`).
pub type Objective {
  Objective(
    type_: Int,
    flags: Int,
    count: Int,
    data: Int,
    reward_pane: Int,
    checklist: Bool,
  )
}

/// A quest as the client keeps it beside its log: its Quest2 id and its objectives in
/// slot order, the empty slots left out.
pub type Quest {
  Quest(id: Int, objectives: List(Objective))
}

/// Why a quest cannot be read from the tables.
pub type QuestRowError {
  /// The client has no Quest2 row for the id: an unknown quest.
  NoQuestRow
  /// A slot of the quest names a QuestObjective row the client's table lacks.
  NoObjectiveRow(objective_id: Int)
}

/// The QuestObjective flag the client's state and reachability skip.
const skipped_flag = 0x20

/// The QuestObjective flag that keeps a kill objective's progress a count.
const counted_flag = 0x200

/// The quest with this Quest2 id, each objective read from QuestObjective.
pub fn quest_of(
  tables tables: table_store.Tables,
  id id: Int,
) -> Result(Quest, QuestRowError) {
  use row <- result.try(
    quest2.get(tables:, id: Quest2Id(id)) |> result.replace_error(NoQuestRow),
  )
  use objectives <- result.map(
    list.try_map(objectives(quest: row), fn(objective_id) {
      use row <- result.map(
        quest_objective.get(tables:, id: QuestObjectiveId(objective_id))
        |> result.replace_error(NoObjectiveRow(objective_id:)),
      )
      objective_of(tables:, row:)
    }),
  )
  Quest(id:, objectives:)
}

/// One QuestObjective row as the client keeps it.
fn objective_of(
  tables tables: table_store.Tables,
  row row: quest_objective.QuestObjective,
) -> Objective {
  Objective(
    type_: row.type_,
    flags: row.flags,
    count: row.count,
    data: row.data,
    reward_pane: row.target_group_id_reward_pane,
    checklist: is_checklist(tables:, objective: row),
  )
}

/// The quest as the log's entry holds it: an active entry's placeholder row stands in
/// the quest's type 31 slot (0x1405fbdc0), whatever its type, flags and count.
fn as_logged(log log: QuestLog, quest quest: Quest) -> Quest {
  case dict.get(log.entries, quest.id) {
    Ok(Active(placeholder: Some(placeholder), ..)) -> {
      let #(before, from_the_slot) =
        list.split_while(quest.objectives, fn(objective) {
          objective.type_ != placeholder_type
        })
      case from_the_slot {
        [_, ..after] ->
          Quest(
            ..quest,
            objectives: list.flatten([before, [placeholder], after]),
          )
        [] -> quest
      }
    }
    Ok(Active(..)) | Ok(Completed(..)) | Ok(Known(..)) | Error(Nil) -> quest
  }
}

/// Whether an objective counts its progress as bits (`0x1405517a0`): types 10, 13, 14
/// and 18, and types 27 and 28 whose PathSoldierActivate row (named by the objective's
/// data) has soldierActivateModeEnum 1 or 2; no such row means not a checklist.
fn is_checklist(
  tables tables: table_store.Tables,
  objective objective: quest_objective.QuestObjective,
) -> Bool {
  case objective.type_ {
    10 | 13 | 14 | 18 -> True
    27 | 28 ->
      case
        path_soldier_activate.get(
          tables:,
          id: PathSoldierActivateId(objective.data),
        )
      {
        Ok(row) ->
          row.soldier_activate_mode_enum == 1
          || row.soldier_activate_mode_enum == 2
        Error(Nil) -> False
      }
    _ -> False
  }
}

/// The state of the quest as the client computes it for the player (lua QuestState,
/// `0x1405fbc40`): 0 for a quest not in the log, 1 accepted, 2 achieved, 3 completed
/// and 4 to 7 for a quest it holds only a state of. A stored Accepted entry reads 2
/// when every objective without flag 0x20 is done, and a quest with no objectives is
/// then achieved at once.
pub fn state(log log: QuestLog, quest quest: Quest) -> Int {
  let quest = as_logged(log:, quest:)
  case dict.get(log.entries, quest.id) {
    Error(Nil) -> 0
    Ok(Completed(..)) -> 3
    Ok(Known(state:)) -> known_state_number(state:)
    Ok(Active(state: Achieved, ..)) -> 2
    Ok(Active(state: Accepted, done_mask:, ..)) ->
      case every_objective_is_done(quest:, done_mask:) {
        True -> 2
        False -> 1
      }
  }
}

/// Whether every objective of the quest without flag 0x20 is done in the mask
/// (`0x1405fbc40`); a quest with no objectives is.
fn every_objective_is_done(
  quest quest: Quest,
  done_mask done_mask: Int,
) -> Bool {
  list.index_map(quest.objectives, fn(objective, index) {
    has_flag(flags: objective.flags, flag: skipped_flag)
    || done_in(mask: done_mask, index:)
  })
  |> list.all(fn(done) { done })
}

/// The state the log stores for a quest, without the derivation `state` makes from the
/// done objectives: 0 for a quest not in the log, 1 accepted, 2 achieved, 3 completed
/// and 4 to 7 for a quest it holds only a state of. It needs no quest rows; the accept
/// checks compare it only against "absent", 1 to 3 and 4 to 7, which `state`'s
/// all-done 2 for a stored 1 does not change.
pub fn stored_state(log log: QuestLog, quest_id quest_id: Int) -> Int {
  case dict.get(log.entries, quest_id) {
    Error(Nil) -> 0
    Ok(Completed(..)) -> 3
    Ok(Known(state:)) -> known_state_number(state:)
    Ok(Active(state:, ..)) -> active_state_number(state:)
  }
}

/// The ids of the quests in the client's active list, accepted or achieved, in
/// ascending order.
pub fn active_ids(log log: QuestLog) -> List(Int) {
  in_quest_order(log:)
  |> list.filter_map(fn(pair) {
    case pair.1 {
      Active(..) -> Ok(pair.0)
      Completed(..) | Known(..) -> Error(Nil)
    }
  })
}

/// How many quests the log holds in the client's active list that count toward its
/// limit: every active entry whose Quest2 flags lack 0x80000, which contracts carry
/// (`0x1405fc680`).
pub fn active_count(
  log log: QuestLog,
  tables tables: table_store.Tables,
) -> Int {
  dict.to_list(log.entries)
  |> list.count(fn(pair) {
    case pair.1 {
      Active(..) ->
        case quest2.get(tables:, id: Quest2Id(pair.0)) {
          Ok(row) -> !has_flag(flags: row.flags, flag: contract_flag)
          Error(Nil) -> False
        }
      Completed(..) | Known(..) -> False
    }
  })
}

/// The Quest2 flag of a contract.
const contract_flag = 0x80000

/// The log after the player accepts the quest: an active Accepted entry in place of
/// whatever the log held of it, tracked (the client gives a new entry the flag word
/// 2, `0x1405fbdc0`), with no objective done and no progress. A quest with a time
/// limit (`max_time_ms`, Quest2 `maxTimeAllowedMS`, 0 for none) runs out that long
/// after `now_ms`, the monotonic time of the accept.
pub fn accept(
  log log: QuestLog,
  quest quest: Quest,
  max_time_ms max_time_ms: Int,
  now_ms now_ms: Int,
) -> QuestLog {
  started(log:, quest:, quest_ms_left: 0, max_time_ms:, now_ms:)
}

/// The log after the player retries a Botched quest: as `accept`, with the quest's
/// whole time left.
pub fn retry(
  log log: QuestLog,
  quest quest: Quest,
  max_time_ms max_time_ms: Int,
  now_ms now_ms: Int,
) -> QuestLog {
  started(log:, quest:, quest_ms_left: max_time_ms, max_time_ms:, now_ms:)
}

fn started(
  log log: QuestLog,
  quest quest: Quest,
  quest_ms_left quest_ms_left: Int,
  max_time_ms max_time_ms: Int,
  now_ms now_ms: Int,
) -> QuestLog {
  let zeros = list.map(quest.objectives, fn(_) { 0 })
  QuestLog(
    ..log,
    entries: dict.insert(
      log.entries,
      quest.id,
      Active(
        state: Accepted,
        placeholder_objective_id: 0,
        placeholder: None,
        tracked: True,
        done_mask: 0,
        progress: zeros,
        quest_ms_left:,
        objective_ms_left: zeros,
        deadline_ms: case max_time_ms > 0 {
          True -> Some(now_ms + max_time_ms)
          False -> None
        },
      ),
    ),
  )
}

/// The log with every accepted quest whose time has run out at this monotonic time
/// held Botched (`hold`), and the ids of those quests in ascending order. An achieved
/// quest keeps its deadline, which is saved and resumed, but is never botched: the
/// client's trackers show it as complete and never as a countdown
/// (`QuestTracker.lua` 775-782, `ContractTracker.lua` 349-356).
pub fn expire(log log: QuestLog, now_ms now_ms: Int) -> #(QuestLog, List(Int)) {
  let due =
    in_quest_order(log:)
    |> list.filter_map(fn(pair) {
      case pair.1 {
        Active(state: Accepted, deadline_ms: Some(deadline_ms), ..)
          if deadline_ms <= now_ms
        -> Ok(pair.0)
        Active(..) | Completed(..) | Known(..) -> Error(Nil)
      }
    })
  #(
    list.fold(due, log, fn(log, quest_id) {
      hold(log:, quest_id:, state: Botched)
    }),
    due,
  )
}

/// The earliest monotonic time at which an accepted quest runs out, when any does.
pub fn next_deadline(log log: QuestLog) -> Option(Int) {
  dict.values(log.entries)
  |> list.filter_map(fn(entry) {
    case entry {
      Active(state: Accepted, deadline_ms: Some(deadline_ms), ..) ->
        Ok(deadline_ms)
      Active(..) | Completed(..) | Known(..) -> Error(Nil)
    }
  })
  |> list.reduce(int.min)
  |> option.from_result
}

/// What the quest deadline timer is told when the earliest deadline moves.
pub type DeadlineTimer {
  /// Start the timer, which is not running, to fire in this many milliseconds.
  StartDeadlineTimer(after_ms: Int)
  /// Cancel the running timer.
  CancelDeadlineTimer
}

/// What the quest deadline timer needs when the earliest deadline of the log
/// (`next_deadline`, on the monotonic clock) goes from `before`, the deadline the
/// running timer is set for, or none when no timer runs, to `after`: nothing when it did
/// not move, the timer started when none ran, the running one cancelled and then started
/// for the new deadline, or only cancelled when none is left. A timer that has just fired
/// or been cancelled is not running.
pub fn deadline_moved(
  before before: Option(Int),
  after after: Option(Int),
  now_ms now_ms: Int,
) -> List(DeadlineTimer) {
  case before, after {
    None, None -> []
    None, Some(deadline_ms) -> [
      StartDeadlineTimer(after_ms: int.max(0, deadline_ms - now_ms)),
    ]
    Some(_), None -> [CancelDeadlineTimer]
    Some(was), Some(deadline_ms) if was == deadline_ms -> []
    Some(_), Some(deadline_ms) -> [
      CancelDeadlineTimer,
      StartDeadlineTimer(after_ms: int.max(0, deadline_ms - now_ms)),
    ]
  }
}

/// The log after the quest is held in the client's second list in this state, in place
/// of whatever the log held of it: the client's state setter moves a quest between its
/// lists (`0x1405fbdc0`), so an active entry is dropped and the state is kept.
pub fn hold(
  log log: QuestLog,
  quest_id quest_id: Int,
  state state: KnownState,
) -> QuestLog {
  QuestLog(..log, entries: dict.insert(log.entries, quest_id, Known(state:)))
}

/// The log after the tracked flag of a quest of the active list is set
/// (`0x1405fcb80`). A quest that is not in the active list is left as it is.
pub fn track(
  log log: QuestLog,
  quest_id quest_id: Int,
  tracked tracked: Bool,
) -> QuestLog {
  case dict.get(log.entries, quest_id) {
    Ok(Active(..) as entry) ->
      QuestLog(
        ..log,
        entries: dict.insert(log.entries, quest_id, Active(..entry, tracked:)),
      )
    Ok(Completed(..)) | Ok(Known(..)) | Error(Nil) -> log
  }
}

/// Whether bit `index` of the done mask is set. The client's objective indexes run 0
/// to 5; a later one is never done.
fn done_in(mask mask: Int, index index: Int) -> Bool {
  index < 6 && int.bitwise_and(mask, int.bitwise_shift_left(1, index)) != 0
}

fn has_flag(flags flags: Int, flag flag: Int) -> Bool {
  int.bitwise_and(flags, flag) != 0
}

/// Whether the quest's objective at `index` is done (`0x1405510d0`): never at or past
/// the objective count, always for a completed quest, by the done mask for a quest in
/// the active list, never for any other.
pub fn objective_done(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
) -> Bool {
  let quest = as_logged(log:, quest:)
  use <- bool.guard(when: index >= list.length(quest.objectives), return: False)
  case dict.get(log.entries, quest.id) {
    Ok(Completed(..)) -> True
    Ok(Active(done_mask:, ..)) -> done_in(mask: done_mask, index:)
    Ok(Known(..)) | Error(Nil) -> False
  }
}

/// Whether the quest's objective at `index` is open (`0x14049f3d0`): the quest is in
/// the active list, the objective is not done, and it is reachable.
pub fn objective_open(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
) -> Bool {
  let quest = as_logged(log:, quest:)
  let in_the_active_list = case dict.get(log.entries, quest.id) {
    Ok(Active(..)) -> True
    Ok(Completed(..)) | Ok(Known(..)) | Error(Nil) -> False
  }
  in_the_active_list
  && !objective_done(log:, quest:, index:)
  && reachable(log:, quest:, index:)
}

/// The quest's open objectives with their indexes (`0x14049f3d0`), the quest read as the
/// log holds it.
pub fn open_objectives(
  log log: QuestLog,
  quest quest: Quest,
) -> List(#(Int, Objective)) {
  let quest = as_logged(log:, quest:)
  list.index_map(quest.objectives, fn(objective, index) { #(index, objective) })
  |> list.filter(fn(pair) { objective_open(log:, quest:, index: pair.0) })
}

/// Whether the objective at `index` is reachable (`0x140553790`): never at or past
/// the count; always for objective type 0; with flag 2, when every earlier objective
/// without flag 0x20 is done; else with flag 1, when every earlier objective is done
/// or itself reachable; with neither flag, always.
fn reachable(log log: QuestLog, quest quest: Quest, index index: Int) -> Bool {
  case list.drop(quest.objectives, index) {
    [] -> False
    [Objective(type_: 0, ..), ..] -> True
    [objective, ..] -> {
      let earlier =
        list.index_map(list.take(quest.objectives, index), fn(before, at) {
          #(at, before)
        })
      case
        has_flag(flags: objective.flags, flag: 2),
        has_flag(flags: objective.flags, flag: 1)
      {
        True, _ ->
          list.all(earlier, fn(before) {
            let #(at, objective) = before
            has_flag(flags: objective.flags, flag: skipped_flag)
            || objective_done(log:, quest:, index: at)
          })
        False, True ->
          list.all(earlier, fn(before) {
            objective_done(log:, quest:, index: before.0)
            || reachable(log:, quest:, index: before.0)
          })
        False, False -> True
      }
    }
  }
}

/// The objective types whose raw progress is thousandths of completion when flag 0x200
/// is clear (`0x1406113b0`): 2, 8, 15, 16 and 46.
fn is_percent_kind(objective objective: Objective) -> Bool {
  case objective.type_ {
    2 | 8 | 15 | 16 | 46 ->
      !has_flag(flags: objective.flags, flag: counted_flag)
    _ -> False
  }
}

/// Whether the objective's stored progress is thousandths of completion: a percent kind
/// objective of a count above 1.
fn is_thousandths(objective objective: Objective) -> Bool {
  is_percent_kind(objective:) && objective.count > 1
}

/// How much progress completes the objective (`0x140551840`): 100 for a percent kind
/// objective of a count above 1, else its count.
fn needed(objective objective: Objective) -> Int {
  use <- bool.guard(when: is_thousandths(objective:), return: 100)
  objective.count
}

/// The stored progress of a thousandths objective of `count` after `kills` more: an
/// equal share of 1000 for each kill, floored, and 1000 once finished. The log keeps
/// the stored value, not the kills, so the kills before are recovered from it by
/// rounding up, which returns them exactly for any count up to 1000 (the floor takes
/// less than one kill's share off).
fn thousandths_after(
  stored stored: Int,
  count count: Int,
  kills kills: Int,
) -> Int {
  let before = { stored * count + 999 } / 1000
  int.min(1000, { 1000 * { before + kills } } / count)
}

/// What one objective's progress leads to: the log after it, the objective's new
/// progress and whether this progress made the quest Achieved, which is only so for a
/// quest that was Accepted before it.
pub type Progressed {
  Progressed(log: QuestLog, progress: Int, became_achieved: Bool)
}

/// The log after `amount` is added to the progress of the quest's objective at `index`,
/// capped at the objective's needed count (`0x140551840`), or `Error(Nil)` when the
/// objective takes none: the quest is not in the active list (Accepted or Achieved), or
/// the objective is done, not reachable or past the quest's objectives (`0x1405510d0`
/// tests only for state 3, so an Achieved quest takes progress; `0x140553790`). The
/// objective is done once its progress reaches the needed count, which sets bit `index`
/// of the done mask (`0x1406115a0`); when every objective without flag 0x20 is then
/// done, an Accepted quest becomes Achieved (`0x1405fbc40`, `0x1405fbdc0`). An Achieved
/// quest stays Achieved: only an objective with flag 0x20 is still open in it. A count
/// objective takes `amount` as it is. A percent kind objective of a count above 1 holds
/// thousandths (`0x1406113b0`), and `amount` is a number of kills: each is an equal
/// share of 1000 (floored), and the objective is done once the progress the client
/// shows reaches 100, which is its count's kills. A checklist's progress is in bits,
/// which this does not read.
pub fn progressed(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
  amount amount: Int,
) -> Result(Progressed, Nil) {
  let quest = as_logged(log:, quest:)
  case dict.get(log.entries, quest.id), list.drop(quest.objectives, index) {
    Ok(Active(state:, done_mask:, progress:, ..) as entry), [objective, ..]
      if index >= 0
    -> {
      use <- bool.guard(
        when: !objective_open(log:, quest:, index:),
        return: Error(Nil),
      )
      let stored = list.drop(progress, index) |> list.first |> result.unwrap(0)
      let thousandths = is_thousandths(objective:)
      let new_progress = case thousandths {
        True ->
          thousandths_after(stored:, count: objective.count, kills: amount)
        False -> int.min(objective.count, stored + amount)
      }
      let shown = case thousandths {
        True -> in_log_progress(objective:, stored: new_progress)
        False -> new_progress
      }
      let done_mask = case shown >= needed(objective:) {
        True -> int.bitwise_or(done_mask, int.bitwise_shift_left(1, index))
        False -> done_mask
      }
      let became_achieved =
        state == Accepted && every_objective_is_done(quest:, done_mask:)
      Ok(Progressed(
        log: QuestLog(
          ..log,
          entries: dict.insert(
            log.entries,
            quest.id,
            Active(
              ..entry,
              state: case became_achieved {
                True -> Achieved
                False -> state
              },
              done_mask:,
              progress: list.index_map(progress, fn(old, at) {
                case at == index {
                  True -> new_progress
                  False -> old
                }
              }),
            ),
          ),
        ),
        progress: new_progress,
        became_achieved:,
      ))
    }
    _, _ -> Error(Nil)
  }
}

/// The progress of the quest's objective at `index` as a prerequisite compares it
/// (`0x14049f4d0`): 0 for an index at or past the count, the needed count for a
/// completed quest, the in-log progress for a quest in the active list, 0 for any other.
pub fn objective_progress(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
) -> Int {
  let quest = as_logged(log:, quest:)
  case list.drop(quest.objectives, index), dict.get(log.entries, quest.id) {
    [], _ -> 0
    [objective, ..], Ok(Completed(..)) -> needed(objective:)
    [objective, ..], Ok(Active(progress:, ..)) ->
      in_log_progress(
        objective:,
        stored: list.drop(progress, index) |> list.first |> result.unwrap(0),
      )
    _, Ok(Known(..)) | _, Error(Nil) -> 0
  }
}

/// An objective's progress in a log entry (`0x1406113b0`): the stored value, its set
/// bits for a checklist, and above 1 for a percent kind objective, whatever its count,
/// the thousandths of completion as a share of the needed count, worked in 32-bit
/// floats.
fn in_log_progress(objective objective: Objective, stored stored: Int) -> Int {
  let raw = case objective.checklist {
    True -> set_bits(of: stored)
    False -> stored
  }
  case raw > 1 && is_percent_kind(objective:) {
    False -> raw
    True -> {
      let share =
        float32.product(
          left: float32.rounded(value: int.to_float(raw)),
          right: float32.rounded(value: 0.001),
        )
      float32.product(
        left: float32.rounded(value: int.to_float(needed(objective:))),
        right: share,
      )
      |> float.truncate
    }
  }
}

fn set_bits(of number: Int) -> Int {
  case number {
    0 -> 0
    _ ->
      int.bitwise_and(number, 1)
      + set_bits(of: int.bitwise_shift_right(number, 1))
  }
}
