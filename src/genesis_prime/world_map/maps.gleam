//// Maps: the registry that finds a map by its id and starts it on the first
//// ask. It is a plain actor, not a rule: it makes no game decision, only
//// "running, or start it", as the store's factory supervisor makes none.
//// One actor serialises the finds, so two connections that enter a map at
//// once never start it twice.
////
//// ```
//// world supervisor (rest_for_one, 3 restarts in 10 s)       permanent
////  ├─ Maps: this actor, named                               permanent
////  └─ map supervisor: factory supervisor, named              permanent
////       └─ one map per MapId: service shell + map rule, unnamed  temporary
//// ```
////
//// Find, from the asker's side (the server's directory and `Locate`, in the
//// asker's process):
////
//// ```
//// directory                       Maps                        map supervisor
////   find_or_start(map) ──call──▶ known: the map's process
////                                 else start_child(map)  ──▶ starts the map
////                                 monitor it, keep it
////   ◀── Ok(MapProcess) ◀─────────
////   service.call_subject(map's subject, Join, reply) ──────────────▶ map
//// ```
////
//// - **The call is timed** (`call_ms`, a start argument): a call up the tree
////   to a registry (the designing-processes skill). No answer in time, Maps
////   not running, or a start that fails is `Error(Nil)`, which the asker's
////   shell gives its rule as `NotRunning`.
//// - **`find`** answers only a running map and never starts one; a watch
////   uses it, so watching a map that is not running ends the watch at once.
//// - **A map ends.** Maps' monitor drops it, so the next find starts it
////   again, empty. Its players' connections watch it and end.
//// - **Maps restarts.** It is the first child under `rest_for_one`, so the
////   map supervisor restarts with it and every map ends: a registry that
////   lost its list must not start a second copy of a running map. Every
////   player's connection ends, and its client logs in again.
//// - **The map supervisor restarts alone.** Every map ends; Maps' monitors
////   drop each, and the next finds start them again.
//// - **The server stopping.** The world subtree starts before the login and
////   game subtrees, so it stops after them: no connection is left asking a
////   map that has stopped.

import genesis_prime/service.{type Call}
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{type MapId}
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Monitor, type Name, type Pid, type Subject}
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision.{type ChildSpecification}

/// A running map: its process, to watch, and its subject, to ask.
pub type MapProcess {
  MapProcess(pid: Pid, subject: Subject(Call(map.Message, map.Outgoing)))
}

/// The map supervisor's messages: a map's id starts a map.
pub type MapSupervisor =
  factory_supervisor.Message(MapId, Subject(Call(map.Message, map.Outgoing)))

/// What reaches Maps.
pub opaque type Message {
  /// Find the map; start it when `start` and it is not running.
  Find(map: MapId, start: Bool, reply: Subject(Result(MapProcess, Nil)))
  /// A map Maps started has ended.
  MapEnded(down: process.Down)
}

/// Maps' state: each running map by its id, with its monitor.
type State {
  State(
    supervisor: Name(MapSupervisor),
    maps: Dict(MapId, #(MapProcess, Monitor)),
  )
}

/// Maps, named, as a permanent child of the world supervisor.
pub fn supervised(
  name name: Name(Message),
  supervisor supervisor: Name(MapSupervisor),
) -> ChildSpecification(Subject(Message)) {
  todo as "built in the build"
}

/// The map supervisor, named, whose children are maps started by `start`,
/// each temporary: a map that ends is started again by the next find.
pub fn map_supervisor(
  name name: Name(MapSupervisor),
  start start: fn(MapId) ->
    actor.StartResult(Subject(Call(map.Message, map.Outgoing))),
) -> ChildSpecification(
  factory_supervisor.Supervisor(MapId, Subject(Call(map.Message, map.Outgoing))),
) {
  todo as "built in the build"
}

/// The running map, started when it is not running: `Error(Nil)` when Maps
/// does not answer within `call_ms`, is not running, or the start fails.
pub fn find_or_start(
  maps maps: Name(Message),
  map map: MapId,
  call_ms call_ms: Int,
) -> Result(MapProcess, Nil) {
  todo as "built in the build"
}

/// The running map, never started: `Error(Nil)` when it is not running or
/// Maps does not answer within `call_ms`.
pub fn find(
  maps maps: Name(Message),
  map map: MapId,
  call_ms call_ms: Int,
) -> Result(MapProcess, Nil) {
  todo as "built in the build"
}
