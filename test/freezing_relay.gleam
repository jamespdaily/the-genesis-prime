//// A TCP relay in front of a Postgres server that can freeze one connection
//// without closing it, so a test can make a database stop answering in the
//// middle of a command while Postgres, and every new connection through the
//// relay, keep working. The relay passes every connection through to the
//// target, reading the client's messages whole (a type byte, a length of 4
//// bytes and the body, after the startup packet) however the bytes are
//// chunked. The first connection to meet the freeze it was made for is
//// frozen: nothing more goes either way and neither socket is closed, until
//// the client closes its own, which closes the target's. What a relay starts
//// is linked to the process that starts it, and stops with it.

import gleam/erlang/process
import gleam/option.{type Option}
import pog
import template_database

/// A host and port of the Postgres server a relay passes connections to. An
/// address with a colon is IPv6.
pub type Target {
  Target(host: String, port: Int)
}

/// What the relay counts, kept by the relay's processes.
pub type Counters

/// When a relay freezes a connection, by the text of a statement the client
/// parses (compared without regard to case, as a part of the text).
pub type Freeze {
  /// At the Parse of a statement with this text, which is not passed on: the
  /// target never hears of the statement.
  Before(statement: String)
  /// At the Sync that ends the exchange of a statement with this text, which
  /// is passed on whole: the target carries the statement out and its reply
  /// never reaches the client.
  After(statement: String)
}

/// A running relay: the loopback address and port to connect to. Its port is
/// chosen when it starts.
pub type Relay {
  Relay(host: String, port: Int, counters: Counters)
}

/// Why a relay could not start: listening failed, named by the operating
/// system's error code.
pub type Failure {
  NotListening(code: String)
}

/// Starts a relay for `target` that freezes the first connection to meet
/// `freeze`.
pub fn start(
  to target: Target,
  freezing freeze: Freeze,
) -> Result(Relay, Failure) {
  start_ffi(target.host, target.port, freeze)
}

@external(erlang, "freezing_relay_ffi", "start")
fn start_ffi(host: String, port: Int, freeze: Freeze) -> Result(Relay, Failure)

/// How many connections the relay has accepted.
pub fn opened(relay: Relay) -> Int {
  opened_ffi(relay.counters)
}

/// The number, counted from 1 in the order the relay accepted them, of the
/// connection that was frozen, or `None` while none has been.
pub fn frozen_connection(relay: Relay) -> Option(Int) {
  frozen_connection_ffi(relay.counters)
}

@external(erlang, "freezing_relay_ffi", "opened")
fn opened_ffi(counters: Counters) -> Int

@external(erlang, "freezing_relay_ffi", "frozen_connection")
fn frozen_connection_ffi(counters: Counters) -> Option(Int)

/// A relay for the test's database that freezes the first connection to meet
/// `freeze`, and a pool of one connection to the database through it.
pub fn start_pool(
  for database: template_database.Database,
  freezing freeze: Freeze,
) -> #(pog.Connection, Relay) {
  let assert Ok(relay) =
    start(
      to: Target(host: database.settings.tcp_host, port: database.settings.port),
      freezing: freeze,
    )
    as "the freezing relay started"
  let pool_name = process.new_name("pool_through_the_freezing_relay")
  let assert Ok(_) =
    template_database.config(for: database, pool_name:, pool_size: 1)
    |> pog.host(relay.host)
    |> pog.port(relay.port)
    |> pog.start
    as "the pool of one connection through the relay started"
  #(pog.named_connection(pool_name), relay)
}
