//// Starts the whole server as `genesis_prime.main` does, with the same
//// environment settings, but with its random bytes drawn from a seeded
//// generator, so a session recorded against it can be played again against a
//// new server started with the same seed:
////
//// `gleam run -m genesis_prime/seeded_server -- <seed>`
////
//// - `seed`: a whole number from 0 to 18446744073709551615.
////
//// It prints the seed, and the recording relay is given the same seed as its
//// last argument (`genesis_prime/record`), which writes it into the header of
//// each recording of the session. The released server has no way to take a
//// seed: its settings use the operating system's strong source, and the code
//// rules keep this generator out of `src/`.
////
//// The seeded source is one process under a supervisor of its own that this
//// program links to. A restart of the source starts its sequence again from
//// the seed.

import argv
import envoy
import genesis_prime
import genesis_prime/seeded_random
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/otp/static_supervisor

/// Ends the program with a status.
@external(erlang, "erlang", "halt")
fn halt(status: Int) -> Nil

/// Starts the server on the seed the command line gives, and keeps the calling
/// process alive until SIGTERM stops the server in order.
pub fn main() -> Nil {
  case argv.load().arguments {
    [text] ->
      case int.parse(text) {
        Ok(seed) if seed >= 0 && seed <= seeded_random.largest_seed ->
          start(seed)
        _ -> refuse("not a seed (0 to 18446744073709551615): " <> text)
      }
    _ -> refuse("usage: gleam run -m genesis_prime/seeded_server -- <seed>")
  }
}

fn start(seed: Int) -> Nil {
  let name = process.new_name("seeded_random")
  let assert Ok(_) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.restart_tolerance(intensity: 3, period: 5)
    |> static_supervisor.add(seeded_random.supervised(name:, seed:))
    |> static_supervisor.start
    as "the seeded random source did not start"
  io.println(
    "seed "
    <> int.to_string(seed)
    <> ": give the recording relay this seed as its last argument",
  )
  genesis_prime.run(settings: genesis_prime.settings(
    get: envoy.get,
    random: seeded_random.source(name),
  ))
}

fn refuse(reason: String) -> Nil {
  io.println_error(reason)
  halt(2)
}
