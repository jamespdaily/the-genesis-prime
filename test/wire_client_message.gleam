//// Reads what the client sent on the connections of a wire recording
//// (genesis_prime/wire_recording), with the server's own decoders: the bytes of
//// each `Read` input, in order, cut into frames, opened and decoded as the
//// connection's rule takes them.
////
//// - The platform login (STS): each request is cut by the STS wire reader and
////   decoded by the STS message decoder, up to and including the KeyData
////   request. The SRP exchange finishes with the reply to that request, and the
////   library then ciphers every later byte of the connection with RC4 under a
////   key made from the server's secret value (StsConnLib64.MT.dll!0x18000a350),
////   which a wire recording does not hold: the reads after the KeyData request
////   are counted and not read.
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

import frame_reader
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
import genesis_prime/wire_recording.{type Recording, Took}
import gleam/bit_array
import gleam/bool
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// What a recording's client bytes hold, read.
pub type Sent {
  /// The platform login: each request in the clear with the line of the read it
  /// ended in, up to and including the KeyData request, and how many reads
  /// follow it, which are ciphered.
  PlatformLogin(requests: List(#(Int, Requested)), ciphered_reads: Int)
  /// The auth or game connection: each message the client sent, in order, and
  /// each message whose number has no decoder.
  FramesRead(messages: List(Received), without_decoder: List(Unread))
}

/// One request the client sent on the platform login.
pub type Requested {
  /// A request the STS message decoder read.
  Decoded(request: Incoming)
  /// A request of a command the STS message decoder does not know, which the
  /// rule logs as unhandled and goes on from.
  NoDecoder(protocol: String, command: String)
}

/// One message the client sent on the auth or a game connection, with the line
/// of the recording whose read it was in.
pub type Received {
  Received(line: Int, message: ClientMessage, body: BitArray, carried: Carried)
}

/// A message the client sent whose number `client_message` has no decoder for.
pub type Unread {
  Unread(line: Int, message_id: Int)
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

/// Why a recording's client bytes did not read: the connection's file, the line
/// of the recording whose read was being read (from 1, the header being 0), and
/// what stopped it.
pub type Failure {
  NotRead(connection: String, line: Int, problem: Problem)
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
  /// The platform login sent a request in the clear after its KeyData request,
  /// in the same read, where every byte is ciphered.
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
  /// The recording ends inside a frame or a request: `bytes` bytes of it are
  /// there.
  CutShort(bytes: Int)
}

/// The connection rules whose recordings hold the client's bytes.
type Connection {
  Sts
  Auth
  Game
}

/// What the client bytes of the connection hold: `None` when it took no socket
/// read. `name` is the connection's file.
pub fn read(
  name name: String,
  recording recording: Recording,
) -> Result(Option(Sent), Failure) {
  let reads =
    list.index_map(recording.lines, fn(line, index) { #(index + 1, line) })
    |> list.filter_map(fn(numbered) {
      case numbered.1 {
        Took(input: wire_recording.Read(bytes:), ..) -> Ok(#(numbered.0, bytes))
        Took(..) | wire_recording.Wrote(..) -> Error(Nil)
      }
    })
  let rule = recording.header.rule
  let read = case reads, connection_of(rule) {
    [], _ -> Ok(None)
    [#(line, _), ..], Error(Nil) -> Error(#(line, RuleNotKnown(rule:)))
    _, Ok(Sts) -> read_sts(reads:) |> result.map(Some)
    _, Ok(Auth) -> read_frames(reads:, game: False) |> result.map(Some)
    _, Ok(Game) -> read_frames(reads:, game: True) |> result.map(Some)
  }
  result.map_error(read, fn(stopped) {
    NotRead(connection: name, line: stopped.0, problem: stopped.1)
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

/// The failure of a read: the line and what stopped it.
type Stopped =
  #(Int, Problem)

/// Reads requests read by read until the KeyData request, in the clear. A read
/// is read whole, so one that holds more after the KeyData request fails the
/// read: a clear request there is reported. The reads after it are counted.
fn read_sts(reads reads: List(#(Int, BitArray))) -> Result(Sent, Stopped) {
  read_clear(reads:, pending: <<>>, requests: [])
}

fn read_clear(
  reads reads: List(#(Int, BitArray)),
  pending pending: BitArray,
  requests requests: List(#(Int, Requested)),
) -> Result(Sent, Stopped) {
  case reads {
    [] ->
      case bit_array.byte_size(pending) {
        0 ->
          Ok(PlatformLogin(requests: list.reverse(requests), ciphered_reads: 0))
        bytes -> Error(#(last_line(requests), CutShort(bytes:)))
      }
    [#(line, bytes), ..later] -> {
      use #(whole, rest) <- result.try(
        sts_wire.decode(received: <<pending:bits, bytes:bits>>)
        |> result.map_error(fn(error) { #(line, StsWireRefused(error)) }),
      )
      use decoded <- result.try(
        list.try_map(whole, fn(request) { decode_request(line:, request:) }),
      )
      let requests =
        list.fold(decoded, requests, fn(requests, request) {
          [#(line, request), ..requests]
        })
      case list.drop_while(decoded, fn(request) { !is_key_data(request) }) {
        [] -> read_clear(reads: later, pending: rest, requests:)
        [_key_data] ->
          case bit_array.byte_size(rest) {
            0 ->
              Ok(PlatformLogin(
                requests: list.reverse(requests),
                ciphered_reads: list.length(later),
              ))
            _ -> Error(#(line, ClearRequestAfterKeyData))
          }
        [_key_data, ..] -> Error(#(line, ClearRequestAfterKeyData))
      }
    }
  }
}

fn decode_request(
  line line: Int,
  request request: sts_wire.Request,
) -> Result(Requested, Stopped) {
  case sts_message.decode(request:) {
    Ok(decoded) -> Ok(Decoded(request: decoded))
    Error(sts_message.UnknownCommand(protocol:, command:)) ->
      Ok(NoDecoder(protocol:, command:))
    Error(error) -> Error(#(line, StsMessageRefused(error)))
  }
}

fn last_line(requests: List(#(Int, Requested))) -> Int {
  case requests {
    [#(line, _), ..] -> line
    [] -> 0
  }
}

fn is_key_data(requested: Requested) -> Bool {
  case requested {
    Decoded(sts_message.Transaction(request: sts_message.KeyData(..), ..)) ->
      True
    Decoded(sts_message.Transaction(..))
    | Decoded(sts_message.ConnectionOpened(..))
    | Decoded(sts_message.Ping)
    | NoDecoder(..) -> False
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
  reads reads: List(#(Int, BitArray)),
  game game: Bool,
) -> Result(Sent, Stopped) {
  let start =
    Frames(
      pending: <<>>,
      cipher: cipher.base(),
      messages: [],
      without_decoder: [],
    )
  use read <- result.try(
    list.try_fold(reads, start, fn(frames, read) {
      read_one(frames:, line: read.0, bytes: read.1, game:)
    }),
  )
  case bit_array.byte_size(read.pending), list.last(reads) {
    0, _ ->
      Ok(FramesRead(
        messages: list.reverse(read.messages),
        without_decoder: list.reverse(read.without_decoder),
      ))
    bytes, Ok(#(line, _)) -> Error(#(line, CutShort(bytes:)))
    bytes, Error(Nil) -> Error(#(0, CutShort(bytes:)))
  }
}

/// Takes the whole frames the bytes of one read complete, in order.
fn read_one(
  frames frames: Frames,
  line line: Int,
  bytes bytes: BitArray,
  game game: Bool,
) -> Result(Frames, Stopped) {
  let #(whole, rest) =
    frame_reader.split(received: <<frames.pending:bits, bytes:bits>>)
  use frames <- result.try(
    list.try_fold(whole, frames, fn(frames, outer) {
      take_frame(frames:, line:, outer:, game:)
    }),
  )
  case rest {
    Ok(rest) -> Ok(Frames(..frames, pending: rest))
    Error(error) -> Error(#(line, FrameRefused(error:)))
  }
}

/// The message in a whole frame, opened as the rule opens it: the client's
/// wrapper is unwrapped under the connection's cipher, any other frame is the
/// message itself.
fn take_frame(
  frames frames: Frames,
  line line: Int,
  outer outer: Frame,
  game game: Bool,
) -> Result(Frames, Stopped) {
  case
    outer.message_id
    == encrypted_frame.message_id(encrypted_frame.ClientWrapper)
  {
    False -> decode(frames:, line:, inner: outer, carried: Bare, game:)
    True ->
      case encrypted_frame.unwrap(outer:, cipher: frames.cipher) {
        Ok(inner) -> decode(frames:, line:, inner:, carried: Wrapped, game:)
        Error(error) -> Error(#(line, WrapperRefused(error:)))
      }
  }
}

/// Decodes one message, and the frame it carries, when it carries one. The game
/// connection's 0x058F re-keys the frames after it.
fn decode(
  frames frames: Frames,
  line line: Int,
  inner inner: Frame,
  carried carried: Carried,
  game game: Bool,
) -> Result(Frames, Stopped) {
  case client_message.decode(message_id: inner.message_id, body: inner.body) {
    Error(client_message.UnknownMessage(message_id:)) ->
      Ok(
        Frames(..frames, without_decoder: [
          Unread(line:, message_id:),
          ..frames.without_decoder
        ]),
      )
    Error(error) ->
      Error(#(line, NotDecoded(message_id: inner.message_id, error:)))
    Ok(message) -> {
      let frames =
        Frames(..frames, messages: [
          Received(line:, message:, body: inner.body, carried:),
          ..frames.messages
        ])
      case role_of(message) {
        Plain -> Ok(frames)
        HelloReply(session_key:) -> rekey(frames:, line:, session_key:, game:)
        Carrier(frame: bytes) ->
          case frame.parse(whole: bytes) {
            Ok(carried_inner) ->
              decode(
                frames:,
                line:,
                inner: carried_inner,
                carried: Inside(carrier: inner.message_id),
                game:,
              )
            Error(error) ->
              Error(#(
                line,
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
  line line: Int,
  session_key session_key: BitArray,
  game game: Bool,
) -> Result(Frames, Stopped) {
  use <- bool.guard(when: !game, return: Ok(frames))
  case game_connection.rekeyed(session_key:) {
    Ok(rekeyed) -> Ok(Frames(..frames, cipher: rekeyed))
    Error(error) -> Error(#(line, KeyRefused(error:)))
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
    | client_message.TerrainLoaded(..)
    | client_message.CampRequest(..)
    | client_message.CampFinished(..)
    | client_message.PlayerMovement(..)
    | client_message.ZoneValueChanged(..)
    | client_message.MovementSendIntervalAnswer(..)
    | client_message.MoveSpeedSetting(..)
    | client_message.FallValue(..)
    | client_message.FellBelowFloor(..) -> Plain
  }
}
