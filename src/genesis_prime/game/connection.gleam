//// The rule of one game connection: the client's connection to the game
//// server, from the hello to the character list its select screen shows. It
//// decides everything; its connection shell carries it out
//// (genesis_prime/connection/shell). The client reaches it with the session
//// key the auth server's hand-off gave it (genesis_prime/login/auth_connection).
////
//// ```
//// client                          rule                              asks
//// connects                     ◀─ 0x3DC{0x0003 hello, realm id}, base key
//// 0x244{0x058F} (base key)     ─▶ session key from the 16 bytes
////                                 and the base key; the connection is
////                                 re-keyed: every frame after this one,
////                                 each way, is under the session key
////                                                                ─▶ hand-off: Take(SessionKey)
//// 0x244{0x07E0}                   waits in the bytes read until the
////   (same read, session key)      hand-off answers
////   Taken(holder)                 the bytes are taken again       ─▶ store: ListCharacters(account)
////     Characters(rows)         ◀─ 0x3DC{0x0117 character_list}, session key
//// 0x244{0x038C{0x082D}}        ─▶ logged as unhandled
//// 0x244{0x0241}                ─▶ logged as unhandled
//// ping 0x0, bare               ◀─ pong 0x1, bare
//// ```
////
//// - **The hello** is the first thing written: any game server message before
////   it ends the client's login with 0x801B2 (0x1400370d0). It is the
////   connection's first input, `Socket(Accepted)`, that writes it, in the game
////   wrapper under the base key, with the realm's id from the settings
////   (genesis_prime/connection/hello, opcode.0x3).
//// - **The re-key.** The client re-keys at once on sending 0x058F, so the
////   rule does too, before it asks; bytes that arrive after it in the same
////   read are read under the session key
////   (vector.0x14003827c.session_fold). The first client message must be
////   0x058F, and only one is taken: another first message, or a second 0x058F,
////   is logged as an error and ends the connection.
//// - **Reads during an ask.** Frames after the one that asked stay in the
////   bytes read and are taken once the answer comes, so 0x07E0 is taken after
////   the hand-off's answer, and 0x038C and 0x0241 after the store's.
//// - **The character list** is character select's own feature
////   (genesis_prime/game/character_select): it makes its own store ask and
////   takes the store's answer, and the rule turns its effects into writes in
////   the game wrapper and into the ask. The failures every ask shares (no
////   answer, or the store unavailable) are the rule's, so a feature added to
////   character select adds no status here.
//// - **The server never ends a connection after the hello without telling
////   the client**, which waits for the list with no timeout and would stay on
////   its prompt otherwise (lua.Character.OnCharacterList): 0x036A in the game
////   wrapper under the cipher the connection holds at that moment, then the
////   close. Every reason drops the client to its error screen and only picks
////   the text (0x1400168a0):
////   - reason 19, "This account has been disconnected", when the hand-off
////     does not hold the session key (never put, taken, or expired), with a
////     warning naming the peer;
////   - reason 8, "Lost connection with user server.", for the server's own
////     failure, with a warning: the hand-off or the store is not running, ended
////     before it answered, gave no answer by the settings' ask deadline, or the
////     store answers `Unavailable`; and with no log for the server stopping,
////     whether it is waiting on an ask (`StoppedWaiting`) or not
////     (`Stopping`).
////   A client that breaks the protocol, closes, or whose socket fails is not
////   told: the rule logs the break and ends the connection.
//// - **A process dying or a deadline passing.** The rule holds no process:
////   a restart of the hand-off or the store is seen only as an ask's outcome
////   (`NotRunning`, `EndedBeforeAnswer`), and a late answer
////   (`AnsweredLate`) is dropped. A crash of the connection's own process
////   drops the client, which connects again from the login.
//// - **Network messages** are answered before any wrapper is read: a ping 0
////   gets a pong 1 (opcode.0x0), a pong or close notice nothing
////   (genesis_prime/client_connection, genesis_prime/connection/network_message).
//// - **Out of order.** A frame the client's reader would refuse ends the
////   connection; a whole frame of a message the rule does not take, 0x038C
////   with 0x082D inside it, 0x0241 and any other, is logged as unhandled and
////   the connection goes on (opcode.0x241).

