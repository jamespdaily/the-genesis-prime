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
import genesis_prime/login/guid
import genesis_prime/login/srp
import genesis_prime/login/sts_message.{
  type Incoming, GameAccount, KeyData, ListMyAccounts, LoginFinish, LoginStart,
  RequestGameToken, Transaction,
}
import gleam/bool
import gleam/int
import gleam/list

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
  AwaitingProof(account: Account, challenge: srp.Challenge)
  Proven(account: Account)
  LoggedIn(account: Account)
  Listed(account: Account)
  IssuingToken(account: Account, sequence: Int)
  Finished
  Ended
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
  Session(state: Connected)
}

/// The effects of a request that arrived, and the session after it.
pub fn receive(
  session session: Session,
  incoming incoming: Incoming,
) -> #(Session, List(Effect)) {
  case incoming {
    sts_message.ConnectionOpened(_) | sts_message.Ping -> #(session, [])
    Transaction(sequence:, request:) ->
      case session.state {
        Ended -> #(session, [])
        Connected ->
          case request {
            LoginStart(login_name:, ..) -> start_login(sequence, login_name)
            KeyData(..)
            | LoginFinish
            | ListMyAccounts(..)
            | RequestGameToken(..) -> out_of_order(request)
          }
        AwaitingProof(account:, challenge:) ->
          case request {
            KeyData(bytes:) ->
              prove(account:, challenge:, sequence:, key_data: bytes)
            LoginStart(..)
            | LoginFinish
            | ListMyAccounts(..)
            | RequestGameToken(..) -> out_of_order(request)
          }
        Proven(account:) ->
          case request {
            LoginFinish -> #(Session(state: LoggedIn(account:)), [
              send(sts_message.LoginFinished(
                sequence:,
                user_id: guid.to_text(account.user_id),
                user_name: account.name,
              )),
            ])
            LoginStart(..)
            | KeyData(..)
            | ListMyAccounts(..)
            | RequestGameToken(..) -> out_of_order(request)
          }
        LoggedIn(account:) ->
          case request {
            ListMyAccounts(user_id:, game_code:) ->
              list_accounts(account:, sequence:, user_id:, game_code:)
            LoginStart(..) | KeyData(..) | LoginFinish | RequestGameToken(..) ->
              out_of_order(request)
          }
        Listed(account:) ->
          case request {
            RequestGameToken(user_id:, game_code:, account_alias:) ->
              request_token(
                account:,
                sequence:,
                user_id:,
                game_code:,
                account_alias:,
              )
            LoginStart(..) | KeyData(..) | LoginFinish | ListMyAccounts(..) ->
              out_of_order(request)
          }
        FindingAccount(..) | IssuingToken(..) | Finished ->
          out_of_order(request)
      }
  }
}

fn out_of_order(request: sts_message.Transaction) -> #(Session, List(Effect)) {
  end(OutOfOrder(command_name(request)), [])
}

fn list_accounts(
  account account: Account,
  sequence sequence: Int,
  user_id user_id: String,
  game_code game_code: String,
) -> #(Session, List(Effect)) {
  use <- bool.guard(
    when: !{
      is_the_login(account, user_id) && game_code == sts_message.game_code
    },
    return: end(WrongIdentity("ListMyAccounts"), []),
  )
  #(Session(state: Listed(account:)), [
    send(
      sts_message.GameAccounts(sequence:, accounts: [
        GameAccount(
          alias: account.name,
          created: account.created,
          game_account_id: guid.to_text(account.user_id),
        ),
      ]),
    ),
  ])
}

fn request_token(
  account account: Account,
  sequence sequence: Int,
  user_id user_id: String,
  game_code game_code: String,
  account_alias account_alias: String,
) -> #(Session, List(Effect)) {
  use <- bool.guard(
    when: !{
      is_the_login(account, user_id)
      && game_code == sts_message.game_code
      && account_alias == account.name
    },
    return: end(WrongIdentity("RequestGameToken"), []),
  )
  #(Session(state: IssuingToken(account:, sequence:)), [
    IssueGameToken(identity_of(account)),
  ])
}

fn start_login(sequence: Int, login_name: String) -> #(Session, List(Effect)) {
  case account.lower_case_name(login_name) {
    Ok(name) -> #(Session(state: FindingAccount(sequence:, name:)), [
      FindAccount(name),
    ])
    Error(account.NameEmpty) | Error(account.NameTooLong(_)) ->
      end(UnknownAccount(login_name), [refusal(sequence)])
  }
}

