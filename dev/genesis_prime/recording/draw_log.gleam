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

import genesis_prime/login/random_source.{type Draw, type RandomSource}
import gleam/erlang/process.{type Name, type Subject}
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

/// What the log process holds: the folder it writes into and the names of the
/// accounts it has written.
type State {
  State(folder: String, accounts_written: Set(String))
}

/// Writes the draw and its account, if the log has not written that account,
/// to the folder, and then answers.
fn handle(_state: State, message: Message) -> actor.Next(State, Message) {
  let Record(draw: _draw, bytes: _bytes, reply: _reply) = message
  panic as "shape only: built after the tests"
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
pub fn source(name _name: Name(Message)) -> RandomSource {
  panic as "shape only: built after the tests"
}
