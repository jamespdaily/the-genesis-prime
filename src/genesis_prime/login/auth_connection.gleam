//// The rule of one auth connection: the login the client makes with the game
//// token from the STS login, to the hand-off to a game server. It decides
//// everything; its connection shell carries it out
//// (genesis_prime/connection/shell).
////
//// ```
//// client                          rule                              asks
//// connects                     ◀─ hello 0x3, bare
////                              ◀─ the planted frame, when the dev start sets one
//// 0x592 in 0x244               ─▶ build 16042? else 0x63d 19
////                                                                ─▶ hand-off: Take(GameToken)
////   Taken(holder), UserId is the holder's   ─▶ session key from the seed
////                                                                ─▶ hand-off: Put(SessionKey)
////     Kept                     ◀─ 0x591, then 0x3db, each in 0x76
////   NoHolder, or another UserId ◀─ 0x63d 16, then the connection ends
//// ping 0x0                     ◀─ pong 0x1, bare
//// ```
////
//// - **The hello** carries build 16042 and checksum 0x097998A0, which the
////   client checks (0x140037b70), the realm's id, and 0 in every field the
////   client never reads (opcode.0x3).
//// - **0x591** is not disconnected for lag (opcode.0x591). **0x3db** names the
////   game server, the session key, the account's id (stable per account: the
////   client names the addon save folder after it), the realm's name, flags 0,
////   PvE and no realm note (opcode.0x3db).
//// - **Refusals** are 0x63d, then the connection ends: reason 16, "Invalid
////   Login Token", for a token never kept, already taken or expired, or a
////   UserId other than the token's account; 19 for a build other than 16042;
////   12, "NCSoft login service finish timeout", with a warning, when the
////   hand-off gives no answer, since the failure is the server's
////   (opcode.0x63d).
//// - **Ciphers.** The hello and the ping's pong travel bare; every other
////   frame each way travels in the wrapper (0x244 from the client, 0x76 to it)
////   under the client's base key (genesis_prime/connection/encrypted_frame).
//// - **Out of order.** A frame the client's reader would refuse ends the
////   connection; a whole frame of a message the rule does not take is logged
////   as unhandled and the connection goes on.

import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{AuthWrapper, ClientWrapper}
import genesis_prime/connection/frame.{type Frame, Frame}
import genesis_prime/connection/network_message
import genesis_prime/hand_off.{type Holder, GameToken, Put, SessionKey, Take}
import genesis_prime/login.{
  type Answer, type Request, AskHandOff, FromHandOff, FromStore,
}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/message/bit_stream.{type Endpoint}
import genesis_prime/message/game_server_handoff.{GameServerHandoff}
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/login_refused.{LoginRefused}
import genesis_prime/message/login_request
import genesis_prime/message/server_hello.{ServerHello}
import genesis_prime/random.{type Random}
import genesis_prime/step.{
  type About, type ConnectionId, type Effect, type Input, type Now, type Outcome,
  type Peer, type Step, About, Accepted, Answered, AnsweredLate, AskId, Asked,
  Effects, EffectsThenAsk, Log, LogError, LogInfo, LogLine, LogWarning,
  PeerClosed, ReadFailed, Socket, Started, Stop, Stopping, TimerFired, Woken,
  Write, WriteFailed,
}
import genesis_prime/store
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// The realm the client is handed to.
pub type Realm {
  Realm(
    /// The realm's id, the same the game server's realm messages carry.
    id: Int,
    /// Its name, which also names the client's realm settings file.
    name: String,
    /// The game server the client connects to next.
    game_server: Endpoint,
  )
}

/// What every auth connection is made with, at start.
pub type Settings {
  Settings(
    realm: Realm,
    /// How long an ask to the hand-off may take.
    ask_deadline_ms: Int,
    /// How long a session key stays good in the hand-off: the client shows
    /// it to the game server right after it gets it.
    session_key_lifetime_ms: Int,
    /// A frame sent right after the hello, in the auth wrapper, that the
    /// client does not handle; only the dev start sets it, to prove the
    /// client's failure log brings back its id.
    planted: Option(Frame),
  )
}

