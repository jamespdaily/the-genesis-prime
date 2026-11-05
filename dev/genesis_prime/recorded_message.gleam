//// Reads a wire recording (genesis_prime/wire_recording) back as the messages
//// each side sent, with the server's own frame reader, cipher and decoders:
//// the bytes of each read and each write, in the order of the recording's
//// lines, cut into frames, opened and decoded as the connection's rule takes
//// and writes them. The replay tests read what the client sent (`read`); the
//// recording dump reads both ways (`exchange`).
////
//// ```
//// a read or a write line ─▶ whole frames, a frame spanning lines kept (frame_reader.split)
////   the sender's wrapper  ─▶ unwrapped under the connection's cipher      depth 1
////     (0x0244 from the client, 0x0076 or 0x03DC from the server)
////   any other frame       ─▶ the message itself                            depth 0
////   0x038C or 0x025C      ─▶ the frame in its body, read in turn           one deeper
//// each message           ─▶ client_message.decode or server_message.decode
//// ```
////
//// - The platform login (STS): each request is cut by the STS wire reader and
////   decoded by the STS message decoder, up to and including the KeyData
////   request. The SRP exchange finishes with the reply to that request, and the
////   library then ciphers every later byte of the connection with RC4 under a
////   key made from the server's secret value (StsConnLib64.MT.dll!0x18000a350),
////   which a wire recording does not hold: the reads after the KeyData request
////   are counted and not read, and the server's replies are not read.
//// - The auth connection: the client sends the network layer's messages bare
////   and every other message inside 0x0244 (opcode.0x244), and the server
////   writes inside 0x0076, both under the base key (`encrypted_frame.unwrap`).
//// - The game connection: read as the auth connection is, with the server's
////   wrapper 0x03DC, and re-keyed to the session key from the moment the
////   client's 0x058F is decoded (`game_connection.rekeyed`), so the frames
////   after it each way are read under the session key, also those of the same
////   read.
////
//// A message whose number has no decoder is listed, not refused: the rule logs
//// it as unhandled and the connection goes on.

import frame_reader
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{type WrapError}
import genesis_prime/connection/frame.{type Frame, type FrameError}
import genesis_prime/game/connection as game_connection
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/login/sts_message.{type Incoming, type MessageError}
import genesis_prime/login/sts_wire.{type WireError}
import genesis_prime/message/bit_stream.{type DecodeError}
import genesis_prime/message/client_message.{
  type ClientMessage, type ClientMessageError,
}
import genesis_prime/message/server_message.{type ServerMessage}
import genesis_prime/wire_recording.{type Recording, Took, Wrote}
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
  /// Inside its sender's wrapper, ciphered.
  Wrapped
  /// As the whole frame inside another message's body.
  Inside(carrier: Int)
}

/// Which side sent a message.
pub type Direction {
  ClientToServer
  ServerToClient
}

/// One message of the auth or a game connection, either way, with the line of
/// the recording whose read or write it was in, and its depth: 0 for a frame
/// as it crossed the wire, 1 inside its sender's wrapper, and one more inside a
/// carrier.
pub type Opened {
  Opened(
    line: Int,
    direction: Direction,
    carried: Carried,
    depth: Int,
    message_id: Int,
    body: BitArray,
    reading: Reading,
  )
}

/// What a message's body read as.
pub type Reading {
  ClientSent(message: ClientMessage)
  ServerSent(message: ServerMessage)
  /// No message of the schema its sender sends has this number.
  WithoutDecoder
  /// The body is not the message its number names.
  Malformed(error: DecodeError)
}

/// The messages of the auth or a game connection both ways, in the order of
/// the recording's lines, and what stopped the read when something did: every
/// message before it is read.
pub type Exchange {
  Exchange(opened: List(Opened), stopped: Option(Failure))
}

/// Why a recording's bytes did not read: the connection's file, the line of the
/// recording whose read or write was being read (from 1, the header being 0),
/// and what stopped it.
pub type Failure {
  NotRead(connection: String, line: Int, problem: Problem)
}

