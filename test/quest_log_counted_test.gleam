//// The quest log's rule for an objective whose progress the server counts from
//// what the player holds or where the player stands (`quest_log.counted`).
//// Expected values come from these places.
//// - `0x1406115a0` and `QuestObjective.type.4.progress`: the client counts nothing for
////   a collect objective and stores the value of the server's 0x361; the objective is
////   done when that value reaches the QuestObjective count (`0x140551840`), which is
////   the needed count for every type but the percent kinds. The server caps what it
////   stores at the count.
//// - `0x1405fb830` and `0x1405fbdc0`: a quest whose every objective without flag
////   0x20 is done is Achieved (state 2) and one with an objective not done is Accepted
////   (state 1); a lower 0x361 value clears the done bit (`0x1406115a0`), so an Achieved
////   quest becomes Accepted again.
////
//// The quests, from the client's rows in the fixture:
//// - 1854: one type 4 objective (1959), count 3.
//// - 2347: three objectives (2709, 2710, 2711), count 1 each.
//// - 3297: objective 0 is 7943 (flags 0x28, count 4), objective 1 is 4299 (flags
////   18, count 1).

import character_tables
import genesis_prime/game/quest_log.{type QuestLog}
import genesis_prime/store.{type QuestRow}
import gleam/list
import gleam/option.{Some}
import owned_test
import quest_support

const collect_three = 1854

const three_singles = 2347

const skipped_first = 3297

fn quest(id id: Int) -> quest_log.Quest {
  let assert Ok(quest) =
    quest_log.quest_of(tables: character_tables.shared(), id:)
    as "the fixture holds the quest's rows"
  quest
}

fn saved(log log: QuestLog, quest_id quest_id: Int) -> QuestRow {
  let assert Ok(row) =
    quest_log.rows(log:, now_ms: 0)
    |> list.find(fn(row) { row.quest_id == quest_id })
    as "the log holds the quest"
  row
}

fn done_mask_of(log log: QuestLog, quest_id quest_id: Int) -> Int {
  let assert Some(active) = saved(log:, quest_id:).active
    as "the quest is in the active list"
  active.done_mask
}

fn progress_of(log log: QuestLog, quest_id quest_id: Int) -> List(Int) {
  let assert Some(active) = saved(log:, quest_id:).active
    as "the quest is in the active list"
  active.progress
}

fn counted(
  log log: QuestLog,
  quest_id quest_id: Int,
  index index: Int,
  value value: Int,
) -> quest_log.Counted {
  let assert Ok(counted) =
    quest_log.counted(
      log:,
      quest: quest(id: quest_id),
      index:,
      value:,
      now_ms: 0,
    )
    as "a quest in the active list takes a count"
  counted
}

