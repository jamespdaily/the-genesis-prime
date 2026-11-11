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
import cast_support
import character_tables
import driven_time
import event_wait
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{
  type Message, CreatureAppeared, ForStay, PeerNews, SentByMap, SentByPeer,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/cast
import genesis_prime/game/hit.{Blow, Offence, Rolls}
import genesis_prime/game/spell_plan
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell.{Answered, Key, Landed, Strike}
import genesis_prime/message/buyback_list.{BuybackList}
import genesis_prime/message/float32
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_dialog_open.{UnitDialogOpen}
import genesis_prime/message/unit_position_command
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/vendor_items
import genesis_prime/server
import genesis_prime/service
import genesis_prime/step.{ConnectionId}
import genesis_prime/store.{type Character, Character}
import genesis_prime/table/id.{Creature2Id, Spell4BaseId}
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/map
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/registry.{type MapProcess} as world_map_registry
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/erlang/process.{type Pid, type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/set
import map_support
import open_wait
import owned_test
import place_support
import quest_support
import rating_support
import spawn_support
import vendor_support
import world_support.{type World}

const ship = MapId(world_id: 3460, instance: 0)

fn started(world: World) -> MapProcess {
  let assert Ok(found) =
    open_wait.named("Maps to answer the find", fn() {
      world_map_registry.find_or_start(
        world.maps,
        ship,
        deadline_ms: ask_support.deadline_far_beyond_the_tests_deadline(),
      )
    })
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
  join_at(
    run:,
    connection:,
    character: map_support.character(number: 100 + connection),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: spawn_support.warfare_woods,
      x: 100.0,
      y: 0.0,
      z: 0.0,
    ),
  )
}

/// The join of the connection as a player standing at `place`.
fn join_at(
  run run: MapProcess,
  connection connection: Int,
  character character: Character,
  place place: Place,
) -> Int {
  let #(_, answer) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(
        run.subject,
        map.Join(
          connection: ConnectionId(connection),
          character:,
          place:,
          stay: map_support.stay(count: 1),
          alive: True,
          hidden: set.new(),
        ),
        reply,
      )
    })
  let assert map.Joined(unit:, ..) = answer as "the map answered the join"
  unit.unit_id
}

/// The next message the connection was sent that `wanted` takes, in the order
/// they came. The wait has no limit of its own: a message that never comes keeps
/// the test waiting past its deadline, which warns and names `what`.
fn next(
  received received: Subject(Message),
  what what: String,
  wanted wanted: fn(Message) -> Result(a, Nil),
) -> a {
  open_wait.named("this to arrive: " <> what, fn() { taken(received:, wanted:) })
}

fn taken(
  received received: Subject(Message),
  wanted wanted: fn(Message) -> Result(a, Nil),
) -> a {
  case wanted(process.receive_forever(received)) {
    Ok(found) -> found
    Error(Nil) -> taken(received:, wanted:)
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

/// A world of one Battle Beast at x 0 whose maps and creatures take their time from
/// `time`, so a timer fires only when the test advances it.
fn one_beast_timed(
  time time: driven_time.Time,
  respawn_ms respawn_ms: Int,
  idle_stop_ms idle_stop_ms: Int,
) -> World {
  world_support.start_timed(
    time: driven_time.service_time(time),
    spawns: [spawn_support.battle_beast(number: 1, x: 0.0)],
    respawn_ms:,
    idle_stop_ms:,
    sweep_ms:,
  )
}

/// The connection is told the creature it saw is out of its sight (0x355). The map
/// sends it in the step that took the player's move, so the map has by then taken
/// the move and read the clock for it.
fn left_sight(received received: Subject(Message), what what: String) -> Nil {
  next(received:, what:, wanted: fn(message) {
    case message {
      ForStay(
        sent: SentByPeer(PeerNews(news: client_connection.Removed, ..)),
        ..,
      ) -> Ok(Nil)
      ForStay(..)
      | client_connection.SentBySessions(..)
      | client_connection.SentByChat(..) -> Error(Nil)
    }
  })
}

/// What the connection was sent that a wait for a strike's answer takes: a
/// creature's 0x262 or the answer itself.
type Heard {
  Appeared(UnitCreateCreature)
  Answer(strike_tell.Outcome)
}

/// The outcome of the creature's answer to strike `cast_id`, as the connection was
/// sent it, and the creatures' 0x262s the connection was sent before it, in the
/// order they came.
fn answer_to_strike(
  received received: Subject(Message),
  cast_id cast_id: Int,
) -> #(List(UnitCreateCreature), strike_tell.Outcome) {
  open_wait.named("the answer to strike " <> int.to_string(cast_id), fn() {
    answer_after(received:, cast_id:, appeared: [])
  })
}

fn answer_after(
  received received: Subject(Message),
  cast_id cast_id: Int,
  appeared appeared: List(UnitCreateCreature),
) -> #(List(UnitCreateCreature), strike_tell.Outcome) {
  case taken(received:, wanted: heard(_, cast_id)) {
    Appeared(unit) ->
      answer_after(received:, cast_id:, appeared: [unit, ..appeared])
    Answer(outcome) -> #(list.reverse(appeared), outcome)
  }
}

