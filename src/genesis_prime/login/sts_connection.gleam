//// One STS connection as a process carries it out: the bytes the socket
//// reads go in, the bytes to write come out. It cuts the bytes into requests,
//// decodes each, runs the session rule and carries out the rule's effects in
//// order: it asks the account store and the hand-off for what the rule asks,
//// puts RC4 on the connection when the rule says so, and logs why a
//// connection ends. After the SRP exchange every byte in both directions goes
//// through the RC4 streams, one for each direction (records
//// StsConnLib64.MT.dll!0x18000a350 and 0x18003a7d0).
////
//// The connection holds its own state and does no socket work: whoever owns
//// the socket gives it the bytes read, writes the bytes it returns and closes
//// the socket when `close` is set.

import genesis_prime/login/account.{type Account, type Identity}
import genesis_prime/login/account_store
import genesis_prime/login/handoff
import genesis_prime/login/log
import genesis_prime/login/rc4
import genesis_prime/login/sts_message
import genesis_prime/login/sts_session
import genesis_prime/login/sts_wire
import gleam/bit_array
import gleam/bool
import gleam/crypto
import gleam/erlang/process.{type Name}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import pog

/// What a connection asks the rest of the server for.
pub type Services {
  Services(
    /// The account of a lower-case name, or none.
    find_account: fn(String) -> Result(Account, Nil),
    /// A new game token for an identity: 16 bytes.
    issue_game_token: fn(Identity) -> BitArray,
    /// 32 random bytes for the server's SRP value.
    draw_secret: fn() -> BitArray,
  )
}

/// The services of a running server: accounts in Postgres through
/// `connection`, game tokens in the hand-off `game_tokens`, and random bytes
/// from the operating system. A database that fails ends the connection's
/// process, which its supervisor does not restart.
pub fn services(
  connection connection: pog.Connection,
  game_tokens game_tokens: Name(handoff.Message(Identity)),
) -> Services {
  Services(
    find_account: fn(name) {
      let assert Ok(found) = account_store.find(connection, name)
        as "the database answered the account lookup"
      found
    },
    issue_game_token: fn(identity) { handoff.issue(game_tokens, identity) },
    draw_secret: fn() { crypto.strong_random_bytes(32) },
  )
}

/// Why a connection ends: what the bytes or the message got wrong, or the
/// rule's own reason.
type EndReason {
  /// The bytes are not a request.
  BadBytes(sts_wire.WireError)
  /// The request is not one of the login's.
  BadMessage(sts_message.MessageError)
  /// The rule ended the login.
  LoginEnded(sts_session.EndReason)
  /// Bytes arrived after the request that starts RC4, which the client
  /// sends only after it has read the reply.
  BytesAfterTheCipher
  /// This OTP has no RC4, so the session key cannot be used.
  NoCipher
}

/// One connection's state.
pub opaque type Connection {
  Connection(
    services: Services,
    session: sts_session.Session,
    received: BitArray,
    receiving: Option(rc4.Stream),
    sending: Option(rc4.Stream),
    account_name: String,
    ended: Bool,
  )
}

/// What a connection hands back: itself, the bytes to write to the socket in
/// order, and whether to close the socket after writing them.
pub type Output {
  Output(connection: Connection, send: List(BitArray), close: Bool)
}

/// A connection that has received nothing.
pub fn new(services services: Services) -> Connection {
  Connection(
    services:,
    session: sts_session.new(),
    received: <<>>,
    receiving: None,
    sending: None,
    account_name: "unknown",
    ended: False,
  )
}

