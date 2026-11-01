//// Closes every listener to new sockets as the server starts to stop, before
//// any connection is told to stop. It is the last child of the server's tree,
//// so the supervisor stops it first: OTP stops a supervisor's children one at
//// a time in the reverse of the order they were started, and waits for each to
//// end.
////
//// ```
//// server supervisor                       closer                       Ranch
////   exit signal `shutdown` to the closer ─▶ Exited(parent)
////                                            for each listener, in order:
////                                              stop_accepting ────────▶ acceptors end,
////                                                                       listening socket closes
////                                              ◀── Ok | Error(Nil)
////                                            exits `shutdown`
////   next child: the game subtree, then login, world, Sessions, ...
////     each listener's connections get `Stopping` and drain
//// ```
////
//// - **Why a process.** A listener closes its own socket first in its own
////   stop, but the tree stops one listener after another, so the login
////   listeners would take new sockets while the game listener's connections
////   drain. The closer's turn comes before any listener's.
//// - **It decides nothing.** It holds no state: the parent's exit is its one
////   message, and what it does on it is the same every time.
//// - **A listener that cannot be closed** (`Error(Nil)`: no listener runs under
////   the name, as when its supervisor is restarting it) is logged as a
////   warning and the rest are closed; that listener is stopped in its turn
////   like any other.
//// - **The closer's deadline.** The supervisor gives it `shutdown_ms` and kills
////   it after; the drain then starts with some listeners still open, and each
////   listener's own stop closes its socket before its connections drain.
//// - **A restart** rebuilds nothing: the closer has no state, and its restart
////   while the tree runs closes nothing.
//// - **It exits `shutdown`, never `normal`:** a supervisor reports a permanent
////   child that exits `normal` while it stops as a failure.

import genesis_prime/connection/listener
import genesis_prime/step
import genesis_prime/step/runtime
import gleam/erlang/process.{type Name}
import gleam/list
import gleam/otp/supervision.{type ChildSpecification}

/// What the closer is started with.
pub type Settings {
  Settings(
    /// The listeners to close, by their names in Ranch, in the order they are
    /// closed.
    listeners: List(Name(Nil)),
    /// How long the closer has to close them all before it is killed.
    shutdown_ms: Int,
  )
}

/// The closer as a permanent child of the server's supervisor, added after
/// every listener's subtree so it is stopped before any of them. The process
/// traps exits, takes the parent's exit as its one message, calls `close_all`
/// and exits `shutdown`.
pub fn supervised(_settings: Settings) -> ChildSpecification(Nil) {
  panic as "built in the next commit"
}

/// Closes each listener to new sockets, in order, and says in the log what it
/// did: one info line when all closed, one warning with the count of those
/// that could not be.
pub fn close_all(listeners: List(Name(Nil))) -> Nil {
  let closed = list.map(listeners, listener.stop_accepting)
  case list.contains(closed, Error(Nil)) {
    False ->
      runtime.log(
        step.LogInfo,
        "every listener stopped accepting new connections",
        step.no_one,
      )
    True ->
      runtime.log(
        step.LogWarning,
        "a listener could not be closed to new connections",
        step.no_one,
      )
  }
}
