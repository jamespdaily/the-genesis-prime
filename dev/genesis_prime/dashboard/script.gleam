//// Runs a script to its end under a deadline, as the dashboard's pollers and
//// controls do. The script's standard error is merged into its output (an
//// Erlang port has no separate stream), so a caller reads one stream and
//// tolerates lines it does not know.
////
//// ```text
//// caller ──run(path, environment, deadline)──► OS process (a port)
////        ◄── Finished(output, status) ─────────  ends by itself
////        ◄── DeadlineReached ──────────────────  ended by SIGTERM, then SIGKILL
//// ```
////
//// - The script is executed as the file it is (its own interpreter line), so
////   a file that is missing or not executable is refused before anything runs.
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
@external(erlang, "dashboard_script_ffi", "run")
pub fn run(
  path path: String,
  environment environment: List(#(String, String)),
  deadline_ms deadline_ms: Int,
) -> Result(Finished, Failure)
