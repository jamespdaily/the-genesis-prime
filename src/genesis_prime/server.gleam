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

import genesis_prime/connection/listener.{Listener}
import genesis_prime/connection/shell as connection_shell
import genesis_prime/hand_off
import genesis_prime/login.{AskHandOff, AskStore, FromHandOff, FromStore}
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/service/shell.{type Call, type Sent} as service_shell
import genesis_prime/step.{type Input, type Step, Rule}
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
    sts: Served(sts_connection.Settings),
    auth: Served(auth_connection.Settings),
    /// How long a write may wait for a client's socket.
    send_deadline_ms: Int,
    /// How long a connection has to stop once the server stops.
    connection_shutdown_ms: Int,
  )
}

/// One login listener: its name in Ranch, unique on the node and made once
/// with `process.new_name`, the port it listens on (0 for one the system
/// picks), the settings its rule is made with, and where each connection's
/// inputs are recorded, `None` unless the dev start turns recording on.
pub type Served(settings) {
  Served(
    listener: Name(Nil),
    port: Int,
    settings: settings,
    recorder: Option(Recorder),
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
      rule: hand_off.rule(),
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
/// names and wraps each answer (`login.FromStore`, `login.FromHandOff`). The
/// directory holds the two names, not the settings.
fn add_login(
  tree: supervisor.Builder,
  settings: Settings,
) -> supervisor.Builder {
  let store = settings.store
  let hand_off = settings.hand_off
  let directory = fn(request: login.Request, reply: fn(login.Answer) -> Nil) {
    case request {
      AskStore(request:) ->
        worker.ask(store, request, fn(answer) { reply(FromStore(answer)) })
      AskHandOff(message:) ->
        service_shell.call(hand_off, message, fn(answer) {
          reply(FromHandOff(answer))
        })
    }
  }
  let login = settings.login
  tree
  |> serve(
    login:,
    served: login.sts,
    name: sts_connection.rule_name,
    new: sts_connection.new,
    step: sts_connection.step,
    directory:,
  )
  |> serve(
    login:,
    served: login.auth,
    name: auth_connection.rule_name,
    new: auth_connection.new,
    step: auth_connection.step,
    directory:,
  )
}

/// Adds one login listener, whose connections run the rule made from `name`,
/// the listener's own settings, `new` and `step`.
fn serve(
  tree: supervisor.Builder,
  login login: Login,
  served served: Served(settings),
  name name: String,
  new new: fn(settings) -> state,
  step step: fn(state, Input(Nil, login.Answer)) ->
    #(state, Step(Nil, login.Request)),
  directory directory: fn(login.Request, fn(login.Answer) -> Nil) ->
    Result(Sent, Nil),
) -> supervisor.Builder {
  supervisor.add(
    tree,
    listener.supervised(Listener(
      name: served.listener,
      port: served.port,
      connection: connection_shell.Settings(
        rule: Rule(name:, settings: served.settings, new:, step:),
        send_deadline_ms: login.send_deadline_ms,
        shutdown_ms: login.connection_shutdown_ms,
        recorder: served.recorder,
        directory:,
      ),
    )),
  )
}
