//// The creatures and static objects a player's use takes out of the world for a
//// while (`genesis_prime/world_map/map`, `Released`), run as the pure rule it is:
//// inputs in, new state and effects out, the clock driven through the inputs'
//// times. Expected values come from these places.
//// - The client's tables: QuestObjective 9659 is a type 12 objective (a use of the
////   creature in its data) whose data is Creature2 27768, the Bramble Trap of quest
////   6296 (Quest2 6296 names it in its second objective); Creature2 28112, the
////   Trapped Mordesh, is no objective's creature. The world database stands the
////   Mordesh at the trap's x and z, 0.07 m above it: of the 1,112 spawns whose creature a
////   type 12 objective names, 38 have such a neighbour, all in
////   quests 6296, 4983 and 6727.
//// - QuestObjective 21324 and 21354 are type 12 objectives whose data is Creature2
////   73419, a type 32 hologram projector of world 3460; Creature2 73619, the
////   hoverboard hologram, is no objective's creature and stands at its x and z, 2.3 m
////   above it (spawns 29036 and 29044). A client unit is removed with a 0x355 and a
////   0x262 for a unit it holds is ignored (`opcode.0x355`, `opcode.0x262`), so an
////   object comes back under its id only after an `ObjectsUnseen`.
//// - The server's reading of the client's behaviour, which is that
////   a rescued exile and its trap, or a used static object and what stands on it,
////   are gone for every player at once and are back after a time: the server's
////   choice of 30 s (the `used_object_release_ms` game number), which the kind's
////   60 s respawn time is not. A static object has no process and no `Gone`: the
////   connection keeps a `Gone` unit gone for good.
//// - The stop path of an idle creature (`map_creature_test`): the map tells the
////   creature `Retire`, and its end sends every player `Gone` of the unit. A
////   creature told to retire while dead stops at its corpse timer
////   (`creature_life_test`, `on_retire`).

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{
  type ServiceStep, ConnectionId, OwnEvent, ServiceTimerFired, WatchEnded,
}
import genesis_prime/table/id.{Creature2Id, PrerequisiteId}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/static_object.{type StaticObject, StaticObject}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/set
import gleam/string
import map_spawn_support as spawns
import map_support
import owned_test
import spawn_support

/// The Bramble Trap's creature and the Trapped Mordesh's.
const bramble_trap = 27_768

const trapped_mordesh = 28_112

/// Creature2 73419, the hologram projector a type 12 objective names, and 73619,
/// the hologram that stands on it.
const hologram_projector = 73_419

const hologram = 73_619

/// The release time, the server's choice (`used_object_release_ms`).
const release_ms = 30_000

