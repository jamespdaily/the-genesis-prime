//// The live session's recordings, replayed through the two login rules with
//// no socket, process or database. Expected values come from these places.
//// - The recordings: a live login of the real client through both servers to
////   the game port (`test/rule_recording/2026-10-27-login-rule`), each closed with
////   `End`, which counts 12 inputs for the STS connection and 153 for the
////   auth connection.
//// - The rule's types as the code stands (`rule_types.digest`): a recording
////   made under other types refuses to replay.
//// - The recording's layout and replay in `genesis_prime/rule_recording`:
////   every recorded step must be the step the rule gives again.

import genesis_prime/login.{type Answer, type Request}
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/rule_recording.{End, Header}
import genesis_prime/rule_types
import genesis_prime/step.{type Input, type Step, Rule}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/atom.{type Atom}
import gleam/list
import owned_test
import simplifile

const folder = "test/rule_recording/2026-10-27-login-rule/"

/// The modules whose record tags and constructors a recording holds as atoms.
/// A recording is read with `binary_to_term` and `[safe]`, which refuses an
/// atom the node does not know yet, and a module's atoms are known once it is
/// loaded; so the replay loads them first, whatever test ran before.
const modules_of_the_recorded_terms = [
  // Builds the settings a recording's header holds.
  "genesis_prime",
  "genesis_prime@step",
  "genesis_prime@rule_recording",
  "genesis_prime@login",
  "genesis_prime@hand_off",
  "genesis_prime@store",
  "genesis_prime@login@guid",
  "genesis_prime@connection@frame",
  "genesis_prime@message@bit_stream",
  "genesis_prime@login@sts_connection",
  "genesis_prime@login@auth_connection",
]

@external(erlang, "code", "ensure_loaded")
fn ensure_loaded(module: Atom) -> Dynamic

/// Replays the recording through the rule, whose settings are the ones its
/// header holds, and gives the inputs replayed and the inputs `End` counts.
fn replayed(
  file file: String,
  module module: String,
  new new: fn(settings) -> state,
  step step: fn(state, Input(Nil, Answer)) -> #(state, Step(Nil, Request)),
) -> #(Int, Int) {
  list.each(modules_of_the_recorded_terms, fn(name) {
    // OTP answers {module, Name} for a module that is loaded.
    let assert Ok(loaded) =
      decode.run(
        ensure_loaded(atom.create(name)),
        decode.at([0], atom.decoder()),
      )
      as { "the module " <> name <> " loads" }
    assert loaded == atom.create("module")
      as { "the module " <> name <> " loads" }
  })
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

pub fn the_live_sessions_sts_recording_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(inputs, count) =
    replayed(
      file: "genesis_prime.login.sts_connection-6.recording",
      module: sts_connection.rule_name,
      new: sts_connection.new,
      step: sts_connection.step,
    )
  assert inputs == count as "the replay folds every input the End counts"
  assert count == 12 as "the live session's STS connection took 12 inputs"
}

pub fn the_live_sessions_auth_recording_replays_to_the_same_steps_test() -> Nil {
  use <- owned_test.run(60_000)
  let #(inputs, count) =
    replayed(
      file: "genesis_prime.login.auth_connection-7.recording",
      module: auth_connection.rule_name,
      new: auth_connection.new,
      step: auth_connection.step,
    )
  assert inputs == count as "the replay folds every input the End counts"
  assert count == 153 as "the live session's auth connection took 153 inputs"
}
