//// A node of its own that serves the server's tree on a database of the test's
//// own, as `gleam run` starts the server: the application first, then this
//// module's `main`, which starts the tree under the application's root and
//// serves it (`genesis_prime.serve`). The tests start it, send it SIGTERM or
//// let it fail, and read what it printed and how it ended.
////
//// Each mode is one way the node is made to run:
//// - `Serving`: the database answers, so the node prints the ready line.
//// - `UnreachableDatabase`: the pool's port has no database, so the readiness
////   ask keeps asking.
//// - `LateDatabase`: the database the node is given does not exist yet and the
////   readiness ask gives up after a second, so the node logs the database as
////   unreachable and keeps asking until the test makes the database.
//// - `SlowStop`: Sessions is suspended, so a stop takes its shutdown time, and
////   the probe answers as soon as the node is stopping, so the answer comes
////   while the tree is still ending.
//// - `GivesUp`: the hand-off is killed once more than the tree's restart
////   intensity allows, so the tree ends with `shutdown` while the node runs.
////
//// The node records the connections of its STS listener on the wire into the
//// folder it is given, and in `Serving` mode holds one connection open to it,
//// so there is a connection to record.

import ask_support
import database_support
import envoy
import genesis_prime
import genesis_prime/application
import genesis_prime/connection/listener
import genesis_prime/migration.{Recorded}
import genesis_prime/readiness
import genesis_prime/server
import genesis_prime/service.{type Sent, ToWorker}
import genesis_prime/step/runtime
import genesis_prime/store/worker.{type Probed, Reached}
import gleam/bool
import gleam/erlang/process
import gleam/io
import gleam/option.{Some}
import login_support
import mug
import pog
import recording_support
import simplifile

/// A node the calling process started, as the test sees it. Every function that
/// takes one is called by that process.
pub type Node

/// How the node is made to run.
pub type Mode {
  Serving
  UnreachableDatabase
  LateDatabase
  SlowStop
  GivesUp
}

/// Starts the node in `mode`, recording Sessions into `folder`, on the
/// migrated database `database`, and gives the node. The node ends when the
/// calling process does.
pub fn start(
  mode mode: Mode,
  folder folder: String,
  database database: String,
) -> Node {
  start_node("serving_node", [
    #("SERVING_MODE", mode_name(mode)),
    #("SERVING_FOLDER", folder),
    #("SERVING_DATABASE", database),
  ])
}

/// Whether the node printed `text` within `within_ms` milliseconds.
@external(erlang, "serving_node_ffi", "await_output")
pub fn await_output(node: Node, text: String, within_ms: Int) -> Bool

/// Everything the node has printed that the caller has read.
@external(erlang, "serving_node_ffi", "output")
pub fn output(node: Node) -> String

/// Sends the node SIGTERM, as the host does.
@external(erlang, "serving_node_ffi", "terminate")
pub fn terminate(node: Node) -> Nil

/// The node's exit status, once it has ended within `within_ms` milliseconds.
@external(erlang, "serving_node_ffi", "await_exit")
pub fn await_exit(node: Node, within_ms: Int) -> Result(Int, Nil)