/// A place in Warfare Woods `x` along, `y` up, at z 0.
fn standing(x x: Float, y y: Float) -> Place {
  spawns.standing(x:, y:)
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

/// A Holoring (spawn `number`) standing `x` along.
fn holoring_at(number number: Int, x x: Float) -> StaticObject {
  spawn_support.holoring(number:, place: standing(x:, y: 0.0))
}

/// A map with these creature spawns and static objects, started.
fn started_with_objects(
  spawns spawns: List(Spawn),
  objects objects: List(StaticObject),
) -> State {
  let state =
    map_support.with_objects(
      incarnation: 1,
      spawns:,
      objects:,
      kinds: spawns.default_kinds(),
    )
  let #(state, _) =
    spawns.feed(
      state:,
      at_ms: spawns.started_at_ms,
      event: OwnEvent(step.Started),
    )
  state
}

/// The unit ids of the objects a step shows players (`ObjectsSeen`), in the order
/// sent.
fn objects_shown(taken: ServiceStep(map.Outgoing)) -> List(Int) {
  list.flat_map(spawns.player_sends(taken), fn(sent) {
    case sent.1 {
      "Objects seen " <> ids ->
        string.split(ids, " ") |> list.filter_map(int.parse)
      _ -> []
    }
  })
}

/// What `spawns.player_sends` says of an `ObjectsSeen` of these units.
fn seen(unit_ids: List(Int)) -> String {
  "Objects seen " <> string.join(list.map(unit_ids, int.to_string), " ")
}

/// What `spawns.player_sends` says of an `ObjectsUnseen` of these units.
fn unseen(unit_ids: List(Int)) -> String {
  "Objects unseen " <> string.join(list.map(unit_ids, int.to_string), " ")
}

/// A map with a Holoring (spawn 101) and the player of connection 1 in sight of
/// it, the Holoring released at 7000 ms: the state, the Holoring's unit id.
fn a_holoring_released_with_a_viewer() -> #(State, Int) {
  let state =
    started_with_objects(spawns: [], objects: [holoring_at(number: 101, x: 0.0)])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [object] = objects_shown(taken)
  let #(state, _) = spawns.released(state:, at_ms: 7000, unit_id: object)
  #(state, object)
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
  assert spawns.first_viewers(start: { start.1 })
    == [#(ConnectionId(1), map_support.stay(count: 1))]
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
  let ended_at_corpse_timer = taken
  assert spawns.player_sends(taken) == [#(1, "Gone " <> int.to_string(trap))]
    as "the unit is gone when the corpse timer ends the creature"
  assert spawns.timers(taken) == [#(1, release_ms)]
    as "and the spawn waits the release time from then, not the respawn time"
  let #(_, taken) = timer_fired(state:, at_ms: 57_000, spawn: 1)
  assert list.length(spawns.starts(taken)) == 1
  let released_first = frames_at_the_end(taken: ended_at_corpse_timer)

  // The other order: the creature's corpse timer fired first and it told the map it
  // expired, and the use reaches the spawn before the creature has stopped. The spawn is
  // released all the same: when the creature ends, the same frames, never a restart at
  // once.
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
  let step.WatchId(life) = watch
  let #(state, _) = spawns.expired(state:, at_ms: 6500, unit_id: trap, life:)
  assert map.spawn_state(state:, spawn: SpawnId(1))
    == Ok(map.Respawning(unit_id: trap, life:))
    as "the creature expired"
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  assert map.spawn_state(state:, spawn: SpawnId(1))
    == Ok(map.Releasing(
      unit_id: trap,
      life:,
      wait_ms: release_ms,
      relations: dict.new(),
    ))
    as "the released spawn waits the release time at the creature's end, with no relation to keep"
  assert spawns.creature_sends(taken) == []
    as "the creature is stopping already: it is not told to retire"
  let #(_, ended) = spawns.feed(state:, at_ms: 27_000, event: WatchEnded(watch))
  assert frames_at_the_end(taken: ended) == released_first
    as "the same frames at the creature's end in both orders: Gone to every player and the release time, no restart"

  // A captive that expired when the use released the unit at its x and z is released too:
  // the trap is told to retire, the captive, which stops by itself, is told nothing.
  let state = a_trap_with_its_captive()
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(_, trap), #(mordesh_watch, mordesh)] = started_units(taken)
  let step.WatchId(mordesh_life) = mordesh_watch
  let #(state, _) =
    spawns.expired(state:, at_ms: 6500, unit_id: mordesh, life: mordesh_life)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  assert spawns.creature_sends(taken) == [#(trap, "Retire")]
    as "the captive that expired is told nothing"
  assert map.spawn_state(state:, spawn: SpawnId(2))
    == Ok(map.Releasing(
      unit_id: mordesh,
      life: mordesh_life,
      wait_ms: release_ms,
      relations: dict.new(),
    ))
    as "and waits the release time at its end, with no relation to keep"
  let #(_, ended) =
    spawns.feed(state:, at_ms: 7100, event: WatchEnded(mordesh_watch))
  assert spawns.player_sends(ended) == [#(1, "Gone " <> int.to_string(mordesh))]
    && spawns.timers(ended) == [#(2, release_ms)]
    && spawns.starts(ended) == []
    as "its end gives Gone to every player and the release time, never an immediate restart"
}

/// What a step that ends a released creature does: what players are sent, the timers it
/// starts and whether it starts a creature.
fn frames_at_the_end(
  taken taken: ServiceStep(map.Outgoing),
) -> #(List(#(Int, String)), List(#(Int, Int)), Bool) {
  #(
    spawns.player_sends(taken),
    spawns.timers(taken),
    spawns.starts(taken) != [],
  )
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

pub fn a_use_of_a_retiring_creature_leaves_its_live_captive_in_place_test() -> Nil {
  use <- owned_test.run(5000)
  let prerequisite = PrerequisiteId(41_803)
  let state =
    started_with_objects(
      spawns: [
        Spawn(
          ..spawn_of(
            number: 1,
            creature: bramble_trap,
            place: standing(x: 0.0, y: 0.0),
          ),
          visibility: Some(prerequisite),
        ),
        spawn_of(
          number: 2,
          creature: trapped_mordesh,
          place: standing(x: 0.0, y: 0.07),
        ),
      ],
      objects: [
        spawn_support.holoring(number: 101, place: standing(x: 0.0, y: 0.07)),
      ],
    )
  let #(state, _) =
    spawns.join_hiding(
      state:,
      at_ms: 6000,
      connection: 1,
      x: 0.0,
      alive: True,
      hidden: set.from_list([prerequisite]),
    )
  let #(state, taken) = spawns.join(state:, at_ms: 6100, connection: 2, x: 0.0)
  let assert [#(_, trap)] = started_units(taken)
  let #(state, _) = spawns.leave(state:, at_ms: 7000, connection: 2)
  let #(state, taken) = spawns.sweep(state:, at_ms: 75_000)
  assert spawns.creature_sends(taken) == [#(trap, "Retire")]
    as "only the trap is idle: the first player sees the Mordesh, not the trap"
  let #(_, taken) = spawns.released(state:, at_ms: 75_100, unit_id: trap)
  assert support.effects_of(taken) == []
    as "a use that lands while the trap retires changes nothing: no Retire for the live Mordesh, no unseen Holoring, no timer"
}

pub fn a_released_static_object_is_unseen_by_every_viewer_and_seen_again_under_its_id_after_the_release_time_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started_with_objects(spawns: [], objects: [holoring_at(number: 101, x: 0.0)])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [object] = objects_shown(taken)
  let #(state, _) = spawns.join(state:, at_ms: 6100, connection: 2, x: 10.0)
  let #(state, _) =
    spawns.join(state:, at_ms: 6200, connection: 3, x: spawns.far)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: object)
  assert spawns.player_sends(taken)
    == [#(1, unseen([object])), #(2, unseen([object]))]
    as "the two players in sight lose the unit with a 0x355, the one far away is told nothing, and no one is sent Gone"
  assert spawns.creature_sends(taken) == []
    as "the object has no creature to retire"
  assert map.spawn_state(state:, spawn: SpawnId(101)) == Error(Nil)
    as "and no state: it never becomes Gone"
  assert spawns.timers(taken) == [#(101, release_ms)]
    as "it waits the release time under its own spawn's timer"
  let #(_, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken)
    == [#(1, seen([object])), #(2, seen([object]))]
    as "at the timer the two in sight are shown the object under the id it had"
  assert spawns.timers(taken) == [] as "and nothing more is waited for"
}

/// A collectible crate (the world database's entity type 8, Creature2 12919, quest 3741's
/// Exile Supply Crate) as spawn `number` standing `x` along.
fn crate_at(number number: Int, x x: Float) -> StaticObject {
  StaticObject(
    ..spawn_support.holoring(number:, place: standing(x:, y: 0.0)),
    unit_type: static_object.Collectible,
    creature_id: Creature2Id(12_919),
  )
}

pub fn a_released_collectible_crate_is_unseen_by_every_viewer_and_seen_again_after_the_release_time_test() -> Nil {
  use <- owned_test.run(5000)
  // The crate is a static object like the Holoring (`static_object` types 4, 8, 10 to 14
  // and 32 are the ones the map shows from its objects), so a used crate goes for
  // every player and returns under its unit id after the release time (migration 0033,
  // 30 s, the server's choice).
  let state =
    started_with_objects(spawns: [], objects: [crate_at(number: 101, x: 0.0)])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [crate] = objects_shown(taken)
  let #(state, _) = spawns.join(state:, at_ms: 6100, connection: 2, x: 10.0)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: crate)
  assert spawns.player_sends(taken)
    == [#(1, unseen([crate])), #(2, unseen([crate]))]
    as "both viewers lose the crate with a 0x355"
  assert spawns.timers(taken) == [#(101, release_ms)]
    as "it waits the release time under its own spawn's timer"
  let #(_, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken)
    == [#(1, seen([crate])), #(2, seen([crate]))]
    as "at the timer both are shown the crate under the id it had"
}

pub fn a_player_who_joins_or_moves_into_sight_of_a_released_static_object_is_shown_it_only_at_the_return_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started_with_objects(spawns: [], objects: [
      holoring_at(number: 101, x: 0.0),
      holoring_at(number: 102, x: 800.0),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [released, other] = objects_shown(taken)
  let #(state, _) = spawns.released(state:, at_ms: 7000, unit_id: released)
  let #(state, taken) = spawns.join(state:, at_ms: 8000, connection: 2, x: 0.0)
  assert objects_shown(taken) == [other]
    as "a joiner is shown the object in sight that stays, and not the released one"
  let #(state, _) =
    spawns.join(state:, at_ms: 8100, connection: 3, x: spawns.far)
  let #(state, taken) =
    spawns.move(state:, at_ms: 9000, connection: 3, x: -900.0)
  assert objects_shown(taken) == []
    as "a player who moves into sight of the released object only is shown no object"
  let #(_, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken)
    == [
      #(1, seen([released])),
      #(2, seen([released])),
      #(3, seen([released])),
    ]
    as "at the return all three are shown it under its id"
}

pub fn a_second_release_of_a_released_static_object_changes_nothing_and_leaves_the_return_at_the_first_time_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, object) = a_holoring_released_with_a_viewer()
  let #(state, taken) = spawns.released(state:, at_ms: 17_000, unit_id: object)
  assert support.effects_of(taken) == []
    as "a second credit of the unit 10 s later sends nothing and starts no timer"
  let #(_, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken) == [#(1, seen([object]))]
    as "the object returns at the first release plus 30 s, not at 40 s"
}

pub fn two_static_objects_released_at_once_return_each_at_its_own_time_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started_with_objects(spawns: [], objects: [
      holoring_at(number: 101, x: 0.0),
      holoring_at(number: 102, x: 100.0),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [first, second] = objects_shown(taken)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: first)
  assert spawns.timers(taken) == [#(101, release_ms)]
  assert spawns.player_sends(taken) == [#(1, unseen([first]))]
  let #(state, taken) = spawns.released(state:, at_ms: 8000, unit_id: second)
  assert spawns.timers(taken) == [#(102, release_ms)]
  assert spawns.player_sends(taken) == [#(1, unseen([second]))]
  let #(state, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken) == [#(1, seen([first]))]
    as "the first return shows the first object only"
  let #(_, taken) = timer_fired(state:, at_ms: 38_000, spawn: 102)
  assert spawns.player_sends(taken) == [#(1, seen([second]))]
    as "the second return shows the second only"
}

pub fn a_return_after_the_viewer_left_sends_nothing_and_a_rejoin_after_it_sees_the_object_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, object) = a_holoring_released_with_a_viewer()
  let #(left, _) = spawns.leave(state:, at_ms: 8000, connection: 1)
  let #(left, taken) = timer_fired(state: left, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken) == [] && spawns.timers(taken) == []
    as "the only player in sight left: the return sends nothing"
  let #(_, taken) =
    spawns.join(state: left, at_ms: 38_000, connection: 1, x: 0.0)
  assert objects_shown(taken) == [object]
    as "a player who joins after the return is shown the object under its old id"
  let #(state, _) = spawns.leave(state:, at_ms: 8000, connection: 1)
  let #(state, taken) = spawns.join(state:, at_ms: 9000, connection: 1, x: 0.0)
  assert objects_shown(taken) == []
    as "a player who joins again before the return is not shown the object"
  let #(_, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken) == [#(1, seen([object]))]
    as "and is shown it at the return"
}

pub fn a_player_who_moved_out_of_sight_during_the_release_gets_nothing_at_the_return_and_sees_the_object_on_entering_later_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, object) = a_holoring_released_with_a_viewer()
  let #(state, taken) =
    spawns.move(state:, at_ms: 8000, connection: 1, x: spawns.far)
  assert spawns.player_sends(taken) == []
    as "the release already took the object from the player's set: leaving sight says nothing of it"
  let #(state, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken) == []
    as "the return sends the player nothing"
  let #(_, taken) = spawns.move(state:, at_ms: 38_000, connection: 1, x: 0.0)
  assert spawns.player_sends(taken) == [#(1, seen([object]))]
    as "a later move back into sight shows the object"
}

pub fn a_released_static_object_hidden_from_a_viewer_by_its_visibility_prerequisite_stays_hidden_at_the_return_test() -> Nil {
  use <- owned_test.run(5000)
  let prerequisite = PrerequisiteId(41_803)
  let state =
    started_with_objects(spawns: [], objects: [
      StaticObject(
        ..holoring_at(number: 101, x: 0.0),
        visibility: Some(prerequisite),
      ),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [object] = objects_shown(taken)
  let #(state, taken) =
    spawns.join_hiding(
      state:,
      at_ms: 6100,
      connection: 2,
      x: 0.0,
      alive: True,
      hidden: set.from_list([prerequisite]),
    )
  assert objects_shown(taken) == []
    as "the player for whom the prerequisite fails is not shown the object"
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: object)
  assert spawns.player_sends(taken) == [#(1, unseen([object]))]
    as "the release unsees it only for the player who was shown it"
  let #(state, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken) == [#(1, seen([object]))]
    as "the return shows it only to that player"
  let #(state, _) = spawns.released(state:, at_ms: 40_000, unit_id: object)
  let #(state, taken) =
    spawns.visibility_changed(
      state:,
      at_ms: 41_000,
      connection: 2,
      hidden: set.new(),
    )
  assert spawns.player_sends(taken) == []
    as "a prerequisite that stops failing during a release shows nothing"
  let #(_, taken) = timer_fired(state:, at_ms: 70_000, spawn: 101)
  assert spawns.player_sends(taken)
    == [#(1, seen([object])), #(2, seen([object]))]
    as "the formerly hidden player is shown it at that release's return"
}

pub fn a_map_that_starts_again_shows_a_released_static_object_at_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, released) = a_holoring_released_with_a_viewer()
  let again =
    started_with_objects(spawns: [], objects: [holoring_at(number: 101, x: 0.0)])
  let #(_, taken) =
    spawns.join(state: again, at_ms: 6000, connection: 1, x: 0.0)
  assert objects_shown(taken) == [released]
    as "a map built again from its settings shows the object to a joiner at once, under the id its counter gives from 1"
  assert spawns.timers(taken) == [] as "and waits for no timer"
}

pub fn a_creature_keyed_release_also_unsees_a_static_captive_at_its_x_and_z_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started_with_objects(
      spawns: [
        spawn_of(
          number: 1,
          creature: bramble_trap,
          place: standing(x: 0.0, y: 0.0),
        ),
      ],
      objects: [
        spawn_support.holoring(number: 101, place: standing(x: 0.0, y: 0.07)),
      ],
    )
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [object] = objects_shown(taken)
  let assert [#(_, trap)] = started_units(taken)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: trap)
  assert spawns.creature_sends(taken) == [#(trap, "Retire")]
    as "the trap is told to stop as in a release of a creature"
  assert spawns.player_sends(taken) == [#(1, unseen([object]))]
    as "the Holoring at its x and z is unseen at once"
  assert spawns.timers(taken) == [#(101, release_ms)]
  let #(_, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken) == [#(1, seen([object]))]
    as "and returns after the release time"
}

pub fn a_creature_captive_of_a_released_static_object_is_released_with_it_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started_with_objects(
      spawns: [
        spawn_of(
          number: 1,
          creature: trapped_mordesh,
          place: standing(x: 0.0, y: 0.07),
        ),
      ],
      objects: [
        StaticObject(
          ..holoring_at(number: 101, x: 0.0),
          unit_type: static_object.SimpleCollidable,
          creature_id: Creature2Id(hologram_projector),
        ),
      ],
    )
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [object] = objects_shown(taken)
  let assert [#(watch, mordesh)] = started_units(taken)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: object)
  assert spawns.creature_sends(taken) == [#(mordesh, "Retire")]
    as "the Mordesh at the object's x and z is told to stop"
  assert spawns.player_sends(taken) == [#(1, unseen([object]))]
    as "the object is unseen at once"
  assert spawns.timers(taken) == [#(101, release_ms)]
  let #(state, taken) =
    spawns.feed(state:, at_ms: 7100, event: WatchEnded(watch))
  assert spawns.player_sends(taken) == [#(1, "Gone " <> int.to_string(mordesh))]
  assert spawns.timers(taken) == [#(1, release_ms)]
    as "the Mordesh's end sends Gone and waits the release time"
  let #(state, taken) = timer_fired(state:, at_ms: 37_000, spawn: 101)
  assert spawns.player_sends(taken) == [#(1, seen([object]))]
  let #(_, taken) = timer_fired(state:, at_ms: 37_100, spawn: 1)
  assert list.length(spawns.starts(taken)) == 1
    as "the creature starts again at its own timer"
}

pub fn a_static_captive_of_a_released_static_object_is_unseen_with_it_and_returns_on_its_own_timer_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started_with_objects(spawns: [], objects: [
      StaticObject(
        ..spawn_support.holoring(
          number: 29_036,
          place: standing(x: 0.0, y: 0.0),
        ),
        unit_type: static_object.SimpleCollidable,
        creature_id: Creature2Id(hologram_projector),
      ),
      StaticObject(
        ..spawn_support.holoring(
          number: 29_044,
          place: standing(x: 0.0, y: 2.3),
        ),
        creature_id: Creature2Id(hologram),
      ),
    ])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [projector, captive] = objects_shown(taken)
  let #(state, taken) = spawns.released(state:, at_ms: 7000, unit_id: projector)
  assert spawns.player_sends(taken) == [#(1, unseen([projector, captive]))]
    as "one notice names both units, in spawn order"
  assert spawns.timers(taken) == [#(29_036, release_ms), #(29_044, release_ms)]
    as "each waits the release time under its own spawn's timer"
  let #(state, taken) = timer_fired(state:, at_ms: 37_000, spawn: 29_036)
  assert spawns.player_sends(taken) == [#(1, seen([projector]))]
  let #(_, taken) = timer_fired(state:, at_ms: 37_000, spawn: 29_044)
  assert spawns.player_sends(taken) == [#(1, seen([captive]))]
}
