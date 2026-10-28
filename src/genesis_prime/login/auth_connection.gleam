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

import genesis_prime/client_archive
import genesis_prime/client_connection.{
  type Answer, type Link, type Request, AskHandOff, Asking, Bytes, Connect,
  Continue, Done, FromHandOff, FromMap, FromSessions, FromStore, Otherwise,
}
import genesis_prime/connection/cipher
import genesis_prime/connection/encrypted_frame.{AuthWrapper}
import genesis_prime/connection/frame.{type Frame, type FrameError, Frame}
import genesis_prime/connection/hello
import genesis_prime/hand_off.{type Holder, GameToken, Put, SessionKey, Take}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/message/bit_stream.{type Endpoint}
import genesis_prime/message/game_server_handoff.{GameServerHandoff}
import genesis_prime/message/login_accepted.{LoginAccepted}
import genesis_prime/message/login_refused.{LoginRefused}
import genesis_prime/message/login_request
import genesis_prime/step.{
  type Effect, type Input, type Now, type Outcome, type Rule, type Step, Effects,
  LogError, LogInfo, LogWarning, Rule, Stop, Write,
}
import genesis_prime/store
import gleam/list
import gleam/option.{type Option, None, Some}

/// The rule's name in a recording's header and in the server's tree.
pub const rule_name = "genesis_prime/login/auth_connection"

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
    link: Link,
    /// Bytes of a frame not yet whole, and whole frames not yet taken while
    /// an ask is out.
    pending: BitArray,
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

/// The build the client must be.
const build = client_archive.target_build

/// 0x63d's reasons (opcode.0x63d).
const reason_service_timeout = 12

const reason_invalid_login_token = 16

const reason_version_mismatch = 19

/// The rule as its connection shell runs it.
pub fn rule(
  settings: Settings,
) -> Rule(Settings, State, Nil, Answer, Nil, Request) {
  Rule(name: rule_name, settings:, new:, step:)
}

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
    NotAccepted(settings:) ->
      case
        client_connection.hear(input.event, about: step.no_one, stopping: fn() {
          []
        })
      {
        Connect(connection:, peer:, seed:) -> {
          let planted = case settings.planted {
            Some(planted) -> [Write(wrapped(planted))]
            None -> []
          }
          #(
            Connected(Session(
              settings:,
              link: client_connection.link(connection:, peer:, seed:),
              pending: <<>>,
              status: AwaitingLoginRequest,
            )),
            Effects([Write(bare_hello(settings.realm)), ..planted]),
          )
        }
        Bytes(..) | client_connection.Outcome(..) -> #(
          state,
          client_connection.before_accepted(rule: "auth"),
        )
        Otherwise(step:) -> #(state, step)
      }
    Connected(session:) ->
      connected(session:, now: input.now, event: input.event)
  }
}

fn connected(
  session session: Session,
  now now: Now,
  event event: step.Event(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  case
    client_connection.hear(event, about: about_of(session), stopping: fn() {
      []
    })
  {
    Bytes(bytes:) -> {
      let session =
        Session(..session, pending: <<session.pending:bits, bytes:bits>>)
      case session.status {
        // A frame is taken only once the answer to the ask in flight comes.
        TakingToken(..) | KeepingSessionKey(..) -> #(
          Connected(session),
          Effects([]),
        )
        AwaitingLoginRequest | HandedOff(..) ->
          client_connection.drive(session:, flow: flow(now), carried: [])
      }
    }
    client_connection.Outcome(outcome:) ->
      client_connection.settle(
        handled: answered(session:, now:, outcome:),
        flow: flow(now),
        carried: [],
      )
    Connect(..) -> #(
      Connected(session),
      client_connection.accepted_again(about: about_of(session), rule: "auth"),
    )
    Otherwise(step:) -> #(Connected(session), step)
  }
}

