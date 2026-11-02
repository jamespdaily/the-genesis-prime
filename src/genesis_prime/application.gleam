//// The server as an OTP application (`application_start_module` in
//// gleam.toml), so the host's SIGTERM stops it through OTP, in order. The
//// application owns one process, a root supervisor with no child. `main`, which
//// runs after the application has started and alone holds the settings (the
//// loaded tables, the dev start's recorders, the environment), starts the
//// server's tree (genesis_prime/server) under the root.
////
//// ```
//// application genesis_prime (started by `gleam run`, `gleam run -m` and the
////   shipment's `genesis_prime@@main:run`, before any `main`)
////  └─ root: factory supervisor, one child kind        start/2
////       └─ server tree (genesis_prime/server)         temporary, started by main
//// ```
////
//// The root is a factory supervisor because its one child starts later, from
//// an argument: `supervisor:start_child` on it runs the tree's start with the
//// settings. The server tree is `temporary`: the root never restarts it. A tree
//// that gave up (a child failed three times in ten seconds) ends, `main` sees
//// it end and ends the node with status 1, and the host starts it again;
//// restarting the tree from the root would hide that.
////
//// From SIGTERM to exit:
////
//// ```
//// host                   VM                  root          tree          main
////  SIGTERM ───────────▶ init:stop (status: stopping)
////                         stops the applications in the reverse of the order
////                         they started: genesis_prime, then ranch, pgo, ...
////                         exit `shutdown` ───▶ root
////                                              exit `shutdown` ─▶ tree
////                                                      stops its children in the reverse of
////                                                      the order they started, one at a time:
////                                                      closer (every listener stops accepting),
////                                                      game, login, world, Sessions, hand-off,
////                                                      store, pool
////                                              ◀─ tree ended ─────┘  ─▶ main's monitor
////                                                                       fires `shutdown`
////                         stop/1 logs the stop                          main returns
////                         halts with status 0
//// ```
////
//// **How `main` tells an orderly end from a fatal one.** A tree that exceeds
//// its restart intensity also ends with `shutdown`, so the reason says nothing.
//// The node's own state does: `init:stop` sets the status to `stopping` before
//// it stops any application, so a tree that ends while the node is stopping
//// ended in order, and a tree that ends while it is not, whatever the reason,
//// is fatal (`ending`).
////
//// What a deadline or a death does, in that order:
//// - **The tree's children** each have their own shutdown time, and one that
////   passes is killed: a connection that has not ended in `connection_shutdown_ms`,
////   a service in its `shutdown_ms`, the closer in its own. A killed process
////   leaves no closing line in its recording. The subtrees and the root wait without a
////   limit, the children's limits being what bounds them. No timer of the VM's
////   ends the stop: the kernel's `shutdown_timeout`, which no file here sets,
////   is infinity.
//// - **The pool dying during the stop.** The pool is the tree's first child, so it
////   stops last. A pool that dies earlier is not restarted, since the tree is
////   stopping; a draining connection's ask meanwhile answers `Unavailable`.
//// - **SIGTERM before `main` has started the tree.** The root has stopped or is
////   stopping, and `start_server` fails with `ApplicationNotRunning`; `main`
////   crashes with that message while the VM, already stopping, halts with
////   status 0: the first `init:stop` sets the status.
//// - **SIGTERM while the tree starts.** The root handles the stop after its
////   start call returns, then stops the tree it started, in order.
//// - **SIGTERM before the ready line.** The tree stops as above, the readiness
////   ask sees its end, no ready line is printed, the status is 0, and every
////   recording a connection had open ends with its closing line.
//// - **The tree failing to start** (a port taken, a table missing) returns
////   `TreeNotStarted`; `main` crashes with it and the status is 1.
//// - **The tree ending while the node runs** crashes `main` (`end_of`): the node
////   stops, in order, from the application's stop, with status 1.
////
//// The monitor on the tree is made as `start_server` returns it, and the same
//// monitor goes to the readiness ask and to the final wait, so the tree's exit
//// reason reaches whichever sees the end first, and a monitor made after the
//// tree had ended would give `noproc` instead.

