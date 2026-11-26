//// What a map tells the players about each other, run as the pure rule it is: inputs in,
//// new state and effects out. Expected values come from these places.
//// - The relation protocol of the map (the doc comment of `genesis_prime/world_map/map`),
////   which a player's sight with another player follows as a creature's does: a pair that
////   comes into sight is given a generation the map never gave before and its relation
////   awaits the owner's snapshot of it; the owner's news is relayed only to a pair whose
////   snapshot was relayed, in connection order; a pair that leaves sight ends under the
////   generation it began with, and the viewer is told so (`PlayerUnseen`) whether or not
////   it took the snapshot. The creature model is the same rules in `map_relay_test`.
//// - The relay table (`genesis_prime/world_map/relay`): a landing is delivered to the
////   player in the stay it names, whatever the players see, with the source check of its
////   kind.
//// - A player's move is no news: the mover tells its viewers itself and the map only
////   decides sight (`genesis_prime/game/move_stamp`).
//// - Sight (`genesis_prime/world_map/sight`): 1024 units, 3D, inclusive.

import connection_rule_support as support
import genesis_prime/game/held_changes
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_casts.{EndsAt, HeldEffect}
import genesis_prime/game/unit_news.{Health, PeerNews}
import genesis_prime/game/unit_properties.{Source}
import genesis_prime/step.{type ServiceStep, ConnectionId, WatchEnded, WatchId}
import genesis_prime/table/id.{Spell4EffectsId, Spell4Id}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map
import genesis_prime/world_map/relay
import genesis_prime/world_map/stay.{type Stay}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/set
import gleam/string
import map_player_support as players
import map_spawn_support as spawns
import owned_test

