//// What a map tells the creatures and the players about their relations, run as the pure
//// rule it is: inputs in, new state and effects out. Expected values come from these
//// places.
//// - The relation protocol of the map (the doc comment of `genesis_prime/world_map/map`): a
////   pair of a player and a creature that comes into sight is given a generation the map
////   never gave before and awaits the creature's snapshot of it; the creature's news is
////   relayed only to a pair whose snapshot was relayed, in connection order; a pair that
////   leaves sight ends under the generation it began with.
//// - The relay table (`genesis_prime/world_map/relay`): a relay is delivered to a player in
////   the stay it names, whatever the player sees, and only from a creature that runs under
////   the life it names.
//// - Sight (`genesis_prime/world_map/sight`): 1024 units, 3D, inclusive.

import connection_rule_support as support
import genesis_prime/game/experience.{Credit}
import genesis_prime/game/strike_tell.{
  Answered, Attacks, Key, Refused, Released, Threatened,
}
import genesis_prime/game/unit_news.{Health, PeerNews}
import genesis_prime/step.{
  type ServiceStep, ConnectionId, Creature, OwnEvent, ServiceTimerFired, TimerId,
  Told, WatchId,
}
import genesis_prime/table/id.{Creature2Id, Faction2Id, PrerequisiteId}
import genesis_prime/world_map/creature
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/relay
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/stay.{type Stay}
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set
import map_spawn_support as spawns
import map_support
import owned_test
import spawn_support
import world_watch_support

/// What a step told a creature about a relation: the creature's unit, the connection's
/// number and the generation. `Started` is a first viewer named in the creature's start.
type Told {
  Started(unit_id: Int, by: Int, generation: Generation)
  Seen(unit_id: Int, by: Int, generation: Generation)
  Unseen(unit_id: Int, by: Int, generation: Generation)
}

/// What the step tells creatures of their relations, in order: the first viewers of each
/// creature it starts, then each `Seen` and `Unseen` it sends.
fn told(taken: ServiceStep(map.Outgoing)) -> List(Told) {
  let started =
    list.flat_map(spawns.starts(taken), fn(start) {
      list.map({ start.1 }.viewers, fn(viewer) {
        let #(ConnectionId(by), _, generation) = viewer
        Started(unit_id: { start.1 }.unit_id, by:, generation:)
      })
    })
  let sent =
    list.filter_map(spawns.sends(taken), fn(sent) {
      case sent {
        #(
          Creature(unit_id:, ..),
          map.Seen(by: ConnectionId(by), generation:, ..),
        ) -> Ok(Seen(unit_id:, by:, generation:))
        #(Creature(unit_id:, ..), map.Unseen(by: ConnectionId(by), generation:)) ->
          Ok(Unseen(unit_id:, by:, generation:))
        _ -> Error(Nil)
      }
    })
  list.append(started, sent)
}

/// The relation the map holds between the creature of a spawn and a connection.
fn relation_of(
  state state: State,
  spawn spawn: Int,
  connection connection: Int,
) -> Option(map.Relation) {
  case map.spawn_state(state:, spawn: SpawnId(spawn)) {
    Ok(map.Live(relations:, ..)) ->
      dict.get(relations, ConnectionId(connection)) |> option.from_result
    Ok(_) | Error(Nil) -> None
  }
}

/// The generation of the relation the map holds.
fn generation_of(
  state state: State,
  spawn spawn: Int,
  connection connection: Int,
) -> Generation {
  let assert Some(map.Relation(generation:, ..)) =
    relation_of(state:, spawn:, connection:)
    as "the map holds the relation"
  generation
}

/// The unit id and life of the creature of the spawn, in any state that runs one.
fn creature_of(state state: State, spawn spawn: Int) -> #(Int, Int) {
  case map.spawn_state(state:, spawn: SpawnId(spawn)) {
    Ok(map.Live(unit_id:, life:, ..))
    | Ok(map.Retiring(unit_id:, life:))
    | Ok(map.Releasing(unit_id:, life:, ..)) -> #(unit_id, life)
    Ok(map.WaitingForRestart) | Ok(map.Failed) | Error(Nil) ->
      panic as "the spawn holds no creature"
  }
}

/// A creature's tell, as its shell gives it to the map.
fn told_by_a_creature(
  state state: State,
  at_ms at_ms: Int,
  message message: map.Message,
) -> #(State, ServiceStep(map.Outgoing)) {
  spawns.feed(state:, at_ms:, event: OwnEvent(Told(message:)))
}

