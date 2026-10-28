//// What the replay tests of the connection rules share: a recording read and
//// replayed through its rule with no socket, process or database.

import client_tables
import fresh_node
import genesis_prime/rule_recording.{End, Header}
import genesis_prime/rule_types
import genesis_prime/step.{type Input, type Step, Rule}
import genesis_prime/table/loader/store
import gleam/list
import gleam/option.{Some}
import gleam/string
import simplifile

/// The folder of the live session's recordings: the real client logged in
/// through the STS, auth and game servers and left on the character select
/// screen, then a second login to the same account that took its session over.
pub const folder = "test/rule_recording/2026-10-28-takeover/"

/// The names of the folder's recordings of the rule `module`, in order: the
/// files the recorder named after the rule (`genesis_prime/rule_recording/file`).
/// A map is recorded once for each run, so a live session holds as many
/// recordings of the map rule as maps ran.
pub fn recordings_of(module module: String) -> List(String) {
  let assert Ok(names) = simplifile.read_directory(folder)
    as "the folder of the live session's recordings reads"
  names
  |> list.filter(string.starts_with(_, string.replace(module, "/", ".") <> "-"))
  |> list.sort(string.compare)
}

/// Replays the recording `file` of the folder through the rule `module`,
/// whose settings are the ones its header holds, and gives the inputs replayed
/// and the inputs `End` counts. The replay fails unless every recorded step is
/// the step the rule gives again, and unless the recording was made under the
/// rule's types as the code stands (`rule_types.digest`) and, for a rule that
/// reads the game tables (`reads_tables`), on the table files loaded now: the
/// replay loads the client's tables under the server's key, where the recorded
/// settings name them, and a digest that differs from the header's fails the
/// replay with `RecordAgain`. A rule that reads no table replays without the
/// tables, whatever digest its header holds.
pub fn replayed(
  file file: String,
  module module: String,
  reads_tables reads_tables: Bool,
  new new: fn(settings) -> state,
  step step: fn(state, Input(message, answer)) ->
    #(state, Step(outgoing, request)),
) -> #(Int, Int) {
  let assert Ok(bytes) = simplifile.read_bits(folder <> file)
    as "the recording reads"
  let assert Ok(#(Header(settings:, tables_digest:, ..), records)) =
    rule_recording.read(bytes)
    as "the recording is a recording"
  let loaded_digest = case reads_tables {
    True -> Some(store.digest(client_tables.shared()))
    False -> tables_digest
  }
  let records: List(rule_recording.Record(message, answer, outgoing, request)) =
    records
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
      loaded_digest,
    )
    as "every recorded step is the step the rule gives again, on the rule's types and tables the recording was made on (a RecordAgain means record it again)"
  #(inputs, count)
}

/// Runs the replay test of a test module, given as the module's name and the
/// test function's name, in a fresh node, where nothing has loaded the modules
/// whose names the recording's terms hold, and fails unless it passes there.
pub fn replays_in_a_fresh_node(replay_test: #(String, String)) -> Nil {
  let #(module, function) = replay_test
  assert fresh_node.run(module:, function:, timeout_ms: 50_000) == Ok(Nil)
    as { function <> " passes in a fresh node, with nothing loaded before it" }
}
