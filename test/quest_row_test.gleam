//// The row of one quest as the character_quest table keeps it
//// (`genesis_prime/store.quest_row`). Expected values come from these places.
//// - `priv/migrations/0021_character_quest.sql:39-50`:
////   `character_quest_state_is_known` (the state is 1 to 7),
////   `character_quest_completed_has_a_time` (`(state = 3) = (completed_at is not
////   null)`) and `character_quest_active_has_its_entry` (the active columns are
////   all set for states 1 and 2 and all null for the others).
//// - `genesis_prime/game/quest_log.entry_of`: the client's lists hold an active
////   quest (states 1, 2), a completed one (3) and a quest known by its state alone
////   (4 to 7).

import genesis_prime/store.{ActiveQuest, QuestRow}
import gleam/list
import gleam/option.{None, Some}
import owned_test

const quest_id = 1857

const completed_at = 1_700_000_000

fn entry() -> store.ActiveQuest {
  ActiveQuest(
    placeholder_objective_id: 0,
    tracked: False,
    done_mask: 0,
    progress: [0],
    quest_ms_left: 0,
    objective_ms_left: [0],
    kill_mask: [0, 0, 0, 0, 0, 0],
    used: [],
  )
}

pub fn a_quest_row_is_built_only_with_the_columns_its_state_holds_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [
      #(
        "state 1 with an entry",
        1,
        None,
        Some(entry()),
        Ok(QuestRow(
          quest_id:,
          state: 1,
          completed_at: None,
          active: Some(entry()),
        )),
      ),
      #(
        "state 2 with an entry",
        2,
        None,
        Some(entry()),
        Ok(QuestRow(
          quest_id:,
          state: 2,
          completed_at: None,
          active: Some(entry()),
        )),
      ),
      #(
        "state 3 with a time",
        3,
        Some(completed_at),
        None,
        Ok(QuestRow(
          quest_id:,
          state: 3,
          completed_at: Some(completed_at),
          active: None,
        )),
      ),
      #(
        "state 4 with none",
        4,
        None,
        None,
        Ok(QuestRow(quest_id:, state: 4, completed_at: None, active: None)),
      ),
      #(
        "state 5 with none",
        5,
        None,
        None,
        Ok(QuestRow(quest_id:, state: 5, completed_at: None, active: None)),
      ),
      #(
        "state 6 with none",
        6,
        None,
        None,
        Ok(QuestRow(quest_id:, state: 6, completed_at: None, active: None)),
      ),
      #(
        "state 7 with none",
        7,
        None,
        None,
        Ok(QuestRow(quest_id:, state: 7, completed_at: None, active: None)),
      ),
      #("state 3 with no time", 3, None, None, Error(Nil)),
      #("state 1 with no entry", 1, None, None, Error(Nil)),
      #("state 4 with a time", 4, Some(completed_at), None, Error(Nil)),
      #("state 1 with a time", 1, Some(completed_at), Some(entry()), Error(Nil)),
      #(
        "state 3 with an entry",
        3,
        Some(completed_at),
        Some(entry()),
        Error(Nil),
      ),
      #("state 8", 8, None, None, Error(Nil)),
      #("state 0", 0, None, None, Error(Nil)),
    ],
    fn(row) {
      let #(reason, state, completed_at, active, expected) = row
      assert store.quest_row(quest_id:, state:, completed_at:, active:)
        == expected
        as reason
    },
  )
}
