//// The rule of one game connection: the hello the server sends on a new
//// connection, the client's 0x58F with the session key inside 0x244 under the
//// base key, then, under the cipher the session key makes, character select
//// and entering the world. Every client message arrives inside 0x244 and
//// every server message leaves inside 0x3DC (records opcode.0x3, opcode.0x58f,
//// opcode.0x244, opcode.0x3dc, opcode.0x25c, opcode.0x38c, opcode.0xf2;
//// HandleLoginGameServerHello 0x140038120).
////
//// The network layer's own messages 0, 1 and 2 (ping, pong, close notice) are
//// read first, bare, in every state (`network_message`).
////
//// The rule decodes each client message into a typed value at this edge and
//// hands it to the rule of its feature: `select` for 0x7E0, 0x25C, 0x352,
//// 0x786 and 0x7DD, and `world_entry` for 0xF2 inside 0x38C. A message that
//// does not decode ends the connection. A message no rule handles is logged
//// once for each message number and the connection goes on.

import genesis_prime/character/customisation
import genesis_prime/character/select
import genesis_prime/character/server_message.{type ServerMessage}
import genesis_prime/character/world_entry
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/connection/network_message
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/auth_session
import genesis_prime/map/delivery.{type Delivery, Appeared, Disappeared}
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}
import genesis_prime/message/bit_stream
import genesis_prime/message/character_select_start
import genesis_prime/message/create_character
import genesis_prime/message/delete_character
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/game_hello_reply
import genesis_prime/message/play_character
import genesis_prime/message/rename_character
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/message/terrain_loaded
import genesis_prime/message/unit_destroyed.{UnitDestroyed}
import genesis_prime/message/world_message
import gleam/bool
import gleam/int
import gleam/list
import gleam/result
import gleam/string

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
  /// The database did not give the characters character select needed.
  StoreAway(select.Outage)
  /// The account logged in again, so the new connection ended this one.
  SessionTakenOver
  /// The connection that held the account's slot did not end in time, or the
  /// registry of the sessions did not answer.
  SessionNotFreed
  /// The map process that held the character's unit ended, and a map that
  /// starts again is empty, so the unit is gone.
  MapEnded
  /// The map did not answer, so the character may or may not be on it.
  MapAway
  /// A message of the answer could not be built.
  AnswerNotBuilt
}

/// Whether the connection took its account's slot: no other connection of the
/// account is left.
pub type Claim {
  SlotFree
  SlotNotFreed
}

/// What the connection carries out, in order.
pub type Effect {
  /// Send these bytes: a whole frame, wrapped, or the bare pong that answers a
  /// ping.
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
  Session(stage: Stage, cipher: Cipher, unhandled: List(Int))
}

/// The stages of a connection: waiting for 0x58F under the base key, waiting
/// for the hand-off to say who the session key stands for, playing under the
/// session key's cipher, or ended.
type Stage {
  AwaitingKey
  RedeemingKey(key: BitArray)
  Playing(select: select.State, entry: world_entry.State)
  Ended
}

/// The message every client message travels in (opcode.0x244).
const wrapper_message = 0x0244

/// The reason of message 0x36A that tells a player the account was
/// disconnected: 19, whose text is 'This account has been disconnected'. No
/// reason says the account logged in elsewhere, and which one retail sent is not
/// in the client, so 19, the only one about the account, is a guess
/// (opcode.0x36a).
const reason_account_disconnected = 19

/// The first message on a game connection (opcode.0x58f).
const key_message = 0x058F

/// A new connection and the effects it starts with: the hello, message 3
/// inside 0x3DC under the base key (opcode.0x3, opcode.0x3dc), with the build
/// and checksum the client checks.
pub fn start() -> #(Session, List(Effect)) {
  let assert Ok(base_cipher) = cipher.new(cipher.base_key)
    as "the base key is not zero"
  let session = Session(stage: AwaitingKey, cipher: base_cipher, unhandled: [])
  let hello =
    ServerHello(
      build: auth_session.build,
      field_2: 0,
      field_3: 0,
      field_4: 0,
      field_5: 0,
      field_6: 0,
      field_7: 0,
      message_table_checksum: auth_session.message_table_checksum,
      field_9: 0,
      field_10: 0,
      field_11: 0,
    )
  let assert Ok(body) = server_hello.encode(hello)
    as "the hello's values fit their fields"
  case wrap(cipher: base_cipher, id: server_hello.message_id, body:) {
    Ok(bytes) -> #(session, [Send(bytes)])
    Error(Nil) -> panic as "the hello is far below the size limit"
  }
}

