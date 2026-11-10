//// The quest log's rule for an objective with a time limit (`quest_log`, with
//// `genesis_prime/game/objective`): the deadline an objective starts with, the quest it
//// botches and what is saved. Expected values come from these places.
//// - `QuestObjective.maxTimeAllowedMS` (`table_rows -- QuestObjective`): the time limit of
////   an objective, in milliseconds, which the client counts from when the objective is
////   reachable. `0x1406111a0`, `0x1405fb830` and `0x1406118a0` give the starts: a quest
////   entering state 1 starts each reachable objective's timer; a 0x361 that makes an
////   objective done starts each later reachable objective's timer where it is 0, and the
////   client never clears one; at login a saved value is the time left and 0 is a full
////   timer for the objectives the client started (the reachable ones).
//// - Botched when it runs out: Jim's decision of 2026-11-09. The client never botches or
////   sends anything at zero; a quest it holds only a state of is Botched, state 4.
//// - Only an Accepted quest is botched, and a done objective's deadline botches nothing:
////   the client's trackers show a done objective and an achieved quest as complete, never
////   as a countdown (`QuestTracker.lua` 775-782).
//// - `opcode.0x35f`, `0x1406118a0`: 0 shows a full timer, so a started objective is saved
////   with at least 1 ms left, and 0 only for one not started.
////
//// The quests, from the client's rows in the fixture (`table_rows -- QuestObjective`):
//// - 2911: one objective, 3677, type 2 for Creature2 5006, count 1, flags 0, 60,000 ms.
//// - 2923: its own limit of 120,000 ms and three objectives: 3686 (type 2 for Creature2
////   5006, count 1, flags 0, 30,000 ms), 3687 (type 12, count 1, flags 3, no limit) and 3688
////   (type 2, flags 3, 30,000 ms). Flag 2 waits for every earlier objective to be done.
//// - 3204: 4182 (type 5, count 1, flags 0, no limit) and 4183 (type 8, count 35, flags 3,
////   600,000 ms). A kill of a type 8 objective is a share of 1000, so 35 kills finish it.
//// - The times are the tests' choice: a connection's monotonic milliseconds.

import character_tables
import genesis_prime/game/objective.{Killed}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/target_group
import genesis_prime/step.{Now}
import genesis_prime/store
import genesis_prime/table/id.{Creature2Id, Faction2Id, UnitRaceId}
import gleam/list
import gleam/option.{None, Some}
import owned_test
import quest_support
import spawn_support
import world_entry_support

const one_kill = 2911

const chain = 2923

const gated_timer = 3204

fn quest(id id: Int) -> quest_log.Quest {
  let assert Ok(quest) =
    quest_log.quest_of(tables: character_tables.shared(), id:)
    as "the fixture holds the quest's rows"
  quest
}

fn nothing() -> QuestLog {
  quest_support.log_of(rows: [])
}

fn accepted(
  log log: QuestLog,
  quest_id quest_id: Int,
  max_time_ms max_time_ms: Int,
  at now_ms: Int,
) -> QuestLog {
  quest_log.accept(log:, quest: quest(id: quest_id), max_time_ms:, now_ms:)
}

/// The log after the objective at `index` is advanced by `amount` at this time.
fn progressed(
  log log: QuestLog,
  quest_id quest_id: Int,
  index index: Int,
  amount amount: Int,
  at now_ms: Int,
) -> QuestLog {
  let assert Ok(progressed) =
    quest_log.progressed(
      log:,
      quest: quest(id: quest_id),
      index:,
      amount:,
      now_ms:,
    )
    as "an open objective takes progress"
  progressed.log
}

/// The log after the server counts the objective at `index` as `value` at this time.
fn counted(
  log log: QuestLog,
  quest_id quest_id: Int,
  index index: Int,
  value value: Int,
  at now_ms: Int,
) -> QuestLog {
  let assert Ok(counted) =
    quest_log.counted(log:, quest: quest(id: quest_id), index:, value:, now_ms:)
    as "a quest in the active list takes a count"
  counted.log
}

fn saved(
  log log: QuestLog,
  quest_id quest_id: Int,
  at now_ms: Int,
) -> store.ActiveQuest {
  let assert Ok(row) =
    quest_log.rows(log:, now_ms:)
    |> list.find(fn(row) { row.quest_id == quest_id })
    as "the log holds the quest"
  let assert Some(active) = row.active as "the quest is in the active list"
  active
}

/// The time left of each objective as the save writes it at this time.
fn ms_left(
  log log: QuestLog,
  quest_id quest_id: Int,
  at now_ms: Int,
) -> List(Int) {
  saved(log:, quest_id:, at: now_ms).objective_ms_left
}