/// Where the login is. Once accepted, the state keeps the connection and the
/// peer for every log line it writes, and the seed's random source.
pub opaque type State {
  NotAccepted(settings: Settings)
  Connected(session: Session)
}

/// What an accepted connection keeps.
type Session {
  Session(
    settings: Settings,
    connection: ConnectionId,
    peer: Peer,
    random: Random,
    /// Bytes of a frame not yet whole, and whole frames not yet taken while
    /// an ask is out.
    pending: BitArray,
    /// The number of the last ask made, so each ask has an id of its own.
    asks: Int,
    status: Status,
  )
}

/// The login's one status.
type Status {
  /// The hello is sent; waiting for 0x592.
  AwaitingLoginRequest
  /// The hand-off is asked to take the game token; `user_id` is the UserId
  /// 0x592 named, checked against the holder's game account id.
  TakingToken(user_id: Guid)
  /// The hand-off is asked to keep the session key for the holder.
  KeepingSessionKey(holder: Holder, session_key: Guid)
  /// 0x591 and 0x3db are sent; the client goes on to the game server.
  HandedOff(holder: Holder)
}

/// The build the client must be, and the hello's build.
const build = 16_042

/// The message table checksum the client checks in the hello
/// (CheckAuthServerVersion 0x140037b70).
const message_table_checksum = 0x097998A0

/// 0x63d's reasons (opcode.0x63d).
const reason_service_timeout = 12

const reason_invalid_login_token = 16

const reason_version_mismatch = 19

/// The rule's first state.
pub fn new(settings: Settings) -> State {
  NotAccepted(settings:)
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: Input(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  case state {
    NotAccepted(settings:) -> before_accept(settings:, event: input.event)
    Connected(session:) ->
      after_accept(session:, now: input.now, event: input.event)
  }
}

/// The hello, and the planted frame after it when the settings hold one.
fn before_accept(
  settings settings: Settings,
  event event: step.Event(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  case event {
    Socket(Accepted(connection:, peer:, seed:)) -> {
      let session =
        Session(
          settings:,
          connection:,
          peer:,
          random: random.new(seed:),
          pending: <<>>,
          asks: 0,
          status: AwaitingLoginRequest,
        )
      let planted = case settings.planted {
        Some(planted) -> [Write(wrapped(AuthWrapper, planted))]
        None -> []
      }
      #(Connected(session), Effects([Write(hello(settings.realm)), ..planted]))
    }
    Socket(step.Read(..))
    | Socket(PeerClosed)
    | Socket(ReadFailed(..))
    | Socket(WriteFailed(..))
    | Started
    | Woken(..)
    | Asked(..)
    | step.WatchEnded(..)
    | TimerFired(..)
    | Answered(..)
    | AnsweredLate(..)
    | Stopping(..) -> #(
      NotAccepted(settings:),
      Effects([
        Log(LogLine(
          level: LogError,
          text: "the auth rule took an input before the connection was accepted",
          about: no_one(),
        )),
        Stop,
      ]),
    )
  }
}

/// The hello, bare: the build and checksum the client checks, the realm's id,
/// and 0 in every field the client never reads (opcode.0x3).
fn hello(realm: Realm) -> BitArray {
  let assert Ok(body) =
    server_hello.encode(ServerHello(
      build:,
      realm_id: realm.id,
      field_3: 0,
      field_4: 0,
      field_5: 0,
      field_6: 0,
      field_7: 0,
      message_table_checksum:,
      field_9: 0,
      field_10: 0,
      field_11: 0,
    ))
    as "the realm's id is within 32 bits"
  let assert Ok(bytes) = frame.encode(server_hello.message_id, body)
    as "the hello is far below the size limit"
  bytes
}

/// A frame in the auth wrapper, under the client's base key.
fn wrapped(wrapper: encrypted_frame.Wrapper, inner: Frame) -> BitArray {
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key is not 0"
  let assert Ok(bytes) = encrypted_frame.wrap(wrapper, inner, base)
    as "the frame is far below the size limit"
  bytes
}

fn after_accept(
  session session: Session,
  now now: Now,
  event event: step.Event(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  case event {
    Socket(step.Read(bytes:)) -> {
      let session =
        Session(..session, pending: <<session.pending:bits, bytes:bits>>)
      case session.status {
        // A frame is taken only once the answer to the ask in flight comes.
        TakingToken(..) | KeepingSessionKey(..) -> #(
          Connected(session),
          Effects([]),
        )
        AwaitingLoginRequest | HandedOff(..) ->
          drive(session:, now:, carried: [])
      }
    }
    Socket(PeerClosed) | Stopping(..) -> #(Connected(session), Effects([Stop]))
    Socket(ReadFailed(failure:)) | Socket(WriteFailed(failure:)) -> #(
      Connected(session),
      Effects([
        log(
          session:,
          level: LogWarning,
          text: "the socket failed (" <> describe_failure(failure) <> ")",
        ),
        Stop,
      ]),
    )
    Answered(outcome:, ..) ->
      settle(handled: answered(session:, now:, outcome:), now:, carried: [])
    AnsweredLate(..) -> #(Connected(session), Effects([]))
    Socket(Accepted(..))
    | Started
    | Woken(..)
    | Asked(..)
    | step.WatchEnded(..)
    | TimerFired(..) -> #(
      Connected(session),
      Effects([
        log(
          session:,
          level: LogError,
          text: "the auth rule took an input a connection is never given",
        ),
        Stop,
      ]),
    )
  }
}