/// The effects of a frame the client sent.
pub fn receive(
  session session: Session,
  frame frame: Frame,
  context context: Context,
) -> #(Session, List(Effect)) {
  case session.stage {
    Ended -> #(session, [])
    AwaitingKey | RedeemingKey(_) | Playing(..) ->
      case network_message.handle(frame) {
        network_message.Answer(bytes:) -> #(session, [Send(bytes)])
        network_message.Accepted -> #(session, [])
        network_message.Malformed(message_id:, error:) ->
          end(session, MalformedMessage(message_id, error))
        network_message.NotNetwork -> wrapped(session:, frame:, context:)
      }
  }
}

/// A frame that is not the network layer's: it must be a 0x244 wrapper.
fn wrapped(
  session session: Session,
  frame frame: Frame,
  context context: Context,
) -> #(Session, List(Effect)) {
  case frame.message_id == wrapper_message {
    False -> end(session, BadWrapper)
    True ->
      case encrypted_frame.unwrap(frame, session.cipher) {
        Error(encrypted_frame.NotAWrapper(_))
        | Error(encrypted_frame.BadFrame(_)) -> end(session, BadWrapper)
        Ok(inner) -> routed(session:, inner:, context:)
      }
  }
}

fn routed(
  session session: Session,
  inner inner: Frame,
  context context: Context,
) -> #(Session, List(Effect)) {
  case session.stage {
    AwaitingKey ->
      case inner.message_id == key_message {
        False -> end(session, UnexpectedMessage(inner.message_id))
        True ->
          case game_hello_reply.decode(inner.body) {
            Error(error) ->
              end(session, MalformedMessage(inner.message_id, error))
            Ok(reply) -> #(
              Session(..session, stage: RedeemingKey(reply.session_key)),
              [RedeemSessionKey(reply.session_key)],
            )
          }
      }
    RedeemingKey(_) -> end(session, UnexpectedMessage(inner.message_id))
    Playing(select: select_state, entry: entry_state) ->
      case player_input(session:, inner:, context:) {
        Error(reason) -> end(session, reason)
        Ok(Unhandled) -> unhandled(session, inner.message_id)
        Ok(ToSelect(input)) ->
          playing(session:, run: fn() {
            apply_select(
              cipher: session.cipher,
              context:,
              select_state:,
              entry_state:,
              input:,
            )
          })
        Ok(ToEntry(input)) ->
          playing(session:, run: fn() {
            apply_entry(
              cipher: session.cipher,
              context:,
              select_state:,
              entry_state:,
              input:,
            )
          })
      }
    Ended -> #(session, [])
  }
}

/// What a message of a playing connection is for.
type PlayerInput {
  ToSelect(select.Input)
  ToEntry(world_entry.Input)
  Unhandled
}

/// Decodes the message of a playing connection into the input of the rule it
/// belongs to, or says why it ends the connection.
fn player_input(
  session session: Session,
  inner inner: Frame,
  context context: Context,
) -> Result(PlayerInput, EndReason) {
  case inner.message_id {
    0x07E0 ->
      character_select_start.decode(inner.body)
      |> decoded(inner.message_id, fn(_) { ToSelect(select.Started) })
    0x025C -> {
      use created <- result.try(
        encrypted_frame.unwrap(inner, session.cipher)
        |> result.replace_error(BadWrapper),
      )
      case created.message_id == create_character.message_id {
        False -> Error(UnexpectedMessage(created.message_id))
        True ->
          create_character.decode(created.body)
          |> result.try(fn(request) {
            customisation.within_limits(
              context.select.customisation,
              labels: list.length(request.customisation_labels),
              bones: list.length(request.bone_values),
            )
            |> result.replace(request)
          })
          |> decoded(created.message_id, fn(request) {
            ToSelect(select.Requested(select.CreateRequested(request)))
          })
      }
    }
    0x0352 ->
      delete_character.decode(inner.body)
      |> decoded(inner.message_id, fn(request) {
        ToSelect(select.Requested(select.DeleteRequested(request)))
      })
    0x0786 ->
      rename_character.decode(inner.body)
      |> decoded(inner.message_id, fn(request) {
        ToSelect(select.Requested(select.RenameRequested(request)))
      })
    0x07DD ->
      play_character.decode(inner.body)
      |> decoded(inner.message_id, fn(request) {
        ToSelect(select.Requested(select.PlayRequested(request)))
      })
    0x038C -> world_input(inner)
    _ -> Ok(Unhandled)
  }
}