/// The hello, bare (genesis_prime/connection/hello).
fn bare_hello(realm: Realm) -> BitArray {
  let hello = hello.frame(realm_id: realm.id)
  let assert Ok(bytes) = frame.encode(hello.message_id, hello.body)
    as "the hello is far below the size limit"
  bytes
}

/// A frame in the auth wrapper, under the client's base key.
fn wrapped(inner: Frame) -> BitArray {
  client_connection.wrapped(AuthWrapper, inner, cipher.base())
}

/// How the rule takes the client's frames, at the time of an input.
fn flow(now: Now) -> client_connection.Flow(Session, Frame, FrameError, State) {
  client_connection.Flow(
    pending: fn(session: Session) { session.pending },
    take: frame.take,
    taking: fn(session, whole, rest) {
      handle(session: Session(..session, pending: rest), now:, frame: whole)
    },
    refused: fn(session, error) {
      end_for(session, "the bytes are no frame: " <> frame.describe(error))
    },
    connected: Connected,
  )
}

/// What one whole frame does: the network layer's messages first, then the
/// login request in its wrapper.
fn handle(
  session session: Session,
  now now: Now,
  frame whole: Frame,
) -> client_connection.Handled(Session) {
  case
    client_connection.open(
      session:,
      about: about_of(session),
      server: "auth",
      frame: whole,
      cipher: cipher.base(),
    )
  {
    client_connection.Settled(handled:) -> handled
    client_connection.Inside(inner:) ->
      case inner.message_id == login_request.message_id {
        True ->
          case login_request.decode(inner.body) {
            Ok(request) -> login_requested(session:, now:, request:)
            Error(error) ->
              end_for(
                session,
                "the login request 0x0592 does not decode: "
                  <> bit_stream.describe_decode(error:),
              )
          }
        False -> unhandled(session, inner.message_id)
      }
  }
}

/// A whole frame of a message the rule does not take: logged, and the
/// connection goes on.
fn unhandled(
  session: Session,
  message_id: Int,
) -> client_connection.Handled(Session) {
  client_connection.unhandled(
    session:,
    about: about_of(session),
    server: "auth",
    message_id:,
    level: LogWarning,
  )
}

