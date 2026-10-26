//// The pool of connections to Postgres that every part of the server saves
//// and loads through: its settings and the child the top supervisor starts.

import gleam/erlang/process.{type Name}
import gleam/int
import gleam/option.{type Option}
import gleam/otp/supervision
import gleam/result
import gleam/string
import pog

/// How many connections a pool holds when nothing has measured a better
/// number: `pog`'s own default.
const default_pool_size = 10

/// How long Postgres lets one statement of the pool's connections run, in
/// milliseconds, before it cancels the statement and rolls it back. A
/// statement that is cancelled leaves its connection open and its error says
/// why (query_canceled, 57014). The transaction as a whole is bounded by
/// `transaction_timeout_ms`, above this. A statement inside a transaction has no
/// timeout of the client's, so this setting is the only limit on it. A statement
/// outside a transaction has `pog`'s default client timeout of 5000 ms from the
/// start of the call, which the functions squirrel generates do not let a
/// caller change, and this limit is below it. 4 seconds; no measurement chose
/// it.
pub const statement_timeout_ms = 4000

/// How long Postgres lets one transaction of the pool's connections run, in
/// milliseconds, from its start to its commit, before it ends the session
/// and rolls the transaction back (PostgreSQL 17 and later,
/// `transaction_timeout`; the setting also covers a statement that is not in a
/// transaction). `statement_timeout_ms` bounds each statement, not the sum of a
/// transaction's statements and its commit, so this is what bounds a write whose
/// statement waits and then commits. 4.5 seconds, half a second above
/// `statement_timeout_ms`, which PostgreSQL's documentation requires for the
/// statement's limit to count; no measurement chose it.
pub const transaction_timeout_ms = 4500

/// The time given, after a transaction's limit, for the answer of a worker that
/// holds a connection to arrive, in milliseconds: it covers the round trip to
/// Postgres that carries the end of the session or the rollback, and the
/// worker's reply. 600 ms; no measurement chose it.
pub const margin_ms = 600

/// How long the asker of a worker that holds a connection waits for its
/// answer, in milliseconds, counted from the moment the worker says it holds
/// it: the transaction's limit and the margin, the longest a write can take
/// from the moment it is sent. The asker's deadline does not apply from then
/// on, because Postgres ends the transaction within this time, so the worker's
/// answer is the truth about the write. An answer that has not come by then
/// leaves the write's outcome unknown.
pub fn holding_wait_ms() -> Int {
  transaction_timeout_ms + margin_ms
}

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
  use host <- result.try(required(get, "PGHOST"))
  use port_text <- result.try(required(get, "PGPORT"))
  use port <- result.try(
    int.parse(port_text)
    |> result.replace_error(NotANumber(variable: "PGPORT", value: port_text)),
  )
  use user <- result.try(required(get, "PGUSER"))
  use database <- result.try(required(get, "PGDATABASE"))
  Ok(Settings(
    name:,
    host:,
    port:,
    database:,
    user:,
    password: option.from_result(get("PGPASSWORD")),
    pool_size: default_pool_size,
  ))
}

fn required(
  get: fn(String) -> Result(String, Nil),
  variable: String,
) -> Result(String, EnvironmentError) {
  get(variable) |> result.replace_error(Missing(variable:))
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
  supervision.worker(fn() { pog.start(config(settings)) })
  |> supervision.timeout(ms: shutdown_ms)
}

/// The connection the pool's users query through, found by the pool's name.
pub fn connection(settings: Settings) -> pog.Connection {
  pog.named_connection(settings.name)
}

/// `pog`'s configuration for the settings. A host with a colon is an IPv6
/// address, which `pog` must be told of. The pool's queue target (50 ms) and
/// queue interval (1000 ms) are `pog`'s defaults: a write that has no connection
/// is killed by its asker before it sends anything, so the queue's refusals are
/// not what keeps a failed write from having committed.
fn config(settings: Settings) -> pog.Config {
  let ip_version = case string.contains(settings.host, ":") {
    True -> pog.Ipv6
    False -> pog.Ipv4
  }
  pog.default_config(settings.name)
  |> pog.host(settings.host)
  |> pog.port(settings.port)
  |> pog.database(settings.database)
  |> pog.user(settings.user)
  |> pog.password(settings.password)
  |> pog.pool_size(settings.pool_size)
  |> pog.ip_version(ip_version)
  |> pog.connection_parameter(
    name: "statement_timeout",
    value: int.to_string(statement_timeout_ms),
  )
  |> pog.connection_parameter(
    name: "transaction_timeout",
    value: int.to_string(transaction_timeout_ms),
  )
}
