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
//// the log, the loaded spawns          ─▶ without_lost_spawns ─▶ the log, the entries the world lost
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
////   (`quest_row.quest_of`: the quest's objectives with their QuestObjective type,
////   flags and count, read once) and the log's entry for it, through the read-only
////   snapshot `view` gives (genesis_prime/shared/quest_view): `state` (0x1405fbc40),
////   `objective_done` (0x1405510d0), `objective_open` (0x140552f50, 0x140553790) and
////   `objective_progress` (0x14049f4d0, 0x1406113b0, 0x140551840, 0x1405517a0). The
////   client derives a quest's state from its done objectives rather than storing it,
////   so the read derives it the same way. The modules of the units and the map read
////   quests only through a view, never the log.
//// - **The objects an objective counted** are kept for each objective that counts a use
////   of a unit or a cast at one, by the object's spawn (`SpawnId`, the id of the spawn
////   table's row), so a use of the same object counts once and a relog does not let it
////   count again (`used`, `is_used`). The set is saved with the quest (`rows`, read back
////   by `from_rows`), dropped when the objective is done and empty when the quest is
////   taken again. A spawn the loaded world lost is dropped at the load
////   (`without_lost_spawns`) and the caller reports it; the spawns the server placed are among
////   the loaded ones, since their ids are fixed by the client's tables. A
////   run-only spawn (a negative id,
////   `world_map/spawn_source`) counts each use and is never remembered: its id restarts
////   in each map run, so it names no object of a later run (a server guess).
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
import genesis_prime/game/objective_kind
import genesis_prime/message/bit_stream
import genesis_prime/message/quest_active.{type QuestActive, QuestActive}
import genesis_prime/message/quest_completed.{
  type QuestCompleted, QuestCompleted,
}
import genesis_prime/message/quest_known.{QuestKnown}
import genesis_prime/message/quest_log as quest_message
import genesis_prime/message/quest_objective_progress.{QuestObjectiveProgress}
import genesis_prime/message/quest_periodic_reset.{QuestPeriodicReset}
import genesis_prime/message/quest_state.{QuestState}
import genesis_prime/shared/quest_row.{type Objective, type Quest}
import genesis_prime/shared/quest_view.{
  type Entry, type QuestView, Active, Completed, Known,
}
import genesis_prime/step.{type Now}
import genesis_prime/store.{
  type KnownState, type QuestRow, Accepted, Achieved, ActiveQuest, ActiveRow,
  CompletedRow, KnownRow, UsedSpawn,
}
import genesis_prime/table/id.{Quest2Id, QuestObjectiveId}
import genesis_prime/table/loader/store as table_store
import genesis_prime/table/quest2.{type Quest2}
import genesis_prime/table/quest_objective
import genesis_prime/world_map/game_number.{type GameNumbers}
import genesis_prime/world_map/spawn_id.{
  type LoadedSpawns, type SpawnId, SpawnId,
}
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
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

/// The read-only snapshot of the log that the modules of the units and the map read
/// quests through (genesis_prime/shared/quest_view): the log's entries as they are
/// now, which a later change to the log does not reach.
pub fn view(log log: QuestLog) -> QuestView {
  quest_view.of(entries: log.entries)
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

/// The log of the saved rows, or the first quest the client would refuse. An active row's
/// used objects (`store.ActiveQuest.used`) are the set `used` keeps.
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

/// An object an objective had counted that the loaded world has no spawn for.
pub type Lost {
  Lost(quest_id: Int, objective_index: Int, spawn_id: SpawnId)
}

/// The log without the objects it remembers as used whose spawn is not among the loaded
/// `spawns` (a stored row or one the server placed, `objective_spawn`), and each one lost,
/// in quest, objective and spawn order. A spawn the world lost (a row deleted and the world
/// imported again, or a placed spawn a stored row now serves) has no object to count, and
/// one imported later has a new id, so it starts empty; the caller reports the list.
pub fn without_lost_spawns(
  log log: QuestLog,
  spawns spawns: LoadedSpawns,
) -> #(QuestLog, List(Lost)) {
  let #(entries, lost) =
    list.fold(
      quest_view.in_quest_order(view: view(log:)),
      #(log.entries, []),
      fn(so_far, pair) {
        let #(entries, lost) = so_far
        case pair {
          #(quest_id, Active(used:, ..) as entry) -> {
            let #(kept, now_lost) = kept_and_lost(used:, spawns:, quest_id:)
            #(
              dict.insert(entries, quest_id, Active(..entry, used: kept)),
              list.append(lost, now_lost),
            )
          }
          #(_, Completed(..)) | #(_, Known(..)) -> #(entries, lost)
        }
      },
    )
  #(QuestLog(..log, entries:), lost)
}

