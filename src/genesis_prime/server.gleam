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
////  ├─ game supervisor (rest_for_one, 3 restarts in 10 s)  permanent
////  │    ├─ registry: OTP's pg scope, named               permanent
////  │    └─ game listener (24000): a connection shell per client, each
////  │         joined to the registry under its ConnectionId
////  └─ closer: closes every listener to new sockets      permanent
//// ```
////
//// The tree stops the closer first, which closes every listener to new
//// sockets (genesis_prime/connection/closer), then the game subtree, the login
//// subtree and the world subtree, before Sessions, the hand-off, the store and
//// the pool they ask, so no connection is left asking a process that has
//// stopped. The tree runs under the application's root
//// (genesis_prime/application), so the host's SIGTERM stops it this way. A map's ask
//// goes through Maps (genesis_prime/world_map/registry), which finds the map or
//// starts it; a map's address is found the same way, never started, for a
//// watch and for the ask of a leave. One directory, made once in `start` from
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
////   client logs in again (genesis_prime/game/connection). When claims of one
////   account come from several connections, in any order and across several
////   restarts, the newest login keeps the slot and each older connection ends
////   with 0x036A reason 19 (genesis_prime/account_session).
//// - **Maps and the maps** (genesis_prime/world_map/registry): a map that ends is
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

import genesis_prime/account_session
import genesis_prime/client_connection.{
  type Answer, type Message, type Request, AskHandOff, AskMap, AskMapRun,
  AskSessions, AskStore, FromHandOff, FromMap, FromSessions, FromStore,
  SentByMap, SentBySessions, TellMoved,
}
import genesis_prime/connection/closer
import genesis_prime/connection/listener.{Listener}
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/connection/script.{type Scripts}
import genesis_prime/connection/shell as connection_shell
import genesis_prime/game/connection as game_connection
import genesis_prime/hand_off
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/service.{type Call, type Locate, type Reach, type Sent}
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{type ConnectionRule}
import genesis_prime/step/runtime
import genesis_prime/store/worker.{type Job}
import genesis_prime/table/loader/store as table_store
import genesis_prime/wire_recording/recorder.{type WireRecorder}
import genesis_prime/world_map/map
import genesis_prime/world_map/registry as world_map_registry
import gleam/erlang/process.{type Name}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/static_supervisor as supervisor
import gleam/otp/supervision
import gleam/result
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
    sessions: Name(Call(account_session.Message, account_session.Outgoing)),
    /// How long Sessions has to stop.
    sessions_shutdown_ms: Int,
    /// Where the game connections are found, made once with
    /// `registry.new`.
    registry: Registry(Message),
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
    maps: Name(world_map_registry.Message),
    /// The map supervisor, whose children are the maps.
    map_supervisor: Name(world_map_registry.MapSupervisor),
    /// How long a watch's call to Maps may take; an ask's call ends at the
    /// ask's own deadline.
    maps_call_ms: Int,
    /// How long a map has to stop.
    map_shutdown_ms: Int,
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
/// the most connections it holds at once (`genesis_prime/connection/listener`),
/// the settings its rule is made with, where the bytes of each connection's
/// socket are recorded (`wire_recorder`), `None` unless the dev start turns
/// recording on, and where each accepted connection gets its script, its seed, the time of
/// each input and its timers (`scripts`): the server's own in the server
/// (`script.operating_system`), each connection's recorded one in a replay.
pub type Served(settings) {
  Served(
    listener: Name(Nil),
    port: Int,
    max_connections: Int,
    settings: settings,
    wire_recorder: Option(WireRecorder),
    scripts: Scripts,
  )
}