fn describe_failure(failure: step.SocketFailure) -> String {
  case failure {
    step.Closed -> "the socket was closed"
    step.Reset -> "the peer reset the connection"
    step.SendTimedOut -> "a write timed out"
    step.OtherSocketFailure(reason:) -> reason
  }
}

/// What taking one frame, or one answer, decided.
type Handled {
  /// Go on to the next frame in the bytes.
  Continue(session: Session, effects: List(Effect(Nil)))
  /// Carry out the effects, then ask; the frames after this one wait.
  Ask(session: Session, effects: List(Effect(Nil)), ask: step.Ask(Request))
  /// Carry out the effects, which end with `Stop`.
  End(session: Session, effects: List(Effect(Nil)))
}

/// Takes the whole frames in the pending bytes in order until one asks or the
/// bytes hold no more. A bad frame ends the connection after the whole frames
/// before it.
fn drive(
  session session: Session,
  now now: Now,
  carried carried: List(Effect(Nil)),
) -> #(State, Step(Nil, Request)) {
  case frame.split(session.pending) {
    #([], Ok(_)) -> #(Connected(session), Effects(carried))
    #([], Error(error)) ->
      end(session:, carried:, effects: [
        log(
          session:,
          level: LogError,
          text: "the bytes are no frame: " <> describe_frame_error(error),
        ),
        Stop,
      ])
    #([first, ..], _) ->
      settle(
        handled: handle(
          session: Session(..session, pending: after(session.pending, first)),
          now:,
          frame: first,
        ),
        now:,
        carried:,
      )
  }
}

/// The pending bytes without their first whole frame, which has its header
/// and its body.
fn after(pending: BitArray, first: Frame) -> BitArray {
  let size = frame.header_size + bit_array.byte_size(first.body)
  let assert Ok(rest) =
    bit_array.slice(pending, size, bit_array.byte_size(pending) - size)
    as "the first frame is the start of the pending bytes"
  rest
}

fn describe_frame_error(error: frame.FrameError) -> String {
  case error {
    frame.ShorterThanHeader(..) -> "a frame shorter than its header"
    frame.LengthBelowHeader(..) -> "a length below the header"
    frame.LengthOverLimit(..) -> "a frame over the size limit"
    frame.LengthDisagrees(..) -> "a length that disagrees with the frame"
    frame.MessageIdOutOfRange(..) -> "a message id out of range"
  }
}