@external(erlang, "serving_node_ffi", "start")
fn start_node(module: String, environment: List(#(String, String))) -> Node

fn mode_name(mode: Mode) -> String {
  case mode {
    Serving -> "serving"
    UnreachableDatabase -> "unreachable_database"
    LateDatabase -> "late_database"
    SlowStop -> "slow_stop"
    GivesUp -> "gives_up"
  }
}

fn mode_of(name: String) -> Mode {
  case name {
    "serving" -> Serving
    "unreachable_database" -> UnreachableDatabase
    "late_database" -> LateDatabase
    "slow_stop" -> SlowStop
    "gives_up" -> GivesUp
    _ -> panic as "SERVING_MODE names no mode"
  }
}

fn variable(name: String) -> String {
  let assert Ok(value) = envoy.get(name) as "the node's variable is set"
  value
}

/// What the node runs.
pub fn main() -> Nil {
  let mode = mode_of(variable("SERVING_MODE"))
  let pool =
    database_support.config(
      for: database_support.settings(),
      database: variable("SERVING_DATABASE"),
      pool_name: process.new_name("pool"),
      pool_size: 2,
    )
  let pool = case mode {
    UnreachableDatabase -> pog.port(pool, 1)
    Serving | LateDatabase | SlowStop | GivesUp -> pool
  }
  let base = login_support.settings(pool:)
  let settings =
    server.Settings(
      ..base,
      login: server.Login(
        ..base.login,
        sts: server.Served(
          ..base.login.sts,
          wire_recorder: Some(
            recording_support.wire_recorder(folder: variable("SERVING_FOLDER")),
          ),
        ),
      ),
      sessions_shutdown_ms: 3000,
    )
  runtime.show_info_lines()
  let assert Ok(tree) = application.start_server(settings:)
    as "the tree started under the application"
  io.println("the tree started")
  let ready =
    readiness.Settings(
      within_ms: case mode {
        LateDatabase -> 1000
        Serving | UnreachableDatabase | SlowStop | GivesUp -> 60_000
      },
      attempt_ms: 2000,
      pause_ms: 100,
    )
  let probe = fn(reply) { worker.probe(store: settings.store, reply:) }
  case mode {
    Serving -> hold_a_connection(settings)
    UnreachableDatabase | LateDatabase | SlowStop | GivesUp -> Nil
  }
  case mode {
    Serving | UnreachableDatabase | LateDatabase ->
      genesis_prime.serve(
        tree:,
        settings:,
        tables: 0,
        ready:,
        probe:,
        migrations: genesis_prime.load_migrations(),
        say: io.println,
      )
    SlowStop -> {
      let assert Ok(sessions) = process.named(settings.sessions)
        as "Sessions runs"
      let assert True = ask_support.suspend_process(sessions)
        as "Sessions was suspended"
      genesis_prime.serve(
        tree:,
        settings:,
        tables: 0,
        ready:,
        probe: probe_after_stop,
        migrations: [],
        say: io.println,
      )
    }
    GivesUp -> {
      let _killer = process.spawn(fn() { give_up(settings) })
      genesis_prime.serve(
        tree:,
        settings:,
        tables: 0,
        ready:,
        probe:,
        migrations: genesis_prime.load_migrations(),
        say: io.println,
      )
    }
  }
}

/// Connects to the STS listener and holds the connection open, and says so
/// once its recording is on disk: the recording's file exists once the
/// shell has taken the socket, so the node says it only after that.
fn hold_a_connection(settings: server.Settings) -> Nil {
  let assert Ok(port) = listener.port(settings.login.sts.listener)
    as "the STS listener has a port"
  let _client =
    process.spawn(fn() {
      let assert Ok(_socket) =
        mug.new("127.0.0.1", port:)
        |> mug.ip_version_preference(mug.Ipv4Only)
        |> mug.timeout(5000)
        |> mug.connect
        as "the node connected to its STS listener"
      await_recording(variable("SERVING_FOLDER"), 3000)
      io.println("a connection is recorded")
      process.sleep_forever()
    })
  Nil
}

/// Waits until the folder holds a recording, asking every 10 ms up to `times`
/// times.
fn await_recording(folder: String, times: Int) -> Nil {
  let assert Ok(names) = simplifile.read_directory(folder)
    as "the recording folder reads"
  case names, times > 0 {
    [_, ..], _ -> Nil
    [], True -> {
      process.sleep(10)
      await_recording(folder, times - 1)
    }
    [], False -> panic as "the connection was never recorded"
  }
}

/// Kills the hand-off one more time than the tree restarts in its period, each
/// time it has been restarted, so the tree gives up.
fn give_up(settings: server.Settings) -> Nil {
  kill_hand_off(settings, restarts_allowed + 1)
}

/// The restarts the server's tree allows in ten seconds.
const restarts_allowed = 3

fn kill_hand_off(settings: server.Settings, times: Int) -> Nil {
  let assert Ok(pid) = process.named(settings.hand_off) as "the hand-off runs"
  process.kill(pid)
  case times > 1 {
    True -> {
      let _restarted =
        ask_support.await_new_pid(
          name: settings.hand_off,
          not: pid,
          within_ms: 5000,
        )
      kill_hand_off(settings, times - 1)
    }
    False -> Nil
  }
}

/// A probe that answers `Reached`, with no migrations recorded (the node's
/// `serve` holds none), once the node is stopping, so the answer comes after
/// the stop has begun.
fn probe_after_stop(reply: fn(Probed) -> Nil) -> Result(Sent, Nil) {
  io.println("probing")
  let pid =
    // Not linked to main: the readiness ask ends this worker when it gives up
    // on the attempt, and that exit must not reach main.
    process.spawn_unlinked(fn() {
      await_stop()
      reply(Reached(recorded: Recorded([])))
    })
  Ok(ToWorker(pid:))
}

fn await_stop() -> Nil {
  use <- bool.guard(when: application.node_stopping(), return: Nil)
  process.sleep(1)
  await_stop()
}
