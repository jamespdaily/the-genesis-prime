//// The live session's Sessions recording, replayed through the sessions rule
//// with no process. Expected values come from these places.
//// - The recording (`test/rule_recording/2026-10-28-player-path`): the real
////   client's claim, the end of its connection's watch and the server's
////   stop, closed with `End`, which counts 4 inputs.
//// - Sessions reads no game table, so the replay needs no tables, whatever
////   digest the header holds.
//// - The rule's types as the code stands (`rule_types.digest`): a recording
////   made under other types refuses to replay.
//// - The recording's layout and replay in `genesis_prime/rule_recording`:
////   every recorded step must be the step the rule gives again.

import genesis_prime/sessions
import owned_test
import rule_replay_support

pub fn the_live_sessions_sessions_recording_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(inputs, count) = replayed()
  assert inputs == count as "the replay folds every input the End counts"
  assert count == 4 as "Sessions took 4 inputs in the live session"
}

const sessions_replay = #(
  "sessions_replay_test",
  "the_live_sessions_sessions_recording_replays_to_the_same_steps_test",
)

/// The recording replays in a fresh node, where nothing has loaded the
/// modules whose names its terms hold: the reader must not depend on what ran
/// before it.
pub fn the_sessions_recording_replays_in_a_fresh_node_test() -> Nil {
  use <- owned_test.run(60_000)
  rule_replay_support.replays_in_a_fresh_node(sessions_replay)
}

fn replayed() -> #(Int, Int) {
  rule_replay_support.replayed(
    file: "genesis_prime.sessions-2.recording",
    module: sessions.rule_name,
    reads_tables: False,
    new: sessions.new,
    step: sessions.step,
  )
}