import genesis_prime/server
import genesis_prime/step
import genesis_prime/step/runtime
import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/erlang/application.{type StartType}
import gleam/erlang/process.{type Monitor, type Pid}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision
import gleam/result

/// The server's tree, started under the application's root, and the monitor
/// `main` holds on it.
pub type Tree {
  Tree(pid: Pid, monitor: Monitor)
}

/// Why `start_server` did not give a running tree.
pub type StartFailure {
  /// No application root is running: the node is stopping, or the server runs
  /// without its application.
  ApplicationNotRunning
  /// The root is running and the tree did not start, as the tree's start
  /// reported it.
  TreeNotStarted(reason: actor.StartError)
}

/// How the end of the server's tree is to be taken.
pub type Ending {
  /// The node is stopping, so the tree ended in order.
  Orderly
  /// The node is not stopping, so the tree ended on its own, whatever the
  /// reason: it gave up, or it was killed.
  Fatal(reason: process.ExitReason)
}

/// OTP's start callback: starts the root supervisor, which has no child, and
/// gives its pid. The tree is started later by `start_server`.
pub fn start(
  start_type _start_type: StartType,
  start_argument _start_argument: Dynamic,
) -> Result(Pid, Dynamic) {
  factory_supervisor.supervisor_child(server.start)
  |> factory_supervisor.restart_strategy(supervision.Temporary)
  // A temporary child is never restarted, so this limit is never reached.
  |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
  |> factory_supervisor.start
  |> result.map(fn(started) { started.pid })
  |> result.map_error(fn(error) {
    dynamic.string(
      "the root supervisor " <> runtime.describe_start_error(error),
    )
  })
}

/// OTP's stop callback, run after the root and the tree under it have stopped:
/// logs the stop.
pub fn stop(_state: Dynamic) -> Nil {
  runtime.log(step.LogInfo, "the server stopped", step.no_one)
}

/// Starts the server's tree under the application's root with these settings,
/// and monitors it. Each fails with the reason it did not run.
pub fn start_server(
  settings settings: server.Settings,
) -> Result(Tree, StartFailure) {
  start_tree(settings)
  |> result.map(fn(pid) { Tree(pid:, monitor: process.monitor(pid)) })
}

/// Finds the root with `application:get_supervisor/1` and starts the tree
/// under it with `supervisor:start_child/2`; no gleam_erlang or gleam_otp
/// function does either (application_ffi says why).
@external(erlang, "application_ffi", "start_tree")
fn start_tree(settings: server.Settings) -> Result(Pid, StartFailure)

/// Whether the node has begun to stop: `init:get_status/0` says `stopping`.
@external(erlang, "application_ffi", "node_stopping")
pub fn node_stopping() -> Bool

/// Whether the server can be said to serve: its tree is running and the node is
/// not stopping. A stop can begin right after the answer, between the check and
/// whatever the caller does with it.
pub fn serving(tree: Tree) -> Bool {
  process.is_alive(tree.pid) && !node_stopping()
}

/// How the end of the tree is taken, by the node's state: orderly while the
/// node is stopping, and fatal otherwise, whatever the reason (a tree past its
/// restart intensity ends with `shutdown` too).
pub fn ending(
  reason reason: process.ExitReason,
  node_stopping node_stopping: Bool,
) -> Ending {
  use <- bool.guard(when: node_stopping, return: Orderly)
  Fatal(reason:)
}

/// Takes the end of the tree: returns when it is orderly, and crashes with a
/// message when it is fatal, so `gleam@@main` ends the node with status 1 and
/// the host starts it again.
pub fn end_of(reason: process.ExitReason) -> Nil {
  case ending(reason:, node_stopping: node_stopping()) {
    Orderly -> Nil
    Fatal(reason:) ->
      panic as {
        "the supervision tree ended while the node runs: "
        <> runtime.describe_exit(reason)
      }
  }
}

/// Waits for the tree to end, on the monitor made when it started, and takes
/// its end (`end_of`). Keeps the node alive in the place of a sleep.
pub fn await_tree_end(tree: Tree) -> Nil {
  let down =
    process.new_selector()
    |> process.select_specific_monitor(tree.monitor, fn(down) { down })
    |> process.selector_receive_forever
  end_of(runtime.down_reason(down))
}
