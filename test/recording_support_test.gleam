//// The folder a test makes with `recording_support.in_folder` is removed
//// whether the test finishes or fails. The rule is the folder's own doc:
//// a test that fails an assertion ends its process, and a guardian that
//// monitors that process removes the folder.

import gleam/erlang/process
import owned_test
import recording_support
import simplifile

pub fn a_folder_is_removed_when_the_process_that_made_it_ends_in_a_failure_test() -> Nil {
  use <- owned_test.run(30_000)
  let made = process.new_subject()
  let worker =
    process.spawn_unlinked(fn() {
      recording_support.in_folder(fn(folder) {
        process.send(made, folder)
        panic as "the planted failure of a test"
      })
    })
  let ended = process.monitor(worker)
  let assert Ok(folder) = process.receive(made, within: 5000)
    as "the worker made its folder"
  let assert Ok(_down) =
    process.new_selector()
    |> process.select_specific_monitor(ended, fn(down) { down })
    |> process.selector_receive(within: 5000)
    as "the worker ended in its failure"
  assert removed(folder, wait_ms: 5000)
    as "the folder is gone once the process that made it ended"
}

pub fn a_folder_is_removed_when_its_body_finishes_test() -> Nil {
  use <- owned_test.run(30_000)
  let folder = recording_support.in_folder(fn(folder) { folder })
  assert simplifile.is_directory(folder) == Ok(False)
    as "the folder is gone when in_folder returns"
}

/// Whether the folder is gone within `wait_ms`: the guardian removes it after
/// the owner's end, which no message of the test's own announces.
fn removed(folder: String, wait_ms wait_ms: Int) -> Bool {
  case simplifile.is_directory(folder), wait_ms > 0 {
    Ok(False), _ -> True
    _, False -> False
    _, True -> {
      process.sleep(1)
      removed(folder, wait_ms: wait_ms - 1)
    }
  }
}