/// The world message inside message 0x38C: 0xF2 says the terrain is loaded; any
/// other is not handled.
fn world_input(inner: Frame) -> Result(PlayerInput, EndReason) {
  use carried <- result.try(
    world_message.decode(inner.body)
    |> result.map_error(fn(error) { MalformedMessage(inner.message_id, error) }),
  )
  use world <- result.try(
    frame.parse(carried.inner_frame) |> result.replace_error(BadWrapper),
  )
  case world.message_id == terrain_loaded.message_id {
    False -> Ok(Unhandled)
    True ->
      terrain_loaded.decode(world.body)
      |> decoded(world.message_id, fn(_) { ToEntry(world_entry.TerrainLoaded) })
  }
}

fn decoded(
  decoding: Result(a, bit_stream.DecodeError),
  message_id: Int,
  make: fn(a) -> PlayerInput,
) -> Result(PlayerInput, EndReason) {
  case decoding {
    Ok(message) -> Ok(make(message))
    Error(error) -> Error(MalformedMessage(message_id:, error:))
  }
}

/// A message no rule handles: logged once for each message number.
fn unhandled(session: Session, message_id: Int) -> #(Session, List(Effect)) {
  use <- bool.guard(
    when: list.contains(session.unhandled, message_id),
    return: #(session, []),
  )
  #(Session(..session, unhandled: [message_id, ..session.unhandled]), [
    Log(
      WarningLevel,
      "message " <> hex(message_id) <> " is not handled by the game server",
    ),
  ])
}

/// The new stage and the effects of a run of the rules of a playing
/// connection.
fn playing(
  session session: Session,
  run run: fn() -> #(select.State, world_entry.State, List(Effect)),
) -> #(Session, List(Effect)) {
  let #(select_state, entry_state, effects) = run()
  let stage = case list.any(effects, is_end) {
    True -> Ended
    False -> Playing(select: select_state, entry: entry_state)
  }
  #(Session(..session, stage:), effects)
}

fn is_end(effect: Effect) -> Bool {
  case effect {
    End(_) -> True
    Send(_) | RedeemSessionKey(_) | Store(_) | JoinMap(..) | Log(..) -> False
  }
}

/// Gives the input to character select and carries its effects into the
/// session's, in order.
fn apply_select(
  cipher cipher: Cipher,
  context context: Context,
  select_state select_state: select.State,
  entry_state entry_state: world_entry.State,
  input input: select.Input,
) -> #(select.State, world_entry.State, List(Effect)) {
  let #(select_state, effects) =
    select.decide(select_state, input, context.select)
  list.fold(effects, #(select_state, entry_state, []), fn(acc, effect) {
    let #(select_state, entry_state, done) = acc
    let #(select_state, entry_state, more) = case effect {
      select.Store(command) -> #(select_state, entry_state, [Store(command)])
      select.Send(message) -> #(select_state, entry_state, [
        sent(cipher:, message:),
      ])
      select.Log(refusal) -> #(select_state, entry_state, [
        Log(
          case refusal {
            select.StoreUnavailable -> ErrorLevel
            select.NameRefused(_)
            | select.CreationUnknown(_)
            | select.CreationNotOffered(_)
            | select.PathOutOfRange(_)
            | select.TooManyCustomisations(_)
            | select.NoStartingPlace(_)
            | select.NameTaken
            | select.NotYourCharacter(_)
            | select.CharacterDisabled(_)
            | select.CharacterRequiresRename(_)
            | select.CharacterOnline(_)
            | select.BoneCountWrong(..)
            | select.LabelRefused(_)
            | select.AccountFull(_) -> WarningLevel
          },
          select.describe_refusal(refusal),
        ),
      ])
      select.Close(breach) -> #(select_state, entry_state, [
        End(CharacterSelectBreach(breach)),
      ])
      select.Abandon(outage) -> #(select_state, entry_state, [
        End(StoreAway(outage)),
      ])
      select.BeginWorldEntry(character) ->
        apply_entry(
          cipher:,
          context:,
          select_state:,
          entry_state:,
          input: world_entry.Begin(character),
        )
    }
    #(select_state, entry_state, list.append(done, more))
  })
}

