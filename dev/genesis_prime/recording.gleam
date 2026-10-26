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
//// build, the date, the role the connection reached, the commit of the
//// server code that was checked out when it was recorded, and the seed of the
//// server's random source when the session ran on the dev start
//// (`genesis_prime/seeded_server`), which a replay starts its server with.
//// A server that draws its random values from the operating system leaves no
//// seed, and its recording cannot be played again past its first random value.
////
//// The layout, with every integer unsigned and big-endian:
//// - header: the four bytes `GREC`, the format version (1 byte, 1 or 2), the
////   client's build (32 bits), the year (16 bits), the month (8 bits, 1 to
////   12), the day (8 bits), the role as text, the commit as text, and, in
////   version 2 only, the seed (64 bits). A text is its length in bytes (16
////   bits) and then that many bytes of UTF-8. A recording with a seed is
////   written as version 2 and one without as version 1, so the files made
////   before the seed existed read as unseeded, byte for byte as they were.
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

import gleam/bit_array
import gleam/bool
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/time/calendar.{type Date, Date}
import simplifile.{type FileError}

/// The four bytes every recording starts with.
const magic = <<"GREC":utf8>>

/// The format version of a recording without a seed, and of one with a seed.
/// Both are read; each is written for the recordings that fit it.
const version_without_seed = 1

const version_with_seed = 2

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
/// recorded, the role, the server code's commit as text, and the seed of the
/// server's random source when the session ran on the dev start, none when it
/// did not (a server that draws from the operating system cannot be played
/// again).
pub type Header {
  Header(build: Int, date: Date, role: Role, commit: String, seed: Option(Int))
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
pub fn role_name(role: Role) -> String {
  case role {
    Sts -> "sts"
    Auth -> "auth"
    Game -> "game"
  }
}

/// The role a name stands for, as `role_name` writes it.
pub fn role_from_name(name: String) -> Result(Role, Nil) {
  case name {
    "sts" -> Ok(Sts)
    "auth" -> Ok(Auth)
    "game" -> Ok(Game)
    _ -> Error(Nil)
  }
}

/// The bytes of a whole recording: its header and then each chunk.
pub fn encode(recording: Recording) -> Result(BitArray, RecordingError) {
  use header <- result.try(encode_header(recording.header))
  list.try_fold(recording.chunks, header, fn(written, chunk) {
    use bytes <- result.map(encode_chunk(chunk))
    <<written:bits, bytes:bits>>
  })
}

fn encode_header(header: Header) -> Result(BitArray, RecordingError) {
  let Header(build:, date:, role:, commit:, ..) = header
  let Date(year:, month:, day:) = date
  let month_number = calendar.month_to_int(month)
  use <- bool.guard(
    !calendar.is_valid_date(date),
    Error(InvalidDate(year:, month: month_number, day:)),
  )
  use build <- result.try(fit(field: "build", value: build, bits: 32))
  use year <- result.try(fit(field: "year", value: year, bits: 16))
  use role <- result.try(encode_text("role", role_name(role)))
  use commit <- result.try(encode_text("commit", commit))
  use #(version, seed) <- result.map(encode_seed(header.seed))
  <<
    magic:bits,
    version:size(8),
    build:size(32),
    year:size(16),
    month_number:size(8),
    day:size(8),
    role:bits,
    commit:bits,
    seed:bits,
  >>
}

/// The format version a header's seed calls for, and the bytes of the seed
/// that follow the commit: none without a seed.
fn encode_seed(seed: Option(Int)) -> Result(#(Int, BitArray), RecordingError) {
  case seed {
    None -> Ok(#(version_without_seed, <<>>))
    Some(seed) -> {
      use seed <- result.map(fit(field: "seed", value: seed, bits: 64))
      #(version_with_seed, <<seed:size(64)>>)
    }
  }
}

fn encode_chunk(chunk: Chunk) -> Result(BitArray, RecordingError) {
  let Chunk(direction:, microseconds:, bytes:) = chunk
  use <- bool.guard(microseconds < 0, Error(NegativeTime(microseconds:)))
  use microseconds <- result.try(fit(
    field: "microseconds",
    value: microseconds,
    bits: 64,
  ))
  use length <- result.try(fit(
    field: "length",
    value: bit_array.byte_size(bytes),
    bits: 32,
  ))
  Ok(<<
    direction_byte(direction):size(8),
    microseconds:size(64),
    length:size(32),
    bytes:bits,
  >>)
}

/// The value, when it fits `bits` bits as an unsigned number.
fn fit(
  field field: String,
  value value: Int,
  bits bits: Int,
) -> Result(Int, RecordingError) {
  use <- bool.guard(
    value < 0 || value >= int.bitwise_shift_left(1, bits),
    Error(OutOfRange(field:, value:)),
  )
  Ok(value)
}

/// A text as the file holds it: its length in bytes and then its UTF-8 bytes.
fn encode_text(
  field: String,
  text: String,
) -> Result(BitArray, RecordingError) {
  let bytes = bit_array.from_string(text)
  use length <- result.map(fit(
    field:,
    value: bit_array.byte_size(bytes),
    bits: 16,
  ))
  <<length:size(16), bytes:bits>>
}

fn direction_byte(direction: Direction) -> Int {
  case direction {
    ClientToServer -> 0
    ServerToClient -> 1
  }
}

/// The recording a file's bytes hold, or the first thing wrong with them.
pub fn decode(bytes: BitArray) -> Result(Recording, RecordingError) {
  let total = bit_array.byte_size(bytes)
  case bytes {
    <<"GREC":utf8, after_magic:bytes>> -> decode_version(after_magic, total)
    _ -> Error(NotARecording)
  }
}

fn decode_version(
  bytes: BitArray,
  total: Int,
) -> Result(Recording, RecordingError) {
  case bytes {
    <<version:size(8), after_version:bytes>> ->
      case version == version_without_seed || version == version_with_seed {
        True -> decode_header(bytes: after_version, total:, version:)
        False -> Error(UnsupportedVersion(version:))
      }
    _ -> Error(Truncated(offset: offset(total, bytes)))
  }
}

fn decode_header(
  bytes bytes: BitArray,
  total total: Int,
  version version: Int,
) -> Result(Recording, RecordingError) {
  case bytes {
    <<
      build:size(32),
      year:size(16),
      month:size(8),
      day:size(8),
      after_date:bytes,
    >> -> {
      use date <- result.try(decode_date(year:, month:, day:))
      use #(name, after_role) <- result.try(decode_text(after_date, total))
      use role <- result.try(
        role_from_name(name)
        |> result.replace_error(UnknownRole(name:)),
      )
      use #(commit, after_commit) <- result.try(decode_text(after_role, total))
      use #(seed, after_seed) <- result.try(decode_seed(
        bytes: after_commit,
        total:,
        version:,
      ))
      use chunks <- result.map(
        decode_chunks(bytes: after_seed, total:, chunks: []),
      )
      Recording(header: Header(build:, date:, role:, commit:, seed:), chunks:)
    }
    _ -> Error(Truncated(offset: offset(total, bytes)))
  }
}

