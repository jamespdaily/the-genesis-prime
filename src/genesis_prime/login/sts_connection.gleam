//// The rule of one STS connection: the NC platform login, from the client's
//// Connect to the game token it shows the auth server. It decides everything;
//// its connection shell carries it out (genesis_prime/connection/shell).
////
//// ```
//// client                              rule                         asks
//// Connect (one-way)                ─▶ nothing
//// LoginStart(name, address)        ─▶                            ─▶ store: FindAccount(name)
////   AccountFound                   ◀─ KeyData(salt, B)               (b from the seed)
////   NoSuchAccount                  ◀─ Error 3002
//// KeyData(A, M1)                   ─▶ srp.prove
////   proven                         ◀─ KeyData(M2), plain; then RC4 under K both ways
////   M1 wrong                       ◀─ Error 3002, plain
//// LoginFinish        (ciphered)    ─▶ token from the seed        ─▶ hand-off: Put(GameToken)
////   Kept                           ◀─ AuthType 0, UserId, UserName (ciphered)
//// ListMyAccounts     (ciphered)    ─▶ one GameAccount with an Alias
//// RequestGameToken   (ciphered)    ─▶ the token kept at LoginFinish, no ask
//// Ping (one-way, every 30 s)       ─▶ nothing
//// ```
////
//// - **Refusals.** An unknown name and a wrong password answer Error 3002,
////   which the client shows as "Invalid account name or password"; it cannot
////   tell the two apart (0x1400b2f20, StsConnLib64.MT.dll!0x180003d30). A
////   store that gives no answer at LoginStart (`NotRunning`, `NoAnswerInTime`,
////   `EndedBeforeAnswer`, `StoppedWaiting`, or its `Unavailable`) answers
////   Error 42, "NCSoft login service start timeout" (0x1400b2f20); a hand-off
////   that gives no answer at LoginFinish, or a token already held, answers
////   Error 42, "NCSoft login service finish timeout" (0x1400b3070). Each logs
////   a warning: the failure is the server's, never the player's. After any
////   of these the connection goes on, waiting for the client's next
////   LoginStart or LoginFinish.
//// - **Why the token is kept at LoginFinish.** Every failure of
////   RequestGameToken, an Error, a reply without Token or no reply, leaves the
////   client on "Authenticating" with no message and no way on (0x1400b3a50).
////   So the rule keeps the token before it answers LoginFinish, where a
////   refusal shows a message, and RequestGameToken makes no ask that could
////   fail. The client sends the three requests back to back, so the token's
////   lifetime starts only a moment early.
//// - **RC4.** Everything is plain up to the end of the reply carrying M2.
////   From the next byte each way, one RC4 state per direction under the
////   64-byte key K runs on across messages (StsConnLib64.MT.dll!0x18000a350).
////   The rule sends nothing between the M2 reply and the client's LoginFinish.
//// - **The account list.** Exactly one GameAccount, with the login name as its
////   Alias; the client reads only the Alias and sends it back in
////   RequestGameToken (StsConnLib64.MT.dll!0x180004950, 0x1400b36c0). Its
////   Created is sent empty, since the client never reads it.
//// - **UserId.** The account's game account id as GUID text; the client only
////   sends it back, in ListMyAccounts, RequestGameToken and 0x592.
//// - **Out of order.** A request the client never sends at that point, such
////   as KeyData before LoginStart, ends the connection with an error log;
////   bytes that are no STS request end it too. A whole request of a command
////   the rule does not know is logged as unhandled and the connection goes on.
//// - **Reads during an ask.** A read's requests after the one that asked stay
////   in the state and are taken once the answer comes.

