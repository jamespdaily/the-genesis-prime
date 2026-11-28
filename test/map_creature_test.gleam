//// The creatures a map starts and stops as players see spawns
//// (`genesis_prime/world_map/map`), run as the pure rule it is: inputs in, new
//// state and effects out. Expected values come from these places.
//// - The design of the world spawns (the Design artifact of issue 375, sections 3
////   and 6): a creature starts when its spawn gets its first viewer, with the
////   spawn's unit id and a life, its watch's number; it stops when no player has
////   seen it for the idle stop, found by a sweep every 10 s, so between 60 and 70
////   s after the last viewer left; a spawn seen while its creature retires waits
////   for its end; a creature that crashes while seen is `Gone` to every player and
////   its spawn restarts after the respawn time under a new unit id if a player
////   sees it then, and is dormant otherwise; a start that fails leaves the spawn
////   empty for the run.
//// - Sight (`genesis_prime/shared/sight`): 1024 units, 3D, inclusive.
//// - Unit ids: never 0 (a 0x262 with unit id 0 becomes the controlled unit,
////   0x1403d9760), never given to two units at once, and below 2^20 (the cast id is
////   built from the unit id, issue 274's design, section 3); a unit id is reused
////   after a clean stop (`opcode.0x262`, `death.creature_respawn`) and never after
////   a crash, which sent `Gone`.
//// - The idle stop, the sweep and the respawn time are the server's choices
////   (design 375, section 4); the rule takes them as settings and the time as the
////   input's, so no test waits.

import connection_rule_support as support
import genesis_prime/map/message as map_message
import genesis_prime/shared/creature_kind.{Kind, Kinds}
import genesis_prime/step.{
  type ServiceStep, CancelServiceTimer, ConnectionId, CreatureNotStarted,
  LogError, OwnEffect, OwnEvent, Reply, Send, ServiceTimerFired, StartCreature,
  StartServiceTimer, WatchEnded, WatchId,
}
import genesis_prime/table/id.{Spell4Id}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn_id.{type SpawnId, SpawnId}
import genesis_prime/world_map/spawn_source
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/string
import inbound_support
import map_spawn_support as spawns
import map_support
import owned_test
import spawn_support

/// The one creature a step starts, with its watch.
fn the_start(
  taken: ServiceStep(map_message.Outgoing),
) -> #(step.WatchId, step.CreatureStart) {
  let assert [only] = spawns.starts(taken) as "exactly one creature starts"
  only
}

