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

import genesis_prime/client_connection.{
  type Answer, type Link, type Request, AskHandOff, AskStore, Asking, Bytes,
  Connect, Continue, End, FromHandOff, FromStore, Otherwise,
}
import genesis_prime/hand_off.{GameToken, Holder, Put}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/login/rc4
import genesis_prime/login/srp
import genesis_prime/login/sts_message.{
  ConnectionOpened, GameAccount, KeyData, ListMyAccounts, LoginFinish,
  LoginStart, Ping, RequestGameToken, Transaction, UnknownCommand,
}
import genesis_prime/login/sts_wire
import genesis_prime/step.{
  type Effect, type Input, type Now, type Outcome, type Rule, type Step, Effects,
  LogError, LogInfo, LogWarning, Rule, Stop, Write,
}
import genesis_prime/store.{
  type Account, AccountFound, FindAccount, ForLogin, ForSelect, Login,
  NoSuchAccount, Unavailable,
}
import gleam/int
import gleam/option.{type Option, None, Some}

/// The rule's name in a recording's header and in the server's tree.
pub const rule_name = "genesis_prime/login/sts_connection"

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
    link: Link,
    /// Bytes of a request not yet whole, and whole requests not yet taken
    /// while an ask is out. Once RC4 is on they are already deciphered.
    pending: BitArray,
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
  /// The proof passed and RC4 is on; `stage` is where the login is after it.
  Proven(account: Account, ciphers: Ciphers, stage: Stage)
}

/// Where the login is once the proof has passed.
type Stage {
  /// Waiting for LoginFinish.
  AwaitingLoginFinish
  /// The hand-off is asked to keep the game token, before LoginFinish is
  /// answered.
  KeepingToken(sequence: Int, token: Guid)
  /// LoginFinish is answered; waiting for ListMyAccounts.
  AwaitingAccountList(token: Guid)
  /// The account list is answered; waiting for RequestGameToken.
  AwaitingTokenRequest(token: Guid)
  /// The token is given; the client goes on to the auth server and keeps
  /// this connection open with its pings until it closes it.
  TokenGiven
}

/// The error code the client shows as "Invalid account name or password".
const invalid_credentials = 3002

/// The error code the client shows as a login service timeout, at LoginStart
/// "start timeout" and at LoginFinish "finish timeout".
const service_timeout = 42

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
    NotAccepted(settings:) -> {
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
            status: AwaitingLoginStart,
          )),
          Effects([]),
        )
        Bytes(..) | client_connection.Outcome(..) -> #(
          state,
          client_connection.before_accepted(rule: "STS"),
        )
        Otherwise(step:) -> #(state, step)
      }
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
        link: session.link,
        account_id: account_id_of(session.status),
      ),
      stopping: fn() { [] },
    )
  {
    Bytes(bytes:) -> read(session:, now:, bytes:)
    client_connection.Outcome(outcome:) ->
      client_connection.settle(
        handled: answered(session:, outcome:),
        flow: flow(now),
        carried: [],
      )
    Connect(..) -> #(
      Connected(session),
      client_connection.accepted_again(
        link: session.link,
        account_id: account_id_of(session.status),
        rule: "STS",
      ),
    )
    Otherwise(step:) -> #(Connected(session), step)
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
    FindingAccount(..) | Proven(stage: KeepingToken(..), ..) -> #(
      Connected(session),
      Effects([]),
    )
    AwaitingLoginStart
    | AwaitingProof(..)
    | Proven(stage: AwaitingLoginFinish, ..)
    | Proven(stage: AwaitingAccountList(..), ..)
    | Proven(stage: AwaitingTokenRequest(..), ..)
    | Proven(stage: TokenGiven, ..) ->
      client_connection.drive(session:, flow: flow(now), carried: [])
  }
}

/// How the rule takes the client's requests, at the time of an input.
fn flow(
  now: Now,
) -> client_connection.Flow(
  Session,
  sts_wire.Request,
  sts_wire.WireError,
  State,
) {
  client_connection.Flow(
    pending: fn(session: Session) { session.pending },
    take: sts_wire.take,
    taking: fn(session, request, rest) {
      handle(session: Session(..session, pending: rest), now:, request:)
    },
    refused: fn(session, error) {
      End(session, [
        log(
          session:,
          level: LogError,
          text: "the bytes are no STS request: " <> sts_wire.describe(error),
        ),
        Stop,
      ])
    },
    connected: Connected,
  )
}

