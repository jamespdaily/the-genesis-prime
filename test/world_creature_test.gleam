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
import attacker_support
import cast_support
import character_tables
import creature_news_support
import crowd_control_support
import driven_time
import event_wait
import fixture_tables
import game_connection_support
import genesis_prime/client_connection.{
  type Message, ForStay, PeerNews, SentByMap, SentByPeer,
}
import genesis_prime/connection/frame.{Frame}
import genesis_prime/game/cast/state as cast_state
import genesis_prime/game/connection/frames
import genesis_prime/game/damage
import genesis_prime/game/forced_move
import genesis_prime/game/hit
import genesis_prime/game/hit_radius
import genesis_prime/game/spell_plan
import genesis_prime/game/spend
import genesis_prime/game/start_place
import genesis_prime/game/strike_tell.{Answered, Key, Landed}
import genesis_prime/game/unit_casts
import genesis_prime/game/world_entry
import genesis_prime/group_registry
import genesis_prime/message/buyback_list.{BuybackList}
import genesis_prime/message/combat_result
import genesis_prime/message/damage_type
import genesis_prime/message/float32
import genesis_prime/message/movement_time.{MovementTime}
import genesis_prime/message/movement_timed_path.{MovementTimedPath}
import genesis_prime/message/relayed_movement
import genesis_prime/message/spell_damage_description
import genesis_prime/message/spell_go
import genesis_prime/message/spell_initial_position.{SpellInitialPosition}
import genesis_prime/message/spell_position.{type SpellPosition, SpellPosition}
import genesis_prime/message/spell_started
import genesis_prime/message/spell_telegraph_position.{SpellTelegraphPosition}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_creature.{type UnitCreateCreature}
import genesis_prime/message/unit_dialog_open.{UnitDialogOpen}
import genesis_prime/message/unit_movement
import genesis_prime/message/unit_position_command
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/vendor_items
import genesis_prime/server
import genesis_prime/service
import genesis_prime/service/shell
import genesis_prime/step.{ConnectionId}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{
  Creature2Id, Spell4BaseId, Spell4EffectsId, Spell4Id,
}
import genesis_prime/table/spell4_effects
import genesis_prime/world_map/creature
import genesis_prime/world_map/creature_faction
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_registry
import genesis_prime/world_map/creature_turn
import genesis_prime/world_map/map
import genesis_prime/world_map/registry.{type MapProcess}
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/unit_fields
import gleam/dict
import gleam/erlang/process.{type Pid, type Subject}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import map_support
import open_wait
import owned_test
import place_support
import planted_table.{Integer}
import quest_support
import rating_support
import spawn_support
import spell_tables
import vendor_support
import world_entry_support
import world_support.{type World}
import world_watch_support

/// A world of one Battle Beast at x 0 whose creatures stop on the short times.
fn one_beast(respawn_ms respawn_ms: Int) -> World {
  world_support.start(
    spawns: [spawn_support.battle_beast(number: 1, x: 0.0)],
    respawn_ms:,
    idle_stop_ms: world_watch_support.idle_stop_ms,
    sweep_ms: world_watch_support.sweep_ms,
  )
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
  case world_watch_support.taken(received:, wanted: heard(_, cast_id)) {
    Appeared(unit) ->
      answer_after(received:, cast_id:, appeared: [unit, ..appeared])
    Answer(outcome) -> #(list.reverse(appeared), outcome)
  }
}

fn heard(message: Message, cast_id: Int) -> Result(Heard, Nil) {
  case world_watch_support.answer_to(message:, cast_id:) {
    Ok(outcome) -> Ok(Answer(outcome))
    Error(Nil) -> result.map(world_watch_support.appearance(message), Appeared)
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
  world_support.start(
    spawns: [],
    respawn_ms: 100,
    idle_stop_ms: world_watch_support.idle_stop_ms,
    sweep_ms: world_watch_support.sweep_ms,
  )
}

/// Far from every spawn the tests stand.
const far = 50_000.0

pub fn a_creature_is_started_when_a_player_sees_its_spawn_found_by_its_address_and_sends_its_0x262_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 60_000)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  assert creature_registry.find(
      world.creatures,
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id: 2,
      life: 2,
    )
    == Error(Nil)
    as "no player sees the spawn yet, so no creature runs"
  let _player = world_watch_support.join(run:, connection: 1)
  let creature =
    world_watch_support.next(
      received:,
      what: "a creature's 0x262",
      wanted: world_watch_support.appearance,
    )
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
  let _unused =
    world_watch_support.creature_pid(world:, run:, unit_id: 2, life: 2)
  Nil
}

pub fn a_killed_creature_is_gone_to_the_players_and_its_spawn_returns_as_a_new_unit_after_the_respawn_time_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 100)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  process.kill(pid)
  let gone =
    world_watch_support.next(
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
    world_watch_support.next(
      received:,
      what: "the returned creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  assert returned.unit_id != first.unit_id && returned.unit_id != player
    as "the spawn returns as a new unit, since the old id was given up with the Gone"
  assert returned.creature_id == first.creature_id
    as "it is the spawn's creature"
}

pub fn a_creature_stops_after_its_last_viewer_leaves_sight_and_the_spawn_seen_again_keeps_its_unit_id_and_shows_once_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms: 60_000,
      idle_stop_ms: world_watch_support.idle_stop_ms,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let first_pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  move_to(run:, connection: 1, x: far)
  world_watch_support.left_sight(
    received:,
    what: "the creature's 0x355 when the player left sight",
  )
  driven_time.advance(time:, ms: world_watch_support.idle_stop_ms)
  let _stopped =
    ask_support.ended(
      watched: process.monitor(first_pid),
      what: "the creature stopped after the idle stop",
    )
  event_wait.until("the stopped creature is found no more", fn() {
    creature_registry.find(
      world.creatures,
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id: first.unit_id,
      life: 2,
    )
    == Error(Nil)
  })
  move_to(run:, connection: 1, x: 0.0)
  let second =
    world_watch_support.next(
      received:,
      what: "the 0x262 of the creature started again",
      wanted: world_watch_support.appearance,
    )
  assert second.unit_id == first.unit_id
    as "the spawn keeps its unit id across a clean stop (death.creature_respawn)"
  let _second_pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: second.unit_id,
      life: 3,
    )
  world_support.stop(world:)
}

pub fn a_dead_creature_comes_back_exactly_at_its_respawn_test() -> Nil {
  use <- owned_test.run(30_000)
  let respawn_ms = 1000
  let time = driven_time.new()
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms:,
      idle_stop_ms: world_watch_support.idle_stop_ms,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  world_watch_support.strike_with(
    world:,
    run:,
    unit_id: first.unit_id,
    life: 2,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  let #(_, outcome) = answer_to_strike(received:, cast_id: 1)
  let assert Landed(
    descriptions: [description],
    controls: [],
    armor_removed: 0,
    gates_passed: [],
  ) = outcome
  assert description.damage.killed == 1
    as "the 60 damage takes the Beast's 52 health to 0"
  // The answer is sent before the corpse timer starts: the advance's barrier waits
  // for the creature to take the strike whole.
  driven_time.advance(time:, ms: respawn_ms - 1)
  world_watch_support.strike_with(
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
  world_watch_support.strike_with(
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
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms: 60_000,
      idle_stop_ms: world_watch_support.idle_stop_ms,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  move_to(run:, connection: 1, x: far)
  world_watch_support.left_sight(
    received:,
    what: "the creature's 0x355 when the player left sight",
  )
  // The sweeps at 20, 40, 60 and 80 ms find it idle for less than the idle stop;
  // the sweep at 100 ms is the first at or after it, and lands on exactly the idle
  // stop only because 100 is a multiple of the 20 ms sweep.
  driven_time.advance(time:, ms: world_watch_support.idle_stop_ms - 1)
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
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms: 60_000,
      idle_stop_ms: 0,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  move_to(run:, connection: 1, x: far)
  world_watch_support.left_sight(
    received:,
    what: "the creature's 0x355 when the player left sight",
  )
  driven_time.advance(time:, ms: world_watch_support.sweep_ms - 1)
  assert process.is_alive(pid)
    as "1 ms before the sweep time the map has not retired the idle creature"
  driven_time.advance(time:, ms: 1)
  assert !process.is_alive(pid)
    as "at the sweep time the map retires the idle creature"
  world_support.stop(world:)
}

/// A world of two Battle Beasts, at x 0 and x 100, whose maps and creatures take
/// their time from `time`.
fn two_beasts_timed(time time: driven_time.Time) -> World {
  world_support.start_timed(
    time: driven_time.service_time(time),
    spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
      spawn_support.battle_beast(number: 2, x: 100.0),
    ],
    respawn_ms: 60_000,
    idle_stop_ms: world_watch_support.idle_stop_ms,
    sweep_ms: world_watch_support.sweep_ms,
  )
}

pub fn a_player_who_stays_keeps_the_creatures_in_sight_running_past_the_idle_stop_and_the_sweep_test() -> Nil {
  use <- owned_test.run(30_000)
  // A map holds a creature for as long as a player's connection sees it: the idle
  // stop counts from the last sight. The connection is registered, so the map's
  // watch on it stays open and the player stays.
  let time = driven_time.new()
  let world = two_beasts_timed(time:)
  let run = world_watch_support.started(world)
  let _received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.creature_pid(world:, run:, unit_id: 2, life: 2)
  let second =
    world_watch_support.creature_pid(world:, run:, unit_id: 3, life: 3)
  driven_time.advance(
    time:,
    ms: world_watch_support.idle_stop_ms + world_watch_support.sweep_ms,
  )
  assert process.is_alive(first) && process.is_alive(second)
    as "the player stays in sight of both creatures, so no sweep retires either"
  world_support.stop(world:)
}

pub fn a_map_run_that_ends_ends_its_creatures_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let world = two_beasts_timed(time:)
  let run = world_watch_support.started(world)
  let _received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.creature_pid(world:, run:, unit_id: 2, life: 2)
  let second =
    world_watch_support.creature_pid(world:, run:, unit_id: 3, life: 3)
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
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id: 2,
      life: 2,
    )
    == Error(Nil)
    && creature_registry.find(
      world.creatures,
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id: 3,
      life: 3,
    )
    == Error(Nil)
  })
  world_support.stop(world:)
}

/// How many spawns stand in sight of the joining player: the densest point of the
/// world database holds 2,386 within sight (design 375, section 3). How long a Join
/// with this many takes is measured in the load run (`genesis_prime/load_walk`),
/// not asserted here, where the suite's parallel tests share the machine.
const spawns_in_sight = 2400

/// A world whose one map has `spawns_in_sight` spawns around x 0 in sight of a
/// player standing at x 100, on the driven clock `time`.
fn crowded_world(time time: driven_time.Time) -> World {
  let spawns =
    list.repeat(Nil, spawns_in_sight)
    |> list.index_map(fn(_, index) {
      spawn_support.battle_beast(
        number: index + 1,
        x: int.to_float(index + 1) *. 0.4,
      )
    })
  world_support.start_timed(
    time: driven_time.service_time(time),
    spawns:,
    respawn_ms: 60_000,
    idle_stop_ms: world_watch_support.idle_stop_ms,
    sweep_ms: world_watch_support.sweep_ms,
  )
}

pub fn a_join_with_2400_spawns_in_sight_is_answered_and_every_creature_started_and_found_test() -> Nil {
  use <- owned_test.run(30_000)
  let time = driven_time.new()
  let world = crowded_world(time:)
  let run = world_watch_support.started(world)
  world_support.connection_that_keeps_nothing(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let _last =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: spawns_in_sight + 1,
      life: spawns_in_sight + 1,
    )
  assert list.length(world_support.creature_pids(world)) == spawns_in_sight
    as "a creature runs for each spawn in sight, each found at its address"
  world_support.stop(world:)
}

pub fn a_map_that_ends_while_its_burst_of_starts_runs_ends_every_creature_it_started_test() -> Nil {
  use <- owned_test.run(30_000)
  // Test 16: the Join is answered before its creatures start, so the map is killed
  // as soon as the first creature runs, with the burst of 2,400 starts under way;
  // every creature it did start watches the run and ends with it.
  let time = driven_time.new()
  let world = crowded_world(time:)
  let run = world_watch_support.started(world)
  world_support.connection_that_keeps_nothing(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  event_wait.until("the first creature of the burst runs", fn() {
    world_support.creature_pids(world) != []
  })
  let ended = process.monitor(run.pid)
  process.kill(run.pid)
  let _reason = ask_support.ended(watched: ended, what: "the killed run to end")
  event_wait.until("every creature the map started has ended", fn() {
    world_support.creature_pids(world) == []
  })
  world_support.stop(world:)
}

/// The blow of Spell4Effects 44477 (spell 26967, `table_rows -- Spell4Effects 44477`) as
/// the player's spell load builds it: effectType 8, targetFlags 2 (the primary target),
/// damageType 2, dataBits00 1065353216 (a multiplier of 1.0), dataBits01 0, and one
/// formula parameter, type 7 (the struck unit's maximum health) at 0.2.
fn max_health_row_blow() -> hit.Amount {
  let base =
    fixture_tables.shared()
    |> spell4_effects.get(id: Spell4EffectsId(96_125))
  let assert Ok(base) = base
    as "the fixture holds a damage row to copy the columns of"
  let row =
    spell4_effects.Spell4Effects(
      ..base,
      id: 44_477,
      effect_type: 8,
      target_flags: 2,
      damage_type: 2,
      tick_time: 0,
      duration_time: 0,
      data_bits00: 1_065_353_216,
      data_bits01: 0,
      parameter_type00: 7,
      parameter_value00: 0.20000000298023224,
      parameter_type01: 0,
      parameter_value01: 0.0,
      parameter_type02: 0,
      parameter_value02: 0.0,
      parameter_type03: 0,
      parameter_value03: 0.0,
    )
  let assert Ok(formula) = damage.formula_of(effect: row)
    as "the multiplier bits are a finite float"
  hit.ByTarget(damage.partial(
    formula:,
    caster: attacker_support.novice_on_itself(),
  ))
}

pub fn a_players_max_health_spell_takes_its_share_of_a_real_creatures_health_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 60_000)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let _found =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  let assert Ok(Nil) =
    creature_registry.tell(
      world.creatures,
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id: first.unit_id,
      life: 2,
      message: world_watch_support.strike_message_of(
        unit_id: first.unit_id,
        damage_type: 2,
        amount: max_health_row_blow(),
        cast_id: 1,
        occasion: strike_tell.AtGo(phase: 0),
      ),
    )
    as "the creature is found by its address and told"
  // 0x140566ad0 case 7 reads the struck unit's maximum health, which the Battle Beast
  // spawns with 52 (`Creature2.73464`, as the 0x262's health stat shows); 0x140565600
  // gives 0 + (0 + 0.2 x 52) x 1.0 = 10.4 of damage, which the strike takes as 10.
  assert list.contains(
    first.tail.stats,
    unit_fields.integer_stat(stat_id: 0, value: 52),
  )
    as "the Beast's maximum health is 52"
  assert health_taken(received:, cast_id: 1) == 10
    as "0.2 of the Beast's maximum health of 52 is 10.4, taken as 10"
}

