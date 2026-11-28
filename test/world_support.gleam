//// A world subtree as the server builds it, for the tests that start maps and
//// their creatures, and the connections that see them: a registry the maps and
//// creatures find their players' connections in, and players' connections that
//// are plain processes handing what they are sent to the test.

import ask_support
import character_tables
import driven_time
import genesis_prime/account_session
import genesis_prime/client_connection.{
  type Message, ForStay, SentByChat, SentBySessions,
}
import genesis_prime/connection/registry.{type Registry}
import genesis_prime/group_registry
import genesis_prime/map/message as map_message
import genesis_prime/server
import genesis_prime/service
import genesis_prime/step.{type Address, Connection, ConnectionId}
import genesis_prime/world_map/creature_registry.{type CreatureRegistry}
import genesis_prime/world_map/creature_supervisor
import genesis_prime/world_map/registry as world_map_registry
import genesis_prime/world_map/spawn.{type Spawn}
import gleam/erlang/process.{type Pid, type Subject}
import gleam/function
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/static_supervisor as supervisor
import gleam/result
import open_wait
import send_gate.{type Gate}
import spawn_support
import supervisor_children

/// A running world: its supervisor, Maps, the creatures' registry, the registry the
/// players' connections are found in and the driven clock its maps and creatures run on.
pub type World {
  World(
    time: driven_time.Time,
    gate: Option(Gate),
    tree: Pid,
    maps: process.Name(world_map_registry.Message),
    creatures: CreatureRegistry,
    creature_supervisor: process.Name(creature_supervisor.CreatureSupervisor),
    connections: Registry(Message),
  )
}

/// The creature processes the creature supervisor runs now.
pub fn creature_pids(world world: World) -> List(Pid) {
  let assert Ok(supervisor) = process.named(world.creature_supervisor)
    as "the creature supervisor runs"
  supervisor_children.in_start_order(supervisor)
}

/// The world `start` makes, with its maps' sends to connections held at a gate the test
/// closes and opens (`send_gate`): the gate is open until the test closes it.
pub fn start_gated(
  time time: driven_time.Time,
  spawns spawns: List(Spawn),
  respawn_ms respawn_ms: Int,
  idle_stop_ms idle_stop_ms: Int,
  sweep_ms sweep_ms: Int,
) -> World {
  started(
    time:,
    spawns:,
    respawn_ms:,
    idle_stop_ms:,
    sweep_ms:,
    gate: Some(send_gate.start()),
  )
}

/// A world whose maps stand a creature at each of the spawns a player sees: the
/// spawns are put in the world's term (World 3460's), a spawn returns
/// `respawn_ms` after its creature crashed, a creature that no player has
/// seen for `idle_stop_ms` stops at the next sweep, and the sweep runs every
/// `sweep_ms`. Its maps and creatures take their time from `time`: their
/// timers fire only when the test advances it.
pub fn start(
  time time: driven_time.Time,
  spawns spawns: List(Spawn),
  respawn_ms respawn_ms: Int,
  idle_stop_ms idle_stop_ms: Int,
  sweep_ms sweep_ms: Int,
) -> World {
  started(time:, spawns:, respawn_ms:, idle_stop_ms:, sweep_ms:, gate: None)
}

fn started(
  time time: driven_time.Time,
  spawns spawns: List(Spawn),
  respawn_ms respawn_ms: Int,
  idle_stop_ms idle_stop_ms: Int,
  sweep_ms sweep_ms: Int,
  gate gate: Option(Gate),
) -> World {
  let maps = process.new_name("maps")
  let connections = registry.new()
  let creatures = creature_registry.new()
  let creature_supervisor = process.new_name("creature_supervisor")
  let key = spawn_support.key_with(spawns:, respawn_ms:)
  let world =
    server.World(
      maps:,
      map_supervisor: process.new_name("map_supervisor"),
      maps_call_ms: ask_support.beyond_the_test_ms,
      maps_reach: function.identity,
      map_shutdown_ms: 1000,
      creatures:,
      map_tells: group_registry.new(label: "map_tells"),
      creature_supervisor:,
      creature_shutdown_ms: 1000,
      idle_stop_ms:,
      sweep_ms:,
      spawns: key,
    )
  let tree =
    supervisor.new(supervisor.RestForOne)
    |> supervisor.restart_tolerance(intensity: 3, period: 10)
    |> supervisor.add(registry.supervised(connections))
  let assert Ok(started) =
    server.add_world(
      tree:,
      world:,
      time: driven_time.service_time(time),
      realm_id: 1,
      tables: character_tables.shared(),
      reach: service.Reach(
        locate: fn(address) { locate(connections:, address:) },
        send: fn(to, outgoing) { send(connections:, gate:, to:, outgoing:) },
        start_creature: fn(_creature) { Error(service.SupervisorNotRunning) },
      ),
    )
    |> supervisor.start
    as "the world tree started"
  process.unlink(started.pid)
  ask_support.guard(started.pid)
  World(
    time:,
    gate:,
    tree: started.pid,
    maps:,
    creatures:,
    creature_supervisor:,
    connections:,
  )
}

