//// Creatures running under the creature supervisor, started by their map when a
//// player first sees their spawn and stopped when no player has for the idle stop
//// (`genesis_prime/world_map/creature`, `creature_supervisor`,
//// `creature_registry`). Expected values come from these places.
//// - The design of the world spawns (the Design artifact of issue 375, sections 3
////   and 6): a creature runs only while a player sees its spawn and up to the idle
////   stop after; it is found by `Creature(map, incarnation, unit_id, life)` from the
////   moment it is started, and not any more once it ended; a spawn stopped and seen
////   again keeps its unit id and shows once; a creature that crashes while seen is
////   `Gone` to the players and its spawn returns as a new unit after the respawn
////   time; a map run that ends ends its creatures.
//// - A creature's life is the number of the watch its map opened on it, from 1 in
////   a run; the first player's connection takes watch 1 (`genesis_prime/world_map/map`
////   `joined_new`), so the first creature a player sees has life 2.
//// - Message 0x262 of a creature (`opcode.0x262.creature`): Creature2 id, stats
////   0 and 10, both factions, the display; the values are the Virtual Battle
////   Beast's of the creature trace (Base Health 52.6205 truncated to 52, level 1,
////   faction 1441, display 26565), as the spawn table's row carries them
////   (`spawn_support`).
//// The idle stop and the sweep are shortened for these tests, so no test waits
//// 60 s. Every wait is for an event, with a deadline a passing test never reaches.

import ask_support
import event_wait
import genesis_prime/client_connection.{
  type Message, CreatureAppeared, ForStay, PeerNews, SentByMap, SentByPeer,
}
import genesis_prime/game/hit.{Blow, Offence, Rolls}
import genesis_prime/game/strike_tell.{Answered, Key, Landed, Strike}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_position_command
import genesis_prime/service
import genesis_prime/step.{ConnectionId}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry.{type MapProcess} as world_map_registry
import genesis_prime/world_map/unit_fields
import gleam/erlang/process.{type Pid, type Subject}
import gleam/int
import gleam/list
import gleam/option.{None}
import map_support
import owned_test
import place_support
import spawn_support
import world_support.{type World}

const ship = MapId(world_id: 3460, instance: 0)

fn started(world: World) -> MapProcess {
  let assert Ok(found) =
    world_map_registry.find_or_start(
      world.maps,
      ship,
      deadline_ms: ask_support.event_wait(),
    )
    as "Maps started the map or found it running"
  found
}

