//// A world subtree as the server builds it, for the tests that start maps and
//// their creatures, and the connections that see them: a registry the maps and
//// creatures find their players' connections in, and players' connections that
//// are plain processes handing what they are sent to the test.

import ask_support
import character_tables
import genesis_prime/client_connection.{type Message, SentByMap, SentByPeer}
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/server
import genesis_prime/service
import genesis_prime/step.{type Address, Connection, ConnectionId}
import genesis_prime/world_map/creature_registry.{type CreatureRegistry}
import genesis_prime/world_map/map
import genesis_prime/world_map/registry as world_map_registry
import genesis_prime/world_map/spawn.{type Spawn}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/otp/static_supervisor as supervisor

/// A running world: its supervisor, Maps, the creatures' registry and the
/// registry the players' connections are found in.
pub type World {
  World(
    tree: Pid,
    maps: process.Name(world_map_registry.Message),
    creatures: CreatureRegistry,
    connections: Registry(Message),
  )
}

/// A world that stands a creature at each of the spawns, whose spawns return
/// `creature_restart_ms` after their creature ended.
pub fn start(
  spawns spawns: List(Spawn),
  creature_restart_ms creature_restart_ms: Int,
) -> World {
  let maps = process.new_name("maps")
  let connections = registry.new()
  let creatures = creature_registry.new()
  let world =
    server.World(
      maps:,
      map_supervisor: process.new_name("map_supervisor"),
      maps_call_ms: 1000,
      map_shutdown_ms: 1000,
      creatures:,
      creature_supervisor: process.new_name("creature_supervisor"),
      creature_shutdown_ms: 1000,
      creature_restart_ms:,
      spawns:,
    )
  let tree =
    supervisor.new(supervisor.RestForOne)
    |> supervisor.restart_tolerance(intensity: 3, period: 10)
    |> supervisor.add(registry.supervised(connections))
  let assert Ok(started) =
    server.add_world(
      tree:,
      world:,
      realm_id: 1,
      tables: character_tables.shared(),
      reach: service.Reach(
        locate: fn(address) { locate(connections:, address:) },
        send: fn(to, outgoing) { send(connections:, to:, outgoing:) },
        start_creature: fn(_creature) { Error(service.SupervisorNotRunning) },
      ),
      to_connection: fn(connection, news) {
        registry.deliver(connections, connection, SentByPeer(news))
      },
    )
    |> supervisor.start
    as "the world tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  World(tree: started.pid, maps:, creatures:, connections:)
}

fn locate(
  connections connections: Registry(Message),
  address address: Address,
) -> Result(Pid, Nil) {
  case address {
    Connection(connection:) -> registry.find(connections, connection)
    step.Sessions
    | step.HandOff
    | step.Store
    | step.Maps
    | step.Map(..)
    | step.Creature(..)
    | step.CharacterNamed(..)
    | step.ZoneChannel(..) -> Error(Nil)
  }
}

fn send(
  connections connections: Registry(Message),
  to to: Address,
  outgoing outgoing: map.Outgoing,
) -> Result(Nil, Nil) {
  case to {
    Connection(connection:) ->
      registry.deliver(connections, connection, SentByMap(outgoing))
    step.Sessions
    | step.HandOff
    | step.Store
    | step.Maps
    | step.Map(..)
    | step.Creature(..)
    | step.CharacterNamed(..)
    | step.ZoneChannel(..) -> Error(Nil)
  }
}

/// A process that is the connection with this id until the test ends, and hands
/// the test each message the world sends it, in the order it arrives.
pub fn connection(world world: World, id id: Int) -> Subject(Message) {
  let received = process.new_subject()
  let ready = process.new_subject()
  let _pid =
    process.spawn_unlinked(fn() {
      registry.join(world.connections, connection: ConnectionId(id))
      let selector =
        registry.select_delivered(
          world.connections,
          process.new_selector(),
          fn(message) { message },
        )
      process.send(ready, Nil)
      forward(selector:, to: received)
    })
  let assert Ok(Nil) = process.receive(ready, within: ask_support.event_wait_ms)
    as "the connection joined the registry"
  received
}

fn forward(
  selector selector: process.Selector(Message),
  to received: Subject(Message),
) -> Nil {
  process.send(received, process.selector_receive_forever(selector))
  forward(selector:, to: received)
}