/// The used objects of one quest that are loaded spawns, and the ones the world lost.
fn kept_and_lost(
  used used: Dict(Int, Set(SpawnId)),
  spawns spawns: LoadedSpawns,
  quest_id quest_id: Int,
) -> #(Dict(Int, Set(SpawnId)), List(Lost)) {
  list.fold(sorted_objects(used:), #(dict.new(), []), fn(so_far, one) {
    let #(kept, lost) = so_far
    let #(objective_index, spawn) = one
    case spawn_id.presence(spawns:, spawn:) {
      spawn_id.Loaded -> #(
        with_used(used: kept, index: objective_index, spawn:),
        lost,
      )
      spawn_id.Lost -> #(
        kept,
        list.append(lost, [
          Lost(quest_id:, objective_index:, spawn_id: spawn),
        ]),
      )
    }
  })
}

/// The used spawns with `spawn` added to the set of the objective at `index`, which starts
/// empty when the objective has none.
fn with_used(
  used used: Dict(Int, Set(SpawnId)),
  index index: Int,
  spawn spawn: SpawnId,
) -> Dict(Int, Set(SpawnId)) {
  dict.upsert(used, index, fn(spawns) {
    set.insert(option.unwrap(spawns, set.new()), spawn)
  })
}

/// The used objects as objective index and spawn, objective then spawn ascending.
fn sorted_objects(used used: Dict(Int, Set(SpawnId))) -> List(#(Int, SpawnId)) {
  dict.to_list(used)
  |> list.flat_map(fn(pair) {
    list.map(set.to_list(pair.1), fn(spawn) { #(pair.0, spawn) })
  })
  |> list.sort(fn(a, b) {
    let SpawnId(first) = a.1
    let SpawnId(second) = b.1
    order.break_tie(int.compare(a.0, b.0), int.compare(first, second))
  })
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
  case row {
    ActiveRow(state:, active:, ..) -> {
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
        objective_deadlines_ms: list.map(active.progress, fn(_) { None }),
        optional_mask: 0,
        kill_masks: active.kill_mask,
        used: list.fold(active.used, dict.new(), fn(used, one) {
          with_used(
            used:,
            index: one.objective_index,
            spawn: SpawnId(one.spawn_id),
          )
        }),
      )
    }
    CompletedRow(at:, ..) -> Ok(Completed(at:))
    KnownRow(state:, ..) -> Ok(Known(state:))
  }
}

/// Whether a QuestObjective row is of the placeholder type.
fn is_placeholder(
  objective objective: Int,
  tables tables: table_store.Tables,
) -> Bool {
  case quest_objective.get(tables:, id: QuestObjectiveId(objective)) {
    Ok(row) -> objective_kind.of_row(row) == objective_kind.Placeholder
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
  let slots = quest_row.objective_ids(quest:)
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
        True, Ok(row) -> Ok(Some(quest_row.objective_of(tables:, row:)))
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
/// order. A running timed quest and each started timed objective is saved with the time
/// it has left, and never 0, which the client's 0x35F shows as a full timer
/// (`opcode.0x35f`, `0x1406118a0`); an objective not started is saved with the time the
/// client was told, 0 for a new entry. An active quest's used objects are saved in
/// objective then spawn order (`store.UsedSpawn`), so a log that did not change saves the
/// rows it loaded.
pub fn rows(log log: QuestLog, now_ms now_ms: Int) -> List(QuestRow) {
  quest_view.in_quest_order(view: view(log:))
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
        objective_ms_left: told_objective_ms_left,
        deadline_ms:,
        objective_deadlines_ms:,
        kill_masks:,
        used:,
        ..,
      ) -> {
        let quest_ms_left = case deadline_ms {
          Some(deadline_ms) -> int.max(1, deadline_ms - now_ms)
          None -> told_ms_left
        }
        let objective_ms_left =
          objectives_ms_left(
            told: told_objective_ms_left,
            deadlines: objective_deadlines_ms,
            now_ms:,
          )
        ActiveRow(
          quest_id:,
          state:,
          active: ActiveQuest(
            placeholder_objective_id:,
            tracked:,
            done_mask:,
            progress:,
            quest_ms_left:,
            objective_ms_left:,
            kill_mask: kill_masks,
            used: list.map(sorted_objects(used:), fn(one) {
              let SpawnId(spawn_id) = one.1
              UsedSpawn(objective_index: one.0, spawn_id:)
            }),
          ),
        )
      }
      Completed(at:) -> CompletedRow(quest_id:, at:)
      Known(state:) -> KnownRow(quest_id:, state:)
    }
  })
}

