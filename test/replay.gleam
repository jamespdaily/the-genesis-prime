//// Replays a recording over TCP against a server, for any edge test: it opens
//// a connection to the server, sends the client's chunks in the order the
//// recording holds them, and before each next client chunk waits for the
//// server chunks that came before it in the recording.
////
//// A server chunk is waited for by its bytes, not by how the server splits
//// them into packets: the bytes that arrive are matched against the
//// recording's server-to-client stream as they come, so two chunks that
//// arrive in one packet, or one chunk in two, replay the same. The wait for one
//// chunk's bytes has a deadline measured on the monotonic clock; it is the
//// time the server may take, not a pause the replay sits out. The first byte
//// that differs ends the replay, with its offset in the stream of everything
//// the server sent.

import genesis_prime/recording.{type Recording}
import mug

/// The server a replay connects to.
pub type Target {
  Target(host: String, port: Int)
}

/// Why a replay ended before the recording did. `chunk` is the position of the
/// recording's chunk being replayed, from 0, and `offset` is a byte's
/// position in the stream of everything the server sent, from 0.
pub type Failure {
  /// The connection to the server was not opened.
  NotConnected(error: mug.ConnectError)
  /// A client chunk was not sent.
  NotSent(chunk: Int, error: mug.Error)
  /// The server sent a byte other than the recording's at `offset`.
  Differs(chunk: Int, offset: Int, expected: Int, received: Int)
  /// The server had not sent the bytes of the chunk by the deadline;
  /// `offset` is the first byte that had not arrived.
  DeadlinePassed(chunk: Int, offset: Int)
  /// The server closed the connection before it had sent the chunk's bytes;
  /// `offset` is the first byte that had not arrived.
  ServerClosed(chunk: Int, offset: Int)
  /// Receiving failed for another reason.
  NotReceived(chunk: Int, offset: Int, error: mug.Error)
}

/// Replays `recording` against `target`. Each wait for the server's bytes of
/// one chunk takes at most `deadline_ms` milliseconds. The connection is closed
/// when the replay ends.
pub fn run(
  _recording: Recording,
  _target: Target,
  _deadline_ms: Int,
) -> Result(Nil, Failure) {
  panic as "shape only: not built"
}