import genesis_prime/client_connection.{
  type Answer, type Link, type Request, AskHandOff, AskStore, Asking, Bytes,
  Connect, Continue, End, FromHandOff, FromStore, Inside, Otherwise, Settled,
}
import genesis_prime/connection/cipher.{type Cipher}
import genesis_prime/connection/encrypted_frame.{GameWrapper}
import genesis_prime/connection/frame.{type Frame, type FrameError, Frame}
import genesis_prime/connection/hello
import genesis_prime/game/character_select
import genesis_prime/hand_off.{type Holder, SessionKey, Take}
import genesis_prime/login/guid
import genesis_prime/message/bit_stream
import genesis_prime/message/character_select_start
import genesis_prime/message/disconnect_notice.{DisconnectNotice}
import genesis_prime/message/game_hello_reply
import genesis_prime/step.{
  type Effect, type Input, type Now, type Outcome, type Rule, type Step, Effects,
  LogWarning, Stop, Write,
}
import genesis_prime/store
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The rule's name in a recording's header and in the server's tree.
pub const rule_name = "genesis_prime/game/connection"

/// What every game connection is made with, at start.
pub type Settings {
  Settings(
    /// The realm's id: the hello's, and the character list's, which becomes
    /// the client's current realm when it plays a character (opcode.0x117).
    realm_id: Int,
    /// The number of characters the client's list is told the account may
    /// have; the Lua keeps it and nothing reads it (lua.Character.OnCharacterList).
    max_characters: Int,
    /// How long an ask to the hand-off or the store may take.
    ask_deadline_ms: Int,
  )
}

/// Where the connection is. Once accepted, the state keeps the connection and
/// the peer for every log line it writes.
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
    /// The cipher the connection's frames are read and written under: the
    /// base key's until 0x058F re-keys it.
    cipher: Cipher,
    status: Status,
  )
}

/// The connection's one status.
type Status {
  /// The hello is sent; waiting for 0x058F.
  AwaitingHelloReply
  /// The hand-off is asked to take the session key.
  TakingSessionKey
  /// The session key was held for `holder`; the client is in character
  /// select, which holds its own state, asks the store itself and says when
  /// its answer is awaited.
  InCharacterSelect(holder: Holder, select: character_select.State)
}

/// 0x036A's reasons (opcode.0x36a, 0x1400168a0).
const reason_server_failure = 8

const reason_account_disconnected = 19

/// The rule as its connection shell runs it.
pub fn rule(
  settings: Settings,
) -> Rule(Settings, State, Nil, Answer, Nil, Request) {
  step.Rule(name: rule_name, settings:, new:, step:)
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
        Connect(connection:, peer:, seed:) -> #(
          Connected(Session(
            settings:,
            link: client_connection.link(connection:, peer:, seed:),
            pending: <<>>,
            cipher: cipher.base(),
            status: AwaitingHelloReply,
          )),
          Effects([Write(hello_bytes(settings))]),
        )
        Bytes(..) | client_connection.Outcome(..) -> #(
          state,
          client_connection.before_accepted(rule: "game"),
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
    client_connection.hear(
      event,
      about: client_connection.about(
        session.link,
        account_id: account_id_of(session.status),
      ),
      stopping: fn() { server_stopping(session) },
    )
  {
    Bytes(bytes:) -> {
      let session =
        Session(..session, pending: <<session.pending:bits, bytes:bits>>)
      case asking(session.status) {
        // A frame is taken only once the answer to the ask in flight comes.
        True -> #(Connected(session), Effects([]))
        False -> client_connection.drive(session:, flow: flow(now), carried: [])
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
      client_connection.accepted_again(
        link: session.link,
        account_id: account_id_of(session.status),
        rule: "game",
      ),
    )
    Otherwise(step:) -> #(Connected(session), step)
  }
}

