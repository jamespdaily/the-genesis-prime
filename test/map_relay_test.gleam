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
//// - Sight (`genesis_prime/shared/sight`): 1024 units, 3D, inclusive.

import connection_rule_support as support
import genesis_prime/game/experience.{Credit}
import genesis_prime/game/strike_tell.{
  Answered, Attacks, Key, Refused, Released, Threatened,
}
import genesis_prime/game/unit_news.{Health, PeerNews}
import genesis_prime/step.{
  type ServiceStep, Connection, ConnectionId, Creature, LogError, OwnEvent,
  ServiceTimerFired, TimerId, Told, WatchId,
}
import genesis_prime/table/id.{Creature2Id, Faction2Id, PrerequisiteId}
import genesis_prime/world_map/creature
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/relay
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/stay.{type Stay}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/set
import gleam/string
import inbound_support
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
) -> List(#(Int, Stay, relay.Delivered)) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      map.Relayed(stay:, delivered:) -> Ok(#(sent.0, stay, delivered))
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
  let #(unit_3, _) = spawns.creature_of(state:, spawn: 3)
  assert spawns.creature_sends(swept) == [#(unit_3, "Retire")]
    as "only the spawn that no one sees retires"
  let #(state, _) = spawns.move(state:, at_ms: 71_000, connection: 1, x: 1200.0)
  let #(first, second, fourth) = #(
    spawns.generation_of(state:, spawn: 1, connection: 1),
    spawns.generation_of(state:, spawn: 2, connection: 1),
    spawns.generation_of(state:, spawn: 4, connection: 1),
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
  let #(unit_1, _) = spawns.creature_of(state:, spawn: 1)
  let #(unit_2, _) = spawns.creature_of(state:, spawn: 2)
  let #(unit_4, _) = spawns.creature_of(state:, spawn: 4)
  let #(now_1, now_2) = #(
    spawns.generation_of(state:, spawn: 1, connection: 1),
    spawns.generation_of(state:, spawn: 2, connection: 1),
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
  assert spawns.relation_of(state:, spawn: 1, connection: 1)
    == Some(map.Relation(
      generation: now_1,
      stay: map_support.stay(count: 1),
      state: map.AwaitingSnapshot,
    ))
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
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
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
        True -> [
          #(
            connection,
            map_support.stay(count: stay_count),
            relay.Tell(payload:),
          ),
        ]
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

/// A spawn of a map in one of the states a creature's spawn can be in, with the player 1 in
/// the map in its first stay, and whether a creature that ran at the spawn still runs.
type SpawnScene {
  SpawnScene(name: String, state: State, running: Bool)
}

/// The Battle Beast's spawn in each state: live, retiring (no one sees it for the idle stop),
/// releasing, respawning (its creature expired), waiting for its restart (its creature
/// ended), failed (its restart was refused) and with no spawn state (nothing started it).
fn spawn_scenes() -> List(SpawnScene) {
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
  let retiring = fn() {
    let #(state, _) =
      spawns.move(state: live(), at_ms: 7000, connection: 1, x: spawns.far)
    let #(state, _) = spawns.sweep(state:, at_ms: 70_000)
    state
  }
  let releasing = fn() {
    let state = live()
    let #(unit_id, _) = spawns.creature_of(state:, spawn: 1)
    spawns.released(state:, at_ms: 7000, unit_id:).0
  }
  let ended = fn() {
    let state = live()
    let #(_, life) = spawns.creature_of(state:, spawn: 1)
    spawns.creature_ended(state:, at_ms: 7000, watch: WatchId(life)).0
  }
  let respawning = fn() {
    let state = live()
    let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
    let #(state, _) = spawns.expired(state:, at_ms: 7000, unit_id:, life:)
    assert map.spawn_state(state:, spawn: SpawnId(1))
      == Ok(map.Respawning(unit_id:, life:))
      as "the creature expired: its spawn is respawning"
    state
  }
  let failed = fn() {
    let state = live()
    let #(_, life) = spawns.creature_of(state:, spawn: 1)
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
  [
    SpawnScene(name: "live", state: live(), running: True),
    SpawnScene(name: "retiring", state: retiring(), running: True),
    SpawnScene(name: "releasing", state: releasing(), running: True),
    SpawnScene(name: "respawning", state: respawning(), running: True),
    SpawnScene(name: "waiting for its restart", state: ended(), running: False),
    SpawnScene(name: "failed", state: failed(), running: False),
    SpawnScene(name: "no spawn state", state: none(), running: False),
  ]
}

/// The unit and life of the creature that ran at the spawn of a scene: the live one's, and
/// a made-up pair for a spawn that held none.
fn creature_of_scene(scene scene: SpawnScene) -> #(Int, Int) {
  case scene.name {
    "no spawn state" -> #(1, 1)
    _ -> {
      let assert [live, ..] = spawn_scenes()
        as "the first scene is the live spawn"
      spawns.creature_of(state: live.state, spawn: 1)
    }
  }
}

pub fn a_relay_from_a_live_retiring_or_releasing_creature_is_admitted_and_one_from_an_ended_creature_or_an_earlier_life_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(spawn_scenes(), fn(scene) {
    let #(unit_id, life) = creature_of_scene(scene:)
    list.each(
      [
        #("the same life", life, scene.running),
        #("an earlier life", life - 1, False),
      ],
      fn(case_) {
        let #(which, relay_life, delivered) = case_
        let #(_, taken) =
          told_by_a_creature(
            state: scene.state,
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
            state: scene.state,
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
            <> scene.name
            <> case delivered {
              True -> " is admitted"
              False -> " is dropped"
            }
          }
      },
    )
  })
}

