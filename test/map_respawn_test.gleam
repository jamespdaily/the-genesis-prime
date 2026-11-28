//// A creature's next life, started by its map (`genesis_prime/world_map/map`), run as the
//// pure rule it is: inputs in, new state and effects out, the clock driven through the
//// inputs' times. Expected values come from these places.
//// - The Design of run A (issue 1410), 4.1 and 4.2: a creature that lay dead until its
////   corpse timer tells its map `Expired` and stops; the map holds the spawn `Respawning`
////   and starts the next life under the same unit id when the creature ends, for the
////   players who see the spawn then, with fresh relations under generations it never gave
////   before, and the ring of the spawn in the start (`CreatureStart.ring`), so one fight
////   starts over every player of it.
//// - The ring (the doc comment of `genesis_prime/world_map/map`): a ready, living,
////   unstealthed player within the creature's aggro range of its spawn, 10 units
////   (migration 0010), of a faction the creature is hostile to; the tests' players are
////   Dominion, which the Virtual Defense Dagun (Creature2 73465) is hostile to
////   (`Creature2.73465`, `0x1403ad540`). Sight is 1024 units.
//// - The server's choice on races: where a design removes a
////   race the server takes the result the race-free order gives: a player whose death or
////   stealth the map took before the next life starts is not aggroed at the respawn, since
////   the ring holds no dead and no stealthed player; a player who wakes in a ring is
////   aggroed on waking in every order (the server's choice).
//// - The used-object release time, 30 s (`used_object_release_ms`), which a spawn waits
////   instead of its kind's respawn time when a player's use released its creature.

import connection_rule_support as support
import genesis_prime/map/message as map_message
import genesis_prime/shared/strike_tell
import genesis_prime/shared/unit_news
import genesis_prime/step.{LogError, WatchId}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/stay.{type Stay}
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import map_spawn_support as spawns
import map_support
import owned_test
import spawn_support

/// The release time, the server's choice (`used_object_release_ms`).
const release_ms = 30_000

/// A Virtual Defense Dagun's spawn at x = 100, hostile to the Dominion.
fn dagun() -> Spawn {
  spawn_support.dagun(number: 1, x: 100.0)
}

fn first_stay() -> Stay {
  map_support.stay(count: 1)
}

/// A map with a Dagun at x = 100 and two players: player 1 at x = 95, ready, in its ring,
/// whose join starts the creature, and player 2 at x = 300, which sees it from outside
/// the ring.
fn seen_by_two() -> State {
  let state = spawns.started_with_spawns(spawns: [dagun()])
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 95.0)
  let #(state, _) = spawns.ready(state:, at_ms: 6010, connection: 1)
  let #(state, _) = spawns.join(state:, at_ms: 6100, connection: 2, x: 300.0)
  state
}

/// The same after the creature expired: the spawn is respawning, and the creature's unit
/// and life.
fn respawning() -> #(State, Int, Int) {
  let state = seen_by_two()
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let #(state, _) = spawns.expired(state:, at_ms: 7000, unit_id:, life:)
  #(state, unit_id, life)
}

/// The spawn's state, which the rows below read after each step.
fn spawn_state(state state: State) -> Result(map.SpawnState, Nil) {
  map.spawn_state(state:, spawn: SpawnId(1))
}