/// What one whole request does.
fn handle(
  session session: Session,
  now now: Now,
  request request: sts_wire.Request,
) -> client_connection.Handled(Session) {
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
        FindingAccount(..) | AwaitingProof(..) | Proven(..) ->
          out_of_order(session, "Connect")
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
) -> client_connection.Handled(Session) {
  case session.status, transaction {
    AwaitingLoginStart, LoginStart(login_name:, ..) ->
      ask(
        session: Session(..session, status: FindingAccount(sequence:)),
        now:,
        request: AskStore(Login(FindAccount(login_name:))),
      )
    AwaitingProof(account:, challenge:), KeyData(bytes:) ->
      prove(session:, sequence:, account:, challenge:, key_data: bytes)
    Proven(account:, ciphers:, stage: AwaitingLoginFinish), LoginFinish -> {
      let #(link, token_bytes) = client_connection.draw(session.link, 16)
      let assert Ok(token) = guid.from_wire(token_bytes)
        as "sixteen bytes are a GUID"
      ask(
        session: Session(
          ..session,
          link:,
          status: Proven(
            account:,
            ciphers:,
            stage: KeepingToken(sequence:, token:),
          ),
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
    Proven(account:, ciphers:, stage: AwaitingAccountList(token:)),
      ListMyAccounts(..)
    -> {
      let #(status, written) =
        send(
          account:,
          ciphers:,
          stage: AwaitingTokenRequest(token:),
          bytes: sts_message.encode(
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
    Proven(account:, ciphers:, stage: AwaitingTokenRequest(token:)),
      RequestGameToken(..)
    -> {
      let #(status, written) =
        send(
          account:,
          ciphers:,
          stage: TokenGiven,
          bytes: sts_message.encode(sts_message.GameToken(
            sequence:,
            token: guid.to_text(token),
          )),
        )
      Continue(Session(..session, status:), [
        Write(written),
        log(
          session:,
          level: LogInfo,
          text: "the STS login is finished and the game token is given",
        ),
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
    | Proven(..), LoginStart(..)
    | Proven(..), KeyData(..)
    | Proven(stage: AwaitingLoginFinish, ..), ListMyAccounts(..)
    | Proven(stage: AwaitingLoginFinish, ..), RequestGameToken(..)
    | Proven(stage: KeepingToken(..), ..), LoginFinish
    | Proven(stage: KeepingToken(..), ..), ListMyAccounts(..)
    | Proven(stage: KeepingToken(..), ..), RequestGameToken(..)
    | Proven(stage: AwaitingAccountList(..), ..), LoginFinish
    | Proven(stage: AwaitingAccountList(..), ..), RequestGameToken(..)
    | Proven(stage: AwaitingTokenRequest(..), ..), LoginFinish
    | Proven(stage: AwaitingTokenRequest(..), ..), ListMyAccounts(..)
    | Proven(stage: TokenGiven, ..), LoginFinish
    | Proven(stage: TokenGiven, ..), ListMyAccounts(..)
    | Proven(stage: TokenGiven, ..), RequestGameToken(..)
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
fn out_of_order(
  session: Session,
  name: String,
) -> client_connection.Handled(Session) {
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
    Proven(stage: AwaitingLoginFinish, ..) -> "the wait for LoginFinish"
    Proven(stage: KeepingToken(..), ..) -> "the wait for the hand-off's answer"
    Proven(stage: AwaitingAccountList(..), ..) -> "the wait for ListMyAccounts"
    Proven(stage: AwaitingTokenRequest(..), ..) ->
      "the wait for RequestGameToken"
    Proven(stage: TokenGiven, ..) -> "the finished login"
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

/// The client's KeyData: A and M1. A right proof is answered with M2 in plain
/// text and RC4 under K starts in both directions from the next byte; a wrong
/// one with error 3002, plain.
fn prove(
  session session: Session,
  sequence sequence: Int,
  account account: Account,
  challenge challenge: srp.Challenge,
  key_data key_data: BitArray,
) -> client_connection.Handled(Session) {
  case srp.prove(challenge:, key_data:) {
    Ok(srp.Proven(session_key:, server_key_data:)) ->
      case session.pending {
        <<>> -> {
          let assert Ok(stream) = rc4.start(session_key)
            as "the session key is 64 bytes"
          Continue(
            Session(
              ..session,
              status: Proven(
                account:,
                ciphers: Ciphers(receiving: stream, sending: stream),
                stage: AwaitingLoginFinish,
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
          end_for(
            session,
            "the client sent bytes after the proof, before it had M2",
          )
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

fn end_for(
  session: Session,
  reason: String,
) -> client_connection.Handled(Session) {
  End(session, [log(session:, level: LogError, text: reason), Stop])
}

fn refusal(sequence: Int, code: Int) -> BitArray {
  sts_message.encode(sts_message.Refused(sequence:, code:))
}

/// The answer to the ask in flight.
fn answered(
  session session: Session,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case session.status {
    FindingAccount(sequence:) -> found(session:, sequence:, outcome:)
    Proven(account:, ciphers:, stage: KeepingToken(sequence:, token:)) ->
      kept(session:, sequence:, account:, token:, ciphers:, outcome:)
    AwaitingLoginStart
    | AwaitingProof(..)
    | Proven(stage: AwaitingLoginFinish, ..)
    | Proven(stage: AwaitingAccountList(..), ..)
    | Proven(stage: AwaitingTokenRequest(..), ..)
    | Proven(stage: TokenGiven, ..) ->
      end_for(session, "an answer came when no ask was out")
  }
}

/// The store's answer to the account's lookup.
fn found(
  session session: Session,
  sequence sequence: Int,
  outcome outcome: Outcome(Answer),
) -> client_connection.Handled(Session) {
  case outcome {
    step.Answer(FromStore(ForLogin(AccountFound(account:)))) -> {
      let #(link, secret) = client_connection.draw(session.link, 32)
      let assert Ok(#(challenge, key_data)) =
        srp.challenge(
          name: account.login_name,
          salt: account.srp_salt,
          verifier: account.srp_verifier,
          secret:,
        )
        as "the secret is 32 bytes"
      Continue(
        Session(..session, link:, status: AwaitingProof(account:, challenge:)),
        [
          Write(
            sts_message.encode(sts_message.KeyDataAnswer(sequence:, key_data:)),
          ),
        ],
      )
    }
    step.Answer(FromStore(ForLogin(NoSuchAccount))) ->
      Continue(Session(..session, status: AwaitingLoginStart), [
        Write(refusal(sequence, invalid_credentials)),
      ])
    step.Answer(FromStore(Unavailable)) ->
      timed_out(session:, sequence:, what: "the store was unavailable")
    step.Answer(FromHandOff(..)) ->
      end_for(session, "the hand-off answered the ask for the account")
    step.Answer(FromStore(ForSelect(..))) ->
      end_for(
        session,
        "the store answered the ask for the account with an answer for character select",
      )
    step.NotRunning
    | step.NoAnswerInTime
    | step.EndedBeforeAnswer
    | step.StoppedWaiting ->
      timed_out(
        session:,
        sequence:,
        what: client_connection.without_answer(who: "the store", outcome:),
      )
  }
}

/// The store gave no answer at LoginStart: error 42, "start timeout", and a
/// warning, since the failure is the server's. The client may start again.
fn timed_out(
  session session: Session,
  sequence sequence: Int,
  what what: String,
) -> client_connection.Handled(Session) {
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
) -> client_connection.Handled(Session) {
  let timed_out = fn(what) {
    // Error 42, "finish timeout", ciphered, and a warning; the client may
    // send LoginFinish again.
    let #(status, written) =
      send(
        account:,
        ciphers:,
        stage: AwaitingLoginFinish,
        bytes: refusal(sequence, service_timeout),
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
  case outcome {
    step.Answer(FromHandOff(hand_off.Kept)) -> {
      let #(status, written) =
        send(
          account:,
          ciphers:,
          stage: AwaitingAccountList(token:),
          bytes: sts_message.encode(sts_message.LoginFinished(
            sequence:,
            user_id: guid.to_text(account.game_account_id),
            user_name: account.login_name,
          )),
        )
      Continue(Session(..session, status:), [Write(written)])
    }
    step.Answer(FromHandOff(hand_off.AlreadyHeld)) ->
      timed_out("the hand-off already held the game token")
    step.Answer(FromHandOff(hand_off.Taken(..)))
    | step.Answer(FromHandOff(hand_off.NoHolder))
    | step.Answer(FromStore(..)) ->
      end_for(session, "the hand-off's answer is none a Put gets")
    step.NotRunning
    | step.NoAnswerInTime
    | step.EndedBeforeAnswer
    | step.StoppedWaiting ->
      timed_out(client_connection.without_answer(who: "the hand-off", outcome:))
  }
}

// ---- RC4 ----

/// The bytes the client sent, deciphered once RC4 is on, and the status with
/// its receiving state moved on.
fn receive(status: Status, bytes: BitArray) -> #(Status, BitArray) {
  case status {
    Proven(account:, ciphers:, stage:) -> {
      let #(receiving, plain) = rc4.crypt(ciphers.receiving, bytes)
      #(
        Proven(account:, ciphers: Ciphers(..ciphers, receiving:), stage:),
        plain,
      )
    }
    AwaitingLoginStart | FindingAccount(..) | AwaitingProof(..) -> #(
      status,
      bytes,
    )
  }
}

/// The bytes to write, ciphered, and the status at `stage` with its sending
/// state moved on.
fn send(
  account account: Account,
  ciphers ciphers: Ciphers,
  stage stage: Stage,
  bytes bytes: BitArray,
) -> #(Status, BitArray) {
  let #(sending, ciphered) = rc4.crypt(ciphers.sending, bytes)
  #(Proven(account:, ciphers: Ciphers(..ciphers, sending:), stage:), ciphered)
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

/// The id of the account the login is for, once the store has found it.
fn account_id_of(status: Status) -> Option(Int) {
  case status {
    AwaitingProof(
      account: store.Account(account_id: store.AccountId(id), ..),
      ..,
    )
    | Proven(account: store.Account(account_id: store.AccountId(id), ..), ..) ->
      Some(id)
    AwaitingLoginStart | FindingAccount(..) -> None
  }
}