/// Whether an ask is in flight, so the frames after the one that asked wait.
fn asking(status: Status) -> Bool {
  case status {
    TakingSessionKey -> True
    InCharacterSelect(select:, ..) -> character_select.waiting(select)
    AwaitingHelloReply -> False
  }
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

/// The hello, in the game wrapper under the base key (genesis_prime/connection/hello).
fn hello_bytes(settings: Settings) -> BitArray {
  client_connection.wrapped(
    GameWrapper,
    hello.frame(realm_id: settings.realm_id),
    cipher.base(),
  )
}

/// A message in the game wrapper under the cipher the connection holds.
fn to_client(session: Session, inner: Frame) -> Effect(Nil) {
  Write(client_connection.wrapped(GameWrapper, inner, session.cipher))
}

/// 0x036A with the reason, in the game wrapper under the cipher the
/// connection holds, so the client leaves its prompt.
fn notice(session session: Session, reason reason: Int) -> Effect(Nil) {
  let assert Ok(body) = disconnect_notice.encode(DisconnectNotice(reason:))
    as "a reason is within 5 bits"
  to_client(session, Frame(disconnect_notice.message_id, body))
}

/// What a connection writes before it ends when the server stops: the notice
/// that the server failed, so the client leaves its prompt. A stop is no
/// failure, so no log line comes with it.
fn server_stopping(session: Session) -> List(Effect(Nil)) {
  [notice(session:, reason: reason_server_failure)]
}

/// What one whole frame does: the network layer's messages first, then the
/// message in the client's wrapper.
fn handle(
  session session: Session,
  now now: Now,
  frame whole: Frame,
) -> client_connection.Handled(Session) {
  case
    client_connection.open(
      session:,
      link: session.link,
      account_id: account_id_of(session.status),
      server: "game",
      frame: whole,
      cipher: session.cipher,
    )
  {
    Settled(handled:) -> handled
    Inside(inner:) -> taken_message(session:, now:, inner:)
  }
}

/// What the message in the client's wrapper does, by where the connection is:
/// the first must be 0x058F and only one is taken, 0x07E0 starts character
/// select, and any other whole message is logged as unhandled.
fn taken_message(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  let is_hello_reply = inner.message_id == game_hello_reply.message_id
  case session.status {
    AwaitingHelloReply ->
      case is_hello_reply {
        True -> hello_replied(session:, now:, inner:)
        False ->
          end_for(
            session,
            "the first message of a game connection is 0x058F, not "
              <> client_connection.message_text(inner.message_id),
          )
      }
    InCharacterSelect(holder:, ..) ->
      case
        is_hello_reply,
        inner.message_id == character_select_start.message_id
      {
        True, _ -> end_for(session, "0x058F was sent a second time")
        False, True -> select_started(session:, now:, holder:, inner:)
        False, False ->
          client_connection.unhandled(
            session:,
            link: session.link,
            account_id: account_id_of(session.status),
            server: "game",
            message_id: inner.message_id,
          )
      }
    TakingSessionKey ->
      end_for(session, "a frame was taken while an ask was out")
  }
}

/// The client's 0x058F: the connection is keyed from the session key at once,
/// as the client keys its own (vector.0x14003827c.session_fold), and the
/// hand-off is asked to take the key.
fn hello_replied(
  session session: Session,
  now now: Now,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case game_hello_reply.decode(inner.body) {
    Error(error) ->
      end_for(
        session,
        "the game hello reply 0x058F does not decode: "
          <> bit_stream.describe_decode(error:),
      )
    Ok(reply) -> {
      let assert Ok(key) = guid.from_wire(reply.session_key)
        as "the reply's session key is 16 bytes"
      case
        cipher.session_key(bytes: reply.session_key, base_key: cipher.base_key)
        |> result.try(cipher.new)
      {
        Error(error) ->
          end_for(
            session,
            "the session key makes no cipher: " <> describe_key_error(error),
          )
        Ok(keyed) ->
          ask(
            session: Session(..session, cipher: keyed, status: TakingSessionKey),
            now:,
            request: AskHandOff(Take(SessionKey(key:))),
            before: [],
          )
      }
    }
  }
}

fn describe_key_error(error: cipher.KeyError) -> String {
  case error {
    cipher.ZeroKey -> "the key is 0, which the client refuses"
    cipher.SessionKeyNotSixteenBytes(bytes:) ->
      "the session key is " <> int.to_string(bytes) <> " bytes, not 16"
  }
}

/// The client's 0x07E0: character select starts for the holder's account.
fn select_started(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  inner inner: Frame,
) -> client_connection.Handled(Session) {
  case character_select_start.decode(inner.body) {
    Error(error) ->
      end_for(
        session,
        "0x07E0 does not decode: " <> bit_stream.describe_decode(error:),
      )
    Ok(_) -> {
      let #(select, effects) = character_select.started(holder.account_id)
      carry_out(
        session: Session(..session, status: InCharacterSelect(holder:, select:)),
        now:,
        effects:,
        written: [],
      )
    }
  }
}

/// Turns what character select decided into writes, and into its ask, which
/// ends the step with what was written before it; `written` are the writes so
/// far, the last first.
fn carry_out(
  session session: Session,
  now now: Now,
  effects effects: List(character_select.Effect),
  written written: List(Effect(Nil)),
) -> client_connection.Handled(Session) {
  case effects {
    [] -> Continue(session, list.reverse(written))
    [character_select.Send(frame:), ..rest] ->
      carry_out(session:, now:, effects: rest, written: [
        to_client(session, frame),
        ..written
      ])
    [character_select.Ask(request:), ..] ->
      ask(
        session:,
        now:,
        request: AskStore(request),
        before: list.reverse(written),
      )
  }
}

/// Makes the connection's next ask, after the effects `before`.
fn ask(
  session session: Session,
  now now: Now,
  request request: Request,
  before before: List(Effect(Nil)),
) -> client_connection.Handled(Session) {
  let #(link, made) =
    client_connection.ask(
      session.link,
      now:,
      deadline_ms: session.settings.ask_deadline_ms,
      request:,
    )
  Asking(Session(..session, link:), before, made)
}

/// The answer to the ask in flight.
fn answered(
  session session: Session,
  now now: Now,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case session.status {
    TakingSessionKey -> key_taken(session:, outcome:)
    InCharacterSelect(holder:, select:) ->
      select_answered(session:, now:, holder:, select:, outcome:)
    AwaitingHelloReply -> end_for(session, "an answer came when no ask was out")
  }
}

/// The hand-off's answer to taking the session key: the holder, or a client
/// that is told it is disconnected.
fn key_taken(
  session session: Session,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromHandOff(hand_off.Taken(holder:))) ->
      Continue(
        Session(
          ..session,
          status: InCharacterSelect(holder:, select: character_select.new()),
        ),
        [],
      )
    step.Answer(FromHandOff(hand_off.NoHolder)) ->
      told(
        session:,
        reason: reason_account_disconnected,
        level: LogWarning,
        text: "the hand-off does not hold the session key",
      )
    step.Answer(FromHandOff(hand_off.Kept))
    | step.Answer(FromHandOff(hand_off.AlreadyHeld))
    | step.Answer(FromStore(..)) ->
      told(
        session:,
        reason: reason_server_failure,
        level: step.LogError,
        text: "the hand-off's answer is none a Take gets",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        reason: reason_server_failure,
        level: LogWarning,
        text: client_connection.without_answer(who: "the hand-off", outcome:),
      )
    step.StoppedWaiting -> stopped(session)
  }
}