pub fn a_spawn_whose_creature_expired_is_respawning_and_each_later_event_has_one_result_for_each_state_test() -> Nil {
  use <- owned_test.run(5000)
  let state = seen_by_two()
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let first_generations = [
    spawns.generation_of(state:, spawn: 1, connection: 1),
    spawns.generation_of(state:, spawn: 1, connection: 2),
  ]

  // `Live` and `Expired`.
  let #(respawning, expired) =
    spawns.expired(state:, at_ms: 7000, unit_id:, life:)
  assert spawn_state(state: respawning) == Ok(map.Respawning(unit_id:, life:))
    as "the creature that expired is respawning, under the same unit id and life"
  assert support.effects_of(expired) == []
    as "no Unseen to the creature, none to a player and no Gone: the creature removed its unit from every viewer before it expired"
  assert spawns.relation_of(state: respawning, spawn: 1, connection: 1) == None
    && spawns.relation_of(state: respawning, spawn: 1, connection: 2) == None
    as "the relations of that life ended"
  assert map.unit_id_of(state: respawning, spawn: SpawnId(1)) == Ok(unit_id)
    as "the unit id is kept"

  // The rows an `Expired` changes nothing in.
  let retiring = {
    let #(state, _) =
      spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
    let #(state, _) =
      spawns.move(state:, at_ms: 7000, connection: 2, x: spawns.far)
    spawns.sweep(state:, at_ms: 80_000).0
  }
  assert spawn_state(state: retiring) == Ok(map.Retiring(unit_id:, life:))
  let releasing = spawns.released(state:, at_ms: 7000, unit_id:).0
  let assert Ok(map.Releasing(wait_ms:, ..)) = spawn_state(state: releasing)
    as "a use released the creature"
  assert wait_ms == release_ms
  list.each(
    [
      #("an expiry of another life", state, unit_id, life + 1),
      #("an expiry of another unit", state, unit_id + 1, life),
      #("a second expiry", respawning, unit_id, life),
      #("an expiry of a retiring creature", retiring, unit_id, life),
      #("an expiry of a creature that was released", releasing, unit_id, life),
    ],
    fn(row) {
      let #(held, unit, expiring_life) = #(row.1, row.2, row.3)
      let #(after, taken) =
        spawns.expired(
          state: held,
          at_ms: 80_100,
          unit_id: unit,
          life: expiring_life,
        )
      assert spawn_state(state: after) == spawn_state(state: held) as row.0
      assert support.effects_of(taken) == [] as row.0
    },
  )

  // `Respawning` and the creature's end, with two viewers: the next life.
  let #(started, ended) =
    spawns.creature_ended(state: respawning, at_ms: 7100, watch: WatchId(life))
  let assert [#(watch, next)] = spawns.starts(ended)
    as "the next life starts at once"
  let WatchId(next_life) = watch
  assert next.unit_id == unit_id && next.life == next_life && next_life != life
    as "under the same unit id and a new life, the number of its watch"
  assert spawns.first_viewers(start: next)
    == [map_support.address(number: 1), map_support.address(number: 2)]
    as "for each player who sees the spawn, in connection order, each in its stay"
  assert list.all(next.viewers, fn(viewer) {
      !list.contains(first_generations, viewer.1)
    })
    && {
      list.map(next.viewers, fn(viewer) { viewer.1 })
      |> list.unique
      |> list.length
    }
    == 2
    as "each under a generation the map never gave before"
  assert spawns.ring_of(start: next) == [1]
    as "the ring holds the ready player standing in it"
  assert spawns.creature_sends(ended) == [] && spawns.player_sends(ended) == []
    as "no separate Approached, no Gone"
  let assert [#(_, second_generation)] = list.drop(next.viewers, 1)
  assert spawns.relation_of(state: started, spawn: 1, connection: 2)
    == Some(map.Relation(
      generation: second_generation,
      stay: first_stay(),
      state: map.AwaitingSnapshot,
    ))
    as "its relation awaits the new life's snapshot"

  // No player sees the spawn when the creature ends: dormant, the unit id kept.
  let #(away, _) =
    spawns.move(state: respawning, at_ms: 7010, connection: 1, x: spawns.far)
  let #(away, _) =
    spawns.move(state: away, at_ms: 7020, connection: 2, x: spawns.far)
  let #(dormant, ended) =
    spawns.creature_ended(state: away, at_ms: 7100, watch: WatchId(life))
  assert spawns.starts(ended) == [] && spawn_state(state: dormant) == Error(Nil)
    as "the spawn is dormant"
  assert map.unit_id_of(state: dormant, spawn: SpawnId(1)) == Ok(unit_id)
    as "with its unit id kept"
  let #(_, back) =
    spawns.move(state: dormant, at_ms: 7200, connection: 1, x: 95.0)
  let assert [#(_, again)] = spawns.starts(back)
  assert again.unit_id == unit_id
    as "a player who sees it again finds the same unit"

  // A viewer that joined again in the gap is the relation's, in its new stay.
  let #(joined, taken) =
    spawns.join_in_stay(
      state: respawning,
      at_ms: 7010,
      connection: 2,
      stay_count: 2,
      x: 300.0,
      alive: True,
      hidden: set.new(),
    )
  assert spawns.lives_told(taken) == [] && spawns.starts(taken) == []
    as "a respawning spawn is told nothing of a join again"
  let #(_, ended) =
    spawns.creature_ended(state: joined, at_ms: 7100, watch: WatchId(life))
  let assert [#(_, next)] = spawns.starts(ended)
  assert spawns.first_viewers(start: next)
    == [map_support.address(number: 1), map_support.address(number: 2)]
    as "the player's new stay is the relation's"

  // `Respawning` and a release: the spawn waits the release time at the creature's end.
  let #(released, taken) =
    spawns.released(state: respawning, at_ms: 7010, unit_id:)
  assert spawn_state(state: released)
    == Ok(map.Releasing(
      unit_id:,
      life:,
      wait_ms: release_ms,
      relations: dict.new(),
    ))
    as "a respawning creature that was released is one that ends and waits the release time"
  assert spawns.creature_sends(taken) == []
    as "the creature is stopping: nothing is told it"
  let #(again, taken) = spawns.released(state: released, at_ms: 7020, unit_id:)
  assert spawn_state(state: again) == spawn_state(state: released)
    && support.effects_of(taken) == []
    as "a second release finds a releasing spawn and changes nothing"
  let #(waiting, ended) =
    spawns.creature_ended(state: released, at_ms: 7100, watch: WatchId(life))
  assert spawns.player_sends(ended)
    == [
      #(1, "Gone " <> int.to_string(unit_id)),
      #(2, "Gone " <> int.to_string(unit_id)),
    ]
    as "every player is sent Gone"
  assert spawns.timers(ended) == [#(1, release_ms)]
    && spawns.starts(ended) == []
    as "and the spawn waits the release time, never an immediate restart"
  assert map.unit_id_of(state: waiting, spawn: SpawnId(1)) == Error(Nil)
    as "the unit id is given up"

  // The ends of the other states.
  let #(restarted, ended) =
    spawns.creature_ended(
      state: spawns.move(state: retiring, at_ms: 80_050, connection: 1, x: 95.0).0,
      at_ms: 80_100,
      watch: WatchId(life),
    )
  let assert [#(_, retired)] = spawns.starts(ended)
    as "a retiring creature's spawn restarts as it did"
  assert retired.unit_id == unit_id
    && spawns.player_sends(ended) == []
    && spawns.timers(ended) == []
  assert spawn_state(state: restarted) != Error(Nil)
  let #(_, ended) =
    spawns.creature_ended(state: releasing, at_ms: 7100, watch: WatchId(life))
  assert spawns.timers(ended) == [#(1, release_ms)]
    && spawns.starts(ended) == []
    as "a released creature's spawn waits the release time"
  let #(_, ended) =
    spawns.creature_ended(state:, at_ms: 7100, watch: WatchId(life))
  assert spawns.timers(ended) == [#(1, map_support.respawn_ms)]
    && spawns.player_sends(ended)
    == [
      #(1, "Gone " <> int.to_string(unit_id)),
      #(2, "Gone " <> int.to_string(unit_id)),
    ]
    && spawns.starts(ended) == []
    as "a live creature that ends with no expiry crashed: Gone to every player and the kind's respawn time"
}

/// A player of connection `connection` who joins at `x` at `at_ms`, and is ready 10 ms
/// later when `ready` is True.
fn joined(
  state state: State,
  connection connection: Int,
  x x: Float,
  at_ms at_ms: Int,
  ready ready: Bool,
) -> State {
  let #(state, _) = spawns.join(state:, at_ms:, connection:, x:)
  case ready {
    True -> spawns.ready(state:, at_ms: at_ms + 10, connection:).0
    False -> state
  }
}

fn numbers(addresses: List(UnitAddress)) -> List(Int) {
  list.map(addresses, fn(address) { unit_address.number(address:) })
}

pub fn a_respawn_start_carries_the_ring_of_ready_living_unstealthed_players_and_no_separate_approached_test() -> Nil {
  use <- owned_test.run(5000)
  // Players at x = 95 to 105 stand in the Dagun's ring (10 units from x = 100), 80 and 70
  // outside it.
  let state = spawns.started_with_spawns(spawns: [dagun()])
  let state = joined(state:, connection: 1, x: 95.0, at_ms: 6000, ready: True)
  let state = joined(state:, connection: 2, x: 96.0, at_ms: 6100, ready: False)
  let state = joined(state:, connection: 3, x: 97.0, at_ms: 6200, ready: True)
  let #(state, _) =
    spawns.stealth(state:, at_ms: 6300, connection: 3, stealthed: True)
  let state = joined(state:, connection: 4, x: 98.0, at_ms: 6400, ready: True)
  let #(state, _) =
    spawns.life(state:, at_ms: 6500, connection: 4, alive: False)
  let state = joined(state:, connection: 5, x: 80.0, at_ms: 6600, ready: True)
  let state = joined(state:, connection: 6, x: 99.0, at_ms: 6700, ready: True)
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let #(state, _) = spawns.expired(state:, at_ms: 7000, unit_id:, life:)
  assert spawn_state(state:) == Ok(map.Respawning(unit_id:, life:))
    as "the creature expired"
  // In the gap between the expiry and the creature's end: player 6 leaves sight, player 7
  // comes into sight outside the ring, and player 8 comes into the ring and is ready.
  let #(state, _) =
    spawns.move(state:, at_ms: 7010, connection: 6, x: spawns.far)
  let state = joined(state:, connection: 7, x: 70.0, at_ms: 7020, ready: True)
  let state = joined(state:, connection: 8, x: 105.0, at_ms: 7030, ready: True)
  let #(_, ended) =
    spawns.creature_ended(state:, at_ms: 7100, watch: WatchId(life))
  let assert [#(_, next)] = spawns.starts(ended)
  assert numbers(spawns.first_viewers(start: next)) == [1, 2, 3, 4, 5, 7, 8]
    as "every player who sees the spawn when the creature ends is a viewer, one that came into sight in the gap outside the ring too (it is shown the 0x262 and no aggro), and the one that left sight is not"
  assert spawns.ring_of(start: next) == [1, 8]
    as "the ring holds the ready, living, unstealthed players standing in it, in connection order: not the one still loading, the stealthed one, the dead one, the ones outside it nor the one that left sight"
  assert spawns.creature_sends(ended) == []
    as "no Approached follows the start: the creature takes the ring from it"
}

/// What a player's life or stealth does at the map.
type Change {
  Death
  Stealth
  Wake
}

/// When the map takes it, against the creature's expiry and the start of its next life.
type When {
  BeforeExpiry
  BetweenExpiryAndStart
  AfterStart
}

/// The creature live with player 1 ready in its ring (dead already for a wake) and player
/// 2 outside it.
fn scene_of(change change: Change) -> State {
  let state = seen_by_two()
  case change {
    Wake -> spawns.life(state:, at_ms: 6500, connection: 1, alive: False).0
    Death | Stealth -> state
  }
}

fn changed(
  state state: State,
  change change: Change,
  at_ms at_ms: Int,
) -> #(State, step.ServiceStep(map_message.Outgoing)) {
  case change {
    Death -> spawns.life(state:, at_ms:, connection: 1, alive: False)
    Stealth -> spawns.stealth(state:, at_ms:, connection: 1, stealthed: True)
    Wake -> spawns.life(state:, at_ms:, connection: 1, alive: True)
  }
}

/// The ring of the next life's start, what the change told creatures (by life), the
/// expiring life and the next life, when the map takes the change at `when`.
fn ring_and_told(
  change change: Change,
  when when: When,
) -> #(List(Int), List(#(Int, String)), Int, Int) {
  let state = scene_of(change:)
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let #(state, told) = case when {
    BeforeExpiry -> {
      let #(state, taken) = changed(state:, change:, at_ms: 6900)
      #(state, spawns.lives_told(taken))
    }
    BetweenExpiryAndStart | AfterStart -> #(state, [])
  }
  let #(state, _) = spawns.expired(state:, at_ms: 7000, unit_id:, life:)
  assert spawn_state(state:) == Ok(map.Respawning(unit_id:, life:))
    as "the creature expired"
  let #(state, told) = case when {
    BetweenExpiryAndStart -> {
      let #(state, taken) = changed(state:, change:, at_ms: 7050)
      #(state, spawns.lives_told(taken))
    }
    BeforeExpiry | AfterStart -> #(state, told)
  }
  let #(state, ended) =
    spawns.creature_ended(state:, at_ms: 7100, watch: WatchId(life))
  let assert [#(_, next)] = spawns.starts(ended)
  assert spawns.creature_sends(ended) == []
    as "no Approached follows the start, whenever the change was taken"
  let told = case when {
    AfterStart -> spawns.lives_told(changed(state:, change:, at_ms: 7200).1)
    BeforeExpiry | BetweenExpiryAndStart -> told
  }
  #(spawns.ring_of(start: next), told, life, next.life)
}

pub fn a_death_a_stealth_or_a_wake_decides_the_new_lifes_ring_by_whether_the_map_took_it_before_the_start_test() -> Nil {
  use <- owned_test.run(5000)
  // Race-free results (Design run A, 4.1; the server's choice): a death or a stealth
  // the map took before the next life starts leaves the player out of its ring, where a
  // corpse timer that fired in the creature first aggroed the body or the stealthed
  // player; one taken after the start is the new life's own to handle, as for any creature
  // that fights. A player who wakes is aggroed on waking in every order (the server's choice).
  // A spawn that is respawning is told nothing: `PlayerDied`, `Withdrew` and `Approached`
  // go to a live creature only.
  list.each(
    [
      #("a death before the expiry", Death, BeforeExpiry, [], fn(old, _) {
        [#(old, "PlayerDied by 1")]
      }),
      #("a death in the gap", Death, BetweenExpiryAndStart, [], fn(_, _) { [] }),
      #("a death after the start", Death, AfterStart, [1], fn(_, new) {
        [#(new, "PlayerDied by 1")]
      }),
      #("a stealth before the expiry", Stealth, BeforeExpiry, [], fn(old, _) {
        [#(old, "Withdrew by 1")]
      }),
      #("a stealth in the gap", Stealth, BetweenExpiryAndStart, [], fn(_, _) {
        []
      }),
      #("a stealth after the start", Stealth, AfterStart, [1], fn(_, new) {
        [#(new, "Withdrew by 1")]
      }),
      #("a wake before the expiry", Wake, BeforeExpiry, [1], fn(old, _) {
        [#(old, "Approached by 1")]
      }),
      #("a wake in the gap", Wake, BetweenExpiryAndStart, [1], fn(_, _) { [] }),
      #("a wake after the start", Wake, AfterStart, [], fn(_, new) {
        [#(new, "Approached by 1")]
      }),
    ],
    fn(row) {
      let #(ring, told, old, new) = ring_and_told(change: row.1, when: row.2)
      assert ring == row.3 as { row.0 <> ": the ring of the next life's start" }
      assert told == row.4(old, new)
        as { row.0 <> ": what the creature that is told it is told" }
    },
  )
}

