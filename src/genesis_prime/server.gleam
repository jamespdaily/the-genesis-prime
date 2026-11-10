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
////  │    ├─ creature registry: OTP's pg scope, named      permanent
////  │    ├─ Maps: the registry actor, named              permanent
////  │    ├─ creature supervisor: factory supervisor, named  permanent
////  │    │    └─ one creature per spawn a player sees in a map run: service shell + creature rule, unnamed  temporary
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
//// Before the tree starts, `main` loads the content tables (genesis_prime/content)
//// into persistent terms under `World.spawns`'s key, with a database pool of its
//// own: a map reads its world's spawns from the term when it starts and no process
//// queries a content table during play. The load stops the start when a row is
//// refused or the migrations differ, so no listener opens first.
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
////   map and every creature. Each in-world connection watches its map, so its end
////   ends the connection with 0x036A reason 8, and its client logs in again.
//// - **The creatures** (genesis_prime/world_map/creature, `creature_supervisor`,
////   `creature_registry`): a map has a creature started at a spawn of its
////   world when a player first sees the spawn, watches it, and stops it when no
////   player has seen it for the idle stop. A creature that crashes is replaced by
////   the map as a new unit after a delay if a player sees the spawn then, and
////   every player is told the old unit is gone; a map run that ends ends its
////   creatures, which watch it by the pid it started them with. The creature supervisor sits after Maps and before the
////   map supervisor, so its restart ends every map and every creature, and the
////   registry's, before them all, ends the same; a creature that fails to start
////   leaves its spawn empty for the run, with an error line.
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
  type Answer, type Message, type PeerNews, type Request, AskHandOff, AskMap,
  AskMapRun, AskSessions, AskStore, ChangeEnds, ChangeStarts, ForStay,
  FromHandOff, FromMap, FromSessions, FromStore, SentByChat, SentByFoe,
  SentByKill, SentByMap, SentByPeer, SentBySessions, SentByTarget, TellChat,
  TellLifeChanged, TellMoved, TellPeer, TellReady, TellStealthChanged,
  TellStrike, TellStrikeAnswered, TellTargetChange, TellTargetMoved,
  TellVisibilityChanged,
}
import genesis_prime/connection/closer
import genesis_prime/connection/listener.{Listener}
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/connection/script.{type Scripts}
import genesis_prime/connection/shell as connection_shell
import genesis_prime/content/creature_kind as content_creature_kind
import genesis_prime/content/game_number as content_game_number
import genesis_prime/content/spawn as content_spawn
import genesis_prime/game/connection as game_connection
import genesis_prime/game/experience
import genesis_prime/hand_off
import genesis_prime/login/auth_connection
import genesis_prime/login/sts_connection
import genesis_prime/service.{type Call, type Locate, type Reach, type Sent}
import genesis_prime/service/shell as service_shell
import genesis_prime/step.{type ConnectionRule, LogError}
import genesis_prime/step/runtime
import genesis_prime/step/watch
import genesis_prime/store/worker.{type Job}
import genesis_prime/table/loader/store as table_store
import genesis_prime/wire_recording/recorder.{type WireRecorder}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_kind
import genesis_prime/world_map/creature_registry.{type CreatureRegistry}
import genesis_prime/world_map/creature_supervisor
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId}
import genesis_prime/world_map/registry as world_map_registry
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/stay.{type Stay}
import gleam/dict
import gleam/erlang/process.{type Name, type Subject}
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
    /// How often the tree may restart a child before it gives up.
    tree_restarts: Restarts,
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

