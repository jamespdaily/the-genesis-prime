//// Prints a wire recording as the messages each side sent, one line each, in
//// the order the node saw them, for a person reading a sitting:
////
//// ```
//// gleam run -m genesis_prime/recording_dump -- <folder or .jsonl> [--from <ms>] [--to <ms>] [--unit <id>]
//// ```
////
//// A folder is every recording in it (a sitting's folder under
//// `~/.genesis-prime/sittings`, or a committed session); a file is one
//// connection. Each line is: the sequence number, the time in milliseconds
//// since the connection's accept, the direction, the connection's file, the
//// depth the message travelled at (genesis_prime/recorded_message), the opcode,
//// the message's name in the schema or `unhandled` when the sender's side of
//// the schema has no message of that number, and the decoded fields as the
//// codec's record holds them. `--from` and `--to` keep the lines whose time is
//// within them; `--unit` keeps the lines with a field named `unit_id`, or
//// ending in `_unit_id`, of that value.
////
//// ```
//// files ─▶ wire_recording.read ─▶ recorded_message.exchange (auth, game) ─▶ entries by sequence ─▶ lines
////                                 recorded_message.read (platform login)
//// ```
////
//// - **Time.** An input line holds the time the shell's clock gave it; a write
////   line holds none, and takes the time of the input before it, whose step
////   wrote it (genesis_prime/wire_recording).
//// - **The platform login** is printed as its clear requests; its bytes after
////   the KeyData request are ciphered under a key the recording does not hold,
////   and its replies have no decoder, so each such line is printed as `not
////   read` with its size.
//// - **A file that does not read** (a sitting still being recorded has no
////   closing line) is named on standard error and the others are printed; a
////   connection whose bytes stop reading prints its messages up to there and a
////   `stopped` line saying why.
////
//// It exits with 2 for arguments it does not take and 1 when no recording
//// reads.

import argv
import genesis_prime/client_connection
import genesis_prime/dev_exit
import genesis_prime/login/sts_connection
import genesis_prime/message/client_message
import genesis_prime/message/server_message
import genesis_prime/message_generator
import genesis_prime/named_fields.{type Names}
import genesis_prime/recorded_message.{
  type Direction, type Failure, type Opened, ClientToServer, ServerToClient,
}
import genesis_prime/wire_recording.{type Recording, Took, Wrote}
import genesis_prime/wire_recording/recorder
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

/// One printed line: a message, a line that could not be read as messages, or
/// the reason a connection's bytes stopped reading.
pub type Entry {
  Entry(
    sequence: Int,
    time_ms: Int,
    direction: Direction,
    connection: String,
    depth: Int,
    /// The message's number; `None` for the platform login, whose requests are
    /// text.
    message_id: Option(Int),
    /// The message's name in the schema, `unhandled`, or for a line that is
    /// not a message, `not read` or `stopped`.
    name: String,
    fields: String,
  )
}

/// Which lines to print.
pub type Filter {
  Filter(from_ms: Option(Int), to_ms: Option(Int), unit_id: Option(Int))
}

/// Prints the recording the arguments name.
pub fn main() -> Nil {
  case parse(argv.load().arguments) {
    Error(Nil) -> {
      io.println_error(
        "usage: gleam run -m genesis_prime/recording_dump -- <folder or .jsonl> [--from <ms>] [--to <ms>] [--unit <id>]",
      )
      dev_exit.halt(2)
    }
    Ok(#(path, filter)) -> {
      let #(connections, unread) = load(path:)
      list.each(unread, fn(unread) { io.println_error(describe_unread(unread)) })
      case connections, named_fields.from_schema_file() {
        [], _ -> {
          io.println_error("no recording read from " <> path)
          dev_exit.halt(1)
        }
        _, Error(failure) -> {
          io.println_error(message_generator.describe_failure(failure))
          dev_exit.halt(1)
        }
        _, Ok(names) -> print(entries(connections:, names:), filter)
      }
    }
  }
}

fn print(entries: List(Entry), filter: Filter) -> Nil {
  list.each(printed(entries:, filter:), io.println)
}

/// The printed lines of the entries the filter keeps.
pub fn printed(
  entries entries: List(Entry),
  filter filter: Filter,
) -> List(String) {
  entries
  |> list.filter(keeps(filter:, entry: _))
  |> list.map(text)
}

/// The path and the filter the command's arguments name, `Error(Nil)` for
/// arguments the command does not take.
pub fn parse(arguments: List(String)) -> Result(#(String, Filter), Nil) {
  case arguments {
    [path, ..options] -> {
      use filter <- result.map(options_of(
        options:,
        filter: Filter(None, None, None),
      ))
      #(path, filter)
    }
    [] -> Error(Nil)
  }
}

