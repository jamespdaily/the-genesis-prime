//// The rule that hides a unit whose visibility prerequisite fails
//// (`genesis_prime/game/visibility`). Expected values come from these places:
//// - `Creature2.prerequisiteIdVisibility`: the client never tests the column; it removes a
////   unit only on the server's 0x355 or a 0x262 flag of 128, so the server decides, and a
////   prerequisite that passes, one the server does not read and none (0) show the unit.
//// - `Prerequisite 41803` (`table_rows -- Prerequisite 41803`): flags 1 (OR), type 43
////   comparison 1 on quest 10527 value 3 or on quest 10532 value 3 (objective index 3,
////   open: in the active list, not done, reachable). Quest 10527's objective 3 is
////   QuestObjective 21323 (flags 3: it waits for the earlier objectives without flag 0x20,
////   which are 21321 and 21324 at indexes 0 and 2, so a done mask of 0b101 opens it).

import character_tables
import genesis_prime/game/prerequisite.{type Prerequisite, Subject}
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/game/visibility
import genesis_prime/table/id.{PrerequisiteId}
import gleam/option.{Some}
import gleam/set
import owned_test
import prerequisite_support
import quest_support

/// Prerequisite 41803 as the client's rows give it, with the quests it reads.
fn start_arrow() -> Prerequisite {
  let tables = character_tables.shared()
  let assert Ok(loaded) =
    prerequisite.load(
      id: PrerequisiteId(41_803),
      rows: prerequisite.table_rows(tables:),
      arcs: prerequisite.table_arcs(tables:),
      quests: prerequisite.table_quests(tables:),
    )
    as "the client's rows hold Prerequisite 41803 and the quests it reads"
  loaded
}

/// A player whose quest log is this.
fn player_with(log log: QuestLog) -> prerequisite.Subject {
  Subject(
    ..prerequisite_support.holding(held: [], second_unit: option.None),
    quests: Some(log),
  )
}

pub fn visibility_hides_a_failing_prerequisite_and_shows_a_passing_or_unread_one_test() -> Nil {
  use <- owned_test.run(60_000)
  let arrow = start_arrow()
  let open_objective_3 =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: 10_527,
        state: 1,
        placeholder: 0,
        tracked: False,
        done_mask: 0b101,
        progress: [1, 0, 1, 0, 0],
      ),
    ])
  assert visibility.hidden([arrow], player_with(log: open_objective_3))
    == set.new()
    as "quest 10527 with objective 3 open passes Prerequisite 41803 (type 43 on quest 10527 value 3), so the unit is shown"
  assert visibility.hidden(
      [arrow],
      player_with(log: quest_support.log_of(rows: [])),
    )
    == set.from_list([PrerequisiteId(41_803)])
    as "neither quest in the log fails Prerequisite 41803 (type 43 needs the objective in the active list), so the unit is hidden"
  assert !prerequisite.is_read(type_id: 117)
    as "the condition type 117 is one the server does not read"
  let unread = prerequisite_support.single(id: 7, condition: #(117, 1, 0, 0))
  assert visibility.hidden(
      [unread],
      player_with(log: quest_support.log_of(rows: [])),
    )
    == set.new()
    as "a type-117 condition reads as not read, which does not hide the unit"
}
