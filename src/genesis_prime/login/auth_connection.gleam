//// One auth-server connection as a process carries it out: the frames the
//// socket's owner has cut go in, the bytes to write come out. It runs the
//// session rule and carries out its effects in order: it redeems the game
//// token and issues the session key in the hand-offs, and logs a digest that
//// is not the expected one and why a connection ends. The frames are whole,
//// size-capped and rate-limited by the socket's owner before they get here.
////
//// The connection holds its own state and does no socket work: whoever owns
//// the socket writes the bytes it returns, first the hello that `new` gives,
//// and closes the socket when `close` is set.

import genesis_prime/connection/frame.{type Frame}
import genesis_prime/connection/socket_owner.{
  type Conversation, type Protocol, type Reaction, BytesRead, Conversation,
  FrameRead, Frames, Protocol, Reaction,
}
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/auth_session
import genesis_prime/login/handoff
import genesis_prime/login/random_source.{type Connection as Origin}
import genesis_prime/telemetry/log
import gleam/erlang/process.{type Name}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// What a connection asks the rest of the server for.
pub type Services {
  Services(
    /// Redeems a game token of 16 bytes, once.
    redeem_game_token: fn(BitArray) -> Result(Identity, Nil),
    /// A new session key for an identity, asked for by the given connection:
    /// 16 bytes.
    issue_session_key: fn(Identity, Option(Origin)) -> BitArray,
  )
}

/// The services of a running server: the game tokens and the session keys in
/// their hand-offs.
pub fn services(
  game_tokens game_tokens: Name(handoff.Message(Identity)),
  session_keys session_keys: Name(handoff.Message(Identity)),
) -> Services {
  Services(
    redeem_game_token: fn(key) {
      handoff.redeem(game_tokens, key) |> result.replace_error(Nil)
    },
    issue_session_key: fn(identity, origin) {
      handoff.issue(session_keys, identity, origin)
    },
  )
}

/// One connection's state.
pub opaque type Connection {
  Connection(
    services: Services,
    session: auth_session.Session,
    peer: Option(String),
    origin: Option(Origin),
    account: Option(Int),
  )
}

/// What a connection hands back: itself, the bytes to write to the socket in
/// order, and whether to close the socket after writing them.
pub type Output {
  Output(connection: Connection, send: List(BitArray), close: Bool)
}

/// A new connection and its first output: the hello. `peer` is the client's
/// address as text, which names it in the log until the login names an
/// account.
pub fn new(
  services services: Services,
  settings settings: auth_session.Settings,
  peer peer: Option(String),
) -> Output {
  let #(session, effects) = auth_session.start(settings)
  run(
    connection: Connection(
      services:,
      session:,
      peer:,
      origin: None,
      account: None,
    ),
    effects:,
    sent: [],
  )
}

/// Takes a frame the socket's owner cut.
pub fn receive(
  connection connection: Connection,
  frame frame: Frame,
) -> Output {
  let #(session, effects) = auth_session.receive(connection.session, frame)
  run(connection: Connection(..connection, session:), effects:, sent: [])
}

fn run(
  connection connection: Connection,
  effects effects: List(auth_session.Effect),
  sent sent: List(BitArray),
) -> Output {
  case effects {
    [] -> Output(connection:, send: list.reverse(sent), close: False)
    [effect, ..rest] ->
      case effect {
        auth_session.Send(bytes) ->
          run(connection:, effects: rest, sent: [bytes, ..sent])
        auth_session.RedeemGameToken(key) -> {
          let redeemed = connection.services.redeem_game_token(key)
          let #(session, more) =
            auth_session.token_redeemed(connection.session, redeemed)
          run(
            connection: Connection(..connection, session:),
            effects: list.append(more, rest),
            sent:,
          )
        }
        auth_session.IssueSessionKey(identity) -> {
          let key =
            connection.services.issue_session_key(identity, connection.origin)
          let #(session, more) =
            auth_session.session_key_issued(connection.session, key)
          log.info(
            who(Some(identity.id), connection.peer),
            "the auth login finished and the client was handed to the game server",
          )
          run(
            connection: Connection(
              ..connection,
              session:,
              account: Some(identity.id),
            ),
            effects: list.append(more, rest),
            sent:,
          )
        }
        auth_session.LogDigestMismatch(received:, expected:) -> {
          log.warning(
            who(connection.account, connection.peer),
            "the client's file digest is "
              <> int.to_string(received)
              <> ", not the expected "
              <> int.to_string(expected)
              <> "; the login goes on",
          )
          run(connection:, effects: rest, sent:)
        }
        auth_session.End(reason) -> {
          log.warning(
            who(connection.account, connection.peer),
            "the auth connection ended: " <> auth_session.describe(reason),
          )
          Output(connection:, send: list.reverse(sent), close: True)
        }
      }
  }
}

/// Who the connection's log lines are about: the account once the login has
/// named it, and the client's peer address.
fn who(account: Option(Int), peer: Option(String)) -> log.Who {
  log.Who(
    account:,
    actor: None,
    place: Some(log.Process("auth_connection")),
    message: None,
    peer:,
  )
}

/// What a listener serves for the auth login: frames, a connection of this
/// module for each client that connects, which writes the hello as it
/// connects.
pub fn protocol(
  services services: Services,
  settings settings: auth_session.Settings,
) -> Protocol {
  Protocol(mode: Frames, connect: fn(peer) {
    reaction(new(services:, settings:, peer:))
  })
}

fn conversation(connection: Connection) -> Conversation {
  Conversation(handle: fn(input) {
    case input {
      FrameRead(frame:) -> reaction(receive(connection:, frame:))
      BytesRead(..) ->
        Reaction(send: [], close: True, next: conversation(connection))
    }
  })
}

fn reaction(output: Output) -> Reaction {
  Reaction(
    send: output.send,
    close: output.close,
    next: conversation(output.connection),
  )
}
