//// Starts the whole server as `genesis_prime.main` does, with the same
//// environment settings, but with every draw of random bytes written down with
//// the connection that made it, and the account rows its logins used, into a
//// session folder, so a session recorded through the relay
//// (`genesis_prime/record`, given the same folder) can be played again:
////
//// `gleam run -m genesis_prime/recording_server -- <session folder>`
////
//// - `session folder`: made when it is missing; by convention
////   `test/recording/<date>-<flow>`, the folder the relays write to.
////
//// The draws are strong random bytes, as the released server's are; only a
//// copy is kept. The released server has no way to take a source of its own:
//// its settings use the strong source, and the code rules refuse building a
//// supplied source anywhere in `src/` but where it is defined.
////
//// The draw log is one process under a supervisor of its own that this program
//// links to. A restart of the log keeps what is in the folder.

import argv
import envoy
import genesis_prime
import genesis_prime/recording/draw_log
import gleam/erlang/process
import gleam/io
import gleam/otp/static_supervisor
import simplifile

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// Starts the server and keeps the calling process alive until SIGTERM stops
/// the server in order.
pub fn main() -> Nil {
  case argv.load().arguments {
    [folder] -> start(folder)
    _ ->
      refuse(
        "usage: gleam run -m genesis_prime/recording_server -- <session folder>",
      )
  }
}

fn start(folder: String) -> Nil {
  case simplifile.create_directory_all(folder) {
    Error(error) ->
      refuse(
        "the session folder "
        <> folder
        <> " was not made: "
        <> simplifile.describe_error(error),
      )
    Ok(Nil) -> {
      let name = process.new_name("draw_log")
      let assert Ok(_) =
        static_supervisor.new(static_supervisor.OneForOne)
        |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
        |> static_supervisor.add(draw_log.supervised(name:, folder:))
        |> static_supervisor.start
        as "the draw log did not start"
      io.println(
        "recording draws and accounts into "
        <> folder
        <> ": give the recording relays the same folder",
      )
      genesis_prime.run(settings: genesis_prime.settings(
        get: envoy.get,
        random: draw_log.source(name),
      ))
    }
  }
}

fn refuse(reason: String) -> Nil {
  io.println_error(reason)
  halt(2)
}
