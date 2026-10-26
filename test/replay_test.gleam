//// The replay of a recording over TCP. Expected values come from the issue of
//// the recording step: a replay opens a connection to the server, sends the
//// client's chunks in order, waits for each server chunk by its bytes with a
//// deadline, and reports the first difference with its offset in the stream of
//// everything the server sent; a server that answers one byte differently
//// fails the replay at that byte.
////
//// The planted recording is made of random bytes, sized as the comments say,
//// because the replay compares bytes and never reads them. The planted server
//// sends two server chunks back to back, so the replay is shown to match the
//// server's stream, not its packets. Every wait is for an event, a connection
//// or a chunk, with a deadline that a passing test never reaches.

import genesis_prime/recording.{
  type Chunk, type Recording, Chunk, ClientToServer, Recording, ServerToClient,
}
import gleam/bit_array
import gleam/erlang/process
import gleam/list
import mug
import owned_test
import planted_peer
import recording_support
import replay.{Differs, ExtraBytes, Target}
import seeded

/// How long one wait for an event may take, in milliseconds.
const event_wait_ms = 5000

/// The planted recording's chunks, in order, with their sizes in bytes:
/// client 30, server 47, server 5, client 200, server 1000, client 7. Their
/// positions in the recording are 0 to 5, and the server's stream is its three
/// chunks one after another: 1052 bytes, the third starting at offset 52.
fn planted_recording() -> Recording {
  let sizes = [
    #(ClientToServer, 30),
    #(ServerToClient, 47),
    #(ServerToClient, 5),
    #(ClientToServer, 200),
    #(ServerToClient, 1000),
    #(ClientToServer, 7),
  ]
  let #(chunks, _) =
    list.fold(sizes, #([], 72), fn(built, size) {
      let #(chunks, random) = built
      let #(bytes, random) = seeded.bytes(state: random, count: size.1)
      #([Chunk(size.0, 0, bytes), ..chunks], random)
    })
  Recording(header: recording_support.header(), chunks: list.reverse(chunks))
}

fn client_bytes(chunks: List(Chunk)) -> BitArray {
  list.filter(chunks, fn(chunk) { chunk.direction == ClientToServer })
  |> list.fold(<<>>, fn(joined, chunk) { <<joined:bits, chunk.bytes:bits>> })
}

pub fn a_replay_sends_the_clients_chunks_in_order_and_waits_for_each_server_chunk_test() -> Nil {
  use <- owned_test.run(30_000)
  let recording = planted_recording()
  let peer =
    planted_peer.start(script: recording.chunks, wait_ms: event_wait_ms)

  assert replay.run(
      recording:,
      target: Target("127.0.0.1", peer.port),
      deadline_ms: event_wait_ms,
    )
    == Ok(Nil)
    as "the server answers as recorded, so the replay reaches the end"

  // The server heard the three client chunks, in the order they were recorded.
  assert process.receive(peer.report, within: event_wait_ms)
    == Ok(Ok(client_bytes(recording.chunks)))
    as "the replay sent the client's chunks, in order and unchanged"
}

pub fn a_server_that_answers_one_byte_differently_fails_the_replay_at_that_byte_test() -> Nil {
  use <- owned_test.run(30_000)
  let recording = planted_recording()

  // The server's third chunk (the recording's fifth, position 4) has its byte
  // 500 changed: its offset in the server's stream is 52 + 500 = 552.
  let assert [_, _, _, _, Chunk(direction, time, original), _] =
    recording.chunks
  let assert <<before:bytes-size(500), recorded, after:bytes>> = original
  let altered = 255 - recorded
  let changed = bit_array.append(before, <<altered, after:bits>>)
  let answered =
    list.index_map(recording.chunks, fn(chunk, position) {
      case position {
        4 -> Chunk(direction, time, changed)
        _ -> chunk
      }
    })
  let peer = planted_peer.start(script: answered, wait_ms: event_wait_ms)

  assert replay.run(
      recording:,
      target: Target("127.0.0.1", peer.port),
      deadline_ms: event_wait_ms,
    )
    == Error(Differs(
      chunk: 4,
      offset: 552,
      expected: recorded,
      received: altered,
    ))
    as "the replay fails at the changed byte, named by its offset in the server's stream"

  // The replay stopped there: it sent nothing more and closed the connection,
  // so the server was left waiting for the last client chunk.
  assert process.receive(peer.report, within: event_wait_ms)
    == Ok(Error(mug.Closed))
    as "the replay sent no client chunk after the difference"
}

pub fn a_server_that_sends_more_after_the_recordings_last_chunk_fails_the_replay_test() -> Nil {
  use <- owned_test.run(30_000)
  let recording = planted_recording()

  // The planted server answers the recording's last client chunk (the 7 bytes
  // at the end) with 3 bytes the recording does not hold, and then closes. The
  // server's stream before them is its three chunks, 1052 bytes.
  let extra = <<1, 2, 3>>
  let peer =
    planted_peer.start(
      script: list.append(recording.chunks, [Chunk(ServerToClient, 0, extra)]),
      wait_ms: event_wait_ms,
    )

  assert replay.run(
      recording:,
      target: Target("127.0.0.1", peer.port),
      deadline_ms: event_wait_ms,
    )
    == Error(ExtraBytes(offset: 1052, bytes: extra))
    as "the replay reached the end of the recording and then failed on the bytes the server sent past it, at the offset where its stream ends"
}