/// Takes the bytes the socket read.
pub fn receive(
  connection connection: Connection,
  bytes bytes: BitArray,
) -> Output {
  use <- bool.guard(
    when: connection.ended,
    return: Output(connection:, send: [], close: True),
  )
  let plain = case connection.receiving {
    Some(stream) -> rc4.crypt(stream, bytes)
    None -> bytes
  }
  case sts_wire.decode(<<connection.received:bits, plain:bits>>) {
    Error(error) -> end(connection:, reason: BadBytes(error), sent: [])
    Ok(#(requests, leftover)) ->
      run_requests(
        connection: Connection(..connection, received: leftover),
        requests:,
        sent: [],
      )
  }
}

fn run_requests(
  connection connection: Connection,
  requests requests: List(sts_wire.Request),
  sent sent: List(BitArray),
) -> Output {
  case requests {
    [] -> Output(connection:, send: list.reverse(sent), close: False)
    [request, ..rest] ->
      case sts_message.decode(request) {
        Error(error) -> end(connection:, reason: BadMessage(error), sent:)
        Ok(incoming) -> {
          let #(session, effects) =
            sts_session.receive(connection.session, incoming)
          let step =
            run_effects(
              connection: Connection(..connection, session:),
              effects:,
              sent:,
              pending: rest,
            )
          case step {
            Continue(connection:, sent:) ->
              run_requests(connection:, requests: rest, sent:)
            Finished(output) -> output
          }
        }
      }
  }
}

/// What carrying out a rule's effects leaves: the connection and what was
/// sent before, to go on with the next request, or the final output.
type Step {
  Continue(connection: Connection, sent: List(BitArray))
  Finished(output: Output)
}

fn run_effects(
  connection connection: Connection,
  effects effects: List(sts_session.Effect),
  sent sent: List(BitArray),
  pending pending: List(sts_wire.Request),
) -> Step {
  case effects {
    [] -> Continue(connection:, sent:)
    [effect, ..rest] ->
      case effect {
        sts_session.Send(bytes) -> {
          let #(sending, written) = write(connection.sending, bytes)
          run_effects(
            connection: Connection(..connection, sending:),
            effects: rest,
            sent: [written, ..sent],
            pending:,
          )
        }
        sts_session.StartCipher(key) ->
          start_cipher(connection:, key:, rest:, sent:, pending:)
        sts_session.FindAccount(name) -> {
          let found = connection.services.find_account(name)
          let #(session, more) =
            sts_session.account_found(
              connection.session,
              found,
              connection.services.draw_secret(),
            )
          run_effects(
            connection: Connection(..connection, session:, account_name: name),
            effects: list.append(more, rest),
            sent:,
            pending:,
          )
        }
        sts_session.IssueGameToken(identity) -> {
          let token = connection.services.issue_game_token(identity)
          let #(session, more) =
            sts_session.game_token_issued(connection.session, token)
          log.info(
            "the STS login finished and a game token was issued",
            identity.name,
          )
          run_effects(
            connection: Connection(..connection, session:),
            effects: list.append(more, rest),
            sent:,
            pending:,
          )
        }
        sts_session.End(reason) ->
          Finished(end(connection:, reason: LoginEnded(reason), sent:))
      }
  }
}

/// Puts RC4 on the connection, as long as no byte is waiting that the client
/// ciphered before it was on.
fn start_cipher(
  connection connection: Connection,
  key key: BitArray,
  rest rest: List(sts_session.Effect),
  sent sent: List(BitArray),
  pending pending: List(sts_wire.Request),
) -> Step {
  let bytes_waiting =
    !list.is_empty(pending) || bit_array.byte_size(connection.received) > 0
  use <- bool.guard(
    when: bytes_waiting,
    return: Finished(end(connection:, reason: BytesAfterTheCipher, sent:)),
  )
  case start_streams(key) {
    Error(rc4.Unsupported) | Error(rc4.EmptyKey) ->
      Finished(end(connection:, reason: NoCipher, sent:))
    Ok(#(receiving, sending)) ->
      run_effects(
        connection: Connection(
          ..connection,
          receiving: Some(receiving),
          sending: Some(sending),
        ),
        effects: rest,
        sent:,
        pending:,
      )
  }
}

fn start_streams(
  key: BitArray,
) -> Result(#(rc4.Stream, rc4.Stream), rc4.StartError) {
  use receiving <- result.try(rc4.start(key))
  use sending <- result.map(rc4.start(key))
  #(receiving, sending)
}

/// Ciphers the bytes to write when RC4 is on.
fn write(
  stream: Option(rc4.Stream),
  bytes: BitArray,
) -> #(Option(rc4.Stream), BitArray) {
  case stream {
    Some(running) -> #(stream, rc4.crypt(running, bytes))
    None -> #(stream, bytes)
  }
}

/// Logs why the connection ends and closes it after what was sent.
fn end(
  connection connection: Connection,
  reason reason: EndReason,
  sent sent: List(BitArray),
) -> Output {
  log.warning(
    "the STS connection ended: " <> describe(reason),
    connection.account_name,
  )
  Output(
    connection: Connection(..connection, ended: True),
    send: list.reverse(sent),
    close: True,
  )
}

/// A sentence that says why the connection ended, for the log.
fn describe(reason: EndReason) -> String {
  case reason {
    BadBytes(error) -> sts_wire.describe(error)
    BadMessage(error) -> sts_message.describe(error)
    LoginEnded(reason) -> sts_session.describe(reason)
    BytesAfterTheCipher ->
      "bytes arrived after the request that starts the cipher"
    NoCipher -> "this server has no RC4 cipher"
  }
}
