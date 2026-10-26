//// The rule of one auth-server connection: the hello the server sends on a
//// new connection, the client's login request 0x592 inside 0x244 under the
//// base key, and the answer, 0x591 and then the hand-off 0x3DB, each inside
//// 0x76 under the base key (records opcode.0x3, opcode.0x592, opcode.0x591,
//// opcode.0x3db, opcode.0x76, opcode.0x244; CheckAuthServerVersion
//// 0x140037b70, SendAuthLoginRequest 0x14003a620).
////
//// The login request is checked against what the STS login settled: the
//// build is 16042, the account name is the STS login's (compared in lower
//// case), the first GUID is its UserId and the second is the game token it
//// issued, which the rule redeems. A file digest that is not the expected one
//// is logged and the login goes on.

import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/message/bit_stream
import genesis_prime/message/game_server_handoff.{GameServerHandoff}
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/login_request
import genesis_prime/message/server_hello.{ServerHello}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// The build the client sends and checks (CheckAuthServerVersion 0x140037b70).
pub const build = 16_042

/// The message table checksum the client checks in the hello
/// (CheckAuthServerVersion 0x140037b70).
pub const message_table_checksum = 0x097998A0

/// What the rule needs to hand a client to the game server.
pub type Settings {
  Settings(
    game_server: bit_stream.Endpoint,
    realm_name: String,
    expected_files_digest: Option(Int),
  )
}

/// Where a connection is in the login.
pub opaque type Session {
  Session(settings: Settings, cipher: Cipher, state: State)
}

type State {
  AwaitingLoginRequest
  RedeemingToken(account_name: String, user_id: Guid)
  Handed
  Ended
}

/// What the connection carries out, in order.
pub type Effect {
  /// Send these bytes: a whole frame, wrapped when it is a reply.
  Send(bytes: BitArray)
  /// Redeem the game token whose 16 bytes these are, then answer with
  /// `token_redeemed`.
  RedeemGameToken(key: BitArray)
  /// Issue a session key for this identity for the game server's 0x58F check,
  /// then answer with `session_key_issued`.
  IssueSessionKey(identity: Identity)
  /// The client's file digest is not the expected one; the login goes on.
  LogDigestMismatch(received: Int, expected: Int)
  /// End the connection, and log why.
  End(reason: EndReason)
}

/// Why the rule ends a connection.
pub type EndReason {
  /// The frame is not a 0x244 wrapper, or its inner frame is malformed.
  BadWrapper
  /// The inner message is not the login request at this point of the login.
  UnexpectedMessage(message_id: Int)
  /// The login request's body is not message 0x592.
  MalformedLoginRequest(error: bit_stream.DecodeError)
  /// The build is not 16042.
  WrongBuild(received: Int)
  /// The game token is unknown or expired.
  TokenRefused
  /// The account name or the UserId is not the STS login's.
  IdentityMismatch
  /// A frame or a message of the answer could not be built.
  AnswerNotBuilt
}

/// A new connection and the effects it starts with: the hello.
pub fn start(settings settings: Settings) -> #(Session, List(Effect)) {
  let assert Ok(base_cipher) = cipher.new(cipher.base_key)
    as "the base key is not zero"
  let hello =
    ServerHello(
      build:,
      field_2: 0,
      field_3: 0,
      field_4: 0,
      field_5: 0,
      field_6: 0,
      field_7: 0,
      message_table_checksum:,
      field_9: 0,
      field_10: 0,
      field_11: 0,
    )
  let assert Ok(body) = server_hello.encode(hello)
    as "the hello's values fit their fields"
  let assert Ok(bytes) = frame.encode(0x0003, body)
    as "the hello is far below the size limit"
  #(Session(settings:, cipher: base_cipher, state: AwaitingLoginRequest), [
    Send(bytes),
  ])
}

/// The effects of a frame the client sent.
pub fn receive(
  session session: Session,
  frame frame: Frame,
) -> #(Session, List(Effect)) {
  case session.state {
    Ended -> #(session, [])
    AwaitingLoginRequest | RedeemingToken(..) | Handed ->
      case
        frame.message_id
        == encrypted_frame.message_id(encrypted_frame.ClientWrapper)
      {
        False -> end(session, BadWrapper)
        True ->
          case encrypted_frame.unwrap(frame, session.cipher) {
            Error(encrypted_frame.NotAWrapper(_))
            | Error(encrypted_frame.BadFrame(_)) -> end(session, BadWrapper)
            Ok(inner) ->
              case session.state, inner.message_id {
                AwaitingLoginRequest, 0x0592 ->
                  read_login_request(session, inner)
                AwaitingLoginRequest, message_id
                | RedeemingToken(..), message_id
                | Handed, message_id
                | Ended, message_id
                -> end(session, UnexpectedMessage(message_id:))
              }
          }
      }
  }
}

