//// Reads what the client sent in a recording, with the server's own decoders:
//// the bytes the client sent on one connection, joined in the order the relay
//// received them, cut into the connection's messages and each decoded.
////
//// - The platform login (STS): each request is read by the STS wire reader and
////   decoded by the STS message decoder, up to and including the KeyData
////   request. The SRP exchange finishes with the reply to that request, and
////   the library then ciphers every later byte of the connection with RC4
////   under the SRP session key (StsConnLib64.MT.dll!0x18000a350,
////   StsConnLib64.MT.dll!0x18003a7d0). That key comes from the server's secret
////   value, which no recording holds, so the bytes after the KeyData request
////   are counted and not read.
//// - The auth connection: each frame is cut by the frame reader. The client
////   sends the network layer's messages bare and every other message inside
////   0x0244 (opcode.0x244), ciphered with the base key, which keys the whole
////   auth connection (0x14000a6db). Each message is decoded by
////   `client_message`.
//// - A game connection is not read: its key changes after 0x058F to one made
////   from the session key the client sends, so a game recording fails the read
////   rather than passing unread.

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{type WrapError}
import genesis_prime/connection/frame.{type Frame, type FrameError}
import genesis_prime/login/sts_message.{type Incoming, type MessageError}
import genesis_prime/login/sts_wire.{type WireError}
import genesis_prime/message/client_message.{
  type ClientMessage, type ClientMessageError,
}
import genesis_prime/recording.{
  type Chunk, type Recording, type RecordingError, type Role, Auth, Game, Sts,
}
import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// What a recording's client bytes hold, read.
pub type Read {
  /// The platform login: each request in the clear, in order, and how many
  /// bytes came after the KeyData request, ciphered.
  StsRead(requests: List(Incoming), ciphered_bytes: Int)
  /// The auth connection: each message the client sent, in order.
  FramesRead(messages: List(Received))
}

/// One message the client sent on the auth or a game connection.
pub type Received {
  Received(message: ClientMessage, body: BitArray, carried: Carried)
}

/// How a message crossed the wire.
pub type Carried {
  /// In its own frame, as the network layer's messages travel.
  Bare
  /// Inside 0x0244, ciphered.
  Wrapped
}

/// Why a recording's client bytes did not read.
pub type Failure {
  /// The file is not a recording.
  NotARecording(path: String, error: RecordingError)
  /// The file is a recording of `role` and its client bytes did not read.
  NotRead(path: String, role: Role, problem: Problem)
}

/// What stopped the read of a connection's client bytes.
pub type Problem {
  /// The STS wire reader refused the bytes.
  StsWireRefused(error: WireError)
  /// The STS message decoder refused a request.
  StsMessageRefused(error: MessageError)
  /// The frame reader refused the bytes.
  FrameRefused(error: FrameError)
  /// A 0x0244 did not unwrap.
  WrapperRefused(error: WrapError)
  /// A message did not decode.
  NotDecoded(error: ClientMessageError)
  /// The platform login sent a request in the clear after its KeyData
  /// request, where every byte is ciphered.
  ClearRequestAfterKeyData
  /// The recording ends inside a message: `bytes` bytes of it are there.
  CutShort(bytes: Int)
  /// The recording is of a game connection, which this read does not read.
  GameConnectionNotRead
}

