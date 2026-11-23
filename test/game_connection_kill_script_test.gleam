//// A kill script on a running game connection: the kill of a creature of the reward pane of a
//// type 5 objective in the kill table counts for it, as an ordinary kill does, and the client
//// is told. Expected values come from these places.
//// - `opcode.0x361`: quest id (15 bits), objective index (32) and progress (32), written by the
////   widths of the client's reader (`message_support.packed`), not by our codec.
//// - `opcode.0x35c`: quest id (15), state (32) and objective id (32); state 2 is Achieved, and
////   objective id 0 leaves the quest's objectives as they are.
//// - `opcode.0x1ac`: the kill's experience, written before its objective progress.
//// - `QuestObjective.type.5`: nothing the client sends completes a type 5 objective, so a quest
////   whose objective is a kill script sends no 0x361 on accept, and one 0x361 for the kill.
////
//// The client's rows in the fixture (`table_rows -- Quest2 5895`, `QuestObjective 8866 8936`,
//// `TargetGroup 5256`): quest 5895 has objective 8866 (type 5, count 1, flags 0x14, reward pane
//// 5256 = Creature2 26037, the scientist) and 8936 (type 2, Creature2 26042, flags 7, closed
//// until 8866 is done). Creature2 26206 receives the quest.

import experience_support
import game_connection_support as connection_support
import genesis_prime/client_connection.{type Request}
import genesis_prime/game/connection/state as connection_state
import genesis_prime/game/objective
import genesis_prime/step.{type ConnectionStep}
import gleam/list
import gleam/set
import message_support
import owned_test
import quest_support

const the_scientist = 26_037

/// The creature quest 5895's second objective names.
const the_scientist_s_assistant = 26_042

const a_beast = 73_464

fn progress_frame(
  index index: Int,
  progress progress: Int,
) -> #(Int, BitArray) {
  message_support.quest_progress_frame(quest: 5895, index:, progress:)
}

fn state_frame(state state: Int) -> #(Int, BitArray) {
  message_support.quest_state_frame(quest: 5895, state:)
}

/// The ids and bodies the step writes to the client, in order.
fn written(taken taken: ConnectionStep(Request)) -> List(#(Int, BitArray)) {
  connection_support.written_pairs(taken:)
}

/// What the step tells of quests: its 0x361 and 0x35c frames.
fn quest_frames(
  taken taken: ConnectionStep(Request),
) -> List(#(Int, BitArray)) {
  list.filter(written(taken:), fn(frame) {
    frame.0 == 0x0361 || frame.0 == 0x035C
  })
}

/// The tests' settings with these objectives in the kill table.
fn killing(kills kills: List(Int)) -> connection_state.Settings {
  connection_state.Settings(
    ..connection_support.settings(),
    script_rows: objective.ScriptRows(
      ..objective.no_rows(),
      kills: set.from_list(kills),
    ),
  )
}

pub fn a_kill_of_the_scientist_sends_the_type_5_kill_objectives_progress_and_achieved_test() -> Nil {
  use <- owned_test.run(10_000)
  let quest = quest_support.accepted(quest_id: 5895, progress: [0, 0])
  // Without the kill table the objective is a stand-in, done when the quest is accepted, so
  // the scientist's kill finds it done and counts nothing: the rule this step replaces.
  let #(state, _) =
    connection_support.entered_with_quests_in(
      settings: killing(kills: []),
      quests: [quest],
    )
  let #(_, standing_in) =
    experience_support.credited(state:, creature_id: the_scientist, level: 1)
  assert quest_frames(taken: standing_in) == []
    as "a stand-in objective is done at accept, so its kill sends no progress"

  let #(state, entry) =
    connection_support.entered_with_quests_in(
      settings: killing(kills: [8866]),
      quests: [quest],
    )
  assert quest_frames(taken: entry) == []
    as "with objective 8866 in the kill table the entry sends no 0x361: the stand-in no longer completes the kill"

  let #(state, stranger) =
    experience_support.credited(state:, creature_id: a_beast, level: 1)
  assert list.map(written(taken: stranger), fn(frame) { frame.0 }) == [0x01AC]
    as "the kill of a creature outside the pane tells the experience and nothing of the objective, and the settle after it completes nothing"

  let #(state, killed) =
    experience_support.credited(state:, creature_id: the_scientist, level: 1)
  assert list.map(written(taken: killed), fn(frame) { frame.0 })
    == [0x01AC, 0x0361]
    as "the experience is written first, then the objective's progress: objective 8936 still waits, so the quest is not Achieved"
  assert quest_frames(taken: killed) == [progress_frame(index: 0, progress: 1)]
    as "opcode.0x361: objective 0 (8866) is at 1 of 1"

  let #(_, finished) =
    experience_support.credited(
      state:,
      creature_id: the_scientist_s_assistant,
      level: 1,
    )
  assert quest_frames(taken: finished)
    == [progress_frame(index: 1, progress: 1), state_frame(state: 2)]
    as "opcode.0x361 and opcode.0x35c: the second objective, a type 2 kill, is done and the quest is Achieved"
}
