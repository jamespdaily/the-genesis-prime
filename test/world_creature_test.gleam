//// Creatures running under the creature supervisor, started by their map as the
//// server's world subtree starts them (`genesis_prime/world_map/creature`,
//// `creature_supervisor`, `creature_registry`). Expected values come from these
//// places.
//// - The failure table of the combat core's design (the Design artifact of issue
////   274, section 5, step C) and the doc comment of `genesis_prime/world_map/creature`:
////   a creature that crashes while shown is `Gone` to the players in the map and
////   its spawn returns after the respawn time as a new unit that is sent to the
////   players who saw the old one; a map run that ends ends its creatures.
//// - The doc comment of `genesis_prime/world_map/creature_registry`: a creature
////   is found by `Creature(map, incarnation, unit_id)` from the moment it is
////   started, and a creature that ended is found no more.
//// - Message 0x262 of a creature (`opcode.0x262.creature`): Creature2 id, stats
////   0 and 10, both factions, the display; the values are the Virtual Battle
////   Beast's (`spawn_support`).
//// Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import character_tables
import event_wait
import genesis_prime/client_connection.{
  type Message, CreatureAppeared, PeerNews, SentByMap, SentByPeer,
}
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/service
import genesis_prime/step.{ConnectionId}
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry.{type MapProcess} as world_map_registry
import genesis_prime/world_map/spawn
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import map_support
import owned_test
import place_support
import spawn_support
import world_support.{type World}

const ship = MapId(world_id: 3460, instance: 0)

/// A deadline a passing test never reaches.
fn deadline() -> Int {
  ask_support.monotonic_ms() + ask_support.event_wait_ms
}

fn started(world: World) -> MapProcess {
  let assert Ok(found) =
    world_map_registry.find_or_start(world.maps, ship, deadline_ms: deadline())
    as "Maps started the map or found it running"
  found
}

/// The process of the creature that is unit `unit_id` in the run, once it runs.
fn creature_pid(
  world world: World,
  run run: MapProcess,
  unit_id unit_id: Int,
) -> Pid {
  let find = fn() {
    creature_registry.find(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id:,
    )
  }
  event_wait.until("the creature was started and joined its address", fn() {
    find() != Error(Nil)
  })
  let assert Ok(pid) = find() as "the creature is found by its address"
  pid
}

/// The join of the connection as a player standing in sight of the creatures, an
/// ask answered with the player's own unit.
fn join(run run: MapProcess, connection connection: Int) -> Int {
  let #(_, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(
        run.subject,
        map.Join(
          connection: ConnectionId(connection),
          character: map_support.character(number: 100 + connection),
          place: place_support.at(
            world_id: 3460,
            world_zone_id: spawn_support.warfare_woods,
            x: 100.0,
            y: 0.0,
            z: 0.0,
          ),
        ),
        reply,
      )
    })
  let assert map.Joined(unit:, ..) = answer as "the map answered the join"
  unit.unit_id
}

/// The next message the connection was sent that `wanted` takes, in the order
/// they came, or fails the test naming `what`.
fn next(
  received received: Subject(Message),
  what what: String,
  wanted wanted: fn(Message) -> Result(a, Nil),
) -> a {
  case process.receive(received, within: ask_support.event_wait_ms) {
    Ok(message) ->
      case wanted(message) {
        Ok(found) -> found
        Error(Nil) -> next(received:, what:, wanted:)
      }
    Error(Nil) -> panic as { "this never arrived in time: " <> what }
  }
}