fn options_of(
  options options: List(String),
  filter filter: Filter,
) -> Result(Filter, Nil) {
  case options {
    [] -> Ok(filter)
    [option, value, ..rest] -> {
      use number <- result.try(int.parse(value))
      use filter <- result.try(case option {
        "--from" -> Ok(Filter(..filter, from_ms: Some(number)))
        "--to" -> Ok(Filter(..filter, to_ms: Some(number)))
        "--unit" -> Ok(Filter(..filter, unit_id: Some(number)))
        _ -> Error(Nil)
      })
      options_of(options: rest, filter:)
    }
    [_] -> Error(Nil)
  }
}

/// The recordings at `path`, a folder or one file, with the file's name, and a
/// sentence for each file that does not read. Unlike `wire_replay.load`, a
/// folder needs no fixture and a file that does not read leaves the others to
/// be printed.
pub fn load(path path: String) -> #(List(#(String, Recording)), List(Unread)) {
  let files = case simplifile.is_directory(path) {
    Ok(True) ->
      simplifile.read_directory(path)
      |> result.map(fn(names) {
        names
        |> list.filter(string.ends_with(_, recorder.file_suffix))
        |> list.sort(string.compare)
        |> list.map(fn(name) { #(name, path <> "/" <> name) })
      })
    Ok(False) -> Ok([#(file_name(path), path)])
    Error(error) -> Error(error)
  }
  case files {
    Error(error) -> #([], [FileNotRead(path:, error:)])
    Ok(files) -> {
      let read = list.map(files, read_file)
      #(
        result.values(read),
        list.filter_map(read, fn(read) {
          case read {
            Ok(_) -> Error(Nil)
            Error(unread) -> Ok(unread)
          }
        }),
      )
    }
  }
}

/// A recording's file, with its name, or why it did not read.
fn read_file(file: #(String, String)) -> Result(#(String, Recording), Unread) {
  let #(name, file_path) = file
  case simplifile.read(file_path) {
    Error(error) -> Error(FileNotRead(path: file_path, error:))
    Ok(text) ->
      case wire_recording.read(text) {
        Ok(recording) -> Ok(#(name, recording))
        Error(failure) -> Error(NoWholeRecording(path: file_path, failure:))
      }
  }
}

/// Why a file or folder gave no recording.
pub type Unread {
  /// The file or folder does not read.
  FileNotRead(path: String, error: simplifile.FileError)
  /// The file is no whole recording: a sitting still being recorded has no
  /// closing line.
  NoWholeRecording(path: String, failure: wire_recording.ReadFailure)
}

/// A sentence that says which file did not read and why, for a person.
pub fn describe_unread(unread: Unread) -> String {
  case unread {
    FileNotRead(path:, error:) ->
      path <> " does not read: " <> simplifile.describe_error(error)
    NoWholeRecording(path:, failure:) ->
      path <> " is no whole recording: " <> inspected(failure)
  }
}

fn file_name(path: String) -> String {
  case list.last(string.split(path, "/")) {
    Ok(name) -> name
    Error(Nil) -> path
  }
}

/// Every message of the connections, in the order of their sequence numbers.
pub fn entries(
  connections connections: List(#(String, Recording)),
  names names: Names,
) -> List(Entry) {
  list.flat_map(connections, fn(connection) {
    let #(name, recording) = connection
    connection_entries(name:, recording:, names:)
  })
  |> list.sort(fn(first, second) {
    int.compare(first.sequence, second.sequence)
  })
}

/// The sequence number and the time since the accept of each line, by its
/// number from 1.
type Clock =
  Dict(Int, #(Int, Int))

fn clock(recording: Recording) -> Clock {
  let accepted_ms =
    list.find_map(recording.lines, fn(line) {
      case line {
        Took(at:, ..) -> Ok(at.monotonic_ms)
        Wrote(..) -> Error(Nil)
      }
    })
    |> result.unwrap(0)
  list.index_fold(
    recording.lines,
    #(dict.new(), accepted_ms),
    fn(state, line, index) {
      let #(times, last_ms) = state
      let #(sequence, at_ms) = case line {
        Took(sequence:, at:, ..) -> #(sequence, at.monotonic_ms)
        Wrote(sequence:, ..) -> #(sequence, last_ms)
      }
      #(dict.insert(times, index + 1, #(sequence, at_ms - accepted_ms)), at_ms)
    },
  ).0
}

fn connection_entries(
  name name: String,
  recording recording: Recording,
  names names: Names,
) -> List(Entry) {
  let connection = string.replace(name, recorder.file_suffix, "")
  let times = clock(recording)
  let entry = fn(line, direction, depth, message_id, name, fields) {
    let #(sequence, time_ms) = dict.get(times, line) |> result.unwrap(#(0, 0))
    Entry(
      sequence:,
      time_ms:,
      direction:,
      connection:,
      depth:,
      message_id:,
      name:,
      fields:,
    )
  }
  case recording.header.rule == sts_connection.rule_name {
    True -> platform_login_entries(name:, recording:, entry:)
    False -> {
      let exchange = recorded_message.exchange(name:, recording:)
      let messages =
        list.map(exchange.opened, fn(opened) {
          let #(message_name, fields) = named(opened:, names:)
          entry(
            opened.line,
            opened.direction,
            opened.depth,
            Some(opened.message_id),
            message_name,
            fields,
          )
        })
      list.append(messages, stopped_entries(exchange.stopped, entry))
    }
  }
}

/// The name and the fields of a message: a carrier's body is the next line's
/// frame, so its fields are left out.
fn named(opened opened: Opened, names names: Names) -> #(String, String) {
  case opened.reading {
    recorded_message.ClientSent(message:) ->
      case recorded_message.carries_a_frame(message) {
        True -> #(client_message.name(message), "")
        False -> #(client_message.name(message), record_of(message, names))
      }
    recorded_message.ServerSent(message:) -> #(
      server_message.name(message),
      record_of(message, names),
    )
    recorded_message.WithoutDecoder -> #(
      "unhandled",
      int.to_string(bit_array.byte_size(opened.body)) <> " bytes",
    )
    recorded_message.Malformed(error:) -> #(
      "malformed",
      inspected(error) <> " in " <> bit_array.base16_encode(opened.body),
    )
  }
}

