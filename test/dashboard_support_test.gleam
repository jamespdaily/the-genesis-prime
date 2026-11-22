//// The dashboard tests' own websocket reader: a frame the server writes with
//// the handshake's head is read, and bytes that are not a text frame fail the
//// read at once. The server is a planted peer (`frame_peer`) that writes
//// the bytes of a row in one send, as a server whose first frame reaches the
//// client with the head does. A handshake the server answers 503 is asked again
//// until another answer comes.

import dashboard_support
import frame_peer
import gleam/bit_array
import gleam/erlang/process
import gleam/list
import owned_test

const upgrade_head =
  "HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n"

/// Opens a connection to a peer that writes `bytes` once it accepts.
fn connected_to_peer_writing(bytes: BitArray) -> dashboard_support.Connection {
  let #(listener, port) = frame_peer.listen()
  frame_peer.write_once_accepted(listener, bytes)
  let #(connection, reply) =
    dashboard_support.handshake(port:, path: "/", headers: [])
  assert reply.status == 101
  connection
}

/// The first frame reaches the client in the same write as the head, so the
/// read that ends the head holds the frame too (the dashboard's first frame, the
/// mount, is written right after the upgrade's 101).
pub fn a_frame_that_arrives_with_the_handshake_is_read_test() -> Nil {
  use <- owned_test.run(5000)
  let payload = bit_array.from_string("<main>the mount</main>")
  let frame = <<0x81, bit_array.byte_size(payload), payload:bits>>
  let connection = connected_to_peer_writing(<<upgrade_head:utf8, frame:bits>>)
  assert dashboard_support.read_frame(connection) == payload
  dashboard_support.close(connection)
}

/// A close frame (RFC 6455 opcode 8), a binary frame (opcode 2) and the HTTP
/// answer mist writes on an upgraded connection when its websocket process
/// does not start are not text frames; each fails with its first byte.
pub fn a_frame_that_is_not_text_fails_the_read_test() -> Nil {
  use <- owned_test.run(5000)
  let rows = [
    #("a close frame", <<0x88, 0x00>>, 0x88),
    #("a binary frame", <<0x82, 0x02, 0x01, 0x02>>, 0x82),
    #(
      "an HTTP answer",
      bit_array.from_string(
        "HTTP/1.1 400 Bad Request\r\ncontent-length: 0\r\n\r\n",
      ),
      0x48,
    ),
  ]
  list.each(rows, fn(row) {
    let connection =
      connected_to_peer_writing(<<upgrade_head:utf8, row.1:bits>>)
    assert dashboard_support.try_read_frame(connection) == Error(row.2) as row.0
    dashboard_support.close(connection)
  })
}

/// A server that answers each connection it accepts with the next of `replies`
/// and keeps the connections open until the test's process ends. Gives its
/// port.
fn answering_in_turn(replies: List(BitArray)) -> Int {
  let #(listener, port) = frame_peer.listen()
  let owner = process.self()
  let _peer =
    process.spawn(fn() {
      list.each(replies, fn(reply) {
        frame_peer.write(frame_peer.accept(listener), reply)
      })
      process.new_selector()
      |> process.select_specific_monitor(process.monitor(owner), fn(_down) {
        Nil
      })
      |> process.selector_receive_forever
    })
  port
}

fn http_answer(status_line: String) -> BitArray {
  bit_array.from_string(
    "HTTP/1.1 " <> status_line <> "\r\ncontent-length: 0\r\n\r\n",
  )
}

/// The dashboard answers 503 to a handshake whose runtime did not start, and a
/// client asks again. Each ask is a new connection; the connection of an answer
/// that asks again is closed, and the connection of the answer that ends the
/// asking is the caller's.
pub fn a_handshake_answered_503_is_asked_again_until_another_answer_comes_test() -> Nil {
  use <- owned_test.run(5000)
  let port =
    answering_in_turn([
      http_answer("503 Service Unavailable"),
      http_answer("503 Service Unavailable"),
      http_answer("400 Bad Request"),
    ])
  let asked = process.new_subject()
  let #(connection, reply) =
    dashboard_support.asked_until_started(fn() {
      let #(connection, reply) =
        dashboard_support.handshake(port:, path: "/", headers: [])
      process.send(asked, connection)
      #(connection, reply)
    })
  assert reply.status == 400
  // The asks ran in this process, so each connection is already in its mailbox.
  let connections = sent_so_far(asked)
  assert list.length(connections) == 3
    as "the 400 came after three asks, not before"
  assert list.map(connections, dashboard_support.is_closed)
    == [True, True, False]
    as "the connections of the two 503 answers are closed and the third is the caller's"
  dashboard_support.close(connection)
}

fn sent_so_far(subject: process.Subject(a)) -> List(a) {
  case process.receive(subject, 0) {
    Ok(message) -> [message, ..sent_so_far(subject)]
    Error(Nil) -> []
  }
}
