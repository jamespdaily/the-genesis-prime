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
import genesis_prime/message/quest_active.{type QuestActive, QuestActive}
import genesis_prime/message/quest_completed.{
  type QuestCompleted, QuestCompleted,
}
import genesis_prime/message/quest_known.{QuestKnown}
import genesis_prime/message/quest_log as quest_message
import genesis_prime/message/quest_periodic_reset.{QuestPeriodicReset}
import genesis_prime/step.{type Now}
import genesis_prime/store.{type QuestRow, ActiveQuest, QuestRow}
import genesis_prime/table/id.{Quest2Id, QuestObjectiveId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/table/quest_objective
import genesis_prime/world_map/game_number.{type GameNumbers}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
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
  /// placeholder objective's id (0 for none), whether it is tracked, the done mask
  /// (a bit for each of the six objectives), the progress of each objective and
  /// the time left of the quest and of each objective, in milliseconds.
  Active(
    state: ActiveState,
    placeholder_objective_id: Int,
    tracked: Bool,
    done_mask: Int,
    progress: List(Int),
    quest_ms_left: Int,
    objective_ms_left: List(Int),
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
type KnownState {
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
      use Nil <- result.map(active_taken(quest:, active:, tables:, refuse:))
      Active(
        state:,
        placeholder_objective_id: active.placeholder_objective_id,
        tracked: active.tracked,
        done_mask: active.done_mask,
        progress: active.progress,
        quest_ms_left: active.quest_ms_left,
        objective_ms_left: active.objective_ms_left,
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

/// Whether the client's state setter takes the active columns for the quest: one
/// progress value for each of its objectives, and, for a quest with a type 31
/// slot, a placeholder that is 0 or a QuestObjective row, which it puts in the
/// slot. For a quest with no such slot it does not look at the placeholder
/// (0x1405fbdc0).
fn active_taken(
  quest quest: Quest2,
  active active: store.ActiveQuest,
  tables tables: table_store.Tables,
  refuse refuse: fn(Reason) -> Refused,
) -> Result(Nil, Refused) {
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
    0 -> Ok(Nil)
    placeholder -> {
      let has_slot =
        list.any(slots, fn(slot) { is_placeholder(objective: slot, tables:) })
      case
        has_slot,
        quest_objective.get(tables:, id: QuestObjectiveId(placeholder))
      {
        True, Error(Nil) ->
          Error(refuse(NoPlaceholderRow(objective_id: placeholder)))
        True, Ok(_) | False, _ -> Ok(Nil)
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

/// The rows the log is saved as, in quest id order.
pub fn rows(log log: QuestLog) -> List(QuestRow) {
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
        quest_ms_left:,
        objective_ms_left:,
      ) ->
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
    QuestLog(..log, told_reset: reset_time),
    Frame(message_id: quest_message.message_id, body:),
  )
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
