//// The live session's login recordings, replayed through the two login rules
//// with no socket, process or database. Expected values come from these
//// places.
//// - The recordings: a live login of the real client through both servers to
////   the game port, with a create after it (`test/rule_recording/2026-10-28-create`),
////   each closed with `End`, which counts 28 inputs for the STS connection and
////   5 for the auth connection.
//// - The game tables: each header holds the digest of the table files the
////   server loaded, which the replay checks against the client's tables, so
////   these tests are skipped where `GENESIS_NO_CLIENT=1`.
//// - The rule's types as the code stands (`rule_types.digest`): a recording
////   made under other types refuses to replay.
//// - The recording's layout and replay in `genesis_prime/rule_recording`:
////   every recorded step must be the step the rule gives again.

import client_tables
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import owned_test
import rule_replay_support
import unitest

pub fn the_live_sessions_sts_recording_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(inputs, count) =
    rule_replay_support.replayed(
      file: "genesis_prime.login.sts_connection-2.recording",
      module: sts_connection.rule_name,
      new: sts_connection.new,
      step: sts_connection.step,
    )
  assert inputs == count as "the replay folds every input the End counts"
  assert count == 28 as "the live session's STS connection took 28 inputs"
}

pub fn the_live_sessions_auth_recording_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  let #(inputs, count) =
    rule_replay_support.replayed(
      file: "genesis_prime.login.auth_connection-3.recording",
      module: auth_connection.rule_name,
      new: auth_connection.new,
      step: auth_connection.step,
    )
  assert inputs == count as "the replay folds every input the End counts"
  assert count == 5 as "the live session's auth connection took 5 inputs"
}

const sts_replay = #(
  "login_replay_test",
  "the_live_sessions_sts_recording_replays_to_the_same_steps_test",
)

/// The recording replays in a fresh node, where nothing has loaded the
/// modules whose names its terms hold: the reader must not depend on what ran
/// before it.
pub fn the_sts_recording_replays_in_a_fresh_node_test() -> Nil {
  use <- owned_test.run(60_000)
  use <- unitest.guard(client_tables.present())
  rule_replay_support.replays_in_a_fresh_node(sts_replay)
}
