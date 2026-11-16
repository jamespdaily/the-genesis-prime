//// The creatures a player's use takes out of the world for a while
//// (`genesis_prime/world_map/map`, `Released`), run as the pure rule it is: inputs
//// in, new state and effects out, the clock driven through the inputs' times.
//// Expected values come from these places.
//// - The client's tables: QuestObjective 9659 is a type 12 objective (a use of the
////   creature in its data) whose data is Creature2 27768, the Bramble Trap of quest
////   6296 (Quest2 6296 names it in its second objective); Creature2 28112, the
////   Trapped Mordesh, is no objective's creature. The world database stands the
////   Mordesh at the trap's x and z, 0.07 m above it: of the 1,112 spawns whose creature a
////   type 12 objective names, 38 have such a neighbour, all in
////   quests 6296, 4983 and 6727.
//// - The server's reading of the client's behaviour, which is that
////   a rescued exile and its trap are gone for every player at once and are back
////   after a time: the server's choice of 30 s (the `used_object_release_ms` game
////   number), which the kind's 60 s respawn time is not.
//// - The stop path of an idle creature (`map_creature_test`): the map tells the
////   creature `Retire`, and its end sends every player `Gone` of the unit. A
////   creature told to retire while dead stops at its corpse timer
////   (`creature_life_test`, `on_retire`).

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{
  type ServiceStep, ConnectionId, LogInfo, LogLine, OwnEvent, ServiceTimerFired,
  WatchEnded,
}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/static_object
import gleam/int
import gleam/list
import gleam/string
import map_spawn_support as spawns
import map_support
import owned_test
import place_support
import spawn_support

/// The Bramble Trap's creature and the Trapped Mordesh's.
const bramble_trap = 27_768

const trapped_mordesh = 28_112

/// The release time, the server's choice (`used_object_release_ms`).
const release_ms = 30_000

/// A place in Warfare Woods `x` along, `y` up, at z 0.
fn standing(x x: Float, y y: Float) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: spawn_support.warfare_woods,
    x:,
    y:,
    z: 0.0,
  )
}

/// Spawn `number`, a creature `creature` stands at `place` in.
fn spawn_of(
  number number: Int,
  creature creature: Int,
  place place: Place,
) -> Spawn {
  Spawn(
    ..spawn_support.beast_at(number:, place:),
    creature_id: Creature2Id(creature),
  )
}

/// A map with a Bramble Trap (spawn 1) and a Trapped Mordesh at its x and z
/// (spawn 2), started.
fn a_trap_with_its_captive() -> State {
  spawns.started_with_spawns(spawns: [
    spawn_of(number: 1, creature: bramble_trap, place: standing(x: 0.0, y: 0.0)),
    spawn_of(
      number: 2,
      creature: trapped_mordesh,
      place: standing(x: 0.0, y: 0.07),
    ),
  ])
}

