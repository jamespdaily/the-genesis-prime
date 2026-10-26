//// The random source of a server that records a session: each draw is strong
//// random bytes from the operating system, as the released server's are, and
//// is written to the session folder with the connection that made it before
//// the caller gets the bytes, together with the account row its login used.
////
//// The log is one process that owns the folder's `draws` and `accounts`
//// files, so the writes of connections that draw at the same time do not
//// mix, and one connection's draws are written in the order it made them:
//// a connection draws one at a time and waits for the answer. The process is
//// a child of the supervisor that starts it, and a restart rebuilds it from
//// the folder name alone; it then writes again an account it had written, and
//// `session.read` keeps one row for each name.

import genesis_prime/login/account.{type Account}
import genesis_prime/login/guid
import genesis_prime/login/random_source.{type Draw, type RandomSource}
import genesis_prime/recording/session.{UsedAccount}
import gleam/crypto
import gleam/erlang/process.{type Name, type Subject}
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/otp/supervision
import gleam/set.{type Set}

/// The messages the log process receives.
pub opaque type Message {
  Record(draw: Draw, bytes: BitArray, reply: Subject(Nil))
}

/// How long the top of the tree waits for the log process to stop before it is
/// killed, in milliseconds. Every write has reached the file before the process
/// answers, so it holds nothing that must be saved.
const shutdown_ms = 1000

/// How long a caller waits for the log to write a draw, in milliseconds. A
/// write is one append to a file, so an answer later than this means the
/// process is gone, which ends the caller.
const call_ms = 5000

/// What the log process holds: the folder it writes into and the names of the
/// accounts it has written.
type State {
  State(folder: String, accounts_written: Set(String))
}

/// Writes the draw and its account, if the log has not written that account,
/// to the folder, and then answers. A file that cannot be written ends the
/// process, so no draw is used that is not on disk: the caller's wait for the
/// answer then ends the caller.
fn handle(state: State, message: Message) -> actor.Next(State, Message) {
  let Record(draw:, bytes:, reply:) = message
  let assert Ok(Nil) =
    session.append_draw(
      folder: state.folder,
      draw: session.Draw(connection: draw.connection, bytes:),
    )
    as "a draw was not written to the session folder"
  let state = case draw.account {
    Some(account) -> write_account(state, account)
    None -> state
  }
  process.send(reply, Nil)
  actor.continue(state)
}

/// Writes the account's row unless the log has written it already.
fn write_account(state: State, account: Account) -> State {
  case set.contains(state.accounts_written, account.name) {
    True -> state
    False -> {
      let assert Ok(Nil) =
        session.append_account(
          folder: state.folder,
          account: UsedAccount(
            name: account.name,
            user_id: guid.to_text(account.user_id),
            salt: account.salt,
            verifier: account.verifier,
          ),
        )
        as "an account was not written to the session folder"
      State(
        ..state,
        accounts_written: set.insert(state.accounts_written, account.name),
      )
    }
  }
}

/// The log process as a child of a supervisor, registered under `name`, writing
/// into `folder`, which exists.
pub fn supervised(
  name name: Name(Message),
  folder folder: String,
) -> supervision.ChildSpecification(Subject(Message)) {
  supervision.worker(fn() {
    actor.new(State(folder:, accounts_written: set.new()))
    |> actor.on_message(handle)
    |> actor.named(name)
    |> actor.start
  })
  |> supervision.timeout(ms: shutdown_ms)
}

/// The source of the log process registered under `name`, for the settings of
/// the login.
pub fn source(name name: Name(Message)) -> RandomSource {
  random_source.Supplied(draw: fn(draw) {
    let bytes = crypto.strong_random_bytes(draw.count)
    actor.call(
      process.named_subject(name),
      waiting: call_ms,
      sending: fn(reply) { Record(draw:, bytes:, reply:) },
    )
    bytes
  })
}