/// The time each objective has left at this monotonic time: the time to its deadline,
/// at least 1, when it started, and the time the client was told when it did not.
fn objectives_ms_left(
  told told: List(Int),
  deadlines deadlines: List(Option(Int)),
  now_ms now_ms: Int,
) -> List(Int) {
  list.index_map(told, fn(left, index) {
    case list.drop(deadlines, index) {
      [Some(deadline_ms), ..] -> int.max(1, deadline_ms - now_ms)
      [None, ..] | [] -> left
    }
  })
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
  let entries = quest_view.in_quest_order(view: view(log:))
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
          Ok(QuestKnown(
            quest_id: pair.0,
            state: store.known_state_number(state:),
          ))
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
  let body =
    bit_stream.must(
      quest_message.QuestLog(completed:, known:, active:, reset_time:),
      quest_message.encode,
    )
  let running =
    list.fold(dict.keys(log.entries), log, fn(log, quest_id) {
      started_running(log:, quest_id:, tables:, now_ms: now.monotonic_ms)
    })
  #(
    QuestLog(..running, told_reset: reset_time),
    Frame(message_id: quest_message.message_id, body:),
  )
}

/// The log with the time of this quest's entry running from this monotonic time, when
/// the quest or an objective has a time limit: the time the client was told is left, and
/// 0 is a full timer, which is what the client shows for 0 (`opcode.0x35f`,
/// `0x1406118a0`). An objective's time limit counts only for one the client started: a
/// time left, or a 0 on an objective that is reachable (`start_reachable`). A deadline an
/// entry held already, which the settle at the entry may have started, is kept where
/// nothing was told.
fn started_running(
  log log: QuestLog,
  quest_id quest_id: Int,
  tables tables: table_store.Tables,
  now_ms now_ms: Int,
) -> QuestLog {
  case dict.get(log.entries, quest_id) {
    Ok(
      Active(quest_ms_left:, objective_ms_left:, objective_deadlines_ms:, ..) as entry,
    ) -> {
      let assert Ok(row) = quest2.get(tables:, id: Quest2Id(quest_id))
        as "from_rows held the saved quest to a Quest2 row"
      let assert Ok(raw_quest) = quest_row.quest_of(tables:, id: quest_id)
        as "the objectives of a saved quest are rows of the tables"
      let quest = quest_view.as_logged(view: view(log:), quest: raw_quest)
      let deadlines =
        list.index_map(objective_deadlines_ms, fn(held, index) {
          let told = list.drop(objective_ms_left, index) |> list.first
          case told, list.drop(quest.objectives, index) {
            Ok(left), [objective, ..]
              if left > 0 && objective.time_limit_ms > 0
            -> Some(now_ms + left)
            _, _ -> held
          }
        })
      let deadline_ms = case row.max_time_allowed_ms > 0 {
        True ->
          Some(
            now_ms
            + case quest_ms_left {
              0 -> row.max_time_allowed_ms
              left -> left
            },
          )
        False -> None
      }
      QuestLog(
        ..log,
        entries: dict.insert(
          log.entries,
          quest_id,
          Active(..entry, deadline_ms:, objective_deadlines_ms: deadlines),
        ),
      )
      |> start_reachable(quest:, from: 0, now_ms:)
    }
    Ok(Completed(..)) | Ok(Known(..)) | Error(Nil) -> log
  }
}

/// The log with the timer of each objective of the quest at or after `from` started at
/// this monotonic time, when the objective has a time limit, has not started and is
/// reachable (`0x140553790`): the client starts the timers of the reachable objectives
/// when a quest enters state 1 (`0x1406111a0`) and, when an objective is done, those of
/// the later reachable ones whose timer is 0 (`0x1405fb830`). A timer that started is
/// never cleared or started again, so a done objective that a falling count reopens keeps
/// the time it started with. It also marks the objectives with flag 0x20 (`optional_mask`).
fn start_reachable(
  log log: QuestLog,
  quest quest: Quest,
  from from: Int,
  now_ms now_ms: Int,
) -> QuestLog {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  case dict.get(log.entries, quest.id) {
    Ok(Active(objective_deadlines_ms:, done_mask:, ..) as entry) -> {
      let deadlines =
        list.index_map(objective_deadlines_ms, fn(held, index) {
          started_deadline(
            log:,
            quest:,
            held:,
            done: quest_row.done_in(mask: done_mask, index:),
            index:,
            from:,
            now_ms:,
          )
        })
      let optional_mask =
        list.index_fold(quest.objectives, 0, fn(mask, objective, index) {
          case
            quest_row.has_flag(
              flags: objective.flags,
              flag: quest_row.optional_flag,
            )
          {
            True -> int.bitwise_or(mask, int.bitwise_shift_left(1, index))
            False -> mask
          }
        })
      QuestLog(
        ..log,
        entries: dict.insert(
          log.entries,
          quest.id,
          Active(..entry, objective_deadlines_ms: deadlines, optional_mask:),
        ),
      )
    }
    Ok(Completed(..)) | Ok(Known(..)) | Error(Nil) -> log
  }
}

