//// The file a recording relay writes for one connection of a live session with
//// the real client, and the reader of it: the second rank of evidence, after
//// the client's own code and tables. A replay (`test/replay.gleam`) drives the
//// server with what a recording holds.
////
//// A recording holds every byte each way of one TCP connection as the relay
//// received it from the socket, before any decode, in the order it received
//// them. Each chunk carries its direction and the microseconds from the
//// connection's start, read from the monotonic clock, so the times never go
//// backwards and mean nothing outside the file. The header holds the client's
//// build, the date, the role the connection reached and the commit of the
//// server code that was checked out when it was recorded.
////
//// The layout, with every integer unsigned and big-endian:
//// - header: the four bytes `GREC`, the format version (1 byte, 1), the
////   client's build (32 bits), the year (16 bits), the month (8 bits, 1 to
////   12), the day (8 bits), the role as text, the commit as text. A text is
////   its length in bytes (16 bits) and then that many bytes of UTF-8.
//// - then any number of chunks, each: the direction (8 bits, 0 for client to
////   server, 1 for server to client), the microseconds from the connection's
////   start (64 bits), the length (32 bits) and that many bytes.
////
//// A relay stopped between two chunks leaves a recording that reads, ending
//// at the last chunk it wrote.
////
//// Secrets: the relay writes the bytes of the wire unchanged, and the reader
//// and the replay keep no marker for a secret. The STS login of the client
//// (port 6600) uses SRP-6a, so no password crosses the wire and a recording
//// holds none: the client keeps only a hash of the account name and password
//// (fact `StsConnLib64.MT.dll!0x18002ccd0`), and what it sends is the account
//// name, public values and proofs. The account name does cross in clear, so a session is
//// recorded with a test account. A secret that did cross the wire would be
//// replaced in the committed file by bytes of the same length before the file
//// is committed, and the replay of that flow would have to be given the secret
//// to send; no recorded flow has one.

import gleam/time/calendar.{type Date}
import simplifile.{type FileError}

/// Which of the server's roles a connection reached, as the client names the
/// ports: the NC platform login (STS, port 6600 by default), the auth server
/// (port 23115 by default) and a game server, the address of which the auth
/// server's hand-off gives (message 0x3DB).
pub type Role {
  Sts
  Auth
  Game
}

/// Which way a chunk crossed the relay.
pub type Direction {
  ClientToServer
  ServerToClient
}

/// What a recording says about itself: the client's build, the day it was
/// recorded, the role and the server code's commit as text.
pub type Header {
  Header(build: Int, date: Date, role: Role, commit: String)
}

/// Bytes the relay received on one side of the connection. `microseconds` is
/// the time from the connection's start, never negative.
pub type Chunk {
  Chunk(direction: Direction, microseconds: Int, bytes: BitArray)
}

/// A whole recording of one connection: its header and its chunks in the order
/// the relay received them.
pub type Recording {
  Recording(header: Header, chunks: List(Chunk))
}

/// Why a recording could not be written or read.
pub type RecordingError {
  /// The file does not start with the four bytes `GREC`.
  NotARecording
  /// The format version of the file, which this reader does not read.
  UnsupportedVersion(version: Int)
  /// The file ends inside the header or inside a chunk, `offset` bytes from
  /// its start being where the incomplete part began.
  Truncated(offset: Int)
  /// The role text is not the name of a role.
  UnknownRole(name: String)
  /// The direction byte is neither 0 nor 1.
  UnknownDirection(value: Int)
  /// The month byte is not 1 to 12, or the day is not a day of that month.
  InvalidDate(year: Int, month: Int, day: Int)
  /// A text of the header is not UTF-8.
  NotText(offset: Int)
  /// A chunk's time is negative, which the format cannot hold.
  NegativeTime(microseconds: Int)
  /// A header field does not fit its width in the file: the build, the year or
  /// a text's length in bytes.
  OutOfRange(field: String, value: Int)
  /// A file is already there where a recording is created.
  AlreadyExists(path: String)
  /// The file system refused a read, a write or a create.
  FileFailed(error: FileError)
}

/// The name of a role as the file and the command line write it: `sts`,
/// `auth` or `game`.
pub fn role_name(_role: Role) -> String {
  panic as "shape only: not built"
}

/// The role a name stands for, as `role_name` writes it.
pub fn role_from_name(_name: String) -> Result(Role, Nil) {
  panic as "shape only: not built"
}

/// The bytes of a header, as the file starts.
pub fn encode_header(_header: Header) -> Result(BitArray, RecordingError) {
  panic as "shape only: not built"
}

/// The bytes of one chunk, as the file holds it.
pub fn encode_chunk(_chunk: Chunk) -> Result(BitArray, RecordingError) {
  panic as "shape only: not built"
}

/// The bytes of a whole recording: its header and then each chunk.
pub fn encode(_recording: Recording) -> Result(BitArray, RecordingError) {
  panic as "shape only: not built"
}

/// The recording a file's bytes hold, or the first thing wrong with them.
pub fn decode(_bytes: BitArray) -> Result(Recording, RecordingError) {
  panic as "shape only: not built"
}

/// Creates a file at `path` holding the header and no chunk. A file already at
/// `path` is never overwritten.
pub fn create(
  at _path: String,
  header _header: Header,
) -> Result(Nil, RecordingError) {
  panic as "shape only: not built"
}

/// Adds one chunk to the end of the file at `path`, which `create` made.
pub fn append(
  to _path: String,
  chunk _chunk: Chunk,
) -> Result(Nil, RecordingError) {
  panic as "shape only: not built"
}

/// The recording in the file at `path`.
pub fn read(from _path: String) -> Result(Recording, RecordingError) {
  panic as "shape only: not built"
}