import genesis_prime/hand_off.{GameToken, Holder, Put}
import genesis_prime/login.{
  type Answer, type Request, AskHandOff, AskStore, FromHandOff, FromStore,
}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/login/rc4
import genesis_prime/login/srp
import genesis_prime/login/sts_message.{
  ConnectionOpened, GameAccount, KeyData, ListMyAccounts, LoginFinish,
  LoginStart, Ping, RequestGameToken, Transaction, UnknownCommand,
}
import genesis_prime/login/sts_wire
import genesis_prime/random.{type Random}
import genesis_prime/step.{
  type About, type ConnectionId, type Effect, type Input, type Now, type Outcome,
  type Peer, type Step, About, Accepted, Answered, AnsweredLate, AskId, Asked,
  Effects, EffectsThenAsk, Log, LogError, LogInfo, LogLine, LogWarning,
  PeerClosed, ReadFailed, Socket, Started, Stop, Stopping, TimerFired, Woken,
  Write, WriteFailed,
}
import genesis_prime/store.{
  type Account, AccountFound, FindAccount, NoSuchAccount, Unavailable,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// What every STS connection is made with, at start.
pub type Settings {
  Settings(
    /// How long an ask to the store or the hand-off may take.
    ask_deadline_ms: Int,
    /// How long a game token stays good in the hand-off: the client shows it
    /// to the auth server right after it gets it.
    game_token_lifetime_ms: Int,
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
    /// Bytes of a request not yet whole, and whole requests not yet taken
    /// while an ask is out. Once RC4 is on they are already deciphered.
    pending: BitArray,
    /// The number of the last ask made, so each ask has an id of its own.
    asks: Int,
    status: Status,
  )
}

/// The RC4 state of each direction once the proof has passed.
type Ciphers {
  Ciphers(receiving: rc4.Stream, sending: rc4.Stream)
}

/// The login's one status, in the order the client's requests come.
type Status {
  /// Waiting for Connect, then LoginStart.
  AwaitingLoginStart
  /// The store is asked for the account LoginStart named.
  FindingAccount(sequence: Int)
  /// KeyData(salt, B) is sent; waiting for the client's A and M1.
  AwaitingProof(account: Account, challenge: srp.Challenge)
  /// The proof passed and RC4 is on; waiting for LoginFinish.
  AwaitingLoginFinish(account: Account, ciphers: Ciphers)
  /// The hand-off is asked to keep the game token, before LoginFinish is
  /// answered.
  KeepingToken(sequence: Int, account: Account, token: Guid, ciphers: Ciphers)
  /// LoginFinish is answered; waiting for ListMyAccounts.
  AwaitingAccountList(account: Account, token: Guid, ciphers: Ciphers)
  /// The account list is answered; waiting for RequestGameToken.
  AwaitingTokenRequest(account: Account, token: Guid, ciphers: Ciphers)
  /// The token is given; the client goes on to the auth server and keeps
  /// this connection open with its pings until it closes it.
  TokenGiven(account: Account, ciphers: Ciphers)
}

/// The error code the client shows as "Invalid account name or password".
const invalid_credentials = 3002

/// The error code the client shows as a login service timeout, at LoginStart
/// "start timeout" and at LoginFinish "finish timeout".
const service_timeout = 42

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

/// The only input a connection not yet accepted takes is `Accepted`; the
/// shell gives it first, so any other is a bug.
fn before_accept(
  settings settings: Settings,
  event event: step.Event(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  case event {
    Socket(Accepted(connection:, peer:, seed:)) -> #(
      Connected(Session(
        settings:,
        connection:,
        peer:,
        random: random.new(seed:),
        pending: <<>>,
        asks: 0,
        status: AwaitingLoginStart,
      )),
      Effects([]),
    )
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
          text: "the STS rule took an input before the connection was accepted",
          about: no_one(),
        )),
        Stop,
      ]),
    )
  }
}