/// What the step tells creatures a player told them, as each creature's unit and life and
/// what the map sends it: the sender, the stay and the payload.
fn told_creatures(
  taken: ServiceStep(map.Outgoing),
) -> List(#(Int, Int, Int, Stay, relay.Inbound)) {
  list.filter_map(spawns.sends(taken), fn(sent) {
    case sent {
      #(
        Creature(unit_id:, life:, ..),
        map.ToldCreature(by: ConnectionId(by), stay:, payload:),
      ) -> Ok(#(unit_id, life, by, stay, payload))
      _ -> Error(Nil)
    }
  })
}

pub fn a_players_tell_is_delivered_to_a_running_creature_unchanged_and_dropped_for_an_ended_one_or_an_earlier_life_test() -> Nil {
  use <- owned_test.run(10_000)
  list.each(spawn_scenes(), fn(scene) {
    let #(unit_id, life) = creature_of_scene(scene:)
    list.each(inbound_support.payloads(unit_id:), fn(row) {
      let #(kind, payload) = row
      // The sender is player 1, in the map in its first stay: it sees the creature in the
      // live scene and not in the retiring one, where it has moved away, so the creature
      // is sent the tell whatever the sender sees.
      let taken = fn(unit_id, life) {
        spawns.tell_creature(
          at_ms: 80_000,
          state: scene.state,
          from: 1,
          stay_count: 1,
          unit_id:,
          life:,
          payload:,
        ).1
      }
      let sent = fn(unit_id, life) { told_creatures(taken(unit_id, life)) }
      let in_stay = map_support.stay(count: 1)
      assert sent(unit_id, life)
        == case scene.running {
          True -> [#(unit_id, life, 1, in_stay, payload)]
          False -> []
        }
        as {
          kind
          <> " to a creature whose spawn is "
          <> scene.name
          <> case scene.running {
            True ->
              ": delivered once, as told, with the sender and stay the relay names"
            False -> ": dropped"
          }
        }
      assert scene.running || support.effects_of(taken(unit_id, life)) == []
        as {
          kind <> " to a creature that is not running sends and logs nothing"
        }
      assert sent(unit_id, life - 1) == []
        as { kind <> " of an earlier life of the creature is dropped" }
      assert support.effects_of(taken(unit_id, life - 1)) == []
        as {
          kind <> " of an earlier life of the creature sends and logs nothing"
        }
      assert sent(unit_id + 1, life) == []
        as {
          kind
          <> " to another unit than the one that runs under that life is dropped"
        }
      assert support.effects_of(taken(unit_id + 1, life)) == []
        as {
          kind
          <> " to another unit than the one that runs under that life sends and logs nothing"
        }
    })
  })
  let #(_, dropped) =
    spawns.tell_creature(
      at_ms: 80_000,
      state: spawns.started_with_spawns(spawns: [
        spawn_support.battle_beast(number: 1, x: 0.0),
      ]),
      from: 1,
      stay_count: 1,
      unit_id: 2,
      life: 1,
      payload: relay.Despawn(delay_ms: 0, went_at_ms: 6000),
    )
  assert support.effects_of(dropped) == []
    as "a tell dropped by the map writes no line and sends nothing"
}

/// The map after the players are in it: connection 1 in its first stay at the creature, 2
/// joined twice (its second stay is the current one), 3 joined and left, and 4 never joined.
/// The first joiner starts the creature, which the scene returns with its life.
fn senders_in_four_ways() -> #(State, Int, Int) {
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
    ])
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(state, _) = spawns.join(state:, at_ms: 6100, connection: 2, x: 0.0)
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
  let #(state, _) = spawns.join(state:, at_ms: 6300, connection: 3, x: 0.0)
  let #(state, _) = spawns.leave(state:, at_ms: 6400, connection: 3)
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  #(state, unit_id, life)
}