/// The process of the creature that is unit `unit_id` in the run under `life`,
/// once it runs.
fn creature_pid(
  world world: World,
  run run: MapProcess,
  unit_id unit_id: Int,
  life life: Int,
) -> Pid {
  let find = fn() {
    creature_registry.find(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id:,
      life:,
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
          stay: map_support.stay(count: 1),
          alive: True,
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
    ForStay(
      sent: SentByPeer(PeerNews(news: CreatureAppeared(unit:, ..), ..)),
      ..,
    ) -> Ok(unit)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// Short times for a world whose creatures stop: a creature no player has seen
/// for 100 ms stops at the next sweep, every 20 ms.
const idle_stop_ms = 100

const sweep_ms = 20

/// A world of one Battle Beast at x 0 whose creatures stop on the short times.
fn one_beast(respawn_ms respawn_ms: Int) -> World {
  world_support.start(
    spawns: [spawn_support.battle_beast(number: 1, x: 0.0)],
    respawn_ms:,
    idle_stop_ms:,
    sweep_ms:,
  )
}

/// The connection's player moves to `x` in the world, a tell the map takes in
/// the order it takes its other inputs.
fn move_to(run run: MapProcess, connection connection: Int, x x: Float) -> Nil {
  let _sent =
    service.tell_subject(
      run.subject,
      map.Moved(
        connection: ConnectionId(connection),
        place: place_support.at(
          world_id: 3460,
          world_zone_id: spawn_support.warfare_woods,
          x:,
          y: 0.0,
          z: 0.0,
        ),
        seq: 1,
      ),
    )
  Nil
}

/// A world with no stored spawn, whose creatures stop on the short times and
/// whose spawns come back after 100 ms.
fn no_spawns() -> World {
  world_support.start(spawns: [], respawn_ms: 100, idle_stop_ms:, sweep_ms:)
}

/// Far from every spawn the tests stand.
const far = 50_000.0

pub fn a_creature_is_started_when_a_player_sees_its_spawn_found_by_its_address_and_sends_its_0x262_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 60_000)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  assert creature_registry.find(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id: 2,
      life: 2,
    )
    == Error(Nil)
    as "no player sees the spawn yet, so no creature runs"
  let _player = join(run:, connection: 1)
  let creature = next(received:, what: "a creature's 0x262", wanted: appearance)
  assert creature.unit_id == 2
    as "the creature stands under the unit id after the player's, which is 1"
  assert creature.creature_id == 73_464
    as "it is the spawn's Creature2 row, which the client refuses unless it loaded it"
  assert list.contains(
      creature.tail.stats,
      unit_fields.integer_stat(stat_id: 0, value: 52),
    )
    && list.contains(
      creature.tail.stats,
      unit_fields.integer_stat(stat_id: 10, value: 1),
    )
    as "stat 0 is Base Health 52.6205 truncated, and stat 10 the level"
  assert creature.tail.faction_id == 1441
    && creature.tail.base_faction_id == 1441
    as "the spawn's faction and base faction"
  assert creature.tail.display_info_id == 26_565
  let _unused = creature_pid(world:, run:, unit_id: 2, life: 2)
  Nil
}

pub fn a_killed_creature_is_gone_to_the_players_and_its_spawn_returns_as_a_new_unit_after_the_respawn_time_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 100)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let pid = creature_pid(world:, run:, unit_id: first.unit_id, life: 2)
  process.kill(pid)
  let gone =
    next(
      received:,
      what: "Gone for the creature that was killed",
      wanted: fn(message) {
        case message {
          ForStay(sent: SentByMap(map.Gone(unit_id:)), ..) -> Ok(unit_id)
          ForStay(..)
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
    as "the spawn returns as a new unit, since the old id was given up with the Gone"
  assert returned.creature_id == first.creature_id
    as "it is the spawn's creature"
}

pub fn a_creature_stops_after_its_last_viewer_leaves_sight_and_the_spawn_seen_again_keeps_its_unit_id_and_shows_once_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 60_000)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let first_pid = creature_pid(world:, run:, unit_id: first.unit_id, life: 2)
  move_to(run:, connection: 1, x: far)
  event_wait.until("the creature stopped after the idle stop", fn() {
    !process.is_alive(first_pid)
  })
  event_wait.until("the stopped creature is found no more", fn() {
    creature_registry.find(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id: first.unit_id,
      life: 2,
    )
    == Error(Nil)
  })
  move_to(run:, connection: 1, x: 0.0)
  let second =
    next(
      received:,
      what: "the 0x262 of the creature started again",
      wanted: appearance,
    )
  assert second.unit_id == first.unit_id
    as "the spawn keeps its unit id across a clean stop (death.creature_respawn)"
  let _second_pid = creature_pid(world:, run:, unit_id: second.unit_id, life: 3)
  Nil
}

pub fn a_map_run_that_ends_ends_its_creatures_test() -> Nil {
  use <- owned_test.run(30_000)
  let world =
    world_support.start(
      spawns: [
        spawn_support.battle_beast(number: 1, x: 0.0),
        spawn_support.battle_beast(number: 2, x: 100.0),
      ],
      respawn_ms: 60_000,
      idle_stop_ms:,
      sweep_ms:,
    )
  let run = started(world)
  let _player = join(run:, connection: 1)
  let first = creature_pid(world:, run:, unit_id: 2, life: 2)
  let second = creature_pid(world:, run:, unit_id: 3, life: 3)
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
      unit_id: 2,
      life: 2,
    )
    == Error(Nil)
    && creature_registry.find(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id: 3,
      life: 3,
    )
    == Error(Nil)
  })
}

/// How many spawns stand in sight of the joining player: the densest point of the
/// world database holds 2,386 within sight (design 375, section 3). How long a Join
/// with this many takes is measured in the load run (`genesis_prime/load_walk`),
/// not asserted here, where the suite's parallel tests share the machine.
const spawns_in_sight = 2400

/// A world whose one map has `spawns_in_sight` spawns around x 0 in sight of a
/// player standing at x 100.
fn crowded_world() -> World {
  let spawns =
    list.repeat(Nil, spawns_in_sight)
    |> list.index_map(fn(_, index) {
      spawn_support.battle_beast(
        number: index + 1,
        x: int.to_float(index + 1) *. 0.4,
      )
    })
  world_support.start(spawns:, respawn_ms: 60_000, idle_stop_ms:, sweep_ms:)
}

