//// A map with players only, driven message by message, for the tests that ask what the
//// map tells the players about each other: the notices of sight, the owner's snapshot and
//// news relayed through a relation, a landing delivered by its kind's checks. Every
//// player stands on the x axis of Warfare Woods and sees every other within
//// `genesis_prime/world_map/sight.range`; a player of connection `n` joins as the `n`th
//// unit when the tests join in the order of their numbers.

import connection_rule_support as support
import genesis_prime/game/chat_tell.{type Tell as ChatTell}
import genesis_prime/game/strike_tell
import genesis_prime/game/unit_news.{type PeerNews, Health, PeerNews}
import genesis_prime/step.{type ServiceStep, ConnectionId, OwnEvent, Told}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/relay
import genesis_prime/world_map/stay.{type Stay}
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import map_spawn_support as spawns
import map_support

/// A started map with no spawns.
pub fn empty() -> State {
  spawns.started_with_spawns(spawns: [])
}

/// The stay of a connection's `count`th join.
pub fn stay(count count: Int) -> Stay {
  map_support.stay(count:)
}

/// What the step sends to the connection `connection`, in order.
pub fn sent_to(
  taken taken: ServiceStep(map.Outgoing),
  connection connection: Int,
) -> List(map.Outgoing) {
  support.sends(taken)
  |> list.filter(fn(sent) { sent.0 == connection })
  |> list.map(fn(sent) { sent.1 })
}

/// What the step relays, each as the connection's number, the stay and what is delivered.
pub fn relayed(
  taken taken: ServiceStep(map.Outgoing),
) -> List(#(Int, Stay, relay.Delivered)) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      map.Relayed(stay:, delivered:) -> Ok(#(sent.0, stay, delivered))
      _ -> Error(Nil)
    }
  })
}

/// The notices the step sends to connection `connection`, each with the stay it is sent
/// for, in order.
pub fn notices_to(
  taken taken: ServiceStep(map.Outgoing),
  connection connection: Int,
) -> List(#(Stay, map.Notice)) {
  list.filter_map(sent_to(taken:, connection:), fn(sent) {
    case sent {
      map.Noticed(stay:, notice:) -> Ok(#(stay, notice))
      _ -> Error(Nil)
    }
  })
}

/// The generation of the sight the map told the owner `owner` that the viewer `viewer`
/// has of it (`SeenBy`), when the step tells one.
pub fn sight_of(
  taken taken: ServiceStep(map.Outgoing),
  owner owner: Int,
  viewer viewer: Int,
) -> Option(Generation) {
  list.find_map(notices_to(taken:, connection: owner), fn(notice) {
    case notice.1 {
      map.SeenBy(by: ConnectionId(by), generation:, ..) if by == viewer ->
        Ok(generation)
      _ -> Error(Nil)
    }
  })
  |> option.from_result
}

/// The generation the step gave the sight the viewer has of the owner, which it must
/// tell.
pub fn the_sight_of(
  taken taken: ServiceStep(map.Outgoing),
  owner owner: Int,
  viewer viewer: Int,
) -> Generation {
  let assert Some(generation) = sight_of(taken:, owner:, viewer:)
    as "the step tells the owner that the viewer sees it"
  generation
}

/// The unit id the map gave the player of connection `connection` when the tests join
/// in the order of the numbers from 1.
pub fn unit_of(connection connection: Int) -> Int {
  connection
}

/// A news of the player's health, which the tests relay: it names the unit it is about.
pub fn health(connection connection: Int, health health: Int) -> PeerNews {
  PeerNews(unit_id: unit_of(connection:), news: Health(health:, dead: False))
}

/// The owner's snapshot of the sight `generation` for `viewer`, as its connection tells
/// the map, at time `at_ms`, with the owner's stay `owner_stay`.
pub fn snapshot(
  state state: State,
  at_ms at_ms: Int,
  owner owner: Int,
  owner_stay owner_stay: Stay,
  viewer viewer: Int,
  generation generation: Generation,
  burst burst: List(PeerNews),
) -> #(State, ServiceStep(map.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map.PlayerSnapshot(
        by: ConnectionId(owner),
        stay: owner_stay,
        viewer: ConnectionId(viewer),
        generation:,
        burst:,
      )),
    ),
  )
}

/// A news of the owner's unit, as its connection tells the map, at time `at_ms`.
pub fn broadcast(
  state state: State,
  at_ms at_ms: Int,
  owner owner: Int,
  owner_stay owner_stay: Stay,
  news news: PeerNews,
) -> #(State, ServiceStep(map.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map.PlayerBroadcast(
        from: ConnectionId(owner),
        stay: owner_stay,
        news:,
      )),
    ),
  )
}

/// A landing of the player of connection `from`, in its stay `from_stay`, on the player
/// of connection `to`, in the stay `to_stay`, at time `at_ms`.
pub fn landing(
  state state: State,
  at_ms at_ms: Int,
  from from: Int,
  from_stay from_stay: Stay,
  to to: Int,
  to_stay to_stay: Stay,
  landing landing: relay.Landing,
) -> #(State, ServiceStep(map.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map.TellLanding(
        from: ConnectionId(from),
        stay: from_stay,
        to: ConnectionId(to),
        to_stay:,
        landing:,
      )),
    ),
  )
}

/// A local chat line of the player, as its connection tells the map, at time `at_ms`.
pub fn say(
  state state: State,
  at_ms at_ms: Int,
  speaker speaker: Int,
  speaker_stay speaker_stay: Stay,
  tell tell: ChatTell,
) -> #(State, ServiceStep(map.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map.Say(
        from: ConnectionId(speaker),
        stay: speaker_stay,
        tell:,
      )),
    ),
  )
}

/// The answer of a heal strike that the tests send as a landing: the strike of the cast
/// `cast_id` on `unit_id`.
pub fn answer(cast_id cast_id: Int, unit_id unit_id: Int) -> relay.Landing {
  relay.HealAnswer(answered: strike_tell.PlayerAnswered(
    key: strike_tell.Key(
      cast_id:,
      occasion: strike_tell.AtGo(phase: 0),
      unit_id:,
    ),
    outcome: strike_tell.PlayerDead,
  ))
}

/// The state's relation for a viewer of an owner, as the tests read it.
pub fn relation(
  state state: State,
  owner owner: Int,
  viewer viewer: Int,
) -> Option(map.Relation) {
  map.player_relation(
    state:,
    owner: ConnectionId(owner),
    viewer: ConnectionId(viewer),
  )
}

/// The first player to join, which is the owner the tests watch, and `viewers` after it,
/// in the order given, all in sight of each other: the state, the step of each join and
/// the time after them.
pub fn joined(
  state state: State,
  connections connections: List(Int),
  from_ms from_ms: Int,
) -> #(State, List(ServiceStep(map.Outgoing)), Int) {
  list.fold(connections, #(state, [], from_ms), fn(so_far, connection) {
    let #(state, taken, at_ms) = so_far
    let #(state, step) =
      spawns.join(
        state:,
        at_ms:,
        connection:,
        x: 100.0 *. int.to_float(connection),
      )
    #(state, list.append(taken, [step]), at_ms + 10)
  })
}
