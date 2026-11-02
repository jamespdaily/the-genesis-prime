//// What the tests of a recorder share: a folder of its own under `build/`, the
//// wire recording read back from it, and a recorder that writes into it.

import genesis_prime/wire_recording/recorder.{type WireRecorder}
import gleam/bit_array
import gleam/crypto
import gleam/erlang/process
import gleam/option.{None}
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

/// The text of the one wire recording in the folder, whole or cut as the
/// shell left it.
pub fn wire_text_in(folder: String) -> String {
  let assert Ok([name]) = simplifile.read_directory(folder)
    as "one wire recording in the folder"
  let assert Ok(text) = simplifile.read(folder <> "/" <> name)
    as "the wire recording reads"
  text
}

/// A wire recorder that writes into `folder`, on the client build the tests are
/// made for and with no table digest.
pub fn wire_recorder(folder folder: String) -> WireRecorder {
  recorder.new(folder:, client_build: 16_042, tables_digest: None)
}
