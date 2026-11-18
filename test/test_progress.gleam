//// The list of the tests a run has started and not ended, which ./check reads when it
//// stops a hung run to name the tests that were still running (the `check` script's
//// `running_tests`).
////
//// ```
//// owned_test.run ──started──▶ file: start ID SECONDS module:function
////                ──ended────▶ file: end ID
//// ./check, on a hang: the start lines with no end line are the tests still running
//// ```
////
//// A line is appended with one write, so the tests of one VM, and the runs of one
//// part, share the file. A test that crashes or fails still ends: `owned_test.run`
//// writes the end line after the body's process is gone, whatever ended it.

/// Appends the start line of the test `name` (`module:function`) to `file` and gives
/// the id its end line carries.
@external(erlang, "test_progress_ffi", "started")
pub fn started(into file: String, test_name name: String) -> String

/// Appends the end line of the test that `started` gave `id`.
@external(erlang, "test_progress_ffi", "ended")
pub fn ended(into file: String, id id: String) -> Nil