pub fn a_join_with_2400_spawns_in_sight_is_answered_and_every_creature_started_and_found_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = crowded_world()
  let run = started(world)
  let _player = join(run:, connection: 1)
  let _last =
    creature_pid(
      world:,
      run:,
      unit_id: spawns_in_sight + 1,
      life: spawns_in_sight + 1,
    )
  assert list.length(world_support.creature_pids(world)) == spawns_in_sight
    as "a creature runs for each spawn in sight, each found at its address"
}

pub fn a_map_that_ends_while_its_burst_of_starts_runs_ends_every_creature_it_started_test() -> Nil {
  use <- owned_test.run(30_000)
  // Test 16: the Join is answered before its creatures start, so the map is killed
  // as soon as the first creature runs, with the burst of 2,400 starts under way;
  // every creature it did start watches the run and ends with it.
  let world = crowded_world()
  let run = started(world)
  let _player = join(run:, connection: 1)
  event_wait.until("the first creature of the burst runs", fn() {
    world_support.creature_pids(world) != []
  })
  let ended = process.monitor(run.pid)
  process.kill(run.pid)
  let _reason = ask_support.ended(ended)
  event_wait.until("every creature the map started has ended", fn() {
    world_support.creature_pids(world) == []
  })
}

/// The strike of connection 1 on the Beast `unit_id` with one blow of `damage` and no
/// luck, told through the registry as a caster's connection tells it.
fn strike_with(
  world world: World,
  run run: MapProcess,
  unit_id unit_id: Int,
  life life: Int,
  damage damage: Int,
  cast_id cast_id: Int,
) -> Nil {
  let assert Ok(Nil) =
    creature_registry.tell(
      world.creatures,
      map: ship,
      incarnation: run.incarnation,
      unit_id:,
      life:,
      message: creature.Strike(
        tell: Strike(
          key: Key(cast_id:, phase: 0, unit_id:),
          from: step.Connection(ConnectionId(1)),
          offence: Offence(
            blows: [
              Blow(
                spell4_effects_id: 1,
                damage_type: 3,
                damage:,
                delay_ms: 0,
                threat_multiplier: 1.0,
              ),
            ],
            crit_chance: 0.0,
            crit_severity: 1.5,
            strikethrough: 0.0,
          ),
          striker: strike_tell.PlayerStriker(
            unit_id: 1,
            place: place_support.at(
              world_id: 3460,
              world_zone_id: 5967,
              x: 0.0,
              y: 0.0,
              z: 0.0,
            ),
            seq: 1,
            stay: map_support.stay(count: 1),
            rolls: Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
          ),
          controls: [],
        ),
      ),
    )
    as "the creature is found by its address and told"
  Nil
}

pub fn a_creature_struck_dead_is_answered_shown_dead_and_stands_again_after_its_kinds_respawn_time_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 150)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let _found = creature_pid(world:, run:, unit_id: first.unit_id, life: 2)
  strike_with(
    world:,
    run:,
    unit_id: first.unit_id,
    life: 2,
    damage: 60,
    cast_id: 1,
  )
  let answer =
    next(received:, what: "the answer to the strike", wanted: fn(message) {
      case message {
        ForStay(sent: client_connection.SentByTarget(answered:), ..) ->
          Ok(answered)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    })
  let assert Answered(key: Key(cast_id: 1, ..), outcome:) = answer
  let assert Landed(descriptions: [description], controls: []) = outcome
  assert description.damage.killed == 1
    as "the 60 damage takes the Beast's 52 health to 0"
  let again =
    next(
      received:,
      what: "the 0x262 of the creature standing again",
      wanted: appearance,
    )
  assert again.unit_id == first.unit_id
    && list.contains(
      again.tail.stats,
      unit_fields.integer_stat(stat_id: 0, value: 52),
    )
    as "death.creature_respawn: the same unit id, at full health, after the kind's respawn time"
}

