//// Replays a recording over TCP against a server, for any edge test: it opens
//// a connection to the server, sends the client's chunks in the order the
//// recording holds them, and before each next client chunk waits for the
//// server chunks that came before it in the recording.
////
//// A server chunk is waited for by its bytes, not by how the server splits
//// them into packets: the bytes that arrive are matched against the
//// recording's server-to-client stream as they come, so two chunks that
//// arrive in one packet, or one chunk in two, replay the same. The wait for one
//// chunk's bytes has a deadline measured on the monotonic clock; it is the
//// time the server may take, not a pause the replay sits out. The first byte
//// that differs ends the replay, with its offset in the stream of everything
//// the server sent.

import genesis_prime/recording.{
  type Chunk, type Recording, ClientToServer, ServerToClient,
}
import genesis_prime/recording/clock
import gleam/bit_array
import gleam/bool
import gleam/result
import mug

/// The server a replay connects to.
pub type Target {
  Target(host: String, port: Int)
}

/// Why a replay ended before the recording did. `chunk` is the position of the
/// recording's chunk being replayed, from 0, and `offset` is a byte's
/// position in the stream of everything the server sent, from 0.
pub type Failure {
  /// The connection to the server was not opened.
  NotConnected(error: mug.ConnectError)
  /// A client chunk was not sent.
  NotSent(chunk: Int, error: mug.Error)
  /// The server sent a byte other than the recording's at `offset`.
  Differs(chunk: Int, offset: Int, expected: Int, received: Int)
  /// The server had not sent the bytes of the chunk by the deadline;
  /// `offset` is the first byte that had not arrived.
  DeadlinePassed(chunk: Int, offset: Int)
  /// The server closed the connection before it had sent the chunk's bytes;
  /// `offset` is the first byte that had not arrived.
  ServerClosed(chunk: Int, offset: Int)
  /// Receiving failed for another reason.
  NotReceived(chunk: Int, offset: Int, error: mug.Error)
  /// The recording ended, and the server then sent `bytes` more before it
  /// closed the connection; `offset` is the first of them in the stream of
  /// everything the server sent.
  ExtraBytes(offset: Int, bytes: BitArray)
  /// The recording ended, the replay closed its sending side, and the server
  /// neither sent nor closed within the deadline; `offset` is the length of the
  /// stream the server sent.
  NotClosed(offset: Int)
}

/// Replays `recording` against `target`. Each wait for the server's bytes of
/// one chunk takes at most `deadline_ms` milliseconds. The connection is closed
/// when the replay ends.
pub fn run(
  recording recording: Recording,
  target target: Target,
  deadline_ms deadline_ms: Int,
) -> Result(Nil, Failure) {
  run_connected(recording:, target:, deadline_ms:, connected: fn(_address) {
    Nil
  })
}

/// Replays as `run` does, and calls `connected` once the connection is open and
/// before the first byte is sent, with the connection's own address as text,
/// which is the peer address the server sees for it. A replay that must give
/// the server something for this connection, such as its recorded draws, does
/// it there.
pub fn run_connected(
  recording recording: Recording,
  target target: Target,
  deadline_ms deadline_ms: Int,
  connected connected: fn(String) -> Nil,
) -> Result(Nil, Failure) {
  let _ = connected
  let options =
    mug.new(target.host, port: target.port)
    |> mug.timeout(deadline_ms)
    |> mug.ip_version_preference(mug.Ipv4Preferred)
  use socket <- result.try(
    mug.connect(options) |> result.map_error(NotConnected),
  )
  let outcome =
    replay_chunks(
      socket:,
      chunks: recording.chunks,
      position: Position(chunk: 0, offset: 0),
      pending: <<>>,
      deadline_ms:,
    )
  case mug.shutdown(socket) {
    Ok(Nil) | Error(mug.Closed) | Error(mug.Enotconn) -> outcome
    Error(error) ->
      panic as {
        "the replay's connection did not shut down: "
        <> mug.describe_error(error)
      }
  }
}

/// How far the replay has come: the position of the next chunk, and how many
/// bytes of the server's stream the chunks before it hold.
type Position {
  Position(chunk: Int, offset: Int)
}