fn after_accept(
  session session: Session,
  now now: Now,
  event event: step.Event(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  case event {
    Socket(step.Read(bytes:)) -> read(session:, now:, bytes:)
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
          text: "the STS rule took an input a connection is never given",
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

/// Reads bytes the client sent: deciphered when RC4 is on, then added to the
/// bytes not yet taken, whose whole requests are taken one by one.
fn read(
  session session: Session,
  now now: Now,
  bytes bytes: BitArray,
) -> #(State, Step(Nil, Request)) {
  let #(status, plain) = receive(session.status, bytes)
  let session =
    Session(..session, status:, pending: <<session.pending:bits, plain:bits>>)
  case session.status {
    // A request is taken only once the answer to the ask in flight comes.
    FindingAccount(..) | KeepingToken(..) -> #(Connected(session), Effects([]))
    AwaitingLoginStart
    | AwaitingProof(..)
    | AwaitingLoginFinish(..)
    | AwaitingAccountList(..)
    | AwaitingTokenRequest(..)
    | TokenGiven(..) -> drive(session:, now:, carried: [])
  }
}

/// What taking one request, or one answer, decided.
type Handled {
  /// Go on to the next request in the bytes.
  Continue(session: Session, effects: List(Effect(Nil)))
  /// Carry out the effects, then ask; the requests after this one wait.
  Ask(session: Session, effects: List(Effect(Nil)), ask: step.Ask(Request))
  /// Carry out the effects, which end with `Stop`.
  End(session: Session, effects: List(Effect(Nil)))
}

/// Takes the whole requests in the pending bytes in order until one asks or
/// the bytes hold no more.
fn drive(
  session session: Session,
  now now: Now,
  carried carried: List(Effect(Nil)),
) -> #(State, Step(Nil, Request)) {
  case sts_wire.take(session.pending) {
    Error(error) ->
      end(session:, carried:, effects: [
        log(
          session:,
          level: LogError,
          text: "the bytes are no STS request: " <> sts_wire.describe(error),
        ),
        Stop,
      ])
    Ok(None) -> #(Connected(session), Effects(carried))
    Ok(Some(#(request, rest))) ->
      settle(
        handled: handle(
          session: Session(..session, pending: rest),
          now:,
          request:,
        ),
        now:,
        carried:,
      )
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

/// What one whole request does.
fn handle(
  session session: Session,
  now now: Now,
  request request: sts_wire.Request,
) -> Handled {
  case sts_message.decode(request) {
    Error(UnknownCommand(protocol:, command:)) ->
      Continue(session, [
        log(
          session:,
          level: LogWarning,
          text: "unhandled STS request /" <> protocol <> "/" <> command,
        ),
      ])
    Error(error) ->
      End(session, [
        log(session:, level: LogError, text: sts_message.describe(error)),
        Stop,
      ])
    Ok(ConnectionOpened(..)) ->
      case session.status {
        AwaitingLoginStart -> Continue(session, [])
        FindingAccount(..)
        | AwaitingProof(..)
        | AwaitingLoginFinish(..)
        | KeepingToken(..)
        | AwaitingAccountList(..)
        | AwaitingTokenRequest(..)
        | TokenGiven(..) -> out_of_order(session, "Connect")
      }
    Ok(Ping) -> Continue(session, [])
    Ok(Transaction(sequence:, request: transaction)) ->
      transact(session:, now:, sequence:, transaction:)
  }
}

fn transact(
  session session: Session,
  now now: Now,
  sequence sequence: Int,
  transaction transaction: sts_message.Transaction,
) -> Handled {
  case session.status, transaction {
    AwaitingLoginStart, LoginStart(login_name:, ..) ->
      ask(
        session: Session(..session, status: FindingAccount(sequence:)),
        now:,
        request: AskStore(FindAccount(login_name:)),
      )
    AwaitingProof(account:, challenge:), KeyData(bytes:) ->
      prove(session:, sequence:, account:, challenge:, key_data: bytes)
    AwaitingLoginFinish(account:, ciphers:), LoginFinish -> {
      let #(random, token_bytes) = random.bytes(session.random, 16)
      let assert Ok(token) = guid.from_wire(token_bytes)
        as "sixteen bytes are a GUID"
      ask(
        session: Session(
          ..session,
          random:,
          status: KeepingToken(sequence:, account:, token:, ciphers:),
        ),
        now:,
        request: AskHandOff(Put(
          key: GameToken(token:),
          holder: Holder(
            account_id: account.account_id,
            login_name: account.login_name,
            game_account_id: account.game_account_id,
          ),
          lifetime_ms: session.settings.game_token_lifetime_ms,
        )),
      )
    }
    AwaitingAccountList(account:, token:, ciphers:), ListMyAccounts(..) -> {
      let #(status, written) =
        send(
          AwaitingTokenRequest(account:, token:, ciphers:),
          sts_message.encode(
            sts_message.GameAccounts(sequence:, accounts: [
              GameAccount(
                alias: account.login_name,
                created: "",
                game_account_id: guid.to_text(account.game_account_id),
              ),
            ]),
          ),
        )
      Continue(Session(..session, status:), [Write(written)])
    }
    AwaitingTokenRequest(account:, token:, ciphers:), RequestGameToken(..) -> {
      let #(status, written) =
        send(
          TokenGiven(account:, ciphers:),
          sts_message.encode(sts_message.GameToken(
            sequence:,
            token: guid.to_text(token),
          )),
        )
      Continue(Session(..session, status:), [
        Write(written),
        Log(LogLine(
          level: LogInfo,
          text: "the STS login is finished and the game token is given",
          about: about(session),
        )),
      ])
    }
    AwaitingLoginStart, KeyData(..)
    | AwaitingLoginStart, LoginFinish
    | AwaitingLoginStart, ListMyAccounts(..)
    | AwaitingLoginStart, RequestGameToken(..)
    | FindingAccount(..), LoginStart(..)
    | FindingAccount(..), KeyData(..)
    | FindingAccount(..), LoginFinish
    | FindingAccount(..), ListMyAccounts(..)
    | FindingAccount(..), RequestGameToken(..)
    | AwaitingProof(..), LoginStart(..)
    | AwaitingProof(..), LoginFinish
    | AwaitingProof(..), ListMyAccounts(..)
    | AwaitingProof(..), RequestGameToken(..)
    | AwaitingLoginFinish(..), LoginStart(..)
    | AwaitingLoginFinish(..), KeyData(..)
    | AwaitingLoginFinish(..), ListMyAccounts(..)
    | AwaitingLoginFinish(..), RequestGameToken(..)
    | KeepingToken(..), LoginStart(..)
    | KeepingToken(..), KeyData(..)
    | KeepingToken(..), LoginFinish
    | KeepingToken(..), ListMyAccounts(..)
    | KeepingToken(..), RequestGameToken(..)
    | AwaitingAccountList(..), LoginStart(..)
    | AwaitingAccountList(..), KeyData(..)
    | AwaitingAccountList(..), LoginFinish
    | AwaitingAccountList(..), RequestGameToken(..)
    | AwaitingTokenRequest(..), LoginStart(..)
    | AwaitingTokenRequest(..), KeyData(..)
    | AwaitingTokenRequest(..), LoginFinish
    | AwaitingTokenRequest(..), ListMyAccounts(..)
    | TokenGiven(..), _
    -> out_of_order(session, request_name(transaction))
  }
}

fn request_name(transaction: sts_message.Transaction) -> String {
  case transaction {
    LoginStart(..) -> "LoginStart"
    KeyData(..) -> "KeyData"
    LoginFinish -> "LoginFinish"
    ListMyAccounts(..) -> "ListMyAccounts"
    RequestGameToken(..) -> "RequestGameToken"
  }
}

/// A request the client never sends at that point ends the connection.
fn out_of_order(session: Session, name: String) -> Handled {
  End(session, [
    log(
      session:,
      level: LogError,
      text: "the request "
        <> name
        <> " came out of order, in "
        <> where_is(session.status),
    ),
    Stop,
  ])
}

fn where_is(status: Status) -> String {
  case status {
    AwaitingLoginStart -> "the wait for LoginStart"
    FindingAccount(..) -> "the wait for the store's answer"
    AwaitingProof(..) -> "the wait for the proof"
    AwaitingLoginFinish(..) -> "the wait for LoginFinish"
    KeepingToken(..) -> "the wait for the hand-off's answer"
    AwaitingAccountList(..) -> "the wait for ListMyAccounts"
    AwaitingTokenRequest(..) -> "the wait for RequestGameToken"
    TokenGiven(..) -> "the finished login"
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

/// The client's KeyData: A and M1. A right proof is answered with M2 in plain
/// text and RC4 under K starts in both directions from the next byte; a wrong
/// one with error 3002, plain.
fn prove(
  session session: Session,
  sequence sequence: Int,
  account account: Account,
  challenge challenge: srp.Challenge,
  key_data key_data: BitArray,
) -> Handled {
  case srp.prove(challenge:, key_data:) {
    Ok(srp.Proven(session_key:, server_key_data:)) ->
      case session.pending {
        <<>> -> {
          let assert Ok(receiving) = rc4.start(session_key)
            as "the session key is 64 bytes"
          let assert Ok(sending) = rc4.start(session_key)
            as "the session key is 64 bytes"
          Continue(
            Session(
              ..session,
              status: AwaitingLoginFinish(
                account:,
                ciphers: Ciphers(receiving:, sending:),
              ),
            ),
            [
              Write(
                sts_message.encode(sts_message.KeyDataAnswer(
                  sequence:,
                  key_data: server_key_data,
                )),
              ),
            ],
          )
        }
        _ ->
          End(session, [
            log(
              session:,
              level: LogError,
              text: "the client sent bytes after the proof, before it had M2",
            ),
            Stop,
          ])
      }
    Error(srp.ProofRefused) ->
      Continue(Session(..session, status: AwaitingLoginStart), [
        Write(refusal(sequence, invalid_credentials)),
      ])
    Error(srp.KeyDataMalformed) ->
      end_for(session, "the client's KeyData is not a length, A, 32 and M1")
    Error(srp.ClientValueRejected) ->
      end_for(session, "the client's A is zero or not below N")
    Error(srp.ScramblerZero) ->
      end_for(session, "the scrambling value of A and B is zero")
    Error(srp.SecretNotThirtyTwoBytes(..)) ->
      end_for(session, "the server's secret is not 32 bytes")
  }
}

fn end_for(session: Session, reason: String) -> Handled {
  End(session, [log(session:, level: LogError, text: reason), Stop])
}

fn refusal(sequence: Int, code: Int) -> BitArray {
  sts_message.encode(sts_message.Refused(sequence:, code:))
}

/// The answer to the ask in flight.
fn answered(
  session session: Session,
  now _now: Now,
  outcome outcome: Outcome(Answer),
) -> Handled {
  case session.status {
    FindingAccount(sequence:) -> found(session:, sequence:, outcome:)
    KeepingToken(sequence:, account:, token:, ciphers:) ->
      kept(session:, sequence:, account:, token:, ciphers:, outcome:)
    AwaitingLoginStart
    | AwaitingProof(..)
    | AwaitingLoginFinish(..)
    | AwaitingAccountList(..)
    | AwaitingTokenRequest(..)
    | TokenGiven(..) -> end_for(session, "an answer came when no ask was out")
  }
}

/// The store's answer to the account's lookup.
fn found(
  session session: Session,
  sequence sequence: Int,
  outcome outcome: Outcome(Answer),
) -> Handled {
  case outcome {
    step.Answer(FromStore(AccountFound(account:))) -> {
      let #(random, secret) = random.bytes(session.random, 32)
      let assert Ok(#(challenge, key_data)) =
        srp.challenge(
          name: account.login_name,
          salt: account.srp_salt,
          verifier: account.srp_verifier,
          secret:,
        )
        as "the secret is 32 bytes"
      Continue(
        Session(..session, random:, status: AwaitingProof(account:, challenge:)),
        [
          Write(
            sts_message.encode(sts_message.KeyDataAnswer(sequence:, key_data:)),
          ),
        ],
      )
    }
    step.Answer(FromStore(NoSuchAccount)) ->
      Continue(Session(..session, status: AwaitingLoginStart), [
        Write(refusal(sequence, invalid_credentials)),
      ])
    step.Answer(FromStore(Unavailable)) ->
      timed_out(session:, sequence:, what: "the store was unavailable")
    step.Answer(FromHandOff(..)) ->
      end_for(session, "the hand-off answered the ask for the account")
    step.NotRunning ->
      timed_out(session:, sequence:, what: "the store was not running")
    step.NoAnswerInTime ->
      timed_out(session:, sequence:, what: "the store gave no answer in time")
    step.EndedBeforeAnswer ->
      timed_out(session:, sequence:, what: "the store ended before it answered")
    step.StoppedWaiting ->
      timed_out(session:, sequence:, what: "the server began stopping")
  }
}

/// The store gave no answer at LoginStart: error 42, "start timeout", and a
/// warning, since the failure is the server's. The client may start again.
fn timed_out(
  session session: Session,
  sequence sequence: Int,
  what what: String,
) -> Handled {
  Continue(Session(..session, status: AwaitingLoginStart), [
    log(
      session:,
      level: LogWarning,
      text: "LoginStart is answered with error "
        <> int.to_string(service_timeout)
        <> ": "
        <> what,
    ),
    Write(refusal(sequence, service_timeout)),
  ])
}

/// The hand-off's answer to keeping the game token.
fn kept(
  session session: Session,
  sequence sequence: Int,
  account account: Account,
  token token: Guid,
  ciphers ciphers: Ciphers,
  outcome outcome: Outcome(Answer),
) -> Handled {
  case outcome {
    step.Answer(FromHandOff(hand_off.Kept)) -> {
      let #(status, written) =
        send(
          AwaitingAccountList(account:, token:, ciphers:),
          sts_message.encode(sts_message.LoginFinished(
            sequence:,
            user_id: guid.to_text(account.game_account_id),
            user_name: account.login_name,
          )),
        )
      Continue(Session(..session, status:), [Write(written)])
    }
    step.Answer(FromHandOff(hand_off.AlreadyHeld)) ->
      finish_timed_out(
        session:,
        sequence:,
        account:,
        ciphers:,
        what: "the hand-off already held the game token",
      )
    step.Answer(FromHandOff(hand_off.Taken(..)))
    | step.Answer(FromHandOff(hand_off.NoHolder))
    | step.Answer(FromStore(..)) ->
      end_for(session, "the hand-off's answer is none a Put gets")
    step.NotRunning ->
      finish_timed_out(
        session:,
        sequence:,
        account:,
        ciphers:,
        what: "the hand-off was not running",
      )
    step.NoAnswerInTime ->
      finish_timed_out(
        session:,
        sequence:,
        account:,
        ciphers:,
        what: "the hand-off gave no answer in time",
      )
    step.EndedBeforeAnswer ->
      finish_timed_out(
        session:,
        sequence:,
        account:,
        ciphers:,
        what: "the hand-off ended before it answered",
      )
    step.StoppedWaiting ->
      finish_timed_out(
        session:,
        sequence:,
        account:,
        ciphers:,
        what: "the server began stopping",
      )
  }
}

/// The hand-off gave no answer at LoginFinish: error 42, "finish timeout",
/// ciphered, and a warning. The client may send LoginFinish again.
fn finish_timed_out(
  session session: Session,
  sequence sequence: Int,
  account account: Account,
  ciphers ciphers: Ciphers,
  what what: String,
) -> Handled {
  let #(status, written) =
    send(
      AwaitingLoginFinish(account:, ciphers:),
      refusal(sequence, service_timeout),
    )
  Continue(Session(..session, status:), [
    log(
      session:,
      level: LogWarning,
      text: "LoginFinish is answered with error "
        <> int.to_string(service_timeout)
        <> ": "
        <> what,
    ),
    Write(written),
  ])
}

// ---- RC4 ----

/// The RC4 state of the status, when the proof has passed.
fn ciphers_of(status: Status) -> Option(Ciphers) {
  case status {
    AwaitingLoginFinish(ciphers:, ..)
    | KeepingToken(ciphers:, ..)
    | AwaitingAccountList(ciphers:, ..)
    | AwaitingTokenRequest(ciphers:, ..)
    | TokenGiven(ciphers:, ..) -> Some(ciphers)
    AwaitingLoginStart | FindingAccount(..) | AwaitingProof(..) -> None
  }
}

/// The status with other RC4 state.
fn with_ciphers(status: Status, ciphers: Ciphers) -> Status {
  case status {
    AwaitingLoginFinish(account:, ..) -> AwaitingLoginFinish(account:, ciphers:)
    KeepingToken(sequence:, account:, token:, ..) ->
      KeepingToken(sequence:, account:, token:, ciphers:)
    AwaitingAccountList(account:, token:, ..) ->
      AwaitingAccountList(account:, token:, ciphers:)
    AwaitingTokenRequest(account:, token:, ..) ->
      AwaitingTokenRequest(account:, token:, ciphers:)
    TokenGiven(account:, ..) -> TokenGiven(account:, ciphers:)
    AwaitingLoginStart | FindingAccount(..) | AwaitingProof(..) -> status
  }
}

/// The bytes the client sent, deciphered once RC4 is on, and the status with
/// its receiving state moved on.
fn receive(status: Status, bytes: BitArray) -> #(Status, BitArray) {
  case ciphers_of(status) {
    None -> #(status, bytes)
    Some(Ciphers(receiving:, sending:)) -> {
      let #(receiving, plain) = rc4.crypt(receiving, bytes)
      #(with_ciphers(status, Ciphers(receiving:, sending:)), plain)
    }
  }
}

/// The bytes to write, ciphered once RC4 is on, and the status with its
/// sending state moved on. The status given is the one after the write.
fn send(status: Status, bytes: BitArray) -> #(Status, BitArray) {
  case ciphers_of(status) {
    None -> #(status, bytes)
    Some(Ciphers(receiving:, sending:)) -> {
      let #(sending, ciphered) = rc4.crypt(sending, bytes)
      #(with_ciphers(status, Ciphers(receiving:, sending:)), ciphered)
    }
  }
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
    account_id: case account_of(session.status) {
      Some(store.Account(account_id: store.AccountId(id), ..)) -> Some(id)
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

/// The account the login is for, once the store has found it.
fn account_of(status: Status) -> Option(Account) {
  case status {
    AwaitingProof(account:, ..)
    | AwaitingLoginFinish(account:, ..)
    | KeepingToken(account:, ..)
    | AwaitingAccountList(account:, ..)
    | AwaitingTokenRequest(account:, ..)
    | TokenGiven(account:, ..) -> Some(account)
    AwaitingLoginStart | FindingAccount(..) -> None
  }
}
