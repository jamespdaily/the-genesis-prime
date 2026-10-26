//// The rule of one STS connection: the state it is in and the request that
//// arrives go in, the new state and the effects come out, in the order the
//// connection carries them out. It follows the client's login in order
//// (records StsConnLib64.MT.dll!0x180006fb0, 0x18000a350, 0x1800043d0,
//// 0x180004950, 0x180004ac0): LoginStart, KeyData, LoginFinish,
//// ListMyAccounts, RequestGameToken. A request out of that order, for another
//// account than the one logging in, or after a refusal ends the connection.
//// The password never arrives: the rule holds the account's verifier and checks
//// the client's SRP proof against it.

import genesis_prime/login/account.{type Account, type Identity}
import genesis_prime/login/srp
import genesis_prime/login/sts_message.{type Incoming}

/// The error code of a refusal for an account that does not exist and for a
/// wrong secret alike, so a client learns nothing about which accounts there
/// are. The client's LoginStart and LoginFinish handlers map 10, 11 and 3002
/// to the same NC platform event, 16 (HandleLoginStartResult 0x1400b2f20,
/// HandleLoginFinishResult 0x1400b3070).
pub const invalid_login_code = 3002

/// Where a connection is in the login.
pub opaque type Session {
  Session(state: State)
}

type State {
  Connected
  FindingAccount(sequence: Int, name: String)
  AwaitingProof(sequence: Int, account: Account, challenge: srp.Challenge)
  Proven(account: Account)
  LoggedIn(account: Account)
  Listed(account: Account)
  IssuingToken(account: Account, sequence: Int)
  Finished
}

/// What the connection carries out, in order.
pub type Effect {
  /// Send these bytes.
  Send(bytes: BitArray)
  /// From the next byte, RC4 under this session key covers the connection in
  /// both directions (StsConnLib64.MT.dll!0x18000a350).
  StartCipher(key: BitArray)
  /// Find the account of this name, then answer with `account_found`.
  FindAccount(name: String)
  /// Issue a game token for this identity, then answer with
  /// `game_token_issued`.
  IssueGameToken(identity: Identity)
  /// End the connection, and log why.
  End(reason: EndReason)
}

/// Why the rule ends a connection.
pub type EndReason {
  /// A request that does not belong at this point of the login.
  OutOfOrder(command: String)
  /// LoginStart named an account that does not exist.
  UnknownAccount(name: String)
  /// The SRP exchange failed for this account: the password is wrong or the
  /// client's key data is not valid.
  ExchangeFailed(name: String, error: srp.SrpError)
  /// A later request names another UserId, game code or alias than the login
  /// does.
  WrongIdentity(command: String)
}

/// A connection that has received nothing.
pub fn new() -> Session {
  todo as "a new session"
}

/// The effects of a request that arrived, and the session after it.
pub fn receive(
  session session: Session,
  incoming incoming: Incoming,
) -> #(Session, List(Effect)) {
  todo as "the rule for a request"
}

/// The effects of the account lookup the rule asked for: the account or
/// none, and `secret`, 32 random bytes for the server's SRP value.
pub fn account_found(
  session session: Session,
  account account: Result(Account, Nil),
  secret secret: BitArray,
) -> #(Session, List(Effect)) {
  todo as "the rule for the lookup"
}

/// The effects of the game token the rule asked for: its 16 bytes.
pub fn game_token_issued(
  session session: Session,
  token token: BitArray,
) -> #(Session, List(Effect)) {
  todo as "the rule for the token"
}

/// A sentence that says why the connection ended, for the log.
pub fn describe(reason reason: EndReason) -> String {
  todo as "the reason in words"
}
