//// The server's supervision tree. Each part of the server is added as a
//// child, in the order it starts; children stop in the reverse order, so
//// what starts first stops last.
////
//// ```
//// server supervisor (one-for-one, 3 restarts in 10 s)
////  ├─ database pool: pog's pool, named                  permanent
////  ├─ store: factory supervisor, named                  permanent
////  │    └─ one worker per ask                            temporary
////  ├─ hand-off: service shell + hand-off rule, named    permanent
////  ├─ STS listener (6600): a connection shell per client
////  └─ auth listener (23115): a connection shell per client
//// ```
////
//// What a restart rebuilds, and what a client sees:
//// - **The pool** reconnects to Postgres. Asks to the store meanwhile answer
////   `Unavailable`.
//// - **The store** starts with no workers. Asks meanwhile get `NotRunning`;
////   an asker whose worker was running gets `EndedBeforeAnswer`.
//// - **The hand-off** starts with no keys. A client part-way through a login
////   is refused and logs in again.
//// - **A listener** restarts with no connections: each client connected to it
////   is dropped and logs in again.

import genesis_prime/hand_off
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/service/shell.{type Call} as service_shell
import genesis_prime/step.{Rule}
import genesis_prime/store/worker.{type Job}
import gleam/erlang/process.{type Name}
import gleam/option.{type Option, None}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import pog

/// The names and settings the tree's children are started with, made once
/// at start.
pub type Settings {
  Settings(
    /// pog's pool, with its name and the database it connects to.
    pool: pog.Config,
    /// The store's factory supervisor.
    store: Name(factory_supervisor.Message(Job, Nil)),
    /// The hand-off service.
    hand_off: Name(Call(hand_off.Message, hand_off.Answer)),
    /// How long the hand-off has to stop.
    hand_off_shutdown_ms: Int,
    /// The login's two listeners.
    login: Login,
  )
}

/// The login's listeners: the STS server and the auth server, each a Ranch
/// listener whose connections run their rule in a connection shell
/// (genesis_prime/connection/listener). Both start after the hand-off and the
/// store they ask, so they stop first.
pub type Login {
  Login(
    /// The STS listener's name in Ranch, unique on the node.
    sts_listener: String,
    sts_port: Int,
    sts: sts_connection.Settings,
    /// The auth listener's name in Ranch, unique on the node.
    auth_listener: String,
    auth_port: Int,
    auth: auth_connection.Settings,
    /// How long a write may wait for a client's socket.
    send_deadline_ms: Int,
    /// How long a connection has to stop once the server stops.
    connection_shutdown_ms: Int,
    /// Where each connection's inputs are recorded; `None` unless the dev
    /// start turns recording on.
    sts_recorder: Option(Recorder(sts_connection.Settings)),
    auth_recorder: Option(Recorder(auth_connection.Settings)),
  )
}

/// Starts the tree. A child that fails three times in ten seconds does not
/// recover by restarting, so the tree gives up, the node stops, and the
/// host starts it again.
pub fn start(
  settings settings: Settings,
) -> actor.StartResult(supervisor.Supervisor) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.restart_tolerance(intensity: 3, period: 10)
  |> supervisor.add(
    pog.supervised(settings.pool)
    |> supervision.restart(supervision.Permanent),
  )
  |> supervisor.add(worker.supervised(
    name: settings.store,
    pool: pog.named_connection(settings.pool.pool_name),
  ))
  |> supervisor.add(
    service_shell.supervised(service_shell.Settings(
      rule: Rule(
        name: "genesis_prime/hand_off",
        settings: Nil,
        new: hand_off.new,
        step: hand_off.step,
      ),
      name: settings.hand_off,
      shutdown_ms: settings.hand_off_shutdown_ms,
      recorder: None,
    )),
  )
  |> add_login(settings)
  |> supervisor.start
}

/// Adds the STS listener, then the auth listener, each with the directory
/// that sends a login rule's asks to the store and the hand-off by their
/// names and wraps each answer (`login.FromStore`, `login.FromHandOff`).
fn add_login(
  tree: supervisor.Builder,
  settings: Settings,
) -> supervisor.Builder {
  todo as "the build follows the shape commit"
}