fn prove(
  account account: Account,
  challenge challenge: srp.Challenge,
  sequence sequence: Int,
  key_data key_data: BitArray,
) -> #(Session, List(Effect)) {
  case srp.prove(challenge, key_data) {
    Ok(srp.Proven(session_key:, server_key_data:)) -> #(
      Session(state: Proven(account:)),
      [
        send(sts_message.KeyDataAnswer(sequence:, key_data: server_key_data)),
        StartCipher(session_key),
      ],
    )
    Error(error) ->
      end(ExchangeFailed(account.name, error), [refusal(sequence)])
  }
}

fn identity_of(found: Account) -> Identity {
  account.identity(found)
}

/// Whether the text names the account's UserId.
fn is_the_login(account: Account, user_id: String) -> Bool {
  guid.from_text(user_id) == Ok(account.user_id)
}

fn send(answer: sts_message.Answer) -> Effect {
  Send(sts_message.encode(answer))
}

fn refusal(sequence: Int) -> Effect {
  send(sts_message.Refused(sequence:, code: invalid_login_code))
}

/// Ends the connection after the effects given: the session takes no more.
fn end(reason: EndReason, before: List(Effect)) -> #(Session, List(Effect)) {
  #(Session(state: Ended), list.append(before, [End(reason)]))
}

fn command_name(request: sts_message.Transaction) -> String {
  case request {
    LoginStart(..) -> "LoginStart"
    KeyData(..) -> "KeyData"
    LoginFinish -> "LoginFinish"
    ListMyAccounts(..) -> "ListMyAccounts"
    RequestGameToken(..) -> "RequestGameToken"
  }
}

/// The effects of the account lookup the rule asked for: the account or
/// none, and `secret`, 32 random bytes for the server's SRP value.
pub fn account_found(
  session session: Session,
  account account: Result(Account, Nil),
  secret secret: BitArray,
) -> #(Session, List(Effect)) {
  case session.state, account {
    FindingAccount(sequence:, name:), Error(Nil) ->
      end(UnknownAccount(name), [refusal(sequence)])
    FindingAccount(sequence:, name:), Ok(found) ->
      case
        srp.challenge(
          name: found.name,
          salt: found.salt,
          verifier: found.verifier,
          secret:,
        )
      {
        Ok(#(challenge, key_data)) -> #(
          Session(state: AwaitingProof(account: found, challenge:)),
          [send(sts_message.KeyDataAnswer(sequence:, key_data:))],
        )
        Error(error) -> end(ExchangeFailed(name, error), [refusal(sequence)])
      }
    Ended, _ -> #(session, [])
    Connected, _
    | AwaitingProof(..), _
    | Proven(..), _
    | LoggedIn(..), _
    | Listed(..), _
    | IssuingToken(..), _
    | Finished, _
    -> end(OutOfOrder("an account lookup nobody asked for"), [])
  }
}

/// The effects of the game token the rule asked for: its 16 bytes.
pub fn game_token_issued(
  session session: Session,
  token token: BitArray,
) -> #(Session, List(Effect)) {
  case session.state {
    IssuingToken(sequence:, ..) -> {
      let assert Ok(token_guid) = guid.from_wire(token)
        as "a hand-off issues keys of 16 bytes"
      #(Session(state: Finished), [
        send(sts_message.GameToken(sequence:, token: guid.to_text(token_guid))),
      ])
    }
    Ended -> #(session, [])
    Connected
    | FindingAccount(..)
    | AwaitingProof(..)
    | Proven(..)
    | LoggedIn(..)
    | Listed(..)
    | Finished -> end(OutOfOrder("a game token nobody asked for"), [])
  }
}

/// A sentence that says why the connection ended, for the log.
pub fn describe(reason reason: EndReason) -> String {
  case reason {
    OutOfOrder(command:) ->
      command <> " does not belong at this point of the login"
    UnknownAccount(name:) -> "there is no account named " <> name
    ExchangeFailed(name:, error:) ->
      "the SRP exchange for " <> name <> " failed: " <> srp_error(error)
    WrongIdentity(command:) ->
      command <> " names another UserId, game code or alias than the login"
  }
}

fn srp_error(error: srp.SrpError) -> String {
  case error {
    srp.KeyDataMalformed -> "the key data is malformed"
    srp.ClientValueRejected -> "the client's value is not a valid A"
    srp.ScramblerZero -> "the scrambling value is zero"
    srp.ProofRefused -> "the proof does not match, the password is wrong"
    srp.SecretNotThirtyTwoBytes(bytes:) ->
      "the server's secret is " <> int.to_string(bytes) <> " bytes"
  }
}