fn settle(
  handled handled: Handled,
  now now: Now,
  carried carried: List(Effect(Nil)),
) -> #(State, Step(Nil, Request)) {
  case handled {
    Continue(session:, effects:) ->
      drive(session:, now:, carried: list.append(carried, effects))
    Ask(session:, effects:, ask:) -> #(
      Connected(session),
      EffectsThenAsk(list.append(carried, effects), ask),
    )
    End(session:, effects:) -> end(session:, carried:, effects:)
  }
}

fn end(
  session session: Session,
  carried carried: List(Effect(Nil)),
  effects effects: List(Effect(Nil)),
) -> #(State, Step(Nil, Request)) {
  #(Connected(session), Effects(list.append(carried, effects)))
}

/// What one whole frame does: the network layer's messages first, then the
/// login request in its wrapper.
fn handle(
  session session: Session,
  now now: Now,
  frame frame: Frame,
) -> Handled {
  case network_message.handle(frame:) {
    network_message.Answer(bytes:) -> Continue(session, [Write(bytes)])
    network_message.Accepted -> Continue(session, [])
    network_message.Malformed(message_id:, ..) ->
      End(session, [
        log(
          session:,
          level: LogError,
          text: "a network message "
            <> message_text(message_id)
            <> " does not decode",
        ),
        Stop,
      ])
    network_message.NotNetwork ->
      case frame.message_id == encrypted_frame.message_id(ClientWrapper) {
        True -> unwrap(session:, now:, outer: frame)
        False -> unhandled(session, frame.message_id)
      }
  }
}

fn unwrap(
  session session: Session,
  now now: Now,
  outer outer: Frame,
) -> Handled {
  let assert Ok(base) = cipher.new(cipher.base_key) as "the base key is not 0"
  case encrypted_frame.unwrap(outer, base) {
    Error(encrypted_frame.NotAWrapper(..)) ->
      unhandled(session, outer.message_id)
    Error(encrypted_frame.BadFrame(error)) ->
      End(session, [
        log(
          session:,
          level: LogError,
          text: "the wrapped frame is no frame: " <> describe_frame_error(error),
        ),
        Stop,
      ])
    Ok(inner) ->
      case inner.message_id == login_request.message_id {
        True ->
          case login_request.decode(inner.body) {
            Ok(request) -> login_requested(session:, now:, request:)
            Error(error) ->
              End(session, [
                log(
                  session:,
                  level: LogError,
                  text: "the login request 0x0592 does not decode: "
                    <> bit_stream.describe_decode(error:),
                ),
                Stop,
              ])
          }
        False -> unhandled(session, inner.message_id)
      }
  }
}