/// A step's starts, each with the spawn's ring it carries and the `Approached` it is sent
/// after it: the ring's connections and what the step tells the started life.
fn started_with(
  taken taken: step.ServiceStep(map_message.Outgoing),
) -> #(List(Int), List(String)) {
  let assert [#(_, start)] = spawns.starts(taken)
    as "the step starts one creature"
  #(
    spawns.ring_of(start:),
    list.filter_map(spawns.lives_told(taken), fn(told) {
      case told.0 == start.life {
        True -> Ok(told.1)
        False -> Error(Nil)
      }
    }),
  )
}

pub fn the_other_starts_of_a_creature_carry_an_empty_ring_and_send_one_approached_each_test() -> Nil {
  use <- owned_test.run(5000)
  // The first start by a join: the joining player is not ready, so no ring holds it.
  let state = spawns.started_with_spawns(spawns: [dagun()])
  let #(_, first_join) =
    spawns.join(state:, at_ms: 6000, connection: 1, x: 95.0)
  assert started_with(taken: first_join) == #([], [])
    as "a first start by a join: an empty ring, and the player not ready"

  // The first start by a move: a ready player moves into sight and into the ring.
  let #(far, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: spawns.far)
  let #(far, _) = spawns.ready(state: far, at_ms: 6010, connection: 1)
  let #(_, moved) = spawns.move(state: far, at_ms: 6100, connection: 1, x: 95.0)
  assert started_with(taken: moved) == #([], ["Approached by 1"])
    as "a first start by a move: an empty ring, then one Approached"

  // The restart after a retire: the creature of a spawn no one sees is told to retire, a
  // ready player comes into its ring while it ends.
  let standing =
    joined(state:, connection: 1, x: 95.0, at_ms: 6000, ready: True)
  let #(unit_id, life) = spawns.creature_of(state: standing, spawn: 1)
  let #(away, _) =
    spawns.move(state: standing, at_ms: 7000, connection: 1, x: spawns.far)
  let #(retiring, _) = spawns.sweep(state: away, at_ms: 80_000)
  let #(retiring, _) =
    spawns.move(state: retiring, at_ms: 80_050, connection: 1, x: 95.0)
  let #(_, retired) =
    spawns.creature_ended(state: retiring, at_ms: 80_100, watch: WatchId(life))
  assert started_with(taken: retired) == #([], ["Approached by 1"])
    as "the restart after a retire: an empty ring, then one Approached"

  // The restart after a crash's wait.
  let #(crashed, _) =
    spawns.creature_ended(state: standing, at_ms: 7000, watch: WatchId(life))
  let #(_, restarted) =
    spawns.feed(
      state: crashed,
      at_ms: 7000 + map_support.respawn_ms,
      event: step.OwnEvent(step.ServiceTimerFired(timer: step.TimerId(1))),
    )
  assert started_with(taken: restarted) == #([], ["Approached by 1"])
    as "the restart after a crash's wait: an empty ring, then one Approached"

  // The restart after a release.
  let #(released, _) = spawns.released(state: standing, at_ms: 7000, unit_id:)
  let #(released, _) =
    spawns.creature_ended(state: released, at_ms: 7100, watch: WatchId(life))
  let #(_, restarted) =
    spawns.feed(
      state: released,
      at_ms: 7100 + release_ms,
      event: step.OwnEvent(step.ServiceTimerFired(timer: step.TimerId(1))),
    )
  assert started_with(taken: restarted) == #([], ["Approached by 1"])
    as "the restart after a release: an empty ring, then one Approached"

  // A summon at the place of a ready player.
  let #(state, _) = spawns.started(at: [])
  let state = joined(state:, connection: 1, x: 100.0, at_ms: 6000, ready: True)
  let #(_, summoned) =
    spawns.summon(
      state:,
      at_ms: 6100,
      caller: 50,
      connection: 1,
      creature_id: 73_465,
    )
  assert started_with(taken: summoned) == #([], ["Approached by 1"])
    as "a summon: an empty ring, then one Approached"
}