/// A creature's 0x262 as the connection was sent it, with the unit id it names.
fn appearance(message: Message) -> Result(UnitCreateCreature, Nil) {
  case message {
    SentByPeer(PeerNews(news: CreatureAppeared(unit:), ..)) -> Ok(unit)
    SentByPeer(..)
    | SentByMap(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

pub fn a_creature_is_found_by_its_address_and_sends_its_0x262_to_a_player_in_sight_test() -> Nil {
  use <- owned_test.run(30_000)
  let world =
    world_support.start(
      spawns: [spawn_support.battle_beast(number: 1, x: 0.0)],
      creature_restart_ms: 60_000,
    )
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let creature = next(received:, what: "a creature's 0x262", wanted: appearance)
  assert creature.unit_id == 1
    as "the creature stands under the first unit id of the run"
  assert creature.creature_id == 73_464
    as "it is the spawn's Creature2 row, which the client refuses unless it loaded it"
  assert list.contains(creature.tail.stats, UnitStat(stat_id: 0, value: 52))
    && list.contains(creature.tail.stats, UnitStat(stat_id: 10, value: 1))
    as "stat 0 is Base Health 52.6205 truncated, and stat 10 the level"
  assert creature.tail.faction_id == 1441
    && creature.tail.base_faction_id == 1441
    as "Creature2.factionId in both fields"
  assert creature.tail.display_info_id == 26_565
  let _unused = creature_pid(world:, run:, unit_id: 1)
  Nil
}

pub fn a_killed_creature_is_gone_to_the_players_and_its_spawn_returns_as_a_new_unit_after_the_respawn_time_test() -> Nil {
  use <- owned_test.run(30_000)
  let world =
    world_support.start(
      spawns: [spawn_support.battle_beast(number: 1, x: 0.0)],
      creature_restart_ms: 100,
    )
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let pid = creature_pid(world:, run:, unit_id: first.unit_id)
  process.kill(pid)
  let gone =
    next(
      received:,
      what: "Gone for the creature that was killed",
      wanted: fn(message) {
        case message {
          SentByMap(map.Gone(unit_id:)) -> Ok(unit_id)
          SentByMap(..)
          | SentByPeer(..)
          | client_connection.SentBySessions(..)
          | client_connection.SentByChat(..) -> Error(Nil)
        }
      },
    )
  assert gone == first.unit_id
    as "the map speaks of the unit once its owner has ended"
  let returned =
    next(received:, what: "the returned creature's 0x262", wanted: appearance)
  assert returned.unit_id != first.unit_id && returned.unit_id != player
    as "the spawn returns as a new unit"
  assert returned.creature_id == first.creature_id
    as "it is the spawn's creature"
}

pub fn a_map_run_that_ends_ends_its_creatures_test() -> Nil {
  use <- owned_test.run(30_000)
  let world =
    world_support.start(
      spawns: [
        spawn_support.battle_beast(number: 1, x: 0.0),
        spawn_support.battle_beast(number: 2, x: 100.0),
      ],
      creature_restart_ms: 60_000,
    )
  let run = started(world)
  let first = creature_pid(world:, run:, unit_id: 1)
  let second = creature_pid(world:, run:, unit_id: 2)
  let ended = process.monitor(run.pid)
  process.kill(run.pid)
  let _reason = ask_support.ended(ended)
  event_wait.until("both creatures ended with their run", fn() {
    !process.is_alive(first) && !process.is_alive(second)
  })
  event_wait.until("neither creature is found any more", fn() {
    creature_registry.find(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id: 1,
    )
    == Error(Nil)
    && creature_registry.find(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id: 2,
    )
    == Error(Nil)
  })
}

/// The most a map's start may take with this world's spawns, in milliseconds.
/// A map starts its creatures one by one inside its own start, which Maps waits
/// for (an actor's start may take 5000 ms). This world's 54 spawns took 1 ms, the
/// clock's resolution (three runs on the development machine); the bound is 50
/// ms, about 1% of the 5000, so a world with some two thousand spawns, or a start
/// that costs 50 times what it did, fails here and reopens the choice to start
/// creatures after the map's start (the shell taking `Started` from its own
/// mailbox).
const map_start_bound_ms = 50

pub fn a_map_that_starts_its_creatures_inside_its_own_start_starts_within_the_bound_test() -> Nil {
  use <- owned_test.run(30_000)
  let spawns = spawn.all(character_tables.shared())
  assert list.length(spawns) == 54
    as "the world's spawns are the 27 Battle Beasts and the 27 Daguns"
  let world = world_support.start(spawns:, creature_restart_ms: 60_000)
  let before = ask_support.monotonic_ms()
  let _run = started(world)
  let took = ask_support.monotonic_ms() - before
  assert took < map_start_bound_ms
    as {
      "the map's start with the world's spawns took "
      <> int.to_string(took)
      <> " ms"
    }
}