/// What a relayed delivery is, as the health the news carries.
fn healths(
  relayed relayed: List(#(Int, Stay, relay.Delivered)),
) -> List(#(Int, Int)) {
  list.filter_map(relayed, fn(delivery) {
    case delivery.2 {
      relay.News(news: PeerNews(news: Health(health:, ..), ..)) ->
        Ok(#(delivery.0, health))
      relay.News(..) | relay.Tell(..) | relay.Landed(..) | relay.Said(..) ->
        Error(Nil)
    }
  })
}

/// Connection 1 and the viewers `viewers` joined in the order given, each in sight of the
/// others, and the generation each viewer's sight of connection 1 was given.
fn owner_and_viewers(
  viewers viewers: List(Int),
) -> #(map.State, List(#(Int, Generation)), Int) {
  let #(state, taken, at_ms) =
    players.joined(
      state: players.empty(),
      connections: [1, ..viewers],
      from_ms: 6000,
    )
  let sights =
    list.filter_map(viewers, fn(viewer) {
      list.find_map(taken, fn(step) {
        case players.sight_of(taken: step, owner: 1, viewer:) {
          Some(generation) -> Ok(#(viewer, generation))
          None -> Error(Nil)
        }
      })
    })
  #(state, sights, at_ms)
}

/// The generation the map gave the viewer's sight of connection 1.
fn sight_of_viewer(
  sights sights: List(#(Int, Generation)),
  viewer viewer: Int,
) -> Generation {
  let assert Ok(#(_, generation)) =
    list.find(sights, fn(held) { held.0 == viewer })
    as "the viewer joined in sight of connection 1"
  generation
}

/// What the viewer's connection is told of a snapshot relayed: its stay and the health in
/// each item.
const owner_stay_count = 1

/// A snapshot of the sight `generation` that connection 2 has of connection 1, with two
/// items, and what is relayed.
fn snapshot_to_two(
  state state: map.State,
  at_ms at_ms: Int,
  generation generation: Generation,
) -> #(map.State, ServiceStep(map.Outgoing)) {
  players.snapshot(
    state:,
    at_ms:,
    owner: 1,
    owner_stay: players.stay(count: owner_stay_count),
    viewer: 2,
    generation:,
    burst: [
      players.health(connection: 1, health: 10),
      players.health(connection: 1, health: 20),
    ],
  )
}

pub fn a_players_snapshot_is_relayed_only_for_the_generation_and_stay_the_relation_awaits_and_news_while_awaiting_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, sights, at_ms) = owner_and_viewers(viewers: [2])
  let sight = sight_of_viewer(sights:, viewer: 2)
  let first_stay = players.stay(count: 1)
  let held =
    Some(map.Relation(
      generation: sight,
      stay: first_stay,
      state: map.AwaitingSnapshot,
    ))
  assert players.relation(state:, owner: 1, viewer: 2) == held
    as "a pair that came into sight awaits the owner's snapshot of its generation"
  // The held generation: relayed in order, each item for the viewer's stay, and relaying.
  let #(relaying, taken) = snapshot_to_two(state:, at_ms:, generation: sight)
  assert healths(relayed: players.relayed(taken:)) == [#(2, 10), #(2, 20)]
    as "the snapshot of the held generation is relayed to the viewer, in the owner's order"
  assert list.all(players.relayed(taken:), fn(delivery) {
    delivery.1 == first_stay
  })
    as "each item is relayed for the viewer's stay"
  assert players.relation(state: relaying, owner: 1, viewer: 2)
    == Some(map.Relation(
      generation: sight,
      stay: first_stay,
      state: map.Relaying,
    ))
    as "the relation relays from the snapshot on"
  // A second snapshot of the same generation changes nothing.
  let #(again, taken) =
    snapshot_to_two(state: relaying, at_ms: at_ms + 1, generation: sight)
  assert players.relayed(taken:) == []
    as "a second snapshot of one generation is dropped"
  assert players.relation(state: again, owner: 1, viewer: 2)
    == players.relation(state: relaying, owner: 1, viewer: 2)
    as "and the relation is as it was"
  // Rows from the state where the pair awaits, each one more thing that happened first.
  let #(out, _) =
    spawns.move(state:, at_ms: at_ms + 2, connection: 2, x: spawns.far)
  let #(back, taken) =
    spawns.move(state: out, at_ms: at_ms + 3, connection: 2, x: 200.0)
  let g_again = players.the_sight_of(taken:, owner: 1, viewer: 2)
  let #(after_a_return, taken) =
    snapshot_to_two(state: back, at_ms: at_ms + 4, generation: sight)
  assert players.relayed(taken:) == []
    as "a snapshot of an earlier generation (the pair left and came back) is dropped"
  assert players.relation(state: after_a_return, owner: 1, viewer: 2)
    == Some(map.Relation(
      generation: g_again,
      stay: first_stay,
      state: map.AwaitingSnapshot,
    ))
    as "the relation still awaits the snapshot of its own generation"
  let #(_, taken) =
    snapshot_to_two(
      state: after_a_return,
      at_ms: at_ms + 5,
      generation: g_again,
    )
  assert healths(relayed: players.relayed(taken:)) == [#(2, 10), #(2, 20)]
    as "control: the snapshot of the generation it awaits is relayed"
  let #(unseen, _) =
    spawns.move(state:, at_ms: at_ms + 6, connection: 2, x: spawns.far)
  let #(unseen, taken) =
    snapshot_to_two(state: unseen, at_ms: at_ms + 7, generation: sight)
  assert players.relayed(taken:) == []
    as "a snapshot after the player's unseen is dropped"
  assert players.relation(state: unseen, owner: 1, viewer: 2) == None
    as "and no relation is made by it"
  // A viewer that left and joined again is in another stay now: the old snapshot is dropped.
  // This clause is a guard, not a decision: a stay change is also a new generation for each
  // pair (`joined_again`), so the generation check alone drops this snapshot too, and a build
  // that ignores the relation's stay passes it. The guard is the second assertion, that the
  // new stay's sight is a new generation; the map's stay check (`in_current_stay`) stands
  // for a path that renews a stay and not the generation.
  let #(left, _) = spawns.leave(state:, at_ms: at_ms + 8, connection: 2)
  let #(rejoined, _) =
    spawns.join_in_stay(
      state: left,
      at_ms: at_ms + 9,
      connection: 2,
      stay_count: 2,
      x: 200.0,
      alive: True,
      hidden: set.new(),
    )
  let #(rejoined, taken) =
    snapshot_to_two(state: rejoined, at_ms: at_ms + 10, generation: sight)
  assert players.relayed(taken:) == []
    as "a snapshot of the sight the viewer had in its earlier stay is dropped"
  let assert Some(map.Relation(generation: now, stay: now_stay, ..)) =
    players.relation(state: rejoined, owner: 1, viewer: 2)
    as "the new stay's sight is held"
  assert now_stay == players.stay(count: 2)
    as "the relation names the viewer's new stay"
  assert generation.compare(now, sight) == order.Gt
    as "guard: a stay change gives the pair a new generation, so the old stay's snapshot is dropped by it alone"
  let #(_, taken) =
    snapshot_to_two(state: rejoined, at_ms: at_ms + 11, generation: now)
  assert list.all(players.relayed(taken:), fn(delivery) {
      delivery.1 == players.stay(count: 2)
    })
    && healths(relayed: players.relayed(taken:)) == [#(2, 10), #(2, 20)]
    as "control: the new stay's snapshot is relayed for the new stay"
  // A burst that does not begin with the owner's 0x262 of that generation is an error line
  // and is not relayed: the viewer releases its held moves by the generation that 0x262 names.
  let refused = fn(burst) {
    let #(refusing, taken) =
      players.snapshot_as_told(
        state:,
        at_ms: at_ms + 12,
        owner: 1,
        owner_stay: first_stay,
        viewer: 2,
        generation: sight,
        burst:,
      )
    #(
      players.relayed(taken:),
      support.logs_of(step: taken, level: step.LogError),
      players.relation(state: refusing, owner: 1, viewer: 2),
    )
  }
  let #(relayed, logs, relation) =
    refused([players.health(connection: 1, health: 5)])
  assert relayed == [] && list.length(logs) == 1 && relation == held
    as "a burst that begins with news, not the owner's 0x262, is logged, relays nothing and leaves the relation awaiting"
  let #(relayed, logs, relation) =
    refused([players.appeared(owner: 1, generation: g_again)])
  assert relayed == [] && list.length(logs) == 1 && relation == held
    as "a burst that begins with the 0x262 of another generation is refused the same way"
  // News while the relation awaits is dropped.
  let #(_, taken) =
    players.broadcast(
      state:,
      at_ms: at_ms + 13,
      owner: 1,
      owner_stay: first_stay,
      news: players.health(connection: 1, health: 99),
    )
  assert players.relayed(taken:) == []
    as "news while the relation awaits its snapshot is dropped: the snapshot is built after everything the owner sent"
}

pub fn a_players_news_is_relayed_to_each_relaying_viewer_in_connection_order_and_to_no_awaiting_or_departed_viewer_and_news_naming_another_unit_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  // Viewers 6 and 2 relay (6 joined first: the order of relaying is the connection's number,
  // not the order of joining), 3 awaits its snapshot, 4 left sight after it relayed, and 5
  // relayed in its first stay and has joined again.
  let #(state, sights, at_ms) = owner_and_viewers(viewers: [6, 2, 3, 4, 5])
  let first_stay = players.stay(count: 1)
  let snapshotted = fn(state, viewer, at_ms) {
    players.snapshot(
      state:,
      at_ms:,
      owner: 1,
      owner_stay: first_stay,
      viewer:,
      generation: sight_of_viewer(sights:, viewer:),
      burst: [players.health(connection: 1, health: 1)],
    ).0
  }
  let state =
    list.fold([6, 2, 4, 5], #(state, at_ms), fn(so_far, viewer) {
      #(snapshotted(so_far.0, viewer, so_far.1), so_far.1 + 1)
    })
  let #(state, at_ms) = #(state.0, state.1)
  let #(state, _) = spawns.move(state:, at_ms:, connection: 4, x: spawns.far)
  let #(state, _) = spawns.leave(state:, at_ms: at_ms + 1, connection: 5)
  let #(state, joined_again) =
    spawns.join_in_stay(
      state:,
      at_ms: at_ms + 2,
      connection: 5,
      stay_count: 2,
      x: 500.0,
      alive: True,
      hidden: set.new(),
    )
  assert players.sight_of(taken: joined_again, owner: 1, viewer: 5) != None
    as "the viewer that joined again sees the owner under a sight of its new stay"
  let #(_, taken) =
    players.broadcast(
      state:,
      at_ms: at_ms + 3,
      owner: 1,
      owner_stay: first_stay,
      news: players.health(connection: 1, health: 55),
    )
  assert healths(relayed: players.relayed(taken:)) == [#(2, 55), #(6, 55)]
    as "the news reaches each relaying viewer in the order of the connections' numbers, and no viewer that awaits its snapshot, left sight or is in another stay"
  // News from the owner's earlier stay is dropped.
  let #(_, taken) =
    players.broadcast(
      state:,
      at_ms: at_ms + 3,
      owner: 1,
      owner_stay: players.stay(count: 2),
      news: players.health(connection: 1, health: 56),
    )
  assert players.relayed(taken:) == []
    as "news of a stay the owner is not in is not relayed"
  // News that names another unit than the sender's is dropped and logged.
  let #(_, taken) =
    players.broadcast(
      state:,
      at_ms: at_ms + 4,
      owner: 1,
      owner_stay: first_stay,
      news: PeerNews(unit_id: 99, news: Health(health: 1, dead: False)),
    )
  assert players.relayed(taken:) == []
    as "news that names another unit than the sender's is not relayed"
  assert list.any(support.logs_of(step: taken, level: step.LogError), fn(line) {
    string.contains(line.text, "unit")
  })
    as "and the map logs an error that names the unit"
}

pub fn a_second_join_ends_each_pair_and_begins_it_again_in_both_directions_and_for_no_player_the_joiner_does_not_see_test() -> Nil {
  use <- owned_test.run(5000)
  // Players 1 and 2 see each other, and 3 stands where it sees neither. Player 1 joins a
  // second time, in its second stay.
  let state = players.empty()
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(state, second) =
    spawns.join(state:, at_ms: 6010, connection: 2, x: 300.0)
  let #(state, _) =
    spawns.join(state:, at_ms: 6020, connection: 3, x: spawns.far)
  let one_sees_two = players.the_sight_of(taken: second, owner: 2, viewer: 1)
  let two_sees_one = players.the_sight_of(taken: second, owner: 1, viewer: 2)
  let #(state, again) =
    spawns.join_in_stay(
      state:,
      at_ms: 6030,
      connection: 1,
      stay_count: 2,
      x: 0.0,
      alive: True,
      hidden: set.new(),
    )
  let new_one_sees_two = players.the_sight_of(taken: again, owner: 2, viewer: 1)
  let new_two_sees_one = players.the_sight_of(taken: again, owner: 1, viewer: 2)
  assert generation.compare(new_one_sees_two, one_sees_two) == order.Gt
    && generation.compare(new_two_sees_one, two_sees_one) == order.Gt
    && new_one_sees_two != new_two_sees_one
    as "each new sight has a generation the map never gave before"
  // Owner 2, viewer 1: the owner is told the sight ended, then the new one; the viewer is
  // told the unit is unseen, for the stay it had.
  let owner_two = players.notices_to(taken: again, connection: 2)
  assert list.filter_map(owner_two, fn(notice) {
      case notice.1 {
        map.UnseenBy(by: ConnectionId(1), generation:) ->
          Ok("UnseenBy " <> int.to_string(generation.number(generation:)))
        map.SeenBy(by: ConnectionId(1), generation:, ..) ->
          Ok("SeenBy " <> int.to_string(generation.number(generation:)))
        _ -> Error(Nil)
      }
    })
    == [
      "UnseenBy " <> int.to_string(generation.number(generation: one_sees_two)),
      "SeenBy "
        <> int.to_string(generation.number(generation: new_one_sees_two)),
    ]
    as "owner 2 is told viewer 1's sight ended, then the new one"
  let owner_one = players.notices_to(taken: again, connection: 1)
  assert list.filter_map(owner_one, fn(notice) {
      case notice.1 {
        map.UnseenBy(by: ConnectionId(2), generation:) ->
          Ok("UnseenBy " <> int.to_string(generation.number(generation:)))
        map.SeenBy(by: ConnectionId(2), generation:, ..) ->
          Ok("SeenBy " <> int.to_string(generation.number(generation:)))
        _ -> Error(Nil)
      }
    })
    == [
      "UnseenBy " <> int.to_string(generation.number(generation: two_sees_one)),
      "SeenBy "
        <> int.to_string(generation.number(generation: new_two_sees_one)),
    ]
    as "owner 1 is told viewer 2's sight ended, then the new one"
  assert list.any(owner_two, fn(notice) {
    notice.1 == map.PlayerUnseen(unit_id: 1, generation: two_sees_one)
  })
    as "viewer 2 is told unit 1 is unseen from the sight that ended"
  assert list.any(owner_one, fn(notice) {
    notice.1 == map.PlayerUnseen(unit_id: 2, generation: one_sees_two)
  })
    as "viewer 1 is told unit 2 is unseen from the sight that ended, for the stay it had"
  assert players.notices_to(taken: again, connection: 3)
    |> list.filter(fn(notice) {
      case notice.1 {
        map.SeenBy(..) | map.UnseenBy(..) | map.PlayerUnseen(..) -> True
        _ -> False
      }
    })
    == []
    as "the player the joiner does not see is told nothing"
  // Each new pair awaits the owner's snapshot of its new generation, and is relayed it.
  assert players.relation(state:, owner: 2, viewer: 1)
    == Some(map.Relation(
      generation: new_one_sees_two,
      stay: players.stay(count: 2),
      state: map.AwaitingSnapshot,
    ))
    as "the joiner's sight of 2 awaits 2's snapshot, under the joiner's new stay"
  let #(_, taken) =
    players.snapshot(
      state:,
      at_ms: 6040,
      owner: 2,
      owner_stay: players.stay(count: 1),
      viewer: 1,
      generation: new_one_sees_two,
      burst: [players.health(connection: 2, health: 7)],
    )
  assert list.all(players.relayed(taken:), fn(delivery) {
      delivery.0 == 1 && delivery.1 == players.stay(count: 2)
    })
    && healths(relayed: players.relayed(taken:)) == [#(1, 7)]
    && list.length(players.relayed(taken:)) == 2
    as "the new snapshot, the owner's 0x262 and its news, is relayed to the joiner for its new stay"
}

/// A landing of each kind, as the tests send them from connection 1, in its first stay, to
/// the unit 2 of connection 2.
fn landings() -> List(#(String, relay.Landing)) {
  let source = Source(cast_id: 5, effect_id: Spell4EffectsId(62_024))
  let starts =
    held_changes.PlayerChangeStarts(
      from: ConnectionId(1),
      from_stay: players.stay(count: 1),
      source:,
      change: held_changes.Applies(held_changes.Absorb(amount: 5, mask: 7)),
      sight: held_changes.EndsWhenUnseen,
      spell4_id: Spell4Id(1),
      effect: HeldEffect(
        effect_id: Spell4EffectsId(62_024),
        starts_ms: 1000,
        ends: EndsAt(ms: 11_000),
      ),
    )
  [
    #(
      "heal strike",
      relay.HealStrike(
        strike: strike_tell.PlayerStrike(
          key: strike_tell.Key(
            cast_id: 5,
            occasion: strike_tell.AtGo(phase: 0),
            unit_id: 2,
          ),
          from: ConnectionId(1),
          stay: players.stay(count: 1),
          outgoing: 1.0,
          heals: [],
        ),
      ),
    ),
    #("answer", players.answer(cast_id: 5, unit_id: 2)),
    #("change start", relay.ChangeStart(change: starts)),
    #(
      "change end",
      relay.ChangeEnd(change: held_changes.PlayerChangeEnds(
        from: ConnectionId(1),
        source:,
      )),
    ),
    #(
      "cast went",
      relay.CastWent(change: held_changes.PlayerCastWent(
        from: ConnectionId(1),
        cast_id: 5,
        audience: set.new(),
      )),
    ),
    #(
      "ally event",
      relay.AllyEvent(event: strike_tell.PlayerEvent(unit_id: 2, events: [])),
    ),
  ]
}

