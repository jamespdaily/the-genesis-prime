//// Reads what the client sent on the connections of the rule recordings
//// (genesis_prime/rule_recording), with the server's own decoders: the bytes of
//// each socket `Read` input, in order, cut into frames, opened and decoded as
//// the connection's rule takes them.
////
//// - The platform login (STS): each request is cut by the STS wire reader and
////   decoded by the STS message decoder, up to and including the KeyData
////   request. The SRP exchange finishes with the reply to that request, and
////   the library then ciphers every later byte of the connection with RC4
////   under a key made from the server's secret value
////   (StsConnLib64.MT.dll!0x18000a350), which the rule keeps in its state and
////   the recording holds only as the seed it was drawn from; the bytes after
////   the KeyData request are counted and not read.
//// - The auth connection: each frame is cut by the frame reader. The client
////   sends the network layer's messages bare and every other message inside
////   0x0244 (opcode.0x244), ciphered with the base key
////   (`encrypted_frame.unwrap`), and each message is decoded by
////   `client_message`.
//// - The game connection: read as the auth connection is, and re-keyed to the
////   session key from the moment its 0x058F is decoded (`game_connection.rekeyed`),
////   so the frames after it are read under the session key, also those of the
////   same read.
////
//// A message whose number has no decoder in `client_message` is listed, not
//// refused: the rule logs it as unhandled and the connection goes on.

import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{type WrapError}
import genesis_prime/connection/frame.{type Frame, type FrameError}
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/login/sts_message.{type Incoming, type MessageError}
import genesis_prime/login/sts_wire.{type WireError}
import genesis_prime/message/client_message.{
  type ClientMessage, type ClientMessageError,
}
import genesis_prime/rule_recording.{type ReplayFailure, Taken}
import genesis_prime/step.{Input, Socket}
import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import simplifile

