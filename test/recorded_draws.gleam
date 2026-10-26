//// The draws of a recorded session, given back to a server that replays it: a
//// random source that answers each connection's draws with the ones the
//// recording server wrote for the connection it replays, in order. A replay
//// registers its connection's draws under the connection's own address once
//// the connection is open (`replay.run_connected`), before the first byte
//// reaches the server, so the server draws only after they are there.
////
//// A draw the source cannot answer from the recording, because the connection
//// has no draws registered, has none left or is asked for another number of
//// bytes than it recorded, ends the drawing process with the reason, which
//// closes the connection and fails the replay.

import genesis_prime/login/random_source.{type RandomSource}
import gleam/erlang/process.{type Subject}

/// The process that holds the registered draws.
pub type Draws {
  Draws(subject: Subject(Message))
}

pub type Message {
  Register(connection: String, draws: List(BitArray), reply: Subject(Nil))
}

/// Starts the process, linked to the caller, with no draws registered.
pub fn start() -> Draws {
  panic as "shape only: built after the tests"
}

/// The source to give the server's settings: each draw of a connection is
/// answered from the draws registered for its address.
pub fn source(draws _draws: Draws) -> RandomSource {
  panic as "shape only: built after the tests"
}

/// Registers the draws a connection will make, under the address the server
/// sees for it, replacing any registered before.
pub fn register(
  draws _draws: Draws,
  connection _connection: String,
  bytes _bytes: List(BitArray),
) -> Nil {
  panic as "shape only: built after the tests"
}