pub fn counted_sets_progress_capped_at_needed_and_the_done_bit_test() -> Nil {
  use <- owned_test.run(60_000)
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: collect_three, progress: [0]),
    ])

  let below = counted(log:, quest_id: collect_three, index: 0, value: 2)
  assert below.progress == 2 as "two held of three is stored as two"
  assert below.changed as "and it is a change from 0"
  assert progress_of(log: below.log, quest_id: collect_three) == [2]
    as "the saved progress is the count"
  assert done_mask_of(log: below.log, quest_id: collect_three) == 0
    as "two of three is not done (0x1406115a0)"
  assert below.moved == quest_log.Stayed as "the quest stays Accepted"

  let at = counted(log:, quest_id: collect_three, index: 0, value: 3)
  assert at.progress == 3 as "three held of three is stored as three"
  assert done_mask_of(log: at.log, quest_id: collect_three) == 0b1
    as "the done bit is set at the needed count (0x1406115a0)"
  assert at.moved == quest_log.BecameAchieved
    as "the only objective done makes the quest Achieved (0x1405fbdc0)"

  let above = counted(log:, quest_id: collect_three, index: 0, value: 7)
  assert above.progress == 3 as "seven held is stored as the count, three"
  assert progress_of(log: above.log, quest_id: collect_three) == [3]
    as "the saved progress is capped at the count"
  assert done_mask_of(log: above.log, quest_id: collect_three) == 0b1
    as "and the objective is done"

  let again = counted(log: at.log, quest_id: collect_three, index: 0, value: 9)
  assert !again.changed as "a value that stores the same progress is no change"
  assert again.moved == quest_log.Stayed
    as "and an Achieved quest is not made Achieved again"

  // The quest with three objectives is Achieved only by its last needed one.
  let log =
    quest_support.log_of(rows: [
      quest_support.accepted(quest_id: three_singles, progress: [0, 0, 0]),
    ])
  let first = counted(log:, quest_id: three_singles, index: 0, value: 1)
  assert first.moved == quest_log.Stayed
  let second =
    counted(log: first.log, quest_id: three_singles, index: 2, value: 1)
  assert second.moved == quest_log.Stayed
    as "two of three objectives done is not Achieved"
  let third =
    counted(log: second.log, quest_id: three_singles, index: 1, value: 1)
  assert third.moved == quest_log.BecameAchieved
    as "the last needed objective makes the quest Achieved"
  assert done_mask_of(log: third.log, quest_id: three_singles) == 0b111
    as "all three done bits are set"

  // A quest that is not in the active list takes no count.
  assert quest_log.counted(
      log: quest_support.log_of(rows: [
        quest_support.completed(quest_id: collect_three, at: 1),
      ]),
      quest: quest(id: collect_three),
      index: 0,
      value: 3,
      now_ms: 0,
    )
    == Error(Nil)
    as "a completed quest takes none (0x1405510d0)"
  assert quest_log.counted(
      log: quest_support.log_of(rows: []),
      quest: quest(id: collect_three),
      index: 0,
      value: 3,
      now_ms: 0,
    )
    == Error(Nil)
    as "a quest not in the log takes none"
}

pub fn counted_below_needed_undoes_the_objective_and_the_achieved_quest_test() -> Nil {
  use <- owned_test.run(60_000)
  let achieved =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: collect_three,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b1,
        progress: [3],
      ),
    ])

  // The held count above the needed one: losing an item leaves it done.
  let still =
    counted(log: achieved, quest_id: collect_three, index: 0, value: 4)
  assert still.progress == 3 as "four held is stored as three, as before"
  assert !still.changed as "so losing the fifth item is no change"
  assert still.moved == quest_log.Stayed
    as "and the quest stays Achieved (0x1406115a0: done at the count)"

  let below =
    counted(log: achieved, quest_id: collect_three, index: 0, value: 2)
  assert below.progress == 2 as "two held is stored as two"
  assert below.changed as "a change from three"
  assert done_mask_of(log: below.log, quest_id: collect_three) == 0
    as "the done bit is cleared (0x1406115a0)"
  assert below.moved == quest_log.BecameAccepted
    as "and the Achieved quest returns to Accepted (0x1405fb830)"
  assert quest_log.state(log: below.log, quest: quest(id: collect_three)) == 1
    as "the log reads the quest Accepted"

  let none = counted(log: achieved, quest_id: collect_three, index: 0, value: 0)
  assert none.progress == 0 as "none held is stored as none"
  assert progress_of(log: none.log, quest_id: collect_three) == [0]

  // Counting it back up finishes the quest again.
  let back =
    counted(log: below.log, quest_id: collect_three, index: 0, value: 3)
  assert back.moved == quest_log.BecameAchieved
    as "holding the count again makes the quest Achieved again"

  // The objectives with flag 0x20 are skipped when the quest's state is read.
  let skipped =
    quest_support.log_of(rows: [
      quest_support.active(
        quest_id: skipped_first,
        state: 2,
        placeholder: 0,
        tracked: False,
        done_mask: 0b10,
        progress: [0, 1],
      ),
    ])
  let lost = counted(log: skipped, quest_id: skipped_first, index: 1, value: 0)
  assert lost.moved == quest_log.BecameAccepted
    as "losing the one objective without flag 0x20 returns the quest to Accepted"
  let found =
    counted(log: lost.log, quest_id: skipped_first, index: 1, value: 1)
  assert found.moved == quest_log.BecameAchieved
    as "and finding it finishes the quest with objective 0 (flags 0x28) still not done"
  assert done_mask_of(log: found.log, quest_id: skipped_first) == 0b10
    as "only objective 1's bit is set"
}
