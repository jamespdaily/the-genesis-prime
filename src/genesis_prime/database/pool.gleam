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
/// milliseconds, before it cancels the statement and rolls it back. A game
/// worker is killed at 5 seconds (`game/service.answer_deadline_ms`), and a
/// write that was reported failed must have committed nothing, so a request
/// waits at most `checkout_wait_bound_ms` for a connection, then runs at most
/// this long, and `margin_ms` is left before the worker's deadline: the three
/// add up to less than it. The statement's own timeout in `pog` is its default
/// of 5000 ms from the start of the call, which the functions squirrel
/// generates do not let a caller change; `pgo` closes the connection of a
/// statement that has run that long, after this limit has cancelled it. 4
/// seconds; no measurement chose it.
pub const statement_timeout_ms = 4000

/// The queue target of the pool, in milliseconds: how long a request may wait
/// for a connection before the pool counts the queue slow. `pgo`'s own
/// default; no measurement chose it.
const queue_target_ms = 50

/// The queue interval of the pool, in milliseconds: how often the pool looks
/// at its queue. 100 ms, a tenth of `pgo`'s default, so that `pgo` refuses a
/// request that cannot get a connection after at most `checkout_wait_bound_ms`;
/// no measurement chose it.
pub const queue_interval_ms = 100

/// How long a request waits in the pool's queue, at most, when every
/// connection of the pool is held and none is given back, in milliseconds:
/// three queue intervals. The pool polls its queue each interval; the first
/// poll after a request arrives records it, the second finds no progress and
/// notes the delay, and the third finds the delay above the target and refuses
/// every request that has waited more than twice the target (`pgo_pool.erl`,
/// `handle_info` for the poll, `timeout/4` and `drop_slow/3`). A pool of one
/// connection held by a transaction refused a request after 292 ms of the
/// 300. `pgo` offers no bound for a pool whose connections are given back and
/// taken again: its wait for a connection (`pgo_pool.erl`, `checkout_call/4`)
/// has no timeout, and the `timeout` of a query counts from the checkout.
pub const checkout_wait_bound_ms = 300

/// The time kept between the end of a statement's longest life and the moment
/// a worker is killed, in milliseconds: the wait for a connection, the
/// statement's limit and this add up to less than the worker's deadline, so a
/// worker that was killed never had a statement left running. 600 ms covers a
/// round trip to Postgres, the start of a worker and the commit; no
/// measurement chose it.
pub const margin_ms = 600

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
/// address, which `pog` must be told of.
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
  |> pog.queue_target(queue_target_ms)
  |> pog.queue_interval(queue_interval_ms)
  |> pog.ip_version(ip_version)
  |> pog.connection_parameter(
    name: "statement_timeout",
    value: int.to_string(statement_timeout_ms),
  )
}