/// The deadline of the quest's objective at `index`: the one it holds, or, when it holds
/// none, is not done, is at or after `from` and has a time limit, and is reachable, the
/// one that starts at this monotonic time.
fn started_deadline(
  log log: QuestLog,
  quest quest: Quest,
  held held: Option(Int),
  done done: Bool,
  index index: Int,
  from from: Int,
  now_ms now_ms: Int,
) -> Option(Int) {
  case held, list.drop(quest.objectives, index) {
    None, [objective, ..]
      if index >= from && objective.time_limit_ms > 0 && !done
    ->
      case quest_view.reachable(view: view(log:), quest:, index:) {
        True -> Some(now_ms + objective.time_limit_ms)
        False -> held
      }
    _, _ -> held
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
  let in_current_period = case in_period(quest_id:, at:, tables:, latest:) {
    Ok(True) -> 1
    Ok(False) | Error(Nil) -> 0
  }
  QuestCompleted(quest_id:, in_current_period:)
}

/// Whether a completion at `at` (Unix seconds) is in the quest's current repeat period,
/// or `Error(Nil)` for a quest that does not repeat.
fn in_period(
  quest_id quest_id: Int,
  at at: Int,
  tables tables: table_store.Tables,
  latest latest: Resets,
) -> Result(Bool, Nil) {
  period_start_ms(quest_id:, tables:, latest:)
  |> result.map(fn(start_ms) { at * 1000 >= start_ms })
}

/// The start of the quest's current repeat period, or `Error(Nil)` for a quest that
/// does not repeat.
fn period_start_ms(
  quest_id quest_id: Int,
  tables tables: table_store.Tables,
  latest latest: Resets,
) -> Result(Int, Nil) {
  let assert Ok(quest) = quest2.get(tables:, id: Quest2Id(quest_id))
    as "from_rows refused a quest the table has no row for"
  case quest.quest_repeat_period_enum {
    1 -> Ok(latest.daily)
    2 -> Ok(latest.weekly)
    3 -> Ok(latest.monthly)
    4 -> Ok(latest.yearly)
    _ -> Error(Nil)
  }
}

/// Whether the quest is completed and, for a quest with a repeat period, completed in
/// its current period at this Unix time in milliseconds: the state a type 24 objective
/// waits for (`QuestObjective.type.24`). A quest that is Achieved, Abandoned, Active
/// again or not in the log is not finished.
pub fn finished(
  log log: QuestLog,
  quest_id quest_id: Int,
  tables tables: table_store.Tables,
  numbers numbers: GameNumbers,
  unix_ms unix_ms: Int,
) -> Bool {
  case dict.get(log.entries, quest_id) {
    Ok(Completed(at:)) ->
      case
        in_period(
          quest_id:,
          at:,
          tables:,
          latest: latest_resets(numbers:, at_ms: unix_ms),
        )
      {
        Ok(in_current_period) -> in_current_period
        Error(Nil) -> True
      }
    Ok(Active(..)) | Ok(Known(..)) | Error(Nil) -> False
  }
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
    state: store.active_state_number(state:),
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
      let body =
        bit_stream.must(
          QuestPeriodicReset(reset_time:, periods:),
          quest_periodic_reset.encode,
        )
      Reset(
        log: QuestLog(..log, told_reset: reset_time),
        frame: Frame(message_id: quest_periodic_reset.message_id, body:),
        after_ms:,
      )
    }
  }
}

// ---- the client's reads of a quest ----

/// The objective slots of a quest, which a kill mask has one value for each of
/// (`0x1405510d0`, kQuestMaxObjective).
const max_objectives = 6

/// The places each QuestObjective is listed at, by its id: for each quest that lists it,
/// the quest as the log reads it, the objective's index there and the objective. A quest
/// whose row cannot be read is left out.
pub fn listed_objectives(
  tables tables: table_store.Tables,
) -> Dict(Int, List(#(Quest, Int, Objective))) {
  quest2.all(tables)
  |> list.filter_map(fn(row) { quest_row.quest_of(tables:, id: row.id) })
  |> list.fold(dict.new(), fn(listed, quest) {
    list.index_fold(quest.objectives, listed, fn(listed, objective, index) {
      dict.upsert(listed, objective.objective_id, fn(places) {
        [#(quest, index, objective), ..option.unwrap(places, [])]
      })
    })
  })
}

/// Whether every objective of the quest without flag 0x20 is done in the log
/// (`0x1405fbc40`), the objectives at the indexes `ignoring` counted as done: the rule of
/// `state` for an objective the caller is about to complete.
pub fn required_objectives_done(
  log log: QuestLog,
  quest quest: Quest,
  ignoring ignoring: List(Int),
) -> Bool {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  quest_row.every_objective_is_done(quest:, done: fn(index) {
    list.contains(ignoring, index)
    || quest_view.objective_done(view: view(log:), quest:, index:)
  })
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
    Ok(Known(state:)) -> store.known_state_number(state:)
    Ok(Active(state:, ..)) -> store.active_state_number(state:)
  }
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
          Ok(row) -> !quest_row.has_flag(flags: row.flags, flag: contract_flag)
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

/// The log after the player turns the quest in: a Completed entry at `at_seconds` (Unix
/// seconds) in place of the active one, which leaves the active list.
pub fn complete(
  log log: QuestLog,
  quest_id quest_id: Int,
  at_seconds at_seconds: Int,
) -> QuestLog {
  QuestLog(
    ..log,
    entries: dict.insert(log.entries, quest_id, Completed(at: at_seconds)),
  )
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
        objective_deadlines_ms: list.map(zeros, fn(_) { None }),
        optional_mask: 0,
        kill_masks: list.repeat(0, max_objectives),
        used: dict.new(),
      ),
    ),
  )
  |> start_reachable(quest:, from: 0, now_ms:)
}