fn logged_in(rows rows: List(store.QuestRow), at now_ms: Int) -> QuestLog {
  let tables = character_tables.shared()
  let #(told, _) =
    quest_log.login(
      log: quest_support.log_of(rows:),
      numbers: spawn_support.numbers,
      tables:,
      now: Now(monotonic_ms: now_ms, filetime: world_entry_support.filetime),
    )
  told
}

fn killed_5006() -> objective.Event {
  Killed(target_group.Unit(
    creature_id: Creature2Id(5006),
    faction_id: Faction2Id(1441),
    unit_race_id: UnitRaceId(0),
  ))
}

pub fn accept_starts_the_reachable_timed_objectives_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3677 is the first and only objective: reachable, so its 60,000 ms run from the
  // accept at 1000 ms.
  let log =
    accepted(log: nothing(), quest_id: one_kill, max_time_ms: 0, at: 1000)
  assert quest_log.next_deadline(log:) == Some(61_000)
    as "the objective's 60,000 ms from the accept"
  assert ms_left(log:, quest_id: one_kill, at: 1000) == [60_000]
    as "the save writes the whole time"

  // 4183 has a limit but flag 2: it waits for 4182, so no timer starts for it.
  let log =
    accepted(log: nothing(), quest_id: gated_timer, max_time_ms: 0, at: 1000)
  assert quest_log.next_deadline(log:) == None
    as "a timed objective that is not reachable has no deadline"
  assert ms_left(log:, quest_id: gated_timer, at: 1000) == [0, 0]
    as "an objective not started is saved with 0"

  // Only 3686 is reachable of the three and only it has a limit that starts: 3687 has
  // none and 3688 waits for it. The earlier of its 31,000 ms and the quest's own
  // 121,000 ms is the next deadline.
  let log =
    accepted(log: nothing(), quest_id: chain, max_time_ms: 120_000, at: 1000)
  assert ms_left(log:, quest_id: chain, at: 1000) == [30_000, 0, 0]
    as "the reachable timed objective starts and the others do not"
  assert quest_log.next_deadline(log:) == Some(31_000)
    as "the objective's deadline is before the quest's"

  // A retry of a Botched quest starts them again at the retry.
  let botched =
    quest_log.hold(
      log: accepted(
        log: nothing(),
        quest_id: one_kill,
        max_time_ms: 0,
        at: 1000,
      ),
      quest_id: one_kill,
      state: quest_log.Botched,
    )
  assert quest_log.next_deadline(log: botched) == None
    as "a Botched quest has no deadline"
  let retried =
    quest_log.retry(
      log: botched,
      quest: quest(id: one_kill),
      max_time_ms: 0,
      now_ms: 5000,
    )
  assert quest_log.next_deadline(log: retried) == Some(65_000)
    as "the retry starts the objective's 60,000 ms at 5000 ms"
  assert ms_left(log: retried, quest_id: one_kill, at: 5000) == [60_000]
    as "and saves the whole time"
}

pub fn a_done_objective_starts_the_later_reachable_timers_test() -> Nil {
  use <- owned_test.run(60_000)
  let log =
    accepted(log: nothing(), quest_id: chain, max_time_ms: 120_000, at: 1000)
  // 3686 is done at 10,000 ms: 3687 is reachable and has no limit, and 3688 still waits
  // for 3687, so no timer starts and 3686's own is kept.
  let log = progressed(log:, quest_id: chain, index: 0, amount: 1, at: 10_000)
  assert ms_left(log:, quest_id: chain, at: 10_000) == [21_000, 0, 0]
    as "no later timer starts, and the done objective keeps its deadline, 31,000 ms"
  assert quest_log.next_deadline(log:) == Some(121_000)
    as "a done objective's deadline is not the next one: the quest's is"
  // 3687 is done at 20,000 ms: 3688 is reachable and its 30,000 ms start.
  let log = progressed(log:, quest_id: chain, index: 1, amount: 1, at: 20_000)
  assert ms_left(log:, quest_id: chain, at: 20_000) == [11_000, 0, 30_000]
    as "0x1405fb830: the objective that became reachable starts at the finish of the one before it"
  assert quest_log.next_deadline(log:) == Some(50_000)
    as "the started timer is the next deadline"

  // A timer starts once: 4183's 600,000 ms start when 4182 is done at 5000 ms, and
  // neither more progress on 4183 nor a count of 4182 that goes down and comes back
  // moves them (the client never clears a timer).
  let log =
    accepted(log: nothing(), quest_id: gated_timer, max_time_ms: 0, at: 1000)
  let log =
    progressed(log:, quest_id: gated_timer, index: 0, amount: 1, at: 5000)
  assert ms_left(log:, quest_id: gated_timer, at: 5000) == [0, 600_000]
    as "4182 done starts 4183's timer"
  let log =
    progressed(log:, quest_id: gated_timer, index: 1, amount: 1, at: 9000)
  assert quest_log.next_deadline(log:) == Some(605_000)
    as "progress on the timed objective does not move its deadline"
  let log = counted(log:, quest_id: gated_timer, index: 0, value: 0, at: 12_000)
  let log = counted(log:, quest_id: gated_timer, index: 0, value: 1, at: 15_000)
  assert quest_log.next_deadline(log:) == Some(605_000)
    as "a count that goes down and comes back does not restart a deadline that started"
  assert ms_left(log:, quest_id: gated_timer, at: 15_000) == [0, 590_000]
    as "the save writes what is left of the first start"
}

