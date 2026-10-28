//// The server's supervision tree. Each part of the server is added as a
//// child, in the order it starts; children stop in the reverse order, so
//// what starts first stops last. Auth and game are each a subtree.
////
//// ```
//// server supervisor (one-for-one, 3 restarts in 10 s)
////  ├─ database pool: pog's pool, named                  permanent
////  ├─ store: factory supervisor, named                  permanent
////  │    └─ one worker per ask                            temporary
////  ├─ hand-off: service shell + hand-off rule, named    permanent
////  ├─ login supervisor (one-for-one, 3 restarts in 10 s)  permanent
////  │    ├─ STS listener (6600): a connection shell per client
////  │    └─ auth listener (23115): a connection shell per client
////  └─ game supervisor (one-for-one, 3 restarts in 10 s)   permanent
////       └─ game listener (24000): a connection shell per client
//// ```
////
//// The tree stops the game subtree, then the login subtree, before the
//// hand-off, the store and the pool they ask, so no connection is left asking
//// a process that has stopped. One directory, made once in `start` from the
//// store's and the hand-off's names, sends the asks of every listener's rules.
////
//// What a restart rebuilds, and what a client sees:
//// - **The pool** reconnects to Postgres. Asks to the store meanwhile answer
////   `Unavailable`.
//// - **The store** starts with no workers. Asks meanwhile get `NotRunning`;
////   an asker whose worker was running gets `EndedBeforeAnswer`.
//// - **The hand-off** starts with no keys. A client part-way through a login
////   is refused and logs in again; a client at the game server with a session
////   key the hand-off no longer holds is refused and disconnected, and logs in
////   again.
//// - **A listener** restarts with no connections: each client connected to it
////   is dropped and logs in again.
//// - **The login supervisor** restarts one listener at a time, so a fault in
////   the STS listener leaves the auth listener's clients connected. A listener
////   that fails three times in ten seconds ends the supervisor, which rebuilds
////   both listeners with no connections; the server supervisor counts that as
////   one of its own restarts.
//// - **The game supervisor** restarts its listener the same way: its clients
////   are dropped and play from the login again, and a fault in it leaves the
////   login's clients as they are. Its limit is the login's: three in ten
////   seconds, the same as the server's, so a listener that cannot stay up ends
////   the subtree after three tries, and the subtree ends the node after three.
////   A subtree's shutdown time is infinity, since its children are listeners
////   that each give their connections `connection_shutdown_ms`.

import genesis_prime/client_connection.{
  type Answer, type Request, AskHandOff, AskStore, FromHandOff, FromStore,
}
import genesis_prime/connection/listener.{Listener}
import genesis_prime/connection/shell as connection_shell
import genesis_prime/game/connection as game_connection
import genesis_prime/hand_off
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/service.{type Call, type Sent}
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{type Rule}
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
    /// How long a write may wait for a client's socket, on every listener.
    send_deadline_ms: Int,
    /// How long a connection has to stop once the server stops, on every
    /// listener.
    connection_shutdown_ms: Int,
    /// The login's two listeners.
    login: Login,
    /// The game server's listener.
    game: Served(game_connection.Settings),
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
  )
}

/// One listener: its name in Ranch, unique on the node and made once with
/// `process.new_name`, the port it listens on (0 for one the system picks),
/// the settings its rule is made with, and where each connection's inputs are
/// recorded, `None` unless the dev start turns recording on.
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
  let directory = directory(settings)
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
  |> supervisor.add(login(settings, directory))
  |> supervisor.add(game(settings, directory))
  |> supervisor.start
}

/// How a rule's ask reaches the process it names: to the store by its name
/// and to the hand-off by its name, each answer wrapped in the answer type of
/// every connection rule (`FromStore`, `FromHandOff`). Made once at start; it
/// holds the two names, not the settings.
fn directory(
  settings: Settings,
) -> fn(Request, fn(Answer) -> Nil) -> Result(Sent, Nil) {
  let store = settings.store
  let hand_off = settings.hand_off
  fn(request: Request, reply: fn(Answer) -> Nil) {
    case request {
      AskStore(request:) ->
        worker.ask(store, request, fn(answer) { reply(FromStore(answer)) })
      AskHandOff(message:) ->
        service.call(hand_off, message, fn(answer) {
          reply(FromHandOff(answer))
        })
    }
  }
}

/// The login subtree: the STS listener, then the auth listener, under a
/// supervisor of their own, a permanent child of the server's. It restarts one
/// listener at a time, three times in ten seconds.
fn login(
  settings: Settings,
  directory: fn(Request, fn(Answer) -> Nil) -> Result(Sent, Nil),
) -> supervision.ChildSpecification(supervisor.Supervisor) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.restart_tolerance(intensity: 3, period: 10)
  |> serve(
    settings:,
    served: settings.login.sts,
    rule: sts_connection.rule,
    directory:,
  )
  |> serve(
    settings:,
    served: settings.login.auth,
    rule: auth_connection.rule,
    directory:,
  )
  |> supervisor.supervised
}

/// The game subtree: the game listener under a supervisor of its own, a
/// permanent child of the server's, restarted three times in ten seconds.
fn game(
  settings: Settings,
  directory: fn(Request, fn(Answer) -> Nil) -> Result(Sent, Nil),
) -> supervision.ChildSpecification(supervisor.Supervisor) {
  supervisor.new(supervisor.OneForOne)
  |> supervisor.restart_tolerance(intensity: 3, period: 10)
  |> serve(
    settings:,
    served: settings.game,
    rule: game_connection.rule,
    directory:,
  )
  |> supervisor.supervised
}

/// Adds one listener, whose connections run the rule `rule` makes from the
/// listener's own settings, with the send and shutdown deadlines every
/// listener shares.
fn serve(
  tree: supervisor.Builder,
  settings settings: Settings,
  served served: Served(rule_settings),
  rule rule: fn(rule_settings) ->
    Rule(rule_settings, state, Nil, Answer, Nil, Request),
  directory directory: fn(Request, fn(Answer) -> Nil) -> Result(Sent, Nil),
) -> supervisor.Builder {
  supervisor.add(
    tree,
    listener.supervised(Listener(
      name: served.listener,
      port: served.port,
      connection: connection_shell.Settings(
        rule: rule(served.settings),
        send_deadline_ms: settings.send_deadline_ms,
        shutdown_ms: settings.connection_shutdown_ms,
        recorder: served.recorder,
        directory:,
      ),
    )),
  )
}