/// The unit ids and watches of the creatures a step starts, in spawn order.
fn started_units(
  taken: ServiceStep(map.Outgoing),
) -> List(#(step.WatchId, Int)) {
  list.map(spawns.starts(taken), fn(start) { #(start.0, { start.1 }.unit_id) })
}

fn timer_fired(
  state state: State,
  at_ms at_ms: Int,
  spawn spawn: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(ServiceTimerFired(timer: step.TimerId(spawn))),
  )
}

pub fn a_released_creature_is_gone_for_every_viewer_and_starts_again_after_the_release_time_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_of(
        number: 1,
        creature: bramble_trap,
        place: standing(x: 0.0, y: 0.0),
      ),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(watch, trap)] = started_units(taken)
  let #(state, _) =
    spawns.join(state:, at_ms: 6100, connection: 2, x: spawns.far)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  assert spawns.creature_sends(taken) == [#(trap, "Retire")]
    as "the creature is told to stop, as an idle one is"
  assert spawns.player_sends(taken) == [] && spawns.timers(taken) == []
    as "no client loses the unit before the creature has stopped"
  let #(state, taken) =
    spawns.feed(state:, at_ms: 7100, event: WatchEnded(watch))
  assert spawns.player_sends(taken)
    == [
      #(1, "Gone " <> int.to_string(trap)),
      #(2, "Gone " <> int.to_string(trap)),
    ]
    as "every player in the map is told the unit is gone, also one that did not see it"
  assert spawns.timers(taken) == [#(1, release_ms)]
    as "the spawn waits the release time, not the kind's 60 s respawn time"
  assert spawns.starts(taken) == [] as "and starts nothing before it"
  let #(_, taken) = timer_fired(state:, at_ms: 37_100, spawn: 1)
  let assert [#(_, again)] = started_units(taken)
  assert again != trap && again > 0
    as "at the timer a creature starts under a new unit id"
  let assert [start] = spawns.starts(taken)
  assert { start.1 }.viewers == [#(ConnectionId(1), map_support.stay(count: 1))]
    as "with the player in sight as its first viewer"
}

pub fn a_released_creature_takes_the_creature_at_its_x_and_z_with_it_test() -> Nil {
  use <- owned_test.run(5000)
  let state = a_trap_with_its_captive()
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(trap_watch, trap), #(mordesh_watch, mordesh)] =
    started_units(taken)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  assert spawns.creature_sends(taken)
    == [#(trap, "Retire"), #(mordesh, "Retire")]
    as "the Mordesh, 0.07 m above the trap, is told to stop with it"
  let #(state, taken) =
    spawns.feed(state:, at_ms: 7100, event: WatchEnded(trap_watch))
  assert spawns.player_sends(taken) == [#(1, "Gone " <> int.to_string(trap))]
  assert spawns.timers(taken) == [#(1, release_ms)]
  let #(state, taken) =
    spawns.feed(state:, at_ms: 7150, event: WatchEnded(mordesh_watch))
  assert spawns.player_sends(taken) == [#(1, "Gone " <> int.to_string(mordesh))]
  assert spawns.timers(taken) == [#(2, release_ms)]
    as "the captive waits the same release time under its own spawn's timer"
  let #(state, taken) = timer_fired(state:, at_ms: 37_100, spawn: 1)
  assert list.length(spawns.starts(taken)) == 1
  let #(_, taken) = timer_fired(state:, at_ms: 37_150, spawn: 2)
  let assert [#(_, again)] = started_units(taken)
  assert again != mordesh
    as "the Mordesh returns under a new unit id, as the trap does"
}

pub fn a_creature_near_but_not_at_the_released_x_and_z_stays_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_of(
        number: 1,
        creature: bramble_trap,
        place: standing(x: 0.0, y: 0.0),
      ),
      spawn_of(
        number: 2,
        creature: trapped_mordesh,
        place: standing(x: 0.5, y: 0.0),
      ),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(_, trap), #(_, neighbour)] = started_units(taken)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  assert spawns.creature_sends(taken) == [#(trap, "Retire")]
    as "the creature 0.5 m away is not at the trap's x and z: it is told nothing"
  let assert Ok(map.Live(unit_id:, ..)) =
    map.spawn_state(state:, spawn: SpawnId(2))
  assert unit_id == neighbour as "and it keeps running"
}

pub fn a_second_release_of_the_same_unit_does_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let state = a_trap_with_its_captive()
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(trap_watch, trap), #(mordesh_watch, _)] = started_units(taken)
  let #(state, _) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  let #(state, taken) = spawns.released(state:, at_ms: 7010, unit_id: trap)
  assert support.effects_of(taken) == []
    as "a second player's credit of the same unit, while it stops, does nothing"
  let #(state, _) =
    spawns.feed(state:, at_ms: 7100, event: WatchEnded(trap_watch))
  let #(state, _) =
    spawns.feed(state:, at_ms: 7150, event: WatchEnded(mordesh_watch))
  let #(_, taken) = spawns.released(state:, at_ms: 8000, unit_id: trap)
  assert support.effects_of(taken) == []
    as "and so does one after the unit was given up: no second Gone, no second timer"
}

pub fn a_released_static_object_stays_and_is_logged_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    map_support.with_objects(
      incarnation: 1,
      spawns: [],
      objects: [
        spawn_support.holoring(number: 101, place: standing(x: 0.0, y: 0.0)),
      ],
      kinds: spawns.default_kinds(),
    )
  let #(state, _) =
    spawns.feed(
      state:,
      at_ms: spawns.started_at_ms,
      event: OwnEvent(step.Started),
    )
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(1, map.Noticed(notice: map.ObjectsSeen(units: [created]), ..))] =
    support.sends(taken)
    as "the one player is shown the one object"
  let object = static_object.unit_id(created:)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: object)
  let assert [step.Log(LogLine(level: LogInfo, text:, ..))] =
    support.effects_of(taken)
    as "the release is logged and nothing else happens"
  assert string.contains(text, "#861")
    as "the line names the step that releases static objects"
  assert map.spawn_state(state:, spawn: SpawnId(101)) == Error(Nil)
    as "the object keeps its place: no state, no Gone, no timer"
}

pub fn a_released_creature_that_respawns_uses_its_kinds_respawn_time_after_a_later_death_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_of(
        number: 1,
        creature: bramble_trap,
        place: standing(x: 0.0, y: 0.0),
      ),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(watch, trap)] = started_units(taken)
  let #(state, _) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  let #(state, _) = spawns.feed(state:, at_ms: 7100, event: WatchEnded(watch))
  let #(state, taken) = timer_fired(state:, at_ms: 37_100, spawn: 1)
  let assert [#(second_watch, _)] = started_units(taken)
  let #(_, taken) =
    spawns.feed(state:, at_ms: 40_000, event: WatchEnded(second_watch))
  assert spawns.timers(taken) == [#(1, map_support.respawn_ms)]
    as "the release time was spent with the one restart: a later crash waits the kind's respawn time"
}

pub fn a_released_creature_that_was_already_dead_ends_at_its_corpse_timer_and_then_waits_the_release_time_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_of(
        number: 1,
        creature: bramble_trap,
        place: standing(x: 0.0, y: 0.0),
      ),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(watch, trap)] = started_units(taken)
  // The map cannot see a death: it tells the creature `Retire` and waits for its
  // `WatchEnded`, whenever that comes. This test ends the creature 20 s after the
  // release, as a corpse's timer would, and checks that the spawn then still waits
  // the release time. That a dead creature stops only at its corpse timer is pinned
  // in `creature_life_test`, in the case that a creature that stands stops at once
  // when told to retire and a corpse waits for its respawn (`on_retire(Dead)`).
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  assert spawns.creature_sends(taken) == [#(trap, "Retire")]
  let #(state, taken) =
    spawns.feed(state:, at_ms: 27_000, event: WatchEnded(watch))
  assert spawns.player_sends(taken) == [#(1, "Gone " <> int.to_string(trap))]
    as "the unit is gone when the corpse timer ends the creature"
  assert spawns.timers(taken) == [#(1, release_ms)]
    as "and the spawn waits the release time from then, not the respawn time"
  let #(_, taken) = timer_fired(state:, at_ms: 57_000, spawn: 1)
  assert list.length(spawns.starts(taken)) == 1
}

pub fn a_use_that_lands_while_its_creature_is_retiring_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_of(
        number: 1,
        creature: bramble_trap,
        place: standing(x: 0.0, y: 0.0),
      ),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(watch, trap)] = started_units(taken)
  let #(state, _) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
  let #(state, _) = spawns.sweep(state:, at_ms: 75_000)
  let #(state, _) = spawns.move(state:, at_ms: 75_050, connection: 1, x: 0.0)
  let #(state, taken) = spawns.released(state:, at_ms: 75_060, unit_id: trap)
  assert support.effects_of(taken) == []
    as "the creature already stops: the release adds nothing to it"
  let #(_, taken) = spawns.feed(state:, at_ms: 75_100, event: WatchEnded(watch))
  let assert [#(_, again)] = started_units(taken)
  assert again == trap
    && spawns.player_sends(taken) == []
    && spawns.timers(taken) == []
    as "it restarts as a retiring creature does, under the same unit id, with no Gone and no timer"
}