/// The seed after the commit, which only version 2 holds.
fn decode_seed(
  bytes bytes: BitArray,
  total total: Int,
  version version: Int,
) -> Result(#(Option(Int), BitArray), RecordingError) {
  case version == version_with_seed, bytes {
    False, _ -> Ok(#(None, bytes))
    True, <<seed:size(64), after:bytes>> -> Ok(#(Some(seed), after))
    True, _ -> Error(Truncated(offset: offset(total, bytes)))
  }
}

fn decode_date(
  year year: Int,
  month month: Int,
  day day: Int,
) -> Result(Date, RecordingError) {
  let invalid = InvalidDate(year:, month:, day:)
  use month <- result.try(
    calendar.month_from_int(month) |> result.replace_error(invalid),
  )
  let date = Date(year:, month:, day:)
  case calendar.is_valid_date(date) {
    True -> Ok(date)
    False -> Error(invalid)
  }
}

fn decode_text(
  bytes: BitArray,
  total: Int,
) -> Result(#(String, BitArray), RecordingError) {
  case bytes {
    <<length:size(16), text:bytes-size(length), after:bytes>> ->
      case bit_array.to_string(text) {
        Ok(text) -> Ok(#(text, after))
        Error(Nil) -> Error(NotText(offset: offset(total, bytes)))
      }
    _ -> Error(Truncated(offset: offset(total, bytes)))
  }
}

fn decode_chunks(
  bytes bytes: BitArray,
  total total: Int,
  chunks chunks: List(Chunk),
) -> Result(List(Chunk), RecordingError) {
  case bytes {
    <<>> -> Ok(list.reverse(chunks))
    <<
      direction:size(8),
      microseconds:size(64),
      length:size(32),
      data:bytes-size(length),
      after:bytes,
    >> ->
      case direction_from_byte(direction) {
        Ok(direction) ->
          decode_chunks(bytes: after, total:, chunks: [
            Chunk(direction:, microseconds:, bytes: data),
            ..chunks
          ])
        Error(error) -> Error(error)
      }
    _ -> Error(Truncated(offset: offset(total, bytes)))
  }
}

fn direction_from_byte(value: Int) -> Result(Direction, RecordingError) {
  case value {
    0 -> Ok(ClientToServer)
    1 -> Ok(ServerToClient)
    _ -> Error(UnknownDirection(value:))
  }
}

/// How many bytes of the file come before `rest`, the part of it still to read.
fn offset(total: Int, rest: BitArray) -> Int {
  total - bit_array.byte_size(rest)
}

/// Creates a file at `path` holding the header and no chunk. A file already at
/// `path` is never overwritten.
pub fn create(
  at path: String,
  header header: Header,
) -> Result(Nil, RecordingError) {
  use bytes <- result.try(encode_header(header))
  use Nil <- result.try(case simplifile.create_file(path) {
    Ok(Nil) -> Ok(Nil)
    Error(simplifile.Eexist) -> Error(AlreadyExists(path:))
    Error(error) -> Error(FileFailed(error:))
  })
  simplifile.write_bits(path, bytes) |> result.map_error(FileFailed)
}

/// Adds one chunk to the end of the file at `path`, which `create` made.
pub fn append(
  to path: String,
  chunk chunk: Chunk,
) -> Result(Nil, RecordingError) {
  use bytes <- result.try(encode_chunk(chunk))
  simplifile.append_bits(path, bytes) |> result.map_error(FileFailed)
}

/// The recording in the file at `path`.
pub fn read(from path: String) -> Result(Recording, RecordingError) {
  use bytes <- result.try(
    simplifile.read_bits(path) |> result.map_error(FileFailed),
  )
  decode(bytes)
}
