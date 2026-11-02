//// Writes a connection's wire recording (genesis_prime/wire_recording) to a
//// file, a line for each input the shell takes and each write it makes. A
//// `WireRecorder` is made only by the dev start; the server's own start has
//// none, and a connection with none writes nothing.
////
//// The shell takes each line's sequence number from `runtime.unique_id` as
//// the line's event happens (a write's before the socket is given the bytes)
//// and hands it in, since the runtime module calls this one.

import genesis_prime/step.{type Now}
import genesis_prime/wire_recording.{type Input, type Side}
import gleam/option.{type Option, None, Some}

/// Where and how each connection of a listener is recorded: a folder, and what
/// a recording's header holds besides the rule's name, the seed and the accept
/// ordinal, which the shell gives.
pub opaque type WireRecorder {
  WireRecorder(folder: String, client_build: Int, tables_digest: Option(String))
}

/// One open recording: the path of its file.
pub type WireWriter

/// Why a recording file could not be made or written.
pub type WriteError {
  WriteError(path: String, reason: String)
}

/// A recorder that writes one file for each connection into `folder`. The dev
/// start is its only caller.
pub fn new(
  folder folder: String,
  client_build client_build: Int,
  tables_digest tables_digest: Option(String),
) -> WireRecorder {
  WireRecorder(folder:, client_build:, tables_digest:)
}

/// Opens the recording of one connection when there is a recorder; with none
/// there is no recording. The file is named after the rule and the connection,
/// starts with the header, and a file already there is never overwritten.
pub fn open_if(
  recorder recorder: Option(WireRecorder),
  rule_name _rule_name: String,
  connection _connection: Int,
  accept_ordinal _accept_ordinal: Int,
  seed _seed: BitArray,
) -> Result(Option(WireWriter), WriteError) {
  case recorder {
    None -> Ok(None)
    Some(_) -> panic as "built in the next commit"
  }
}

/// Appends the line of an input the shell is taking, with the `Now` its clock
/// gave it. With no recording open it writes nothing.
pub fn taken(
  writer writer: Option(WireWriter),
  sequence _sequence: Int,
  at _at: Now,
  input _input: Input,
) -> Result(Nil, WriteError) {
  case writer {
    None -> Ok(Nil)
    Some(_) -> panic as "built in the next commit"
  }
}

/// Appends the line of bytes the socket took from the shell, with the sequence
/// number taken before they were given to it. With no recording open it writes
/// nothing.
pub fn sent(
  writer writer: Option(WireWriter),
  sequence _sequence: Int,
  bytes _bytes: BitArray,
) -> Result(Nil, WriteError) {
  case writer {
    None -> Ok(Nil)
    Some(_) -> panic as "built in the next commit"
  }
}

/// Ends the recording when one is open: appends the closing line, naming the
/// side that ended the connection.
pub fn close_if(
  writer writer: Option(WireWriter),
  sequence _sequence: Int,
  by _by: Side,
) -> Result(Nil, WriteError) {
  case writer {
    None -> Ok(Nil)
    Some(_) -> panic as "built in the next commit"
  }
}

/// A sentence that says which file failed and why, for the log.
pub fn describe(error error: WriteError) -> String {
  error.path <> ": " <> error.reason
}