fn heard(message: Message, cast_id: Int) -> Result(Heard, Nil) {
  case answer_to(message, cast_id) {
    Ok(outcome) -> Ok(Answer(outcome))
    Error(Nil) -> result.map(appearance(message), Appeared)
  }
}

/// The outcome of the creature's answer to strike `cast_id`, when the message is
/// that answer.
fn answer_to(
  message: Message,
  cast_id: Int,
) -> Result(strike_tell.Outcome, Nil) {
  case message {
    ForStay(sent: client_connection.SentByTarget(answered:), ..)
      if answered.key.cast_id == cast_id
    -> Ok(answered.outcome)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
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
  let time = driven_time.new()
  let world = one_beast_timed(time:, respawn_ms: 60_000, idle_stop_ms:)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let first_pid = creature_pid(world:, run:, unit_id: first.unit_id, life: 2)
  move_to(run:, connection: 1, x: far)
  left_sight(received:, what: "the creature's 0x355 when the player left sight")
  driven_time.advance(time:, ms: idle_stop_ms)
  let _stopped =
    ask_support.ended(
      watched: process.monitor(first_pid),
      what: "the creature stopped after the idle stop",
    )
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
  world_support.stop(world:)
}

pub fn a_dead_creature_comes_back_exactly_at_its_respawn_test() -> Nil {
  use <- owned_test.run(30_000)
  let respawn_ms = 1000
  let time = driven_time.new()
  let world = one_beast_timed(time:, respawn_ms:, idle_stop_ms:)
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
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  let #(_, outcome) = answer_to_strike(received:, cast_id: 1)
  let assert Landed(descriptions: [description], controls: []) = outcome
  assert description.damage.killed == 1
    as "the 60 damage takes the Beast's 52 health to 0"
  // The answer is sent before the corpse timer starts: the clock moves only after
  // the creature has taken the strike whole.
  driven_time.settled(pid)
  driven_time.advance(time:, ms: respawn_ms - 1)
  strike_with(
    world:,
    run:,
    unit_id: first.unit_id,
    life: 2,
    damage_type: 3,
    damage: 1,
    cast_id: 2,
  )
  assert answer_to_strike(received:, cast_id: 2)
    == #([], strike_tell.Refused(why: strike_tell.Dead))
    as "1 ms before the respawn time the creature is still dead: it refuses a strike and shows no creature standing"
  driven_time.advance(time:, ms: 1)
  strike_with(
    world:,
    run:,
    unit_id: first.unit_id,
    life: 2,
    damage_type: 3,
    damage: 1,
    cast_id: 3,
  )
  let #(appeared, outcome) = answer_to_strike(received:, cast_id: 3)
  let assert [again] = appeared
    as "the creature stood again, once, before it answered the strike"
  assert again.unit_id == first.unit_id
    && list.contains(
      again.tail.stats,
      unit_fields.integer_stat(stat_id: 0, value: 52),
    )
    as "death.creature_respawn: the same unit id at full health, at the respawn time"
  let assert Landed(..) = outcome
    as "at the respawn time the creature stands and a strike lands"
  world_support.stop(world:)
}

pub fn a_creature_stops_at_the_first_sweep_at_or_after_its_idle_limit_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let world = one_beast_timed(time:, respawn_ms: 60_000, idle_stop_ms:)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let pid = creature_pid(world:, run:, unit_id: first.unit_id, life: 2)
  move_to(run:, connection: 1, x: far)
  left_sight(received:, what: "the creature's 0x355 when the player left sight")
  // The sweeps at 20, 40, 60 and 80 ms find it idle for less than the idle stop;
  // the sweep at 100 ms is the first at or after it, and lands on exactly the idle
  // stop only because 100 is a multiple of the 20 ms sweep.
  driven_time.advance(time:, ms: idle_stop_ms - 1)
  assert process.is_alive(pid)
    as "1 ms before the idle stop the creature is running"
  driven_time.advance(time:, ms: 1)
  assert !process.is_alive(pid)
    as "after the idle stop the creature is told to retire and has stopped"
  world_support.stop(world:)
}

