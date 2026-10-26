//// A TCP relay in front of a Postgres server, so a test can make the database
//// "away" and "back" without stopping Postgres. A relay is made refusing: its
//// port has nothing listening, so a connection to it is refused as it is
//// when the server is down. `forward` starts it listening on that same port and
//// passing every connection through to the target, as it is when the server
//// is back. A relay belongs to the process that makes it, and stops with it.

/// The Postgres server a relay passes connections to. `host` is a TCP host
/// name or address; an address with a colon is IPv6.
pub type Target {
  Target(host: String, port: Int)
}

/// A relay's address, which is the loopback of the target's address family,
/// and where it passes connections to. Its port is chosen when it is made.
pub type Relay {
  Relay(host: String, port: Int, target: Target)
}

/// Why a relay could not be made or started.
pub type Failure {
  /// The relay's port was taken by another process between being chosen and
  /// being listened on.
  AddressInUse
  /// Listening failed for another reason, named by the operating system's
  /// error code.
  NotListening(code: String)
}

/// A relay for `target` that refuses connections: a free port on the loopback
/// is chosen and nothing listens on it.
pub fn refusing(to target: Target) -> Result(Relay, Failure) {
  todo as "choose a free port and leave it unlistened"
}

/// Starts `relay` listening on its port and passing each connection through to
/// its target, until the process that called this ends.
pub fn forward(relay: Relay) -> Result(Nil, Failure) {
  todo as "listen on the relay's port and pass connections through"
}