/// Gives the input to the world entry and carries its effects into the
/// session's, in order.
fn apply_entry(
  cipher cipher: Cipher,
  context context: Context,
  select_state select_state: select.State,
  entry_state entry_state: world_entry.State,
  input input: world_entry.Input,
) -> #(select.State, world_entry.State, List(Effect)) {
  let #(entry_state, effects) =
    world_entry.decide(entry_state, input, context.entry)
  list.fold(effects, #(select_state, entry_state, []), fn(acc, effect) {
    let #(select_state, entry_state, done) = acc
    let #(select_state, entry_state, more) = case effect {
      world_entry.JoinMap(world_id:, newcomer:) -> #(select_state, entry_state, [
        JoinMap(world_id:, newcomer:),
      ])
      world_entry.Send(message) -> #(select_state, entry_state, [
        sent(cipher:, message:),
      ])
      world_entry.Failed ->
        apply_select(
          cipher:,
          context:,
          select_state:,
          entry_state:,
          input: select.WorldEntryRefused,
        )
      world_entry.Close(breach) -> #(select_state, entry_state, [
        End(WorldEntryBreach(breach)),
      ])
    }
    #(select_state, entry_state, list.append(done, more))
  })
}

/// A message of the server as the bytes of its 0x3DC frame, or the end that
/// building it would be.
fn sent(cipher cipher: Cipher, message message: ServerMessage) -> Effect {
  let built =
    server_message.encode(message)
    |> result.replace_error(Nil)
    |> result.try(fn(numbered) {
      wrap(cipher:, id: numbered.0, body: numbered.1)
    })
  case built {
    Ok(bytes) -> Send(bytes)
    Error(Nil) -> End(AnswerNotBuilt)
  }
}

/// A message inside 0x3DC under the cipher.
fn wrap(
  cipher cipher: Cipher,
  id id: Int,
  body body: BitArray,
) -> Result(BitArray, Nil) {
  encrypted_frame.wrap(GameWrapper, Frame(message_id: id, body:), cipher)
  |> result.replace_error(Nil)
}

/// The effects of the session key's redemption: who it was issued to, or
/// why not. A redeemed key makes the cipher both ways use from then on
/// (HandleLoginGameServerHello 0x140038120), and starts character select for
/// the account.
pub fn session_key_redeemed(
  session session: Session,
  identity identity: Result(Identity, Nil),
) -> #(Session, List(Effect)) {
  case session.stage, identity {
    RedeemingKey(key:), Ok(account) -> {
      let assert Ok(made) = cipher.session_key(key, cipher.base_key)
        as "a session key in 0x58F is 16 bytes"
      let assert Ok(session_cipher) = cipher.new(made)
        as "a session key makes a cipher"
      #(
        Session(
          ..session,
          cipher: session_cipher,
          stage: Playing(
            select: select.new(account_id: account.id),
            entry: world_entry.new(),
          ),
        ),
        [],
      )
    }
    RedeemingKey(_), Error(Nil) -> end(session, SessionKeyRefused)
    Ended, _ -> #(session, [])
    AwaitingKey, _ | Playing(..), _ ->
      panic as "a session key was redeemed that the rule did not ask for"
  }
}

/// The effects of the store's answer.
pub fn stored(
  session session: Session,
  answer answer: select.Answer,
  context context: Context,
) -> #(Session, List(Effect)) {
  case session.stage {
    Playing(select: select_state, entry: entry_state) ->
      playing(session:, run: fn() {
        apply_select(
          cipher: session.cipher,
          context:,
          select_state:,
          entry_state:,
          input: select.Stored(answer),
        )
      })
    Ended -> #(session, [])
    AwaitingKey | RedeemingKey(_) ->
      panic as "the store answered a command the rule did not give"
  }
}

/// The effects of the map's answer. A map that did not answer may hold the
/// unit, so the connection ends, which takes the unit off the map.
pub fn map_answered(
  session session: Session,
  answer answer: MapAnswer,
  context context: Context,
) -> #(Session, List(Effect)) {
  case session.stage, answer {
    Playing(select: select_state, entry: entry_state), MapJoined(unit) ->
      playing(session:, run: fn() {
        apply_entry(
          cipher: session.cipher,
          context:,
          select_state:,
          entry_state:,
          input: world_entry.Joined(unit),
        )
      })
    Playing(select: select_state, entry: entry_state), MapRefusedCharacter ->
      playing(session:, run: fn() {
        apply_entry(
          cipher: session.cipher,
          context:,
          select_state:,
          entry_state:,
          input: world_entry.MapRefused,
        )
      })
    Playing(..), MapNotAnswering -> end(session, MapAway)
    Ended, _ -> #(session, [])
    AwaitingKey, _ | RedeemingKey(_), _ ->
      panic as "the map answered a request the rule did not make"
  }
}