pub fn a_map_sweeps_exactly_at_its_sweep_time_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  // An idle stop of 0 ms: a creature no player sees is idle long enough for the
  // first sweep, so what the sweep does shows when it runs.
  let world = one_beast_timed(time:, respawn_ms: 60_000, idle_stop_ms: 0)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let pid = creature_pid(world:, run:, unit_id: first.unit_id, life: 2)
  move_to(run:, connection: 1, x: far)
  left_sight(received:, what: "the creature's 0x355 when the player left sight")
  driven_time.advance(time:, ms: sweep_ms - 1)
  assert process.is_alive(pid)
    as "1 ms before the sweep time the map has not retired the idle creature"
  driven_time.advance(time:, ms: 1)
  assert !process.is_alive(pid)
    as "at the sweep time the map retires the idle creature"
  world_support.stop(world:)
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
  let _reason =
    ask_support.ended(watched: ended, what: "the run to end when killed")
  let _first_ended =
    ask_support.ended(
      watched: process.monitor(first),
      what: "the first creature ended with its run",
    )
  let _second_ended =
    ask_support.ended(
      watched: process.monitor(second),
      what: "the second creature ended with its run",
    )
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
  let _reason = ask_support.ended(watched: ended, what: "the killed run to end")
  event_wait.until("every creature the map started has ended", fn() {
    world_support.creature_pids(world) == []
  })
}

