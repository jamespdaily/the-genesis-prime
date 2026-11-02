//// A recording of what one connection's shell took and wrote: each input it
//// took, with the time it carried, and each write, as bytes. It holds nothing
//// of the server's own types, so a change to a rule's internal types never
//// makes a recording refuse to replay.
////
//// The file is JSON lines, one file for each connection, written as the shell
//// takes inputs and writes:
////
//// ```
//// header   {"format":1,"rule":"genesis_prime/login/sts_connection",
////           "client_build":16042,"tables_digest":"...","seed":"<hex>",
////           "accept_ordinal":3}
//// an input {"sequence":41,"monotonic_ms":..,"filetime":..,"in":"read","bytes":"<hex>"}
////          {"sequence":43,"monotonic_ms":..,"filetime":..,"in":"answered","outcome":"answer"}
////          {"sequence":47,"monotonic_ms":..,"filetime":..,"in":"timer_fired","timer":2}
////          "in" is one of accepted, read, answered, timer_fired, peer_closed,
////          read_failed, write_failed, woken, watch_ended, stopping
//// a write  {"sequence":42,"out":"<hex>"}
//// the end  {"sequence":52,"closed":"client"}     or "server"
//// ```
////
//// - **Sequence.** Every line holds a number from the node's one counter
////   (`runtime.unique_id`), taken as the line's event happens: before the
////   socket is given a write's bytes, and as an input is taken. The lines of
////   every connection of a session, sorted by it, are the order the node saw
////   them in, so a replay walks them in that order.
//// - **Time.** An input line holds the whole `Now` the shell's clock gave the
////   input: the monotonic clock and the FILETIME. A write line holds none: the
////   bytes depend on the time of the input whose step wrote them, and a replay
////   gives that input the same `Now`.
//// - **Accept ordinal.** The place of the connection among those its server
////   accepted, given with its script as the shell took the socket, so the
////   order of accepts is recorded and never inferred from times.
//// - **The end.** The closing line names the side that ended the connection:
////   the client when the shell's last input was the socket's close, the server
////   otherwise. A file with no closing line, or whose last line is cut, is a
////   cut recording.
//// - **What an input line leaves out.** The messages of other processes, the
////   answers to asks and the failures' reasons are the rule's own types, so a
////   line holds only the kind of input and, for an answer, how the ask ended.
////   A replay gets the same messages and answers by running the real services.

import genesis_prime/step.{type Now}
import gleam/option.{type Option}

/// The version of this file format; a reader refuses any other.
pub const format = 1

/// What a replay must match before it plays the lines.
pub type Header {
  Header(
    format: Int,
    /// The rule's module, such as `genesis_prime/login/sts_connection`.
    rule: String,
    /// The client build the session was played on.
    client_build: Int,
    /// A digest of the game table files the rule reads, or `None` for a rule
    /// that reads no table.
    tables_digest: Option(String),
    /// The 32 bytes the rule's random values are all drawn from.
    seed: BitArray,
    /// The place of the connection among those its server accepted.
    accept_ordinal: Int,
  )
}

/// How an ask ended, without the answer, which is the rule's own type.
pub type Outcome {
  Answer
  NotRunning
  EndedBeforeAnswer
  NoAnswerInTime
  StoppedWaiting
}

/// One kind of input the shell takes. Only what the replay needs to cause or
/// to wait for is kept.
pub type Input {
  /// The connection's socket is the process's own: the first input.
  Accepted
  /// Bytes the client sent, as the socket delivered them.
  Read(bytes: BitArray)
  /// The outcome of the ask that ended the rule's last step.
  Answered(outcome: Outcome)
  /// A timer the rule started fired; `timer` is the number inside its
  /// `TimerId`.
  TimerFired(timer: Int)
  /// The client closed the connection.
  PeerClosed
  ReadFailed
  WriteFailed
  /// Another process sent the connection a message.
  Woken
  /// A process the rule watched ended.
  WatchEnded
  /// The server is stopping.
  Stopping
}

/// Which side ended the connection.
pub type Side {
  Client
  Server
}

/// One line after the header and before the closing line.
pub type Line {
  /// An input the shell took, with the `Now` its clock gave it.
  Took(sequence: Int, at: Now, input: Input)
  /// Bytes the shell wrote to the socket, which the socket took.
  Wrote(sequence: Int, bytes: BitArray)
}

/// The last line: the connection ended.
pub type Closing {
  Closing(sequence: Int, by: Side)
}

/// A recording read whole: its header, its lines in the order written and its
/// closing line.
pub type Recording {
  Recording(header: Header, lines: List(Line), closing: Closing)
}

/// Why a file is not a recording that can be played.
pub type ReadFailure {
  /// The file ends before its closing line, or inside a line: the server
  /// stopped mid-session or the file was cut. `lines` counts the whole lines
  /// read, the header included.
  Cut(lines: Int)
  /// The header is of another format; the session must be recorded again.
  OtherFormat(found: Int)
  /// The line at `line` (from 0, the header being 0) is not a line of this
  /// format, or its sequence number does not grow, with what is wrong with it.
  NotALine(line: Int, reason: String)
}

/// The header as one JSON line, ending in a line feed.
pub fn encode_header(header _header: Header) -> String {
  panic as "built in the next commit"
}

/// A line as one JSON line, ending in a line feed.
pub fn encode_line(line _line: Line) -> String {
  panic as "built in the next commit"
}

/// The closing line as one JSON line, ending in a line feed.
pub fn encode_closing(closing _closing: Closing) -> String {
  panic as "built in the next commit"
}

/// The recording a file's text holds. A file whose last line is cut, or that
/// has no closing line, is `Cut`; each line's sequence number must be larger
/// than the one before.
pub fn read(text _text: String) -> Result(Recording, ReadFailure) {
  panic as "built in the next commit"
}