/// How often a supervisor may restart its children before it gives up: more
/// than `intensity` restarts within `period_s` seconds end it.
pub type Restarts {
  Restarts(intensity: Int, period_s: Int)
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
    /// Where the creatures are found, made once with `creature_registry.new`.
    creatures: CreatureRegistry,
    /// The creature supervisor, whose children are the creatures.
    creature_supervisor: Name(creature_supervisor.CreatureSupervisor),
    /// How long a creature has to stop.
    creature_shutdown_ms: Int,
    /// How long a creature that no player sees keeps running, and how often
    /// each map looks for one: the idle stop and the sweep of the map's rule.
    idle_stop_ms: Int,
    sweep_ms: Int,
    /// The key the content load put each world's spawns under
    /// (genesis_prime/content/spawn): a map reads its world's term when it
    /// starts, and a creature reads its spawn from it, with no query during play.
    spawns: table_store.Key,
    /// The clock the maps and creatures take each input's time from and the
    /// scheduler their timers start on: `service_shell.real_time()` on a
    /// server, the driven clock's in a whole-server test.
    service_time: service_shell.ServiceTime,
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
/// socket are recorded (`wire_recorder`), `None` unless GENESIS_RECORD_DIR turns
/// recording on (genesis_prime/sitting), and where each accepted connection gets its script, its seed, the time of
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

/// Starts the tree. A child that fails more often than the settings'
/// `tree_restarts` allow (the server's are three times in ten seconds) does not
/// recover by restarting, so the tree gives up, the node stops, and the host
/// starts it again.
pub fn start(
  settings settings: Settings,
) -> actor.StartResult(supervisor.Supervisor) {
  let directory = directory(settings)
  supervisor.new(supervisor.OneForOne)
  |> supervisor.restart_tolerance(
    intensity: settings.tree_restarts.intensity,
    period: settings.tree_restarts.period_s,
  )
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
      found_at: None,
      time: service_shell.real_time(),
    ),
  ))
  |> supervisor.add(service_shell.supervised(
    name: settings.sessions,
    settings: service_shell.Settings(
      rule: account_session.rule(),
      reach: connection_reach(settings, fn(message) {
        Ok(SentBySessions(message))
      }),
      shutdown_ms: settings.sessions_shutdown_ms,
      found_at: None,
      time: service_shell.real_time(),
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
      TellMoved(..)
      | TellReady(..)
      | TellStealthChanged(..)
      | TellLifeChanged(..)
      | TellVisibilityChanged(..)
      | TellPeer(..)
      | TellChat(..)
      | TellStrike(..)
      | TellTargetMoved(..)
      | TellStrikeAnswered(..)
      | TellTargetChange(..) -> Error(Nil)
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
  fn(address: step.Address) {
    case address {
      step.Sessions -> process.named(sessions)
      step.HandOff -> process.named(hand_off)
      step.Store -> process.named(store)
      step.Connection(connection:) -> registry.find(registry, connection)
      step.CharacterNamed(folded_name:) ->
        registry.find_named(registry, folded_name)
      step.ZoneChannel(..) -> Error(Nil)
      step.Creature(map:, incarnation:, unit_id:, life:) ->
        creature_registry.find(
          settings.world.creatures,
          map:,
          incarnation:,
          unit_id:,
          life:,
        )
      step.Maps -> process.named(settings.world.maps)
      step.Map(map:, incarnation:) ->
        find_run(settings:, map:, incarnation:)
        |> result.map(fn(found) { found.pid })
    }
  }
}

/// The run of the map with this incarnation, which Maps finds and never
/// starts, in the time a watch's call to Maps may take. One lookup serves both
/// the pid a watch monitors and the subject a tell goes to.
fn find_run(
  settings settings: Settings,
  map map: MapId,
  incarnation incarnation: Int,
) -> Result(world_map_registry.MapProcess, Nil) {
  world_map_registry.find(
    settings.world.maps,
    map,
    incarnation,
    deadline_ms: runtime.now().monotonic_ms + settings.world.maps_call_ms,
  )
  |> result.replace_error(Nil)
}

/// How a game or login connection's shell finds the process a `Watch` names,
/// with the way to tell it when the rule tells it: the run of a map is found
/// once, and the way to tell it (`TellMoved`) comes with the pid the watch
/// monitors; the connection that holds a character's name is found in the
/// registry, and told a chat tell (`TellChat`) through it. A zone channel is
/// never watched, and any other address has no process that takes a tell.
fn connection_locate(
  settings: Settings,
) -> fn(step.Address) -> Result(watch.Found(fn(Request) -> Nil), Nil) {
  let pids = locate(settings)
  fn(address: step.Address) {
    case address {
      step.Map(map:, incarnation:) ->
        find_run(settings:, map:, incarnation:)
        |> result.map(fn(found) {
          watch.Tellable(pid: found.pid, sender: tell_the_run(
            subject: found.subject,
            request: _,
          ))
        })
      step.CharacterNamed(folded_name:) ->
        registry.find_named(settings.registry, folded_name)
        |> result.map(fn(pid) {
          watch.Tellable(pid:, sender: tell_the_connection(pid:, request: _))
        })
      step.Sessions
      | step.HandOff
      | step.Store
      | step.Maps
      | step.ZoneChannel(..)
      | step.Creature(..)
      | step.Connection(..) -> pids(address) |> result.map(watch.Watched)
    }
  }
}

/// Tells the connection a watch on a character's name found what the request
/// says, a chat tell, which its shell takes as a `SentByChat` message. Any other
/// request is no tell to a connection by name: a rule that tells one has a bug,
/// logged as an error, and nothing is sent.
fn tell_the_connection(pid pid: process.Pid, request request: Request) -> Nil {
  case request {
    TellChat(tell:) -> registry.deliver_to(pid, SentByChat(tell:))
    TellMoved(..)
    | TellReady(..)
    | TellStealthChanged(..)
    | TellLifeChanged(..)
    | TellVisibilityChanged(..)
    | TellPeer(..)
    | TellStrike(..)
    | TellTargetMoved(..)
    | TellStrikeAnswered(..)
    | TellTargetChange(..)
    | AskStore(..)
    | AskHandOff(..)
    | AskSessions(..)
    | AskMap(..)
    | AskMapRun(..) ->
      runtime.log(
        LogError,
        "a rule told a connection by name something other than a chat tell",
        step.no_one,
      )
  }
}

/// Tells the run of a map what the request says: that a player moved, is
/// ready, entered or left stealth, or died or woke. Any other request is an ask, which a tell never carries: a rule that
/// tells one has a bug, logged as an error, and nothing is sent.
pub fn tell_the_run(
  subject subject: Subject(Call(map.Message, map.Outgoing)),
  request request: Request,
) -> Nil {
  case request {
    TellMoved(connection:, place:, seq:) -> {
      let _sent =
        service.tell_subject(subject, map.Moved(connection:, place:, seq:))
      Nil
    }
    TellReady(connection:, seq:) -> {
      let _sent = service.tell_subject(subject, map.Ready(connection:, seq:))
      Nil
    }
    TellStealthChanged(connection:, stealthed:) -> {
      let _sent =
        service.tell_subject(
          subject,
          map.StealthChanged(connection:, stealthed:),
        )
      Nil
    }
    TellVisibilityChanged(connection:, hidden:) -> {
      let _sent =
        service.tell_subject(
          subject,
          map.VisibilityChanged(connection:, hidden:),
        )
      Nil
    }
    TellLifeChanged(connection:, alive:) -> {
      let _sent =
        service.tell_subject(subject, map.LifeChanged(connection:, alive:))
      Nil
    }
    TellPeer(..)
    | TellChat(..)
    | TellStrike(..)
    | TellTargetMoved(..)
    | TellStrikeAnswered(..)
    | TellTargetChange(..)
    | AskStore(..)
    | AskHandOff(..)
    | AskSessions(..)
    | AskMap(..)
    | AskMapRun(..) ->
      runtime.log(
        LogError,
        "a rule told a map something other than a move, which a map takes only by an ask",
        step.no_one,
      )
  }
}

/// A connection's tell to the creature `to`, through the creature registry with no
/// watch: a strike (`TellStrike`) as the creature's `Strike`, a fighter's move
/// (`TellTargetMoved`) as `TargetMoved`, the answer to its strike
/// (`TellStrikeAnswered`) as `StrikeAnswered`, and a modifier's start or end
/// (`TellTargetChange`) as `ModifierStarts` or `ModifierEnds`. Any other request,
/// or an address that is no creature, is an error and nothing is sent.
pub fn tell_creature(
  creatures creatures: CreatureRegistry,
  to to: step.Address,
  request request: Request,
) -> Result(Nil, Nil) {
  case to, creature_told(request) {
    step.Creature(map:, incarnation:, unit_id:, life:), Ok(message) ->
      creature_registry.tell(
        creatures,
        map:,
        incarnation:,
        unit_id:,
        life:,
        message:,
      )
    step.Creature(..), Error(Nil)
    | step.Connection(..), _
    | step.Sessions, _
    | step.HandOff, _
    | step.Store, _
    | step.Maps, _
    | step.Map(..), _
    | step.CharacterNamed(..), _
    | step.ZoneChannel(..), _
    -> Error(Nil)
  }
}

/// The message a creature takes a connection's request as, for the four requests a
/// creature is told.
fn creature_told(request: Request) -> Result(creature.Message, Nil) {
  case request {
    TellStrike(tell:) -> Ok(creature.Strike(tell:))
    TellTargetMoved(connection:, place:, seq:, stay:) ->
      Ok(creature.TargetMoved(by: connection, place:, seq:, stay:))
    TellStrikeAnswered(answered:) -> Ok(creature.StrikeAnswered(answered:))
    TellTargetChange(connection:, change:) ->
      Ok(case change {
        ChangeStarts(source:, modifier:, struck_at_ms:) ->
          creature.ModifierStarts(
            by: connection,
            source:,
            modifier:,
            struck_at_ms:,
          )
        ChangeEnds(source:) -> creature.ModifierEnds(source:)
      })
    TellPeer(..)
    | TellChat(..)
    | TellMoved(..)
    | TellReady(..)
    | TellStealthChanged(..)
    | TellLifeChanged(..)
    | TellVisibilityChanged(..)
    | AskStore(..)
    | AskHandOff(..)
    | AskSessions(..)
    | AskMap(..)
    | AskMapRun(..) -> Error(Nil)
  }
}

/// How a connection's shell sends a request to another connection by address
/// (`Tell` to a `Connection`) or to every connection of a zone channel (`Tell` to
/// a `ZoneChannel`): news of a player's unit (`TellPeer`) goes through the
/// registry as `SentByPeer` for the viewer's stay (`ForStay`), and a chat tell
/// (`TellChat`) as `SentByChat`, by the
/// same reach the services' sends take (`connection_reach`). A strike
/// (`TellStrike`), a fighter's move (`TellTargetMoved`), the answer to a
/// creature's strike (`TellStrikeAnswered`) and a modifier's start or end
/// (`TellTargetChange`) told to a `Creature` go through the creature registry with
/// no watch, as the creature's `Strike`, `TargetMoved`, `StrikeAnswered`,
/// `ModifierStarts` and `ModifierEnds` messages. Any other request is no tell to a
/// connection or a creature: a rule that sends one has a bug, logged as an error,
/// and nothing is sent.
fn connection_deliver(
  settings: Settings,
) -> fn(step.Address, Request) -> Result(Nil, Nil) {
  let reach =
    connection_reach(settings, fn(sent: #(Stay, PeerNews)) {
      Ok(ForStay(stay: sent.0, sent: SentByPeer(news: sent.1)))
    })
  let chat_reach = connection_reach(settings, fn(tell) { Ok(SentByChat(tell)) })
  fn(to: step.Address, request: Request) {
    case request, to {
      TellPeer(stay:, news:), _ -> reach.send(to, #(stay, news))
      TellChat(tell:), _ -> chat_reach.send(to, tell)
      TellStrike(..) as request, step.Creature(..)
      | TellTargetMoved(..) as request, step.Creature(..)
      | TellStrikeAnswered(..) as request, step.Creature(..)
      | TellTargetChange(..) as request, step.Creature(..)
      -> tell_creature(creatures: settings.world.creatures, to:, request:)
      TellStrike(..), _
      | TellTargetMoved(..), _
      | TellStrikeAnswered(..), _
      | TellTargetChange(..), _
      | TellMoved(..), _
      | TellReady(..), _
      | TellStealthChanged(..), _
      | TellLifeChanged(..), _
      | TellVisibilityChanged(..), _
      | AskStore(..), _
      | AskHandOff(..), _
      | AskSessions(..), _
      | AskMap(..), _
      | AskMapRun(..), _
      -> {
        runtime.log(
          LogError,
          "a rule sent a connection something other than news of a player's unit",
          step.no_one,
        )
        Error(Nil)
      }
    }
  }
}

/// How a service reaches the processes its rule names: the same lookups, and
/// a send to a connection, which takes what the service sends wrapped by
/// `wrap` (`SentBySessions`, a map's notice for a stay). Only a connection is sent
/// to; any other address has no process that takes a message from a service. A
/// send `wrap` has no message for is a bug of the sender's rule: an error line,
/// and nothing is sent.
fn connection_reach(
  settings: Settings,
  wrap: fn(outgoing) -> Result(Message, Nil),
) -> Reach(outgoing) {
  let registry = settings.registry
  service.Reach(
    locate: locate(settings),
    send: fn(to, outgoing) {
      case wrap(outgoing), to {
        Error(Nil), _ -> {
          runtime.log(
            LogError,
            "a service sent a connection something no connection takes",
            step.no_one,
          )
          Error(Nil)
        }
        Ok(message), step.Connection(connection:) ->
          registry.deliver(registry, connection, message)
        Ok(message), step.ZoneChannel(..) ->
          registry.deliver_group(registry, to, message)
        Ok(_), step.Sessions
        | Ok(_), step.HandOff
        | Ok(_), step.Store
        | Ok(_), step.Maps
        | Ok(_), step.Map(..)
        | Ok(_), step.Creature(..)
        | Ok(_), step.CharacterNamed(..)
        -> Error(Nil)
      }
    },
    start_creature: fn(_creature) { Error(service.SupervisorNotRunning) },
  )
}

/// The message a connection takes what a map sends it as: a notice for the
/// player's stay. Any other outgoing of a map is an answer or a creature's, never
/// sent to a connection, and has none.
pub fn map_message(outgoing outgoing: map.Outgoing) -> Result(Message, Nil) {
  case outgoing {
    map.Noticed(stay:, notice:) -> Ok(ForStay(stay:, sent: SentByMap(notice:)))
    map.Joined(..)
    | map.Summoned(..)
    | map.NotSummoned(..)
    | map.NotJoined(..)
    | map.Left
    | map.Watched(..)
    | map.Unwatched(..)
    | map.Retire
    | map.Approached(..)
    | map.Withdrew(..)
    | map.PlayerDied(..) -> Error(Nil)
  }
}

/// The world subtree: the creature registry, Maps, the creature supervisor, then
/// the map supervisor, under a `rest_for_one` supervisor of their own, a
/// permanent child of the server's.
fn world(
  settings: Settings,
) -> supervision.ChildSpecification(supervisor.Supervisor) {
  use tree <- subtree(supervisor.RestForOne)
  let connections = settings.registry
  add_world(
    tree:,
    world: settings.world,
    realm_id: settings.game.settings.realm_id,
    tables: settings.game.settings.tables,
    reach: connection_reach(settings, fn(outgoing) { map_message(outgoing:) }),
    to_connection: fn(connection, outgoing) {
      registry.deliver(connections, connection, creature_message(outgoing:))
    },
  )
}

/// Adds the creature registry, Maps, the creature supervisor and the map
/// supervisor to a `rest_for_one` supervisor, in that order: the registry's
/// restart ends everything after it, Maps' ends the creatures and the maps, and
/// the creature supervisor's ends the maps, so no map outlives the registry that
/// knew its creatures. A map is started by the map supervisor with the rule of its id and
/// incarnation, the realm and game tables its players' units are built from, the
/// spawns of its world, no name, and a reach that finds what it watches and
/// sends to its players' connections (`reach`) and to its creatures, and starts
/// them. A creature is started by the creature supervisor with the rule of its
/// spawn, no name, and a reach that sends its 0x262 and 0x355 to the connections
/// of the players who see it (`to_connection`) and finds the run that started it
/// by that run's pid. The server's tree and the tests start the world with this
/// function.
pub fn add_world(
  tree tree: supervisor.Builder,
  world world: World,
  realm_id realm_id: Int,
  tables tables: table_store.Tables,
  reach reach: Reach(map.Outgoing),
  to_connection to_connection: fn(step.ConnectionId, creature.Outgoing) ->
    Result(Nil, Nil),
) -> supervisor.Builder {
  tree
  |> supervisor.add(creature_registry.supervised(world.creatures))
  |> supervisor.add(world_map_registry.supervised(
    name: world.maps,
    supervisor: world.map_supervisor,
  ))
  |> supervisor.add(
    creature_supervisor.supervisor(
      name: world.creature_supervisor,
      shutdown_ms: world.creature_shutdown_ms,
      start: fn(start: creature_supervisor.CreatureProcessStart) {
        start_creature_process(world:, reach:, to_connection:, start:)
      },
    ),
  )
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
            spawns: content_spawn.world(world.spawns, start.map.world_id),
            summons: content_spawn.summon_checks(world.spawns),
            kinds: content_creature_kind.kinds(world.spawns),
            numbers: content_game_number.numbers(world.spawns),
            idle_stop_ms: world.idle_stop_ms,
            sweep_ms: world.sweep_ms,
          ),
          reach: map_reach(world:, reach:),
          shutdown_ms: world.map_shutdown_ms,
          found_at: None,
          time: world.service_time,
        ))
      },
    ),
  )
}