/// Every recording under `folder`, with what each one's client bytes hold, in
/// the order of their paths.
pub fn read_folder(folder: String) -> List(#(String, Result(Read, Failure))) {
  let assert Ok(paths) = simplifile.get_files(folder)
    as { "the folder " <> folder <> " could not be listed" }
  paths
  |> list.filter(string.ends_with(_, ".recording"))
  |> list.sort(string.compare)
  |> list.map(fn(path) { #(path, read_file(path)) })
}

/// What the client bytes of the recording at `path` hold.
pub fn read_file(path: String) -> Result(Read, Failure) {
  use recorded <- result.try(
    recording.read(from: path)
    |> result.map_error(NotARecording(path:, error: _)),
  )
  read(recorded)
  |> result.map_error(NotRead(path:, role: recorded.header.role, problem: _))
}

/// What a recording's client bytes hold.
pub fn read(recorded: Recording) -> Result(Read, Problem) {
  case recorded.header.role {
    Sts -> read_sts(client_chunks(recorded.chunks))
    Auth -> read_frames(client_bytes(recorded.chunks))
    Game -> Error(GameConnectionNotRead)
  }
}

/// The bytes of each chunk the client sent, in order.
fn client_chunks(chunks: List(Chunk)) -> List(BitArray) {
  list.filter_map(chunks, fn(chunk) {
    case chunk.direction {
      recording.ClientToServer -> Ok(chunk.bytes)
      recording.ServerToClient -> Error(Nil)
    }
  })
}

fn client_bytes(chunks: List(Chunk)) -> BitArray {
  bit_array.concat(client_chunks(chunks))
}

/// Reads requests chunk by chunk until the KeyData request, and counts every
/// byte after it as ciphered. A chunk is read whole, so a chunk that holds
/// more after the KeyData request fails the read: a clear request there is
/// reported, and ciphered bytes fail the wire reader. A clear request the
/// client sent in a later chunk, before the reply that turns RC4 on, is
/// counted with the ciphered bytes.
fn read_sts(chunks: List(BitArray)) -> Result(Read, Problem) {
  read_sts_chunks(chunks:, pending: <<>>, requests: [])
}

fn read_sts_chunks(
  chunks chunks: List(BitArray),
  pending pending: BitArray,
  requests requests: List(Incoming),
) -> Result(Read, Problem) {
  case chunks {
    [] ->
      case bit_array.byte_size(pending) {
        0 -> Ok(StsRead(requests: list.reverse(requests), ciphered_bytes: 0))
        bytes -> Error(CutShort(bytes:))
      }
    [chunk, ..later] -> {
      let received = <<pending:bits, chunk:bits>>
      use #(whole, rest) <- result.try(
        sts_wire.decode(received:) |> result.map_error(StsWireRefused),
      )
      use decoded <- result.try(
        list.try_map(whole, fn(request) { sts_message.decode(request:) })
        |> result.map_error(StsMessageRefused),
      )
      let requests = list.append(list.reverse(decoded), requests)
      case list.drop_while(decoded, fn(request) { !is_key_data(request) }) {
        [] -> read_sts_chunks(chunks: later, pending: rest, requests:)
        [_key_data] ->
          Ok(StsRead(
            requests: list.reverse(requests),
            ciphered_bytes: byte_count([rest, ..later]),
          ))
        [_key_data, ..] -> Error(ClearRequestAfterKeyData)
      }
    }
  }
}

fn byte_count(chunks: List(BitArray)) -> Int {
  list.fold(chunks, 0, fn(total, chunk) { total + bit_array.byte_size(chunk) })
}

fn is_key_data(incoming: Incoming) -> Bool {
  case incoming {
    sts_message.Transaction(request: sts_message.KeyData(..), ..) -> True
    sts_message.Transaction(..)
    | sts_message.ConnectionOpened(..)
    | sts_message.Ping -> False
  }
}

fn read_frames(bytes: BitArray) -> Result(Read, Problem) {
  let #(frames, rest) = frame.split(received: bytes)
  use rest <- result.try(rest |> result.map_error(FrameRefused))
  use messages <- result.try(list.try_map(frames, read_frame))
  case bit_array.byte_size(rest) {
    0 -> Ok(FramesRead(messages:))
    bytes -> Error(CutShort(bytes:))
  }
}

fn read_frame(outer: Frame) -> Result(Received, Problem) {
  case
    outer.message_id
    == encrypted_frame.message_id(encrypted_frame.ClientWrapper)
  {
    True -> {
      let assert Ok(auth_cipher) = cipher.new(key: cipher.base_key)
        as "the base key is not 0"
      use inner <- result.try(
        encrypted_frame.unwrap(outer:, cipher: auth_cipher)
        |> result.map_error(WrapperRefused),
      )
      decode(inner, Wrapped)
    }
    False -> decode(outer, Bare)
  }
}

fn decode(received: Frame, carried: Carried) -> Result(Received, Problem) {
  client_message.decode(message_id: received.message_id, body: received.body)
  |> result.map(Received(message: _, body: received.body, carried:))
  |> result.map_error(NotDecoded)
}