/// How a rule's ask reaches the process it names, and how its answer comes
/// back as the answer type of every connection rule. It is given the ask's
/// deadline on the monotonic clock, so a lookup on the way (Maps') ends by
/// it.
type Directory =
  fn(Request, Int, fn(Answer) -> Nil) -> Result(Sent, Nil)

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
  |> supervisor.add(service_shell.supervised(
    name: settings.hand_off,
    settings: service_shell.Settings(
      rule: hand_off.rule(),
      reach: service.watch_only(locate: locate(settings)),
      shutdown_ms: settings.hand_off_shutdown_ms,
    ),
  ))
  |> supervisor.add(service_shell.supervised(
    name: settings.sessions,
    settings: service_shell.Settings(
      rule: account_session.rule(),
      reach: sessions_reach(settings),
      shutdown_ms: settings.sessions_shutdown_ms,
    ),
  ))
  |> supervisor.add(world(settings))
  |> supervisor.add(login(settings, directory))
  |> supervisor.add(game(settings, directory))
  |> supervisor.add(
    closer.supervised([
      settings.login.sts.listener,
      settings.login.auth.listener,
      settings.game.listener,
    ]),
  )
  |> supervisor.start
}

/// How a rule's ask reaches the process it names: to the store by its name,
/// to the hand-off and Sessions by theirs, and to a map through Maps, which
/// finds it or starts it by the ask's deadline (`AskMap`), or only finds the
/// run the ask names and never starts a map (`AskMapRun`); each answer is wrapped in the
/// answer type of every connection rule (`FromStore`, `FromHandOff`,
/// `FromSessions`, `FromMap`). Made once at start; it holds the names, not
/// the settings.
fn directory(settings: Settings) -> Directory {
  let store = settings.store
  let hand_off = settings.hand_off
  let sessions = settings.sessions
  let maps_name = settings.world.maps
  fn(request: Request, deadline_ms: Int, reply: fn(Answer) -> Nil) {
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
      AskMap(map:, message:) ->
        world_map_registry.find_or_start(maps_name, map, deadline_ms)
        |> result.try(fn(found) {
          service.call_subject(found.subject, message, fn(answer) {
            reply(FromMap(answer))
          })
        })
      AskMapRun(map:, incarnation:, message:) ->
        world_map_registry.ask_run(
          maps: maps_name,
          map:,
          incarnation:,
          message:,
          deadline_ms:,
          reply: fn(answer) { reply(FromMap(answer)) },
        )
      TellMoved(..) -> Error(Nil)
    }
  }
}

/// How a shell finds the process an address names, for a `Watch`: a service,
/// Maps or the store by its name, a connection in the registry, and the run of
/// a map that Maps finds without starting it.
fn locate(settings: Settings) -> Locate {
  let store = settings.store
  let hand_off = settings.hand_off
  let sessions = settings.sessions
  let registry = settings.registry
  let maps_name = settings.world.maps
  let maps_call_ms = settings.world.maps_call_ms
  fn(address: step.Address) {
    case address {
      step.Sessions -> process.named(sessions)
      step.HandOff -> process.named(hand_off)
      step.Store -> process.named(store)
      step.Connection(connection:) -> registry.find(registry, connection)
      step.Maps -> process.named(maps_name)
      step.Map(map:, incarnation:) ->
        world_map_registry.find(
          maps_name,
          map,
          incarnation,
          deadline_ms: runtime.now().monotonic_ms + maps_call_ms,
        )
        |> result.map(fn(found) { found.pid })
        |> result.replace_error(Nil)
    }
  }
}

/// How a connection's shell resolves the address of a process its rule tells,
/// once, into the way to tell it: the run of a map, found through Maps, which
/// is told that a player moved (`TellMoved`). Any other address, and any other
/// request, has no process that takes a tell, and the way to it drops what it
/// is given.
fn teller(
  settings: Settings,
) -> fn(step.Address) -> Result(fn(Request) -> Nil, Nil) {
  let maps_name = settings.world.maps
  let maps_call_ms = settings.world.maps_call_ms
  fn(address: step.Address) {
    case address {
      step.Map(map:, incarnation:) ->
        world_map_registry.find(
          maps_name,
          map,
          incarnation,
          deadline_ms: runtime.now().monotonic_ms + maps_call_ms,
        )
        |> result.map(fn(found) {
          fn(request: Request) {
            case request {
              TellMoved(connection:, place:, commands:) -> {
                let _sent =
                  service.tell_subject(
                    found.subject,
                    map.Moved(connection:, place:, commands:),
                  )
                Nil
              }
              AskStore(..)
              | AskHandOff(..)
              | AskSessions(..)
              | AskMap(..)
              | AskMapRun(..) -> Nil
            }
          }
        })
        |> result.replace_error(Nil)
      step.Sessions
      | step.HandOff
      | step.Store
      | step.Maps
      | step.Connection(..) -> Error(Nil)
    }
  }
}

