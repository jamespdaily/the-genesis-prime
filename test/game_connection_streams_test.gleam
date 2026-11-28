//// What a player's connection tells the map, not the connections of other players, as the
//// connection's rule takes its inputs with no socket: its snapshot for a viewer the map
//// names, and the news a heal's landing makes. Expected values come from these places.
//// - The map is the one sender of a player's unit to its viewers
////   (`genesis_prime/world_map/map`): a connection told `SeenBy(by, stay, unit, g)`
////   answers the map with one `TellSnapshot` of that generation, and tells its own news as
////   `TellBroadcast`; it never tells a viewer's connection, and its camp is no removal:
////   the map's `PlayerUnseen` is.
//// - The create flags of a stealthed player are 16 (`opcode.0x262.unit_fields`), and a
////   0x262 lists the casts the unit holds (`opcode.0x262`).
//// - A heal's answer is told before the target's own news, as a creature's is
////   (`genesis_prime/game/connection/landing`).

import fixture_tables
import game_connection_support as support
import genesis_prime/client_connection.{type Request}
import genesis_prime/map/message as map_message
import genesis_prime/shared/effect_kind
import genesis_prime/shared/heal_parts.{Split}
import genesis_prime/shared/strike_tell.{
  HealLanded, HealsLanded, Key, PlayerAnswered,
}
import genesis_prime/shared/unit_news.{type PeerNews, Appeared, PeerNews}
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/table/id.{Spell4EffectsId}
import genesis_prime/world_map/generation.{type Generation}
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/int
import gleam/list
import map_support
import owned_test
import planted_table

