//// What the replay tests of the connection rules share: a recording read and
//// replayed through its rule with no socket, process or database.

import fresh_node
import genesis_prime/client_connection.{type Answer, type Request}
import genesis_prime/rule_recording.{End, Header}
import genesis_prime/rule_types
import genesis_prime/step.{type Input, type Step, Rule}
import gleam/list
import simplifile

/// The folder of the live session's recordings: a login of the real client
/// through the STS, auth and game servers, with one character on the account.
pub const folder = "test/rule_recording/2026-10-27-character-list/"

/// Replays the recording `file` of the folder through the rule `module`,
/// whose settings are the ones its header holds, and gives the inputs replayed
/// and the inputs `End` counts. The replay fails unless every recorded step is
/// the step the rule gives again, and unless the recording was made under the
/// rule's types as the code stands (`rule_types.digest`).
pub fn replayed(
  file file: String,
  module module: String,
  new new: fn(settings) -> state,
  step step: fn(state, Input(Nil, Answer)) -> #(state, Step(Nil, Request)),
) -> #(Int, Int) {
  let assert Ok(bytes) = simplifile.read_bits(folder <> file)
    as "the recording reads"
  let assert Ok(#(Header(settings:, ..), records)) = rule_recording.read(bytes)
    as "the recording is a recording"
  let records: List(rule_recording.Record(Nil, Answer, Nil, Request)) = records
  let assert Ok(End(count:)) = list.last(records)
    as "the live session ended each connection, so each recording closes with End"
  let assert Ok(digest) =
    rule_types.digest(rule_module: module, source_roots: ["src", "test"])
    as "the rule's types read"
  let assert Ok(inputs) =
    rule_recording.replay(
      bytes,
      Rule(name: module, settings:, new:, step:),
      digest,
    )
    as "every recorded step is the step the rule gives again"
  #(inputs, count)
}

/// Runs the replay test `function` of the test module `module` in a fresh
/// node, where nothing has loaded the modules whose names the recording's
/// terms hold, and fails unless it passes there.
pub fn replays_in_a_fresh_node(
  module module: String,
  function function: String,
) -> Nil {
  assert fresh_node.run(module:, function:, timeout_ms: 50_000) == Ok(Nil)
    as { function <> " passes in a fresh node, with nothing loaded before it" }
}