/// What the step relays, each as the connection's number, the stay and the payload.
fn relayed(
  taken: ServiceStep(map.Outgoing),
) -> List(#(Int, Stay, relay.Payload)) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      map.Relayed(stay:, payload:) -> Ok(#(sent.0, stay, payload))
      _ -> Error(Nil)
    }
  })
}

/// A Battle Beast whose visibility prerequisite is the Start Arrow's (Creature2
/// prerequisiteIdVisibility 41803), which a player's hidden set can hold.
fn hideable_beast(number number: Int, x x: Float) -> Spawn {
  Spawn(
    ..spawn_support.battle_beast(number:, x:),
    visibility: Some(PrerequisiteId(41_803)),
  )
}

/// The news of a creature's health, which the tests relay.
fn health_news(unit_id unit_id: Int, health health: Int) -> unit_news.PeerNews {
  PeerNews(unit_id:, news: Health(health:, dead: False))
}

/// A strike of a caster on the creature, whose `Tell` an `Attacks` carries.
fn a_strike(unit_id unit_id: Int) -> strike_tell.Tell {
  let assert creature.Strike(tell:) =
    world_watch_support.strike_message(
      unit_id:,
      damage_type: 3,
      damage: 5,
      cast_id: 1,
      occasion: strike_tell.AtGo(phase: 0),
    )
    as "the strike message holds a strike"
  tell
}

pub fn a_second_join_unsees_then_sees_each_kept_creature_under_a_new_generation_test() -> Nil {
  use <- owned_test.run(5000)
  // Four spawns, and a player 1 that stands where it sees them all: a second player 2
  // keeps 1, 2 and 4 live, 3 retires while no one sees it, and the second join hides 4.
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 200.0),
      spawn_support.battle_beast(number: 2, x: 300.0),
      spawn_support.battle_beast(number: 3, x: 1500.0),
      hideable_beast(number: 4, x: 800.0),
    ])
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 1200.0)
  let #(state, _) = spawns.move(state:, at_ms: 7000, connection: 1, x: 3000.0)
  let #(state, _) = spawns.join(state:, at_ms: 8000, connection: 2, x: 0.0)
  let #(state, swept) = spawns.sweep(state:, at_ms: 70_000)
  let #(unit_3, _) = creature_of(state:, spawn: 3)
  assert spawns.creature_sends(swept) == [#(unit_3, "Retire")]
    as "only the spawn that no one sees retires"
  let #(state, _) = spawns.move(state:, at_ms: 71_000, connection: 1, x: 1200.0)
  let #(first, second, fourth) = #(
    generation_of(state:, spawn: 1, connection: 1),
    generation_of(state:, spawn: 2, connection: 1),
    generation_of(state:, spawn: 4, connection: 1),
  )
  let #(state, taken) =
    spawns.join_hiding(
      state:,
      at_ms: 72_000,
      connection: 1,
      x: 1200.0,
      alive: True,
      hidden: set.from_list([PrerequisiteId(41_803)]),
    )
  let #(unit_1, _) = creature_of(state:, spawn: 1)
  let #(unit_2, _) = creature_of(state:, spawn: 2)
  let #(unit_4, _) = creature_of(state:, spawn: 4)
  let #(now_1, now_2) = #(
    generation_of(state:, spawn: 1, connection: 1),
    generation_of(state:, spawn: 2, connection: 1),
  )
  assert told(taken)
    == [
      Unseen(unit_id: unit_1, by: 1, generation: first),
      Seen(unit_id: unit_1, by: 1, generation: now_1),
      Unseen(unit_id: unit_2, by: 1, generation: second),
      Seen(unit_id: unit_2, by: 1, generation: now_2),
      Unseen(unit_id: unit_4, by: 1, generation: fourth),
    ]
    as "each kept live creature in spawn order: Unseen of the sight that ends, then Seen of a new one; the newly hidden spawn Unseen only; the retiring spawn told nothing"
  assert generation.compare(now_1, first) == order.Gt
    && generation.compare(now_2, second) == order.Gt
    && now_1 != now_2
    as "each new sight has a generation the map never gave before"
  assert relation_of(state:, spawn: 1, connection: 1)
    == Some(map.Relation(generation: now_1, state: map.AwaitingSnapshot))
    as "the new sight awaits the creature's snapshot"
}

