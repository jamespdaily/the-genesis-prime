//// The live session's two game recordings, replayed through the game rule with
//// no socket, process or database. Expected values come from these places.
//// - The recordings (`test/rule_recording/2026-10-28-world-entry`): the real
////   client's connection that played a level-3 Veteran character into the
////   world and moved it (`veteran`), and a later connection of the same
////   client that created a Novice character and played it into the world
////   (`novice`). Each closed with `End`, which counts 1500 inputs for the
////   first and 910 for the second.
//// - The game tables: the header's digest of the table files the server
////   loaded; a replay on other files fails with "record again". The replay
////   reads the client's tables, so it is skipped where `GENESIS_NO_CLIENT=1`.
//// - The rule's types as the code stands (`rule_types.digest`): a recording
////   made under other types refuses to replay.
//// - The recording's layout and replay in `genesis_prime/rule_recording`:
////   every recorded step must be the step the rule gives again.

import client_tables
import genesis_prime/game/connection as game_connection
import owned_test
import rule_replay_support
import unitest

pub fn the_veteran_entrys_game_recording_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(inputs, count) =
    replayed(file: "genesis_prime.game.connection-5.recording")
  assert inputs == count as "the replay folds every input the End counts"
  assert count == 1500 as "the Veteran entry's connection took 1500 inputs"
}

pub fn the_novice_entrys_game_recording_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(inputs, count) =
    replayed(file: "genesis_prime.game.connection-19.recording")
  assert inputs == count as "the replay folds every input the End counts"
  assert count == 910 as "the Novice entry's connection took 910 inputs"
}

fn replayed(file file: String) -> #(Int, Int) {
  rule_replay_support.replayed(
    file:,
    module: game_connection.rule_name,
    reads_tables: True,
    new: game_connection.new,
    step: game_connection.step,
  )
}

const game_replay = #(
  "game_replay_test",
  "the_veteran_entrys_game_recording_replays_to_the_same_steps_test",
)

/// The recording replays in a fresh node, where nothing has loaded the
/// modules whose names its terms hold: the reader must not depend on what ran
/// before it.
pub fn the_game_recording_replays_in_a_fresh_node_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  rule_replay_support.replays_in_a_fresh_node(game_replay)
}