fn stopped_entries(
  stopped: Option(Failure),
  entry: fn(Int, Direction, Int, Option(Int), String, String) -> Entry,
) -> List(Entry) {
  case stopped {
    None -> []
    Some(recorded_message.NotRead(line:, problem:, ..)) -> [
      entry(line, ClientToServer, 0, None, "stopped", inspected(problem)),
    ]
  }
}

/// The platform login's clear requests, then each line it does not read.
fn platform_login_entries(
  name name: String,
  recording recording: Recording,
  entry entry: fn(Int, Direction, Int, Option(Int), String, String) -> Entry,
) -> List(Entry) {
  let lines =
    list.index_map(recording.lines, fn(line, index) { #(index + 1, line) })
  let unread = fn(read_lines: List(Int)) {
    list.filter_map(lines, fn(numbered) {
      case numbered.1 {
        Took(input: wire_recording.Read(bytes:), ..) ->
          case list.contains(read_lines, numbered.0) {
            True -> Error(Nil)
            False ->
              Ok(entry(
                numbered.0,
                ClientToServer,
                0,
                None,
                "not read",
                size(bytes),
              ))
          }
        Wrote(bytes:, ..) ->
          Ok(entry(numbered.0, ServerToClient, 0, None, "not read", size(bytes)))
        Took(..) -> Error(Nil)
      }
    })
  }
  case recorded_message.read(name:, recording:) {
    Ok(Some(recorded_message.PlatformLogin(requests:, ..))) -> {
      let read_lines = list.map(requests, fn(request) { request.0 })
      list.append(
        list.map(requests, fn(request) {
          let #(line, requested) = request
          case requested {
            recorded_message.Decoded(request:) ->
              entry(
                line,
                ClientToServer,
                0,
                None,
                "sts_request",
                inspected(request),
              )
            recorded_message.NoDecoder(protocol:, command:) ->
              entry(
                line,
                ClientToServer,
                0,
                None,
                "unhandled",
                protocol <> "/" <> command,
              )
          }
        }),
        unread(read_lines),
      )
    }
    Ok(Some(recorded_message.FramesRead(..))) | Ok(None) -> unread([])
    Error(failure) ->
      list.append(unread([]), stopped_entries(Some(failure), entry))
  }
}

fn size(bytes: BitArray) -> String {
  int.to_string(bit_array.byte_size(bytes)) <> " bytes"
}

/// The record a dispatch variant holds, with its fields named from the
/// schema (genesis_prime/named_fields).
fn record_of(variant: variant, names: Names) -> String {
  named_fields.inside(text: inspected(variant), names:)
}

/// A value as the runtime prints it. The dump prints each decoded message
/// field by field as its record holds it, which only the runtime's inspect does
/// for every message of the schema.
fn inspected(value: value) -> String {
  string.inspect(value)
}

/// Whether the filter keeps the entry.
fn keeps(filter filter: Filter, entry entry: Entry) -> Bool {
  let after = case filter.from_ms {
    Some(from_ms) -> entry.time_ms >= from_ms
    None -> True
  }
  let before = case filter.to_ms {
    Some(to_ms) -> entry.time_ms <= to_ms
    None -> True
  }
  let of_unit = case filter.unit_id {
    Some(unit_id) -> {
      let field = "unit_id: " <> int.to_string(unit_id)
      string.contains(entry.fields, field <> ",")
      || string.contains(entry.fields, field <> ")")
    }
    None -> True
  }
  after && before && of_unit
}

/// The printed line of an entry.
fn text(entry: Entry) -> String {
  let direction = case entry.direction {
    ClientToServer -> "client→server"
    ServerToClient -> "server→client"
  }
  let opcode = case entry.message_id {
    Some(message_id) -> client_connection.message_text(message_id:)
    None -> "sts"
  }
  string.join(
    [
      int.to_string(entry.sequence),
      "+" <> int.to_string(entry.time_ms) <> "ms",
      direction,
      entry.connection,
      "depth " <> int.to_string(entry.depth),
      opcode,
      entry.name,
      entry.fields,
    ],
    " ",
  )
}
