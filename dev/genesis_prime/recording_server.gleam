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

/// Starts the server and keeps the calling process alive until SIGTERM stops
/// the server in order.
pub fn main() -> Nil {
  panic as "shape only: built after the tests"
}