pub fn a_move_is_delivered_only_from_a_player_in_the_map_in_the_stay_the_relay_names_and_a_strike_or_an_answer_from_any_sender_is_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, unit_id, life) = senders_in_four_ways()
  // The sender, the stay it names, and whether the map holds that player in that stay.
  let senders = [
    #("in the map in that stay", 1, 1, True),
    #("in the map in an earlier stay (it joined again)", 2, 1, False),
    #("that left", 3, 1, False),
    #("that never joined", 4, 1, False),
  ]
  list.each(senders, fn(sender) {
    let #(situation, from, stay_count, in_the_map_in_that_stay) = sender
    list.each(inbound_support.payloads(unit_id:), fn(row) {
      let #(kind, payload) = row
      // The move and the two kinds that make a holding on the creature are checked for
      // their sender; a strike names the sender it is told from.
      let delivered = case payload {
        relay.TargetMoved(..)
        | relay.ModifierStarts(..)
        | relay.CastViewSet(..) -> in_the_map_in_that_stay
        _ -> True
      }
      let payload = case payload {
        relay.Strike(tell:) ->
          relay.Strike(tell: inbound_support.struck_by(
            tell:,
            from:,
            stay_count:,
          ))
        _ -> payload
      }
      let #(_, taken) =
        spawns.tell_creature(
          at_ms: 80_000,
          state:,
          from:,
          stay_count:,
          unit_id:,
          life:,
          payload:,
        )
      assert list.length(told_creatures(taken))
        == case delivered {
          True -> 1
          False -> 0
        }
        as {
          kind
          <> " from a player "
          <> situation
          <> case delivered {
            True -> " is delivered"
            False -> " is dropped"
          }
        }
      assert result.is_ok(map.admitted_inbound(
          state:,
          unit_id:,
          life:,
          from: ConnectionId(from),
          stay: map_support.stay(count: stay_count),
          payload:,
        ))
        == delivered
        as {
          "the function the step admits a tell by agrees for "
          <> kind
          <> " from a player "
          <> situation
        }
    })
  })
  assert map.admitted_inbound(
      state:,
      unit_id:,
      life:,
      from: ConnectionId(2),
      stay: map_support.stay(count: 1),
      payload: relay.TargetMoved(
        place: inbound_support.place(),
        seq: 1,
        hit_radius: 0.5,
      ),
    )
    == Error(map.SourceRefused)
    as "a move from a player of another stay is refused for its source, not for its creature"
  list.each(
    [
      relay.ModifierStarts(
        source: inbound_support.source(),
        modifier: inbound_support.modifier(),
      ),
      relay.CastViewSet(view: inbound_support.view()),
    ],
    fn(payload) {
      list.each([2, 3, 4], fn(from) {
        assert map.admitted_inbound(
            state:,
            unit_id:,
            life:,
            from: ConnectionId(from),
            stay: map_support.stay(count: 1),
            payload:,
          )
          == Error(map.SourceRefused)
          as {
            spawns.inbound_name(payload)
            <> " from a player of another stay, one that left or one never in the map is refused for its source"
          }
      })
    },
  )
}

