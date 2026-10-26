//// A server the test plants, to be replayed against or passed through: it
//// listens on a free loopback port, accepts one connection and plays a script
//// over it. For each client chunk of the script it reads that many bytes, and
//// for each server chunk it sends those bytes, in the script's order. When the
//// script ends it reports every byte the client sent and closes.

import genesis_prime/recording.{type Chunk}
import gleam/erlang/process.{type Subject}
import mug

/// A planted server that is listening: its port, and where it reports once
/// its script has played. The report is the bytes the client sent, in order,
/// or why the script could not play to its end.
pub type Peer {
  Peer(port: Int, report: Subject(Result(BitArray, mug.Error)))
}

/// Starts a planted server that plays `script`, linked to the caller. It
/// returns once the server listens. Every wait of the script takes at most
/// `wait_ms` milliseconds.
pub fn start(_script: List(Chunk), _wait_ms: Int) -> Peer {
  panic as "shape only: not built"
}