pub fn a_creature_relay_is_delivered_to_a_current_stay_and_dropped_to_an_old_one_whatever_the_players_sight_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
    ])
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(state, _) =
    spawns.join(state:, at_ms: 6100, connection: 2, x: spawns.far)
  let #(unit_id, life) = creature_of(state:, spawn: 1)
  let payloads = [
    #(
      "Struck",
      relay.Struck(answered: Answered(
        key: Key(cast_id: 1, occasion: strike_tell.AtGo(phase: 0), unit_id:),
        outcome: Refused(why: strike_tell.Dead),
      )),
    ),
    #(
      "KillCredit",
      relay.KillCredit(credit: Credit(
        unit_id:,
        creature_id: Creature2Id(73_464),
        faction_id: Faction2Id(1),
        level: 1,
      )),
    ),
    #("Attacks", relay.Fight(told: Attacks(tell: a_strike(unit_id:)))),
    #("Threatened", relay.Fight(told: Threatened(unit_id:, life:))),
    #("Released", relay.Fight(told: Released(unit_id:))),
  ]
  // The destination: the connection and the stay the relay names, and whether it is delivered.
  let destinations = [
    #("a current stay, the player sees the creature", 1, 1, True),
    #("a current stay, the player does not see the creature", 2, 1, True),
    #("an earlier stay", 1, 0, False),
    #("a player not in the map", 99, 1, False),
  ]
  list.each(payloads, fn(row) {
    let #(name, payload) = row
    list.each(destinations, fn(destination) {
      let #(situation, connection, stay_count, delivered) = destination
      let #(_, taken) =
        told_by_a_creature(
          state:,
          at_ms: 7000,
          message: map.Relay(
            unit_id:,
            life:,
            to: ConnectionId(connection),
            stay: map_support.stay(count: stay_count),
            payload:,
          ),
        )
      let expected = case delivered {
        True -> [#(connection, map_support.stay(count: stay_count), payload)]
        False -> []
      }
      assert relayed(taken) == expected
        as {
          name
          <> " to "
          <> situation
          <> case delivered {
            True -> ": delivered, whatever the player sees"
            False -> ": dropped"
          }
        }
    })
  })
}

pub fn a_relay_from_a_live_retiring_or_releasing_creature_is_admitted_and_one_from_an_ended_creature_or_an_earlier_life_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let beast = spawn_support.battle_beast(number: 1, x: 0.0)
  let live = fn() {
    let #(state, _) =
      spawns.join(
        state: spawns.started_with_spawns(spawns: [beast]),
        at_ms: 6000,
        connection: 1,
        x: 0.0,
      )
    state
  }
  // Each state a spawn can be in, with a player 1 in the map in its first stay.
  let retiring = fn() {
    let #(state, _) =
      spawns.move(state: live(), at_ms: 7000, connection: 1, x: spawns.far)
    let #(state, _) = spawns.sweep(state:, at_ms: 70_000)
    state
  }
  let releasing = fn() {
    let state = live()
    let #(unit_id, _) = creature_of(state:, spawn: 1)
    spawns.released(state:, at_ms: 7000, unit_id:).0
  }
  let ended = fn() {
    let state = live()
    let #(_, life) = creature_of(state:, spawn: 1)
    spawns.creature_ended(state:, at_ms: 7000, watch: WatchId(life)).0
  }
  let failed = fn() {
    let state = live()
    let #(_, life) = creature_of(state:, spawn: 1)
    spawns.creature_not_started(
      state:,
      at_ms: 7000,
      watch: WatchId(life),
      reason: "refused",
    ).0
  }
  let none = fn() {
    spawns.join(
      state: spawns.started_with_spawns(spawns: [beast]),
      at_ms: 6000,
      connection: 1,
      x: spawns.far,
    ).0
  }
  let rows = [
    #("live", live(), True),
    #("retiring", retiring(), True),
    #("releasing", releasing(), True),
    #("waiting for its restart", ended(), False),
    #("failed", failed(), False),
    #("no spawn state", none(), False),
  ]
  list.each(rows, fn(row) {
    let #(spawn_state, state, admitted) = row
    // The creature that ran at the spawn: the live one's unit and life, a made-up pair for
    // a spawn that held none.
    let #(unit_id, life) = case spawn_state {
      "no spawn state" -> #(1, 1)
      _ -> creature_of(state: live(), spawn: 1)
    }
    list.each(
      [
        #("the same life", life, admitted),
        #("an earlier life", life - 1, False),
      ],
      fn(case_) {
        let #(which, relay_life, delivered) = case_
        let #(_, taken) =
          told_by_a_creature(
            state:,
            at_ms: 80_000,
            message: map.Relay(
              unit_id:,
              life: relay_life,
              to: ConnectionId(1),
              stay: map_support.stay(count: 1),
              payload: relay.Fight(told: Released(unit_id:)),
            ),
          )
        assert result.is_ok(map.admitted(
            state:,
            unit_id:,
            life: relay_life,
            to: ConnectionId(1),
            stay: map_support.stay(count: 1),
            payload: relay.Fight(told: Released(unit_id:)),
          ))
          == delivered
          as { "the function the step admits a relay by agrees: " <> which }
        assert list.length(relayed(taken))
          == case delivered {
            True -> 1
            False -> 0
          }
          as {
            "a relay of "
            <> which
            <> " from a creature whose spawn is "
            <> spawn_state
            <> case delivered {
              True -> " is admitted"
              False -> " is dropped"
            }
          }
      },
    )
  })
}

