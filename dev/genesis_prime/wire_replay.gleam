//// Replays a recorded session (genesis_prime/wire_recording) against the real
//// server tree, one connection at a time, and compares the bytes the server
//// writes with the bytes recorded.
////
//// ```
//// a test database ── every migration, then the session's fixture (`prepare`)
//// the server tree ── started on that database with, for each connection, the
////                    recorded seed and a clock the replay client moves
////                    (`replaying`, `serve_from`)
//// the replay client ─ connects to the listener of the connection's rule and
////                    walks the recorded lines in order (`play`):
////                      an "out" line: waits until the server has written the
////                        bytes recorded, then compares them (`compare`)
////                      an "in" line: moves the clock to the line's time, then
////                        sends the client's bytes
////                    so every read happens only after the server wrote all
////                    that was recorded before it
//// ```
////
//// What is compared is the byte stream, not how the socket cut it into reads
//// and writes, so a replay gives the same result when the client's chunks are
//// split or joined differently. A refusal, a difference or a silence ends the
//// replay of the connection with a `Failure` that names the connection and
//// the recorded line.

import genesis_prime/server
import genesis_prime/step.{type Now}
import genesis_prime/step/runtime.{type Clock, type SeedSource}
import genesis_prime/wire_recording.{type ReadFailure, type Recording}
import genesis_prime/wire_recording/fixture.{type FixtureError}
import gleam/option.{type Option}
import pog

/// How long the replay client waits for bytes the server has not written, in
/// milliseconds. A replay that waits this long fails as `Silent`.
pub const silence_ms = 5000

/// One recorded connection: the name of its file and what it holds.
pub type Connection {
  Connection(name: String, recording: Recording)
}

/// A recorded session: the connections of its folder in the order the session
/// opened them, and the path of the fixture beside them.
pub type Session {
  Session(folder: String, connections: List(Connection), fixture: String)
}

/// Why a session is not played at all.
pub type Refusal {
  /// A connection's file is not a recording that can be played; a cut
  /// recording is `Unreadable(_, Cut(_))`.
  Unreadable(connection: String, failure: ReadFailure)
  /// The recording was made on another client build than the one the replay is
  /// for, so the session must be recorded again.
  ClientBuildDiffers(connection: String, recorded: Int, current: Int)
  /// The recording was made on other game table files than the ones loaded
  /// now, so the session must be recorded again.
  TablesDiffer(
    connection: String,
    recorded: Option(String),
    current: Option(String),
  )
  /// The folder holds no fixture.
  NoFixture(path: String)
}

/// One message of a recorded or written stream, read with the current codec so
/// a person sees what differed.
pub type Decoded {
  /// A frame whose id the codec names, with its fields written out.
  Message(message_id: Int, name: String, text: String)
  /// A frame whose id has no decoder, or bytes that are not a whole frame.
  Undecoded(bytes: BitArray)
}

/// Where two byte streams first differ: the offset of the first different byte
/// and the message each stream holds there. A stream that ends before the
/// other has `Undecoded(<<>>)` where it stopped.
pub type Difference {
  Difference(offset: Int, recorded: Decoded, written: Decoded)
}

/// Why the replay of a connection failed. Every variant but `Refused` names the
/// connection and the line of the recording (from 0, the header being 0) the
/// replay was at.
pub type Failure {
  /// The session is not played.
  Refused(refusal: Refusal)
  /// The fixture could not be applied.
  FixtureFailed(error: FixtureError)
  /// The server wrote other bytes than the recording holds.
  Differs(connection: String, line: Int, difference: Difference)
  /// The server wrote nothing for `silence_ms` where the recording holds
  /// bytes; `expected` is the message it waited for.
  Silent(connection: String, line: Int, expected: Decoded)
  /// The server wrote bytes after the recording's last line, or while the
  /// recording expects the client to send.
  Unexpected(connection: String, line: Int, written: Decoded)
  /// The server ended the connection where the recording goes on, with the
  /// log lines the connection wrote (its refusal of a client byte among them).
  EndedEarly(connection: String, line: Int, logged: List(String))
  /// The replay client could not connect to the listener.
  NotConnected(connection: String, reason: String)
}

/// The hand that moves a replay's clock, held by the replay client: an Erlang
/// atomics array of the two values a `Now` holds, which the clock reads, so no
/// process holds the time.
pub type ClockHand

/// One connection's recording with what a replay of it gives the server: the
/// seed source that returns the recorded seed, and the clock, which reads the
/// `Now` its hand last moved to. The clock starts at the header's time, with its
/// monotonic time moved by one fixed offset so that it starts at the node's
/// own monotonic clock, since the deadlines a rule counts from its input's time
/// are compared with the node's.
pub type Replaying {
  Replaying(
    connection: Connection,
    seed_source: SeedSource,
    clock: Clock,
    hand: ClockHand,
  )
}

/// Reads every recording of the folder, and the fixture beside them, and
/// orders the connections as the session opened them (by the time of each
/// header).
pub fn load(folder _folder: String) -> Result(Session, Refusal) {
  panic as "built in the next commit"
}

/// Refuses a session whose recordings were made on another client build or on
/// other game table files than the ones given.
pub fn refuse_stale(
  session _session: Session,
  client_build _client_build: Int,
  tables_digest _tables_digest: Option(String),
) -> Result(Nil, Refusal) {
  panic as "built in the next commit"
}

/// Applies the session's fixture to a database that holds the schema and no
/// rows.
pub fn prepare(
  session _session: Session,
  database _database: pog.Connection,
) -> Result(Nil, Failure) {
  panic as "built in the next commit"
}

/// The seed source and the clock a replay of the connection gives the server.
pub fn replaying(connection _connection: Connection) -> Replaying {
  panic as "built in the next commit"
}

/// The listener's settings with the recorded seed source and clock of the
/// connection to replay; its recorders stay off.
pub fn serve_from(
  served _served: server.Served(settings),
  replaying _replaying: Replaying,
) -> server.Served(settings) {
  panic as "built in the next commit"
}

/// Moves the clock to `at`: every input the server takes from now until the
/// next move gets that `Now`.
pub fn move_clock(hand _hand: ClockHand, to _at: Now) -> Nil {
  panic as "built in the next commit"
}

/// The replay client: connects to the listener on `port`, plays the recorded
/// lines in order and compares what the server writes, ending at the first
/// failure. It returns when the recording's last line has been played and the
/// server has closed the connection.
pub fn play(
  replaying _replaying: Replaying,
  port _port: Int,
) -> Result(Nil, Failure) {
  panic as "built in the next commit"
}

/// Compares the bytes recorded with the bytes written, as streams, and says
/// where they first differ, with the message each holds there decoded.
pub fn compare(
  recorded _recorded: BitArray,
  written _written: BitArray,
) -> Result(Nil, Difference) {
  panic as "built in the next commit"
}

/// Reads the first message of `bytes` with the current codec.
pub fn decode(bytes _bytes: BitArray) -> Decoded {
  panic as "built in the next commit"
}