pub fn a_timed_objective_running_out_botches_the_quest_test() -> Nil {
  use <- owned_test.run(60_000)
  // 3677 is open at its deadline: the quest is Botched, one ms before it is not.
  let log =
    accepted(log: nothing(), quest_id: one_kill, max_time_ms: 0, at: 1000)
  assert quest_log.expire(log:, now_ms: 60_999) == #(log, [])
    as "an objective before its deadline botches nothing"
  let #(expired, due) = quest_log.expire(log:, now_ms: 61_000)
  assert due == [one_kill]
    as "the open objective at its deadline botches its quest"
  assert quest_log.stored_state(log: expired, quest_id: one_kill) == 4
    as "the quest is held Botched, state 4 (opcode.0x35c)"
  assert quest_log.next_deadline(log: expired) == None
    as "a Botched quest has no deadline left"

  // 3686 runs out at 31,000 ms, long before the quest's 121,000 ms: one botch for the
  // quest, not one for each deadline.
  let log =
    accepted(log: nothing(), quest_id: chain, max_time_ms: 120_000, at: 1000)
  assert quest_log.expire(log:, now_ms: 31_000).1 == [chain]
    as "the objective's deadline botches the quest before the quest's own"
  let #(_, due) = quest_log.expire(log:, now_ms: 500_000)
  assert due == [chain] as "a quest past both deadlines is botched once"

  // 3686 done at 10,000 ms: its deadline botches nothing, and the quest's own does.
  let done = progressed(log:, quest_id: chain, index: 0, amount: 1, at: 10_000)
  assert quest_log.expire(log: done, now_ms: 31_000).1 == []
    as "a done objective's deadline botches nothing"
  assert quest_log.expire(log: done, now_ms: 121_000).1 == [chain]
    as "the quest's own deadline still botches it"

  // 4183's deadline passes while it is done and its quest is Achieved, then Accepted
  // again by 4182's count going down: the deadline botches nothing while 4183 is done
  // and a count that takes it back to open is held to the deadline that started.
  let log =
    accepted(log: nothing(), quest_id: gated_timer, max_time_ms: 0, at: 0)
  let log =
    progressed(log:, quest_id: gated_timer, index: 0, amount: 1, at: 1000)
  let log =
    progressed(log:, quest_id: gated_timer, index: 1, amount: 35, at: 2000)
  assert quest_log.stored_state(log:, quest_id: gated_timer) == 2
    as "both objectives done: Achieved"
  assert quest_log.next_deadline(log:) == None
    as "an Achieved quest is not botched, so it has no next deadline"
  let log = counted(log:, quest_id: gated_timer, index: 0, value: 0, at: 3000)
  assert quest_log.stored_state(log:, quest_id: gated_timer) == 1
    as "4182's count going down makes the quest Accepted again"
  assert quest_log.expire(log:, now_ms: 700_000).1 == []
    as "4183 is done, so its deadline, 601,000 ms, botches nothing"
  let log =
    counted(log:, quest_id: gated_timer, index: 1, value: 0, at: 701_000)
  assert quest_log.expire(log:, now_ms: 701_000).1 == [gated_timer]
    as "4183 open again is held to the deadline that started at 1000 ms (a count that goes down does not stop or restart it)"
}