/// Whether the kind checks that the sender is in the stay the tell names for it: only a
/// change's start does (`relay.landing_kind_of`).
fn checks_the_source_stay(landing landing: relay.Landing) -> Bool {
  relay.landing_kind_of(landing:).source == relay.SenderStayIsCurrent
}

pub fn each_player_to_player_effect_is_delivered_by_its_kinds_checks_test() -> Nil {
  use <- owned_test.run(5000)
  // Player 1 is the sender and player 2 the told player, in sight of it or not, in the stay
  // the tell names or in another, or never joined.
  let told_rows = [
    #("T in the stay named, in sight", 2, 1, True, True),
    #("T in the stay named, out of sight of C", 2, 1, False, True),
    #("T in another stay than the tell names", 2, 0, True, False),
    #("T never joined", 9, 1, True, False),
  ]
  list.each(told_rows, fn(row) {
    let #(situation, told, told_stay_count, in_sight, delivered) = row
    list.each(landings(), fn(kind) {
      let #(name, landing) = kind
      let state = players.empty()
      let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
      let #(state, _) =
        spawns.join(state:, at_ms: 6010, connection: 2, x: case in_sight {
          True -> 300.0
          False -> spawns.far
        })
      let #(_, taken) =
        players.landing(
          state:,
          at_ms: 6020,
          from: 1,
          from_stay: players.stay(count: 1),
          to: told,
          to_stay: players.stay(count: told_stay_count),
          landing:,
        )
      let expected = case delivered {
        True -> [
          #(told, players.stay(count: told_stay_count), relay.Landed(landing:)),
        ]
        False -> []
      }
      assert players.relayed(taken:) == expected
        as { name <> ": " <> situation }
    })
  })
  // The change start also needs the sender to be in the stay the tell names for it: a tell
  // from the sender's other stay is dropped, and every other kind is delivered all the same.
  list.each(landings(), fn(kind) {
    let #(name, landing) = kind
    let state = players.empty()
    let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
    let #(state, _) = spawns.join(state:, at_ms: 6010, connection: 2, x: 300.0)
    let #(_, taken) =
      players.landing(
        state:,
        at_ms: 6020,
        from: 1,
        from_stay: players.stay(count: 0),
        to: 2,
        to_stay: players.stay(count: 1),
        landing:,
      )
    let expected = case checks_the_source_stay(landing:) {
      True -> []
      False -> [#(2, players.stay(count: 1), relay.Landed(landing:))]
    }
    assert players.relayed(taken:) == expected
      as { name <> ": the sender is in another stay than the tell names" }
  })
  // A player that left the map is told nothing, whatever the kind.
  list.each(landings(), fn(kind) {
    let #(name, landing) = kind
    let state = players.empty()
    let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
    let #(state, _) = spawns.join(state:, at_ms: 6010, connection: 2, x: 300.0)
    let #(state, _) = spawns.leave(state:, at_ms: 6015, connection: 2)
    let #(_, taken) =
      players.landing(
        state:,
        at_ms: 6020,
        from: 1,
        from_stay: players.stay(count: 1),
        to: 2,
        to_stay: players.stay(count: 1),
        landing:,
      )
    assert players.relayed(taken:) == []
      as { name <> ": the told player left the map" }
  })
}

pub fn the_news_a_connection_sent_before_it_ended_is_relayed_before_its_removal_test() -> Nil {
  use <- owned_test.run(5000)
  // Players 1 and 2 stand at x 100 and 200 and see each other: 2's sight of 1 and 1's
  // sight of 2 are two generations the map told each owner.
  let #(state, joins, at_ms) =
    players.joined(state: players.empty(), connections: [1, 2], from_ms: 6000)
  let told_sight = fn(owner, viewer) {
    let assert Ok(generation) =
      list.find_map(joins, fn(taken) {
        option.to_result(players.sight_of(taken:, owner:, viewer:), Nil)
      })
      as "the join told the owner the sight its viewer has"
    generation
  }
  let sight = told_sight(1, 2)
  let owners_sight = told_sight(2, 1)
  let first_stay = players.stay(count: 1)
  let #(state, _) =
    players.snapshot(
      state:,
      at_ms:,
      owner: 1,
      owner_stay: first_stay,
      viewer: 2,
      generation: sight,
      burst: [players.health(connection: 1, health: 1)],
    )
  // The connection of player 1 told two news and then ended; the map takes them in that
  // order, then the end of its watch.
  let #(state, first) =
    players.broadcast(
      state:,
      at_ms: at_ms + 1,
      owner: 1,
      owner_stay: first_stay,
      news: players.health(connection: 1, health: 2),
    )
  let #(state, second) =
    players.broadcast(
      state:,
      at_ms: at_ms + 2,
      owner: 1,
      owner_stay: first_stay,
      news: players.health(connection: 1, health: 3),
    )
  let #(_, ended) =
    spawns.feed(state:, at_ms: at_ms + 3, event: WatchEnded(WatchId(1)))
  assert healths(relayed: players.relayed(taken: first)) == [#(2, 2)]
    && healths(relayed: players.relayed(taken: second)) == [#(2, 3)]
    as "each news the connection sent is relayed when the map takes it, in order"
  let to_two =
    list.map(players.notices_to(taken: ended, connection: 2), fn(notice) {
      notice.1
    })
  let unseen = map.PlayerUnseen(unit_id: 1, generation: sight)
  assert list.contains(to_two, unseen)
    && list.contains(to_two, map.Gone(unit_id: 1))
    && list.take_while(to_two, fn(notice) { notice != unseen })
    |> list.all(fn(notice) { notice != map.Gone(unit_id: 1) })
    as "then 2 is told the unit is unseen and then gone: the connection's end sends nothing of the unit before them"
  assert list.contains(
    to_two,
    map.UnseenBy(by: ConnectionId(1), generation: owners_sight),
  )
    as "2, as the owner of its own unit, is told that 1 no longer sees it, from the sight 1 had of it: its copy stops stamping moves to a connection that ended"
}

pub fn a_pair_that_leaves_while_its_snapshot_is_awaited_tells_the_viewer_its_unseen_and_the_late_snapshot_is_dropped_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, sights, at_ms) = owner_and_viewers(viewers: [2])
  let sight = sight_of_viewer(sights:, viewer: 2)
  let #(state, moved) =
    spawns.move(state:, at_ms:, connection: 2, x: spawns.far)
  assert list.map(players.notices_to(taken: moved, connection: 2), fn(notice) {
      notice.1
    })
    |> list.contains(map.PlayerUnseen(unit_id: 1, generation: sight))
    as "the viewer is told the unit is unseen although it took no snapshot of the sight"
  assert players.relation(state:, owner: 1, viewer: 2) == None
    as "the relation is gone"
  let #(_, late) =
    players.snapshot(
      state:,
      at_ms: at_ms + 1,
      owner: 1,
      owner_stay: players.stay(count: 1),
      viewer: 2,
      generation: sight,
      burst: [players.health(connection: 1, health: 1)],
    )
  assert players.relayed(taken: late) == []
    as "the late snapshot relays nothing"
}

pub fn a_move_told_to_the_map_makes_it_decide_sight_and_send_no_move_test() -> Nil {
  use <- owned_test.run(5000)
  // Players 2, 3 and 4 stand at x 200, 300 and 400 and see player 1, at x 100 (sight 1024):
  // its move to x -700 leaves 2 and 3 in sight (900 and 1000 away) and takes 4 out (1100).
  let #(state, sights, at_ms) = owner_and_viewers(viewers: [2, 3, 4])
  let first_stay = players.stay(count: 1)
  let #(state, at_ms) =
    list.fold([2, 3, 4], #(state, at_ms), fn(so_far, viewer) {
      let #(state, at_ms) = so_far
      #(
        players.snapshot(
          state:,
          at_ms:,
          owner: 1,
          owner_stay: first_stay,
          viewer:,
          generation: sight_of_viewer(sights:, viewer:),
          burst: [players.health(connection: 1, health: 1)],
        ).0,
        at_ms + 1,
      )
    })
  let #(_, taken) = spawns.move(state:, at_ms:, connection: 1, x: -700.0)
  assert players.relayed(taken:) == []
    as "the map relays no move, and no news, for a move"
  let sight_notices =
    list.filter_map(support.sends(taken), fn(sent) {
      case sent.1 {
        map.Noticed(notice: map.UnseenBy(by: ConnectionId(by), ..), ..) ->
          Ok(#(sent.0, "UnseenBy " <> int.to_string(by)))
        map.Noticed(notice: map.PlayerUnseen(unit_id:, ..), ..) ->
          Ok(#(sent.0, "PlayerUnseen " <> int.to_string(unit_id)))
        _ -> Error(Nil)
      }
    })
  assert list.contains(sight_notices, #(4, "PlayerUnseen 1"))
    && list.contains(sight_notices, #(1, "UnseenBy 4"))
    as "the viewer that left sight is told the unit is unseen and the owner that it is unseen by it"
  assert list.contains(sight_notices, #(1, "PlayerUnseen 4"))
    && list.contains(sight_notices, #(4, "UnseenBy 1"))
    as "sight is symmetric: 1 no longer sees 4 either, so 1 is told 4's unit is unseen and 4 that 1 no longer sees it"
  assert list.length(sight_notices) == 4
    as "2 and 3 stay in sight and are told nothing of it: only the pair of 1 and 4 leaves, four notices"
  assert list.length(support.sends(taken)) == list.length(sight_notices)
    as "the step sends nothing but the sight notices: no move reaches a viewer through the map"
}