/// A map's reach: the given one for everything but its creatures, which it finds
/// and sends `Watched` and `Unwatched` through the creature registry, and starts
/// under the creature supervisor.
fn map_reach(
  world world: World,
  reach reach: Reach(map.Outgoing),
) -> Reach(map.Outgoing) {
  service.Reach(
    locate: fn(address) {
      case address {
        step.Creature(map:, incarnation:, unit_id:, life:) ->
          creature_registry.find(
            world.creatures,
            map:,
            incarnation:,
            unit_id:,
            life:,
          )
        step.Sessions
        | step.HandOff
        | step.Store
        | step.Maps
        | step.Map(..)
        | step.Connection(..)
        | step.CharacterNamed(..)
        | step.ZoneChannel(..) -> reach.locate(address)
      }
    },
    send: fn(to, outgoing) {
      case to {
        step.Creature(map:, incarnation:, unit_id:, life:) ->
          creature.told_by_map(outgoing)
          |> result.try(fn(message) {
            creature_registry.tell(
              world.creatures,
              map:,
              incarnation:,
              unit_id:,
              life:,
              message:,
            )
          })
        step.Sessions
        | step.HandOff
        | step.Store
        | step.Maps
        | step.Map(..)
        | step.Connection(..)
        | step.CharacterNamed(..)
        | step.ZoneChannel(..) -> reach.send(to, outgoing)
      }
    },
    start_creature: fn(creature) {
      creature_supervisor.start_creature(
        supervisor: world.creature_supervisor,
        creature:,
      )
    },
  )
}