/// The spawn whose creature the burst's start of the unit made.
fn spawn_of_unit(
  creatures creatures: List(#(step.WatchId, step.CreatureStart)),
  unit_id unit_id: Int,
) -> SpawnId {
  let assert Ok(#(_, start)) =
    list.find(creatures, fn(start) { { start.1 }.unit_id == unit_id })
  let assert spawn_source.Stored(id:) = start.spawn
  id
}

/// Whether the spawn is dormant: no creature, no wait, no failure.
fn dormant(state state: State, spawn spawn: Int) -> Bool {
  map.spawn_state(state:, spawn: SpawnId(spawn)) == Error(Nil)
}

pub fn a_started_map_starts_its_sweep_timer_and_no_creature_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = spawns.started(at: [0.0, 100.0])
  assert spawns.starts(taken) == []
    as "a map stands no creature until a player sees one"
  assert spawns.timers(taken) == [#(0, map_support.sweep_ms)]
    as "the sweep timer is TimerId(0): spawn numbers start at 1, so no spawn's timer is it"
  assert dormant(state:, spawn: 1) && dormant(state:, spawn: 2)
    as "every spawn is dormant"
}

pub fn a_join_starts_exactly_the_spawns_within_1024_with_the_player_as_first_viewer_and_the_reply_comes_first_test() -> Nil {
  use <- owned_test.run(5000)
  // Sight is 1024 units, inclusive (`sight`): spawns 1 to 3 at 0, 500 and 1024
  // are seen from x 0; 1024.5 and 5000 are not.
  let #(state, _) = spawns.started(at: [0.0, 500.0, 1024.0, 1024.5, 5000.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let creatures = spawns.starts(taken)
  assert list.map(creatures, fn(start) { { start.1 }.spawn })
    == [
      spawn_source.Stored(id: SpawnId(1)),
      spawn_source.Stored(id: SpawnId(2)),
      spawn_source.Stored(id: SpawnId(3)),
    ]
    as "the three spawns in sight start, in the order of the spawns, and no other"
  let units = list.map(creatures, fn(start) { { start.1 }.unit_id })
  assert list.length(list.unique(list.prepend(units, 1))) == 4
    && list.all(units, fn(unit_id) { unit_id > 0 && unit_id < 1_048_576 })
    as "each creature is a unit of its own, and none is the player's unit 1"
  assert list.all(creatures, fn(start) {
    let WatchId(number) = start.0
    { start.1 }.life == number
  })
    as "a creature's life is the number of the watch it is started under"
  assert list.all(creatures, fn(start) {
    spawns.first_viewers(start: { start.1 })
    == [#(ConnectionId(1), map_support.stay(count: 1))]
  })
    as "each starts with the player as its first viewer, its unit 1, the map's first id, taken before the starts', and sends the 0x262 as it starts"
  let generations =
    list.map(creatures, fn(start) {
      let assert [#(_, _, generation)] = { start.1 }.viewers
        as "the player is the one first viewer"
      let assert Ok(map.Live(relations:, ..)) =
        map.spawn_state(
          state:,
          spawn: spawn_of_unit(creatures:, unit_id: { start.1 }.unit_id),
        )
      assert dict.get(relations, ConnectionId(1))
        == Ok(map.Relation(
          generation:,
          stay: map_support.stay(count: 1),
          state: map.AwaitingSnapshot,
        ))
        as "the map holds each first viewer's relation under the generation the start names, awaiting the creature's snapshot"
      generation
    })
  assert list.length(list.unique(generations)) == list.length(generations)
    as "each relation of the burst has a generation of its own"
  assert list.all(creatures, fn(start) { start.0 != WatchId(1) })
    && list.all(creatures, fn(start) { { start.1 }.life != 1 })
    as "no creature's life is the player's watch, 1: the player's watch is taken before the starts"
  assert spawns.creature_sends(taken) == []
    as "so no Watched follows a burst of starts"
  let labels =
    list.map(support.effects_of(taken), fn(effect) {
      case effect {
        step.Watch(..) -> "watch"
        OwnEffect(Reply(..)) -> "reply"
        OwnEffect(StartCreature(..)) -> "start"
        OwnEffect(Send(..)) -> "send"
        OwnEffect(StartServiceTimer(..)) | OwnEffect(CancelServiceTimer(..)) ->
          "timer"
        step.Unwatch(..) | step.Log(..) | step.Stop -> "other"
      }
    })
  assert list.take(labels, 2) == ["watch", "reply"]
    as "the Join is answered first"
  assert list.drop(labels, 2) == ["start", "start", "start"]
    as "then the starts"
  assert dormant(state:, spawn: 4) && dormant(state:, spawn: 5)
    as "a spawn beyond sight has no process and no state"
}

pub fn a_move_into_sight_starts_the_creature_with_the_player_as_first_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) =
    spawns.join(state:, at_ms: 6000, connection: 1, x: spawns.far)
  assert spawns.starts(taken) == [] as "far from every spawn, nothing starts"
  let #(_, taken) = spawns.move(state:, at_ms: 7000, connection: 1, x: 0.0)
  let #(_, creature) = the_start(taken)
  assert creature.spawn == spawn_source.Stored(id: SpawnId(1))
  assert spawns.first_viewers(start: creature)
    == [#(ConnectionId(1), map_support.stay(count: 1))]
    as "the creature starts for the player and sends its one 0x262 as it starts"
  assert spawns.creature_sends(taken) == []
}

pub fn the_last_viewer_leaving_sends_an_unwatched_and_the_creature_stops_between_60_and_70_seconds_later_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(_, creature) = the_start(taken)
  let #(state, taken) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
  assert spawns.creature_sends(taken) == [#(creature.unit_id, "Unseen by 1")]
    as "the player's loss of sight is told to the creature, which sends the 0x355"
  // The sweep timer started at 5000 fires every 10 s: 15000, 25000, ... The
  // creature has been idle since 7000, so it retires at the first sweep at or
  // after 67000, which is 75000: 68 s after the last viewer left.
  let sweeps =
    int.range(from: 1, to: 9, with: [], run: fn(times, count) {
      [spawns.started_at_ms + count * map_support.sweep_ms, ..times]
    })
    |> list.reverse
  let #(_, retired) =
    list.fold(sweeps, #(state, []), fn(held, at_ms) {
      let #(state, retired) = held
      let #(state, taken) = spawns.sweep(state:, at_ms:)
      case spawns.creature_sends(taken) {
        [] -> #(state, retired)
        [#(unit_id, "Retire")] -> #(state, [#(at_ms, unit_id), ..retired])
        _ -> panic as "a sweep sent something other than one Retire"
      }
    })
  assert retired == [#(75_000, creature.unit_id)]
    as "not at the sweep at 65000, when it has been idle 58 s, and at the first after 60 s"
}

pub fn a_spawn_seen_again_before_the_idle_stop_is_not_restarted_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(_, creature) = the_start(taken)
  let #(state, _) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
  let #(state, taken) =
    spawns.move(state:, at_ms: 30_000, connection: 1, x: 0.0)
  assert spawns.starts(taken) == [] as "the same creature runs: nothing starts"
  assert spawns.creature_sends(taken) == [#(creature.unit_id, "Seen by 1")]
    as "it is told the player sees it again, and sends its 0x262 once more"
  let #(_, taken) = spawns.sweep(state:, at_ms: 75_000)
  assert spawns.creature_sends(taken) == []
    as "a creature with a viewer is never retired, however long ago it was idle"
}

pub fn a_spawn_stopped_and_seen_again_keeps_its_unit_id_under_a_new_life_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(first_watch, first) = the_start(taken)
  let #(state, _) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
  let #(state, taken) = spawns.sweep(state:, at_ms: 75_000)
  assert spawns.creature_sends(taken) == [#(first.unit_id, "Retire")]
  let #(state, taken) =
    spawns.feed(state:, at_ms: 75_100, event: WatchEnded(first_watch))
  assert spawns.player_sends(taken) == []
    as "a clean stop sends no Gone: the 0x355 went with the last viewer"
  assert spawns.starts(taken) == [] && spawns.timers(taken) == []
    as "the spawn is dormant, with no restart timer"
  assert dormant(state:, spawn: 1)
  let #(_, taken) = spawns.move(state:, at_ms: 90_000, connection: 1, x: 0.0)
  let #(second_watch, second) = the_start(taken)
  assert second.unit_id == first.unit_id
    as "a spawn has one unit id for the run, reused after a clean stop (death.creature_respawn)"
  assert second_watch != first_watch && second.life != first.life
    as "under a new life, so its address is not the stopped creature's"
  assert spawns.first_viewers(start: second)
    == [#(ConnectionId(1), map_support.stay(count: 1))]
  assert spawns.creature_sends(taken) == []
}

pub fn a_spawn_seen_while_its_creature_retires_restarts_only_after_the_creatures_end_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(first_watch, first) = the_start(taken)
  let #(state, _) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
  let #(state, _) = spawns.sweep(state:, at_ms: 75_000)
  let #(state, taken) =
    spawns.move(state:, at_ms: 75_050, connection: 1, x: 0.0)
  assert spawns.starts(taken) == [] && spawns.creature_sends(taken) == []
    as "the creature has been told to stop: nothing starts and it is told nothing"
  let #(_, taken) =
    spawns.feed(state:, at_ms: 75_100, event: WatchEnded(first_watch))
  let #(second_watch, second) = the_start(taken)
  assert second.unit_id == first.unit_id && second_watch != first_watch
    as "at its end a creature starts under the same unit id and a new life"
  assert spawns.first_viewers(start: second)
    == [#(ConnectionId(1), map_support.stay(count: 1))]
    as "with the player who sees the spawn now as its first viewer"
}

pub fn a_player_who_saw_a_retiring_spawn_and_went_away_before_its_end_leaves_it_dormant_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, _) = the_start(taken)
  let #(state, _) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
  let #(state, _) = spawns.sweep(state:, at_ms: 75_000)
  let #(state, _) = spawns.move(state:, at_ms: 75_050, connection: 1, x: 0.0)
  let #(state, _) =
    spawns.move(state:, at_ms: 75_060, connection: 1, x: spawns.far)
  let #(state, taken) =
    spawns.feed(state:, at_ms: 75_100, event: WatchEnded(watch))
  assert spawns.starts(taken) == [] && dormant(state:, spawn: 1)
    as "the player who was held has gone: the creature's end leaves the spawn dormant"
  let #(state, _) = spawns.move(state:, at_ms: 75_200, connection: 1, x: 0.0)
  let #(state, taken) =
    spawns.join(state:, at_ms: 75_300, connection: 2, x: 0.0)
  assert spawns.starts(taken) == []
    as "the creature started by the first move is already running: the joiner is told Watched"
  let #(state, _) = spawns.leave(state:, at_ms: 75_400, connection: 2)
  let #(state, _) = spawns.leave(state:, at_ms: 75_500, connection: 1)
  let #(_, taken) = spawns.sweep(state:, at_ms: 150_000)
  assert list.length(spawns.creature_sends(taken)) == 1
    as "and after both left, the sweep retires it"
}

pub fn a_spawn_that_crashed_and_restarted_keeps_its_new_unit_id_after_a_clean_stop_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(first_watch, first) = the_start(taken)
  let #(state, _) =
    spawns.feed(state:, at_ms: 7000, event: WatchEnded(first_watch))
  let #(state, taken) =
    spawns.feed(
      state:,
      at_ms: 67_000,
      event: OwnEvent(ServiceTimerFired(timer: step.TimerId(1))),
    )
  let #(second_watch, second) = the_start(taken)
  assert second.unit_id != first.unit_id
  let #(state, _) =
    spawns.move(state:, at_ms: 68_000, connection: 1, x: spawns.far)
  let #(state, _) = spawns.sweep(state:, at_ms: 135_000)
  let #(state, _) =
    spawns.feed(state:, at_ms: 135_100, event: WatchEnded(second_watch))
  let #(_, taken) = spawns.move(state:, at_ms: 140_000, connection: 1, x: 0.0)
  let #(_, third) = the_start(taken)
  assert third.unit_id == second.unit_id
    as "the unit id the restart took is the spawn's for the rest of the run"
}

pub fn a_creature_that_crashes_while_retiring_is_taken_as_retired_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, _) = the_start(taken)
  let #(state, _) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
  let #(state, _) = spawns.sweep(state:, at_ms: 75_000)
  let #(state, taken) =
    spawns.feed(state:, at_ms: 75_010, event: WatchEnded(watch))
  assert spawns.player_sends(taken) == [] && spawns.timers(taken) == []
    as "no client shows the unit: no Gone and no restart timer"
  assert dormant(state:, spawn: 1)
}