/// The client's login request: a build other than 16042 is refused; else the
/// game token it shows is taken from the hand-off.
fn login_requested(
  session session: Session,
  now now: Now,
  request request: login_request.LoginRequest,
) -> client_connection.Handled(Session) {
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

/// Makes the connection's next ask.
fn ask(
  session session: Session,
  now now: Now,
  request request: Request,
) -> client_connection.Handled(Session) {
  let #(link, made) =
    client_connection.ask(
      session.link,
      now:,
      deadline_ms: session.settings.ask_deadline_ms,
      request:,
    )
  Asking(Session(..session, link:), [], made)
}

/// The refusal 0x63d with the reason, in the auth wrapper, and the end of the
/// connection; `before` are the effects ahead of it, such as a log line.
fn refuse(
  session session: Session,
  reason reason: Int,
  before before: List(Effect(Nil)),
) -> client_connection.Handled(Session) {
  let assert Ok(body) =
    login_refused.encode(LoginRefused(reason:, value: 0, field_3: 0))
    as "a reason is within 32 bits"
  Done(
    session,
    list.append(before, [
      Write(wrapped(Frame(login_refused.message_id, body))),
      Stop,
    ]),
  )
}

/// A hand-off that gave no answer: 0x63d reason 12, "NCSoft login service
/// finish timeout", and a warning, since the failure is the server's.
fn timed_out(
  session session: Session,
  what what: String,
) -> client_connection.Handled(Session) {
  refuse(session:, reason: reason_service_timeout, before: [
    log(
      session:,
      level: LogWarning,
      text: "the login is refused with reason 12: " <> what,
    ),
  ])
}

/// The client broke the protocol: an error log line and the end of the
/// connection.
fn end_for(
  session: Session,
  text: String,
) -> client_connection.Handled(Session) {
  client_connection.end_for(session:, about: about_of(session), text:)
}

/// The answer to the ask in flight.
fn answered(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
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
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromHandOff(hand_off.Taken(holder:))) ->
      case holder.game_account_id == user_id {
        True -> {
          let #(link, key_bytes) = client_connection.draw(session.link, 16)
          let assert Ok(session_key) = guid.from_wire(key_bytes)
            as "sixteen bytes are a GUID"
          ask(
            session: Session(
              ..session,
              link:,
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
    | step.Answer(FromStore(..))
    | step.Answer(FromSessions(..))
    | step.Answer(FromMap(..)) ->
      end_for(session, "the hand-off's answer is none a Take gets")
    step.NotRunning
    | step.NoAnswerInTime
    | step.EndedBeforeAnswer
    | step.StoppedWaiting ->
      timed_out(
        session:,
        what: client_connection.without_answer(who: "the hand-off", outcome:),
      )
  }
}

/// The hand-off's answer to keeping the session key: 0x591, then 0x3db.
fn kept(
  session session: Session,
  holder holder: Holder,
  session_key session_key: Guid,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromHandOff(hand_off.Kept)) ->
      handed_off(session:, holder:, session_key:)
    step.Answer(FromHandOff(hand_off.AlreadyHeld)) ->
      timed_out(session:, what: "the hand-off already held the session key")
    step.Answer(FromHandOff(hand_off.Taken(..)))
    | step.Answer(FromHandOff(hand_off.NoHolder))
    | step.Answer(FromStore(..))
    | step.Answer(FromSessions(..))
    | step.Answer(FromMap(..)) ->
      end_for(session, "the hand-off's answer is none a Put gets")
    step.NotRunning
    | step.NoAnswerInTime
    | step.EndedBeforeAnswer
    | step.StoppedWaiting ->
      timed_out(
        session:,
        what: client_connection.without_answer(who: "the hand-off", outcome:),
      )
  }
}

/// 0x591 and 0x3db, each in the auth wrapper. A 0x3db that cannot be written
/// for this account and realm is the server's failure: an error log and 0x63d
/// reason 12.
fn handed_off(
  session session: Session,
  holder holder: Holder,
  session_key session_key: Guid,
) -> client_connection.Handled(Session) {
  let realm = session.settings.realm
  let store.AccountId(account_id) = holder.account_id
  let assert Ok(accepted) =
    login_accepted.encode(LoginAccepted(disconnected_for_lag: 0))
    as "a value of 0 fits 32 bits"
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
      refuse(session:, reason: reason_service_timeout, before: [
        log(
          session:,
          level: LogError,
          text: "0x03DB cannot be written for the account and the realm: "
            <> bit_stream.describe_encode(error:),
        ),
      ])
    Ok(handoff) -> {
      let handed = Session(..session, status: HandedOff(holder:))
      Continue(handed, [
        Write(wrapped(Frame(login_accepted.message_id, accepted))),
        Write(wrapped(Frame(game_server_handoff.message_id, handoff))),
        log(
          session: handed,
          level: LogInfo,
          text: "the login is accepted and the client is handed to the game server",
        ),
      ])
    }
  }
}

// ---- log lines ----

fn log(
  session session: Session,
  level level: step.LogLevel,
  text text: String,
) -> Effect(Nil) {
  client_connection.log(about: about_of(session), level:, text:)
}

/// What a log line of the login is about: the connection, the peer and the
/// account once the hand-off has named it.
fn about_of(session: Session) -> step.About {
  client_connection.about(
    session.link,
    account_id: account_id_of(session.status),
  )
}

/// The id of the account the login is for, once the hand-off has named the
/// holder.
fn account_id_of(status: Status) -> Option(Int) {
  case status {
    KeepingSessionKey(
      holder: hand_off.Holder(account_id: store.AccountId(id), ..),
      ..,
    )
    | HandedOff(holder: hand_off.Holder(account_id: store.AccountId(id), ..)) ->
      Some(id)
    AwaitingLoginRequest | TakingToken(..) -> None
  }
}