/// Starts one creature as the creature supervisor asks: the shell of its rule,
/// which joins the creature's address in the registry as it starts.
fn start_creature_process(
  world world: World,
  reach reach: Reach(map.Outgoing),
  to_connection to_connection: fn(step.ConnectionId, creature.Outgoing) ->
    Result(Nil, Nil),
  start start: creature_supervisor.CreatureProcessStart,
) -> actor.StartResult(Subject(Call(creature.Message, creature.Outgoing))) {
  let wanted = start.creature
  case spawn_of_start(world:, wanted:) {
    Error(Nil) ->
      Error(actor.InitFailed(
        "the creature names a spawn the world does not hold",
      ))
    Ok(found) ->
      service_shell.start_unnamed(service_shell.Settings(
        rule: creature.rule(
          creature: wanted,
          spawn: found,
          kind: creature_kind.kind_of(
            kinds: content_creature_kind.kinds(world.spawns),
            creature2_id: { found.creature_id }.value,
          ),
          numbers: content_game_number.numbers(world.spawns),
        ),
        reach: creature_reach(world:, reach:, to_connection:, start:),
        shutdown_ms: world.creature_shutdown_ms,
        found_at: Some(service_shell.FoundAt(
          scope: creature_registry.scope(world.creatures),
          address: step.Creature(
            map: wanted.map,
            incarnation: wanted.incarnation,
            unit_id: wanted.unit_id,
            life: wanted.life,
          ),
        )),
        time: world.service_time,
      ))
  }
}

