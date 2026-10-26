//// The rule of one game connection: the hello the server sends on a new
//// connection, the client's 0x58F with the session key inside 0x244 under the
//// base key, then, under the cipher the session key makes, character select
//// and entering the world. Every client message arrives inside 0x244 and
//// every server message leaves inside 0x3DC (records opcode.0x3, opcode.0x58f,
//// opcode.0x244, opcode.0x3dc, opcode.0x25c, opcode.0x38c, opcode.0xf2;
//// HandleLoginGameServerHello 0x140038120).
////
//// The rule decodes each client message into a typed value at this edge and
//// hands it to the rule of its feature: `select` for 0x7E0, 0x25C, 0x352,
//// 0x786 and 0x7DD, and `world_entry` for 0xF2 inside 0x38C. A message that
//// does not decode ends the connection. A message no rule handles is logged
//// once for each message number and the connection goes on.

import genesis_prime/character/select
import genesis_prime/character/world_entry
import genesis_prime/connection/frame.{type Frame}
import genesis_prime/login/account.{type Identity}
import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/message/bit_stream

/// The facts the rules read beyond their state, made by the connection for each
/// input: the time and the tables are read as they are when the input arrives.
pub type Context {
  Context(select: select.Context, entry: world_entry.Context)
}

/// How serious a line the rule asks to be logged is: a warning for an outside
/// failure or a player's mistake the server recovered from, an error for a
/// bug.
pub type Level {
  WarningLevel
  ErrorLevel
}

/// What the map answered when the connection asked it to join the character's
/// unit.
pub type MapAnswer {
  /// The map holds the unit.
  MapJoined(PlayerUnit)
  /// The map refused the character: it is on the map already.
  MapRefusedCharacter
  /// The map or its registry did not answer in time, or could not start.
  MapNotAnswering
}

/// Why the rule ends a connection.
pub type EndReason {
  /// The frame is not a 0x244 wrapper, or its inner frame is malformed.
  BadWrapper
  /// The inner message is not one that belongs at this point of the
  /// connection.
  UnexpectedMessage(message_id: Int)
  /// A message's body does not decode.
  MalformedMessage(message_id: Int, error: bit_stream.DecodeError)
  /// The session key is unknown, used already or expired.
  SessionKeyRefused
  /// Character select was asked for something it takes at no time.
  CharacterSelectBreach(select.Breach)
  /// The world entry was asked for something it takes at no time.
  WorldEntryBreach(world_entry.Breach)
  /// The map did not answer, so the character may or may not be on it.
  MapAway
  /// A message of the answer could not be built.
  AnswerNotBuilt
}

/// What the connection carries out, in order.
pub type Effect {
  /// Send these bytes: a whole frame, wrapped.
  Send(bytes: BitArray)
  /// Redeem the session key whose 16 bytes these are, then answer with
  /// `session_key_redeemed`.
  RedeemSessionKey(key: BitArray)
  /// Ask the store; its answer goes to `stored`.
  Store(select.Command)
  /// Ask the world's map to join the character's unit; its answer goes to
  /// `map_answered`.
  JoinMap(world_id: Int, newcomer: Newcomer)
  /// Log a line.
  Log(level: Level, text: String)
  /// End the connection, and log why.
  End(reason: EndReason)
}

/// Where a connection is.
pub opaque type Session {
  Session(stage: Stage, unhandled: List(Int))
}

type Stage {
  Placeholder
}

/// A new connection and the effects it starts with: the hello.
pub fn start() -> #(Session, List(Effect)) {
  todo as "the hello under the base key"
}

/// The effects of a frame the client sent.
pub fn receive(
  session session: Session,
  frame frame: Frame,
  context context: Context,
) -> #(Session, List(Effect)) {
  todo as "route a frame"
}

/// The effects of the session key's redemption: who it was issued to, or
/// why not.
pub fn session_key_redeemed(
  session session: Session,
  identity identity: Result(Identity, Nil),
) -> #(Session, List(Effect)) {
  todo as "the session key's answer"
}

/// The effects of the store's answer.
pub fn stored(
  session session: Session,
  answer answer: select.Answer,
  context context: Context,
) -> #(Session, List(Effect)) {
  todo as "the store's answer"
}

/// The effects of the map's answer.
pub fn map_answered(
  session session: Session,
  answer answer: MapAnswer,
  context context: Context,
) -> #(Session, List(Effect)) {
  todo as "the map's answer"
}

/// The effects of a delivery from the map: a unit in range appeared or went.
pub fn delivered(
  session session: Session,
  delivery delivery: Delivery,
  context context: Context,
) -> #(Session, List(Effect)) {
  todo as "a delivery"
}

/// A sentence that says why the connection ended, for the log.
pub fn describe(reason reason: EndReason) -> String {
  todo as "describe an end"
}

/// How serious the log line of an end is.
pub fn level_of(reason reason: EndReason) -> Level {
  todo as "the level of an end"
}
