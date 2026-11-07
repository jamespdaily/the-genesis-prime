//// The unhandled ranking counts the messages the client sent that no rule
//// names, across the connections of a folder. Expected values come from these
//// places.
//// - The routing: the network layer's ping (0x0000) and the client's wrapper
////   (0x0244) are taken by every connection, and 0x038C is taken by the game
////   rule (`coverage/engine.handled_client_message_ids`); no rule names 0x023C
////   (the client sends it through SendWorldMessage 0x1403f4900) or 0x0FFF.
//// - 0x082D is the store-catalog request (opcode.0x82d), which no roadmap
////   system holds.
//// - The folder is a planted session of two game connections and one cut
////   connection, written into a folder of its own and read back, as
////   `wire_client_message_test`'s recordings are.

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/connection as game_connection
import genesis_prime/message/world_message.{WorldMessage}
import genesis_prime/recording_dump
import genesis_prime/unhandled_ranking
import genesis_prime/wire_recording.{Accepted, Client, Read}
import gleam/bit_array
import gleam/list
import gleam/string
import owned_test
import recording_support
import unitest
import wire_replay_support as support

/// A message the client sends in its wrapper, under the base key.
fn sent(id id: Int, body body: BitArray) -> BitArray {
  let assert Ok(bytes) =
    encrypted_frame.wrap(
      encrypted_frame.ClientWrapper,
      Frame(message_id: id, body:),
      cipher.base(),
    )
    as "the frame is within the size limit"
  bytes
}

/// A message the client sends inside a 0x038C, as the client sends world
/// messages.
fn carried(id id: Int) -> BitArray {
  let assert Ok(inner) = frame.encode(message_id: id, body: <<>>)
    as "the frame is within the size limit"
  let assert Ok(body) =
    world_message.encode(WorldMessage(field_1: 0, inner_frame: inner))
    as "the carrier encodes"
  sent(id: 0x038C, body:)
}

/// The ranked lines and the stopped sentences of a planted folder: the first
/// connection sends 0x023C twice, once inside a carrier, 0x082D once, 0x0FFF
/// once and the network layer's ping three times; the second sends 0x0FFF
/// twice and 0x0FFE once and the server writes a message; the third ends inside
/// a frame after one 0x0FFE.
fn planted_ranking(folder: String) -> #(List(String), List(String)) {
  let assert Ok(ping) = frame.encode(message_id: 0x0000, body: <<3>>)
    as "a ping is within the size limit"
  let assert Ok(server_message) = frame.encode(message_id: 0x0FFF, body: <<1>>)
    as "a frame is within the size limit"
  let whole = sent(id: 0x0FFE, body: <<>>)
  let assert Ok(cut) = bit_array.slice(whole, 0, bit_array.byte_size(whole) - 1)
    as "the frame is longer than one byte"
  let planted = fn(ordinal) {
    support.Planted(
      rule: game_connection.rule_name,
      seed: support.seed(ordinal),
      ordinal:,
    )
  }
  support.write(
    folder:,
    connections: [planted(1), planted(2), planted(3)],
    steps: [
      support.In(0, support.now_at(1), Accepted),
      support.In(1, support.now_at(2), Accepted),
      support.In(2, support.now_at(3), Accepted),
      support.In(0, support.now_at(4), Read(sent(id: 0x023C, body: <<>>))),
      support.In(0, support.now_at(5), Read(carried(id: 0x023C))),
      support.In(0, support.now_at(6), Read(sent(id: 0x082D, body: <<>>))),
      support.In(0, support.now_at(7), Read(sent(id: 0x0FFF, body: <<>>))),
      support.In(0, support.now_at(8), Read(ping)),
      support.In(0, support.now_at(9), Read(<<ping:bits, ping:bits>>)),
      support.In(1, support.now_at(10), Read(sent(id: 0x0FFF, body: <<>>))),
      support.Out(1, server_message),
      support.In(1, support.now_at(11), Read(sent(id: 0x0FFF, body: <<>>))),
      support.In(1, support.now_at(12), Read(sent(id: 0x0FFE, body: <<>>))),
      support.In(2, support.now_at(13), Read(whole)),
      support.In(2, support.now_at(14), Read(cut)),
      support.Closed(0, Client),
      support.Closed(1, Client),
      support.Closed(2, Client),
    ],
  )
  support.load(folder).connections
  |> list.map(fn(connection) { #(connection.name, connection.recording) })
  |> unhandled_ranking.ranking
}

/// The words of a ranked line: its count, opcode, group and name.
fn columns(line: String) -> List(String) {
  string.trim(line) |> string.split("  ")
}

pub fn the_ranking_counts_each_unhandled_message_across_the_connections_most_frequent_first_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("dev_tool")
  use folder <- recording_support.in_folder
  let #(lines, _) = planted_ranking(folder)
  assert list.map(lines, columns)
    == [
      ["3", "0x0FFF", "no group", "no decoder"],
      ["2", "0x023C", "no group", "no decoder"],
      ["2", "0x0FFE", "no group", "no decoder"],
      ["1", "0x082D", "the store: no roadmap system", "no decoder"],
    ]
    as "0x0FFF 3 times, 0x023C twice (once inside the carrier 0x038C), and 0x0FFE twice, listed by opcode among equals; the ping, the wrapper and the carrier are handled, and the server's write is no message of the client"
}

