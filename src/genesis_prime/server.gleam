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
////  ├─ sessions: service shell + sessions rule, named    permanent
////  ├─ world supervisor (rest_for_one, 3 restarts in 10 s)  permanent
////  │    ├─ Maps: the registry actor, named              permanent
////  │    └─ map supervisor: factory supervisor, named     permanent
////  │         └─ one map per MapId: service shell + map rule, unnamed  temporary
////  ├─ login supervisor (one-for-one, 3 restarts in 10 s)  permanent
////  │    ├─ STS listener (6600): a connection shell per client
////  │    └─ auth listener (23115): a connection shell per client
////  └─ game supervisor (rest_for_one, 3 restarts in 10 s)  permanent
////       ├─ registry: OTP's pg scope, named                permanent
////       └─ game listener (24000): a connection shell per client, each
////            joined to the registry under its ConnectionId
//// ```
////
//// The tree stops the game subtree, then the login subtree, then the world
//// subtree, before Sessions, the hand-off, the store and the pool they ask,
//// so no connection is left asking a process that has stopped. A map's ask
//// goes through Maps (genesis_prime/world_map/maps), which finds the map or
//// starts it; a map's address is found the same way, never started, for a
//// watch. One directory, made once in `start` from
//// the store's, the hand-off's and Sessions' names, sends the asks of every
//// listener's rules; one `Locate` and the sessions' `Reach`, made from the
//// same names and the registry, find the processes a rule watches or sends to.
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
//// - **Sessions** starts with no slots. Each game connection watches it, so
////   each takes the end of its watch, waits a moment and claims again, and the
////   slots match the connections alive; a claim that finds Sessions not yet
////   running is made again a few times, and one it does not answer ends that
////   connection with 0x036A reason 8, as does the last of the retries, and its
////   client logs in again (genesis_prime/game/connection). A client that logs in to an account during the gap,
////   before the account's old connection claims again, is not caught: that
////   old connection's claim then takes the slot from it
////   (genesis_prime/sessions).
//// - **Maps and the maps** (genesis_prime/world_map/maps): a map that ends is
////   started again, empty, by the next ask for it; Maps' restart ends every
////   map. Each in-world connection watches its map, so its end ends the
////   connection with 0x036A reason 8, and its client logs in again.
//// - **The registry** (the `pg` scope) starts with no members, so no
////   connection could be found. It is the game subtree's first child under
////   `rest_for_one`, so its restart also restarts the game listener: every
////   game client is dropped and logs in again, and Sessions frees each
////   slot as its connection ends. A restart of the game listener alone leaves
////   the registry as it is; the scope drops each member that ended.
//// - **A listener** restarts with no connections: each client connected to it
////   is dropped and logs in again.
//// - **The login supervisor** restarts one listener at a time, so a fault in
////   the STS listener leaves the auth listener's clients connected. A listener
////   that fails three times in ten seconds ends the supervisor, which rebuilds
////   both listeners with no connections; the server supervisor counts that as
////   one of its own restarts.
//// - **The game supervisor** restarts its listener the same way: its clients
////   are dropped and play from the login again, and a fault in it leaves the
////   login's clients as they are. It is `rest_for_one` for the registry's
////   sake, above, so the registry's restart ends the listener first. Its limit is the login's: three in ten
////   seconds, the same as the server's, so a listener that cannot stay up ends
////   the subtree after three tries, and the subtree ends the node after three.
////   A subtree's shutdown time is infinity, since its children are listeners
////   that each give their connections `connection_shutdown_ms`.

import genesis_prime/client_connection.{
  type Answer, type Request, AskHandOff, AskSessions, AskStore, FromHandOff,
  FromSessions, FromStore, SentBySessions,
}
import genesis_prime/connection/listener.{Listener}
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/connection/shell as connection_shell
import genesis_prime/game/connection as game_connection
import genesis_prime/hand_off
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/rule_recording/file.{type Recorder}
import genesis_prime/service.{type Call, type Locate, type Reach, type Sent}
import genesis_prime/service/shell as service_shell
import genesis_prime/sessions
import genesis_prime/step.{type Rule}
import genesis_prime/store/worker.{type Job}
import genesis_prime/world_map/maps
import gleam/erlang/process.{type Name, type Pid}
import gleam/option.{type Option, None, Some}
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
    /// The sessions service.
    sessions: Name(Call(sessions.Message, sessions.Outgoing)),
    /// How long Sessions has to stop.
    sessions_shutdown_ms: Int,
    /// Where Sessions' inputs are recorded; `None` unless the dev start turns
    /// recording on.
    sessions_recorder: Option(Recorder),
    /// Where the game connections are found, made once with
    /// `registry.new`.
    registry: Registry,
    /// The world subtree: Maps and the map supervisor.
    world: World,
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