/// A whole frame of a message the rule does not take: logged, and the
/// connection goes on.
fn unhandled(session: Session, message_id: Int) -> Handled {
  Continue(session, [
    Log(LogLine(
      level: LogWarning,
      text: "unhandled auth message " <> message_text(message_id),
      about: About(..about(session), message: Some(#("unhandled", message_id))),
    )),
  ])
}

fn message_text(message_id: Int) -> String {
  "0x" <> string.pad_start(string.uppercase(int.to_base16(message_id)), 4, "0")
}

/// The client's login request: a build other than 16042 is refused; else the
/// game token it shows is taken from the hand-off.
fn login_requested(
  session session: Session,
  now now: Now,
  request request: login_request.LoginRequest,
) -> Handled {
  case session.status {
    AwaitingLoginRequest ->
      case request.build == build {
        False -> refuse(session:, reason: reason_version_mismatch, before: [])
        True -> {
          let assert Ok(user_id) = guid.from_wire(request.user_id)
            as "the request's UserId is 16 bytes"
          let assert Ok(token) = guid.from_wire(request.game_token)
            as "the request's game token is 16 bytes"
          ask(
            session: Session(..session, status: TakingToken(user_id:)),
            now:,
            request: AskHandOff(Take(GameToken(token:))),
          )
        }
      }
    TakingToken(..) | KeepingSessionKey(..) | HandedOff(..) ->
      unhandled(session, login_request.message_id)
  }
}

/// Makes an ask with the next id of the connection.
fn ask(
  session session: Session,
  now now: Now,
  request request: Request,
) -> Handled {
  let asks = session.asks + 1
  Ask(
    session: Session(..session, asks:),
    effects: [],
    ask: step.Ask(
      ask: AskId(asks),
      request:,
      deadline_ms: now.monotonic_ms + session.settings.ask_deadline_ms,
    ),
  )
}

/// The refusal 0x63d with the reason, in the auth wrapper, and the end of the
/// connection; `before` are the effects ahead of it, such as a log line.
fn refuse(
  session session: Session,
  reason reason: Int,
  before before: List(Effect(Nil)),
) -> Handled {
  let assert Ok(body) =
    login_refused.encode(LoginRefused(reason:, value: 0, field_3: 0))
    as "a reason is within 32 bits"
  End(
    session,
    list.append(before, [
      Write(wrapped(AuthWrapper, Frame(login_refused.message_id, body))),
      Stop,
    ]),
  )
}

/// A hand-off that gave no answer: 0x63d reason 12, "NCSoft login service
/// finish timeout", and a warning, since the failure is the server's.
fn timed_out(session session: Session, what what: String) -> Handled {
  refuse(session:, reason: reason_service_timeout, before: [
    log(
      session:,
      level: LogWarning,
      text: "the login is refused with reason 12: " <> what,
    ),
  ])
}

fn end_for(session: Session, reason: String) -> Handled {
  End(session, [log(session:, level: LogError, text: reason), Stop])
}

/// The answer to the ask in flight.
fn answered(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> Handled {
  case session.status {
    TakingToken(user_id:) -> taken(session:, now:, user_id:, outcome:)
    KeepingSessionKey(holder:, session_key:) ->
      kept(session:, holder:, session_key:, outcome:)
    AwaitingLoginRequest | HandedOff(..) ->
      end_for(session, "an answer came when no ask was out")
  }
}

/// The hand-off's answer to taking the game token: the holder's game account
/// must be the UserId the client showed.
fn taken(
  session session: Session,
  now now: Now,
  user_id user_id: Guid,
  outcome outcome: Outcome(Answer),
) -> Handled {
  case outcome {
    step.Answer(FromHandOff(hand_off.Taken(holder:))) ->
      case holder.game_account_id == user_id {
        True -> {
          let #(random, key_bytes) = random.bytes(session.random, 16)
          let assert Ok(session_key) = guid.from_wire(key_bytes)
            as "sixteen bytes are a GUID"
          ask(
            session: Session(
              ..session,
              random:,
              status: KeepingSessionKey(holder:, session_key:),
            ),
            now:,
            request: AskHandOff(Put(
              key: SessionKey(key: session_key),
              holder:,
              lifetime_ms: session.settings.session_key_lifetime_ms,
            )),
          )
        }
        False ->
          refuse(session:, reason: reason_invalid_login_token, before: [])
      }
    step.Answer(FromHandOff(hand_off.NoHolder)) ->
      refuse(session:, reason: reason_invalid_login_token, before: [])
    step.Answer(FromHandOff(hand_off.Kept))
    | step.Answer(FromHandOff(hand_off.AlreadyHeld))
    | step.Answer(FromStore(..)) ->
      end_for(session, "the hand-off's answer is none a Take gets")
    step.NotRunning -> timed_out(session:, what: "the hand-off was not running")
    step.NoAnswerInTime ->
      timed_out(session:, what: "the hand-off gave no answer in time")
    step.EndedBeforeAnswer ->
      timed_out(session:, what: "the hand-off ended before it answered")
    step.StoppedWaiting ->
      timed_out(session:, what: "the server began stopping")
  }
}

/// The hand-off's answer to keeping the session key: 0x591, then 0x3db.
fn kept(
  session session: Session,
  holder holder: Holder,
  session_key session_key: Guid,
  outcome outcome: Outcome(Answer),
) -> Handled {
  case outcome {
    step.Answer(FromHandOff(hand_off.Kept)) ->
      handed_off(session:, holder:, session_key:)
    step.Answer(FromHandOff(hand_off.AlreadyHeld)) ->
      timed_out(session:, what: "the hand-off already held the session key")
    step.Answer(FromHandOff(hand_off.Taken(..)))
    | step.Answer(FromHandOff(hand_off.NoHolder))
    | step.Answer(FromStore(..)) ->
      end_for(session, "the hand-off's answer is none a Put gets")
    step.NotRunning -> timed_out(session:, what: "the hand-off was not running")
    step.NoAnswerInTime ->
      timed_out(session:, what: "the hand-off gave no answer in time")
    step.EndedBeforeAnswer ->
      timed_out(session:, what: "the hand-off ended before it answered")
    step.StoppedWaiting ->
      timed_out(session:, what: "the server began stopping")
  }
}

/// 0x591 and 0x3db, each in the auth wrapper. A message that cannot be
/// written is the server's failure: an error log and 0x63d reason 12.
fn handed_off(
  session session: Session,
  holder holder: Holder,
  session_key session_key: Guid,
) -> Handled {
  let realm = session.settings.realm
  let store.AccountId(account_id) = holder.account_id
  case login_accepted.encode(LoginAccepted(disconnected_for_lag: 0)) {
    Error(error) ->
      unwritable(session:, reason: bit_stream.describe_encode(error:))
    Ok(accepted) ->
      case
        game_server_handoff.encode(GameServerHandoff(
          game_server: realm.game_server,
          session_key: guid.to_wire(session_key),
          account_id:,
          realm_name: realm.name,
          realm_flags: 0,
          realm_pvp_type: 0,
          realm_note_text_id: 0,
        ))
      {
        Error(error) ->
          unwritable(session:, reason: bit_stream.describe_encode(error:))
        Ok(handoff) -> {
          let handed = Session(..session, status: HandedOff(holder:))
          Continue(handed, [
            Write(wrapped(
              AuthWrapper,
              Frame(login_accepted.message_id, accepted),
            )),
            Write(wrapped(
              AuthWrapper,
              Frame(game_server_handoff.message_id, handoff),
            )),
            Log(LogLine(
              level: LogInfo,
              text: "the login is accepted and the client is handed to the game server",
              about: about(handed),
            )),
          ])
        }
      }
  }
}

/// A message that cannot be written for this account and realm is the
/// server's failure: an error log and 0x63d reason 12.
fn unwritable(session session: Session, reason reason: String) -> Handled {
  refuse(session:, reason: reason_service_timeout, before: [
    log(
      session:,
      level: LogError,
      text: "0x0591 or 0x03DB cannot be written for the account and the realm: "
        <> reason,
    ),
  ])
}

// ---- log lines ----

fn log(
  session session: Session,
  level level: step.LogLevel,
  text text: String,
) -> Effect(Nil) {
  Log(LogLine(level:, text:, about: about(session)))
}

fn about(session: Session) -> About {
  About(
    connection: Some(session.connection),
    peer: Some(session.peer),
    account_id: case holder_of(session.status) {
      Some(hand_off.Holder(account_id: store.AccountId(id), ..)) -> Some(id)
      None -> None
    },
    character_id: None,
    map: None,
    message: None,
  )
}

fn no_one() -> About {
  About(
    connection: None,
    peer: None,
    account_id: None,
    character_id: None,
    map: None,
    message: None,
  )
}

/// Whose login this is, once the hand-off has named the holder.
fn holder_of(status: Status) -> Option(Holder) {
  case status {
    KeepingSessionKey(holder:, ..) | HandedOff(holder:) -> Some(holder)
    AwaitingLoginRequest | TakingToken(..) -> None
  }
}