pub fn a_connection_whose_bytes_stop_is_named_and_the_messages_before_it_are_counted_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("dev_tool")
  use folder <- recording_support.in_folder
  let #(lines, stopped) = planted_ranking(folder)
  let assert [sentence] = stopped
    as "one connection stopped, and the others did not"
  assert string.contains(sentence, "stopped reading at line")
  assert string.contains(sentence, "CutShort")
    as "the recording ends inside a frame"
  assert list.any(lines, fn(line) {
    columns(line) == ["2", "0x0FFE", "no group", "no decoder"]
  })
    as "the 0x0FFE before the cut is counted, with the other connection's"
}

pub fn a_folder_with_no_unhandled_message_ranks_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("dev_tool")
  use folder <- recording_support.in_folder
  let assert Ok(ping) = frame.encode(message_id: 0x0000, body: <<3>>)
    as "a ping is within the size limit"
  support.write(
    folder:,
    connections: [
      support.Planted(
        rule: game_connection.rule_name,
        seed: support.seed(1),
        ordinal: 1,
      ),
    ],
    steps: [
      support.In(0, support.now_at(1), Accepted),
      support.In(0, support.now_at(2), Read(ping)),
      support.Closed(0, Client),
    ],
  )
  let connections =
    support.load(folder).connections
    |> list.map(fn(connection) { #(connection.name, connection.recording) })
  assert unhandled_ranking.ranking(connections) == #([], [])
    as "a ping is the network layer's"
  assert recording_dump.load(folder).1 == [] as "the folder reads whole"
}

pub fn a_recording_with_no_closing_line_is_counted_and_named_as_unfinished_test() -> Nil {
  use <- owned_test.run(30_000)
  use <- unitest.tag("dev_tool")
  use folder <- recording_support.in_folder
  support.write(
    folder:,
    connections: [
      support.Planted(
        rule: game_connection.rule_name,
        seed: support.seed(1),
        ordinal: 1,
      ),
    ],
    steps: [
      support.In(0, support.now_at(1), Accepted),
      support.In(0, support.now_at(2), Read(sent(id: 0x0FFF, body: <<>>))),
      support.In(0, support.now_at(3), Read(sent(id: 0x0FFF, body: <<>>))),
    ],
  )
  let #(connections, unread) = recording_dump.load(folder)
  assert unread == []
    as "a recording still being written reads up to its last whole line"
  let #(lines, notes) = unhandled_ranking.ranking(connections)
  assert list.map(lines, columns) == [["2", "0x0FFF", "no group", "no decoder"]]
    as "the messages read before the end are counted"
  let assert [note] = notes as "one connection is unfinished"
  assert string.contains(note, "has no closing line yet")
}
