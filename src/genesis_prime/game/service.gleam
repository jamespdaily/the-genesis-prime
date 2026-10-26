//// The game's subtree of the supervision tree: the maps, the workers that
//// carry out character select's commands and the game listener a client is
//// handed to after the login. The maps and the workers start first, so a
//// listener's first client finds them. It is one for one with 3 restarts in 5
//// seconds, like the other subtrees, so a fault that survives three rebuilds
//// stops the subtree and reaches the top. The listener registers with the
//// shutdown coordinator, which stops it accepting and closes its connections
//// in order.

import genesis_prime/character/character.{type Place}
import genesis_prime/character/character_slots
import genesis_prime/character/customisation.{type Customisation}
import genesis_prime/character/store_worker
import genesis_prime/connection/clock
import genesis_prime/connection/listener
import genesis_prime/database/pool
import genesis_prime/game/game_connection
import genesis_prime/game/sessions
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/handoff
import genesis_prime/map/heap_limit
import genesis_prime/map/maps
import genesis_prime/shutdown
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/telemetry/snapshot
import gleam/erlang/process.{type Name}
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision

/// How many restarts the subtree allows in `restart_period_seconds`: the
/// service subtrees' 3 in 5 seconds.
const restart_intensity = 3

const restart_period_seconds = 5

/// How long a connection waits for the store or a map to answer, in
/// milliseconds. 5 seconds; no measurement chose it.
pub const answer_deadline_ms = 5000

/// What the subtree starts with. `port` is the game listener's port, where 0
/// takes a free port, and `opened` is called with the port that is open.
/// `realm_id` is the realm the connections are on, `start` the place a
/// character made from a CharacterCreation row starts at, read from the
/// loaded tables, `clock` the system
/// time as a Windows FILETIME, `customisation` and `character_slots` what the
/// loaded tables say a create request may carry and how many characters an
/// account may hold, made once at start, and `answer_deadline_ms` how long a connection
/// waits for the store or a map. `maps` and `workers` are the names of the
/// processes the connections ask.
pub type Settings {
  Settings(
    port: Int,
    opened: fn(Int) -> Nil,
    realm_id: Int,
    start: fn(Tables, CharacterCreation) -> Result(Place, Nil),
    customisation: fn(Tables) -> Customisation,
    character_slots: fn(Tables) -> Int,
    clock: fn() -> Int,
    answer_deadline_ms: Int,
    maps: maps.Settings,
    sessions: Name(sessions.Message),
    workers: store_worker.Workers,
  )
}

/// Settings for a game listener on `port` whose maps register with the
/// snapshot process named `snapshot`: names of their own made here, the
/// measured heap ceilings, the system clock and `answer_deadline_ms` for an
/// answer; the port reports nothing when it opens.
pub fn settings(
  port port: Int,
  realm_id realm_id: Int,
  start start: fn(Tables, CharacterCreation) -> Result(Place, Nil),
  snapshot snapshot: Name(snapshot.Message),
) -> Settings {
  Settings(
    port:,
    opened: fn(_port) { Nil },
    realm_id:,
    start:,
    customisation: customisation.of,
    character_slots: character_slots.hybrid,
    clock: clock.system_filetime,
    answer_deadline_ms:,
    maps: maps.Settings(
      registry: process.new_name("maps"),
      factory: process.new_name("maps_factory"),
      snapshot:,
      heap_limits: heap_limit.measured,
    ),
    sessions: process.new_name("game_sessions"),
    workers: store_worker.Workers(factory: process.new_name("store_workers")),
  )
}

/// The game's subtree as a child of the top supervisor. `pool` is the pool the
/// characters are read through, `tables` the loaded game tables, `session_keys`
/// the hand-off the auth login issues session keys in, and `shutdown` the
/// coordinator the listener and its connections register with.
pub fn supervised(
  settings settings: Settings,
  pool pool: pool.Settings,
  tables tables: Tables,
  session_keys session_keys: Name(handoff.Message(Identity)),
  shutdown shutdown: shutdown.Settings,
) -> supervision.ChildSpecification(Supervisor) {
  let services =
    game_connection.services(game_connection.Settings(
      session_keys:,
      workers: settings.workers,
      db: pool.connection(pool),
      registry: settings.maps.registry,
      sessions: settings.sessions,
      tables:,
      start: settings.start,
      customisation: settings.customisation(tables),
      character_slots: settings.character_slots(tables),
      realm_id: settings.realm_id,
      clock: settings.clock,
      answer_deadline_ms: settings.answer_deadline_ms,
    ))
  static_supervisor.new(static_supervisor.OneForOne)
  |> static_supervisor.restart_tolerance(
    intensity: restart_intensity,
    period: restart_period_seconds,
  )
  |> static_supervisor.add(sessions.supervised(settings.sessions))
  |> static_supervisor.add(maps.supervised(settings.maps))
  |> static_supervisor.add(store_worker.supervised(settings.workers))
  |> static_supervisor.add(listener.supervised(
    listener.Settings(
      ..listener.protocol_settings(
        port: settings.port,
        protocol: game_connection.protocol(services),
        shutdown:,
      ),
      listening: settings.opened,
    ),
  ))
  |> static_supervisor.supervised
}