/// The spawn a creature is started at: a stored one is read from its world's
/// term, and a run-only one is built again from the summon the map checked, with
/// the world's summon checks, so the map and the creature hold the same spawn
/// (genesis_prime/world_map/spawn_source). `Error(Nil)` for a stored id the
/// world does not hold.
fn spawn_of_start(
  world world: World,
  wanted wanted: step.CreatureStart,
) -> Result(spawn.Spawn, Nil) {
  case wanted.spawn {
    spawn_source.Stored(id:) ->
      content_spawn.world(world.spawns, wanted.map.world_id).by_id
      |> dict.get(id)
    spawn_source.RunOnly(summoned:) -> {
      let assert Ok(built) =
        spawn.summoned(
          checks: content_spawn.summon_checks(world.spawns),
          summoned:,
        )
        as "the map checked this summon with the same checks, so the creature's start finds no refusal"
      Ok(built)
    }
  }
}

/// A creature's reach: it finds the run that started it by that run's pid, since
/// Maps is waiting on the run's start while the run starts its creatures, finds
/// any other process as the world's reach does, and sends the connections of the
/// players who see it what it owns of its unit.
fn creature_reach(
  world world: World,
  reach reach: Reach(map.Outgoing),
  to_connection to_connection: fn(step.ConnectionId, creature.Outgoing) ->
    Result(Nil, Nil),
  start start: creature_supervisor.CreatureProcessStart,
) -> Reach(creature.Outgoing) {
  let own = start.creature
  service.Reach(
    locate: fn(address) {
      case address {
        step.Map(map:, incarnation:)
          if map == own.map && incarnation == own.incarnation
        -> Ok(start.run)
        step.Creature(map:, incarnation:, unit_id:, life:) ->
          creature_registry.find(
            world.creatures,
            map:,
            incarnation:,
            unit_id:,
            life:,
          )
        step.Sessions
        | step.HandOff
        | step.Store
        | step.Maps
        | step.Map(..)
        | step.Connection(..)
        | step.CharacterNamed(..)
        | step.ZoneChannel(..) -> reach.locate(address)
      }
    },
    send: fn(to, news) {
      case to {
        step.Connection(connection:) -> to_connection(connection, news)
        step.Sessions
        | step.HandOff
        | step.Store
        | step.Maps
        | step.Map(..)
        | step.Creature(..)
        | step.CharacterNamed(..)
        | step.ZoneChannel(..) -> Error(Nil)
      }
    },
    start_creature: fn(_creature) { Error(service.SupervisorNotRunning) },
  )
}

/// The message a connection takes what a creature sends it as: the news of a unit
/// as `SentByPeer`, the creature's threat, release or strike as `SentByFoe`, each
/// for the viewer's stay, the answer to its strike as `SentByTarget`, and the credit
/// for its death as `SentByKill`, each for the stay the strike was told for.
pub fn creature_message(outgoing outgoing: creature.Outgoing) -> Message {
  case outgoing {
    creature.News(stay:, news:) -> ForStay(stay:, sent: SentByPeer(news:))
    creature.Struck(stay:, answered:) ->
      ForStay(stay:, sent: SentByTarget(answered))
    creature.FightTold(stay:, told:) -> ForStay(stay:, sent: SentByFoe(told))
    creature.KillCredit(stay:, unit_id:, creature_id:, faction_id:, level:) ->
      ForStay(
        stay:,
        sent: SentByKill(experience.Credit(
          unit_id:,
          creature_id:,
          faction_id:,
          level:,
        )),
      )
  }
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
        locate: connection_locate(settings),
        deliver: connection_deliver(settings),
      ),
    )),
  )
}