/// The strike of connection 1 on the Beast `unit_id` with one blow of `damage` of
/// `damage_type` (1 Physical, 2 Tech, 3 Magic) and no luck, told through the registry
/// as a caster's connection tells it.
fn strike_with(
  world world: World,
  run run: MapProcess,
  unit_id unit_id: Int,
  life life: Int,
  damage_type damage_type: Int,
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
                damage_type:,
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
    damage_type: 3,
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
  let respawn_ms = 1000
  let time = driven_time.new()
  let world = one_beast_timed(time:, respawn_ms:, idle_stop_ms:)
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
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  // The corpse timer starts once the creature has taken the strike whole; the clock
  // moves only after.
  driven_time.settled(pid)
  move_to(run:, connection: 1, x: far)
  left_sight(received:, what: "the corpse's 0x355 when the player left sight")
  // The sweeps retire it at the idle stop, 100 ms after the player left sight.
  driven_time.advance(time:, ms: respawn_ms - 1)
  assert process.is_alive(pid)
    as "a dead creature told to retire keeps its corpse and its respawn: the creature process lives until the respawn time (genesis_prime/world_map/creature), well after the player's 0x355 and the idle stop of 100 ms"
  driven_time.advance(time:, ms: 1)
  assert !process.is_alive(pid) as "the dead creature stopped at its respawn"
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
  world_support.stop(world:)
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

// ---- a property modifier a player's cast puts on a creature ----

/// Medic Fissure's proxy spell, Spell4 41844: one Proxy row aimed at the area
/// (targetFlags 4, effectType 26) that starts Spell4 41886 on each unit the go hit
/// (`table_rows -- Spell4Effects dataBits00=41886`). The child's one row is
/// Spell4Effects 94370: a UnitPropertyModifier of property 160 (Damage Taken
/// Multiplier Tech) aimed at the cast's target (targetFlags 2), delay 0, duration
/// 8000, mode 2, dataBits02 1_066_192_077 (`table_rows -- Spell4Effects 94370`). No
/// plan holds the spell yet (plans cover level-1 trees), so it is planned on its own
/// from the client's rows and put in the bag slot of Spell4Base 3, which index 11 of
/// the caster's bag names.
const fissure_proxy = 41_844

/// dataBits02 of Spell4Effects 94370, the bits of the multiplier 1.1.
const fissure_bits = 1_066_192_077

const tech_taken_property = 160

const tech = 2

fn fissure_plans() -> spell_plan.Plans {
  let tables = fixture_tables.shared()
  let assert Ok(planned) =
    spell_plan.spell_alone(
      tables:,
      sources: spell_plan.sources_of(tables:),
      spell4_id: fissure_proxy,
      chain: [],
    )
    as "Fissure's proxy spell plans on its own from the client's rows"
  cast_support.plans_of([
    spell_plan.Spell(..planned, spell4_base_id: Spell4BaseId(3)),
  ])
}

/// What the connection's shell does with the cast rule's effects on a creature
/// (`genesis_prime/game/connection/casting`): the same tell, through the server's own
/// `tell_creature`, which names the creature by its address and takes the request as
/// the creature's message.
fn tell_change(
  world world: World,
  run run: MapProcess,
  connection connection: Int,
  effect effect: cast.Effect,
) -> client_connection.TargetChange {
  let #(unit_id, life, change) = case effect {
    cast.TargetChangeStarts(unit_id:, life:, struck_at_ms:, source:, modifier:) -> #(
      unit_id,
      life,
      client_connection.ChangeStarts(source:, modifier:, struck_at_ms:),
    )
    cast.TargetChangeEnds(unit_id:, life:, source:) -> #(
      unit_id,
      life,
      client_connection.ChangeEnds(source:),
    )
    cast.Send(..)
    | cast.Tell(..)
    | cast.StartTimer(..)
    | cast.CancelTimer(..)
    | cast.Strike(..)
    | cast.Pay(..)
    | cast.Gain(..)
    | cast.Log(..)
    | cast.CasterChangeStarts(..)
    | cast.CasterChangeEnds(..)
    | cast.Activated(..)
    | cast.StealthChanged(..) -> panic as "not a change of a creature's property"
  }
  let assert Ok(Nil) =
    server.tell_creature(
      creatures: world.creatures,
      to: step.Creature(
        map: ship,
        incarnation: run.incarnation,
        unit_id:,
        life:,
      ),
      request: client_connection.TellTargetChange(
        connection: ConnectionId(connection),
        change:,
      ),
    )
    as "the creature is found by its address and told"
  change
}

/// The entry of a creature's 0x93a for the Tech damage taken multiplier after the
/// change: its default 1.0 as the base, and the row's value while the change starts
/// the modifier.
fn tech_taken(told told: client_connection.TargetChange) -> UnitProperty {
  UnitProperty(
    property_id: tech_taken_property,
    base: float32.to_bits(1.0),
    value: case told {
      client_connection.ChangeStarts(..) -> fissure_bits
      client_connection.ChangeEnds(..) -> float32.to_bits(1.0)
    },
  )
}

