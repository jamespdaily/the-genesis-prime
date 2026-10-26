//// The release, built the way it is built for the image: `release/build`
//// exports Gleam's Erlang shipment and adds `release/vm.args` and the start
//// script beside it. The export takes seconds, so it runs once per test run,
//// whichever test asks first, and every test that starts the release uses
//// that one folder.

import database_support
import simplifile

/// The folder of the exported release, made by the first caller and the same
/// for every later one.
pub fn folder() -> String {
  once("shipment", export)
}

/// The script that starts the release in `folder`, which runs the server with
/// the settings in its environment.
pub fn start_script() -> String {
  folder() <> "/start"
}

fn export() -> String {
  let assert Ok(base) = simplifile.current_directory()
    as "the working directory is not readable"
  case run_command(base <> "/release/build", [], []) {
    Ok(_) -> base <> "/build/erlang-shipment"
    Error(database_support.CommandFailed(output:)) ->
      panic as { "release/build did not export the shipment: " <> output }
  }
}

/// Runs `create` once per key in this VM; every caller gets the same value.
@external(erlang, "database_support_ffi", "once")
fn once(key: String, create: fn() -> a) -> a

@external(erlang, "database_support_ffi", "run_command")
fn run_command(
  program: String,
  arguments: List(String),
  environment: List(#(String, String)),
) -> Result(String, database_support.CommandFailed)
