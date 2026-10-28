//// The live session's game recording, replayed through the game rule with no
//// socket, process or database. Expected values come from these places.
//// - The recording: a live login of the real client to the game server, with
////   one character on the account
////   (`test/rule_recording/2026-10-27-character-list`), closed with `End`,
////   which counts 116 inputs.
//// - The rule's types as the code stands (`rule_types.digest`): a recording
////   made under other types refuses to replay.
//// - The recording's layout and replay in `genesis_prime/rule_recording`:
////   every recorded step must be the step the rule gives again.

import fresh_node
import genesis_prime/game/connection as game_connection
import owned_test
import rule_replay_support

pub fn the_live_sessions_game_recording_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(inputs, count) =
    rule_replay_support.replayed(
      file: "genesis_prime.game.connection-4.recording",
      module: game_connection.rule_name,
      new: game_connection.new,
      step: game_connection.step,
    )
  assert inputs == count as "the replay folds every input the End counts"
  assert count == 116 as "the live session's game connection took 116 inputs"
}

/// The recording replays in a fresh node, where nothing has loaded the
/// modules whose names its terms hold: the reader must not depend on what ran
/// before it.
pub fn the_game_recording_replays_in_a_fresh_node_test() -> Nil {
  use <- owned_test.run(60_000)
  assert fresh_node.run(
      module: "game_replay_test",
      function: "the_live_sessions_game_recording_replays_to_the_same_steps_test",
      timeout_ms: 50_000,
    )
    == Ok(Nil)
    as "the game recording replays with nothing loaded before it"
}
