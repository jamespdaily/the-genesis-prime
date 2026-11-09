//// The quest log's rules (`genesis_prime/game/quest_log`): which saved quest the
//// client would refuse at a load, and what the log sent at a play entry (0x35F)
//// carries for a periodic quest. Expected values come from these places.
//// - `opcode.0x35f.unknown_quest`: the client answers a quest id it has no Quest2
////   row for with the Client/Server Data Mismatch disconnect.
//// - `opcode.0x35f.active_state_crash` and 0x1405fbdc0 (the client's quest state
////   setter): the active list holds a quest's progress for its objectives, and a
////   placeholder objective replaces the quest's type 31 objective slot.
//// - `0x1405fb350.completed_bit` and 0x140489aa0: a periodic quest completed in
////   its current period is flagged in the completed list; the period of a quest is
////   its `Quest2.questRepeatPeriodEnum` (`table_rows -- Quest2 1857 9713 9714 9715
////   2347`: 1, 2, 3, 4 and 0 for the one-time quest 2347).
//// - The reset instants are the server's choice (Jim, 2026-11-08): daily at 10:00
////   UTC, weekly on Tuesday at 10:00 UTC, monthly and yearly at the first daily
////   reset of the month and year. The instants below are calendar dates read off a
////   calendar: 2025-04-24 20:26:40 UTC (a Thursday) is the entry time the tests'
////   connections run at (`world_entry_support.filetime`), the daily reset of that
////   day was 2025-04-24 10:00:00 UTC, the weekly one 2025-04-22 10:00:00 UTC (the
////   Tuesday before), the monthly one 2025-04-01 10:00:00 UTC and the yearly one
////   2025-01-01 10:00:00 UTC.

import character_tables
import connection_rule_support as support
import game_connection_support
import genesis_prime/game/quest_log
import genesis_prime/game/world_entry
import genesis_prime/message/quest_completed.{type QuestCompleted}
import genesis_prime/message/quest_log as quest_message
import genesis_prime/step.{LogError, Now}
import genesis_prime/store.{type QuestRow, QuestRow}
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/string
import owned_test
import quest_support
import spawn_support
import world_entry_support

/// The store's answer holding these quest rows, for a play of the tests'
/// character: what the load leads to.
fn loaded_holding(quests quests: List(QuestRow)) -> world_entry.Loaded {
  world_entry_support.loaded_with_quests(
    tables: character_tables.shared(),
    character: game_connection_support.world_character(),
    items: [],
    quests:,
  ).1
}

/// The text of the fault a load of these rows ends in.
fn fault_of(quests quests: List(QuestRow)) -> String {
  let assert world_entry.Fault(text:) = loaded_holding(quests:)
    as "the quest log the client would refuse fails the load"
  text
}

/// What the load of these rows refuses, from the log's own function.
fn refused_by_the_load(quests quests: List(QuestRow)) -> quest_log.Refused {
  let assert Error(refused) =
    quest_log.from_rows(rows: quests, tables: character_tables.shared())
    as "the rows are ones the client would refuse"
  refused
}

