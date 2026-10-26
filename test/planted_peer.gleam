//// A server the test plants, to be replayed against: it listens on a free
//// loopback port, accepts one connection and plays a script over it. For each
//// client chunk of the script it reads that many bytes, and for each server
//// chunk it sends those bytes, in the script's order. When the script ends it
//// reports every byte the client sent and its process ends, which closes the
//// connection.

import genesis_prime/recording.{type Chunk, ClientToServer, ServerToClient}
import genesis_prime/recording/listener
import gleam/bit_array
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/result
import mug

/// A planted server that is listening: its port, and where it reports once
/// its script has played. The report is the bytes the client sent, in order,
/// or why the script could not play to its end.
pub type Peer {
  Peer(port: Int, report: Subject(Result(BitArray, mug.Error)))
}

/// Starts a planted server that plays `script`, linked to the caller. It
/// returns once the server listens. Every wait of the script takes at most
/// `wait_ms` milliseconds.
pub fn start(script script: List(Chunk), wait_ms wait_ms: Int) -> Peer {
  let listening = process.new_subject()
  let report = process.new_subject()
  process.spawn(fn() {
    let assert Ok(socket) = listener.listen(bind: listener.Loopback, port: 0)
      as "the planted peer did not listen"
    let assert Ok(port) = listener.port(socket)
      as "the planted peer has no port"
    process.send(listening, port)
    process.send(report, play(socket:, script:, wait_ms:))
  })
  let assert Ok(port) = process.receive(listening, within: wait_ms)
    as "the planted peer did not start listening"
  Peer(port:, report:)
}

fn play(
  socket socket: listener.Listener,
  script script: List(Chunk),
  wait_ms wait_ms: Int,
) -> Result(BitArray, mug.Error) {
  use connection <- result.try(listener.accept_within(socket, within: wait_ms))
  list.try_fold(script, <<>>, fn(heard, chunk) {
    case chunk.direction {
      ClientToServer ->
        mug.receive_exact(
          connection,
          byte_size: bit_array.byte_size(chunk.bytes),
          timeout_milliseconds: wait_ms,
        )
        |> result.map(fn(bytes) { <<heard:bits, bytes:bits>> })
      ServerToClient ->
        mug.send(connection, chunk.bytes) |> result.replace(heard)
    }
  })
}