/// What a recording's client bytes hold, read.
pub type ClientBytes {
  /// The platform login: each request in the clear with the number of the
  /// input it ended in, and how many bytes came after the KeyData request,
  /// ciphered.
  StsRead(requests: List(#(Int, Incoming)), ciphered_bytes: Int)
  /// The auth or game connection: each message the client sent, in order, and
  /// each message whose number has no decoder.
  FramesRead(messages: List(Received), without_decoder: List(Unread))
}

/// One message the client sent on the auth or a game connection.
pub type Received {
  Received(input: Int, message: ClientMessage, body: BitArray, carried: Carried)
}

/// A message the client sent whose number `client_message` has no decoder
/// for.
pub type Unread {
  Unread(input: Int, message_id: Int)
}

/// How a message crossed the wire.
pub type Carried {
  /// In its own frame, as the network layer's messages travel.
  Bare
  /// Inside 0x0244, ciphered.
  Wrapped
  /// As the whole frame inside another message's body.
  Inside(carrier: Int)
}

/// Why a recording's client bytes did not read.
pub type Failure {
  /// The file is not a rule recording.
  NotARecording(recording: String, failure: ReplayFailure(Nil, Nil))
  /// The recording's client bytes did not read: `input` is the number of the
  /// input (from 0, the connection's first input being 0) whose bytes were
  /// being read.
  NotRead(recording: String, input: Int, problem: Problem)
}

/// What stopped the read of a connection's client bytes.
pub type Problem {
  /// The recording is of a rule that took a socket read and is none of the
  /// three connection rules.
  RuleNotKnown(rule: String)
  /// The STS wire reader refused the bytes.
  StsWireRefused(error: WireError)
  /// The STS message decoder refused a request.
  StsMessageRefused(error: MessageError)
  /// The platform login sent a request in the clear after its KeyData
  /// request, where every byte is ciphered.
  ClearRequestAfterKeyData
  /// The frame reader refused the bytes.
  FrameRefused(error: FrameError)
  /// A 0x0244 did not unwrap.
  WrapperRefused(error: WrapError)
  /// A message did not decode.
  NotDecoded(message_id: Int, error: ClientMessageError)
  /// The frame inside a carrier message is no frame.
  CarriedFrameRefused(carrier: Int, error: FrameError)
  /// The session key in 0x058F makes no cipher.
  KeyRefused(error: cipher.KeyError)
  /// The recording ends inside a frame: `bytes` bytes of it are there.
  CutShort(bytes: Int)
}

/// The connection rules whose recordings hold the client's bytes.
type Connection {
  Sts
  Auth
  Game
}

/// Every recording in `folder`, with what each one's client bytes hold, in
/// the order of the file names. A recording of a rule that has no socket
/// (Sessions, a map) holds no client bytes and is left out.
pub fn read_folder(
  folder: String,
) -> List(#(String, Result(Option(ClientBytes), Failure))) {
  let assert Ok(names) = simplifile.read_directory(folder)
    as { "the folder " <> folder <> " could not be listed" }
  names
  |> list.filter(string.ends_with(_, ".recording"))
  |> list.sort(string.compare)
  |> list.map(fn(name) {
    let recording = folder <> "/" <> name
    #(recording, read_recording(recording))
  })
}

/// What the client bytes of the recording at `recording` hold, `None` when
/// the recording took no socket read.
pub fn read_recording(
  recording: String,
) -> Result(Option(ClientBytes), Failure) {
  let assert Ok(bytes) = simplifile.read_bits(recording)
    as { "the recording " <> recording <> " could not be read" }
  use #(header, records) <- result.try(
    rule_recording.read(bytes)
    |> result.map_error(NotARecording(recording:, failure: _)),
  )
  let inputs =
    list.index_fold(records, [], fn(found, record, input) {
      case record {
        Taken(input: Input(event: Socket(step.Read(bytes:)), ..), ..) -> [
          #(input, bytes),
          ..found
        ]
        Taken(..) | rule_recording.End(..) -> found
      }
    })
    |> list.reverse
  let read = case inputs, connection_of(header.rule) {
    [], _ -> Ok(None)
    [#(input, _), ..], Error(Nil) ->
      Error(#(input, RuleNotKnown(rule: header.rule)))
    _, Ok(Sts) ->
      read_sts(inputs:, pending: <<>>, requests: []) |> result.map(Some)
    _, Ok(Auth) -> read_frames(inputs:, game: False) |> result.map(Some)
    _, Ok(Game) -> read_frames(inputs:, game: True) |> result.map(Some)
  }
  result.map_error(read, fn(stopped) {
    NotRead(recording:, input: stopped.0, problem: stopped.1)
  })
}

fn connection_of(rule: String) -> Result(Connection, Nil) {
  list.key_find(
    [
      #(sts_connection.rule_name, Sts),
      #(auth_connection.rule_name, Auth),
      #(game_connection.rule_name, Game),
    ],
    rule,
  )
}

/// The failure of a read: the input and what stopped it.
type Stopped =
  #(Int, Problem)

/// Reads requests input by input until the KeyData request, and counts every
/// byte after it as ciphered. An input is read whole, so one that holds more
/// after the KeyData request fails the read: a clear request there is
/// reported, and ciphered bytes fail the wire reader.
fn read_sts(
  inputs inputs: List(#(Int, BitArray)),
  pending pending: BitArray,
  requests requests: List(#(Int, Incoming)),
) -> Result(ClientBytes, Stopped) {
  case inputs {
    [] ->
      case bit_array.byte_size(pending) {
        0 -> Ok(StsRead(requests: list.reverse(requests), ciphered_bytes: 0))
        bytes -> Error(#(last_input(requests), CutShort(bytes:)))
      }
    [#(input, bytes), ..later] -> {
      use #(whole, rest) <- result.try(
        sts_wire.decode(received: <<pending:bits, bytes:bits>>)
        |> result.map_error(fn(error) { #(input, StsWireRefused(error)) }),
      )
      use decoded <- result.try(
        list.try_map(whole, fn(request) {
          sts_message.decode(request:)
          |> result.map_error(fn(error) { #(input, StsMessageRefused(error)) })
        }),
      )
      let requests =
        list.fold(decoded, requests, fn(requests, request) {
          [#(input, request), ..requests]
        })
      case list.drop_while(decoded, fn(request) { !is_key_data(request) }) {
        [] -> read_sts(inputs: later, pending: rest, requests:)
        [_key_data] ->
          Ok(StsRead(
            requests: list.reverse(requests),
            ciphered_bytes: byte_count([
              rest,
              ..list.map(later, fn(input) { input.1 })
            ]),
          ))
        [_key_data, ..] -> Error(#(input, ClearRequestAfterKeyData))
      }
    }
  }
}

fn last_input(requests: List(#(Int, Incoming))) -> Int {
  case requests {
    [#(input, _), ..] -> input
    [] -> 0
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

/// What a read of frames has so far: the bytes of a frame not yet whole, the
/// cipher the connection's frames are read under, and what was read.
type Frames {
  Frames(
    pending: BitArray,
    cipher: Cipher,
    messages: List(Received),
    without_decoder: List(Unread),
  )
}

fn read_frames(
  inputs inputs: List(#(Int, BitArray)),
  game game: Bool,
) -> Result(ClientBytes, Stopped) {
  let start =
    Frames(
      pending: <<>>,
      cipher: cipher.base(),
      messages: [],
      without_decoder: [],
    )
  use read <- result.try(
    list.try_fold(inputs, start, fn(frames, input) {
      read_input(frames:, input: input.0, bytes: input.1, game:)
    }),
  )
  case bit_array.byte_size(read.pending), list.last(inputs) {
    0, _ ->
      Ok(FramesRead(
        messages: list.reverse(read.messages),
        without_decoder: list.reverse(read.without_decoder),
      ))
    bytes, Ok(#(input, _)) -> Error(#(input, CutShort(bytes:)))
    bytes, Error(Nil) -> Error(#(0, CutShort(bytes:)))
  }
}

/// Takes the whole frames the bytes of one input complete, in order.
fn read_input(
  frames frames: Frames,
  input input: Int,
  bytes bytes: BitArray,
  game game: Bool,
) -> Result(Frames, Stopped) {
  let #(whole, rest) =
    frame.split(received: <<frames.pending:bits, bytes:bits>>)
  use frames <- result.try(
    list.try_fold(whole, frames, fn(frames, outer) {
      take_frame(frames:, input:, outer:, game:)
    }),
  )
  case rest {
    Ok(rest) -> Ok(Frames(..frames, pending: rest))
    Error(error) -> Error(#(input, FrameRefused(error:)))
  }
}

/// The message in a whole frame, opened as the rule opens it: the client's
/// wrapper is unwrapped under the connection's cipher, any other frame is the
/// message itself.
fn take_frame(
  frames frames: Frames,
  input input: Int,
  outer outer: Frame,
  game game: Bool,
) -> Result(Frames, Stopped) {
  case
    outer.message_id
    == encrypted_frame.message_id(encrypted_frame.ClientWrapper)
  {
    False -> decode(frames:, input:, inner: outer, carried: Bare, game:)
    True ->
      case encrypted_frame.unwrap(outer:, cipher: frames.cipher) {
        Ok(inner) -> decode(frames:, input:, inner:, carried: Wrapped, game:)
        Error(error) -> Error(#(input, WrapperRefused(error:)))
      }
  }
}

/// Decodes one message, and the frame it carries, when it carries one. The
/// game connection's 0x058F re-keys the frames after it.
fn decode(
  frames frames: Frames,
  input input: Int,
  inner inner: Frame,
  carried carried: Carried,
  game game: Bool,
) -> Result(Frames, Stopped) {
  case client_message.decode(message_id: inner.message_id, body: inner.body) {
    Error(client_message.UnknownMessage(message_id:)) ->
      Ok(
        Frames(..frames, without_decoder: [
          Unread(input:, message_id:),
          ..frames.without_decoder
        ]),
      )
    Error(error) ->
      Error(#(input, NotDecoded(message_id: inner.message_id, error:)))
    Ok(message) -> {
      let frames =
        Frames(..frames, messages: [
          Received(input:, message:, body: inner.body, carried:),
          ..frames.messages
        ])
      case role_of(message) {
        Plain -> Ok(frames)
        HelloReply(session_key:) -> rekey(frames:, input:, session_key:, game:)
        Carrier(frame: bytes) ->
          case frame.parse(whole: bytes) {
            Ok(carried_inner) ->
              decode(
                frames:,
                input:,
                inner: carried_inner,
                carried: Inside(carrier: inner.message_id),
                game:,
              )
            Error(error) ->
              Error(#(
                input,
                CarriedFrameRefused(carrier: inner.message_id, error:),
              ))
          }
      }
    }
  }
}

/// The game connection's cipher once 0x058F has been read: the session key's.
fn rekey(
  frames frames: Frames,
  input input: Int,
  session_key session_key: BitArray,
  game game: Bool,
) -> Result(Frames, Stopped) {
  use <- bool.guard(when: !game, return: Ok(frames))
  case game_connection.rekeyed(session_key:) {
    Ok(rekeyed) -> Ok(Frames(..frames, cipher: rekeyed))
    Error(error) -> Error(#(input, KeyRefused(error:)))
  }
}

/// What a message is to the read, beyond being decoded.
type Role {
  /// 0x058F: the game connection is re-keyed to the session key it carries.
  HelloReply(session_key: BitArray)
  /// A message that carries a whole frame in its body, which is read in turn.
  Carrier(frame: BitArray)
  /// Any other message.
  Plain
}

fn role_of(message: ClientMessage) -> Role {
  case message {
    client_message.GameHelloReply(message:) ->
      HelloReply(session_key: message.session_key)
    client_message.WorldMessage(message:) -> Carrier(frame: message.inner_frame)
    client_message.CreateCharacterCarrier(message:) ->
      Carrier(frame: message.inner_frame)
    client_message.Ping(..)
    | client_message.Pong(..)
    | client_message.CloseNotice(..)
    | client_message.LoginRequest(..)
    | client_message.CharacterSelectStart(..)
    | client_message.RealmSelectStart(..)
    | client_message.ClientWrapper(..)
    | client_message.CreateCharacter(..)
    | client_message.PlayCharacter(..)
    | client_message.DeleteCharacter(..)
    | client_message.RenameCharacter(..)
    | client_message.ChooseRealm(..)
    | client_message.ClientControlEchoed(..)
    | client_message.TerrainLoaded(..) -> Plain
  }
}