pub fn a_creature_struck_dead_is_answered_shown_dead_and_stands_again_after_its_kinds_respawn_time_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 150)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let _found =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  world_watch_support.strike_with(
    world:,
    run:,
    unit_id: first.unit_id,
    life: 2,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  let answer =
    world_watch_support.next(
      received:,
      what: "the answer to the strike",
      wanted: fn(message) {
        case message {
          ForStay(sent: client_connection.SentByTarget(answered:), ..) ->
            Ok(answered)
          ForStay(..)
          | client_connection.SentBySessions(..)
          | client_connection.SentByChat(..) -> Error(Nil)
        }
      },
    )
  let assert Answered(key: Key(cast_id: 1, ..), outcome:) = answer
  let assert Landed(
    descriptions: [description],
    controls: [],
    armor_removed: 0,
    gates_passed: [],
  ) = outcome
  assert description.damage.killed == 1
    as "the 60 damage takes the Beast's 52 health to 0"
  let again =
    world_watch_support.next(
      received:,
      what: "the 0x262 of the creature standing again",
      wanted: world_watch_support.appearance,
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
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms:,
      idle_stop_ms: world_watch_support.idle_stop_ms,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  world_watch_support.strike_with(
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
  world_watch_support.left_sight(
    received:,
    what: "the corpse's 0x355 when the player left sight",
  )
  // The sweeps retire it at the idle stop, 100 ms after the player left sight.
  driven_time.advance(time:, ms: respawn_ms - 1)
  assert process.is_alive(pid)
    as "a dead creature told to retire keeps its corpse and its respawn: the creature process lives until the respawn time (genesis_prime/world_map/creature), well after the player's 0x355 and the idle stop of 100 ms"
  driven_time.advance(time:, ms: 1)
  assert !process.is_alive(pid) as "the dead creature stopped at its respawn"
  move_to(run:, connection: 1, x: 0.0)
  let second =
    world_watch_support.next(
      received:,
      what: "the 0x262 of the creature started again",
      wanted: fn(message) {
        case world_watch_support.appearance(message) {
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

pub fn a_restarted_creature_refuses_the_old_lifes_tick_test() -> Nil {
  use <- owned_test.run(30_000)
  let respawn_ms = 1000
  let time = driven_time.new()
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms:,
      idle_stop_ms: world_watch_support.idle_stop_ms,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  world_watch_support.strike_with(
    world:,
    run:,
    unit_id: first.unit_id,
    life: 2,
    damage_type: 3,
    damage: 60,
    cast_id: 1,
  )
  driven_time.settled(pid)
  move_to(run:, connection: 1, x: far)
  world_watch_support.left_sight(
    received:,
    what: "the corpse's 0x355 when the player left sight",
  )
  driven_time.advance(time:, ms: respawn_ms)
  assert !process.is_alive(pid) as "the dead creature stopped at its respawn"
  move_to(run:, connection: 1, x: 0.0)
  let second =
    world_watch_support.next(
      received:,
      what: "the 0x262 of the creature started again",
      wanted: world_watch_support.appearance,
    )
  assert second.unit_id == first.unit_id
  // A cast that struck life 2 ticks on with that life's address: the creature that
  // stands in its place under the same unit id is never told it (step `Creature`: the
  // life tells the two apart), so the cast's round runs to its deadline and the cast
  // stops the unit's ticks (`cast_tick_test`).
  assert creature_registry.tell(
      world.creatures,
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id: first.unit_id,
      life: 2,
      message: world_watch_support.strike_message(
        unit_id: first.unit_id,
        damage_type: 3,
        damage: 18,
        cast_id: 1,
        occasion: strike_tell.AtTick(
          effect_id: Spell4EffectsId(96_125),
          go: 1,
          tick: 2,
        ),
      ),
    )
    == Error(Nil)
    as "no creature of life 2 is left to take the tick"
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
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let player = world_watch_support.join(run:, connection: 1)
  let unit_id = summon(run:, connection: 1, creature_id: 73_465)
  assert unit_id != player as "the creature has a unit id of its own"
  let creature =
    world_watch_support.next(
      received:,
      what: "the summoned creature's 0x262",
      wanted: world_watch_support.appearance,
    )
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
  let _pid = world_watch_support.creature_pid(world:, run:, unit_id:, life: 2)
  Nil
}

pub fn a_summoned_creature_that_crashes_under_its_supervisor_is_gone_to_the_players_test() -> Nil {
  use <- owned_test.run(30_000)
  // That no creature stands there again is the map rule's (`map_summon_test`):
  // a negative cannot be waited for.
  let world = no_spawns()
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let unit_id = summon(run:, connection: 1, creature_id: 73_465)
  let _first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  process.kill(world_watch_support.creature_pid(world:, run:, unit_id:, life: 2))
  let gone =
    world_watch_support.next(
      received:,
      what: "Gone for the summoned creature",
      wanted: fn(message) {
        case message {
          ForStay(sent: SentByMap(map.Gone(unit_id:)), ..) -> Ok(unit_id)
          ForStay(..)
          | client_connection.SentBySessions(..)
          | client_connection.SentByChat(..) -> Error(Nil)
        }
      },
    )
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
  effect effect: cast_state.Effect,
) -> client_connection.TargetChange {
  let #(unit_id, life, change) = case effect {
    cast_state.TargetChangeStarts(
      unit_id:,
      life:,
      struck_at_ms:,
      source:,
      modifier:,
    ) -> #(
      unit_id,
      life,
      client_connection.ChangeStarts(source:, modifier:, struck_at_ms:),
    )
    cast_state.TargetChangeEnds(unit_id:, life:, source:) -> #(
      unit_id,
      life,
      client_connection.ChangeEnds(source:),
    )
    cast_state.ForcedMoveStarts(..)
    | cast_state.CreatureDespawns(..)
    | cast_state.CreatureHoldsUnitStates(..)
    | cast_state.Send(..)
    | cast_state.Tell(..)
    | cast_state.StartTimer(..)
    | cast_state.CancelTimer(..)
    | cast_state.Strike(..)
    | cast_state.Pay(..)
    | cast_state.Gain(..)
    | cast_state.Log(..)
    | cast_state.CasterChangeStarts(..)
    | cast_state.CasterChangeEnds(..)
    | cast_state.Activated(..)
    | cast_state.ShortcutCast(..)
    | cast_state.QuestAdvanced(..)
    | cast_state.TickStrike(..)
    | cast_state.StealthChanged(..) ->
      panic as "not a change of a creature's property"
  }
  let assert Ok(Nil) =
    server.tell_creature(
      creatures: world.creatures,
      to: step.Creature(
        map: world_watch_support.ship,
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
    world_watch_support.next(
      received:,
      what: "the answer to the strike",
      wanted: fn(message) {
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
      },
    )
  let assert Landed(
    descriptions: [description],
    controls: [],
    armor_removed: 0,
    gates_passed: [],
  ) = answered.outcome
  description.damage.health_damage_with_overkill
}

pub fn fissure_on_creature_raises_tech_damage_taken_test() -> Nil {
  use <- owned_test.run(30_000)
  let world = one_beast(respawn_ms: 60_000)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let unit_id = first.unit_id
  let _found = world_watch_support.creature_pid(world:, run:, unit_id:, life: 2)
  // What the cast rule does with Fissure's debuff on this creature: a go that
  // strikes it starts the row's modifier at once and ends it with the node.
  let struck = [
    cast_state.Hit(
      unit_id:,
      unit: cast_state.HitCreature(life: 2, struck_at_ms: 1000),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
  ]
  let #(state, pressed) =
    cast_support.pressed_raw_in(
      plans: fissure_plans(),
      state: cast_state.new(),
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
  let assert cast_state.TargetChangeEnds(..) = last
    as "the cast's last change ends the debuff with its node"
  let assert [cast_state.TargetChangeStarts(..), ..] = earlier
    as "the first change is the go's own start of the row's modifier"
  // The same Tech blow before, during and after the debuff.
  world_watch_support.strike_with(
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
      world_watch_support.next(
        received:,
        what: "the creature's 0x93a for a change",
        wanted: properties_changed,
      )
    assert shown == [tech_taken(told:)]
      as "a start puts Damage Taken Multiplier Tech at the row's value and an end back at its default 1.0, and no other property changes"
  })
  world_watch_support.strike_with(
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
    world_watch_support.next(
      received:,
      what: "the creature's 0x93a for the end",
      wanted: properties_changed,
    )
  assert restored_properties == [tech_taken(told: ended)]
    as "the last end puts the property back to 1.0"
  world_watch_support.strike_with(
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
      idle_stop_ms: world_watch_support.idle_stop_ms,
      sweep_ms: world_watch_support.sweep_ms,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let exile =
    Character(
      ..map_support.character(number: 101),
      faction_id: spawn.exile_faction,
    )
  let player =
    world_watch_support.join_at(
      run:,
      connection: 1,
      character: exile,
      place: entry,
    )
  let #(news, shown) =
    world_watch_support.next(
      received:,
      what: "Dorian Walker's 0x262",
      wanted: fn(message) {
        result.map(world_watch_support.appearance(message), fn(unit) {
          #(message, unit)
        })
      },
    )
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
    == Ok(UnitDialogOpen(unit_id: shown.unit_id, unread_2: 0))
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
      factions: creature_faction.none(),
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
      idle_stop_ms: world_watch_support.idle_stop_ms,
      sweep_ms: world_watch_support.sweep_ms,
    )
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let exile =
    Character(
      ..map_support.character(number: 101),
      faction_id: spawn.exile_faction,
    )
  let player =
    world_watch_support.join_at(
      run:,
      connection: 1,
      character: exile,
      place: entry,
    )
  let #(news, shown) =
    world_watch_support.next(
      received:,
      what: "Supplier Ingavak's 0x262",
      wanted: fn(message) {
        result.map(world_watch_support.appearance(message), fn(unit) {
          #(message, unit)
        })
      },
    )
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

// ---- a thrown creature, seen by a watching client (issue 788) ----

/// The row of Spell4Effects 73826 (spell 36010, "Generic Knockback - 10 m",
/// `table_rows -- Spell4Effects 73826`): targetFlags 2 (the primary target), delayTime 0,
/// kind 4 (away from a unit) in dataBits00, 10.0 m (the bits 1092616192) in dataBits01 and
/// dataBits02, a flight of 375 ms in dataBits03, flags 1 and an apex of 2.0.
fn knockback_row() -> List(planted_table.Cell) {
  spell_tables.effect_row_with(
    id: 99_061,
    effect_type: 3,
    target_flags: 2,
    columns: [
      #("delayTime", Integer(0)),
      #("dataBits00", Integer(4)),
      #("dataBits01", Integer(1_092_616_192)),
      #("dataBits02", Integer(1_092_616_192)),
      #("dataBits03", Integer(375)),
      #("dataBits04", Integer(0)),
      #("dataBits05", Integer(1)),
      #("dataBits06", Integer(1_073_741_824)),
    ],
  )
}

/// The plans where the planted base 3, at bag index 11, throws what the plan reads from
/// that row (`spell_plan.read_row`).
fn knockback_plans() -> spell_plan.Plans {
  let assert Ok(planned) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(effect: knockback_row()),
    )
  let assert [_] =
    spell_plan.payloads(spell: planned, as_kind: spell_plan.as_struck_move)
    as "the plan reads the row as one move of the units a strike hits"
  // A spell cast on the caster has the caster as its primary target, so the throw
  // aimed at the primary target (targetFlags 2) runs in a child a Proxy starts on each
  // unit the parent struck (`ProxyTarget.OnEachStruck`), whose primary target is that unit.
  let knockback =
    cast_support.with_effects(
      spell: cast_support.child(spell4_id: 36_010, base: 21_614),
      kinds: list.map(
        spell_plan.payloads(spell: planned, as_kind: spell_plan.as_struck_move),
        spell_plan.StruckMoveEffect,
      ),
    )
  cast_support.plans_with(
    spell: cast_support.with_effects(
      spell: cast_support.child(spell4_id: 34_355, base: 3),
      kinds: [
        spell_plan.ProxyEffect(
          spell_plan.Proxy(
            effect_id: Spell4EffectsId(99_060),
            delay_ms: 0,
            phase_flags: -1,
            condition: spell_plan.Always,
            tag: spend.always,
            target: spell_plan.OnEachStruck,
            spell: knockback,
            gains: [],
          ),
        ),
      ],
    ),
  )
}

/// The path of a creature's flight as the connection was sent it.
fn flight(message: Message) -> Result(creature_path.Path, Nil) {
  case message {
    ForStay(
      sent: SentByPeer(PeerNews(
        news: client_connection.CreatureMoved(path:),
        ..,
      )),
      ..,
    ) -> Ok(path)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

fn float_of(bits bits: Int) -> Float {
  let assert Ok(value) = float32.bits(number: bits) |> result.try(float32.value)
  value
}

pub fn a_knockback_spell_on_a_creature_shows_its_flight_to_a_watching_client_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms: 60_000,
      idle_stop_ms: world_watch_support.idle_stop_ms,
    )
  let run = world_watch_support.started(world)
  let caster = world_support.connection(world:, id: 1)
  let watcher = world_support.connection(world:, id: 2)
  let _caster_unit = world_watch_support.join(run:, connection: 1)
  let _watcher_unit = world_watch_support.join(run:, connection: 2)
  let first =
    world_watch_support.next(
      received: caster,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let _shown =
    world_watch_support.next(
      received: watcher,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let unit_id = first.unit_id
  let _found = world_watch_support.creature_pid(world:, run:, unit_id:, life: 2)
  // The go that strikes the creature at the clock's time, and what the cast rule tells
  // the creature for it.
  let shell.ServiceTime(clock:, ..) = driven_time.service_time(time)
  let step.Now(monotonic_ms: go_ms, ..) = clock()
  let struck = [
    cast_state.Hit(
      unit_id:,
      unit: cast_state.HitCreature(life: 2, struck_at_ms: go_ms),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
  ]
  let #(state, pressed) =
    cast_support.pressed_raw_in(
      plans: knockback_plans(),
      state: cast_state.new(),
      caster: cast_support.caster(),
      bag_index: 11,
      target: unit_id,
      at: go_ms,
    )
  let #(_, answered) =
    cast_support.answered_each(
      caster: cast_support.caster(),
      state:,
      effects: pressed,
      at: go_ms,
      struck_of: fn(_) { struck },
      rolls: [],
      poses: dict.new(),
    )
  let assert [
    cast_state.ForcedMoveStarts(unit_id: thrown, life:, struck_at_ms:, move:),
  ] = cast_support.throws(effects: list.append(pressed, answered))
    as "the row's delayTime is 0, so the go tells the one creature it hit its throw at once"
  // The client reads the throw's ForcedMove effect from the 0x7f4's target info of the
  // creature it throws (`Spell4Effects.effectType.3`), with the row's delayTime.
  let listed =
    cast_support.frames_of(
      message_id: spell_go.message_id,
      effects: list.append(pressed, answered),
    )
    |> list.flat_map(fn(frame) {
      let assert Ok(decoded) = spell_go.decode(frame.body)
      list.flat_map(decoded.targets, fn(info) {
        list.map(info.effects, fn(effect) {
          #(info.unit_id, effect.spell4_effects_id, effect.delay_ms)
        })
      })
    })
  assert list.contains(listed, #(unit_id, 99_061, 0))
    as "a 0x7f4 lists the throw's row on the creature it throws"
  // The connection's tell, through the server's own `tell_creature`: the draws are
  // the two fractions at 0, and the reference is the caster's place.
  let race_id = map_support.character(number: 101).race_id
  let assert Ok(Nil) =
    server.tell_creature(
      creatures: world.creatures,
      to: step.Creature(
        map: world_watch_support.ship,
        incarnation: run.incarnation,
        unit_id: thrown,
        life:,
      ),
      request: client_connection.TellThrown(
        throw: forced_move.Throw(
          move:,
          draws: forced_move.Draws(distance: 0.0, angle: 0.0),
          reference: forced_move.Reference(
            place: world_watch_support.sight_place(),
            radius: hit_radius.of_playing(
              tables: character_tables.shared(),
              race_id:,
            ),
          ),
        ),
        struck_at_ms:,
      ),
    )
    as "the creature is found by its address and told"
  let path =
    world_watch_support.next(
      received: watcher,
      what: "the creature's flight",
      wanted: flight,
    )
  // The watcher's connection writes it as one 0x638 on the map's clock, which started
  // 5000 ms before the go.
  let #(_, entered) =
    world_entry_support.entry(
      tables: character_tables.shared(),
      character: world_entry_support.character(class: 4, faction: 167, level: 1),
    )
  let entered = world_entry.Entered(..entered, clock_origin_ms: go_ms - 5000)
  let assert Some(Frame(message_id: 0x0638, body:)) =
    frames.path_frame(entered:, unit_id: thrown, path:, face: None)
    as "the flight is one 0x638"
  let assert Ok(movement) = unit_movement.decode(body)
  let assert [
    relayed_movement.Time(MovementTime(time: started)),
    relayed_movement.TimedPath(MovementTimedPath(times:, points:)),
    relayed_movement.MoveAsked(_),
    relayed_movement.StateFlags(_),
  ] = movement.commands
    as "opcode.0x638: kind 0, then kind 3, then the stop (kind 11 and kind 24) that ends any walk"
  assert started == 5000
    as "the flight starts at the go's time on the map's clock"
  assert times == [5000, 5375]
    as "and its last point is the go plus the row's delay 0 plus its dataBits03 375 ms"
  let assert [from, to] = points as "a flight with no arc has its two points"
  let squared = fn(start, end) {
    let gap = float_of(bits: end) -. float_of(bits: start)
    gap *. gap
  }
  let moved =
    float.square_root(
      squared(from.x, to.x) +. squared(from.y, to.y) +. squared(from.z, to.z),
    )
    |> result.unwrap(0.0)
  assert float.loosely_equals(moved, 10.0, tolerating: 0.001)
    as "it ends 10.0 m (dataBits01 and dataBits02) from where it started"
  assert float_of(bits: to.x) <. float_of(bits: from.x)
    as "away from the caster, who stands at x 100 while the creature stands at x 0"
  world_support.stop(world:)
}

pub fn tell_despawn_reaches_the_creature_as_despawn_test() -> Nil {
  use <- owned_test.run(30_000)
  // A stand-in for the creature: the test process joins the address of a creature that
  // does not run (unit 900, life 9), so what the registry delivers to it is what the
  // server's `tell_creature` made of each request. The creature's own reading of the
  // message is the creature rule's.
  let world = one_beast(respawn_ms: 60_000)
  let address =
    step.Creature(
      map: world_watch_support.ship,
      incarnation: 1,
      unit_id: 900,
      life: 9,
    )
  let scope = creature_registry.scope(world.creatures)
  group_registry.join(scope:, group: address, pid: process.self())
  let delivered = fn(request) {
    let assert Ok(Nil) =
      server.tell_creature(creatures: world.creatures, to: address, request:)
      as "the stand-in is found by its address and told"
    let assert service.TellCall(message:) =
      group_registry.select_delivered(
        scope:,
        selector: process.new_selector(),
        mapping: fn(call) { call },
      )
      |> process.selector_receive_forever
    message
  }
  assert delivered(client_connection.TellDespawn(
      delay_ms: 3000,
      struck_at_ms: 900,
      went_at_ms: 1000,
    ))
    == creature.Despawn(delay_ms: 3000, struck_at_ms: 900, went_at_ms: 1000)
    as "a removal is the creature's Despawn, with its delay, the round's time and the go's time"
  let throw =
    forced_move.Throw(
      move: forced_move.Move(
        way: forced_move.Away,
        mover: forced_move.Flight,
        min_distance: 10.0,
        max_distance: 10.0,
        flight_ms: 375,
        gravity: 0.0,
        flags: 1,
        height: 2.0,
      ),
      draws: forced_move.Draws(distance: 0.0, angle: 0.0),
      reference: forced_move.Reference(
        place: world_watch_support.sight_place(),
        radius: 0.5,
      ),
    )
  assert delivered(client_connection.TellThrown(throw:, struck_at_ms: 900))
    == creature.Thrown(throw:, struck_at_ms: 900)
    as "a throw is still the creature's Thrown"
  world_support.stop(world:)
}

pub fn tell_cast_view_reaches_the_creature_as_cast_view_set_and_ends_test() -> Nil {
  use <- owned_test.run(30_000)
  // A stand-in for the creature: the test process joins the address of a creature that
  // does not run (unit 900, life 9), so what the registry delivers to it is what the
  // server's `tell_creature` made of each request.
  let world = one_beast(respawn_ms: 60_000)
  let address =
    step.Creature(
      map: world_watch_support.ship,
      incarnation: 1,
      unit_id: 900,
      life: 9,
    )
  let scope = creature_registry.scope(world.creatures)
  group_registry.join(scope:, group: address, pid: process.self())
  let next_delivered = fn() {
    let assert service.TellCall(message:) =
      group_registry.select_delivered(
        scope:,
        selector: process.new_selector(),
        mapping: fn(call) { call },
      )
      |> process.selector_receive_forever
    message
  }
  let delivered = fn(request) {
    let assert Ok(Nil) =
      server.tell_creature(creatures: world.creatures, to: address, request:)
      as "the stand-in is found by its address and told"
    next_delivered()
  }
  let view =
    unit_casts.CastView(
      caster_unit_id: 21,
      cast_id: cast_state.cast_id(unit_id: 21, number: 1),
      spell4_id: Spell4Id(41_886),
      primary_target: 900,
      gone: True,
      current: False,
      targets: [],
    )
  assert delivered(client_connection.TellCastView(
      connection: ConnectionId(4),
      change: client_connection.ViewSet(view:, struck_at_ms: 900),
    ))
    == creature.CastViewSet(by: ConnectionId(4), view:, struck_at_ms: 900)
    as "a set is the creature's CastViewSet, with the connection that told it and the round's time"
  assert delivered(client_connection.TellCastView(
      connection: ConnectionId(4),
      change: client_connection.ViewEnds(cast_id: view.cast_id),
    ))
    == creature.CastViewEnds(by: ConnectionId(4), cast_id: view.cast_id)
    as "an end is the creature's CastViewEnds"
  let another_life = step.Creature(..address, life: 8)
  assert server.tell_creature(
      creatures: world.creatures,
      to: another_life,
      request: client_connection.TellCastView(
        connection: ConnectionId(4),
        change: client_connection.ViewEnds(cast_id: 1),
      ),
    )
    == Error(Nil)
    as "a tell for a life no creature holds is dropped by the registry"
  assert delivered(client_connection.TellCastView(
      connection: ConnectionId(4),
      change: client_connection.ViewEnds(cast_id: 2),
    ))
    == creature.CastViewEnds(by: ConnectionId(4), cast_id: 2)
    as "and delivers nothing: the next message the stand-in takes is the later life-9 tell"
  world_support.stop(world:)
}

// ---- a despawn a player's cast puts on a creature (issue 793) ----

/// The despawn row the plan reads from planted columns of one of the client's rows
/// (`table_rows -- Spell4Effects 56028 99864 119478`), each aimed at the target
/// (targetFlags 2) and planted under the client's id on the spell tree the plan tests
/// build on, which holds none of them. No Proxy or Proc row of the client's tables starts
/// 30600, so it is a quest spell's row planted for the test, not a route a player has
/// (the aimed shortcut press is the route, `cast_shortcut_test.an_aimed_shortcut_press_despawns_its_target_creature_after_the_go_test`): 56028 (Spell4 30600, "Q5511 Falkrin Whirlwind
/// (Quest Flavor)": delayTime 4000, phaseFlags 1, dataBits04 and dataBits05 1, orderIndex
/// 1), 99864 (Spell4 43559, delayTime 0, every phase) and 119478 (Spell4 50224, delayTime
/// 3000, every phase). 56024, the throw beside 56028, is left out: it is another effect
/// of the spell, whose throw `a_knockback_spell_on_a_creature_shows_its_flight_to_a_watching_client_test`
/// carries through the same processes.
fn despawn_row(
  id id: Int,
  delay_ms delay_ms: Int,
  phase_flags phase_flags: Int,
  columns columns: List(#(String, planted_table.Cell)),
) -> spell_plan.Despawn {
  let assert Ok(planned) =
    spell_tables.planned_strike(
      rows: spell_tables.rows_with_effect(
        effect: spell_tables.effect_row_with(
          id:,
          effect_type: 97,
          target_flags: 2,
          columns: [
            #("delayTime", Integer(delay_ms)),
            #("phaseFlags", Integer(phase_flags)),
            ..columns
          ],
        ),
      ),
    )
  let assert [row] =
    spell_plan.payloads(spell: planned, as_kind: spell_plan.as_despawn)
    as "the plan reads the planted row as one despawn"
  assert row.delay_ms == delay_ms && row.effect_id == Spell4EffectsId(id)
    as "with the row's own delay"
  row
}

/// The effects of the go of a spell with this despawn row, pressed at `struck_at_ms` and
/// answered at `went_at_ms` with the creature `unit_id` the round hit in `life`. The row
/// aimed at the target (targetFlags 2) runs in a child that a Proxy planted by the test
/// starts on each unit the go struck, so its primary target is that unit, as the throw's
/// row does in `a_knockback_spell_on_a_creature_shows_its_flight_to_a_watching_client_test`;
/// no client row starts 30600 so, and an aimed shortcut press gives its pressed unit as
/// the primary target itself (`cast.aimed_in_range`).
fn quest_go(
  row row: spell_plan.Despawn,
  unit_id unit_id: Int,
  life life: Int,
  struck_at_ms struck_at_ms: Int,
  went_at_ms went_at_ms: Int,
) -> List(cast_state.Effect) {
  let #(state, pressed) =
    cast_support.pressed_raw_in(
      plans: cast_support.plans_starting_on_each_struck(
        started: cast_support.with_effects(
          spell: cast_support.child(spell4_id: 30_600, base: 21_614),
          kinds: [spell_plan.DespawnEffect(row)],
        ),
      ),
      state: cast_state.new(),
      caster: cast_support.caster(),
      bag_index: 11,
      target: unit_id,
      at: struck_at_ms,
    )
  let struck = [
    cast_state.Hit(
      unit_id:,
      unit: cast_state.HitCreature(life:, struck_at_ms:),
      descriptions: [],
      controls: [],
      armor_removed: 0,
      ticking: [],
    ),
  ]
  let #(_, answered) =
    cast_support.answered_each(
      caster: cast_support.caster(),
      state:,
      effects: pressed,
      at: went_at_ms,
      struck_of: fn(_) { struck },
      rolls: [],
      poses: dict.new(),
    )
  list.append(pressed, answered)
}

/// What the caster's connection did with one effect of a go.
type Done {
  Wrote(message_id: Int)
  Told(unit_id: Int)
}

/// What the caster's connection does with the go's effects, in their order, as
/// `genesis_prime/game/connection/casting` and the server carry them out: each frame
/// is written, and each removal is told to the creature by its address as
/// `TellDespawn`, through the server's own `tell_creature`. Returns what it did, in
/// order.
fn carried_out(
  world world: World,
  run run: MapProcess,
  effects effects: List(cast_state.Effect),
) -> List(Done) {
  list.flat_map(effects, fn(effect) {
    case effect {
      cast_state.Send(frame:) -> [Wrote(message_id: frame.message_id)]
      cast_state.CreatureDespawns(
        unit_id:,
        life:,
        struck_at_ms:,
        went_at_ms:,
        delay_ms:,
      ) -> {
        let assert Ok(Nil) =
          server.tell_creature(
            creatures: world.creatures,
            to: step.Creature(
              map: world_watch_support.ship,
              incarnation: run.incarnation,
              unit_id:,
              life:,
            ),
            request: client_connection.TellDespawn(
              delay_ms:,
              struck_at_ms:,
              went_at_ms:,
            ),
          )
          as "the creature is found by its address and told"
        [Told(unit_id:)]
      }
      cast_state.Tell(..)
      | cast_state.StartTimer(..)
      | cast_state.CancelTimer(..)
      | cast_state.Strike(..)
      | cast_state.Log(..)
      | cast_state.Pay(..)
      | cast_state.Gain(..)
      | cast_state.CasterChangeStarts(..)
      | cast_state.CasterChangeEnds(..)
      | cast_state.TargetChangeStarts(..)
      | cast_state.TargetChangeEnds(..)
      | cast_state.ForcedMoveStarts(..)
      | cast_state.CreatureHoldsUnitStates(..)
      | cast_state.Activated(..)
      | cast_state.ShortcutCast(..)
      | cast_state.QuestAdvanced(..)
      | cast_state.TickStrike(..)
      | cast_state.StealthChanged(..) -> []
    }
  })
}

/// The quest spell's go on the watched beast, whose round opened at the clock's time and
/// whose go comes 250 ms later, so a delay that ran from the round's opening would
/// remove the beast early. Returns what the connection did.
fn quest_go_on(
  watched watched: world_watch_support.Watched,
  row row: spell_plan.Despawn,
) -> List(Done) {
  let struck_at_ms = world_watch_support.clock_ms(time: watched.time)
  driven_time.advance(time: watched.time, ms: 250)
  let went_at_ms = world_watch_support.clock_ms(time: watched.time)
  assert went_at_ms == struck_at_ms + 250
  let done =
    carried_out(
      world: watched.world,
      run: watched.run,
      effects: quest_go(
        row:,
        unit_id: watched.beast.unit_id,
        life: 2,
        struck_at_ms:,
        went_at_ms:,
      ),
    )
  // The tell is taken before the clock moves, so the timer it starts is due at the go's
  // time plus the delay.
  driven_time.settled(watched.pid)
  done
}

/// A strike of 1 damage on the watched beast, answered to the caster: the 0x262s and the
/// number of removals the caster was sent before the answer, and the answer.
fn probed(
  watched watched: world_watch_support.Watched,
  cast_id cast_id: Int,
) -> #(List(UnitCreateCreature), Int, strike_tell.Outcome) {
  world_watch_support.strike_with(
    world: watched.world,
    run: watched.run,
    unit_id: watched.beast.unit_id,
    life: 2,
    damage_type: 3,
    damage: 1,
    cast_id:,
  )
  world_watch_support.heard_up_to_answer(received: watched.caster, cast_id:)
}

pub fn a_quest_spell_despawns_the_creature_after_its_delay_for_the_caster_and_a_second_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4 30600's despawn row 56028 has delayTime 4000 (`Spell4Effects.effectType.97`); the
  // viewers see the removal as the server's 0x355 (`opcode.0x355`).
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let row =
    despawn_row(id: 56_028, delay_ms: 4000, phase_flags: 1, columns: [
      #("damageType", Integer(2)),
      #("dataBits04", Integer(1)),
      #("dataBits05", Integer(1)),
      #("orderIndex", Integer(1)),
    ])
  let done = quest_go_on(watched:, row:)
  assert list.contains(done, Wrote(message_id: spell_go.message_id))
    && list.contains(done, Told(unit_id: watched.beast.unit_id))
    as "the go is written to the caster and the beast is told, in the go's own step"
  driven_time.advance(time: watched.time, ms: 3999)
  let #(appeared, removals, outcome) = probed(watched:, cast_id: 1)
  assert removals == 0 && appeared == []
    as "nothing is sent to the caster before 4 s after the go"
  let assert Landed(..) = outcome
    as "the creature still stands and takes a strike"
  assert world_watch_support.removals_waiting(received: watched.viewer) == 0
    as "nothing is sent to the second viewer before 4 s after the go"
  driven_time.advance(time: watched.time, ms: 1)
  world_watch_support.left_sight(
    received: watched.caster,
    what: "the caster's removal of the beast",
  )
  world_watch_support.left_sight(
    received: watched.viewer,
    what: "the second viewer's removal",
  )
  let #(_, removals, outcome) = probed(watched:, cast_id: 2)
  assert removals == 0 as "the caster was sent one removal, not two"
  assert outcome == strike_tell.Refused(why: strike_tell.Despawned)
    as "the creature left the field: it refuses a strike as despawned, not dead"
  world_support.stop(world: watched.world)
}

pub fn a_despawn_of_delay_0_reaches_the_caster_after_the_go_frame_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 99864 (Spell4 43559): delayTime 0, the spell's only effect.
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let row = despawn_row(id: 99_864, delay_ms: 0, phase_flags: -1, columns: [])
  let now_ms = world_watch_support.clock_ms(time: watched.time)
  let effects =
    quest_go(
      row:,
      unit_id: watched.beast.unit_id,
      life: 2,
      struck_at_ms: now_ms,
      went_at_ms: now_ms,
    )
  assert list.contains(
    effects,
    cast_state.CreatureDespawns(
      unit_id: watched.beast.unit_id,
      life: 2,
      struck_at_ms: now_ms,
      went_at_ms: now_ms,
      delay_ms: 0,
    ),
  )
    as "the go that hit the beast tells it to leave with the row's delay 0"
  let done = carried_out(world: watched.world, run: watched.run, effects:)
  let told = Told(unit_id: watched.beast.unit_id)
  let #(before, _) = list.split_while(done, fn(one) { one != told })
  assert list.last(before) == Ok(Wrote(message_id: spell_go.message_id))
    as "the connection writes the go's 0x7f4 and then, next, tells the creature to leave"
  assert list.count(done, fn(one) { one == told }) == 1 as "and tells it once"
  // The clock has not moved, so the removal comes at once; the creature is told after the
  // 0x7f4 is written, so the 0x355 can only follow it in the caster's own writes.
  world_watch_support.left_sight(
    received: watched.caster,
    what: "the caster's removal of the beast",
  )
  world_watch_support.left_sight(
    received: watched.viewer,
    what: "the second viewer's removal",
  )
  world_support.stop(world: watched.world)
}

pub fn a_despawn_of_delay_3000_waits_3_seconds_for_every_viewer_test() -> Nil {
  use <- owned_test.run(60_000)
  // Spell4Effects 119478 (Spell4 50224): delayTime 3000, damageType 1, orderIndex 1.
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let row =
    despawn_row(id: 119_478, delay_ms: 3000, phase_flags: -1, columns: [
      #("damageType", Integer(1)),
      #("orderIndex", Integer(1)),
    ])
  let _written = quest_go_on(watched:, row:)
  driven_time.advance(time: watched.time, ms: 2999)
  let #(_, removals, outcome) = probed(watched:, cast_id: 1)
  assert removals == 0 as "no 0x355 reaches the caster at 2999 ms after the go"
  let assert Landed(..) = outcome as "the creature still stands"
  assert world_watch_support.removals_waiting(received: watched.viewer) == 0
    as "none reaches the second viewer at 2999 ms"
  driven_time.advance(time: watched.time, ms: 1)
  world_watch_support.left_sight(
    received: watched.caster,
    what: "the caster's removal at 3000 ms",
  )
  world_watch_support.left_sight(
    received: watched.viewer,
    what: "the viewer's removal at 3000 ms",
  )
  world_support.stop(world: watched.world)
}

pub fn a_despawn_outlives_the_casters_leaving_test() -> Nil {
  use <- owned_test.run(60_000)
  // The creature owns the delay (the Design artifact of issue 793, option A): the caster's
  // connection is not needed after the tell.
  let watched = world_watch_support.watched_by_two(respawn_ms: 60_000)
  let row =
    despawn_row(id: 56_028, delay_ms: 4000, phase_flags: 1, columns: [
      #("orderIndex", Integer(1)),
    ])
  let _written = quest_go_on(watched:, row:)
  let #(_, _left) =
    ask_support.ask_and_wait(send: fn(reply) {
      service.call_subject(
        watched.run.subject,
        map.Leave(connection: ConnectionId(1)),
        reply,
      )
    })
  driven_time.advance(time: watched.time, ms: 3999)
  assert world_watch_support.removals_waiting(received: watched.viewer) == 0
    as "the second viewer is sent nothing before the delay is over"
  driven_time.advance(time: watched.time, ms: 1)
  world_watch_support.left_sight(
    received: watched.viewer,
    what: "the second viewer's removal",
  )
  world_support.stop(world: watched.world)
}

pub fn a_despawned_creature_comes_back_exactly_at_its_respawn_test() -> Nil {
  use <- owned_test.run(60_000)
  // As `a_dead_creature_comes_back_exactly_at_its_respawn_test`, for a creature that left
  // the field by a despawn of delay 0: the kind's respawn time counts from the removal, and
  // the same unit stands again with a fresh 0x262 and no second removal
  // (`death.creature_respawn`).
  let respawn_ms = 1000
  let watched = world_watch_support.watched_by_two(respawn_ms:)
  let row = despawn_row(id: 99_864, delay_ms: 0, phase_flags: -1, columns: [])
  let _written = quest_go_on(watched:, row:)
  world_watch_support.left_sight(
    received: watched.caster,
    what: "the caster's removal of the beast",
  )
  driven_time.advance(time: watched.time, ms: respawn_ms - 1)
  let #(appeared, removals, outcome) = probed(watched:, cast_id: 1)
  assert appeared == []
    && removals == 0
    && outcome == strike_tell.Refused(why: strike_tell.Despawned)
    as "1 ms before the respawn time the creature is still gone: it refuses a strike and shows no creature standing"
  driven_time.advance(time: watched.time, ms: 1)
  let #(appeared, removals, outcome) = probed(watched:, cast_id: 2)
  let assert [again] = appeared
    as "the creature stood again, once, before it answered the strike"
  assert again.unit_id == watched.beast.unit_id
    && list.contains(
      again.tail.stats,
      unit_fields.integer_stat(stat_id: 0, value: 52),
    )
    as "death.creature_respawn: the same unit id at full health, at the respawn time"
  assert removals == 0 as "no second removal came with it"
  let assert Landed(..) = outcome
    as "at the respawn time the creature stands and a strike lands"
  world_support.stop(world: watched.world)
}

pub fn a_creature_that_crashes_with_a_despawn_pending_is_gone_and_returns_new_test() -> Nil {
  use <- owned_test.run(60_000)
  // The map's crash row for a creature (`map.creature_ended`): the players are sent `Gone`
  // and the spawn returns as a new unit after the respawn time, whatever the creature's
  // life was doing. Here the despawn is pending when it crashes, and then the returned
  // creature crashes after it left the field.
  let respawn_ms = 1000
  let watched = world_watch_support.watched_by_two(respawn_ms:)
  let pending =
    despawn_row(id: 56_028, delay_ms: 4000, phase_flags: 1, columns: [
      #("orderIndex", Integer(1)),
    ])
  let _written = quest_go_on(watched:, row: pending)
  process.kill(watched.pid)
  let gone =
    world_watch_support.next(
      received: watched.caster,
      what: "Gone for the creature with a despawn pending",
      wanted: world_watch_support.gone_unit,
    )
  assert gone == watched.beast.unit_id
    as "the map speaks of the unit once its owner has ended"
  // `Gone` is sent before the restart timer starts (`map.waiting_for_restart`): the
  // advance's barrier waits for the map to finish that step.
  driven_time.advance(time: watched.time, ms: respawn_ms)
  let returned =
    world_watch_support.next(
      received: watched.caster,
      what: "the returned creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  assert returned.unit_id != watched.beast.unit_id
    && returned.creature_id == watched.beast.creature_id
    as "the spawn returns as a new unit, which is the spawn's creature"
  // The despawn that was pending is lost with the creature it was told to: the new unit
  // stands past the old due time.
  driven_time.advance(time: watched.time, ms: 4000)
  assert world_watch_support.removals_waiting(received: watched.caster) == 0
    as "the caster is never sent a removal for the returned creature"
  // The returned creature leaves the field by a despawn of delay 0 and then crashes. Its
  // life is the map's next watch, 4: watch 1 is the first player's, 2 the first beast's
  // and 3 the second player's (the module doc, on the map's watches).
  let second =
    world_watch_support.creature_pid(
      world: watched.world,
      run: watched.run,
      unit_id: returned.unit_id,
      life: 4,
    )
  let now_ms = world_watch_support.clock_ms(time: watched.time)
  let _written =
    carried_out(
      world: watched.world,
      run: watched.run,
      effects: quest_go(
        row: despawn_row(id: 99_864, delay_ms: 0, phase_flags: -1, columns: []),
        unit_id: returned.unit_id,
        life: 4,
        struck_at_ms: now_ms,
        went_at_ms: now_ms,
      ),
    )
  world_watch_support.left_sight(
    received: watched.caster,
    what: "the removal of the returned creature",
  )
  driven_time.settled(second)
  process.kill(second)
  let gone =
    world_watch_support.next(
      received: watched.caster,
      what: "Gone for the creature that was despawned",
      wanted: world_watch_support.gone_unit,
    )
  assert gone == returned.unit_id
    as "a despawned creature that crashes is gone to the players as one that stands is"
  driven_time.advance(time: watched.time, ms: respawn_ms)
  let again =
    world_watch_support.next(
      received: watched.caster,
      what: "the 0x262 of the spawn's third creature",
      wanted: world_watch_support.appearance,
    )
  assert again.unit_id != returned.unit_id
    && again.creature_id == watched.beast.creature_id
    as "the spawn returns once more as a new unit"
  world_support.stop(world: watched.world)
}

// A creature's special through its process: a Rootbrute Grimspore's Earthen Roar (Spell4 55317)
// on the client's own rows for Creature2 12212, 13118 and 13549, built as the load builds a
// creature (`spawn_support.special_creature`). The player's connection is the world's subject for
// it, so a message the connection would write is the message it is sent, and every wait is for
// the driven clock.

/// The Rootbrute Grimspore `creature_id` that casts Earthen Roar.
fn roaring_rootbrute(creature_id creature_id: Int) -> spawn.Spawn {
  spawn_support.special_creature(number: 1, creature_id:, spell4_id: 55_317)
}

/// A world of the one creature `creature`, on `time`.
fn roaring_world(
  time time: driven_time.Time,
  creature creature: spawn.Spawn,
) -> World {
  world_support.start_timed(
    time: driven_time.service_time(time),
    spawns: [creature],
    respawn_ms: 60_000,
    idle_stop_ms: 60_000,
    sweep_ms: 60_000,
  )
}

/// A player's strike on the creature from `connection`, standing at `x`, with one blow of
/// `damage`, as a caster's connection tells it.
fn struck_from(
  world world: World,
  run run: MapProcess,
  connection connection: Int,
  unit_id unit_id: Int,
  x x: Float,
  damage damage: Int,
  cast_id cast_id: Int,
) -> Nil {
  struck_with_states(
    world:,
    run:,
    connection:,
    unit_id:,
    x:,
    damage:,
    cast_id:,
    controls: [],
  )
}

/// The same strike carrying these crowd-control states.
fn struck_with_states(
  world world: World,
  run run: MapProcess,
  connection connection: Int,
  unit_id unit_id: Int,
  x x: Float,
  damage damage: Int,
  cast_id cast_id: Int,
  controls controls: List(strike_tell.ControlTell),
) -> Nil {
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id:,
      damage_type: 3,
      damage:,
      cast_id:,
      occasion: strike_tell.AtGo(phase: 0),
    )
  let message =
    creature.Strike(
      tell: strike_tell.Strike(
        ..tell,
        from: step.Connection(ConnectionId(connection)),
        striker: strike_tell.PlayerStriker(
          unit_id: connection * 10,
          place: place_support.at(
            world_id: 3460,
            world_zone_id: 5967,
            x:,
            y: 0.0,
            z: 0.0,
          ),
          seq: 1,
          stay: map_support.stay(count: 1),
          hit_radius: place_support.player_hit_radius,
          rolls: hit.Rolls(crit: 0.5, deflect: 0.5, glance: 0.5),
        ),
        controls:,
      ),
    )
  let assert Ok(Nil) =
    creature_registry.tell(
      world.creatures,
      map: world_watch_support.ship,
      incarnation: run.incarnation,
      unit_id:,
      life: 2,
      message:,
    )
    as "the creature is found by its address and told"
  Nil
}

/// The next cast start the connection was sent, the creature's 0x7ff.
fn next_cast_started(
  received received: Subject(Message),
) -> spell_started.SpellStarted {
  world_watch_support.next(
    received:,
    what: "the creature's 0x7ff",
    wanted: fn(message) {
      case message {
        ForStay(
          sent: SentByPeer(PeerNews(
            news: client_connection.CastStarted(start:),
            ..,
          )),
          ..,
        ) -> Ok(start)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    },
  )
}

/// The next go the connection was sent, the creature's 0x7f4.
fn next_cast_went(received received: Subject(Message)) -> spell_go.SpellGo {
  world_watch_support.next(
    received:,
    what: "the creature's 0x7f4",
    wanted: fn(message) {
      case message {
        ForStay(
          sent: SentByPeer(PeerNews(news: client_connection.CastWent(go:), ..)),
          ..,
        ) -> Ok(go)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    },
  )
}

/// Whether the connection was sent the creature's 0x7fe of `cast_id`.
fn next_cast_finished(
  received received: Subject(Message),
  cast_id cast_id: Int,
) -> Nil {
  world_watch_support.next(
    received:,
    what: "the creature's 0x7fe",
    wanted: fn(message) {
      case message {
        ForStay(
          sent: SentByPeer(PeerNews(
            news: client_connection.CastFinished(cast_id: finished),
            ..,
          )),
          ..,
        )
          if finished == cast_id
        -> Ok(Nil)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    },
  )
}

/// The strike the creature told the connection's player to take: its key.
fn next_strike_told(received received: Subject(Message)) -> strike_tell.Key {
  world_watch_support.next(
    received:,
    what: "the creature's strike",
    wanted: fn(message) {
      case message {
        ForStay(
          sent: client_connection.SentByFoe(strike_tell.Attacks(tell: strike_tell.Strike(
            key:,
            ..,
          ))),
          ..,
        ) -> Ok(key)
        ForStay(..)
        | client_connection.SentBySessions(..)
        | client_connection.SentByChat(..) -> Error(Nil)
      }
    },
  )
}

/// Everything the world sent the connection `id` that a message `wanted` takes, once the
/// marker through the connection has come back (`world_support.sent_before_the_marker`).
fn sent_so_far(
  world world: World,
  id id: Int,
  received received: Subject(Message),
  wanted wanted: fn(Message) -> Result(a, Nil),
) -> List(a) {
  world_support.sent_before_the_marker(world:, id:, received:)
  |> list.filter_map(wanted)
}

/// The cast news of the creature among what the connection has been sent so far.
fn cast_news(message: Message) -> Result(String, Nil) {
  creature_news_support.named_among(names: ["0x7ff", "0x7f4", "0x7fe", "0x7f9"])(
    message,
  )
}

/// The answer of a fighter the strike hit, as its connection's hit rule gives it
/// (genesis_prime/game/player_life): one damage description for the special's damage effect
/// `spell4_effects_id`.
fn hit_answer(
  key key: strike_tell.Key,
  spell4_effects_id spell4_effects_id: Int,
) -> creature.Message {
  creature.StrikeAnswered(answered: Answered(
    key:,
    outcome: Landed(
      descriptions: [
        hit.Description(
          spell4_effects_id:,
          delay_ms: 0,
          damage: spell_damage_description.SpellDamageDescription(
            raw_damage: 21,
            scaled_raw_damage: 21,
            absorbed: 0,
            shield_absorbed: 0,
            health_damage_with_overkill: 21,
            overkill: 0,
            glance: 0,
            killed: 0,
            combat_result: combat_result.Hit,
            damage_type: damage_type.Physical,
            hits: [],
          ),
        ),
      ],
      controls: [],
      armor_removed: 0,
      gates_passed: [],
    ),
  ))
}

/// A world with the roaring creature struck by player 1 (unit 10) standing on it, the
/// player's connection, the creature's process and the clock, with the strike taken.
type Roaring {
  Roaring(
    time: driven_time.Time,
    world: World,
    run: MapProcess,
    received: Subject(Message),
    pid: Pid,
    unit_id: Int,
    damage_effects_id: Int,
  )
}

/// The fight of Earthen Roar, whose damage effect is Spell4Effects 131967.
fn roaring_fight() -> Roaring {
  rootbrute_fight(creature_id: 12_212)
}

/// The fight of Earthen Roar with the Rootbrute Grimspore `creature_id`.
fn rootbrute_fight(creature_id creature_id: Int) -> Roaring {
  fight_of(
    creature: roaring_rootbrute(creature_id:),
    damage_effects_id: 131_967,
    x: 0.0,
  )
}

/// A fight with `creature`, whose special's damage effect is the row `damage_effects_id`.
fn fight_of(
  creature creature: spawn.Spawn,
  damage_effects_id damage_effects_id: Int,
  x x: Float,
) -> Roaring {
  let time = driven_time.new()
  let world = roaring_world(time:, creature:)
  let run = world_watch_support.started(world)
  let received = world_support.connection(world:, id: 1)
  let _player = world_watch_support.join(run:, connection: 1)
  let first =
    world_watch_support.next(
      received:,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: first.unit_id,
      life: 2,
    )
  struck_from(
    world:,
    run:,
    connection: 1,
    unit_id: first.unit_id,
    x:,
    damage: 5,
    cast_id: 1,
  )
  driven_time.settled(pid)
  Roaring(
    time:,
    world:,
    run:,
    received:,
    pid:,
    unit_id: first.unit_id,
    damage_effects_id:,
  )
}

fn answer(roaring roaring: Roaring, key key: strike_tell.Key) -> Nil {
  let assert Ok(Nil) =
    creature_registry.tell(
      roaring.world.creatures,
      map: world_watch_support.ship,
      incarnation: roaring.run.incarnation,
      unit_id: roaring.unit_id,
      life: 2,
      message: hit_answer(key:, spell4_effects_id: roaring.damage_effects_id),
    )
  driven_time.wait_until_quiet(roaring.time)
}

pub fn a_struck_rootbrute_grimspore_casts_earthen_roar_with_a_cast_bar_two_gos_a_hit_and_a_hold_test() -> Nil {
  use <- owned_test.run(90_000)
  // Each of Creature2 12212, 13118 and 13549 (the Rootbrute Grimspores of the Northern Wilds)
  // on the client's own rows. The creature's first attack tick is 1500 ms after the strike (its kind's interval); it
  // chooses the special, whose gos are 2500 and 3000 ms after the cast starts (SpellPhase
  // 11191 and 11192), the second striking (Spell4Effects 131967, phase flag 2); the delay row
  // 131968 holds it 1000 ms.
  list.each([12_212, 13_118, 13_549], fn(creature_id) {
    let roaring = rootbrute_fight(creature_id:)
    driven_time.advance(time: roaring.time, ms: 1500)
    let start = next_cast_started(received: roaring.received)
    assert start.spell4_id == 55_317
      && start.caster_unit_id == roaring.unit_id
      && start.primary_target_unit_id == 10
      as "the cast bar: Earthen Roar, cast on the player that struck it"
    driven_time.advance(time: roaring.time, ms: 2499)
    driven_time.settled(roaring.pid)
    assert sent_so_far(
        world: roaring.world,
        id: 1,
        received: roaring.received,
        wanted: cast_news,
      )
      == []
      as "no go before 2500 ms"
    driven_time.advance(time: roaring.time, ms: 1)
    let first = next_cast_went(received: roaring.received)
    assert first.phase == 0
      && first.targets == []
      && first.cast_id == start.cast_id
      as "the first go, phase 0, names no one"
    driven_time.advance(time: roaring.time, ms: 500)
    let key = next_strike_told(received: roaring.received)
    assert key.occasion == strike_tell.AtGo(phase: 1)
      && key.cast_id == start.cast_id
      && key.unit_id == 10
      as "at 3000 ms the player standing in the cone is told to take the hit"
    answer(roaring:, key:)
    let second = next_cast_went(received: roaring.received)
    assert second.phase == 1
      && list.map(second.targets, fn(target) { target.unit_id }) == [10]
      as "the second go, phase 1, lists the player"
    next_cast_finished(received: roaring.received, cast_id: start.cast_id)
    // The hold: nothing for 999 ms, then the creature's next attack, the instant one, since
    // the special's cooldown (10 000 ms from the cast's start) runs on.
    driven_time.advance(time: roaring.time, ms: 999)
    driven_time.settled(roaring.pid)
    assert sent_so_far(
        world: roaring.world,
        id: 1,
        received: roaring.received,
        wanted: cast_news,
      )
      == []
      as "the creature holds 1000 ms after the strike"
    driven_time.advance(time: roaring.time, ms: 1)
    let next = next_cast_started(received: roaring.received)
    assert next.spell4_id == 5649
      as "then its auto-attack, the special being on cooldown"
    world_support.stop(world: roaring.world)
  })
}

/// The 0x7ff as the client reads it: encoded and decoded by the generated codec.
fn read_by_the_client(
  start start: spell_started.SpellStarted,
) -> spell_started.SpellStarted {
  let assert Ok(body) = spell_started.encode(start)
    as "the cast start's lists fit the wire's counts"
  let assert Ok(read) = spell_started.decode(body)
    as "the client's reader takes the body"
  read
}

pub fn a_viewer_of_a_rootbrute_grimspores_cast_gets_the_positions_the_client_draws_its_cone_from_test() -> Nil {
  use <- owned_test.run(90_000)
  // Earthen Roar's row 7880 has TelegraphDamage flags 0x105000 and targetTypeFlags 1: the client
  // draws it only at a telegraph position of (7880, the caster), found through the caster's
  // initial position (`0x140546e60`, `spell.telegraph_position`). The row has no offset or
  // rotation, so both entries are the creature's own pose, which the 0x7ff's own position and
  // yaw carry (the entries' flags byte is the caster's role bit 1, the anchor 0). Player 2
  // arrives while the cast bar runs and is sent the same positions; the gos and the finish
  // follow, and the hit is by the cone the picture shows: the player on the creature is struck.
  let roaring = roaring_fight()
  let received_2 = world_support.connection(world: roaring.world, id: 2)
  driven_time.advance(time: roaring.time, ms: 1500)
  let start =
    read_by_the_client(start: next_cast_started(received: roaring.received))
  assert start.initial_positions
    == [
      SpellInitialPosition(
        unit_id: roaring.unit_id,
        target_flags: 1,
        position: start.position,
        yaw: start.yaw,
        anchor_unit_id: 0,
      ),
    ]
    as "the caster's initial position, at its pose"
  assert start.telegraph_positions
    == [
      SpellTelegraphPosition(
        telegraph_damage_id: 7880,
        unit_id: roaring.unit_id,
        target_flags: 1,
        position: start.position,
        yaw: start.yaw,
        anchor_unit_id: 0,
      ),
    ]
    as "the entry the cone is drawn from: row 7880 on the caster, at the same pose"
  driven_time.advance(time: roaring.time, ms: 500)
  let _player = world_watch_support.join(run: roaring.run, connection: 2)
  let late = read_by_the_client(start: next_cast_started(received: received_2))
  assert late.cast_id == start.cast_id
    && late.initial_positions == start.initial_positions
    && late.telegraph_positions == start.telegraph_positions
    as "a viewer arriving mid-cast is sent the same cast and the same positions"
  driven_time.advance(time: roaring.time, ms: 2000)
  let first = next_cast_went(received: roaring.received)
  assert first.phase == 0 && first.cast_id == start.cast_id
    as "the first go follows as before"
  driven_time.advance(time: roaring.time, ms: 500)
  let key = next_strike_told(received: roaring.received)
  assert key.occasion == strike_tell.AtGo(phase: 1) && key.unit_id == 10
    as "the player on the creature, inside the cone drawn, is told to take the hit"
  answer(roaring:, key:)
  let second = next_cast_went(received: roaring.received)
  assert second.phase == 1
    && list.map(second.targets, fn(target) { target.unit_id }) == [10]
    as "the strike go lists the player"
  next_cast_finished(received: roaring.received, cast_id: start.cast_id)
  world_support.stop(world: roaring.world)
}

pub fn a_player_outside_the_cone_sees_the_cast_and_takes_nothing_test() -> Nil {
  use <- owned_test.run(30_000)
  // Player 2 stands 5 aside of the creature and joins its fight with a lighter strike, so
  // player 1 stays the target: 5 is within the cone's 5.5 reach, but 90 degrees off the
  // creature's facing, outside a cone 40 degrees across.
  let roaring = roaring_fight()
  let received_2 = world_support.connection(world: roaring.world, id: 2)
  let _player = world_watch_support.join(run: roaring.run, connection: 2)
  let _appeared =
    world_watch_support.next(
      received: received_2,
      what: "the creature's 0x262 for player 2",
      wanted: world_watch_support.appearance,
    )
  struck_from(
    world: roaring.world,
    run: roaring.run,
    connection: 2,
    unit_id: roaring.unit_id,
    x: 5.0,
    damage: 1,
    cast_id: 2,
  )
  driven_time.advance(time: roaring.time, ms: 1500)
  let start = next_cast_started(received: received_2)
  assert start.spell4_id == 55_317 as "player 2 sees the cast bar"
  driven_time.advance(time: roaring.time, ms: 2500)
  let first = next_cast_went(received: received_2)
  assert first.phase == 0 as "and the first go"
  driven_time.advance(time: roaring.time, ms: 500)
  let key = next_strike_told(received: roaring.received)
  assert key.unit_id == 10 as "player 1 is told to take the hit"
  answer(roaring:, key:)
  let second = next_cast_went(received: received_2)
  assert second.phase == 1
    && list.map(second.targets, fn(target) { target.unit_id }) == [10]
    as "and the strike go, which names player 1 alone"
  driven_time.settled(roaring.pid)
  assert sent_so_far(
      world: roaring.world,
      id: 2,
      received: received_2,
      wanted: fn(message) {
        case message {
          ForStay(
            sent: client_connection.SentByFoe(strike_tell.Attacks(..)),
            ..,
          ) -> Ok(Nil)
          ForStay(..)
          | client_connection.SentBySessions(..)
          | client_connection.SentByChat(..) -> Error(Nil)
        }
      },
    )
    == []
    as "player 2 was told no strike to take"
  world_support.stop(world: roaring.world)
}

pub fn a_stun_between_the_gos_ends_the_cast_and_the_creature_returns_to_its_auto_attack_test() -> Nil {
  use <- owned_test.run(30_000)
  // The stun lands at 4200 ms (700 ms after the cast's first go): the cast ends with 0x7f9,
  // the strike go that was due at 4500 ms hits no one, and the stun's end (2500 ms, Stagger's
  // 28673) lets the creature attack again with the instant attack (the special's cooldown
  // runs to 11 500 ms).
  let roaring = roaring_fight()
  driven_time.advance(time: roaring.time, ms: 1500)
  let start = next_cast_started(received: roaring.received)
  driven_time.advance(time: roaring.time, ms: 2500)
  let first = next_cast_went(received: roaring.received)
  assert first.phase == 0
  driven_time.advance(time: roaring.time, ms: 200)
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id: roaring.unit_id,
      damage_type: 3,
      damage: 1,
      cast_id: 3,
      occasion: strike_tell.AtGo(phase: 0),
    )
  let assert Ok(Nil) =
    creature_registry.tell(
      roaring.world.creatures,
      map: world_watch_support.ship,
      incarnation: roaring.run.incarnation,
      unit_id: roaring.unit_id,
      life: 2,
      message: creature.Strike(
        tell: strike_tell.Strike(..tell, controls: [
          crowd_control_support.stagger_stun(instance_id: 28_673),
        ]),
      ),
    )
  driven_time.settled(roaring.pid)
  let interrupted =
    world_watch_support.next(
      received: roaring.received,
      what: "the creature's 0x7f9",
      wanted: fn(message) {
        case message {
          ForStay(
            sent: SentByPeer(PeerNews(
              news: client_connection.CastInterrupted(cast_id:),
              ..,
            )),
            ..,
          ) -> Ok(cast_id)
          ForStay(..)
          | client_connection.SentBySessions(..)
          | client_connection.SentByChat(..) -> Error(Nil)
        }
      },
    )
  assert interrupted == start.cast_id as "the broken cast is the one shown"
  driven_time.advance(time: roaring.time, ms: 400)
  driven_time.settled(roaring.pid)
  assert sent_so_far(
      world: roaring.world,
      id: 1,
      received: roaring.received,
      wanted: fn(message) {
        case message {
          ForStay(
            sent: client_connection.SentByFoe(strike_tell.Attacks(..)),
            ..,
          ) -> Ok(Nil)
          ForStay(..)
          | client_connection.SentBySessions(..)
          | client_connection.SentByChat(..) -> Error(Nil)
        }
      },
    )
    == []
    as "past the strike go's time nobody was told to take a hit"
  driven_time.advance(time: roaring.time, ms: 3000)
  let next = next_cast_started(received: roaring.received)
  assert next.spell4_id == 5649
    as "once the stun ended the creature attacks with its instant attack"
  world_support.stop(world: roaring.world)
}

/// One creature of each other zone casts its special: the table's spell, the cast bar, a go
/// at 2800 ms and the strike at 3000 ms.
pub fn the_creatures_of_the_other_three_zones_cast_their_specials_test() -> Nil {
  use <- owned_test.run(60_000)
  // Each creature's first attack tick is 1500 ms after the strike and it chooses its special.
  // SpellPhase 11146 and 11147 (Spell4 55296), 11209 and 11210 (55327), 11215 and 11216
  // (55330) give phase delays of 2800 and 200 ms, so the gos fall at 2800 and 3000 ms. The
  // damage effects are Spell4Effects 131925, 131988 and 131994 (type 8, phaseFlags 2: go 1).
  // The creatures and their spells are the retail record's (creature_special_test).
  list.each(
    [
      #(27_687, 55_296, 131_925),
      #(28_623, 55_296, 131_925),
      #(24_057, 55_327, 131_988),
      #(25_979, 55_330, 131_994),
    ],
    fn(row) {
      let #(creature_id, spell4_id, damage_effects_id) = row
      let fight =
        fight_of(
          creature: spawn_support.special_creature(
            number: 1,
            creature_id:,
            spell4_id:,
          ),
          damage_effects_id:,
          x: 0.0,
        )
      driven_time.advance(time: fight.time, ms: 1500)
      let start = next_cast_started(received: fight.received)
      assert start.spell4_id == spell4_id
        && start.caster_unit_id == fight.unit_id
        as "the cast bar names the creature's special"
      driven_time.advance(time: fight.time, ms: 2799)
      driven_time.settled(fight.pid)
      assert sent_so_far(
          world: fight.world,
          id: 1,
          received: fight.received,
          wanted: cast_news,
        )
        == []
        as "no go before 2800 ms"
      driven_time.advance(time: fight.time, ms: 1)
      let first = next_cast_went(received: fight.received)
      assert first.phase == 0 && first.targets == []
        as "the first go, phase 0, names no one"
      driven_time.advance(time: fight.time, ms: 200)
      let key = next_strike_told(received: fight.received)
      assert key.occasion == strike_tell.AtGo(phase: 1)
        && key.cast_id == start.cast_id
        as "at 3000 ms the player in the telegraph is told to take the hit"
      answer(roaring: fight, key:)
      let second = next_cast_went(received: fight.received)
      assert second.phase == 1
        && list.map(second.targets, fn(target) { target.unit_id }) == [10]
        as "the strike go lists the player"
      next_cast_finished(received: fight.received, cast_id: start.cast_id)
      world_support.stop(world: fight.world)
    },
  )
}

pub fn a_struck_yeti_snowstalker_strikes_with_maul_then_slam_test() -> Nil {
  use <- owned_test.run(90_000)
  // Creature2 51126, a Yeti Snowstalker of the Northern Wilds, on the client's own rows, built as
  // the load builds a creature with the auto-attacks of its kind: its Jabbithole page
  // (`yeti-snowstalker-1`) lists Maul (Spell4 33251) and Slam (33252), numbered "#1" and "#2" by
  // the client's Spell4 descriptions. The creature's first attack tick is 1500 ms after the
  // strike (its kind's interval) and each next one 1500 ms after it; the 0x7ff of each names
  // the spell it casts (`opcode.0x7ff`), and never the default attack 5649.
  let yeti =
    spawn_support.autos_creature(number: 1, creature_id: 51_126, spell4_ids: [
      33_251,
      33_252,
    ])
  let roaring = fight_of(creature: yeti, damage_effects_id: 184_751, x: 0.0)
  driven_time.advance(time: roaring.time, ms: 1500)
  let maul = next_cast_started(received: roaring.received)
  assert maul.spell4_id == 33_251
    && maul.caster_unit_id == roaring.unit_id
    && maul.primary_target_unit_id == 10
    as "the first strike is Maul, cast on the player that struck the creature"
  answer(roaring:, key: next_strike_told(received: roaring.received))
  driven_time.advance(time: roaring.time, ms: 1500)
  let slam = next_cast_started(received: roaring.received)
  assert slam.spell4_id == 33_252 as "the second is Slam"
  answer(
    roaring: Roaring(..roaring, damage_effects_id: 184_752),
    key: next_strike_told(received: roaring.received),
  )
  driven_time.advance(time: roaring.time, ms: 1500)
  let again = next_cast_started(received: roaring.received)
  assert again.spell4_id == 33_251 as "the third is Maul again"
  assert maul.spell4_id != 5649
    && slam.spell4_id != 5649
    && again.spell4_id != 5649
    as "none is the default attack"
  world_support.stop(world: roaring.world)
}

/// What a creature's fight sent the connection, in order: a cast start, a go, a strike told to
/// take, a cast's finish.
type CastFrame {
  FrameStarted(spell4_id: Int)
  FrameWent(phase: Int, targets: List(Int))
  FrameTold(key: strike_tell.Key)
  FrameFinished(cast_id: Int)
}

/// The frame of a message the connection was sent, or `Error(Nil)` for any other.
fn cast_frame_of(message: Message) -> Result(CastFrame, Nil) {
  case message {
    ForStay(
      sent: SentByPeer(PeerNews(news: client_connection.CastStarted(start:), ..)),
      ..,
    ) -> Ok(FrameStarted(spell4_id: start.spell4_id))
    ForStay(
      sent: SentByPeer(PeerNews(news: client_connection.CastWent(go:), ..)),
      ..,
    ) ->
      Ok(FrameWent(
        phase: go.phase,
        targets: list.map(go.targets, fn(target) { target.unit_id }),
      ))
    ForStay(
      sent: SentByPeer(PeerNews(
        news: client_connection.CastFinished(cast_id:),
        ..,
      )),
      ..,
    ) -> Ok(FrameFinished(cast_id:))
    ForStay(
      sent: client_connection.SentByFoe(strike_tell.Attacks(tell: strike_tell.Strike(
        key:,
        ..,
      ))),
      ..,
    ) -> Ok(FrameTold(key:))
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

pub fn a_yeti_snowstalker_casts_ice_breath_with_two_hits_and_four_gos_test() -> Nil {
  use <- owned_test.run(90_000)
  // Creature2 51126 on the client's own rows with Ice Breath (Spell4 55635) as its special, fighting
  // player 1 standing 3 units off on the x axis. Its gos fall 2600, 3000, 3500 and 3800 ms after
  // the cast starts (SpellPhase 11479 to 11482: delays 2600, 400, 500 and 300); the damage row
  // 132757 (phaseFlags 6) strikes at gos 1 and 2 with the cone of row 7956, then 7957's; the delay row
  // 132758 holds 500 ms after go 3 (`table_rows -- Spell4Effects spellId=55635`). Rows 7956 and 7957
  // have flag 0x101000 and targetTypeFlags 1: the client draws both at the caster's initial
  // position, so the 0x7ff carries that one position and no telegraph position
  // (`0x14054b1b0.fixed_placement`, `telegraph_entries`).
  let fight =
    fight_of(
      creature: spawn_support.special_creature(
        number: 1,
        creature_id: 51_126,
        spell4_id: 55_635,
      ),
      damage_effects_id: 132_757,
      x: 3.0,
    )
  driven_time.advance(time: fight.time, ms: 1500)
  let start =
    read_by_the_client(start: next_cast_started(received: fight.received))
  assert start.spell4_id == 55_635
    && start.caster_unit_id == fight.unit_id
    && start.primary_target_unit_id == 10
    as "the cast bar: Ice Breath, cast on the player that struck the creature"
  assert list.map(start.initial_positions, fn(entry) { entry.unit_id })
    == [fight.unit_id]
    && start.telegraph_positions == []
    as "both cones are drawn at the caster's one initial position"
  let frames = fn() {
    driven_time.settled(fight.pid)
    sent_so_far(
      world: fight.world,
      id: 1,
      received: fight.received,
      wanted: cast_frame_of,
    )
  }
  let told_key = fn(frame) {
    let assert FrameTold(key:) = frame
      as "the frame is a strike told to the player"
    key
  }
  driven_time.advance(time: fight.time, ms: 2600)
  assert frames() == [FrameWent(phase: 0, targets: [])] as "go 0 names no one"
  driven_time.advance(time: fight.time, ms: 400)
  let assert [first_told] = frames()
    as "go 1: the player is told one strike and nothing else is sent before it is answered"
  let key_1 = told_key(first_told)
  assert key_1.occasion == strike_tell.AtGo(phase: 1)
    && key_1.cast_id == start.cast_id
    && key_1.unit_id == 10
    as "the first hit is keyed AtGo(1)"
  answer(roaring: fight, key: key_1)
  assert frames() == [FrameWent(phase: 1, targets: [10])]
    as "go 1 lists the player"
  driven_time.advance(time: fight.time, ms: 500)
  let assert [second_told] = frames() as "go 2: the player is told one strike"
  let key_2 = told_key(second_told)
  assert key_2.occasion == strike_tell.AtGo(phase: 2)
    && key_2.cast_id == start.cast_id
    && key_2.unit_id == 10
    as "the second hit is keyed AtGo(2)"
  answer(roaring: fight, key: key_2)
  assert frames() == [FrameWent(phase: 2, targets: [10])]
    as "go 2 lists the player"
  driven_time.advance(time: fight.time, ms: 300)
  assert frames()
    == [
      FrameWent(phase: 3, targets: []),
      FrameFinished(cast_id: start.cast_id),
    ]
    as "go 3, the last, names no one, and the cast finishes"
  driven_time.advance(time: fight.time, ms: 500)
  let assert [FrameStarted(spell4_id: next_spell4_id), ..] = frames()
    as "after the hold the creature casts again"
  assert next_spell4_id == 5649
    as "its next attack is its 5649, the special being on cooldown"
  world_support.stop(world: fight.world)
}

pub fn a_sandthorne_malverine_casts_savage_shred_from_its_0x7ff_with_gos_at_0_and_1_ms_five_hits_and_a_hold_test() -> Nil {
  use <- owned_test.run(90_000)
  // Creature2 35947 on the client's own rows with Savage Shred (Spell4 34252, castTime 0) as its
  // special, fighting player 1 standing 3 units off on the x axis. Its gos fall 0, 1, 200, 700,
  // 1,200, 1,700 and 2,800 ms after the cast starts (SpellPhase 436 to 442: delays 0, 1, 199,
  // 500, 500, 500 and 1,100); the damage rows 67447 to 67451 (phaseFlags 4, 8, 16, 32 and 64)
  // strike at gos 2 to 6, and the delay row 111462 (1,200 ms, phaseFlags 0xffff0040) holds after
  // go 6 (`table_rows -- Spell4Effects spellId=34252`, `-- SpellPhase spell4IdOwner=34252`).
  let fight =
    fight_of(
      creature: spawn_support.special_creature(
        number: 1,
        creature_id: 35_947,
        spell4_id: 34_252,
      ),
      damage_effects_id: 67_447,
      x: 3.0,
    )
  driven_time.advance(time: fight.time, ms: 1500)
  let start =
    read_by_the_client(start: next_cast_started(received: fight.received))
  assert start.spell4_id == 34_252
    && start.caster_unit_id == fight.unit_id
    && start.primary_target_unit_id == 10
    as "the 0x7ff: Savage Shred, cast on the player that struck the creature"
  let frames = fn() {
    driven_time.settled(fight.pid)
    sent_so_far(
      world: fight.world,
      id: 1,
      received: fight.received,
      wanted: cast_frame_of,
    )
  }
  let told_key = fn(frame, phase) {
    let assert [FrameTold(key:)] = frame
      as "the player is told one strike and nothing else is sent before it is answered"
    assert key.occasion == strike_tell.AtGo(phase:)
      && key.cast_id == start.cast_id
      && key.unit_id == 10
      as { "the hit is keyed AtGo(" <> int.to_string(phase) <> ")" }
    key
  }
  driven_time.advance(time: fight.time, ms: 0)
  assert frames() == [FrameWent(phase: 0, targets: [])]
    as "the go at 0 is written the moment its timer fires, naming no one"
  driven_time.advance(time: fight.time, ms: 1)
  assert frames() == [FrameWent(phase: 1, targets: [])]
    as "the go at 1 ms, naming no one"
  // Each strike go: the delay to it, the damage row that answers it (`phaseFlags`).
  list.each(
    [
      #(2, 199, 67_447),
      #(3, 500, 67_448),
      #(4, 500, 67_449),
      #(5, 500, 67_450),
    ],
    fn(go) {
      let #(phase, delay_ms, damage_effects_id) = go
      driven_time.advance(time: fight.time, ms: delay_ms)
      let key = told_key(frames(), phase)
      answer(roaring: Roaring(..fight, damage_effects_id:), key:)
      assert frames() == [FrameWent(phase:, targets: [10])]
        as { "go " <> int.to_string(phase) <> " lists the player" }
    },
  )
  driven_time.advance(time: fight.time, ms: 1100)
  let key = told_key(frames(), 6)
  answer(roaring: Roaring(..fight, damage_effects_id: 67_451), key:)
  assert frames()
    == [
      FrameWent(phase: 6, targets: [10]),
      FrameFinished(cast_id: start.cast_id),
    ]
    as "go 6, the last, lists the player and the cast finishes"
  driven_time.advance(time: fight.time, ms: 1200)
  let assert [FrameStarted(spell4_id: next_spell4_id), ..] = frames()
    as "after the hold the creature casts again"
  assert next_spell4_id == 5649
    as "its next attack is its 5649, the special being on cooldown to 10,000 ms"
  world_support.stop(world: fight.world)
}

/// What a connection was sent of a creature's aggro and turns, as the test reads it.
type Seen {
  Targeted(unit_id: Int)
  Turned(face: creature_turn.Face)
  Ran(path: creature_path.Path)
}

/// The news of a fight the test reads, none for any other message.
fn seen_of(message: Message) -> Result(Seen, Nil) {
  case message {
    ForStay(
      sent: SentByPeer(PeerNews(
        news: client_connection.Targeting(target_unit_id:, ..),
        ..,
      )),
      ..,
    ) -> Ok(Targeted(target_unit_id))
    ForStay(
      sent: SentByPeer(PeerNews(
        news: client_connection.CreatureFaces(face:, ..),
        ..,
      )),
      ..,
    ) -> Ok(Turned(face))
    ForStay(
      sent: SentByPeer(PeerNews(
        news: client_connection.CreatureMoved(path:),
        ..,
      )),
      ..,
    ) -> Ok(Ran(path))
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// What the connection is sent up to the next path of the creature, in order.
fn seen_until_the_path(received received: Subject(Message)) -> List(Seen) {
  open_wait.named("the creature's path", fn() {
    seen_until_a_path(received:, so_far: [])
  })
}

fn seen_until_a_path(
  received received: Subject(Message),
  so_far so_far: List(Seen),
) -> List(Seen) {
  case world_watch_support.taken(received:, wanted: seen_of) {
    Ran(..) as path -> list.reverse([path, ..so_far])
    Targeted(..) as seen | Turned(..) as seen ->
      seen_until_a_path(received:, so_far: [seen, ..so_far])
  }
}

/// The player of `connection` moves to (`x`, `z`), the nth move.
fn moved_round(
  run run: MapProcess,
  connection connection: Int,
  x x: Float,
  z z: Float,
  seq seq: Int,
) -> Nil {
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
          z:,
        ),
        seq:,
      ),
    )
  Nil
}

pub fn a_creature_fighting_a_player_standing_apart_faces_the_player_through_chase_circling_and_leash_test() -> Nil {
  use <- owned_test.run(60_000)
  let time = driven_time.new()
  let world =
    world_watch_support.one_beast_timed(
      time:,
      respawn_ms: 60_000,
      idle_stop_ms: 60_000,
    )
  let run = world_watch_support.started(world)
  let first = world_support.connection(world:, id: 1)
  let _first_unit = world_watch_support.join(run:, connection: 1)
  let appeared =
    world_watch_support.next(
      received: first,
      what: "the creature's 0x262",
      wanted: world_watch_support.appearance,
    )
  let pid =
    world_watch_support.creature_pid(
      world:,
      run:,
      unit_id: appeared.unit_id,
      life: 2,
    )
  // Player 1 (unit 10) strikes from 12 units off, not on the creature's point.
  struck_from(
    world:,
    run:,
    connection: 1,
    unit_id: appeared.unit_id,
    x: 12.0,
    damage: 1,
    cast_id: 1,
  )
  driven_time.settled(pid)
  let assert [Targeted(10), Turned(creature_turn.Unit(10)), Ran(path)] =
    seen_until_the_path(received: first)
    as "the target, the turn to the player's unit, then the path: the order the client turns in"
  let assert creature_path.Running(to:, ..) = path
    as "the creature runs toward the player"
  // The turn on the wire: kind 0 then kind 18 naming the player, blend bit set.
  let #(_, entered) =
    world_entry_support.entry(
      tables: character_tables.shared(),
      character: world_entry_support.character(class: 4, faction: 167, level: 1),
    )
  let frame =
    frames.face_frame(
      entered:,
      unit_id: appeared.unit_id,
      standing_at: to,
      face: creature_turn.Unit(10),
      at_ms: 1000,
    )
  let assert Ok(movement) = unit_movement.decode(frame.body)
  let assert [_, relayed_movement.FaceUnit(face)] = movement.commands
    as "kind 0, then kind 18"
  assert face.unit_id == 10 && face.blends == 1
    as "naming player 1's unit, turning over half a second"
  // The player circles the creature inside reach of the path's end: the client keeps it
  // facing the player, so nothing at all is sent.
  let path_end_x = start_place.x(to)
  moved_round(run:, connection: 1, x: path_end_x +. 0.3, z: 0.0, seq: 2)
  moved_round(run:, connection: 1, x: path_end_x, z: 0.3, seq: 3)
  moved_round(run:, connection: 1, x: path_end_x -. 0.3, z: 0.0, seq: 4)
  moved_round(run:, connection: 1, x: path_end_x, z: 0.0 -. 0.3, seq: 5)
  // The four moves are the map's to forward: the map takes them, then the creature has what
  // the map forwarded, before the connection's output is read.
  driven_time.settled(run.pid)
  driven_time.settled(pid)
  assert sent_so_far(world:, id: 1, received: first, wanted: seen_of) == []
    as "four moves round the creature send no turn and no path"
  // Half a second on, the creature has run 5 of its 8 units. A second player entering
  // mid-fight is sent the current turn after the 0x262.
  driven_time.advance(time:, ms: 500)
  driven_time.settled(pid)
  let second = world_support.connection(world:, id: 2)
  let _second_unit = world_watch_support.join(run:, connection: 2)
  let _appeared =
    world_watch_support.next(
      received: second,
      what: "the creature's 0x262 for player 2",
      wanted: world_watch_support.appearance,
    )
  let assert [Targeted(10), Turned(creature_turn.Unit(10)), Ran(..)] =
    seen_until_the_path(received: second)
    as "the arriving viewer's client is told the target and turned to it before the path"
  // The player leaves: the leash turns the creature to its spawn's place, walks it home, and on
  // arrival gives it the spawn's facing.
  move_to(run:, connection: 1, x: far)
  let assert [Turned(creature_turn.Point(place:)), Ran(home_path)] =
    seen_until_the_path(received: second)
    as "kind 19 toward home goes before the walk home"
  let spawn = spawn_support.battle_beast(number: 1, x: 0.0)
  assert place == spawn.place
    && creature_path.end(path: home_path) == spawn.place
    as "the point and the walk are the spawn's place"
  driven_time.advance(time:, ms: 60_000)
  let assert Turned(arrived) =
    world_watch_support.next(
      received: second,
      what: "the creature's turn at home",
      wanted: seen_of,
    )
    as "on arrival one rotation"
  assert arrived == creature_turn.Home(facing: start_place.facing(spawn.place))
    as "the home turn with the facing of the spawn's 0x262, which a viewer blends"
  world_support.stop(world:)
}

/// The key of a strike the creature told the connection's player to take.
fn strike_told(message: Message) -> Result(strike_tell.Key, Nil) {
  case message {
    ForStay(
      sent: client_connection.SentByFoe(strike_tell.Attacks(tell: strike_tell.Strike(
        key:,
        ..,
      ))),
      ..,
    ) -> Ok(key)
    ForStay(..)
    | client_connection.SentBySessions(..)
    | client_connection.SentByChat(..) -> Error(Nil)
  }
}

/// A fight of the Rootbrute Grimspore with Spell4 63569 as its special, against player 1 (unit
/// 10, on it) and player 2 (unit 20, 5 aside): the cast id of the special's round and the unit
/// it struck, after both players have seen the cast and its go.
fn void_blast_fight() -> #(Int, Int) {
  let roaring =
    fight_of(
      creature: spawn_support.special_creature(
        number: 1,
        creature_id: 12_212,
        spell4_id: 63_569,
      ),
      damage_effects_id: 159_886,
      x: 0.0,
    )
  let received_2 = world_support.connection(world: roaring.world, id: 2)
  let _player = world_watch_support.join(run: roaring.run, connection: 2)
  let _appeared =
    world_watch_support.next(
      received: received_2,
      what: "the creature's 0x262 for player 2",
      wanted: world_watch_support.appearance,
    )
  struck_from(
    world: roaring.world,
    run: roaring.run,
    connection: 2,
    unit_id: roaring.unit_id,
    x: 5.0,
    damage: 1,
    cast_id: 2,
  )
  driven_time.advance(time: roaring.time, ms: 1500)
  let start = next_cast_started(received: roaring.received)
  assert start.spell4_id == 63_569 as "player 1 sees the special's cast"
  assert next_cast_started(received: received_2).cast_id == start.cast_id
    as "player 2 sees the same cast"
  driven_time.advance(time: roaring.time, ms: 160)
  driven_time.settled(roaring.pid)
  let told =
    list.append(
      sent_so_far(
        world: roaring.world,
        id: 1,
        received: roaring.received,
        wanted: strike_told,
      ),
      sent_so_far(
        world: roaring.world,
        id: 2,
        received: received_2,
        wanted: strike_told,
      ),
    )
  let assert [key] = told as "one of the two players is told to take the strike"
  assert key.cast_id == start.cast_id as "under the cast's id"
  answer(roaring:, key:)
  list.each([roaring.received, received_2], fn(received) {
    let went = next_cast_went(received:)
    assert went.cast_id == start.cast_id
      && list.map(went.targets, fn(target) { target.unit_id }) == [key.unit_id]
      as "both players see the go name the struck player alone"
  })
  world_support.stop(world: roaring.world)
  #(start.cast_id, key.unit_id)
}

pub fn a_creature_with_the_special_63569_strikes_the_unit_its_cast_id_picks_test() -> Nil {
  use <- owned_test.run(90_000)
  // Spell4 63569 (castTime 160, one go) has area row 541: 360 degrees, 70 m, one unit, order 3
  // (Random), and no telegraph row, so both players are inside. The round's cast id is the
  // seed, and the Random order is the guess marked in `area` (units by the MurmurHash3
  // finalizer of `seed * 0x9E3779B1 + unit_id`, masked to 32 bits). Worked outside the code
  // for cast id 2147487745: unit 10 gives 2166553108 and unit 20 gives 3475147392, so unit 10
  // is first; with the seed 0 a plain `select` would pass, unit 20 is first (the strike
  // would fail here if it ignored the round).
  let #(cast_id, struck) = void_blast_fight()
  assert cast_id == 2_147_487_745 as "the round's cast id"
  assert struck == 10 as "the unit the cast id's mix puts first"
  assert void_blast_fight() == #(cast_id, struck)
    as "the same cast id, the same unit"
}

/// The connection's player, on the creature's threat list, moves to `x`: the creature is sent
/// the `TargetMoved` that the connection sends for each accepted move while the creature holds
/// the player on its threat list (`movement.tells_a_fighter_the_place`). The stand-in
/// connections here run no connection rule, so the test sends it.
fn target_moved(
  roaring roaring: Roaring,
  connection connection: Int,
  x x: Float,
  seq seq: Int,
) -> Nil {
  let assert Ok(Nil) =
    creature_registry.tell(
      roaring.world.creatures,
      map: world_watch_support.ship,
      incarnation: roaring.run.incarnation,
      unit_id: roaring.unit_id,
      life: 2,
      message: creature.TargetMoved(
        by: ConnectionId(connection),
        place: place_support.at(
          world_id: 3460,
          world_zone_id: spawn_support.warfare_woods,
          x:,
          y: 0.0,
          z: 0.0,
        ),
        seq:,
        stay: map_support.stay(count: 1),
        hit_radius: place_support.player_hit_radius,
      ),
    )
    as "the creature is found by its address and told"
  driven_time.settled(roaring.pid)
}

/// The 0x7ff position of a place on the x axis at ground level, as the client reads it.
fn on_the_x_axis(x x: Float) -> SpellPosition {
  SpellPosition(x: float32.to_bits(x), y: float32.to_bits(0.0), z: 0)
}

pub fn an_eldan_security_construct_draws_its_laser_bolt_circle_under_the_player_and_strikes_the_fighters_in_it_test() -> Nil {
  use <- owned_test.run(90_000)
  // Levian Bay's Eldan Security Construct (Creature2 25986) casts Laser Bolt (Spell4 55846,
  // damage effect 133289): row 7874 is a circle of 4 on the cast's target (flags 0x905000, tt
  // 2), drawn where the 0x7ff puts it. On the x axis the creature stands at 0, player 1 (the
  // target) at 8, player 2 at 9 (1 from the circle's centre) and player 3 at 2 (6 from it,
  // outside 4 plus the player's hit radius 1.2); player 1 then steps to 14, still within the
  // reach of 15 plus the Construct's hit radius 1.0, and 6 from the centre. The target's
  // role bit 2 is the entry's flags byte (`spell.telegraph_position`, a marked guess), and the
  // strike go is phase 0 (SpellPhase 11613 holds the one go), which the client's missile row
  // 7473 (phaseFlags 1) launches in.
  let roaring =
    fight_of(
      creature: spawn_support.special_creature(
        number: 1,
        creature_id: 25_986,
        spell4_id: 55_846,
      ),
      damage_effects_id: 133_289,
      x: 0.0,
    )
  let joined_at = fn(connection, x) {
    let received =
      world_support.connection(world: roaring.world, id: connection)
    let _player = world_watch_support.join(run: roaring.run, connection:)
    let _appeared =
      world_watch_support.next(
        received:,
        what: "the creature's 0x262 for the player",
        wanted: world_watch_support.appearance,
      )
    struck_from(
      world: roaring.world,
      run: roaring.run,
      connection:,
      unit_id: roaring.unit_id,
      x:,
      damage: 1,
      cast_id: connection,
    )
    received
  }
  let received_2 = joined_at(2, 9.0)
  let received_3 = joined_at(3, 2.0)
  target_moved(roaring:, connection: 1, x: 8.0, seq: 2)
  driven_time.advance(time: roaring.time, ms: 1500)
  let start =
    read_by_the_client(start: next_cast_started(received: roaring.received))
  assert start.spell4_id == 55_846 && start.primary_target_unit_id == 10
    as "the cast is on player 1, the creature's target"
  let initial_at_the_target = [
    SpellInitialPosition(
      unit_id: 10,
      target_flags: 2,
      position: on_the_x_axis(x: 8.0),
      yaw: 0,
      anchor_unit_id: 0,
    ),
  ]
  let circle_at_the_target = [
    SpellTelegraphPosition(
      telegraph_damage_id: 7874,
      unit_id: 10,
      target_flags: 2,
      position: on_the_x_axis(x: 8.0),
      yaw: 0,
      anchor_unit_id: 0,
    ),
  ]
  assert start.initial_positions == initial_at_the_target
    as "the target's initial position, at its place, with the target's role bit"
  assert start.telegraph_positions == circle_at_the_target
    as "the circle of row 7874 under the target"
  target_moved(roaring:, connection: 1, x: 14.0, seq: 3)
  let received_4 = world_support.connection(world: roaring.world, id: 4)
  let _late = world_watch_support.join(run: roaring.run, connection: 4)
  let late = read_by_the_client(start: next_cast_started(received: received_4))
  assert late.cast_id == start.cast_id
    && late.primary_target_unit_id == 10
    && late.initial_positions == initial_at_the_target
    && late.telegraph_positions == circle_at_the_target
    as "a viewer arriving mid-cast reads the same lists, though the target has stepped out"
  driven_time.advance(time: roaring.time, ms: 3000)
  driven_time.settled(roaring.pid)
  let told = fn(id, received) {
    sent_so_far(world: roaring.world, id:, received:, wanted: strike_told)
  }
  assert told(1, roaring.received) == []
    as "player 1 stepped out of the circle and is not struck"
  assert told(3, received_3) == []
    as "player 3 stood outside the circle and is not struck"
  let key = next_strike_told(received: received_2)
  assert key.unit_id == 20
    && key.cast_id == start.cast_id
    && key.occasion == strike_tell.AtGo(phase: 0)
    as "player 2 stands in the circle where player 1 stood, and is struck at the go"
  answer(roaring:, key:)
  let went = next_cast_went(received: roaring.received)
  assert went.phase == 0
    && list.map(went.targets, fn(target) { target.unit_id }) == [20]
    as "the strike go is phase 0 and names player 2 alone"
  world_support.stop(world: roaring.world)
}

/// The mark of each state of the answers to the strike `cast_id` among what the connection
/// was sent.
fn marks_answered(
  world world: World,
  id id: Int,
  received received: Subject(Message),
  cast_id cast_id: Int,
) -> List(option.Option(strike_tell.Interrupted)) {
  sent_so_far(world:, id:, received:, wanted: fn(message) {
    case message {
      ForStay(
        sent: client_connection.SentByTarget(answered: Answered(
          key: Key(cast_id: answered_cast, ..),
          outcome: Landed(controls:, ..),
        )),
        ..,
      )
        if answered_cast == cast_id
      -> Ok(list.map(controls, fn(control) { control.interrupted }))
      ForStay(..)
      | client_connection.SentBySessions(..)
      | client_connection.SentByChat(..) -> Error(Nil)
    }
  })
  |> list.flatten
}

/// The state and cast-ending news a viewer's connection was sent, by the names of the frames
/// each becomes. A broken cast is one `CastInterrupted` news, which the connection writes as
/// the 0x7f9 and then the 0x7fe, so it is named "0x7f9" here and the creature sends no
/// `CastFinished` news besides it.
fn state_and_cast_news(message: Message) -> Result(String, Nil) {
  creature_news_support.named_among(names: ["0x87f", "0x7f9", "0x7fe"])(message)
}

pub fn a_stun_between_the_gos_of_earthen_roar_marks_the_answer_to_the_stunner_alone_test() -> Nil {
  use <- owned_test.run(30_000)
  // Rootbrute Grimspore (Creature2 12212) casts Earthen Roar (Spell4 55317) 1500 ms after
  // player 1's strike, its first go 2500 ms after the cast starts. Player 2's Stagger stun
  // lands 500 ms into the cast. The second row's stunner is a connection the world has no
  // process for: its answer is dropped, and the creature breaks the cast and goes on all
  // the same.
  [#("a stunner that is there", True), #("a stunner that is gone", False)]
  |> list.each(fn(row) {
    let #(reason, there) = row
    let roaring = roaring_fight()
    let received_2 = case there {
      True -> Some(world_support.connection(world: roaring.world, id: 2))
      False -> None
    }
    driven_time.advance(time: roaring.time, ms: 1500)
    let start = next_cast_started(received: roaring.received)
    driven_time.advance(time: roaring.time, ms: 500)
    struck_with_states(
      world: roaring.world,
      run: roaring.run,
      connection: 2,
      unit_id: roaring.unit_id,
      x: 0.0,
      damage: 1,
      cast_id: 7,
      controls: [crowd_control_support.stagger_stun(instance_id: 28_673)],
    )
    driven_time.settled(roaring.pid)
    assert list.filter_map(
        world_support.sent_before_the_marker(
          world: roaring.world,
          id: 1,
          received: roaring.received,
        ),
        state_and_cast_news,
      )
      == ["0x87f", "0x7f9"]
      as {
        reason
        <> ": the other viewer is sent the state and the one news of the broken cast, which its connection writes as 0x7f9 then 0x7fe"
      }
    assert marks_answered(
        world: roaring.world,
        id: 1,
        received: roaring.received,
        cast_id: 7,
      )
      == []
      as {
        reason
        <> ": the other viewer is sent no answer to a strike that is not its own"
      }
    case received_2 {
      Some(received) -> {
        assert marks_answered(
            world: roaring.world,
            id: 2,
            received:,
            cast_id: 7,
          )
          == [Some(strike_tell.Interrupted(spell4_id: Spell4Id(55_317)))]
          as { reason <> ": the stunner's answer names Earthen Roar" }
      }
      None -> Nil
    }
    driven_time.advance(time: roaring.time, ms: 3000)
    let next = next_cast_started(received: roaring.received)
    assert next.spell4_id == 5649 && next.cast_id != start.cast_id
      as {
        reason
        <> ": the stun ended and the creature attacks with its instant attack"
      }
    world_support.stop(world: roaring.world)
  })
}
