//// Where the login's random bytes come from: the server's SRP secret and the
//// one-time keys of the hand-offs. A running server draws from the operating
//// system's strong source. A source supplied from outside is for the dev start
//// that records a session and for the tests that replay one: each draw is told
//// which connection makes it, so a recording can keep a connection's draws
//// apart from every other connection's, and a replay can give the replayed
//// connection those draws again. The code rules refuse building `Supplied`
//// anywhere in `src/` but here, so the server that is released has only
//// `Strong`.

import genesis_prime/login/account.{type Account}
import gleam/crypto
import gleam/option.{type Option}

/// One draw: how many bytes are wanted, the connection that wants them, and
/// the account the draw is for, when it is for the login of one.
///
/// `connection` is the connection's peer address as text, which no other open
/// connection of the server has at the same time, and none when the socket has
/// no peer. `account` is the row the login found, so a record of the draws
/// holds the salt and verifier its login read.
pub type Draw {
  Draw(count: Int, connection: Option(String), account: Option(Account))
}

/// Where a draw of random bytes comes from.
pub type RandomSource {
  /// The operating system's strong source: bytes nobody can predict.
  Strong
  /// A source the caller supplies: `draw` takes a draw and returns as many
  /// bytes as it asks for.
  Supplied(draw: fn(Draw) -> BitArray)
}

/// The bytes the draw asks for, from the source.
pub fn bytes(source source: RandomSource, draw draw: Draw) -> BitArray {
  case source {
    Strong -> crypto.strong_random_bytes(draw.count)
    Supplied(draw: supplied) -> supplied(draw)
  }
}
