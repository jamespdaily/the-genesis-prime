//// The game's subtree of the supervision tree: the maps, the workers that
//// carry out character select's commands and the game listener a client is
//// handed to after the login. The maps and the workers start first, so a
//// listener's first client finds them. It is one for one with 3 restarts in 5
//// seconds, like the other subtrees, so a fault that survives three rebuilds
//// stops the subtree and reaches the top. The listener registers with the
//// shutdown coordinator, which stops it accepting and closes its connections
//// in order.

import genesis_prime/character/character.{type Place}
import genesis_prime/character/store_worker
import genesis_prime/database/pool
import genesis_prime/login/account.{type Identity}
import genesis_prime/login/handoff
import genesis_prime/map/maps
import genesis_prime/shutdown
import genesis_prime/table/character_creation.{type CharacterCreation}
import genesis_prime/table/loader/store.{type Tables}
import genesis_prime/telemetry/snapshot
import gleam/erlang/process.{type Name}
import gleam/otp/static_supervisor.{type Supervisor}
import gleam/otp/supervision

/// What the subtree starts with. `port` is the game listener's port, where 0
/// takes a free port, and `opened` is called with the port that is open.
/// `realm_id` is the realm the connections are on, `start` the place a
/// character made from a CharacterCreation row starts at, `clock` the system
/// time as a Windows FILETIME and `answer_deadline_ms` how long a connection
/// waits for the store or a map. `maps` and `workers` are the names of the
/// processes the connections ask.
pub type Settings {
  Settings(
    port: Int,
    opened: fn(Int) -> Nil,
    realm_id: Int,
    start: fn(CharacterCreation) -> Result(Place, Nil),
    clock: fn() -> Int,
    answer_deadline_ms: Int,
    maps: maps.Settings,
    workers: store_worker.Workers,
  )
}

/// Settings for a game listener on `port` whose maps register with the
/// snapshot process named `snapshot`: names of their own made here, the
/// measured heap ceilings, the system clock and a deadline of 5 seconds for an
/// answer, which no measurement chose; the port reports nothing when it opens.
pub fn settings(
  port port: Int,
  realm_id realm_id: Int,
  start start: fn(CharacterCreation) -> Result(Place, Nil),
  snapshot snapshot: Name(snapshot.Message),
) -> Settings {
  todo as "settings of the game subtree"
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
  todo as "the game's subtree"
}