/// The log with every accepted quest whose time has run out at this monotonic time
/// held Botched (`hold`), and the ids of those quests in ascending order. A quest runs
/// out when its own time does or when the time of one of its objectives does before that
/// objective is done (`entry_deadline`). An achieved quest keeps its deadlines, which are
/// saved and resumed, but is never botched: the client's trackers show it as complete and
/// never as a countdown (`QuestTracker.lua` 775-782, `ContractTracker.lua` 349-356). The
/// server botches a quest whose timed objective runs out; the client never botches on its
/// own.
pub fn expire(log log: QuestLog, now_ms now_ms: Int) -> #(QuestLog, List(Int)) {
  let due =
    quest_view.in_quest_order(view: view(log:))
    |> list.filter_map(fn(pair) {
      case entry_deadline(entry: pair.1) {
        Some(deadline_ms) if deadline_ms <= now_ms -> Ok(pair.0)
        Some(_) | None -> Error(Nil)
      }
    })
  #(
    list.fold(due, log, fn(log, quest_id) {
      hold(log:, quest_id:, state: store.Botched)
    }),
    due,
  )
}

/// The earliest monotonic time at which an accepted quest runs out, when any does.
pub fn next_deadline(log log: QuestLog) -> Option(Int) {
  dict.values(log.entries)
  |> list.filter_map(fn(entry) {
    entry_deadline(entry:) |> option.to_result(Nil)
  })
  |> list.reduce(int.min)
  |> option.from_result
}