/// A health news of the unit, which the old life's tells carry.
fn health_news(unit_id unit_id: Int) -> unit_news.PeerNews {
  unit_news.PeerNews(unit_id:, news: unit_news.Health(health: 52, dead: False))
}

/// The tells the creature of `unit_id` and `life` sends its map for the player of
/// connection 1: its snapshot of `generation`, a broadcast and a relay.
fn tells_of(
  unit_id unit_id: Int,
  life life: Int,
  generation generation: Generation,
) -> List(#(String, map_message.Message)) {
  [
    #(
      "a snapshot",
      map_message.Snapshot(
        unit_id:,
        life:,
        by: map_support.address(number: 1),
        generation:,
        burst: [
          health_news(unit_id:),
        ],
      ),
    ),
    #(
      "a broadcast",
      map_message.Broadcast(unit_id:, life:, news: health_news(unit_id:)),
    ),
    #(
      "a relay",
      map_message.Relay(
        unit_id:,
        life:,
        to: map_support.address(number: 1),
        payload: map_message.Fight(told: strike_tell.Released(unit_id:)),
      ),
    ),
  ]
}

pub fn a_snapshot_a_broadcast_and_a_relay_of_the_life_that_expired_are_dropped_in_each_state_the_spawn_goes_through_test() -> Nil {
  use <- owned_test.run(5000)
  let live = seen_by_two()
  let #(unit_id, life) = spawns.creature_of(state: live, spawn: 1)
  let old_generation =
    spawns.generation_of(state: live, spawn: 1, connection: 1)
  let old = tells_of(unit_id:, life:, generation: old_generation)
  let told = fn(state, tells: List(#(String, map_message.Message)), at_ms) {
    list.fold(tells, #(state, []), fn(held, tell) {
      let #(state, relays) = held
      let #(state, taken) =
        spawns.feed(
          state:,
          at_ms:,
          event: step.OwnEvent(step.Told(message: tell.1)),
        )
      #(state, list.append(relays, [#(tell.0, spawns.relays_sent(taken))]))
    })
  }
  // Live, before the expiry: the snapshot of the generation the relation awaits is taken,
  // and the news after it, which the relation relays, is too.
  let #(_, relays) = told(live, old, 6500)
  assert relays == [#("a snapshot", 1), #("a broadcast", 1), #("a relay", 1)]
    as "the creature's tells while its spawn is live are relayed"

  // Respawning: the spawn holds no relation, and `running` admits a relay of the life that
  // is ending (`admitted`). No sender produces these tells for a respawning spawn: the
  // creature's earlier sends come before its `Expired` in its one queue to the map, and it
  // sends nothing after it. The rows guard `running` and the relations' absence.
  let #(respawning, _, _) = respawning()
  let #(_, relays) = told(respawning, old, 7500)
  assert relays == [#("a snapshot", 0), #("a broadcast", 0), #("a relay", 1)]
    as "a respawning spawn drops the old life's snapshot and broadcast: it holds no relation; its relay is admitted until the creature ends"

  // The next life, live under a new generation of the same viewer.
  let #(next_life, ended) =
    spawns.creature_ended(state: respawning, at_ms: 7100, watch: WatchId(life))
  let assert [#(_, next)] = spawns.starts(ended)
  let assert Some(awaiting) =
    spawns.relation_of(state: next_life, spawn: 1, connection: 1)
  assert awaiting.generation != old_generation
    && awaiting.state == map.AwaitingSnapshot
  let #(after, relays) = told(next_life, old, 7500)
  assert relays == [#("a snapshot", 0), #("a broadcast", 0), #("a relay", 0)]
    as "the next life's spawn drops the old life's tells: an unknown life, and a generation that is not the relation's"
  assert spawns.relation_of(state: after, spawn: 1, connection: 1)
    == Some(awaiting)
    as "the viewer's relation stays awaiting the next life's snapshot"
  assert next.life != life

  // Dormant: no player sees the spawn when the creature ends.
  let #(away, _) =
    spawns.move(state: respawning, at_ms: 7010, connection: 1, x: spawns.far)
  let #(away, _) =
    spawns.move(state: away, at_ms: 7020, connection: 2, x: spawns.far)
  let #(dormant, _) =
    spawns.creature_ended(state: away, at_ms: 7100, watch: WatchId(life))
  let #(_, relays) = told(dormant, old, 7500)
  assert relays == [#("a snapshot", 0), #("a broadcast", 0), #("a relay", 0)]
    as "a dormant spawn drops them"
}

pub fn a_respawn_that_does_not_start_leaves_the_spawn_failed_for_the_run_and_tells_no_player_anything_test() -> Nil {
  use <- owned_test.run(5000)
  // Two Dagun spawns: the second is 1,900 units from the first, out of sight of a player
  // at the first.
  let state =
    spawns.started_with_spawns(spawns: [
      dagun(),
      spawn_support.dagun(number: 2, x: 2000.0),
    ])
  let state = joined(state:, connection: 1, x: 95.0, at_ms: 6000, ready: True)
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let #(state, _) = spawns.expired(state:, at_ms: 7000, unit_id:, life:)
  assert spawn_state(state:) == Ok(map.Respawning(unit_id:, life:))
    as "the creature expired"
  let #(state, ended) =
    spawns.creature_ended(state:, at_ms: 7100, watch: WatchId(life))
  let assert [#(next_watch, _)] = spawns.starts(ended)
  let #(state, taken) =
    spawns.creature_not_started(
      state:,
      at_ms: 7101,
      watch: next_watch,
      reason: "the creature supervisor is not running",
    )
  assert spawn_state(state:) == Ok(map.Failed)
    as "the spawn stays empty for the run"
  assert spawns.relation_of(state:, spawn: 1, connection: 1) == None
    as "its relations are gone"
  let assert [line] = support.logs(taken)
    as "the map says that the creature did not start, once"
  assert line.level == LogError
    && string.contains(line.text, "the creature supervisor is not running")
    as "an error line that names the reason"
  assert spawns.player_sends(taken) == [] && spawns.creature_sends(taken) == []
    as "no Gone and no Unseen: the viewers saw the creature removed and see no new unit"
  let #(_, moved) = spawns.move(state:, at_ms: 8000, connection: 1, x: 1500.0)
  assert list.length(spawns.starts(moved)) == 1 as "the other spawns start"
}
