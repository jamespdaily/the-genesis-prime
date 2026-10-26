//// A relay in front of a planted server, for the tests of the recording relay:
//// a folder of its own, a listening server the test accepts on, and the relay
//// started with the loopback as its address. The test is the client and, by
//// accepting, the server's side too, so it sees both ends of a connection.

import genesis_prime/recording.{
  type Chunk, type Direction, type Header, type Recording,
}
import mug

/// A running relay in front of a planted server.
pub type Session {
  Session(relay_port: Int, folder: String, header: Header)
}

/// Both ends of one connection through the relay: the client's socket, and the
/// socket the planted server accepted from the relay.
pub type Ends {
  Ends(client: mug.Socket, server: mug.Socket)
}

/// Runs `body` with a relay in a new folder under `build/`, and removes the
/// folder after.
pub fn run(_body: fn(Session) -> a) -> a {
  panic as "shape only: not built"
}

/// Opens a client connection through the relay and accepts it on the planted
/// server, waiting for each at most `wait_ms` milliseconds.
pub fn connect(_session: Session, _wait_ms: Int) -> Ends {
  panic as "shape only: not built"
}

/// The recordings in the session's folder, in the order of their file names.
pub fn recordings(_session: Session) -> List(Recording) {
  panic as "shape only: not built"
}

/// The chunks joined into runs of one direction: each run is its direction and
/// the bytes of its chunks one after another. A relay records a packet as the
/// socket delivers it, so the number of chunks in a run is not the number of
/// sends.
pub fn runs(_chunks: List(Chunk)) -> List(#(Direction, BitArray)) {
  panic as "shape only: not built"
}