/// How Sessions reaches the processes its rule names: the same lookups, and
/// a send to a connection, which takes what Sessions sends as the message
/// `SentBySessions`. Only a connection is sent to; any other address has no
/// process that takes a message from Sessions.
fn sessions_reach(settings: Settings) -> Reach(account_session.Outgoing) {
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

/// How a map reaches the processes its rule names: the same lookups, and a
/// send to a connection, which takes what a map sends as the message
/// `SentByMap`. Only a connection is sent to.
fn map_reach(settings: Settings) -> Reach(map.Outgoing) {
  let registry = settings.registry
  service.Reach(locate: locate(settings), send: fn(to, outgoing) {
    case to {
      step.Connection(connection:) ->
        registry.deliver(registry, connection, SentByMap(outgoing))
      step.Sessions | step.HandOff | step.Store | step.Maps | step.Map(..) ->
        Error(Nil)
    }
  })
}

/// The world subtree: Maps, then the map supervisor, under a `rest_for_one`
/// supervisor of their own, a permanent child of the server's.
fn world(
  settings: Settings,
) -> supervision.ChildSpecification(supervisor.Supervisor) {
  use tree <- subtree(supervisor.RestForOne)
  add_world(
    tree:,
    world: settings.world,
    realm_id: settings.game.settings.realm_id,
    tables: settings.game.settings.tables,
    reach: map_reach(settings),
  )
}

/// Adds Maps and the map supervisor to a `rest_for_one` supervisor, in that
/// order: Maps' restart restarts the map supervisor, so every map ends with
/// the registry that knew them. A map is started by the map supervisor with
/// the rule of its id and incarnation, the realm and game tables its players'
/// units are built from, no name, and `reach`, which finds what it watches and
/// sends to its players' connections. The server's tree and the tests start
/// the world with this function.
pub fn add_world(
  tree tree: supervisor.Builder,
  world world: World,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
  reach reach: Reach(map.Outgoing),
) -> supervisor.Builder {
  tree
  |> supervisor.add(world_map_registry.supervised(
    name: world.maps,
    supervisor: world.map_supervisor,
  ))
  |> supervisor.add(
    world_map_registry.map_supervisor(
      name: world.map_supervisor,
      shutdown_ms: world.map_shutdown_ms,
      start: fn(start: world_map_registry.MapStart) {
        service_shell.start_unnamed(service_shell.Settings(
          rule: map.rule(
            map: start.map,
            incarnation: start.incarnation,
            realm_id:,
            tables:,
          ),
          reach:,
          shutdown_ms: world.map_shutdown_ms,
        ))
      },
    ),
  )
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
    ConnectionRule(rule_settings, state, Request, message, Answer),
  directory directory: Directory,
  registry registry: Option(Registry(message)),
) -> supervisor.Builder {
  supervisor.add(
    tree,
    listener.supervised(Listener(
      name: served.listener,
      port: served.port,
      max_connections: served.max_connections,
      connection: connection_shell.Settings(
        rule: rule(served.settings),
        send_deadline_ms: settings.send_deadline_ms,
        shutdown_ms: settings.connection_shutdown_ms,
        wire_recorder: served.wire_recorder,
        scripts: served.scripts,
        directory:,
        registry:,
        teller: teller(settings),
        locate: locate(settings),
      ),
    )),
  )
}