/// The monotonic time at which an accepted quest runs out: the earlier of its own time
/// and the time of an objective that is not done, reachable or not. A done objective's
/// time botches nothing, nor does that of an objective with flag 0x20, and an Achieved
/// quest has no time that does.
fn entry_deadline(entry entry: Entry) -> Option(Int) {
  case entry {
    Active(
      state: Accepted,
      done_mask:,
      deadline_ms:,
      objective_deadlines_ms:,
      optional_mask:,
      ..,
    ) ->
      list.index_map(objective_deadlines_ms, fn(deadline, index) {
        case
          quest_row.done_in(mask: done_mask, index:)
          || quest_row.done_in(mask: optional_mask, index:)
        {
          True -> None
          False -> deadline
        }
      })
      |> list.prepend(deadline_ms)
      |> option.values
      |> list.reduce(int.min)
      |> option.from_result
    Active(state: Achieved, ..) | Completed(..) | Known(..) -> None
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

/// The quest's open objectives with their indexes (`0x14049f3d0`), the quest read as the
/// log holds it.
pub fn open_objectives(
  log log: QuestLog,
  quest quest: Quest,
) -> List(#(Int, Objective)) {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  list.index_map(quest.objectives, fn(objective, index) { #(index, objective) })
  |> list.filter(fn(pair) {
    quest_view.objective_open(view: view(log:), quest:, index: pair.0)
  })
}

/// The objectives of the quest that stay unreachable (`0x140553790`) while the objectives
/// at `holding` are not done, though every other objective is: the ones the client keeps
/// closed behind them, directly by flag 2 or through a flag 1 chain. An objective
/// at or before the first held one is never among them. An objective kept closed behind
/// another that is itself kept closed is among them too, since the player can do neither
/// before the held ones: the search repeats with the closed ones held until it finds no
/// more. The quest is read as the log holds it: the placeholder row stands in the type 31
/// slot.
pub fn locked_behind(
  log log: QuestLog,
  quest quest: Quest,
  holding holding: List(Int),
) -> List(Int) {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  locked_through(quest:, holding:)
  |> list.filter(fn(index) { !list.contains(holding, index) })
}

/// The held objectives and every objective closed behind them, to a fixed point.
fn locked_through(quest quest: Quest, holding holding: List(Int)) -> List(Int) {
  let closed =
    list.index_map(quest.objectives, fn(_, index) { index })
    |> list.filter(fn(index) {
      list.contains(holding, index)
      || !quest_row.reachable_when(quest:, index:, done: fn(at) {
        !list.contains(holding, at)
      })
    })
  case list.length(closed) == list.length(holding) {
    True -> closed
    False -> locked_through(quest:, holding: closed)
  }
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
  now_ms now_ms: Int,
) -> Result(Progressed, Nil) {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  case dict.get(log.entries, quest.id), list.drop(quest.objectives, index) {
    Ok(Active(done_mask:, progress:, ..) as entry), [objective, ..]
      if index >= 0
    -> {
      use <- bool.guard(
        when: !quest_view.objective_open(view: view(log:), quest:, index:),
        return: Error(Nil),
      )
      let stored = list.drop(progress, index) |> list.first |> result.unwrap(0)
      let thousandths = quest_row.is_thousandths(objective:)
      let new_progress = case thousandths {
        True ->
          thousandths_after(stored:, count: objective.count, kills: amount)
        False -> int.min(objective.count, stored + amount)
      }
      let shown = case thousandths {
        True -> quest_row.in_log_progress(objective:, stored: new_progress)
        False -> new_progress
      }
      let done_mask = case shown >= quest_row.needed(objective:) {
        True -> int.bitwise_or(done_mask, int.bitwise_shift_left(1, index))
        False -> done_mask
      }
      let #(log, moved) =
        store_progress(
          log:,
          quest:,
          entry:,
          index:,
          progress: new_progress,
          done_mask:,
          now_ms:,
        )
      Ok(Progressed(
        log:,
        progress: new_progress,
        became_achieved: moved == BecameAchieved,
      ))
    }
    _, _ -> Error(Nil)
  }
}

/// The log after the unit of checklist index `bit` is counted for the quest's checklist
/// objective at `index`: its stored progress is the mask the client reads bits from, so
/// the unit's bit is set (`0x140611680` tests `mask & (1 << bit)`), and the objective is
/// done once the bits set reach its count (`0x1406113b0`, `0x1406115a0`). `Error(Nil)`
/// when the objective takes no progress (the quest is not in the active list, or the
/// objective is no checklist, is done, is not reachable or is past the quest's
/// objectives) or `bit` is not one of the mask's 32 (the client counts those as never
/// counted). A bit that is set already changes nothing: `changed` is false.
pub fn marked(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
  bit bit: Int,
  now_ms now_ms: Int,
) -> Result(Counted, Nil) {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  case dict.get(log.entries, quest.id), list.drop(quest.objectives, index) {
    Ok(Active(done_mask:, progress:, ..) as entry), [objective, ..]
      if index >= 0
      && bit >= 0
      && bit < quest_row.mask_bits
      && objective.checklist
    -> {
      use <- bool.guard(
        when: !quest_view.objective_open(view: view(log:), quest:, index:),
        return: Error(Nil),
      )
      let before = list.drop(progress, index) |> list.first |> result.unwrap(0)
      let mask = int.bitwise_or(before, int.bitwise_shift_left(1, bit))
      let done_mask = case
        quest_row.set_bits(of: mask) >= quest_row.needed(objective:)
      {
        True -> int.bitwise_or(done_mask, int.bitwise_shift_left(1, index))
        False -> done_mask
      }
      let #(log, moved) =
        store_progress(
          log:,
          quest:,
          entry:,
          index:,
          progress: mask,
          done_mask:,
          now_ms:,
        )
      Ok(Counted(log:, progress: mask, changed: mask != before, moved:))
    }
    _, _ -> Error(Nil)
  }
}

/// The log after a use of, or a cast at, the object of the spawn `unit` is counted for the
/// quest's objective at `index`: one more of its count, which `progressed` takes, and the
/// spawn remembered as used, so that a second use of the same object counts nothing:
/// `changed` is false and the log is as it was. The caller does not ask this of an
/// objective in `reused` (`objective_units.reused`) or of a checklist, which counts by bit
/// (`marked`). The client keeps no per-unit record of a non-checklist objective
/// (`0x1405517a0`, the fact of that name, makes none a checklist), so one count for each
/// object is the server's choice. The set is kept on the quest's entry in the log and saved
/// with it (`rows`), so a relog does not let an object count again, and an abandoned quest
/// that is retaken starts it empty. It is dropped when the objective is done. A run-only
/// spawn (a negative id) counts each use and is never remembered. `Error(Nil)` when the
/// objective takes no progress (`progressed`) or is not open.
pub fn used(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
  unit unit: SpawnId,
  now_ms now_ms: Int,
) -> Result(Counted, Nil) {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  case dict.get(log.entries, quest.id), list.drop(quest.objectives, index) {
    Ok(Active(progress:, ..)), [_, ..] if index >= 0 -> {
      use <- bool.guard(
        when: !quest_view.objective_open(view: view(log:), quest:, index:),
        return: Error(Nil),
      )
      let stored = list.drop(progress, index) |> list.first |> result.unwrap(0)
      case is_used(log:, quest:, index:, unit:) {
        True ->
          Ok(Counted(log:, progress: stored, changed: False, moved: Stayed))
        False -> counted_new_unit(log:, quest:, index:, unit:, now_ms:)
      }
    }
    _, _ -> Error(Nil)
  }
}

/// The count of an object this objective has not counted: one more progress and the spawn
/// remembered (`used`).
fn counted_new_unit(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
  unit unit: SpawnId,
  now_ms now_ms: Int,
) -> Result(Counted, Nil) {
  use counted <- result.map(progressed(log:, quest:, index:, amount: 1, now_ms:))
  Counted(
    log: remember_used(log: counted.log, quest:, index:, unit:),
    progress: counted.progress,
    changed: True,
    moved: case counted.became_achieved {
      True -> BecameAchieved
      False -> Stayed
    },
  )
}

/// The log with the spawn `unit` added to the spawns used for the objective at `index`, or
/// with the objective's set dropped once the objective is done.
fn remember_used(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
  unit unit: SpawnId,
) -> QuestLog {
  let SpawnId(number) = unit
  case dict.get(log.entries, quest.id) {
    Ok(Active(used:, ..) as entry) -> {
      let units = case
        quest_view.objective_done(view: view(log:), quest:, index:),
        number < 0
      {
        True, _ -> dict.delete(used, index)
        False, True -> used
        False, False -> with_used(used:, index:, spawn: unit)
      }
      QuestLog(
        ..log,
        entries: dict.insert(
          log.entries,
          quest.id,
          Active(..entry, used: units),
        ),
      )
    }
    _ -> log
  }
}

/// Whether the spawn `unit` is used already for the quest's objective at `index` (`used`):
/// false for a quest not in the active list. An objective in `reused` and a checklist keep
/// no set, so they have none.
pub fn is_used(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
  unit unit: SpawnId,
) -> Bool {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  case dict.get(log.entries, quest.id) {
    Ok(Active(used:, ..)) ->
      case dict.get(used, index) {
        Ok(units) -> set.contains(units, unit)
        Error(Nil) -> False
      }
    _ -> False
  }
}

/// The creatures a named group lists at most: the data words of a TargetGroup row
/// (`TargetGroup.data0` to `data6`), so the bits of one kill mask value.
const group_slots = 7

/// The log after the player's blow killed the creature of entry `member` of the named group
/// the quest's kill objective at `index` is waiting for, a group of `members` creatures, and
/// whether that blow filled the group. The entry's bit is set in the objective's kill mask,
/// which the client is never sent. The caller counts a kill for the objective (`progressed`)
/// only when the group is full: the client counts nothing for a kill and takes the server's
/// 0x361 only (`opcode.0x361`, `0x140551840`: the needed count of a count 1 kill objective
/// is 1). `Error(Nil)` when the objective takes no progress (the quest is not in the active
/// list, or the objective is done, is not reachable or is past the quest's objectives) or
/// `member` is not an entry of the group.
pub fn kill_marked(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
  member member: Int,
  members members: Int,
) -> Result(#(QuestLog, Bool), Nil) {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  case dict.get(log.entries, quest.id), list.drop(quest.objectives, index) {
    Ok(Active(kill_masks:, ..) as entry), [_, ..]
      if index >= 0 && member >= 0 && member < members && members <= group_slots
    -> {
      use <- bool.guard(
        when: !quest_view.objective_open(view: view(log:), quest:, index:),
        return: Error(Nil),
      )
      let before =
        list.drop(kill_masks, index) |> list.first |> result.unwrap(0)
      let mask = int.bitwise_or(before, int.bitwise_shift_left(1, member))
      let marked =
        QuestLog(
          ..log,
          entries: dict.insert(
            log.entries,
            quest.id,
            Active(
              ..entry,
              kill_masks: replaced_at(values: kill_masks, index:, with: mask),
            ),
          ),
        )
      let group = int.bitwise_shift_left(1, members) - 1
      Ok(#(marked, int.bitwise_and(mask, group) == group))
    }
    _, _ -> Error(Nil)
  }
}

/// The list with the element at `index` replaced by `value`.
fn replaced_at(
  values values: List(Int),
  index index: Int,
  with value: Int,
) -> List(Int) {
  list.index_map(values, fn(old, at) {
    case at == index {
      True -> value
      False -> old
    }
  })
}

/// How an objective's count moved its quest: it stayed as it was, an Accepted quest
/// became Achieved or an Achieved one became Accepted again.
pub type Moved {
  Stayed
  BecameAchieved
  BecameAccepted
}

/// What one objective's count leads to: the log after it, the objective's stored
/// progress, whether that is a change from what was stored, and how the quest moved.
pub type Counted {
  Counted(log: QuestLog, progress: Int, changed: Bool, moved: Moved)
}

/// The log after the server counts the quest's objective at `index` as `value`, or
/// `Error(Nil)` when the quest is not in the active list or has no such objective. The
/// client counts nothing for a collect or visit objective and stores the value of the
/// server's 0x361 (`0x140575a80`), so the stored progress is the value capped at the
/// objective's count and the done bit follows it, set at the count and cleared below it
/// (`0x1406115a0`). Reachability is not tested: the count is a fact about the world, not
/// progress the objective takes. An Accepted quest whose every objective without flag
/// 0x20 is then done becomes Achieved, and an Achieved quest with one not done becomes
/// Accepted again (`0x1405fb830`, `0x1405fbdc0`).
pub fn counted(
  log log: QuestLog,
  quest quest: Quest,
  index index: Int,
  value value: Int,
  now_ms now_ms: Int,
) -> Result(Counted, Nil) {
  let quest = quest_view.as_logged(view: view(log:), quest:)
  case dict.get(log.entries, quest.id), list.drop(quest.objectives, index) {
    Ok(Active(done_mask:, progress:, ..) as entry), [objective, ..]
      if index >= 0
    -> {
      let new_progress = int.max(0, int.min(objective.count, value))
      let done_bit = int.bitwise_shift_left(1, index)
      let done_mask = case new_progress >= quest_row.needed(objective:) {
        True -> int.bitwise_or(done_mask, done_bit)
        False -> int.bitwise_and(done_mask, int.bitwise_not(done_bit))
      }
      let before = list.drop(progress, index) |> list.first |> result.unwrap(0)
      let #(log, moved) =
        store_progress(
          log:,
          quest:,
          entry:,
          index:,
          progress: new_progress,
          done_mask:,
          now_ms:,
        )
      Ok(Counted(
        log:,
        progress: new_progress,
        changed: new_progress != before,
        moved:,
      ))
    }
    _, _ -> Error(Nil)
  }
}

/// The log with the quest's objective at `index` stored as `progress` and the done mask
/// as given, and how that moved the quest: a quest whose every objective without flag
/// 0x20 is done is Achieved and one with an objective not done is Accepted
/// (`0x1405fbc40`, `0x1405fbdc0`). An objective that is done then starts the timers of the
/// later objectives that are reachable (`start_reachable`). A count that falls can take
/// an Achieved quest back to Accepted, which a timed quest carries past its deadline: the
/// quest is held to the time its objectives and the quest started with, and a reopened
/// objective whose time has passed botches it at the next `expire`. Quest 3977's
/// collect objective 5219 is timed and counted this way.
fn store_progress(
  log log: QuestLog,
  quest quest: Quest,
  entry entry: Entry,
  index index: Int,
  progress progress: Int,
  done_mask done_mask: Int,
  now_ms now_ms: Int,
) -> #(QuestLog, Moved) {
  let assert Active(state:, progress: kept, ..) = entry
    as "only an entry in the active list takes a count"
  let all_done =
    quest_row.every_objective_is_done(quest:, done: fn(index) {
      quest_row.done_in(mask: done_mask, index:)
    })
  let #(state, moved) = case state, all_done {
    Accepted, True -> #(Achieved, BecameAchieved)
    Achieved, False -> #(Accepted, BecameAccepted)
    Accepted, False | Achieved, True -> #(state, Stayed)
  }
  let stored =
    QuestLog(
      ..log,
      entries: dict.insert(
        log.entries,
        quest.id,
        Active(
          ..entry,
          state:,
          done_mask:,
          progress: replaced_at(values: kept, index:, with: progress),
        ),
      ),
    )
  case quest_row.done_in(mask: done_mask, index:) {
    True -> #(
      start_reachable(log: stored, quest:, from: index + 1, now_ms:),
      moved,
    )
    False -> #(stored, moved)
  }
}

/// 0x35c, the state a quest is now in (`opcode.0x35c`): the quest, its state and the
/// objective the client is told of, 0 for none.
pub fn quest_state_frame(
  quest_id quest_id: Int,
  state state: Int,
  objective_id objective_id: Int,
) -> Frame {
  let body =
    bit_stream.must(
      QuestState(quest_id:, state:, objective_id:),
      quest_state.encode,
    )
  Frame(message_id: quest_state.message_id, body:)
}

/// 0x361, an objective's new progress (`opcode.0x361`): the quest, the objective's index
/// in the quest and the count it has now.
pub fn quest_objective_progress_frame(
  quest_id quest_id: Int,
  objective_index objective_index: Int,
  progress progress: Int,
) -> Frame {
  let body =
    bit_stream.must(
      QuestObjectiveProgress(quest_id:, objective_index:, progress:),
      quest_objective_progress.encode,
    )
  Frame(message_id: quest_objective_progress.message_id, body:)
}
