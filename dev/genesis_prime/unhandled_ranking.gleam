//// Ranks the messages the client sent in recorded sittings that the server
//// does not handle, most frequent first, to choose what to build next:
////
//// ```
//// gleam run -m genesis_prime/unhandled_ranking -- <folder>...
//// ```
////
//// Each folder is a sitting's (`~/.genesis-prime/sittings/<date>-<topic>`) or a
//// committed session's. Each line is: how many times the client sent the
//// message across the folders, its opcode, its system's group, and its name in
//// the schema or `no decoder`.
////
//// ```
//// folders ─▶ recording_dump.load ─▶ recorded_message.exchange ─▶ the client's messages
////         ─▶ those whose id no rule names (coverage/engine.handled_client_message_ids)
////         ─▶ counted by id ─▶ lines, most first
//// ```
////
//// - **Unhandled** is the coverage measure's reading: an id no rule names, which
////   the server logs as unhandled wherever it arrives. A carrier is handled, and
////   the message inside it is counted on its own.
//// - **The group** is the system of the roadmap the message belongs to
////   (`groups`), for a message whose sender the client's code names; any
////   other prints `no group`.
//// - A file that does not read, or a connection whose bytes stop reading, is
////   named on standard error, and the messages read before it are counted.
//// - A recording still being written (no closing line yet, its last line
////   perhaps cut) is read up to its last whole line, counted, and named on
////   standard error as having no closing line yet.
////
//// It exits with 2 when no folder is given and 1 when no recording reads.

import argv
import genesis_prime/client_connection
import genesis_prime/coverage/engine
import genesis_prime/dev_exit
import genesis_prime/login/sts_connection
import genesis_prime/message/client_message
import genesis_prime/recorded_message.{type Opened, ClientToServer}
import genesis_prime/recording_dump
import genesis_prime/wire_recording.{type Recording}
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string

/// One message the server does not handle: its number, how many times the
/// client sent it, and its name in the schema when it has one.
type Unhandled {
  Unhandled(message_id: Int, count: Int, name: Option(String))
}

/// Prints the ranking of the folders the arguments name.
pub fn main() -> Nil {
  case argv.load().arguments {
    [] -> {
      io.println_error(
        "usage: gleam run -m genesis_prime/unhandled_ranking -- <folder>...",
      )
      dev_exit.halt(2)
    }
    folders -> {
      let loaded = list.map(folders, fn(folder) { recording_dump.load(folder) })
      list.flat_map(loaded, fn(loaded) { loaded.1 })
      |> list.each(fn(unread) {
        io.println_error(recording_dump.describe_unread(unread))
      })
      case list.flat_map(loaded, fn(loaded) { loaded.0 }) {
        [] -> {
          io.println_error(
            "no recording read from " <> string.join(folders, ", "),
          )
          dev_exit.halt(1)
        }
        connections -> print(ranking(connections))
      }
    }
  }
}

fn print(ranking: #(List(String), List(String))) -> Nil {
  let #(lines, stopped) = ranking
  list.each(stopped, io.println_error)
  list.each(lines, io.println)
}

/// The printed lines of the client's messages no rule names, most frequent
/// first and by opcode among equals, and a sentence for each connection whose
/// bytes stopped reading, and one for each connection that has no closing line
/// yet.
pub fn ranking(
  connections: List(#(String, Recording)),
) -> #(List(String), List(String)) {
  let handled = engine.handled_client_message_ids()
  let exchanges =
    list.filter_map(connections, fn(connection) {
      let #(name, recording) = connection
      case recording.header.rule == sts_connection.rule_name {
        True -> Error(Nil)
        False -> Ok(recorded_message.exchange(name:, recording:))
      }
    })
  let counted =
    list.flat_map(exchanges, fn(exchange) { exchange.opened })
    |> list.filter(fn(opened) {
      opened.direction == ClientToServer
      && !list.contains(handled, opened.message_id)
    })
    |> list.fold(dict.new(), count)
  let ranked =
    dict.values(counted)
    |> list.sort(fn(first, second) {
      int.compare(second.count, first.count)
      |> order.break_tie(int.compare(first.message_id, second.message_id))
    })
  let stopped =
    list.filter_map(exchanges, fn(exchange) {
      case exchange.stopped {
        Some(recorded_message.NotRead(connection:, line:, problem:)) ->
          Ok(
            connection
            <> " stopped reading at line "
            <> int.to_string(line)
            <> ": "
            <> inspected(problem),
          )
        None -> Error(Nil)
      }
    })
  let unfinished =
    list.filter_map(connections, fn(connection) {
      let #(name, recording) = connection
      case recording.closing {
        None -> Ok(name <> " has no closing line yet")
        Some(_) -> Error(Nil)
      }
    })
  #(list.map(ranked, line), list.append(stopped, unfinished))
}

fn count(
  counted: Dict(Int, Unhandled),
  opened: Opened,
) -> Dict(Int, Unhandled) {
  let name = case opened.reading {
    recorded_message.ClientSent(message:) -> Some(client_message.name(message))
    recorded_message.ServerSent(..)
    | recorded_message.WithoutDecoder
    | recorded_message.Malformed(..) -> None
  }
  dict.upsert(counted, opened.message_id, fn(found) {
    case found {
      Some(found) -> Unhandled(..found, count: found.count + 1)
      None -> Unhandled(message_id: opened.message_id, count: 1, name:)
    }
  })
}

/// The printed line of a ranked message.
fn line(unhandled: Unhandled) -> String {
  string.join(
    [
      string.pad_start(int.to_string(unhandled.count), 7, " "),
      client_connection.message_text(message_id: unhandled.message_id),
      option.unwrap(group_of(unhandled.message_id), "no group"),
      option.unwrap(unhandled.name, "no decoder"),
    ],
    "  ",
  )
}

/// The system of the roadmap a client message belongs to.
fn group_of(message_id: Int) -> Option(String) {
  list.key_find(groups, message_id) |> option.from_result
}

/// Each message id whose sender the client's code names, with its system's
/// group: the roadmap's systems by number and name, or the client's feature
/// for a message no system holds.
const groups = [
  // The answer to 0x0636, which hands the player its unit on entering the
  // world (opcode.0x635).
  #(0x0635, "1 log in, enter world, move"),
  // Sent by the cast of a creature's activate spell (0x14039c430).
  #(0x0097, "7 quests, zones, prerequisites"),
  // The store-catalog request (opcode.0x82d).
  #(0x082D, "the store: no roadmap system"),
]

/// A problem as the runtime prints it, for a person reading why a connection
/// stopped.
fn inspected(value: value) -> String {
  string.inspect(value)
}
