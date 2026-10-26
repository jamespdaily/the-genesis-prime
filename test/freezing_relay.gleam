//// A TCP relay in front of a Postgres server that can freeze one connection
//// without closing it, so a test can make a database stop answering in the
//// middle of a write while Postgres, and every new connection through the
//// relay, keep working. The relay passes every connection through to the
//// target. The first connection whose bytes to the target contain the
//// statement it was made for is passed those bytes and then frozen: nothing
//// more goes either way and neither socket is closed, until the client closes
//// its own, which closes the target's. What a relay starts is linked to the
//// process that starts it, and stops with it.

import gleam/option.{type Option}

/// A host and port of the Postgres server a relay passes connections to. An
/// address with a colon is IPv6.
pub type Target {
  Target(host: String, port: Int)
}

/// What the relay counts, kept by the relay's processes.
pub type Counters

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

/// Starts a relay for `target` that freezes the first connection to send a
/// message containing `statement`, whatever the case of its letters, after
/// passing that message on.
pub fn start(
  to target: Target,
  freezing_on statement: String,
) -> Result(Relay, Failure) {
  start_ffi(target.host, target.port, statement)
}

@external(erlang, "freezing_relay_ffi", "start")
fn start_ffi(
  host: String,
  port: Int,
  statement: String,
) -> Result(Relay, Failure)

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