pub fn a_snapshot_in_the_maps_mailbox_when_its_creature_ends_is_relayed_and_gone_follows_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
    ])
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(state, _) =
    spawns.join(state:, at_ms: 6100, connection: 2, x: spawns.far)
  let #(unit_id, life) = creature_of(state:, spawn: 1)
  let generation = generation_of(state:, spawn: 1, connection: 1)
  let #(state, snapshot) =
    told_by_a_creature(
      state:,
      at_ms: 7000,
      message: map.Snapshot(
        unit_id:,
        life:,
        by: ConnectionId(1),
        generation:,
        burst: [
          health_news(unit_id:, health: 52),
          health_news(unit_id:, health: 40),
        ],
      ),
    )
  assert relayed(snapshot)
    == [
      #(
        1,
        map_support.stay(count: 1),
        relay.News(health_news(unit_id:, health: 52)),
      ),
      #(
        1,
        map_support.stay(count: 1),
        relay.News(health_news(unit_id:, health: 40)),
      ),
    ]
    as "the burst in the map's mailbox is relayed, in the order the creature built it"
  let #(state, ended) =
    spawns.creature_ended(state:, at_ms: 7100, watch: WatchId(life))
  assert spawns.player_sends(ended)
    == [
      #(1, "Gone " <> int.to_string(unit_id)),
      #(2, "Gone " <> int.to_string(unit_id)),
    ]
    as "then the end of the creature is Gone to every player, once"
  assert map.spawn_state(state:, spawn: SpawnId(1)) == Ok(map.WaitingForRestart)
    as "and the relations went with the live spawn"
  assert relation_of(state:, spawn: 1, connection: 1) == None
}

