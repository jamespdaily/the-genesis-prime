//// The server as an OTP application (`application_start_module` in
//// gleam.toml), so the host's SIGTERM stops it through OTP, in order. The
//// application owns one process, a root supervisor with no child; `main`,
//// which runs once it has started and alone holds the settings, starts the
//// server's tree (genesis_prime/server) under the root.
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
////                                                      the order they started, one at a time
////                                              ◀─ tree ended ─────┘  ─▶ main's monitor
////                                                                       fires `shutdown`
////                         stop/1 logs the stop, then                    main returns
////                         waits for main to end ◀───────────────────────┘
////                         halts with status 0
//// ```
////
//// - The root is a factory supervisor: the tree starts later (`supervisor:start_child/2`).
//// - The tree is `temporary`: the root never restarts it; a fatal end crashes `main` (`end_of`).
//// - stop/1 returns only once `main` has ended (`register_program`), so `init` cannot kill it.
//// - `main` calls nothing on the application master while it stops: the master waits on stop/1.
//// - Orderly or fatal is the node's state, not the reason: `init:stop` sets `stopping` first.
//// - The stop's only deadlines are the children's own: `shutdown_timeout` stays unset (infinity).
//// - `start_server` finds the root by name (`register_root`) and makes the tree's only monitor.
//// - One monitor, made at start, serves the readiness ask and the final wait.

import genesis_prime/server
import genesis_prime/step
import genesis_prime/step/runtime
import gleam/bool
import gleam/dynamic.{type Dynamic}
import gleam/erlang/application.{type StartType}
import gleam/erlang/process.{type Monitor, type Pid}
import gleam/option.{type Option, None, Some}
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
  /// No application root is running and the node is not stopping: the server
  /// runs without its application.
  ApplicationNotRunning
  /// No application root is running because the node is stopping.
  NodeStopping
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

/// OTP's start callback: starts the root supervisor, which has no child,
/// registers it under the name `start_server` finds it by, and gives its pid.
/// The tree is started later by `start_server`.
pub fn start(
  start_type _start_type: StartType,
  start_argument _start_argument: Dynamic,
) -> Result(Pid, Dynamic) {
  factory_supervisor.supervisor_child(server.start)
  |> factory_supervisor.restart_strategy(supervision.Temporary)
  // A temporary child is never restarted, so this limit is never reached.
  |> factory_supervisor.restart_tolerance(intensity: 1, period: 5)
  |> factory_supervisor.start
  |> result.map(fn(started) {
    register_root(started.pid)
    started.pid
  })
  |> result.map_error(fn(error) {
    dynamic.string(
      "the root supervisor " <> runtime.describe_start_error(error),
    )
  })
}

/// OTP's stop callback, run after the root and the tree under it have stopped:
/// logs the stop, and returns once the node's program has ended
/// (`register_program`).
pub fn stop(_state: Dynamic) -> Nil {
  runtime.log(step.LogInfo, "the server stopped", step.no_one)
  await_program_end()
}

/// Makes the calling process the node's program: the process that
/// `genesis_prime@@main:run` runs `main` in. The application's stop does not
/// return until the program has ended, so the VM does not go on to close the
/// node's output and kill its processes while the program is still taking the
/// tree's end. `main` calls it before anything else.
@external(erlang, "genesis_prime_application_ffi", "register_program")
pub fn register_program() -> Nil

@external(erlang, "genesis_prime_application_ffi", "await_program_end")
fn await_program_end() -> Nil

/// Starts the server's tree under the application's root with these settings,
/// and monitors it. Each fails with the reason it did not run.
pub fn start_server(
  settings settings: server.Settings,
) -> Result(Tree, StartFailure) {
  start_tree(settings)
  |> result.map(fn(pid) { Tree(pid:, monitor: process.monitor(pid)) })
  |> result.map_error(fn(failure) {
    case failure {
      ApplicationNotRunning ->
        case node_stopping() {
          True -> NodeStopping
          False -> ApplicationNotRunning
        }
      NodeStopping | TreeNotStarted(..) -> failure
    }
  })
}

/// Starts the server's tree as `start_server` does and gives it, or gives
/// nothing when the node is stopping, which `main` takes as its orderly end
/// (it logs it). Crashes with the reason when the tree did not start while the
/// node runs.
pub fn start_server_unless_stopping(
  settings settings: server.Settings,
) -> Option(Tree) {
  case start_server(settings:) {
    Ok(tree) -> Some(tree)
    Error(NodeStopping) -> {
      runtime.log(
        step.LogInfo,
        "the node stopped before the server's tree started",
        step.no_one,
      )
      None
    }
    Error(ApplicationNotRunning) ->
      panic as "the supervision tree did not start: no application root runs"
    Error(TreeNotStarted(reason:)) ->
      panic as {
        "the supervision tree did not start: "
        <> runtime.describe_start_error(reason)
      }
  }
}

/// Starts the tree under the root registered by `register_root`, with
/// `supervisor:start_child/2`; no gleam_erlang or gleam_otp function does it
/// (genesis_prime_application_ffi says why).
@external(erlang, "genesis_prime_application_ffi", "start_tree")
fn start_tree(settings: server.Settings) -> Result(Pid, StartFailure)

/// Registers the root under the name `start_tree` finds it by.
@external(erlang, "genesis_prime_application_ffi", "register_root")
fn register_root(root: Pid) -> Nil

/// Whether the node has begun to stop: `init:get_status/0` says `stopping`.
@external(erlang, "genesis_prime_application_ffi", "node_stopping")
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