pub fn a_saved_entry_the_client_would_refuse_fails_the_load_test() -> Nil {
  use <- owned_test.run(10_000)
  // The same rows, each with one fault of the kind the client's code refuses, and
  // the quest and the kind of fault the load names.
  let refused = [
    #(
      "an id with no Quest2 row (opcode.0x35f.unknown_quest)",
      quest_support.accepted(quest_id: quest_support.no_row, progress: []),
      quest_log.Refused(
        quest_id: quest_support.no_row,
        reason: quest_log.NoQuest2Row,
      ),
    ),
    #(
      "a quest the client has no row for in the second list too",
      quest_support.known(quest_id: quest_support.no_row, state: 6),
      quest_log.Refused(
        quest_id: quest_support.no_row,
        reason: quest_log.NoQuest2Row,
      ),
    ),
    #(
      "two progress values for a quest of one objective (0x1405fbdc0)",
      quest_support.accepted(quest_id: quest_support.daily, progress: [1, 2]),
      quest_log.Refused(
        quest_id: quest_support.daily,
        reason: quest_log.ProgressCountIsNotObjectiveCount(
          progress: 2,
          objectives: 1,
        ),
      ),
    ),
    #(
      "no progress value for a quest of one objective (0x1405fbdc0 counts the objectives the entry holds the progress of)",
      quest_support.accepted(quest_id: quest_support.daily, progress: []),
      quest_log.Refused(
        quest_id: quest_support.daily,
        reason: quest_log.ProgressCountIsNotObjectiveCount(
          progress: 0,
          objectives: 1,
        ),
      ),
    ),
    #(
      "one progress value for a quest of three objectives",
      quest_support.accepted(quest_id: quest_support.one_time, progress: [1]),
      quest_log.Refused(
        quest_id: quest_support.one_time,
        reason: quest_log.ProgressCountIsNotObjectiveCount(
          progress: 1,
          objectives: 3,
        ),
      ),
    ),
    #(
      "one progress value for a quest of two objectives",
      quest_support.accepted(
        quest_id: quest_support.daily_two_objectives,
        progress: [1],
      ),
      quest_log.Refused(
        quest_id: quest_support.daily_two_objectives,
        reason: quest_log.ProgressCountIsNotObjectiveCount(
          progress: 1,
          objectives: 2,
        ),
      ),
    ),
    #(
      "a placeholder that is no QuestObjective row, on a quest with a type 31 slot (0x1405fbdc0)",
      quest_support.active(
        quest_id: quest_support.daily_with_a_placeholder,
        state: 2,
        placeholder: 999_999,
        tracked: False,
        done_mask: 0,
        progress: [0],
      ),
      quest_log.Refused(
        quest_id: quest_support.daily_with_a_placeholder,
        reason: quest_log.NoPlaceholderRow(objective_id: 999_999),
      ),
    ),
    #(
      "a completed state with no completed time",
      QuestRow(
        quest_id: quest_support.daily,
        state: 3,
        completed_at: None,
        active: None,
      ),
      quest_log.Refused(
        quest_id: quest_support.daily,
        reason: quest_log.StateDoesNotGoWithColumns(state: 3),
      ),
    ),
  ]
  list.each(refused, fn(case_) {
    let #(what, row, expected) = case_
    assert refused_by_the_load(quests: [row]) == expected as what
    let text = fault_of(quests: [row])
    assert string.contains(
      text,
      "quest " <> int.to_string(expected.quest_id) <> ":",
    )
      as { what <> ": the fault names the quest, got: " <> text }
  })
  // The quests are also refused after the first, in the order the rows came.
  let text =
    fault_of(quests: [
      quest_support.completed(
        quest_id: quest_support.one_time,
        at: 1_745_488_800,
      ),
      quest_support.accepted(quest_id: quest_support.daily, progress: [1, 2]),
    ])
  assert string.contains(text, "quest 1857:")
    as "a quest the client accepts before it does not hide the one it refuses"
  // The same quests with rows the client accepts load.
  let accepted = [
    quest_support.accepted(quest_id: quest_support.one_time, progress: [4, 0, 9]),
    quest_support.accepted(quest_id: quest_support.daily, progress: [1]),
    quest_support.active(
      quest_id: quest_support.daily_with_a_placeholder,
      state: 2,
      placeholder: quest_support.placeholder_objective,
      tracked: True,
      done_mask: 1,
      progress: [1],
    ),
    quest_support.completed(quest_id: quest_support.weekly, at: 1_745_488_800),
    quest_support.known(quest_id: quest_support.monthly, state: 5),
  ]
  let assert world_entry.Join(..) = loaded_holding(quests: accepted)
    as "rows within the client's quest rows load, so the faults above are the rows', not the test's"
  // The state setter looks a placeholder id up only for a quest that has a type 31
  // slot and puts the row it finds there, whatever its type (0x1405fbdc0), so it
  // refuses neither a placeholder id on a quest with no such slot, which it does
  // not look at, nor a row of another type, which it puts in the slot.
  let placeholder_rows = [
    quest_support.active(
      quest_id: quest_support.daily,
      state: 1,
      placeholder: quest_support.placeholder_objective,
      tracked: False,
      done_mask: 0,
      progress: [0],
    ),
    quest_support.active(
      quest_id: quest_support.daily_with_a_placeholder,
      state: 1,
      placeholder: quest_support.ordinary_objective,
      tracked: False,
      done_mask: 0,
      progress: [0],
    ),
  ]
  let assert world_entry.Join(..) = loaded_holding(quests: placeholder_rows)
    as "a placeholder id the state setter does not refuse loads"
  // And the connection ends for a refused log, writing no 0x35F and no entry.
  let #(_, taken) =
    game_connection_support.joining_with_quests(
      in_character_select: game_connection_support.in_select(),
      character: game_connection_support.world_character(),
      saved_health: None,
      quests: [
        quest_support.accepted(quest_id: quest_support.daily, progress: [1, 2]),
      ],
    )
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "one error line says the saved log is one the client would refuse"
  assert support.says(line, "quest 1857") && support.says(line, "would refuse")
    as "the line names the quest and what the client would do"
  assert support.asked(taken) == None as "no map is asked for the character"
  assert list.all(game_connection_support.written(taken:), fn(frame) {
    frame.message_id != quest_message.message_id
  })
    as "no quest log is sent to the client"
}