pub fn a_strike_that_names_another_striker_than_the_connection_that_told_it_is_dropped_with_an_error_line_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, unit_id, life) = senders_in_four_ways()
  let tell = inbound_support.strike(unit_id:)
  let rows = [
    #(
      "from another connection",
      strike_tell.Strike(..tell, from: Connection(ConnectionId(2))),
      False,
    ),
    #(
      "whose striker's stay is not the relay's",
      inbound_support.struck_by(tell:, from: 1, stay_count: 2),
      False,
    ),
    #(
      "whose striker is a creature",
      strike_tell.Strike(
        ..tell,
        striker: strike_tell.CreatureStriker(
          unit_id: 9,
          spell4_id: id.Spell4Id(1),
        ),
      ),
      False,
    ),
    #("that matches the connection and its stay", tell, True),
  ]
  list.each(rows, fn(row) {
    let #(situation, tell, delivered) = row
    let #(_, taken) =
      spawns.tell_creature(
        at_ms: 80_000,
        state:,
        from: 1,
        stay_count: 1,
        unit_id:,
        life:,
        payload: relay.Strike(tell:),
      )
    assert list.length(told_creatures(taken))
      == case delivered {
        True -> 1
        False -> 0
      }
      as {
        "a strike "
        <> situation
        <> case delivered {
          True -> " is delivered"
          False -> " is dropped"
        }
      }
    assert list.length(support.logs_of(step: taken, level: LogError))
      == case delivered {
        True -> 0
        False -> 1
      }
      as {
        "a strike "
        <> situation
        <> case delivered {
          True -> " writes no line"
          False -> " writes one error line"
        }
      }
    assert list.all(support.logs_of(step: taken, level: LogError), fn(line) {
      string.contains(line.text, "told a creature a strike")
    })
      as {
        "the line of a strike "
        <> situation
        <> " names the tell: a strike told to a creature"
      }
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
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let generation = spawns.generation_of(state:, spawn: 1, connection: 1)
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
  assert spawns.relation_of(state:, spawn: 1, connection: 1) == None
}

pub fn the_map_numbers_each_creature_relation_through_join_move_leave_crash_re_entry_and_hide_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [hideable_beast(number: 1, x: 0.0)])
  // 1. the first viewer: its generation is in the creature's start.
  let #(state, joined) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let a_first = spawns.generation_of(state:, spawn: 1, connection: 1)
  assert told(joined) == [Started(unit_id:, by: 1, generation: a_first)]
    as "the first viewer's start carries the generation the map holds for it"
  // 2. a later joiner is told to the creature.
  let #(state, later) = spawns.join(state:, at_ms: 6100, connection: 2, x: 0.0)
  let b_first = spawns.generation_of(state:, spawn: 1, connection: 2)
  assert told(later) == [Seen(unit_id:, by: 2, generation: b_first)]
  // 3. a move out of sight, and 4. back.
  let #(state, out) =
    spawns.move(state:, at_ms: 6200, connection: 2, x: spawns.far)
  assert told(out) == [Unseen(unit_id:, by: 2, generation: b_first)]
    as "the pair ends under the generation it began with"
  let #(state, back) = spawns.move(state:, at_ms: 6300, connection: 2, x: 0.0)
  let b_second = spawns.generation_of(state:, spawn: 1, connection: 2)
  assert told(back) == [Seen(unit_id:, by: 2, generation: b_second)]
  // 5. a leave, and 6. a join again.
  let #(state, left) = spawns.leave(state:, at_ms: 6400, connection: 1)
  assert told(left) == [Unseen(unit_id:, by: 1, generation: a_first)]
  let #(state, again) = spawns.join(state:, at_ms: 6500, connection: 1, x: 0.0)
  let a_second = spawns.generation_of(state:, spawn: 1, connection: 1)
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
  let b_third = spawns.generation_of(state:, spawn: 1, connection: 2)
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
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let state =
    list.fold([3, 1, 4], state, fn(state, connection) {
      told_by_a_creature(
        state:,
        at_ms: 6400,
        message: map.Snapshot(
          unit_id:,
          life:,
          by: ConnectionId(connection),
          generation: spawns.generation_of(state:, spawn: 1, connection:),
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
  // The creature is released: the relations are kept as they were, so the viewer that
  // relays is still sent the broadcast, and the viewer that awaits its snapshot is sent it.
  let #(released, _) = spawns.released(state:, at_ms: 6700, unit_id:)
  let #(released_with_snapshot, snapshot) =
    told_by_a_creature(
      state: released,
      at_ms: 6800,
      message: map.Snapshot(
        unit_id:,
        life:,
        by: ConnectionId(2),
        generation: spawns.generation_of(
          state: released,
          spawn: 1,
          connection: 2,
        ),
        burst: [news],
      ),
    )
  assert relayed(snapshot)
    == [#(2, map_support.stay(count: 2), relay.News(news))]
    as "a releasing creature's snapshot reaches the viewer that awaits it, for the stay of its relation"
  let #(_, broadcast_released) =
    told_by_a_creature(
      state: released_with_snapshot,
      at_ms: 6900,
      message: map.Broadcast(unit_id:, life:, news:),
    )
  assert relayed(broadcast_released)
    == [
      #(1, map_support.stay(count: 1), relay.News(news)),
      #(2, map_support.stay(count: 2), relay.News(news)),
      #(3, map_support.stay(count: 3), relay.News(news)),
    ]
    as "a releasing creature's broadcast reaches each viewer that relays, as before the release"
  // Viewers 1 (relaying) and 2 (awaiting) leave and join again in new stays while the
  // creature lies released: the relations still name the stays they were made in.
  let rejoined =
    list.fold([#(1, 11), #(2, 22)], released, fn(state, again) {
      let #(connection, stay_count) = again
      let #(state, _) = spawns.leave(state:, at_ms: 7000, connection:)
      spawns.join_in_stay(
        state:,
        at_ms: 7100,
        connection:,
        stay_count:,
        x: 0.0,
        alive: True,
        hidden: set.new(),
      ).0
    })
  let #(_, stale_snapshot) =
    told_by_a_creature(
      state: rejoined,
      at_ms: 7200,
      message: map.Snapshot(
        unit_id:,
        life:,
        by: ConnectionId(2),
        generation: spawns.generation_of(
          state: released,
          spawn: 1,
          connection: 2,
        ),
        burst: [news],
      ),
    )
  assert relayed(stale_snapshot) == []
    as "a snapshot of the stay the viewer left is not relayed to the stay it joined again in"
  let #(_, broadcast_rejoined) =
    told_by_a_creature(
      state: rejoined,
      at_ms: 7300,
      message: map.Broadcast(unit_id:, life:, news:),
    )
  assert relayed(broadcast_rejoined)
    == [#(3, map_support.stay(count: 3), relay.News(news))]
    as "a broadcast is relayed to no viewer under a stay it has left, here 1 and 2, and still to the one that stayed"
}

pub fn a_snapshot_of_an_earlier_generation_relays_nothing_and_leaves_the_relation_awaiting_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
    ])
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(state, _) = spawns.join(state:, at_ms: 6100, connection: 2, x: 0.0)
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let earlier = spawns.generation_of(state:, spawn: 1, connection: 2)
  let #(state, _) =
    spawns.move(state:, at_ms: 6200, connection: 2, x: spawns.far)
  let #(state, _) = spawns.move(state:, at_ms: 6300, connection: 2, x: 0.0)
  let current = spawns.generation_of(state:, spawn: 1, connection: 2)
  assert earlier != current
    as "the pair that came back holds a generation of its own"
  let news = health_news(unit_id:, health: 40)
  let #(state, stale) =
    told_by_a_creature(
      state:,
      at_ms: 6400,
      message: map.Snapshot(
        unit_id:,
        life:,
        by: ConnectionId(2),
        generation: earlier,
        burst: [news],
      ),
    )
  assert relayed(stale) == []
    as "a snapshot of the sight that ended is dropped, whatever it carries"
  assert spawns.relation_of(state:, spawn: 1, connection: 2)
    == Some(map.Relation(
      generation: current,
      stay: map_support.stay(count: 1),
      state: map.AwaitingSnapshot,
    ))
    as "the relation still awaits the snapshot of its own generation"
  let #(_, own) =
    told_by_a_creature(
      state:,
      at_ms: 6500,
      message: map.Snapshot(
        unit_id:,
        life:,
        by: ConnectionId(2),
        generation: current,
        burst: [news],
      ),
    )
  assert relayed(own) == [#(2, map_support.stay(count: 1), relay.News(news))]
    as "the snapshot of its own generation is relayed"
}
