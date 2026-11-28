//// A map with players only, driven message by message, for the tests that ask what the
//// map tells the players about each other: the notices of sight, the owner's snapshot and
//// news relayed through a relation, a landing delivered by its kind's checks. Every
//// player stands on the x axis of Warfare Woods and sees every other within
//// `genesis_prime/shared/sight.range`; a player of connection `n` joins as the `n`th
//// unit when the tests join in the order of their numbers.

import character_support
import connection_rule_support as support
import genesis_prime/map/message as map_message
import genesis_prime/message/bit_stream
import genesis_prime/shared/chat_channel
import genesis_prime/shared/chat_tell.{type Said as ChatSaid}
import genesis_prime/shared/player_unit
import genesis_prime/shared/strike_tell
import genesis_prime/shared/unit_news.{type PeerNews, Appeared, Health, PeerNews}
import genesis_prime/step.{type ServiceStep, OwnEvent, Told}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/map_id
import genesis_prime/world_map/unit_address
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import map_spawn_support as spawns
import map_support
import place_support
import unit_support

/// A started map with no spawns.
pub fn empty() -> State {
  spawns.started_with_spawns(spawns: [])
}

/// What the step sends to the connection `connection`, in order.
pub fn sent_to(
  taken taken: ServiceStep(map_message.Outgoing),
  connection connection: Int,
) -> List(map_message.Outgoing) {
  support.sends(taken)
  |> list.filter(fn(sent) { sent.0 == connection })
  |> list.map(fn(sent) { sent.1 })
}

/// What the step relays, each as the number of the unit's address and what is delivered.
pub fn relayed(
  taken taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, map_message.Delivered)) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      map_message.Relayed(delivered:) -> Ok(#(sent.0, delivered))
      _ -> Error(Nil)
    }
  })
}

/// What a step sends as a notice (`Noticed`), each as the number of the unit's address it is
/// sent to and the notice, in the order sent.
pub fn notices(
  taken taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, map_message.Notice)) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      map_message.Noticed(notice:) -> Ok(#(sent.0, notice))
      _ -> Error(Nil)
    }
  })
}

/// The notices the step sends to connection `connection`'s unit, in order.
pub fn notices_to(
  taken taken: ServiceStep(map_message.Outgoing),
  connection connection: Int,
) -> List(map_message.Notice) {
  list.filter_map(notices(taken:), fn(sent) {
    case sent.0 == connection {
      True -> Ok(sent.1)
      False -> Error(Nil)
    }
  })
}

/// The generation of the sight the map told the owner `owner` that the viewer `viewer`
/// has of it (`SeenBy`), when the step tells one.
pub fn sight_of(
  taken taken: ServiceStep(map_message.Outgoing),
  owner owner: Int,
  viewer viewer: Int,
) -> Option(Generation) {
  list.find_map(notices_to(taken:, connection: owner), fn(notice) {
    case notice {
      map_message.SeenBy(by:, generation:, ..) ->
        case unit_address.rank(address: by) == viewer {
          True -> Ok(generation)
          False -> Error(Nil)
        }
      _ -> Error(Nil)
    }
  })
  |> option.from_result
}

/// The generation the step gave the sight the viewer has of the owner, which it must
/// tell.
pub fn the_sight_of(
  taken taken: ServiceStep(map_message.Outgoing),
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
/// the map, at time `at_ms`: the owner's own 0x262 of
/// that sight, as a real owner begins it, then `burst`.
pub fn snapshot(
  state state: State,
  at_ms at_ms: Int,
  owner owner: Int,
  viewer viewer: Int,
  generation generation: Generation,
  burst burst: List(PeerNews),
) -> #(State, ServiceStep(map_message.Outgoing)) {
  snapshot_as_told(state:, at_ms:, owner:, viewer:, generation:, burst: [
    appeared(owner:, generation:),
    ..burst
  ])
}

/// The owner's 0x262 of the sight `generation`, which begins a snapshot.
pub fn appeared(
  owner owner: Int,
  generation generation: Generation,
) -> PeerNews {
  PeerNews(
    unit_id: unit_of(connection: owner),
    news: Appeared(
      unit: player_unit.create(
        unit: unit_support.bare_unit(
          character: character_support.character(number: owner),
          place: place_support.live_character_place(),
          unit_id: unit_of(connection: owner),
          body: [],
        ),
        realm_id: 1,
      ),
      generation:,
    ),
  )
}

/// A snapshot exactly as given: `burst` is relayed or refused as it is.
pub fn snapshot_as_told(
  state state: State,
  at_ms at_ms: Int,
  owner owner: Int,
  viewer viewer: Int,
  generation generation: Generation,
  burst burst: List(PeerNews),
) -> #(State, ServiceStep(map_message.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.PlayerSnapshot(
        by: map_support.unit(state:, connection: owner),
        viewer: map_support.unit(state:, connection: viewer),
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
  news news: PeerNews,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.PlayerBroadcast(
        from: map_support.unit(state:, connection: owner),
        news:,
      )),
    ),
  )
}

/// A landing of the player of connection `from` on the player of connection `to`, at time
/// `at_ms`.
pub fn landing(
  state state: State,
  at_ms at_ms: Int,
  from from: Int,
  to to: Int,
  landing landing: map_message.Landing,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.TellLanding(
        from: map_support.unit(state:, connection: from),
        to: map_support.unit(state:, connection: to),
        landing:,
      )),
    ),
  )
}

/// A Say line of the player of connection `connection`, as that player's chat builds it: the
/// speaker's unit is the connection's.
pub fn said_by(connection connection: Int, text text: String) -> ChatSaid {
  chat_tell.Said(
    speaker: chat_tell.Speaker(
      realm_id: 1,
      character_id: connection,
      name: "Speaker " <> int.to_string(connection),
      faction_id: 166,
      unit_id: unit_of(connection:),
      map: map_id.MapId(world_id: 1, instance: 0),
      incarnation: 1,
    ),
    line: chat_tell.Line(
      channel_type: chat_channel.Say,
      channel_id: 0,
      text: bit_stream.utf16_units(text),
      formats: [],
    ),
  )
}

/// A local chat line of the player, as its connection tells the map, at time `at_ms`.
pub fn say(
  state state: State,
  at_ms at_ms: Int,
  speaker speaker: Int,
  said said: ChatSaid,
) -> #(State, ServiceStep(map_message.Outgoing)) {
  spawns.feed(
    state:,
    at_ms:,
    event: OwnEvent(
      Told(message: map_message.Say(
        from: map_support.unit(state:, connection: speaker),
        said:,
      )),
    ),
  )
}

/// The answer of a heal strike that the tests send as a landing: the strike of the cast
/// `cast_id` on `unit_id`.
pub fn answer(
  cast_id cast_id: Int,
  unit_id unit_id: Int,
) -> map_message.Landing {
  map_message.HealAnswer(answered: strike_tell.PlayerAnswered(
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
    owner: map_support.unit(state:, connection: owner),
    viewer: map_support.unit(state:, connection: viewer),
  )
}

/// The first player to join, which is the owner the tests watch, and `viewers` after it,
/// in the order given, all in sight of each other: the state, the step of each join and
/// the time after them.
pub fn joined(
  state state: State,
  connections connections: List(Int),
  from_ms from_ms: Int,
) -> #(State, List(ServiceStep(map_message.Outgoing)), Int) {
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
