//// Writes a connection's recording to a file, record by record as the shell
//// takes each input, in the layout of genesis_prime/rule_recording. A
//// `Recorder` is made only by the dev start; the server's own start has none.

import genesis_prime/rule_recording.{type Header, type Record, End}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

/// Where and how each connection of a listener is recorded: a folder, and the
/// header every recording starts with.
pub opaque type Recorder(settings) {
  Recorder(folder: String, header: Header(settings))
}

/// One open recording: its path and how many inputs it holds.
pub opaque type Writer {
  Writer(path: String, count: Int)
}

/// Why a recording file could not be made or written.
pub type FileError {
  FileError(path: String, reason: String)
}

/// A recorder that writes one file per connection into `folder`. The dev
/// start is its only caller.
pub fn recorder(
  folder folder: String,
  header header: Header(settings),
) -> Recorder(settings) {
  Recorder(folder:, header:)
}

/// Makes the file of one connection, named after the rule and the
/// connection, and writes its header. A file already there is never
/// overwritten.
fn open(
  recorder recorder: Recorder(settings),
  connection connection: Int,
) -> Result(Writer, FileError) {
  let path =
    recorder.folder
    <> "/"
    <> string.replace(recorder.header.rule, "/", ".")
    <> "-"
    <> int.to_string(connection)
    <> ".recording"
  let failed = fn(error) {
    FileError(path:, reason: simplifile.describe_error(error))
  }
  use Nil <- result.try(
    simplifile.create_directory_all(recorder.folder) |> result.map_error(failed),
  )
  use Nil <- result.try(
    simplifile.create_file(path) |> result.map_error(failed),
  )
  use Nil <- result.map(
    simplifile.write_bits(path, rule_recording.encode(recorder.header))
    |> result.map_error(failed),
  )
  Writer(path:, count: 0)
}

/// Appends one input's record.
fn append(
  writer writer: Writer,
  record record: Record(message, answer, outgoing, request),
) -> Result(Writer, FileError) {
  simplifile.append_bits(writer.path, rule_recording.encode(record))
  |> result.map(fn(_) { Writer(..writer, count: writer.count + 1) })
  |> result.map_error(fn(error) {
    FileError(path: writer.path, reason: simplifile.describe_error(error))
  })
}

/// Writes `End` with the count of inputs.
fn finish(writer: Writer) -> Result(Nil, FileError) {
  let end: Record(Nil, Nil, Nil, Nil) = End(count: writer.count)
  simplifile.append_bits(writer.path, rule_recording.encode(end))
  |> result.map_error(fn(error) {
    FileError(path: writer.path, reason: simplifile.describe_error(error))
  })
}

/// Opens the recording of one connection when there is a recorder; with none
/// there is no recording.
pub fn open_if(
  recorder recorder: Option(Recorder(settings)),
  connection connection: Int,
) -> Result(Option(Writer), FileError) {
  case recorder {
    None -> Ok(None)
    Some(recorder) -> result.map(open(recorder:, connection:), Some)
  }
}

/// Appends the record when a recording is open; with none there is nothing to
/// write.
pub fn append_if(
  writer writer: Option(Writer),
  record record: Record(message, answer, outgoing, request),
) -> Result(Option(Writer), FileError) {
  case writer {
    None -> Ok(None)
    Some(writer) -> result.map(append(writer:, record:), Some)
  }
}

/// Ends the recording when one is open.
pub fn finish_if(writer writer: Option(Writer)) -> Result(Nil, FileError) {
  case writer {
    None -> Ok(Nil)
    Some(writer) -> finish(writer)
  }
}

/// A sentence that says which file failed and why, for the log.
pub fn describe(error error: FileError) -> String {
  error.path <> ": " <> error.reason
}
