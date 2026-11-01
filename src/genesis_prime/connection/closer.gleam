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
//// - **The order of the listeners** is the order the tree gives them: the
////   login's two, then the game server's, so a game listener that refuses new
////   sockets says that every listener does.
//// - **It decides nothing.** It holds no state but the listeners' names: the
////   parent's exit is its one message, and what it does on it is the same
////   every time.
//// - **A listener that cannot be closed** (`Error(Nil)`: no listener runs under
////   the name, as when its supervisor is restarting it) is logged as a
////   warning and the rest are closed; that listener is stopped in its turn
////   like any other.
//// - **The closer's deadline** is 5 s, after which the supervisor kills it:
////   the drain then starts with some listeners still open, and each listener's
////   own stop closes its socket before its connections drain.
//// - **A restart** rebuilds nothing, and a restart while the tree runs closes
////   nothing.
//// - **It exits `shutdown`, never `normal`:** a supervisor reports a permanent
////   child that exits `normal` while it stops as a failure.

import genesis_prime/connection/listener
import genesis_prime/step
import genesis_prime/step/runtime.{Shutdown}
import gleam/erlang/process.{type Name, type Pid}
import gleam/list
import gleam/otp/actor
import gleam/otp/supervision.{type ChildSpecification}

/// How long the closer has to close every listener before it is killed.
const shutdown_ms = 5000

/// What reaches the closer: an exit signal it traps.
type Mail {
  Exited(exit: process.ExitMessage)
}

/// What the closer holds: the supervisor that started it, whose exit is its
/// signal to act, and the listeners to close.
type Closing {
  Closing(parent: Pid, listeners: List(Name(Nil)))
}

/// The closer as a permanent child of the server's supervisor, to close the
/// listeners named, in order. It is added after every listener's subtree so it
/// is stopped before any of them.
pub fn supervised(listeners: List(Name(Nil))) -> ChildSpecification(Nil) {
  supervision.worker(fn() {
    // The supervisor runs the start function, so its own pid is the parent.
    start(Closing(parent: process.self(), listeners:))
  })
  |> supervision.restart(supervision.Permanent)
  |> supervision.timeout(ms: shutdown_ms)
}

fn start(closing: Closing) -> actor.StartResult(Nil) {
  actor.new_with_initialiser(5000, fn(_subject) {
    process.trap_exits(True)
    Ok(
      actor.initialised(closing)
      |> actor.selecting(
        process.new_selector() |> process.select_trapped_exits(Exited),
      )
      |> actor.returning(Nil),
    )
  })
  |> actor.on_message(handle)
  |> actor.start
}

/// On the parent's exit: closes the listeners and exits `shutdown`. The exit of
/// any other process is not the closer's.
fn handle(closing: Closing, mail: Mail) -> actor.Next(Closing, Mail) {
  let Exited(exit:) = mail
  case exit.pid == closing.parent {
    True -> {
      close_all(closing.listeners)
      runtime.exit_now(Shutdown)
    }
    False -> actor.continue(closing)
  }
}

/// Closes each listener to new sockets, in order, and says in the log what it
/// did: one info line when all closed, one warning when one could not be.
fn close_all(listeners: List(Name(Nil))) -> Nil {
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
