//// A command a test runs to the end, with its output: the planted codec test
//// builds and runs a scratch Gleam project with `gleam`.

/// What an executable that ran to its end gave.
pub type Ran {
  Ran(exit_status: Int, output: String)
}

/// Why an executable did not run to its end.
pub type NotRun {
  /// No such executable is on the PATH.
  ExecutableNotFound
  /// It was still running after the time given.
  TimedOut
}

/// Runs `executable` with `arguments` in `directory`, and waits at most
/// `timeout_ms` milliseconds for it to end. Its output holds what it wrote to
/// both standard output and standard error.
@external(erlang, "command_ffi", "run")
pub fn run(
  executable executable: String,
  arguments arguments: List(String),
  directory directory: String,
  timeout_ms timeout_ms: Int,
) -> Result(Ran, NotRun)