pub fn a_creature_struck_dead_and_left_unseen_stops_at_its_respawn_and_the_spawn_seen_again_stands_full_with_its_unit_id_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 1000)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let pid = creature_pid(world:, run:, unit_id: first.unit_id, life: 2)
  strike_with(
    world:,
    run:,
    unit_id: first.unit_id,
    life: 2,
    damage: 60,
    cast_id: 1,
  )
  move_to(run:, connection: 1, x: far)
  next(
    received:,
    what: "the corpse's 0x355 when the player left sight",
    wanted: fn(message) {
      case message {
        ForStay(
          sent: SentByPeer(PeerNews(news: client_connection.Removed, ..)),
          ..,
        ) -> Ok(Nil)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    },
  )
  assert process.is_alive(pid)
    as "a dead creature told to retire keeps its corpse and its respawn: the creature process lives until the respawn time (genesis_prime/world_map/creature), well after the player's 0x355 and the idle stop of 100 ms"
  event_wait.until("the dead creature stopped at its respawn", fn() {
    !process.is_alive(pid)
  })
  move_to(run:, connection: 1, x: 0.0)
  let second =
    next(
      received:,
      what: "the 0x262 of the creature started again",
      wanted: fn(message) {
        case appearance(message) {
          Ok(unit) ->
            case
              list.contains(
                unit.tail.stats,
                unit_fields.integer_stat(stat_id: 0, value: 52),
              )
            {
              True -> Ok(unit)
              False -> Error(Nil)
            }
          Error(Nil) -> Error(Nil)
        }
      },
    )
  assert second.unit_id == first.unit_id
    as "a clean stop keeps the spawn's unit id, and the creature that starts is at full health (the corpse died with its process)"
}

/// The summon of Creature2 `creature_id` by the connection's player, answered
/// with the unit id the creature starts under.
fn summon(
  run run: MapProcess,
  connection connection: Int,
  creature_id creature_id: Int,
) -> Int {
  let #(_, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(
        run.subject,
        map.Summon(
          connection: ConnectionId(connection),
          creature_id: Creature2Id(creature_id),
          level: None,
        ),
        reply,
      )
    })
  let assert map.Summoned(unit_id:) = answer
    as "the map answered the summon: the creature started"
  unit_id
}

pub fn a_summoned_creature_runs_under_the_creature_supervisor_and_sends_its_0x262_at_the_players_place_test() -> Nil {
  use <- owned_test.run(30_000)
  // A summon is rebuilt in the creature's start from the summon the map checked
  // (`server` `spawn_of_start`), so the creature's 0x262 is the Creature2 row's,
  // at the player's place (the join's: x 100, y 0, z 0, whose float32 bits are
  // 1120403456, 0 and 0). The Dagun is Creature2 73465: faction 1442, display
  // 26578 (`spawn_support`, held to the client's rows by `character_tables_test`).
  let world = no_spawns()
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let player = join(run:, connection: 1)
  let unit_id = summon(run:, connection: 1, creature_id: 73_465)
  assert unit_id != player as "the creature has a unit id of its own"
  let creature =
    next(received:, what: "the summoned creature's 0x262", wanted: appearance)
  assert creature.unit_id == unit_id && creature.creature_id == 73_465
    as "the 0x262 is of the creature the answer names"
  assert creature.tail.faction_id == 1442
    && creature.tail.base_faction_id == 1442
    && creature.tail.display_info_id == 26_578
    as "the Creature2 row's faction and the first entry of its display group"
  assert list.contains(
    creature.tail.movement_commands,
    start_movement.Position(unit_position_command.UnitPositionCommand(
      x: 1_120_403_456,
      y: 0,
      z: 0,
      blends: 0,
    )),
  )
    as "it stands where the player does"
  let _pid = creature_pid(world:, run:, unit_id:, life: 2)
  Nil
}

pub fn a_summoned_creature_that_crashes_under_its_supervisor_is_gone_to_the_players_test() -> Nil {
  use <- owned_test.run(30_000)
  // That no creature stands there again is the map rule's (`map_summon_test`):
  // a negative cannot be waited for.
  let world = no_spawns()
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let unit_id = summon(run:, connection: 1, creature_id: 73_465)
  let _first = next(received:, what: "the creature's 0x262", wanted: appearance)
  process.kill(creature_pid(world:, run:, unit_id:, life: 2))
  let gone =
    next(received:, what: "Gone for the summoned creature", wanted: fn(message) {
      case message {
        ForStay(sent: SentByMap(map.Gone(unit_id:)), ..) -> Ok(unit_id)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    })
  assert gone == unit_id
    as "the map speaks of the unit once its owner has ended, as for a stored spawn's"
}