/// Replays `chunks` from `position`. `pending` holds the bytes the server has
/// sent that no chunk has taken yet.
fn replay_chunks(
  socket socket: mug.Socket,
  chunks chunks: List(Chunk),
  position position: Position,
  pending pending: BitArray,
  deadline_ms deadline_ms: Int,
) -> Result(Nil, Failure) {
  case chunks {
    [] -> Ok(Nil)
    [chunk, ..later] -> {
      let next = Position(..position, chunk: position.chunk + 1)
      case chunk.direction {
        ClientToServer ->
          case mug.send(socket, chunk.bytes) {
            Ok(Nil) ->
              replay_chunks(
                socket:,
                chunks: later,
                position: next,
                pending:,
                deadline_ms:,
              )
            Error(error) -> Error(NotSent(chunk: position.chunk, error:))
          }
        ServerToClient -> {
          let deadline = clock.microseconds() + deadline_ms * 1000
          use pending <- result.try(await_chunk(
            socket:,
            expected: chunk.bytes,
            position:,
            pending:,
            deadline:,
          ))
          let size = bit_array.byte_size(chunk.bytes)
          replay_chunks(
            socket:,
            chunks: later,
            position: Position(..next, offset: position.offset + size),
            pending:,
            deadline_ms:,
          )
        }
      }
    }
  }
}

/// Waits until `pending` holds the bytes of `expected`, taking what the server
/// sends. Returns what is left after them. A byte that differs, the deadline
/// (a reading of the clock in microseconds) and a close each end the wait.
fn await_chunk(
  socket socket: mug.Socket,
  expected expected: BitArray,
  position position: Position,
  pending pending: BitArray,
  deadline deadline: Int,
) -> Result(BitArray, Failure) {
  case first_difference(expected:, received: pending, index: 0) {
    Ok(#(index, recorded, received)) ->
      Error(Differs(
        chunk: position.chunk,
        offset: position.offset + index,
        expected: recorded,
        received:,
      ))
    Error(Nil) -> {
      let size = bit_array.byte_size(expected)
      let held = bit_array.byte_size(pending)
      case held >= size {
        True -> {
          let assert Ok(rest) = bit_array.slice(pending, size, held - size)
            as "the bytes after the chunk are inside what was received"
          Ok(rest)
        }
        False ->
          receive_more(socket:, expected:, position:, pending:, deadline:)
      }
    }
  }
}

/// Takes the next bytes the server sends, within the deadline, and goes on
/// waiting for the chunk with them added to `pending`.
fn receive_more(
  socket socket: mug.Socket,
  expected expected: BitArray,
  position position: Position,
  pending pending: BitArray,
  deadline deadline: Int,
) -> Result(BitArray, Failure) {
  let missing_from = position.offset + bit_array.byte_size(pending)
  let wait_ms = { deadline - clock.microseconds() + 999 } / 1000
  use <- bool.guard(
    wait_ms <= 0,
    Error(DeadlinePassed(chunk: position.chunk, offset: missing_from)),
  )
  case mug.receive(socket, timeout_milliseconds: wait_ms) {
    Ok(bytes) ->
      await_chunk(
        socket:,
        expected:,
        position:,
        pending: <<pending:bits, bytes:bits>>,
        deadline:,
      )
    Error(mug.Timeout) ->
      Error(DeadlinePassed(chunk: position.chunk, offset: missing_from))
    Error(mug.Closed) ->
      Error(ServerClosed(chunk: position.chunk, offset: missing_from))
    Error(error) ->
      Error(NotReceived(chunk: position.chunk, offset: missing_from, error:))
  }
}

/// The first position at which `expected` and `received` hold different bytes,
/// within the shorter of the two, with the two bytes; nothing when one is the
/// beginning of the other.
fn first_difference(
  expected expected: BitArray,
  received received: BitArray,
  index index: Int,
) -> Result(#(Int, Int, Int), Nil) {
  case expected, received {
    <<recorded, expected_rest:bytes>>, <<received_byte, received_rest:bytes>> ->
      case recorded == received_byte {
        True ->
          first_difference(
            expected: expected_rest,
            received: received_rest,
            index: index + 1,
          )
        False -> Ok(#(index, recorded, received_byte))
      }
    _, _ -> Error(Nil)
  }
}