/// The snapshots a step tells the map, each as the viewer's address, the generation and the
/// burst.
fn snapshots_told(
  taken taken: ConnectionStep(Request),
) -> List(#(UnitAddress, Generation, List(PeerNews))) {
  list.filter_map(support.told_the_map(taken), fn(effect) {
    case effect {
      step.OwnEffect(step.Tell(
        request: client_connection.TellSnapshot(
          viewer:,
          generation:,
          burst:,
          ..,
        ),
        ..,
      )) -> Ok(#(viewer, generation, burst))
      _ -> Error(Nil)
    }
  })
}

/// The map's `SeenBy` of the sight the viewer `viewer` has of the tests' player.
fn seen_by(
  viewer viewer: Int,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  support.sent_by_the_map(map_message.SeenBy(
    by: support.viewer_address(viewer),
    unit_id: support.viewer_unit_id(viewer),
    generation: support.viewer_sight(viewer),
  ))
}

/// The create flags the snapshot's first item carries, which is the player's 0x262.
fn create_flags(burst burst: List(PeerNews)) -> Int {
  let assert [PeerNews(news: Appeared(unit:, ..), ..), ..] = burst
    as "the snapshot begins with the player's unit"
  unit.tail.create_flags
}

pub fn an_owner_answers_the_seen_of_a_generation_with_one_snapshot_listing_its_live_casts_and_a_camp_sends_its_viewers_nothing_itself_test() -> Nil {
  use <- owned_test.run(10_000)
  // A plain player: one snapshot of the generation the map named, for the viewer and the
  // stay it named, holding the player's 0x262, and no news told to the viewer's connection.
  let #(state, taken) =
    support.feed(state: support.in_world(), event: seen_by(viewer: 2))
  assert list.map(snapshots_told(taken:), fn(snapshot) {
      #(snapshot.0, snapshot.1)
    })
    == [#(support.viewer_address(2), support.viewer_sight(2))]
    as "one snapshot, for the viewer the map named, of the generation named (`PlayerSnapshot`)"
  let assert [#(_, _, burst)] = snapshots_told(taken:)
  assert list.map(burst, fn(item) { item.unit_id }) == [support.own_unit_id]
    as "it holds the player's own unit"
  assert support.tells_to_players_but_moves(taken) == []
    as "and the connection tells the viewer's connection nothing itself: the map relays the snapshot"
  // The next move step addresses that viewer with the generation, after the snapshot.
  let #(_, moved) = support.read(state:, bytes: support.a_move(1.5))
  assert list.map(support.viewer_moves(taken: moved), fn(tell) {
      #(tell.0, tell.1.generation)
    })
    == [#(2, support.viewer_sight(2))]
    as "after the map's SeenBy the player's next move is told to that viewer with the generation (positive control)"
  let #(_, before) =
    support.read(state: support.in_world(), bytes: support.a_move(1.5))
  assert support.viewer_moves(taken: before) == []
    as "and no move is told to a viewer the map has not named"
  // A stealthed player's snapshot carries create flag 16.
  let #(stealthed, _) = support.stealthed_stalker()
  let #(_, taken) = support.feed(state: stealthed, event: seen_by(viewer: 2))
  let assert [#(_, _, stealth_burst)] = snapshots_told(taken:)
  assert int.bitwise_and(create_flags(burst: stealth_burst), 16) == 16
    as "create flag 16 makes the unit stealthed from its creation (opcode.0x262.unit_fields)"
  // A player that is casting lists the cast its 0x262 holds.
  use tables <- fixture_tables.added(
    table: "SpellLevel",
    copy_of: 647,
    id: 773,
    with: [
      #("characterLevel", planted_table.Integer(6)),
      #("spell4Id", planted_table.Integer(32_823)),
    ],
  )
  let #(caster, _) =
    support.armor_pressed_at_the_ally(tables:, ally_connection: 3, ally_unit: 9)
  let #(_, taken) = support.feed(state: caster, event: seen_by(viewer: 4))
  let assert [#(_, _, casting_burst)] = snapshots_told(taken:)
  let assert [PeerNews(news: Appeared(unit:, ..), ..), ..] = casting_burst
    as "the snapshot begins with the player's unit"
  assert unit.tail.casts != []
    as "the live cast is listed in the 0x262 of the snapshot, as it was in the 0x262 the connection used to send"
  // A camp sends its viewers nothing: the map's PlayerUnseen is the removal.
  let #(camping, _) =
    support.read(
      state: support.watched_by(support.in_world(), [3, 2]),
      bytes: support.camp_request_message(True),
    )
  let #(camping, finished) =
    support.read(state: camping, bytes: support.camp_finished_message())
  let #(_, saved) =
    support.answer(
      state: camping,
      taken: finished,
      outcome: support.place_saved(),
    )
  assert support.tells_to_players_but_moves(saved) == []
    as "a camp's step tells no viewer a removal: the map ends each sight when the leave is taken"
  assert support.ask_request(saved) == support.leave_asked()
    as "and the leave of the map is still asked in that step"
}

pub fn a_heals_answer_precedes_the_targets_own_news_in_the_maps_stream_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(state, _) =
    support.feed(
      state: support.watched_by(support.in_world(), [2]),
      event: support.a_beast_strike(support.own_unit_id),
    )
  let #(_, taken) =
    support.feed(
      state:,
      event: support.for_unit(
        address: support.own_address(),
        sent: support.a_player_strike(
          from: 3,
          cast_id: 100,
          outgoing: 1.0,
          heals: [#(effect_kind.Shield, 10), #(effect_kind.Health, 40)],
        ),
      ),
    )
  let answered =
    PlayerAnswered(
      key: Key(
        cast_id: 100,
        occasion: strike_tell.AtGo(phase: 0),
        unit_id: support.own_unit_id,
      ),
      outcome: HealsLanded(heals: [
        HealLanded(
          effect_id: Spell4EffectsId(62_019),
          vital: effect_kind.Shield,
          split: Split(amount: 10, shield: 2, health: 0, overheal: 8),
        ),
        HealLanded(
          effect_id: Spell4EffectsId(62_020),
          vital: effect_kind.Health,
          split: Split(amount: 40, shield: 0, health: 1, overheal: 39),
        ),
      ]),
    )
  let own = support.own_address()
  assert support.told_the_map_but_creatures(taken)
    == [
      support.map_tell(client_connection.TellLanding(
        unit: own,
        to: map_support.address(number: 3),
        landing: map_message.HealAnswer(answered:),
      )),
      support.map_tell(client_connection.TellBroadcast(
        unit: own,
        news: support.told(news: unit_news.Shield(shield: 450)),
      )),
      support.map_tell(client_connection.TellBroadcast(
        unit: own,
        news: support.told(news: unit_news.Health(health: 736, dead: False)),
      )),
    ]
    as "the answer to the caster, then the target's own Shield and Health news, all to the map in one stream: the map relays them in that order"
  assert list.filter(support.tells(taken), fn(told) {
      case told.0 {
        step.Connection(..) -> True
        _ -> False
      }
    })
    == []
    as "and nothing is told to another player's connection directly"
}

pub fn a_snapshot_names_the_players_own_address_test() -> Nil {
  use <- owned_test.run(10_000)
  let #(_, taken) =
    support.feed(state: support.in_world(), event: seen_by(viewer: 2))
  assert list.map(support.told_the_map(taken), fn(effect) {
      case effect {
        step.OwnEffect(step.Tell(
          request: client_connection.TellSnapshot(unit:, viewer:, ..),
          ..,
        )) -> Ok(#(unit, viewer))
        _ -> Error(Nil)
      }
    })
    == [Ok(#(support.own_address(), support.viewer_address(2)))]
    as "the snapshot names the player's own address as its owner and the viewer's address the notice named"
}