pub fn the_map_numbers_each_creature_relation_through_join_move_leave_crash_re_entry_and_hide_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [hideable_beast(number: 1, x: 0.0)])
  // 1. the first viewer: its generation is in the creature's start.
  let #(state, joined) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(unit_id, life) = creature_of(state:, spawn: 1)
  let a_first = generation_of(state:, spawn: 1, connection: 1)
  assert told(joined) == [Started(unit_id:, by: 1, generation: a_first)]
    as "the first viewer's start carries the generation the map holds for it"
  // 2. a later joiner is told to the creature.
  let #(state, later) = spawns.join(state:, at_ms: 6100, connection: 2, x: 0.0)
  let b_first = generation_of(state:, spawn: 1, connection: 2)
  assert told(later) == [Seen(unit_id:, by: 2, generation: b_first)]
  // 3. a move out of sight, and 4. back.
  let #(state, out) =
    spawns.move(state:, at_ms: 6200, connection: 2, x: spawns.far)
  assert told(out) == [Unseen(unit_id:, by: 2, generation: b_first)]
    as "the pair ends under the generation it began with"
  let #(state, back) = spawns.move(state:, at_ms: 6300, connection: 2, x: 0.0)
  let b_second = generation_of(state:, spawn: 1, connection: 2)
  assert told(back) == [Seen(unit_id:, by: 2, generation: b_second)]
  // 5. a leave, and 6. a join again.
  let #(state, left) = spawns.leave(state:, at_ms: 6400, connection: 1)
  assert told(left) == [Unseen(unit_id:, by: 1, generation: a_first)]
  let #(state, again) = spawns.join(state:, at_ms: 6500, connection: 1, x: 0.0)
  let a_second = generation_of(state:, spawn: 1, connection: 1)
  assert told(again) == [Seen(unit_id:, by: 1, generation: a_second)]
  // 7. the creature's prerequisite enters the player's hidden set, and 8. leaves it.
  let #(state, hidden) =
    spawns.visibility_changed(
      state:,
      at_ms: 6600,
      connection: 2,
      hidden: set.from_list([PrerequisiteId(41_803)]),
    )
  assert told(hidden) == [Unseen(unit_id:, by: 2, generation: b_second)]
  let #(state, shown) =
    spawns.visibility_changed(
      state:,
      at_ms: 6700,
      connection: 2,
      hidden: set.new(),
    )
  let b_third = generation_of(state:, spawn: 1, connection: 2)
  assert told(shown) == [Seen(unit_id:, by: 2, generation: b_third)]
  // Every generation the map gave is one it never gave before.
  let all = [a_first, b_first, b_second, a_second, b_third]
  assert list.length(list.unique(all)) == list.length(all)
    as "a pair that returns gets a generation never used before"
  // 9. the creature ends: Gone to every player, and no Unseen to the dead creature.
  let #(state, crashed) =
    spawns.creature_ended(state:, at_ms: 7000, watch: WatchId(life))
  assert told(crashed) == []
    as "a creature that ended is told nothing of its viewers"
  assert spawns.player_sends(crashed)
    == [
      #(1, "Gone " <> int.to_string(unit_id)),
      #(2, "Gone " <> int.to_string(unit_id)),
    ]
    as "a crash drops the relations with a Gone to each player, once"
  // 10. the new life's first viewers hold generations of their own.
  let #(_, restarted) =
    spawns.feed(
      state:,
      at_ms: 67_000,
      event: OwnEvent(ServiceTimerFired(timer: TimerId(1))),
    )
  let assert [
    Started(by: 1, generation: a_third, ..),
    Started(by: 2, generation: b_fourth, ..),
  ] = told(restarted)
    as "the spawn's next creature starts for the players who see it"
  assert !list.contains(all, a_third)
    && !list.contains(all, b_fourth)
    && a_third != b_fourth
    as "with fresh generations"
}

pub fn a_broadcast_is_relayed_to_each_relaying_viewer_in_connection_order_and_to_no_awaiting_or_departed_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  // Four players join in the order 3, 1, 2, 4, each in a stay of its own. Players 3, 1 and 4
  // have their snapshots taken, 2 does not, and 4 leaves.
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
    ])
  let #(state, _) =
    spawns.join_in_stay(
      state:,
      at_ms: 6000,
      connection: 3,
      stay_count: 3,
      x: 0.0,
      alive: True,
      hidden: set.new(),
    )
  let #(state, _) =
    spawns.join_in_stay(
      state:,
      at_ms: 6100,
      connection: 1,
      stay_count: 1,
      x: 0.0,
      alive: True,
      hidden: set.new(),
    )
  let #(state, _) =
    spawns.join_in_stay(
      state:,
      at_ms: 6200,
      connection: 2,
      stay_count: 2,
      x: 0.0,
      alive: True,
      hidden: set.new(),
    )
  let #(state, _) =
    spawns.join_in_stay(
      state:,
      at_ms: 6300,
      connection: 4,
      stay_count: 4,
      x: 0.0,
      alive: True,
      hidden: set.new(),
    )
  let #(unit_id, life) = creature_of(state:, spawn: 1)
  let state =
    list.fold([3, 1, 4], state, fn(state, connection) {
      told_by_a_creature(
        state:,
        at_ms: 6400,
        message: map.Snapshot(
          unit_id:,
          life:,
          by: ConnectionId(connection),
          generation: generation_of(state:, spawn: 1, connection:),
          burst: [],
        ),
      ).0
    })
  let #(state, _) = spawns.leave(state:, at_ms: 6500, connection: 4)
  let news = health_news(unit_id:, health: 40)
  let #(_, taken) =
    told_by_a_creature(
      state:,
      at_ms: 6600,
      message: map.Broadcast(unit_id:, life:, news:),
    )
  assert relayed(taken)
    == [
      #(1, map_support.stay(count: 1), relay.News(news)),
      #(3, map_support.stay(count: 3), relay.News(news)),
    ]
    as "relayed to the viewers that relay, each for its own stay, in connection order; the viewer that awaits its snapshot and the one that left are sent none"
}