/// The completed list a log of these rows sends at the entry time, as pairs of
/// quest id and the period flag, and the reset time, after the log is read from
/// the rows and then sent.
fn completed_flags(
  rows rows: List(QuestRow),
) -> #(List(#(Int, Int)), Int, quest_log.QuestLog) {
  let assert Ok(log) =
    quest_log.from_rows(rows:, tables: character_tables.shared())
    as "the rows are quests the client accepts"
  let #(told, frame) =
    quest_log.login(
      log:,
      numbers: spawn_support.numbers,
      tables: character_tables.shared(),
      now: Now(monotonic_ms: 0, filetime: world_entry_support.filetime),
    )
  assert frame.message_id == quest_message.message_id
    as "the log is sent as 0x35F"
  let assert Ok(message) = quest_message.decode(frame.body)
    as "the frame the log is sent in decodes"
  #(
    list.map(message.completed, fn(entry: QuestCompleted) {
      #(entry.quest_id, entry.in_current_period)
    }),
    message.reset_time,
    told,
  )
}

pub fn the_login_log_marks_a_periodic_quest_done_only_when_completed_in_its_current_period_test() -> Nil {
  use <- owned_test.run(10_000)
  // Completed after the reset of its current period: the flag is set, and a
  // quest completed exactly at the reset instant is in the period that starts there.
  let #(flags, reset_time, told) =
    completed_flags(rows: [
      quest_support.completed(quest_id: quest_support.daily, at: 1_745_488_800),
      quest_support.completed(
        quest_id: quest_support.one_time,
        at: 1_745_496_000,
      ),
      quest_support.completed(
        quest_id: quest_support.daily_two_objectives,
        at: 1_745_488_799,
      ),
      quest_support.completed(quest_id: quest_support.weekly, at: 1_745_409_600),
      quest_support.completed(
        quest_id: quest_support.monthly,
        at: 1_743_588_000,
      ),
      quest_support.completed(quest_id: quest_support.yearly, at: 1_738_368_000),
    ])
  assert flags
    == [
      #(1857, 1),
      #(2347, 0),
      #(3204, 0),
      #(9713, 1),
      #(9714, 1),
      #(9715, 1),
    ]
    as "0x1405fb350.completed_bit: a daily quest done at or after 2025-04-24 10:00 and a weekly one done after 2025-04-22 10:00 carry the bit, one done a second before the daily reset does not, and a one-time quest (Quest2 2347, period 0) never does; a monthly quest done 2025-04-02 and a yearly one done 2025-02-01 are in their periods; all are in the completed list in quest id order"
  assert reset_time == 1_745_488_800
    as "the reset time sent is the latest reset instant, 2025-04-24 10:00:00 UTC, in Unix seconds"
  assert quest_log.told_reset(told) == 1_745_488_800
    as "the log remembers the time the client was told"
  // Completed before the reset of its current period: the flag is clear.
  let #(flags, _, _) =
    completed_flags(rows: [
      quest_support.completed(quest_id: quest_support.weekly, at: 1_745_315_999),
      quest_support.completed(
        quest_id: quest_support.monthly,
        at: 1_743_462_000,
      ),
      quest_support.completed(quest_id: quest_support.yearly, at: 1_735_646_400),
      quest_support.completed(quest_id: quest_support.daily, at: 1_745_402_400),
    ])
  assert flags == [#(1857, 0), #(9713, 0), #(9714, 0), #(9715, 0)]
    as "a weekly quest done a second before 2025-04-22 10:00, a monthly one done 2025-03-31 and a yearly one done 2024-12-31, a daily one done the day before, are each of an earlier period"
}
