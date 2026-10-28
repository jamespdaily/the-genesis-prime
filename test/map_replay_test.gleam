//// The live session's map recordings, replayed through the map rule with no
//// process. Expected values come from these places.
//// - The recordings (the folder of `rule_replay_support`): one file for each
////   run of a map the live session held, named by its world, instance and
////   incarnation, each closed with `End`, which counts its inputs.
//// - The map reads no game table, so a replay needs no tables, whatever digest
////   the header holds.
//// - The rule's types as the code stands (`rule_types.digest`): a recording
////   made under other types refuses to replay.
//// - The recording's layout and replay in `genesis_prime/rule_recording`:
////   every recorded step must be the step the rule gives again.

import genesis_prime/world_map/map
import gleam/list
import owned_test
import rule_replay_support

pub fn every_map_run_the_live_session_recorded_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  list.each(rule_replay_support.recordings_of(module: map.rule_name), fn(file) {
    let #(inputs, count) = replayed(file:)
    assert inputs == count
      as { file <> ": the replay folds every input the End counts" }
  })
}

fn replayed(file file: String) -> #(Int, Int) {
  rule_replay_support.replayed(
    file:,
    module: map.rule_name,
    reads_tables: False,
    new: map.new,
    step: map.step,
  )
}

const map_replay = #(
  "map_replay_test",
  "every_map_run_the_live_session_recorded_replays_to_the_same_steps_test",
)

/// The recordings replay in a fresh node, where nothing has loaded the modules
/// whose names their terms hold: the reader must not depend on what ran before
/// it.
pub fn the_map_recordings_replay_in_a_fresh_node_test() -> Nil {
  use <- owned_test.run(60_000)
  rule_replay_support.replays_in_a_fresh_node(map_replay)
}
