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
//// seed.

/// Starts the server on the seed the command line gives.
pub fn main() -> Nil {
  panic as "shape only: not built"
}
