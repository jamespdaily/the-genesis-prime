//// Reads what one process, or every process, logs through Erlang's logger, so
//// a test sees the error a process logged before it ended, and the logger's
//// primary level.

import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Pid, type Subject}

/// A running capture; `stop` removes it.
pub type Capture

/// Whose log lines a capture takes.
type Source {
  Process(pid: Pid)
  AllProcesses
}

/// A line's metadata: key and value texts.
type Metadata =
  List(#(String, String))

/// Sends each log line the process `from` writes to `into`, as its level in
/// lower case and its text.
pub fn start(from from: Pid, into into: Subject(#(String, String))) -> Capture {
  start_text(Process(from), into, False)
}

/// Sends each log line the process `from` writes to `into`, as its level in
/// lower case, its text and its metadata as key and value texts.
pub fn start_with_metadata(
  from from: Pid,
  into into: Subject(#(String, String, Metadata)),
) -> Capture {
  start_metadata(Process(from), into, True)
}

/// Sends each log line any process of the node writes to `into`, as its level
/// in lower case, its text and its metadata as key and value texts. Lines of
/// other tests running at the same time are in it too, so a test filters or is
/// `serial`.
pub fn start_all(into into: Subject(#(String, String, Metadata))) -> Capture {
  start_metadata(AllProcesses, into, True)
}

@external(erlang, "log_capture_ffi", "start")
fn start_text(
  source: Source,
  into: Subject(#(String, String)),
  with_metadata: Bool,
) -> Capture

@external(erlang, "log_capture_ffi", "start")
fn start_metadata(
  source: Source,
  into: Subject(#(String, String, Metadata)),
  with_metadata: Bool,
) -> Capture

/// Stops the capture.
@external(erlang, "log_capture_ffi", "stop")
pub fn stop(capture: Capture) -> Nil

/// The logger's primary level: the lowest level it lets through.
@external(erlang, "log_capture_ffi", "primary_level")
pub fn primary_level() -> Atom

/// Sets the logger's primary level, for a test that restores what it found.
@external(erlang, "log_capture_ffi", "set_primary_level")
pub fn set_primary_level(level: Atom) -> Nil

/// How a guardian of the level ended its wait.
type Guarded {
  BodyDone
  OwnerEnded
}

/// Runs `body` with the logger's primary level at `level`, and puts back the
/// level it found however the body ends: when the body returns, and, by a
/// guardian that watches the calling process, when the caller ends first (a
/// failed assertion), so no failed test leaves a level set for the others. The
/// level is the node's, so a test that uses this is `serial`.
pub fn at_level(level level: Atom, body body: fn() -> a) -> a {
  let before = primary_level()
  let owner = process.self()
  let done = process.new_subject()
  let _guardian =
    process.spawn_unlinked(fn() {
      let selector =
        process.new_selector()
        |> process.select_map(done, fn(_done) { BodyDone })
        |> process.select_specific_monitor(process.monitor(owner), fn(_down) {
          OwnerEnded
        })
      case process.selector_receive_forever(selector) {
        OwnerEnded -> set_primary_level(before)
        BodyDone -> Nil
      }
    })
  set_primary_level(level)
  let result = body()
  set_primary_level(before)
  process.send(done, Nil)
  result
}

/// Logs one progress report, as a supervisor does when it starts a child.
@external(erlang, "log_capture_ffi", "log_progress_report")
pub fn log_progress_report() -> Nil

/// Removes the filter the server's start adds against progress reports, for a
/// test that restores what it found.
@external(erlang, "log_capture_ffi", "remove_progress_filter")
pub fn remove_progress_filter() -> Nil

/// Removes the filter the server's start adds against mailboxes in crash
/// reports, for a test that restores what it found.
@external(erlang, "log_capture_ffi", "remove_crash_report_filter")
pub fn remove_crash_report_filter() -> Nil
