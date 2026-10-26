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
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/message/bit_stream
import gleam/option.{type Option}

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
  todo as "the hello"
}

/// The effects of a frame the client sent.
pub fn receive(
  session session: Session,
  frame frame: Frame,
) -> #(Session, List(Effect)) {
  todo as "the rule for a frame"
}

/// The effects of the game token's redemption: who it was issued to, or why
/// not.
pub fn token_redeemed(
  session session: Session,
  identity identity: Result(Identity, Nil),
) -> #(Session, List(Effect)) {
  todo as "the rule for the redemption"
}

/// The effects of the session key issued: its 16 bytes.
pub fn session_key_issued(
  session session: Session,
  key key: BitArray,
) -> #(Session, List(Effect)) {
  todo as "the answer"
}

/// A sentence that says why the connection ended, for the log.
pub fn describe(reason reason: EndReason) -> String {
  todo as "the reason in words"
}
