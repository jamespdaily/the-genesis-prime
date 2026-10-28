//// Writes a connection's recording to a file, record by record as the shell
//// takes each input, in the layout of genesis_prime/rule_recording. A
//// `Recorder` is made only by the dev start; the server's own start has none.

import genesis_prime/rule_recording.{type Record, End, Header, Taken}
import genesis_prime/step.{type Event, type Now, type Rule, type Step, Input}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

/// Where and how each connection of a listener is recorded: a folder, and what
/// a recording's header holds besides the rule's name and settings, which the
/// shell takes from the rule it runs.
pub opaque type Recorder {
  Recorder(
    folder: String,
    client_build: Int,
    tables_digest: Option(String),
    types_digest: String,
  )
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
  client_build client_build: Int,
  tables_digest tables_digest: Option(String),
  types_digest types_digest: String,
) -> Recorder {
  Recorder(folder:, client_build:, tables_digest:, types_digest:)
}

/// Opens the recording of one connection when there is a recorder; with none
/// there is no recording. The file is named after the rule and the connection
/// and starts with the header of `rule`; a file already there is never
/// overwritten.
pub fn open_if(
  recorder recorder: Option(Recorder),
  rule rule: Rule(settings, state, message, answer, outgoing, request),
  connection connection: Int,
) -> Result(Option(Writer), FileError) {
  case recorder {
    None -> Ok(None)
    Some(recorder) -> {
      let path =
        recorder.folder
        <> "/"
        <> string.replace(rule.name, "/", ".")
        <> "-"
        <> int.to_string(connection)
        <> ".recording"
      let header =
        Header(
          format: rule_recording.format,
          rule: rule.name,
          client_build: recorder.client_build,
          tables_digest: recorder.tables_digest,
          settings: rule.settings,
          types_digest: recorder.types_digest,
        )
      use Nil <- result.try(
        simplifile.create_directory_all(recorder.folder)
        |> result.map_error(failed(path)),
      )
      use Nil <- result.try(
        simplifile.create_file(path) |> result.map_error(failed(path)),
      )
      use Nil <- result.map(
        simplifile.write_bits(path, rule_recording.encode(header))
        |> result.map_error(failed(path)),
      )
      Some(Writer(path:, count: 0))
    }
  }
}

/// Folds one input through the rule and, when a recording is open, appends the
/// `Taken` record before anything of the step is carried out. A record that
/// cannot be written is an error, and the new state is not returned.
pub fn fold(
  rule rule: Rule(settings, state, message, answer, outgoing, request),
  state state: state,
  writer writer: Option(Writer),
  now now: Now,
  event event: Event(message, answer),
) -> Result(#(state, Step(outgoing, request), Option(Writer)), FileError) {
  let input = Input(now:, event:)
  let #(state, step) = rule.step(state, input)
  use writer <- result.map(case writer {
    None -> Ok(None)
    Some(writer) -> {
      simplifile.append_bits(
        writer.path,
        rule_recording.encode(Taken(input:, step:)),
      )
      |> result.map(fn(_) { Some(Writer(..writer, count: writer.count + 1)) })
      |> result.map_error(failed(writer.path))
    }
  })
  #(state, step, writer)
}

/// Ends the recording when one is open: writes `End` with the count of
/// inputs.
pub fn finish_if(writer writer: Option(Writer)) -> Result(Nil, FileError) {
  case writer {
    None -> Ok(Nil)
    Some(writer) -> {
      let end: Record(Nil, Nil, Nil, Nil) = End(count: writer.count)
      simplifile.append_bits(writer.path, rule_recording.encode(end))
      |> result.map_error(failed(writer.path))
    }
  }
}

/// A sentence that says which file failed and why, for the log.
pub fn describe(error error: FileError) -> String {
  error.path <> ": " <> error.reason
}

fn failed(path: String) -> fn(simplifile.FileError) -> FileError {
  fn(error) { FileError(path:, reason: simplifile.describe_error(error)) }
}