/// Stops the world's tree and waits for it to end, as a test that drives its clock
/// does before it returns, while the clock its maps and creatures read still runs
/// (the clock ends with the test).
pub fn stop(world world: World) -> Nil {
  let _reason = ask_support.stop_tree(world.tree)
  Nil
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
  gate gate: Option(Gate),
  to to: Address,
  outgoing outgoing: map_message.Outgoing,
) -> Result(Nil, Nil) {
  case to {
    Connection(connection:) ->
      case gate {
        None -> deliver(connections:, connection:, outgoing:)
        Some(gate) -> {
          send_gate.send(gate:, carry: fn() {
            let _delivered = deliver(connections:, connection:, outgoing:)
            Nil
          })
          Ok(Nil)
        }
      }
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

fn deliver(
  connections connections: Registry(Message),
  connection connection: step.ConnectionId,
  outgoing outgoing: map_message.Outgoing,
) -> Result(Nil, Nil) {
  server.map_message(outgoing:)
  |> result.try(registry.deliver(connections, connection, _))
}

/// The gate the maps' sends to connections pass, of a world made with `start_gated`.
pub fn gate(world world: World) -> Gate {
  let assert Some(gate) = world.gate
    as "the world was started with a gate (`start_gated`)"
  gate
}

/// A process that is the connection with this id until the test ends, and hands
/// the test each message the world sends it, in the order it arrives.
pub fn connection(world world: World, id id: Int) -> Subject(Message) {
  let received = process.new_subject()
  join_connection(world:, id:, handle: process.send(received, _))
  received
}

/// Ends the process that is the connection with this id, as a connection ends that sends
/// no leave, and returns once it has ended.
pub fn end_connection(world world: World, id id: Int) -> Nil {
  let assert Ok(pid) = registry.find(world.connections, ConnectionId(id))
    as "the connection is in the registry"
  let monitor = process.monitor(pid)
  process.kill(pid)
  let _reason =
    ask_support.ended(watched: monitor, what: "the connection to end")
  Nil
}

/// A process that is the connection with this id until the test ends and keeps
/// nothing it is sent, for a test whose player must stay in the world but that
/// reads none of what the world sends: a test body holds each message it is
/// handed until it reads it, and a crowd's frames would fill its mailbox.
pub fn connection_that_keeps_nothing(world world: World, id id: Int) -> Nil {
  join_connection(world:, id:, handle: fn(_message) { Nil })
}

fn join_connection(
  world world: World,
  id id: Int,
  handle handle: fn(Message) -> Nil,
) -> Nil {
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
      handle_each(selector:, handle:)
    })
  open_wait.received(from: ready, what: "the connection to join the registry")
}

/// Everything the world sent the connection `id` (the one `connection` made, whose messages
/// `received` holds) before this call, in the order it came. The clock's participants are
/// quiet first, so a message a creature told its map has been relayed by it. A marker then goes
/// to the connection through the registry and the forwarding process hands it to the test after
/// every message it held, so what comes back before the marker is all that was sent: a check
/// that expects nothing inspects this batch, never a read that returns when no message is
/// waiting yet.
pub fn sent_before_the_marker(
  world world: World,
  id id: Int,
  received received: Subject(Message),
) -> List(Message) {
  driven_time.wait_until_quiet(world.time)
  let assert Ok(Nil) =
    registry.deliver(
      registry: world.connections,
      connection: ConnectionId(id),
      message: SentBySessions(message: account_session.Claimed),
    )
    as "the connection is a member of the registry"
  until_the_marker(received:, before: [])
}

fn until_the_marker(
  received received: Subject(Message),
  before before: List(Message),
) -> List(Message) {
  case
    open_wait.received(
      from: received,
      what: "the marker sent through the connection to come back",
    )
  {
    SentBySessions(message: account_session.Claimed) -> list.reverse(before)
    SentBySessions(message: account_session.TakenOver) as other
    | ForStay(..) as other
    | SentByChat(..) as other ->
      until_the_marker(received:, before: [other, ..before])
  }
}

fn handle_each(
  selector selector: process.Selector(Message),
  handle handle: fn(Message) -> Nil,
) -> Nil {
  handle(process.selector_receive_forever(selector))
  handle_each(selector:, handle:)
}
