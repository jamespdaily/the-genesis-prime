//// A recording of what one connection's socket carried: the bytes the client
//// sent and the bytes the server wrote, each with the time of the input they
//// belong to. It holds nothing of the server's own types, so a change to a
//// rule's internal types never makes a recording refuse to replay.
////
//// The file is JSON lines, one file for each connection, written as the shell
//// reads and writes:
////
//// ```
//// header   {"format":1,"rule":"genesis_prime/login/sts_connection",
////           "client_build":16042,"tables_digest":"...","seed":"<hex>",
////           "monotonic_ms":..,"filetime":..}
//// a read   {"monotonic_ms":..,"filetime":..,"direction":"in","bytes":"<hex>"}
//// a write  {"monotonic_ms":..,"filetime":..,"direction":"out","bytes":"<hex>"}
//// the end  {"closed":true}
//// ```
////
//// The time of a line is the `Now` of the input the shell was taking when the
//// bytes moved: the read's own time, or, for a write, the input whose step
//// wrote it. The server's clock then gives the same `Now` to the same input
//// when the recording is played again, so a message that carries the server's
//// time (opcode.0x117) comes out as it did. A file with no closing line, or
//// whose last line is cut, is a cut recording.

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
    /// The time the connection was accepted: the `Now` of its first input.
    started: Now,
  )
}

/// Which way bytes crossed the socket.
pub type Direction {
  /// The client sent them: the shell read them.
  FromClient
  /// The server wrote them.
  ToClient
}

/// One read or write of the socket: the bytes as the socket carried them, and
/// the `Now` of the input the shell was taking.
pub type Transfer {
  Transfer(at: Now, direction: Direction, bytes: BitArray)
}

/// One line after the header.
pub type Line {
  Moved(transfer: Transfer)
  /// The last line: the connection ended.
  Closed
}

/// A recording read whole: its header and every transfer, in order.
pub type Recording {
  Recording(header: Header, transfers: List(Transfer))
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
  /// format, with what is wrong with it.
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

/// The recording a file's text holds. A file whose last line is cut, or that
/// has no closing line, is `Cut`; the closing line is not among the transfers.
pub fn read(text _text: String) -> Result(Recording, ReadFailure) {
  panic as "built in the next commit"
}
