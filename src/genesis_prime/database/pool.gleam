//// The pool of connections to Postgres that every part of the server saves
//// and loads through: its settings and the child the top supervisor starts.

import gleam/erlang/process.{type Name}
import gleam/option.{type Option}
import gleam/otp/supervision
import pog

/// How many connections a pool holds when nothing has measured a better
/// number: `pog`'s own default.
const default_pool_size = 10

/// What a pool needs to start. `name` is the name the pool registers and
/// that its users find it by, made once by whoever starts the tree, so two
/// pools in one node never share it. `host` is a TCP host name or address
/// (an address with a colon is read as IPv6) and `password` is `None` for an
/// account that logs in without one.
pub type Settings {
  Settings(
    name: Name(pog.Message),
    host: String,
    port: Int,
    database: String,
    user: String,
    password: Option(String),
    pool_size: Int,
  )
}

/// Why the settings could not be read from the environment.
pub type EnvironmentError {
  /// A variable the pool needs is not set.
  Missing(variable: String)
  /// A variable that must be a whole number is not one.
  NotANumber(variable: String, value: String)
}

/// Reads the pool's settings from the variables Postgres's own tools read,
/// each through `get`. PGHOST is the server's TCP host, PGPORT its port,
/// PGUSER the account and PGDATABASE the database; each must be set. PGPASSWORD
/// is the account's password and is `None` when unset. The pool holds
/// `default_pool_size` connections. `name` is the pool's name.
pub fn from_environment(
  name name: Name(pog.Message),
  get get: fn(String) -> Result(String, Nil),
) -> Result(Settings, EnvironmentError) {
  todo as "read the pool's settings from the environment"
}

/// A sentence that says which variable is wrong and how, for the message the
/// server stops with when the pool's settings cannot be read.
pub fn describe(error: EnvironmentError) -> String {
  case error {
    Missing(variable:) ->
      variable <> " is not set; the database pool needs it to start"
    NotANumber(variable:, value:) ->
      variable
      <> " is "
      <> value
      <> ", which is not a whole number; the database pool needs a number"
  }
}

/// How long the top supervisor waits for the pool to stop before it is
/// killed, in milliseconds. The pool is not a supervisor but a server that
/// stops its connections as it ends; `pgo`'s own supervisor gives the same
/// process this long (`pgo_sup.erl`, the `pgo_pool` child's `shutdown`).
const shutdown_ms = 1000

/// The pool as a child of a supervisor: restarted whenever it ends, given
/// `shutdown_ms` to stop. It starts without waiting for Postgres; its
/// connections open in the background and are retried until they succeed.
pub fn supervised(
  settings: Settings,
) -> supervision.ChildSpecification(pog.Connection) {
  todo as "the pool as a supervised worker with its shutdown time"
}

/// The connection the pool's users query through, found by the pool's name.
pub fn connection(settings: Settings) -> pog.Connection {
  todo as "the connection named by the settings"
}