/// The properties of a creature's 0x93a as the connection was sent it.
fn properties_changed(message: Message) -> Result(List(UnitProperty), Nil) {
  case message {
    ForStay(
      sent: SentByPeer(PeerNews(
        news: client_connection.PropertiesChanged(properties:),
        ..,
      )),
      ..,
    ) -> Ok(properties)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// The health the strike of `cast_id` took, from its answer to the striker.
fn health_taken(
  received received: Subject(Message),
  cast_id cast_id: Int,
) -> Int {
  let answered =
    next(received:, what: "the answer to the strike", wanted: fn(message) {
      case message {
        ForStay(
          sent: client_connection.SentByTarget(
            answered: Answered(key: Key(cast_id: id, ..), ..) as answered,
          ),
          ..,
        )
          if id == cast_id
        -> Ok(answered)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    })
  let assert Landed(descriptions: [description], controls: []) =
    answered.outcome
  description.damage.health_damage_with_overkill
}

pub fn fissure_on_creature_raises_tech_damage_taken_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 60_000)
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = join(run:, connection: 1)
  let first = next(received:, what: "the creature's 0x262", wanted: appearance)
  let unit_id = first.unit_id
  let _found = creature_pid(world:, run:, unit_id:, life: 2)
  // What the cast rule does with Fissure's debuff on this creature: a go that
  // strikes it starts the row's modifier at once and ends it with the node.
  let struck = [
    cast.Hit(
      unit_id:,
      unit: cast.HitCreature(life: 2, struck_at_ms: 1000),
      descriptions: [],
      controls: [],
    ),
  ]
  let #(state, pressed) =
    cast_support.pressed_raw_in(
      plans: fissure_plans(),
      state: cast.new(),
      caster: cast_support.caster(),
      bag_index: 11,
      target: unit_id,
      at: 1000,
    )
  let #(state, effects) =
    cast_support.answered_by(state:, effects: pressed, at: 1000, struck:)
  let #(_, fired) =
    cast_support.run_timers_striking(state:, effects:, from_ms: 1000, struck:)
  // The cast's changes of the creature in order: the go's own, then each timer's. The
  // proxy's phases (SpellPhase of Spell4 41844) cast the child again, and each cast
  // ends the one before it, so the debuff is held again at each phase's go.
  let changes =
    list.append(
      cast_support.target_changes(effects:),
      list.map(cast_support.target_timeline(fired:), fn(step) { step.1 }),
    )
  let assert [last, ..earlier] = list.reverse(changes)
  let earlier = list.reverse(earlier)
  let assert cast.TargetChangeEnds(..) = last
    as "the cast's last change ends the debuff with its node"
  let assert [cast.TargetChangeStarts(..), ..] = earlier
    as "the first change is the go's own start of the row's modifier"
  // The same Tech blow before, during and after the debuff.
  strike_with(
    world:,
    run:,
    unit_id:,
    life: 2,
    damage_type: tech,
    damage: 10,
    cast_id: 1,
  )
  let plain = health_taken(received:, cast_id: 1)
  list.each(earlier, fn(effect) {
    let told = tell_change(world:, run:, connection: 1, effect:)
    let shown =
      next(
        received:,
        what: "the creature's 0x93a for a change",
        wanted: properties_changed,
      )
    assert shown == [tech_taken(told:)]
      as "a start puts Damage Taken Multiplier Tech at the row's value and an end back at its default 1.0, and no other property changes"
  })
  strike_with(
    world:,
    run:,
    unit_id:,
    life: 2,
    damage_type: tech,
    damage: 10,
    cast_id: 2,
  )
  let raised = health_taken(received:, cast_id: 2)
  let ended = tell_change(world:, run:, connection: 1, effect: last)
  let restored_properties =
    next(
      received:,
      what: "the creature's 0x93a for the end",
      wanted: properties_changed,
    )
  assert restored_properties == [tech_taken(told: ended)]
    as "the last end puts the property back to 1.0"
  strike_with(
    world:,
    run:,
    unit_id:,
    life: 2,
    damage_type: tech,
    damage: 10,
    cast_id: 3,
  )
  let restored = health_taken(received:, cast_id: 3)
  let assert Ok(multiplier) =
    float32.bits(number: fissure_bits) |> result.try(float32.value)
  assert raised == float.round(int.to_float(plain) *. multiplier)
    as "a Tech blow lands at the mitigated amount times the row's multiplier, rounded (hit.taken_by)"
  assert raised > plain
    as "and the raised amount differs from the plain one, so the test can tell"
  assert restored == plain as "after the end the same blow lands as before"
}

pub fn right_click_on_giver_opens_dialog_test() -> Nil {
  use <- owned_test.run(30_000)
  // Dorian Walker (Creature2 74812) stands as a stored spawn 3.0 from the player's
  // edge, within the 6.0 + 3.0 a TalkTo is answered up to (opcode.0x7ea; the edge
  // gap is the distance less the player's hit radius 1.2, Race.hitRadius, and his
  // 1.1, Creature2DisplayInfo 25510). The creature's process sends the news the
  // connection shows him by; the connection answers the client's right-click, 0x7EA
  // with kind 37 (TalkTo) and his unit id, with 0x357 naming that unit
  // (opcode.0x357). The player is an Exile: his faction 171 is level 0 to the
  // Dominion, whom the interaction rule refuses him to (Faction2Relationship 685),
  // and level 10 to the Exile (771).
  let entry = game_connection_support.entry_place()
  let walker_place =
    start_place.moved(
      place: entry,
      x: start_place.x(entry),
      y: start_place.y(entry),
      z: start_place.z(entry) -. { 3.0 +. 1.2 +. 1.1 },
    )
  let world =
    world_support.start(
      spawns: [spawn_support.dorian_walker(number: 1, place: walker_place)],
      respawn_ms: 60_000,
      idle_stop_ms:,
      sweep_ms:,
    )
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let exile =
    Character(
      ..map_support.character(number: 101),
      faction_id: spawn.exile_faction,
    )
  let player = join_at(run:, connection: 1, character: exile, place: entry)
  let #(news, shown) =
    next(received:, what: "Dorian Walker's 0x262", wanted: fn(message) {
      result.map(appearance(message), fn(unit) { #(message, unit) })
    })
  assert shown.creature_id == 74_812
    as "the creature the map showed is Dorian Walker's row"
  assert shown.unit_id != player as "he has a unit id of his own"
  let assert ForStay(stay:, sent:) = news
    as "the map's creature news is a message for a stay"
  let #(state, _) =
    game_connection_support.feed(
      // Walker receives quest 10520, which the player holds Accepted, so the client's
      // marking shows him with a dialog (`0x1405a8d40`).
      state: game_connection_support.in_world_as_exile_holding(quests: [
        quest_support.accepted(10_520, progress: [0, 0, 0, 0, 0]),
      ]),
      event: game_connection_support.for_stay(stay:, sent:),
    )
  let #(_, taken) =
    game_connection_support.interaction_requested(
      state:,
      unit_id: shown.unit_id,
      kind: 37,
    )
  let assert [Frame(message_id: 0x0357, body:)] =
    game_connection_support.written(taken:)
    as "the right-click on the giver is answered with 0x357 alone"
  assert unit_dialog_open.decode(body)
    == Ok(UnitDialogOpen(unit_id: shown.unit_id, field_2: 0))
    as "opcode.0x357: it names the unit the client clicked"
}

pub fn right_click_on_a_vendor_opens_its_window_test() -> Nil {
  use <- owned_test.run(30_000)
  // Supplier Ingavak (Creature2 28739, spawn 10706) is selected from the spawn table's
  // row over the vendor content, so his spawn is a vendor's from that selection and his
  // 0x262 carries create flag 4 (opcode.0x262.vendor_flag). His faction 171, the display
  // 29772 of his display group 32495 and the outfit 9029 of his outfit group 9725 are
  // Creature2 28739's own row, and faction 171 is friendly to an Exile. He stands 3.0
  // from the player's edge, within the 9.0 a vendor request is answered up to
  // (opcode.0x7ea). The connection answers the client's right-click, 0x7EA with kind
  // 0x31 and his unit id, with his stock, 0x90b, then 0xbc (opcode.0x90b, opcode.0xbc).
  let entry = game_connection_support.entry_place()
  let selection =
    spawn.select(
      rows: [
        spawn.Row(
          ..spawn_support.beast_row(number: 10_706),
          creature_id: 28_739,
          display_info_id: 29_772,
          outfit_info_id: 9029,
          faction_id: 171,
          base_faction_id: 171,
        ),
      ],
      tables: character_tables.content_tables(),
      formulas: rating_support.formulas(),
      kinds: spawn_support.kinds(),
      vendors: vendor_support.stocking_items(
        creature_ids: [28_739],
        items: vendor_support.ingavaks_items,
      ),
    )
  assert selection.refusals == [] as "the row passes the spawn checks"
  let assert Ok(spawns) = dict.get(selection.worlds, 3460)
    as "the row starts in world 3460"
  let assert Ok(selected) = dict.get(spawns.by_id, SpawnId(10_706))
    as "the selection starts Supplier Ingavak's row"
  assert selected.vendor
    as "the selection marks the creature that has stock a vendor"
  let place =
    start_place.moved(
      place: entry,
      x: start_place.x(entry),
      y: start_place.y(entry),
      z: start_place.z(entry) -. { 3.0 +. 1.2 +. selected.combat.hit_radius },
    )
  let ingavak = spawn.Spawn(..selected, place:)
  let world =
    world_support.start(
      spawns: [ingavak],
      respawn_ms: 60_000,
      idle_stop_ms:,
      sweep_ms:,
    )
  let run = started(world)
  let received = world_support.connection(world:, id: 1)
  let exile =
    Character(
      ..map_support.character(number: 101),
      faction_id: spawn.exile_faction,
    )
  let player = join_at(run:, connection: 1, character: exile, place: entry)
  let #(news, shown) =
    next(received:, what: "Supplier Ingavak's 0x262", wanted: fn(message) {
      result.map(appearance(message), fn(unit) { #(message, unit) })
    })
  assert shown.unit_id != player
    as "the unit the map showed is the creature, not the joined player"
  assert shown.creature_id == 28_739
    as "the creature the map showed is Supplier Ingavak's row"
  assert shown.tail.create_flags == 4
    as "opcode.0x262.vendor_flag: the vendor mark of a creature that sells"
  let assert ForStay(stay:, sent:) = news
    as "the map's creature news is a message for a stay"
  let #(state, _) =
    game_connection_support.feed(
      state: game_connection_support.in_world_stocking(
        vendors: vendor_support.stocking_items(
          creature_ids: [28_739],
          items: vendor_support.ingavaks_items,
        ),
      ),
      event: game_connection_support.for_stay(stay:, sent:),
    )
  let #(_, taken) =
    game_connection_support.interaction_requested(
      state:,
      unit_id: shown.unit_id,
      kind: 0x31,
    )
  let assert [
    Frame(message_id: 0x090B, body: items),
    Frame(message_id: 0x00BC, body: buyback),
  ] = game_connection_support.written(taken:)
    as "the right-click on the vendor is answered with 0x90b, then 0xbc"
  let assert Ok(window) = vendor_items.decode(items)
    as "the stock is a 0x90b the client's reader reads"
  assert window.unit_id == shown.unit_id
    as "opcode.0x90b: it names the unit the client clicked"
  assert list.length(window.items) == 22 as "Supplier Ingavak sells 22 items"
  assert list.first(window.items) |> result.map(fn(item) { item.entry_id })
    == Ok(12_078)
    as "the first of his page is Small Stimpack"
  assert list.last(window.items) |> result.map(fn(item) { item.entry_id })
    == Ok(13_160)
    as "the last of his page"
  assert window.open == 1 && window.full_list == 1 && window.refuse == 0
    as "opcode.0x90b: the window opens with the full list"
  assert buyback_list.decode(buyback) == Ok(BuybackList(entries: []))
    as "opcode.0xbc: nothing has been sold to the vendor"
}
