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
////  SIGTERM ───────────▶ init:stop
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
//// What a deadline or a death does, in that order:
//// - **The tree's children** each have their own shutdown time, and one that
////   passes is killed: a connection that has not ended in `connection_shutdown_ms`,
////   a service in its `shutdown_ms`, the closer in its own. A killed process
////   leaves no `End` in its recording. The subtrees and the root wait without a
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
//// - **SIGTERM before the ready line.** The tree stops as above, `main` is
////   still in `readiness.await` and is ended with the VM, no ready line is
////   printed, the status is 0, and every recording a process had open ends with
////   `End`.
//// - **The tree failing to start** (a port taken, a table missing) returns
////   `TreeNotStarted`; `main` crashes with it and the status is 1.
//// - **The tree ending while the node runs.** `await_tree_end` sees its monitor
////   fire with a reason other than `shutdown` and crashes `main`: the node
////   stops, in order, from the application's stop, with status 1.

import genesis_prime/server
import genesis_prime/step
import genesis_prime/step/runtime
import gleam/dynamic.{type Dynamic}
import gleam/erlang/application.{type StartType}
import gleam/erlang/process.{type Pid}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision
import gleam/result

/// Why `start_server` did not give a running tree.
pub type StartFailure {
  /// No application root is running: the node is stopping, or the server runs
  /// without its application.
  ApplicationNotRunning
  /// The root is running and the tree did not start, as the tree's start
  /// reported it.
  TreeNotStarted(reason: actor.StartError)
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
  |> result.map_error(fn(error) { dynamic.string(describe(error)) })
}

/// OTP's stop callback, run after the root and the tree under it have stopped:
/// logs the stop.
pub fn stop(_state: Dynamic) -> Nil {
  runtime.log(step.LogInfo, "the server stopped", step.no_one)
}

/// Starts the server's tree under the application's root with these settings
/// and gives the tree's pid. The root is found with `application:get_supervisor/1`
/// and the tree started with `supervisor:start_child/2`; no gleam_erlang or
/// gleam_otp function does either (the factory supervisor's handle cannot be
/// made from a pid, and only a name finds it, which `process.new_name` makes
/// fresh), so two Erlang functions in an Erlang module of this application
/// do, each with a typed result: `top_supervisor() -> Result(Pid, Nil)` and
/// `start_tree(Pid, Settings) -> Result(Pid, StartError)`.
pub fn start_server(
  settings _settings: server.Settings,
) -> Result(Pid, StartFailure) {
  panic as "built in the next commit"
}

/// Returns when the server's tree has ended with `shutdown`, the reason the
/// root gives it when the node stops, or `normal`; crashes with a message for
/// any other reason, so `gleam@@main` ends the node with status 1 and the host
/// starts it again. Takes the place of the sleep that kept the node alive.
pub fn await_tree_end(_tree: Pid) -> Nil {
  panic as "built in the next commit"
}

fn describe(error: actor.StartError) -> String {
  case error {
    actor.InitTimeout -> "the root supervisor did not start in time"
    actor.InitFailed(reason) -> reason
    actor.InitExited(_) -> "the root supervisor exited while it started"
  }
}