/// The world subtree's names and settings.
pub type World {
  World(
    /// Maps, the registry that finds and starts maps.
    maps: Name(maps.Message),
    /// The map supervisor, whose children are the maps.
    map_supervisor: Name(maps.MapSupervisor),
    /// How long a call to Maps may take, from a connection's directory or
    /// locate.
    maps_call_ms: Int,
    /// How long a map has to stop.
    map_shutdown_ms: Int,
    /// The folder each map's inputs are recorded in, one file per map;
    /// `None` unless the dev start turns recording on.
    map_recordings: Option(String),
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

/// How a rule's ask reaches the process it names, and how its answer comes
/// back as the answer type of every connection rule.
type Directory =
  fn(Request, fn(Answer) -> Nil) -> Result(Sent, Nil)

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
      reach: service.Reach(locate: locate(settings), send: fn(_to, _answer) {
        Error(Nil)
      }),
      shutdown_ms: settings.hand_off_shutdown_ms,
      recorder: None,
    )),
  )
  |> supervisor.add(
    service_shell.supervised(service_shell.Settings(
      rule: sessions.rule(),
      name: settings.sessions,
      reach: sessions_reach(settings),
      shutdown_ms: settings.sessions_shutdown_ms,
      recorder: settings.sessions_recorder,
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
fn directory(settings: Settings) -> Directory {
  let store = settings.store
  let hand_off = settings.hand_off
  let sessions = settings.sessions
  fn(request: Request, reply: fn(Answer) -> Nil) {
    case request {
      AskStore(request:) ->
        worker.ask(store, request, fn(answer) { reply(FromStore(answer)) })
      AskHandOff(message:) ->
        service.call(hand_off, message, fn(answer) {
          reply(FromHandOff(answer))
        })
      AskSessions(message:) ->
        service.call(sessions, message, fn(answer) {
          reply(FromSessions(answer))
        })
    }
  }
}

/// How a shell finds the process an address names, for a `Watch`: a service
/// or the store by its name, a connection in the registry. No process holds a
/// map's address yet.
fn locate(settings: Settings) -> Locate {
  let store = settings.store
  let hand_off = settings.hand_off
  let sessions = settings.sessions
  let registry = settings.registry
  fn(address: step.Address) {
    case address {
      step.Sessions -> process.named(sessions)
      step.HandOff -> process.named(hand_off)
      step.Store -> process.named(store)
      step.Connection(connection:) -> registry.find(registry, connection)
      step.Maps | step.Map(..) -> Error(Nil)
    }
  }
}

/// How Sessions reaches the processes its rule names: the same lookups, and
/// a send to a connection, which takes what Sessions sends as the message
/// `SentBySessions`. Only a connection is sent to; any other address has no
/// process that takes a message from Sessions.
fn sessions_reach(settings: Settings) -> Reach(sessions.Outgoing) {
  let registry = settings.registry
  service.Reach(locate: locate(settings), send: fn(to, outgoing) {
    case to {
      step.Connection(connection:) ->
        registry.deliver(registry, connection, SentBySessions(outgoing))
      step.Sessions | step.HandOff | step.Store | step.Maps | step.Map(..) ->
        Error(Nil)
    }
  })
}

/// The login subtree: the STS listener, then the auth listener, under a
/// supervisor of their own, a permanent child of the server's.
fn login(
  settings: Settings,
  directory: Directory,
) -> supervision.ChildSpecification(supervisor.Supervisor) {
  use tree <- subtree(supervisor.OneForOne)
  tree
  |> serve(
    settings:,
    served: settings.login.sts,
    rule: sts_connection.rule,
    directory:,
    registry: None,
  )
  |> serve(
    settings:,
    served: settings.login.auth,
    rule: auth_connection.rule,
    directory:,
    registry: None,
  )
}

/// The game subtree: the registry and the game listener, in that order, under
/// a `rest_for_one` supervisor of their own, a permanent child of the
/// server's. The registry's restart restarts the listener, since a restarted
/// registry knows no connection.
fn game(
  settings: Settings,
  directory: Directory,
) -> supervision.ChildSpecification(supervisor.Supervisor) {
  use tree <- subtree(supervisor.RestForOne)
  tree
  |> supervisor.add(registry.supervised(settings.registry))
  |> serve(
    settings:,
    served: settings.game,
    rule: game_connection.rule,
    directory:,
    registry: Some(settings.registry),
  )
}

/// A subtree of the server's tree: a supervisor of its own with the given
/// strategy that restarts three times in ten seconds, the limit of every
/// subtree. With `OneForOne` a fault in one child leaves the others as they
/// are; with `RestForOne` it also restarts the children added after it. `add`
/// puts the subtree's children on it.
fn subtree(
  strategy: supervisor.Strategy,
  add: fn(supervisor.Builder) -> supervisor.Builder,
) -> supervision.ChildSpecification(supervisor.Supervisor) {
  supervisor.new(strategy)
  |> supervisor.restart_tolerance(intensity: 3, period: 10)
  |> add
  |> supervisor.supervised
}

/// Adds one listener, whose connections run the rule `rule` makes from the
/// listener's own settings, with the send and shutdown deadlines every
/// listener shares. Its connections join `registry` when there is one, so a
/// rule can be sent to and watched by its connection's id.
fn serve(
  tree: supervisor.Builder,
  settings settings: Settings,
  served served: Served(rule_settings),
  rule rule: fn(rule_settings) ->
    Rule(rule_settings, state, message, Answer, Nil, Request),
  directory directory: Directory,
  registry registry: Option(Registry),
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
        registry:,
        locate: locate(settings),
      ),
    )),
  )
}

/// Stops the tree, then the VM, when the host sends SIGTERM. The tree is
/// started outside an application, which the VM's own stop does not shut down,
/// so without this its processes get no `Stopping` and no recording gets its
/// `End`. Other signals are handled as the VM does.
pub fn stop_on_sigterm(tree tree: Pid) -> Nil {
  stop_tree_on_sigterm(tree)
}

@external(erlang, "server_shutdown_ffi", "stop_tree_on_sigterm")
fn stop_tree_on_sigterm(tree: Pid) -> Nil
