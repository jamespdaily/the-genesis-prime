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

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/step.{type Now}
import genesis_prime/store.{type QuestRow}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/game_number.{type GameNumbers}
import gleam/dict.{type Dict}
import gleam/int

/// The quests a character has a record of, by Quest2 id, and the reset time the
/// client was last told (the Unix seconds, 0 before the log is sent).
pub type QuestLog {
  QuestLog(entries: Dict(Int, Entry), told_reset: Int)
}

/// What the character has of one quest.
pub type Entry {
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
pub type ActiveState {
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
  Refused(quest_id: Int, reason: String)
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

/// A character with no record of any quest.
pub fn empty() -> QuestLog {
  QuestLog(entries: dict.new(), told_reset: 0)
}

/// The log of the saved rows, or the first quest the client would refuse.
pub fn from_rows(
  rows rows: List(QuestRow),
  tables _tables: table_store.Tables,
) -> Result(QuestLog, Refused) {
  case rows {
    [] -> Ok(empty())
    [_, ..] ->
      panic as "not built: each row is checked against the Quest2 and QuestObjective rows (opcode.0x35f.unknown_quest, opcode.0x35f.active_state_crash, 0x1405fbdc0) and becomes an entry"
  }
}

/// What a refusal says, for the fault the connection logs.
pub fn describe(refused refused: Refused) -> String {
  "quest " <> int.to_string(refused.quest_id) <> ": " <> refused.reason
}

/// The rows the log is saved as, in quest id order.
pub fn rows(log log: QuestLog) -> List(QuestRow) {
  case dict.is_empty(log.entries) {
    True -> []
    False ->
      panic as "not built: each entry becomes a QuestRow, a completed one with its time and an active one with its columns"
  }
}

/// The log as the client is sent it at a play entry, and the log that remembers the
/// reset time the message carried.
pub fn login(
  log _log: QuestLog,
  numbers _numbers: GameNumbers,
  tables _tables: table_store.Tables,
  now _now: Now,
) -> #(QuestLog, Frame) {
  panic as "not built: 0x35F with the completed, known and active lists in quest id order, the period bit of each periodic completed quest and the latest reset in Unix seconds"
}

/// The milliseconds from `now` to the next daily reset, which the timer the play
/// entry starts waits for.
pub fn next_reset_in(numbers _numbers: GameNumbers, now _now: Now) -> Int {
  panic as "not built: the time to the next daily reset after now, from daily_quest_reset_ms"
}

/// What the reset timer firing at `now` leads to.
pub fn reset_due(
  log _log: QuestLog,
  numbers _numbers: GameNumbers,
  now _now: Now,
) -> ResetDue {
  panic as "not built: NotYet when no reset instant lies between the time told and now, else 0x362 with the latest reset and the bit of every period that reset since"
}