/// The effects of the answer to taking the account's slot: a slot that is not
/// free ends the connection.
pub fn account_claimed(
  session session: Session,
  claim claim: Claim,
) -> #(Session, List(Effect)) {
  case session.stage, claim {
    Ended, _ -> #(session, [])
    _, SlotFree -> #(session, [])
    _, SlotNotFreed -> end(session, SessionNotFreed)
  }
}

/// The effects of a second login of the account: the player is told the account
/// was disconnected (0x36A) and the connection ends. The unit is taken off the
/// map by the connection before it ends.
pub fn taken_over(session session: Session) -> #(Session, List(Effect)) {
  case session.stage {
    Ended -> #(session, [])
    AwaitingKey | RedeemingKey(_) | Playing(..) -> {
      let #(ended, ending) = end(session, SessionTakenOver)
      #(ended, [
        sent(
          cipher: session.cipher,
          message: server_message.Disconnected(DisconnectNotice(
            reason: reason_account_disconnected,
          )),
        ),
        ..ending
      ])
    }
  }
}

/// The effects of the end of the map process that holds the character's unit,
/// which the connection watches from the moment the map joined the unit: the
/// connection ends, because a map that starts again holds none of its players.
pub fn map_ended(session session: Session) -> #(Session, List(Effect)) {
  case session.stage {
    Ended -> #(session, [])
    AwaitingKey | RedeemingKey(_) | Playing(..) -> end(session, MapEnded)
  }
}

/// The effects of a delivery from the map: a unit in range appeared (0x262
/// creates it) or went (0x355 removes it).
pub fn delivered(
  session session: Session,
  delivery delivery: Delivery,
  context context: Context,
) -> #(Session, List(Effect)) {
  case session.stage {
    Playing(..) -> {
      let message = case delivery {
        Appeared(unit:) ->
          server_message.UnitCreated(world_entry.unit_create(
            unit:,
            realm_id: context.entry.realm_id,
          ))
        Disappeared(unit_id:) ->
          server_message.UnitRemoved(UnitDestroyed(unit_id:, field_2: 0))
      }
      #(session, [sent(cipher: session.cipher, message:)])
    }
    AwaitingKey | RedeemingKey(_) | Ended -> #(session, [])
  }
}

/// Ends the connection: the session takes no more.
fn end(session: Session, reason: EndReason) -> #(Session, List(Effect)) {
  #(Session(..session, stage: Ended), [End(reason:)])
}

/// A message number as the client's records write it: four hex digits.
fn hex(number: Int) -> String {
  "0x" <> string.pad_start(int.to_base16(number), 4, "0")
}

/// A sentence that says why the connection ended, for the log.
pub fn describe(reason reason: EndReason) -> String {
  case reason {
    BadWrapper ->
      "the frame is not a 0x0244 wrapper around a whole frame, or the message inside it is not carried as the client carries it"
    UnexpectedMessage(message_id:) ->
      "message "
      <> hex(message_id)
      <> " does not belong at this point of the connection"
    MalformedMessage(message_id:, error:) ->
      "message "
      <> hex(message_id)
      <> " does not decode: "
      <> describe_decoding(error)
    SessionKeyRefused -> "the session key is unknown, used already or expired"
    CharacterSelectBreach(breach) -> select.describe_breach(breach)
    WorldEntryBreach(breach) -> world_entry.describe_breach(breach)
    StoreAway(outage) -> select.describe_outage(outage)
    SessionTakenOver ->
      "the account logged in again, so the new connection ended this one"
    SessionNotFreed ->
      "the connection that held the account's slot did not end in time, or the registry of the sessions did not answer"
    MapEnded ->
      "the map that held the character's unit ended, and a map that starts again is empty, so the connection ends and the player enters again"
    MapAway ->
      "the map did not answer in time, so the connection ends and the map takes the unit off with it"
    AnswerNotBuilt -> "a message of the answer could not be built"
  }
}

fn describe_decoding(error: bit_stream.DecodeError) -> String {
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

/// How serious the log line of an end is: a message the server could not
/// build is a bug; a map that did not answer and a database that gave no list
/// are outside failures the server cannot repair, logged as errors; a map that
/// ended is an outside failure the server recovered from, a warning, as is
/// every end that is a client's or a player's doing.
pub fn level_of(reason reason: EndReason) -> Level {
  case reason {
    AnswerNotBuilt | MapAway | StoreAway(_) | SessionNotFreed -> ErrorLevel
    SessionTakenOver
    | MapEnded
    | BadWrapper
    | UnexpectedMessage(_)
    | MalformedMessage(..)
    | SessionKeyRefused
    | CharacterSelectBreach(_)
    | WorldEntryBreach(_) -> WarningLevel
  }
}
