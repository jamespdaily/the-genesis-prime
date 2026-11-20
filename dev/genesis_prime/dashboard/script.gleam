//// Runs a script to its end under a deadline, as the dashboard's pollers and
//// controls do. The script's standard error is merged into its output (an
//// Erlang port has no separate stream), so a caller reads one stream and
//// tolerates lines it does not know.
////
//// ```text
//// caller ──run_with(path, arguments, environment, deadline)──► OS process (a port)
////        ◄── Finished(output, status) ─────────  ends by itself
////        ◄── DeadlineReached ──────────────────  ended by SIGTERM, then SIGKILL
//// ```
////
//// - The script is executed as the file it is (its own interpreter line), so
////   a file that is missing or not executable is refused before anything runs.
//// - The arguments are handed to the program whole, one each, with no shell
////   between: a space, a quote or a leading dash in one stays in it.
//// - The deadline ends the script's own process; a program the script started
////   is the script's to end.

/// What a script printed and the status it ended with.
pub type Finished {
  Finished(output: BitArray, status: Int)
}

/// Why a script gave no output and status.
pub type Failure {
  NotFound(path: String)
  NotExecutable(path: String)
  NotStarted(path: String, reason: String)
  DeadlineReached(deadline_ms: Int)
}

/// Runs the script at `path` with `environment` added to this program's, and
/// waits for it to end or for `deadline_ms` milliseconds to pass. A script
/// still running at the deadline is ended and gone when this returns.
pub fn run(
  path path: String,
  environment environment: List(#(String, String)),
  deadline_ms deadline_ms: Int,
) -> Result(Finished, Failure) {
  run_with(path:, arguments: [], environment:, deadline_ms:)
}

/// Runs the program at `path` with these arguments, each one argument of the
/// program, under `run`'s rules for the environment, the deadline and the
/// output.
@external(erlang, "dashboard_script_ffi", "run")
pub fn run_with(
  path path: String,
  arguments arguments: List(String),
  environment environment: List(#(String, String)),
  deadline_ms deadline_ms: Int,
) -> Result(Finished, Failure)

/// The path of the executable called `name` on this program's search path, as a
/// shell would find it; a program is run by its path, so a name is looked up
/// first.
@external(erlang, "dashboard_script_ffi", "find_on_path")
pub fn find_on_path(name name: String) -> Result(String, Nil)