/// What stopped the read of a connection's bytes.
pub type Problem {
  /// The recording is of a rule that took a socket read and is none of the
  /// three connection rules, or `exchange` was asked for the platform login.
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
  /// A wrapper did not unwrap.
  WrapperRefused(error: WrapError)
  /// A message the client sent did not decode.
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
    list.filter_map(numbered(recording), fn(chunk) {
      case chunk.direction {
        ClientToServer -> Ok(#(chunk.line, chunk.bytes))
        ServerToClient -> Error(Nil)
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

/// Every message of the auth or a game connection both ways, in the order of
/// its lines. `name` is the connection's file. The platform login's bytes are
/// ciphered after its KeyData request (`read` reads its clear requests), so it
/// and any other rule stop at once with `RuleNotKnown`.
pub fn exchange(name name: String, recording recording: Recording) -> Exchange {
  let failure = fn(stopped: Stopped) {
    Some(NotRead(connection: name, line: stopped.0, problem: stopped.1))
  }
  let rule = recording.header.rule
  case connection_of(rule) {
    Error(Nil) | Ok(Sts) ->
      Exchange(opened: [], stopped: failure(#(0, RuleNotKnown(rule:))))
    Ok(Auth) | Ok(Game) -> {
      let chunks = numbered(recording)
      let #(walked, stopped) =
        walk_chunks(chunks:, walk: start(game: connection_of(rule) == Ok(Game)))
      let stopped = case stopped {
        Error(stopped) -> Error(stopped)
        Ok(Nil) -> left_over(walked:, chunks:)
      }
      Exchange(opened: list.reverse(walked.opened), stopped: case stopped {
        Ok(Nil) -> None
        Error(stopped) -> failure(stopped)
      })
    }
  }
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

/// The bytes of one line: a read is the client's, a write the server's.
type Chunk {
  Chunk(line: Int, direction: Direction, bytes: BitArray)
}

/// The reads and writes of a recording, each with its line, from 1.
fn numbered(recording: Recording) -> List(Chunk) {
  list.index_map(recording.lines, fn(line, index) { #(index + 1, line) })
  |> list.filter_map(fn(numbered) {
    case numbered.1 {
      Took(input: wire_recording.Read(bytes:), ..) ->
        Ok(Chunk(line: numbered.0, direction: ClientToServer, bytes:))
      Wrote(bytes:, ..) ->
        Ok(Chunk(line: numbered.0, direction: ServerToClient, bytes:))
      Took(..) -> Error(Nil)
    }
  })
}

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

/// The client's messages of the auth or a game connection: the first message
/// that does not decode, or else what stopped the walk, fails the read.
fn read_frames(
  reads reads: List(#(Int, BitArray)),
  game game: Bool,
) -> Result(Sent, Stopped) {
  let chunks =
    list.map(reads, fn(read) {
      Chunk(line: read.0, direction: ClientToServer, bytes: read.1)
    })
  let #(walked, stopped) = walk_chunks(chunks:, walk: start(game:))
  let opened = list.reverse(walked.opened)
  let not_decoded =
    list.find_map(opened, fn(opened) {
      case opened.reading {
        Malformed(error:) ->
          Ok(#(
            opened.line,
            NotDecoded(
              message_id: opened.message_id,
              error: client_message.Malformed(
                message_id: opened.message_id,
                error:,
              ),
            ),
          ))
        ClientSent(..) | ServerSent(..) | WithoutDecoder -> Error(Nil)
      }
    })
  use <- result_or(not_decoded)
  use Nil <- result.try(stopped)
  use Nil <- result.try(left_over(walked:, chunks:))
  Ok(FramesRead(
    messages: list.filter_map(opened, fn(opened) {
      case opened.reading {
        ClientSent(message:) ->
          Ok(Received(
            line: opened.line,
            message:,
            body: opened.body,
            carried: opened.carried,
          ))
        ServerSent(..) | WithoutDecoder | Malformed(..) -> Error(Nil)
      }
    }),
    without_decoder: list.filter_map(opened, fn(opened) {
      case opened.reading {
        WithoutDecoder ->
          Ok(Unread(line: opened.line, message_id: opened.message_id))
        ClientSent(..) | ServerSent(..) | Malformed(..) -> Error(Nil)
      }
    }),
  ))
}

/// The failure found, when one was, else what `otherwise` gives.
fn result_or(
  found: Result(Stopped, Nil),
  otherwise: fn() -> Result(Sent, Stopped),
) -> Result(Sent, Stopped) {
  case found {
    Ok(stopped) -> Error(stopped)
    Error(Nil) -> otherwise()
  }
}

/// A recording that ends inside a frame either way: the bytes of it that are
/// there, at the last line of that side.
fn left_over(
  walked walked: Walk,
  chunks chunks: List(Chunk),
) -> Result(Nil, Stopped) {
  let cut = fn(pending: BitArray, direction: Direction) {
    case bit_array.byte_size(pending) {
      0 -> Ok(Nil)
      bytes -> {
        let line =
          list.filter(chunks, fn(chunk) { chunk.direction == direction })
          |> list.last
          |> result.map(fn(chunk) { chunk.line })
          |> result.unwrap(0)
        Error(#(line, CutShort(bytes:)))
      }
    }
  }
  use Nil <- result.try(cut(walked.from_client, ClientToServer))
  cut(walked.from_server, ServerToClient)
}

/// What a walk over a connection's frames has so far: the cipher its frames are
/// read under, the bytes of a frame not yet whole each way, and the messages
/// read, latest first.
type Walk {
  Walk(
    cipher: Cipher,
    game: Bool,
    from_client: BitArray,
    from_server: BitArray,
    opened: List(Opened),
  )
}

/// A walk at the connection's start: the base key, as every connection that
/// takes the client's wrapper starts.
fn start(game game: Bool) -> Walk {
  Walk(
    cipher: cipher.base(),
    game:,
    from_client: <<>>,
    from_server: <<>>,
    opened: [],
  )
}

/// A walk that stopped, with every message read before it stopped.
type Halted {
  Halted(walk: Walk, stopped: Stopped)
}

/// Takes the chunks in order, until one fails: the walk so far, and what
/// stopped it.
fn walk_chunks(
  chunks chunks: List(Chunk),
  walk walk: Walk,
) -> #(Walk, Result(Nil, Stopped)) {
  case chunks {
    [] -> #(walk, Ok(Nil))
    [chunk, ..later] ->
      case take_chunk(walk:, chunk:) {
        Ok(walk) -> walk_chunks(chunks: later, walk:)
        Error(Halted(walk:, stopped:)) -> #(walk, Error(stopped))
      }
  }
}

/// Takes the whole frames the bytes of one line complete, in order.
fn take_chunk(walk walk: Walk, chunk chunk: Chunk) -> Result(Walk, Halted) {
  let pending = case chunk.direction {
    ClientToServer -> walk.from_client
    ServerToClient -> walk.from_server
  }
  let #(whole, rest) =
    frame_reader.split(received: <<pending:bits, chunk.bytes:bits>>)
  use walk <- result.try(
    list.try_fold(whole, walk, fn(walk, outer) {
      take_frame(walk:, line: chunk.line, direction: chunk.direction, outer:)
    }),
  )
  case rest, chunk.direction {
    Ok(rest), ClientToServer -> Ok(Walk(..walk, from_client: rest))
    Ok(rest), ServerToClient -> Ok(Walk(..walk, from_server: rest))
    Error(error), _ ->
      Error(Halted(walk:, stopped: #(chunk.line, FrameRefused(error:))))
  }
}

/// The message in a whole frame, opened as the rule opens or writes it: the
/// sender's wrapper is unwrapped under the connection's cipher, any other frame
/// is the message itself.
fn take_frame(
  walk walk: Walk,
  line line: Int,
  direction direction: Direction,
  outer outer: Frame,
) -> Result(Walk, Halted) {
  let wrappers = case direction {
    ClientToServer -> [encrypted_frame.ClientWrapper]
    ServerToClient -> [encrypted_frame.AuthWrapper, encrypted_frame.GameWrapper]
  }
  let wrapped =
    list.any(wrappers, fn(wrapper) {
      encrypted_frame.message_id(wrapper) == outer.message_id
    })
  case wrapped {
    False ->
      decode(walk:, line:, direction:, inner: outer, carried: Bare, depth: 0)
    True ->
      case encrypted_frame.unwrap(outer:, cipher: walk.cipher) {
        Ok(inner) ->
          decode(walk:, line:, direction:, inner:, carried: Wrapped, depth: 1)
        Error(error) ->
          Error(Halted(walk:, stopped: #(line, WrapperRefused(error:))))
      }
  }
}

/// Decodes one message, and the frame it carries, when it carries one. The game
/// connection's 0x058F re-keys the frames after it, each way.
fn decode(
  walk walk: Walk,
  line line: Int,
  direction direction: Direction,
  inner inner: Frame,
  carried carried: Carried,
  depth depth: Int,
) -> Result(Walk, Halted) {
  let reading = reading_of(direction:, inner:)
  let walk =
    Walk(..walk, opened: [
      Opened(
        line:,
        direction:,
        carried:,
        depth:,
        message_id: inner.message_id,
        body: inner.body,
        reading:,
      ),
      ..walk.opened
    ])
  case reading {
    ServerSent(..) | WithoutDecoder | Malformed(..) -> Ok(walk)
    ClientSent(message:) ->
      case role_of(message) {
        Plain -> Ok(walk)
        HelloReply(session_key:) -> rekey(walk:, line:, session_key:)
        Carrier(frame: bytes) ->
          case frame.parse(whole: bytes) {
            Ok(carried_inner) ->
              decode(
                walk:,
                line:,
                direction:,
                inner: carried_inner,
                carried: Inside(carrier: inner.message_id),
                depth: depth + 1,
              )
            Error(error) ->
              Error(
                Halted(walk:, stopped: #(
                  line,
                  CarriedFrameRefused(carrier: inner.message_id, error:),
                )),
              )
          }
      }
  }
}

/// A message's body read by the decoders of its sender's messages.
fn reading_of(direction direction: Direction, inner inner: Frame) -> Reading {
  case direction {
    ClientToServer ->
      case client_message.decode(inner.message_id, inner.body) {
        Ok(message) -> ClientSent(message:)
        Error(client_message.UnknownMessage(..)) -> WithoutDecoder
        Error(client_message.Malformed(error:, ..)) -> Malformed(error:)
      }
    ServerToClient ->
      case server_message.decode(inner.message_id, inner.body) {
        Ok(message) -> ServerSent(message:)
        Error(server_message.UnknownMessage(..)) -> WithoutDecoder
        Error(server_message.Malformed(error:, ..)) -> Malformed(error:)
      }
  }
}

/// The game connection's cipher once 0x058F has been read: the session key's.
fn rekey(
  walk walk: Walk,
  line line: Int,
  session_key session_key: BitArray,
) -> Result(Walk, Halted) {
  use <- bool.guard(when: !walk.game, return: Ok(walk))
  case game_connection.rekeyed(session_key:) {
    Ok(rekeyed) -> Ok(Walk(..walk, cipher: rekeyed))
    Error(error) -> Error(Halted(walk:, stopped: #(line, KeyRefused(error:))))
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
    | client_message.WorldZoneChanged(..)
    | client_message.MovementSendIntervalAnswer(..)
    | client_message.MoveSpeedSetting(..)
    | client_message.FallValue(..)
    | client_message.FellBelowFloor(..)
    | client_message.SendChatLine(..)
    | client_message.SendWhisper(..)
    | client_message.CastAbility(..)
    | client_message.AbilityHold(..)
    | client_message.CancelCast(..)
    | client_message.ChooseResurrection(..) -> Plain
  }
}

/// Whether a message the client sends carries a whole frame in its body, which
/// is read as the next message, one deeper.
pub fn carries_a_frame(message: ClientMessage) -> Bool {
  case role_of(message) {
    Carrier(..) -> True
    HelloReply(..) | Plain -> False
  }
}