/// The store's answer to character select's ask: the failures every store ask
/// shares tell the client the server failed; any other answer is character
/// select's to take.
fn select_answered(
  session session: Session,
  now now: Now,
  holder holder: Holder,
  select select: character_select.State,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(store.Unavailable)) ->
      told(
        session:,
        reason: reason_server_failure,
        level: LogWarning,
        text: "the store is unavailable",
      )
    step.Answer(FromStore(answer)) ->
      case
        character_select.answered(
          select,
          answer,
          filetime: now.filetime,
          realm_id: session.settings.realm_id,
          max_characters: session.settings.max_characters,
        )
      {
        Ok(#(select, effects)) ->
          carry_out(
            session: Session(
              ..session,
              status: InCharacterSelect(holder:, select:),
            ),
            now:,
            effects:,
            written: [],
          )
        Error(Nil) ->
          told(
            session:,
            reason: reason_server_failure,
            level: step.LogError,
            text: "the store's answer is none character select asked for",
          )
      }
    step.Answer(FromHandOff(..)) ->
      told(
        session:,
        reason: reason_server_failure,
        level: step.LogError,
        text: "the hand-off's answer is none a store ask gets",
      )
    step.NotRunning | step.NoAnswerInTime | step.EndedBeforeAnswer ->
      told(
        session:,
        reason: reason_server_failure,
        level: LogWarning,
        text: client_connection.without_answer(who: "the store", outcome:),
      )
    step.StoppedWaiting -> stopped(session)
  }
}

/// The connection ends after 0x036A with the reason, and a log line saying
/// why.
fn told(
  session session: Session,
  reason reason: Int,
  level level: step.LogLevel,
  text text: String,
) -> client_connection.Handled(Session) {
  End(session, [
    log(session:, level:, text:),
    notice(session:, reason:),
    Stop,
  ])
}

/// The server is stopping while an ask is out: the client is told, with no
/// log line, since a stop is no failure.
fn stopped(session: Session) -> client_connection.Handled(Session) {
  End(session, list.append(server_stopping(session), [Stop]))
}

/// The client broke the protocol: an error log line and the end of the
/// connection, with nothing written to a client that is no client.
fn end_for(
  session: Session,
  text: String,
) -> client_connection.Handled(Session) {
  client_connection.end_for(
    session:,
    link: session.link,
    account_id: account_id_of(session.status),
    text:,
  )
}

// ---- log lines ----

fn log(
  session session: Session,
  level level: step.LogLevel,
  text text: String,
) -> Effect(Nil) {
  client_connection.log(
    link: session.link,
    account_id: account_id_of(session.status),
    level:,
    text:,
  )
}

/// The id of the account the connection is for, once the hand-off has named
/// the holder.
fn account_id_of(status: Status) -> Option(Int) {
  case status {
    InCharacterSelect(
      holder: hand_off.Holder(account_id: store.AccountId(id), ..),
      ..,
    ) -> Some(id)
    AwaitingHelloReply | TakingSessionKey -> None
  }
}