/// The checks of the login request that need no other process.
fn read_login_request(
  session: Session,
  inner: Frame,
) -> #(Session, List(Effect)) {
  case login_request.decode(inner.body) {
    Error(error) -> end(session, MalformedLoginRequest(error:))
    Ok(request) ->
      case request.build == build {
        False -> end(session, WrongBuild(received: request.build))
        True -> {
          let assert Ok(user_id) = guid.from_wire(request.field_4)
            as "the request's GUIDs are 16 bytes"
          let logged = case session.settings.expected_files_digest {
            Some(expected) if expected != request.files_digest -> [
              LogDigestMismatch(received: request.files_digest, expected:),
            ]
            Some(_) | None -> []
          }
          #(
            Session(
              ..session,
              state: RedeemingToken(
                account_name: string.lowercase(request.account_name),
                user_id:,
              ),
            ),
            list.append(logged, [RedeemGameToken(request.field_5)]),
          )
        }
      }
  }
}

/// The effects of the game token's redemption: who it was issued to, or why
/// not.
pub fn token_redeemed(
  session session: Session,
  identity identity: Result(Identity, Nil),
) -> #(Session, List(Effect)) {
  case session.state, identity {
    RedeemingToken(account_name:, user_id:), Ok(issued) ->
      case issued.name == account_name && issued.user_id == user_id {
        True -> #(session, [IssueSessionKey(issued)])
        False -> end(session, IdentityMismatch)
      }
    RedeemingToken(..), Error(Nil) -> end(session, TokenRefused)
    Ended, _ -> #(session, [])
    AwaitingLoginRequest, _ | Handed, _ ->
      panic as "a token was redeemed that the rule did not ask for"
  }
}

/// The effects of the session key issued: its 16 bytes.
pub fn session_key_issued(
  session session: Session,
  key key: BitArray,
) -> #(Session, List(Effect)) {
  case session.state {
    RedeemingToken(..) ->
      case answer(session, key) {
        Ok(sends) -> #(Session(..session, state: Handed), sends)
        Error(reason) -> end(session, reason)
      }
    Ended -> #(session, [])
    AwaitingLoginRequest | Handed ->
      panic as "a session key was issued that the rule did not ask for"
  }
}

/// 0x591 and then the hand-off 0x3DB, each in a 0x76 wrapper.
fn answer(session: Session, key: BitArray) -> Result(List(Effect), EndReason) {
  let settings = session.settings
  use accepted <- result.try(
    login_accepted.encode(LoginAccepted(field_1: 0))
    |> result.replace_error(AnswerNotBuilt),
  )
  use session_key <- result.try(
    guid.from_wire(key) |> result.replace_error(AnswerNotBuilt),
  )
  use handoff <- result.try(
    game_server_handoff.encode(GameServerHandoff(
      game_server: settings.game_server,
      session_key: guid.to_wire(session_key),
      field_3: 0,
      realm_name: settings.realm_name,
      field_5: 0,
      field_6: 0,
      field_7: 0,
    ))
    |> result.replace_error(AnswerNotBuilt),
  )
  use first <- result.try(wrapped(session:, message_id: 0x0591, body: accepted))
  use second <- result.map(wrapped(session:, message_id: 0x03DB, body: handoff))
  [Send(first), Send(second)]
}

fn wrapped(
  session session: Session,
  message_id message_id: Int,
  body body: BitArray,
) -> Result(BitArray, EndReason) {
  encrypted_frame.wrap(
    encrypted_frame.AuthWrapper,
    Frame(message_id:, body:),
    session.cipher,
  )
  |> result.replace_error(AnswerNotBuilt)
}

/// Ends the connection: the session takes no more.
fn end(session: Session, reason: EndReason) -> #(Session, List(Effect)) {
  #(Session(..session, state: Ended), [End(reason:)])
}

/// A sentence that says why the connection ended, for the log.
pub fn describe(reason reason: EndReason) -> String {
  case reason {
    BadWrapper -> "the frame is not a 0x0244 wrapper around a whole frame"
    UnexpectedMessage(message_id:) ->
      "message "
      <> int.to_string(message_id)
      <> " does not belong at this point of the login"
    MalformedLoginRequest(error:) ->
      "the login request does not decode: " <> decode_error(error)
    WrongBuild(received:) ->
      "the client's build is "
      <> int.to_string(received)
      <> ", not "
      <> int.to_string(build)
    TokenRefused -> "the game token is unknown or expired"
    IdentityMismatch -> "the account name or the UserId is not the STS login's"
    AnswerNotBuilt -> "the answer could not be built"
  }
}

fn decode_error(error: bit_stream.DecodeError) -> String {
  case error {
    bit_stream.EndOfData -> "the bytes end inside a field"
    bit_stream.TrailingBytes(count:) ->
      int.to_string(count) <> " bytes follow the last field"
    bit_stream.InvalidText -> "a text is not valid UTF-16"
    bit_stream.InvalidCountedText -> "a counted text is not valid"
    bit_stream.InnerFrameTooShort(length:) ->
      "an inner frame's length is " <> int.to_string(length)
    bit_stream.UnexpectedValue(field:, value:) ->
      "the field " <> field <> " holds " <> int.to_string(value)
  }
}