pub fn objective_time_left_is_saved_never_zero_and_resumed_test() -> Nil {
  use <- owned_test.run(60_000)
  // A started objective is saved with what is left, at least 1.
  let log =
    accepted(log: nothing(), quest_id: one_kill, max_time_ms: 0, at: 1000)
  assert ms_left(log:, quest_id: one_kill, at: 26_000) == [35_000]
    as "the time left of 3677's 60,000 ms at 26,000 ms"
  assert ms_left(log:, quest_id: one_kill, at: 61_000) == [1]
    as "0 would show a full timer (0x1406118a0), so a deadline reached is saved with 1 ms left"
  assert ms_left(log:, quest_id: one_kill, at: 90_000) == [1]
    as "and one long past too"
  let log =
    accepted(log: nothing(), quest_id: gated_timer, max_time_ms: 0, at: 1000)
  assert ms_left(log:, quest_id: gated_timer, at: 90_000) == [0, 0]
    as "an objective not started is saved with 0"

  // The rows the store reads back carry the time without the log running.
  let row =
    quest_support.with_objective_time(
      one_kill,
      progress: [0],
      done_mask: 0,
      objective_ms_left: [35_000],
    )
  assert quest_log.rows(log: quest_support.log_of(rows: [row]), now_ms: 99_000)
    == [row]
    as "a log that is not running writes the time it read"

  // Login restores the deadline from the time left.
  let log = logged_in(rows: [row], at: 100_000)
  assert quest_log.next_deadline(log:) == Some(135_000)
    as "the saved 35,000 ms run from the login at 100,000 ms"
  assert ms_left(log:, quest_id: one_kill, at: 110_000) == [25_000]
    as "and the next save writes what is left"

  // 0 is a full timer for a reachable objective (0x1406118a0).
  let full =
    quest_support.with_objective_time(
      one_kill,
      progress: [0],
      done_mask: 0,
      objective_ms_left: [0],
    )
  assert quest_log.next_deadline(log: logged_in(rows: [full], at: 100_000))
    == Some(160_000)
    as "a saved 0 is a full 60,000 ms for the reachable objective"

  // 4182 done, so 4183 is reachable: 0 is its full 600,000 ms and a saved value is its
  // time left. With 4182 not done, 4183 is not reachable and a 0 starts nothing.
  let reachable =
    quest_support.with_objective_time(
      gated_timer,
      progress: [1, 0],
      done_mask: 0b1,
      objective_ms_left: [0, 0],
    )
  assert quest_log.next_deadline(log: logged_in(rows: [reachable], at: 100_000))
    == Some(700_000)
    as "a reachable timed objective saved with 0 gets its full time"
  let saved_left =
    quest_support.with_objective_time(
      gated_timer,
      progress: [1, 0],
      done_mask: 0b1,
      objective_ms_left: [0, 123_000],
    )
  assert quest_log.next_deadline(log: logged_in(rows: [saved_left], at: 100_000))
    == Some(223_000)
    as "a saved time left wins over a full timer"
  let gated =
    quest_support.with_objective_time(
      gated_timer,
      progress: [0, 0],
      done_mask: 0,
      objective_ms_left: [0, 0],
    )
  assert quest_log.next_deadline(log: logged_in(rows: [gated], at: 100_000))
    == None
    as "an objective that is not reachable starts no timer at login"
}

pub fn the_deadline_timer_follows_the_earliest_objective_deadline_test() -> Nil {
  use <- owned_test.run(60_000)
  let tables = character_tables.shared()
  // 2923 runs for 31,000 ms (3686) before its quest's 121,000 ms. A kill of Creature2
  // 5006 finishes 3686 at 10,000 ms: the earliest deadline moves to the quest's, and
  // the running timer is cancelled before it starts again, since starting a running
  // timer ends the connection.
  let log =
    accepted(log: nothing(), quest_id: chain, max_time_ms: 120_000, at: 1000)
  let advanced =
    objective.advance(log:, tables:, event: killed_5006(), now_ms: 10_000)
  assert quest_log.deadline_moved(
      before: quest_log.next_deadline(log:),
      after: quest_log.next_deadline(log: advanced.log),
      now_ms: 10_000,
    )
    == [
      quest_log.CancelDeadlineTimer,
      quest_log.StartDeadlineTimer(after_ms: 111_000),
    ]
    as "the timer for 31,000 ms is cancelled and starts for the quest's 121,000 ms"

  // 4182 done at 5000 ms starts 4183's 600,000 ms with no timer running: it starts
  // and nothing is cancelled.
  let log =
    accepted(log: nothing(), quest_id: gated_timer, max_time_ms: 0, at: 1000)
  let done =
    progressed(log:, quest_id: gated_timer, index: 0, amount: 1, at: 5000)
  assert quest_log.deadline_moved(
      before: quest_log.next_deadline(log:),
      after: quest_log.next_deadline(log: done),
      now_ms: 5000,
    )
    == [quest_log.StartDeadlineTimer(after_ms: 600_000)]
    as "a first timed deadline starts the timer and cancels nothing"

  // The only objective of 2911 done: the quest is Achieved, which no longer runs out.
  let log =
    accepted(log: nothing(), quest_id: one_kill, max_time_ms: 0, at: 1000)
  let advanced =
    objective.advance(log:, tables:, event: killed_5006(), now_ms: 20_000)
  assert quest_log.deadline_moved(
      before: quest_log.next_deadline(log:),
      after: quest_log.next_deadline(log: advanced.log),
      now_ms: 20_000,
    )
    == [quest_log.CancelDeadlineTimer]
    as "no deadline is left, so the timer is cancelled and not started"
}
