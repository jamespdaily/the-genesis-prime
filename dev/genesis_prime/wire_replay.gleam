//// Replays a recorded session (genesis_prime/wire_recording) against the real
//// server tree and compares the bytes the server writes with the bytes
//// recorded.
////
//// ```
//// a test database ── every migration, then the session's fixture (`prepare`)
//// the server tree ── started on that database; each listener's `Served` has
////                    `scripts` from `serve_from`, which hands the connection
////                    accepted n-th the script of the recording with the n-th
////                    accept ordinal: its seed, its `Now`s in a queue and a
////                    scheduler whose timers wait for the replay client
//// the replay client ─ `play` walks the plan (`plan`) of every connection's
////                    lines, sorted by sequence number:
////                      connect: one connection after another, in accept
////                        order, each only once the server has handed out
////                        the script of its ordinal
////                      an input line the client causes (a read, a timer, the
////                        client's close): first waits until that connection's
////                        shell has taken every earlier input (`taken`, the
////                        number of times its script's clock was called),
////                        then sends the bytes, fires the timer at the
////                        scheduler or closes the socket
////                      an input line the server causes (an answer, a
////                        message, a watch's end): waits until the shell has
////                        taken it
////                      a write line: waits until the server has written the
////                        bytes recorded, then compares them (`compare`)
////                      the closing line: the client's close was sent at its
////                        input line; a server close is awaited
//// ```
////
//// What is compared is the byte stream the server writes, not how the socket
//// cut it into writes, so a replay gives the same result when the server cuts
//// its writes differently. The client's bytes are sent as the recording holds
//// them, one send for each read line, each only after the shell has taken the
//// input before it: a read line is one input and one `Now`, so a replay does
//// not join or split them.
////
//// Every wait of the replay client is bounded by `wait_ms` of real time, and
//// so is the shell's wait for an ask (genesis_prime/connection/shell): a replay
//// ends, and says what it waited for. A refusal, a difference, a silence or a
//// shell that never takes an input ends the replay with a `Failure` that names
//// the connection and the recorded line.

import genesis_prime/connection/script.{type Scripts}
import genesis_prime/server
import genesis_prime/wire_recording.{
  type Input, type ReadFailure, type Recording, type Side,
}
import genesis_prime/wire_recording/fixture.{type FixtureError}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name}
import gleam/option.{type Option}
import gleam/otp/supervision.{type ChildSpecification}
import pog

/// How long every wait of the replay client, and every ask's wait in the
/// shell, lasts in real milliseconds. A replay that waits this long fails.
pub const wait_ms = 5000

/// One recorded connection: the name of its file and what it holds.
pub type Connection {
  Connection(name: String, recording: Recording)
}

/// A recorded session: the connections of its folder in the order the server
/// accepted them (by the accept ordinal of each header), and the path of the
/// fixture beside them.
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
  /// An ask of the recording ended with no answer in time. Whether the asked
  /// process would have answered is a matter of time, so a replay cannot
  /// bring the outcome about, and the session must be recorded again.
  AskTimedOut(connection: String, line: Int)
  /// A connection was accepted more than the hand-off keys' lifetime after the
  /// connection before it was last read from, so a key the one put could not
  /// be taken by the other. A replay runs no slower than the recording and
  /// would take the key, so the session must be recorded again.
  HandOffKeyExpired(
    earlier: String,
    later: String,
    gap_ms: Int,
    lifetime_ms: Int,
  )
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
/// and the message each stream holds there, decoded only where no cipher is on
/// (the replay client holds no session keys), else `Undecoded` with the bytes. A
/// stream that ends before the other has `Undecoded(<<>>)` where it stopped.
pub type Difference {
  Difference(offset: Int, recorded: Decoded, written: Decoded)
}

/// Why the replay of a session failed. Every variant but `Refused` and
/// `FixtureFailed` names the connection and the line of its recording (from 0,
/// the header being 0) the replay was at.
pub type Failure {
  /// The session is not played.
  Refused(refusal: Refusal)
  /// The fixture could not be applied.
  FixtureFailed(error: FixtureError)
  /// The replay client could not connect to the listener, or the server
  /// did not hand out the connection's script within `wait_ms`.
  NotConnected(connection: String, reason: String)
  /// The server wrote other bytes than the recording holds.
  Differs(connection: String, line: Int, difference: Difference)
  /// The server wrote nothing for `wait_ms` where the recording holds bytes;
  /// `expected` is the message it waited for.
  Silent(connection: String, line: Int, expected: Decoded)
  /// The server wrote bytes after the recording's last line, or while the
  /// recording expects the client to send.
  Unexpected(connection: String, line: Int, written: Decoded)
  /// The shell took fewer inputs than the recording's line needs within
  /// `wait_ms`: `taken` is how many it had taken and `input` the kind of input
  /// the line records.
  NeverTaken(connection: String, line: Int, input: Input, taken: Int)
  /// The timer the line records was not started within `wait_ms`.
  TimerNeverStarted(connection: String, line: Int, timer: Int)
  /// The shell took an input the recording does not hold, so its script's
  /// clock had no `Now` to give.
  TookUnrecordedInput(connection: String, line: Int)
  /// The server ended the connection where the recording goes on, with the
  /// log lines the connection wrote (its refusal of a client byte among them).
  EndedEarly(connection: String, line: Int, logged: List(String))
  /// The recording's last line says the server closed the connection, and it
  /// had not within `wait_ms`.
  StillOpen(connection: String, line: Int)
}