pub fn a_spawn_whose_creature_crashes_waits_the_respawn_time_of_its_creatures_kind_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    spawns.started_with(
      at: [0.0],
      kinds: Kinds(
        default: Kind(
          respawn_ms: map_support.respawn_ms,
          attack_spell4_id: Spell4Id(5649),
          alternate_spell4_ids: [],
          attack_interval_ms: 1500,
          guard: option.None,
          specials: [],
        ),
        by_creature: dict.from_list([
          #(
            73_464,
            Kind(
              respawn_ms: 5000,
              attack_spell4_id: Spell4Id(5649),
              alternate_spell4_ids: [],
              attack_interval_ms: 1500,
              guard: option.None,
              specials: [],
            ),
          ),
        ]),
      ),
    )
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, _) = the_start(taken)
  let #(_, taken) = spawns.feed(state:, at_ms: 7000, event: WatchEnded(watch))
  assert spawns.timers(taken) == [#(1, 5000)]
    as "the Virtual Battle Beast (Creature2 73464) has a kind of its own, 5 s, which the crash restart waits instead of the default's 60 s: one number serves the corpse and the restart"
}

pub fn a_creature_that_crashes_while_seen_is_gone_to_every_player_and_returns_under_a_new_unit_id_if_seen_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, first) = the_start(taken)
  let #(state, _) =
    spawns.join(state:, at_ms: 6100, connection: 2, x: spawns.far)
  let #(state, taken) =
    spawns.feed(state:, at_ms: 7000, event: WatchEnded(watch))
  let crashed = taken
  assert spawns.player_sends(taken)
    == [
      #(1, "Gone " <> int.to_string(first.unit_id)),
      #(2, "Gone " <> int.to_string(first.unit_id)),
    ]
    as "every player in the map is told the unit is gone, also one that did not see it"
  assert spawns.timers(taken) == [#(1, map_support.respawn_ms)]
    as "the spawn waits the respawn time, under the timer of its own number"
  assert spawns.starts(taken) == [] as "and is not started again at once"
  let #(_, taken) =
    spawns.feed(
      state:,
      at_ms: 67_000,
      event: OwnEvent(ServiceTimerFired(timer: step.TimerId(1))),
    )
  let #(_, second) = the_start(taken)
  assert second.unit_id != first.unit_id && second.unit_id > 0
    as "the unit id was given up with the Gone, so the new creature has another"
  assert spawns.first_viewers(start: second)
    == [#(ConnectionId(1), map_support.stay(count: 1))]
    as "the player in sight is the new creature's first viewer"
  assert spawns.creature_sends(crashed) == []
    as "the creature that ended is told nothing: no Unseen to a dead creature"
  let assert [#(_, _, first_generation)] = first.viewers
  let assert [#(_, _, second_generation)] = second.viewers
  assert first_generation != second_generation
    as "the new life's first viewer holds a generation the map never gave before"
  // The same spawn's next life, started by the map after the creature expired, killed
  // before it answered its first `Seen`.
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, first) = the_start(taken)
  let #(state, _) =
    spawns.join(state:, at_ms: 6100, connection: 2, x: spawns.far)
  let #(state, _) =
    spawns.expired(
      state:,
      at_ms: 6500,
      unit_id: first.unit_id,
      life: first.life,
    )
  assert map.spawn_state(state:, spawn: SpawnId(1))
    == Ok(map.Respawning(unit_id: first.unit_id, life: first.life))
    as "the creature expired: its spawn is respawning"
  let #(state, taken) =
    spawns.feed(state:, at_ms: 6600, event: WatchEnded(watch))
  let #(next_watch, next) = the_start(taken)
  assert next.unit_id == first.unit_id
    && map.spawn_state(state:, spawn: SpawnId(1))
    == Ok(map.Live(
      unit_id: next.unit_id,
      life: next.life,
      relations: dict.from_list(
        list.map(next.viewers, fn(viewer) {
          #(
            viewer.0,
            map.Relation(
              generation: viewer.2,
              stay: viewer.1,
              state: map.AwaitingSnapshot,
            ),
          )
        }),
      ),
      idle_since_ms: option.None,
    ))
    as "the next life's spawn is live with its viewer awaiting its first snapshot"
  let #(ended, taken) =
    spawns.feed(state:, at_ms: 6700, event: WatchEnded(next_watch))
  assert spawns.player_sends(taken)
    == [
      #(1, "Gone " <> int.to_string(next.unit_id)),
      #(2, "Gone " <> int.to_string(next.unit_id)),
    ]
    as "exactly one Gone for each player, though no viewer was shown the unit"
  assert spawns.timers(taken) == [#(1, map_support.respawn_ms)]
    as "the spawn waits the kind's respawn time"
  assert spawns.creature_sends(taken) == []
    as "and the creature that ended is told no Unseen"
  // The same watch ended a second time: the map no longer holds it for a creature.
  let #(again, taken) =
    spawns.feed(state: ended, at_ms: 6800, event: WatchEnded(next_watch))
  assert again == ended
    as "a second end of the same creature watch changes nothing"
  assert spawns.player_sends(taken) == []
    && spawns.timers(taken) == []
    && spawns.starts(taken) == []
    as "and sends no Gone, starts no timer and starts no creature"
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "and writes one error line"
  assert string.contains(
    line.text,
    "a watch ended that names no player of the map",
  )
    as "that says the watch names no player: it is read as a player's end"
}

pub fn a_restart_timer_that_fires_with_no_one_in_sight_leaves_the_spawn_dormant_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(watch, _) = the_start(taken)
  let #(state, _) = spawns.feed(state:, at_ms: 7000, event: WatchEnded(watch))
  let #(state, _) =
    spawns.move(state:, at_ms: 8000, connection: 1, x: spawns.far)
  let #(state, taken) =
    spawns.feed(
      state:,
      at_ms: 67_000,
      event: OwnEvent(ServiceTimerFired(timer: step.TimerId(1))),
    )
  assert spawns.starts(taken) == []
    as "no one sees the spawn: no creature starts"
  assert dormant(state:, spawn: 1)
}

pub fn a_creature_that_does_not_start_leaves_its_spawn_empty_for_the_run_and_the_others_appear_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0, 100.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [#(first_watch, first), #(_, second)] = spawns.starts(taken)
    as "two creatures start in the burst"
  assert spawns.first_viewers(start: first)
    == [#(ConnectionId(1), map_support.stay(count: 1))]
    && spawns.first_viewers(start: second)
    == [#(ConnectionId(1), map_support.stay(count: 1))]
    as "both start for the player, whatever the first's start does"
  let #(state, taken) =
    spawns.feed(
      state:,
      at_ms: 6001,
      event: OwnEvent(CreatureNotStarted(
        watch: first_watch,
        reason: "the creature supervisor is not running",
      )),
    )
  let assert [line] = support.logs(taken)
    as "the map says that the creature did not start, once"
  assert line.level == LogError
    as "a creature that does not start is the server's failure, an error line"
  assert string.contains(line.text, "the creature supervisor is not running")
    as "the line gives the reason the supervisor reported"
  assert line.about.map == Some(spawns.ship)
  assert spawns.starts(taken) == [] && spawns.timers(taken) == []
    as "the spawn stays empty: no later creature is started for it"
  assert map.spawn_state(state:, spawn: SpawnId(1)) == Ok(map.Failed)
  let #(_, taken) = spawns.move(state:, at_ms: 7000, connection: 1, x: 10.0)
  assert spawns.starts(taken) == [] && spawns.creature_sends(taken) == []
    as "a move in sight of the failed spawn starts nothing and tells nothing"
}

pub fn a_leave_right_after_a_burst_sends_unwatched_to_each_creature_of_the_player_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = spawns.started(at: [0.0, 100.0, 200.0])
  let #(state, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let units = list.map(spawns.starts(taken), fn(start) { { start.1 }.unit_id })
  let #(state, taken) = spawns.leave(state:, at_ms: 6001, connection: 1)
  assert spawns.creature_sends(taken)
    == list.append(
      list.map(units, fn(unit_id) { #(unit_id, "Unseen by 1") }),
      list.map(units, fn(unit_id) { #(unit_id, "CasterGone by 1") }),
    )
    as "the player's creatures are told it no longer sees them, then that it is gone, each in the order of the spawns"
  let #(_, taken) = spawns.sweep(state:, at_ms: 75_000)
  assert spawns.creature_sends(taken)
    == list.map(units, fn(unit_id) { #(unit_id, "Retire") })
    as "and each stops at the first sweep after the idle stop"
}

/// The seven spawns of `with_a_spawn_in_each_state`: the map, the watches of the two
/// players' connections, and the unit id and life of the creatures of spawns 1 to 4,
/// which run.
type SpawnStates {
  SpawnStates(
    state: State,
    first_watch: step.WatchId,
    second_watch: step.WatchId,
    units: List(#(Int, Int)),
  )
}

/// A map of seven spawns, three near the players and four far from them, with players 1
/// and 2 standing among the near ones: spawn 1 is live, 2 respawning (its creature
/// expired), 3 releasing (a use released it), 4 retiring (no one has seen it for the idle
/// stop), 5 waiting to restart (its creature crashed), 6 failed (its creature did not
/// start) and 7 dormant (its creature retired and ended with no one to see it).
fn with_a_spawn_in_each_state() -> SpawnStates {
  let near = [0.0, 20.0, 40.0]
  let far = list.map([0.0, 20.0, 40.0, 60.0], fn(x) { spawns.far +. x })
  let state =
    spawns.started_with_spawns(
      spawns: list.index_map(list.append(near, far), fn(x, index) {
        spawn_support.battle_beast(number: index + 1, x:)
      }),
    )
  let #(state, joined) =
    spawns.join(state:, at_ms: 6000, connection: 1, x: spawns.far)
  let assert [#(first_watch, _)] = support.watches(joined)
    as "the join opens a watch on the connection"
  let life_of = fn(state, spawn) { spawns.creature_of(state:, spawn:).1 }
  let #(state, _) =
    spawns.creature_ended(
      state:,
      at_ms: 6100,
      watch: WatchId(life_of(state, 5)),
    )
  let #(state, _) =
    spawns.creature_not_started(
      state:,
      at_ms: 6200,
      watch: WatchId(life_of(state, 6)),
      reason: "planted",
    )
  let #(state, _) = spawns.move(state:, at_ms: 6300, connection: 1, x: 0.0)
  let #(state, joined) = spawns.join(state:, at_ms: 6400, connection: 2, x: 0.0)
  let assert [#(second_watch, _)] = support.watches(joined)
    as "the join opens a watch on the connection"
  let #(unit_2, life_2) = spawns.creature_of(state:, spawn: 2)
  let #(state, _) =
    spawns.expired(state:, at_ms: 6500, unit_id: unit_2, life: life_2)
  let #(unit_3, _) = spawns.creature_of(state:, spawn: 3)
  let #(state, _) = spawns.released(state:, at_ms: 6600, unit_id: unit_3)
  let #(state, _) = spawns.sweep(state:, at_ms: 80_000)
  let #(state, _) =
    spawns.creature_ended(
      state:,
      at_ms: 80_100,
      watch: WatchId(life_of(state, 7)),
    )
  let states =
    list.map([1, 2, 3, 4, 5, 6, 7], fn(spawn) {
      map.spawn_state(state:, spawn: SpawnId(spawn))
    })
  let assert [
    Ok(map.Live(..)),
    Ok(map.Respawning(..)),
    Ok(map.Releasing(..)),
    Ok(map.Retiring(..)),
    Ok(map.WaitingForRestart),
    Ok(map.Failed),
    Error(Nil),
  ] = states
    as "the seven spawns are live, respawning, releasing, retiring, waiting to restart, failed and dormant"
  SpawnStates(
    state:,
    first_watch:,
    second_watch:,
    units: list.map([1, 2, 3, 4], fn(spawn) {
      spawns.creature_of(state:, spawn:)
    }),
  )
}

pub fn a_leave_and_a_connections_end_tell_every_running_creature_that_the_caster_is_gone_and_no_other_test() -> Nil {
  use <- owned_test.run(10_000)
  let scene = with_a_spawn_in_each_state()
  let gone = fn(connection) {
    list.map(scene.units, fn(unit) {
      #(unit.0, "CasterGone by " <> int.to_string(connection))
    })
  }
  // The player of connection 1 tells the live and the retiring creature before it leaves.
  let told = fn(state, unit: #(Int, Int), at_ms) {
    spawns.tell_creature(
      state:,
      at_ms:,
      from: 1,
      stay_count: 1,
      unit_id: unit.0,
      life: unit.1,
      payload: map_message.ModifierEnds(source: inbound_support.source()),
    )
  }
  let assert [live, _, _, retiring] = scene.units
  let #(state, first) = told(scene.state, live, 80_200)
  let #(state, second) = told(state, retiring, 80_210)
  assert spawns.creature_sends(first) == [#(live.0, "Told ModifierEnds by 1")]
    && spawns.creature_sends(second)
    == [#(retiring.0, "Told ModifierEnds by 1")]
    as "the relays the connection sent are delivered before its leave"
  let rows = [
    #("the leave of player 1", 1, fn(state) {
      spawns.leave(state:, at_ms: 80_300, connection: 1)
    }),
    #("the end of the watch of player 2", 2, fn(state) {
      spawns.creature_ended(state:, at_ms: 80_300, watch: scene.second_watch)
    }),
  ]
  list.each(rows, fn(row) {
    let #(name, connection, remove) = row
    let #(after, taken) = remove(state)
    let sends = spawns.creature_sends(taken)
    let unseens =
      list.filter(sends, fn(sent) { string.starts_with(sent.1, "Unseen by ") })
    assert unseens != []
      as { name <> " ends the sight of the creatures the player saw" }
    assert sends == list.append(unseens, gone(connection))
      as {
        name
        <> " tells each running creature, live, respawning, releasing and retiring, in spawn order, one CasterGone of the connection, after the Unseens of the removal, and the creatures that do not run (waiting, failed, dormant) nothing"
      }
    let other = case connection {
      1 -> 2
      _ -> 1
    }
    assert !list.contains(
      list.map(sends, fn(sent) { sent.1 }),
      "CasterGone by " <> int.to_string(other),
    )
      as { name <> " tells nothing of the other player" }
    // The connection is no longer in the map: its end or its leave again finds no player.
    let #(_, again) = remove(after)
    assert list.filter(spawns.creature_sends(again), fn(sent) {
        string.starts_with(sent.1, "CasterGone")
      })
      == []
      as { name <> " again finds no player and tells no creature" }
  })
  let #(_, stranger) = spawns.leave(state:, at_ms: 80_300, connection: 9)
  assert spawns.creature_sends(stranger) == []
    && list.length(support.logs_of(step: stranger, level: LogError)) == 1
    as "a connection that is not in the map tells no creature: one error line"
}
