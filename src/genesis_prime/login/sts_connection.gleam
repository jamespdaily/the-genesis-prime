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
////   a warning: the failure is the server's, never the player's.
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
////   RequestGameToken (StsConnLib64.MT.dll!0x180004950, 0x1400b36c0).
//// - **UserId.** The account's game account id as GUID text; the client only
////   sends it back, in ListMyAccounts, RequestGameToken and 0x592.
//// - **Out of order.** A request the client never sends at that point, such
////   as KeyData before LoginStart, ends the connection with an error log;
////   bytes that are no STS request end it too. A whole request of a command
////   the rule does not know is logged as unhandled and the connection goes on.
//// - **Reads during an ask.** A read's requests after the one that asked stay
////   in the state and are taken once the answer comes.

import genesis_prime/login.{type Answer, type Request}
import genesis_prime/login/guid.{type Guid}
import genesis_prime/login/rc4
import genesis_prime/login/srp
import genesis_prime/random.{type Random}
import genesis_prime/step.{type ConnectionId, type Input, type Peer, type Step}
import genesis_prime/store.{type Account}

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
  Connected(
    settings: Settings,
    connection: ConnectionId,
    peer: Peer,
    random: Random,
    /// Bytes of a request not yet whole, and whole requests not yet taken
    /// while an ask is out.
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

/// The rule's first state.
pub fn new(settings: Settings) -> State {
  todo as "the build follows the shape commit"
}

/// One input in, the new state and what the shell must do out.
pub fn step(
  state state: State,
  input input: Input(Nil, Answer),
) -> #(State, Step(Nil, Request)) {
  todo as "the build follows the shape commit"
}