/// One step of the replay client, in the order it takes them.
pub type Action {
  /// Connects to the listener of the connection's rule and waits until the
  /// server has handed out the script of the connection's ordinal.
  Connect(connection: String)
  /// Waits until the connection's shell has taken `inputs` inputs. `input` is
  /// the kind of input of `line`, named when the wait ends in `NeverTaken`.
  AwaitTaken(connection: String, line: Int, inputs: Int, input: Input)
  /// Sends the bytes of a read line, whole, in one send.
  Send(connection: String, line: Int, bytes: BitArray)
  /// Fires the timer a timer line records, waiting for the shell to have
  /// started it.
  Fire(connection: String, line: Int, timer: Int)
  /// Closes the replay client's socket, as the recorded client did.
  CloseClientSocket(connection: String, line: Int)
  /// Waits for the server to write the bytes of a write line and compares them.
  Expect(connection: String, line: Int, bytes: BitArray)
  /// Waits for the end of the connection, which the closing line says `by`
  /// ended: a client's close has been sent, so only the shell's own end is
  /// awaited; a server's close is awaited on the socket.
  AwaitEnd(connection: String, line: Int, by: Side)
}

/// How many inputs one connection's shell has taken: the number of times its
/// script's clock has been called. The replay client reads it to know how far
/// the shell is, and the shell never writes it any other way.
pub type Progress

/// The scheduler's table of the timers the replay's shells have started, kept
/// by one process so the shells that start a timer, the client that fires it
/// and the client that waits for it to be started share nothing else.
pub type Timers {
  Timers(name: Name(TimerCommand))
}

/// What the timer table is told.
pub type TimerCommand

/// What a replay gives the server and keeps for the replay client.
pub type Replay {
  Replay(
    /// Hands out the script of each connection in the order of the accept
    /// ordinals, each once, and `Error(Nil)` after the last, whatever listener
    /// asks and however often a listener restarts.
    scripts: Scripts,
    /// How far each connection's shell is, by the name of its file.
    progress: Dict(String, Progress),
    timers: Timers,
  )
}

/// The timer table as a child of the replay's own supervisor, started before
/// the server tree and stopped after it.
pub fn timers_supervised(
  name _name: Name(TimerCommand),
) -> ChildSpecification(Nil) {
  panic as "built in the next commit"
}

/// Reads every recording of the folder, and the fixture beside them, and
/// orders the connections by the accept ordinal of their headers.
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

/// Refuses a session a replay cannot bring about: an ask that timed out, or a
/// hand-off key that outlived `hand_off_lifetime_ms` between two connections.
pub fn refuse_unreproducible(
  session _session: Session,
  hand_off_lifetime_ms _hand_off_lifetime_ms: Int,
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

/// What the session's connections are given: one script for each, with the
/// recording's seed, a clock that queues its recorded `Now`s (one for each
/// call, and the `Now`s of an input the recording holds only), and a scheduler
/// that starts its timers in `timers` and fires them when the replay client asks.
pub fn replay(session _session: Session, timers _timers: Timers) -> Replay {
  panic as "built in the next commit"
}

/// The listener's settings with the replay's scripts; its recorders stay off.
pub fn serve_from(
  served _served: server.Served(settings),
  replay _replay: Replay,
) -> server.Served(settings) {
  panic as "built in the next commit"
}

/// How many inputs the shell of a connection has taken.
pub fn taken(progress _progress: Progress) -> Int {
  panic as "built in the next commit"
}

/// The replay client's steps for the session: a `Connect` for each connection
/// in accept order, then the lines of every connection sorted by sequence
/// number.
/// - a read line: `AwaitTaken` of the inputs before it, then `Send`;
/// - a timer line: `AwaitTaken` of the inputs before it, then `Fire`;
/// - a client's close line: `AwaitTaken` of the inputs before it, then
///   `CloseClientSocket`;
/// - any other input line (accepted, answered, woken, watch ended, a failure,
///   stopping): `AwaitTaken` of the inputs up to and including it;
/// - a write line: `Expect`;
/// - the closing line: `AwaitEnd`.
pub fn plan(session _session: Session) -> List(Action) {
  panic as "built in the next commit"
}

/// The replay client: carries out the plan of the session, connecting each
/// connection to the port of its rule's listener (`ports`, by the rule's name),
/// and ends at the first failure. It returns when the plan has been carried
/// out.
pub fn play(
  session _session: Session,
  replay _replay: Replay,
  ports _ports: Dict(String, Int),
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
