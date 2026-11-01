//// What the tests of a recorder share: a folder of its own under `build/`, the
//// rule recording read back from it, and a recorder of a rule that writes into
//// it.

import genesis_prime/rule_recording/file
import genesis_prime/rule_types
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/option.{type Option, None}
import gleam/string
import simplifile

/// A new folder under `build/` that no other test uses, made empty.
pub fn new_folder() -> String {
  let folder =
    "build/test_folder/"
    <> string.lowercase(bit_array.base16_encode(crypto.strong_random_bytes(8)))
  let assert Ok(Nil) = simplifile.create_directory_all(folder)
    as "the test's folder was not made"
  folder
}

/// Runs `body` with a new folder under `build/`, and removes the folder after.
/// A test that fails an assertion ends its process before the removal, so a
/// guardian process that monitors the caller removes the folder when the
/// caller ends for any reason. What can remain is a folder of a test whose node
/// was killed, with the guardian, and a `gleam` or other operating system
/// process the test started, which goes on writing into it.
pub fn in_folder(body: fn(String) -> a) -> a {
  let folder = new_folder()
  remove_when_owner_ends(folder)
  let result = body(folder)
  let assert Ok(Nil) = simplifile.delete(folder) as "the folder was removed"
  result
}

/// Starts the guardian that removes `folder` once the calling process has
/// ended. A folder already removed is no error: the caller removes it itself
/// when its body finishes.
fn remove_when_owner_ends(folder: String) -> Nil {
  let owner = process.self()
  let _guardian =
    process.spawn_unlinked(fn() {
      let _down =
        process.new_selector()
        |> process.select_specific_monitor(process.monitor(owner), fn(down) {
          down
        })
        |> process.selector_receive_forever
      let _removed = simplifile.delete(folder)
      Nil
    })
  Nil
}

/// The bytes of the one rule recording in the folder.
pub fn recording_in(folder: String) -> BitArray {
  let assert Ok([name]) = simplifile.read_directory(folder)
    as "one recording in the folder"
  let assert Ok(bytes) = simplifile.read_bits(folder <> "/" <> name)
    as "the recording reads"
  bytes
}

/// The digest of the types of the rule in `rule_module`, as the code stands.
pub fn types_digest(rule_module: String) -> String {
  let assert Ok(digest) =
    rule_types.digest(rule_module:, source_roots: ["src", "test"])
    as "the rule's types digest"
  digest
}

/// A recorder of the rule in `rule_module` that writes into `folder`, on the
/// client build the tests are made for and with no table digest.
pub fn recorder(
  folder folder: String,
  rule_module rule_module: String,
) -> file.Recorder {
  recorder_of_tables(folder:, rule_module:, tables_digest: None)
}

/// A recorder as `recorder` makes, whose header holds the digest of the game
/// tables the rule reads.
pub fn recorder_of_tables(
  folder folder: String,
  rule_module rule_module: String,
  tables_digest tables_digest: Option(String),
) -> file.Recorder {
  file.recorder(
    folder:,
    client_build: 16_042,
    tables_digest:,
    types_digest: types_digest(rule_module),
  )
}
