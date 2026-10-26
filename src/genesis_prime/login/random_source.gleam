//// Where the login's random bytes come from: the server's SRP secret and the
//// one-time keys of the hand-offs. A running server draws from the operating
//// system's strong source. A source supplied from outside is for the dev start
//// and the tests, which need the same draws every run so a recorded session
//// can be played again; the code rules refuse the seeded generator in `src/`,
//// so the server that is released has only `Strong`.

import gleam/crypto

/// Where a draw of random bytes comes from.
pub type RandomSource {
  /// The operating system's strong source: bytes nobody can predict.
  Strong
  /// A source the caller supplies: `draw` takes the number of bytes wanted and
  /// returns that many.
  Supplied(draw: fn(Int) -> BitArray)
}

/// `count` random bytes from the source.
pub fn bytes(source source: RandomSource, count count: Int) -> BitArray {
  case source {
    Strong -> crypto.strong_random_bytes(count)
    Supplied(draw:) -> draw(count)
  }
}
