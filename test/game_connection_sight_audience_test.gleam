//// A player leaving a caster's sight is out of the audience of the caster's casts, whichever
//// of the two news of the departure the caster's connection takes first
//// (`genesis_prime/game/connection/viewers`). Expected values come from these places.
//// - Sight is symmetric: the map moves a pair out of sight in one step and tells each
////   connection that the other's unit is gone (`map.goes_out_of_sight`), so the caster's
////   connection takes the removal of the ally's unit (`Removed`, from the ally's connection)
////   and the map's `UnseenBy` of the ally in either order.
//// - The client keeps a cast whose spell holds propertyFlags 0x100 when its caster's unit is
////   removed, and reads the cast's 0x7fe before the unit's 0x355 when it is finished
////   (`cast.target_node_end`): an ally whose client was told a unit's removal first must be
////   told no finish of that unit's casts after it.
//// - Phantasmal Armor (Spell4 32823, an Esper's at level 6, Spell4Base 19033) pressed at an
////   ally holds its node on the ally alone for 10 000 ms.

import cast_support
import fixture_tables
import game_connection_support as connection_support
import genesis_prime/client_connection
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/game/unit_news.{Appeared, CastFinished, Removed}
import genesis_prime/message/unit_create_player.{UnitCreatePlayer}
import genesis_prime/step.{ConnectionId, OwnEvent}
import genesis_prime/table/loader/store as store_tables
import genesis_prime/world_map/generation
import genesis_prime/world_map/map.{SeenBy, UnseenBy}
import gleam/list
import gleam/option.{None}
import owned_test
import planted_table

const armor_ability = 19_033

/// Which of the two news of the ally's departure the caster's connection takes first.
type Order {
  RemovalFirst
  UnseenFirst
}

/// An ally in sight of the caster: the connection that tells the caster its news and the
/// unit it owns.
type Ally {
  Ally(connection: Int, unit_id: Int)
}

fn ally_event(
  ally ally: Ally,
  news news: unit_news.News,
) -> step.Event(
  step.ConnectionEvent(client_connection.Message, client_connection.Answer),
) {
  connection_support.sent_by_a_peer(connection_support.news_of(
    unit_id: ally.unit_id,
    news:,
  ))
}

/// The Esper of level 6 that pressed Phantasmal Armor at the ally at 1000 ms, with its go
/// run: the connection that holds the cast with its only node on the ally, with the ally
/// shown, in its viewers and in the audience of the cast, and the control viewer 2 beside it.
fn armor_held_on_the_ally(
  tables tables: store_tables.Tables,
  ally ally: Ally,
) -> game_connection.State {
  let #(state, _) =
    connection_support.entered_at_level(
      settings: Settings(..connection_support.settings(), tables:),
      class_id: 3,
      level: 6,
      saved_health: None,
    )
  let bag_index =
    connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: armor_ability,
    )
  let state = connection_support.watched_by(state:, viewers: [2])
  let #(state, _) =
    connection_support.feed(
      state:,
      event: connection_support.sent_by_the_map(SeenBy(
        by: ConnectionId(ally.connection),
        stay: connection_support.viewer_stay(ally.connection),
        unit_id: ally.unit_id,
        generation: connection_support.viewer_sight(ally.connection),
      )),
    )
  let #(state, _) =
    connection_support.feed(
      state:,
      event: ally_event(
        ally:,
        news: Appeared(
          unit: UnitCreatePlayer(
            ..connection_support.another_unit(),
            unit_id: ally.unit_id,
          ),
          generation: generation.first(),
        ),
      ),
    )
  let #(state, pressed) =
    connection_support.at(
      state:,
      ms: 1000,
      event: OwnEvent(
        step.Read(connection_support.world_message(
          message_id: 0x009A,
          body: cast_support.press_body(
            client_cast_id: 1,
            bag_index:,
            target: ally.unit_id,
            press: 1,
          ),
        )),
      ),
    )
  connection_support.casts_run(
    state:,
    pending: connection_support.cast_timers(steps: [pressed], ms: 1000),
    until_ms: 2000,
    steps: [pressed],
  ).0
}

fn is_finish(news news: unit_news.News) -> Bool {
  case news {
    CastFinished(..) -> True
    _ -> False
  }
}

pub fn a_removed_unit_heard_before_the_maps_unseen_by_is_out_of_the_cast_audience_test() -> Nil {
  use <- owned_test.run(10_000)
  // The fixture holds Phantasmal Armor's Spell4 rows and lacks the client's SpellLevel row 773
  // that gives it to an Esper at level 6, so that row is added as the client holds it.
  use tables <- fixture_tables.added(
    table: "SpellLevel",
    copy_of: 647,
    id: 773,
    with: [
      #("characterLevel", planted_table.Integer(6)),
      #("spell4Id", planted_table.Integer(32_823)),
    ],
  )
  let rows = [
    #(
      "the ally's removal heard before the map's unseen: no finish is told to the ally at either",
      Ally(connection: 3, unit_id: 9),
      RemovalFirst,
    ),
    #(
      "the same for another ally, whose connection and unit are not the first's",
      Ally(connection: 4, unit_id: 14),
      RemovalFirst,
    ),
    #(
      "the map's unseen before the ally's removal: no finish is told to the ally",
      Ally(connection: 3, unit_id: 9),
      UnseenFirst,
    ),
  ]
  list.each(rows, fn(row) {
    let #(reason, ally, order) = row
    let removal = ally_event(ally:, news: Removed)
    let unseen =
      connection_support.sent_by_the_map(UnseenBy(
        by: ConnectionId(ally.connection),
        generation: connection_support.viewer_sight(ally.connection),
      ))
    let events = case order {
      RemovalFirst -> [removal, unseen]
      UnseenFirst -> [unseen, removal]
    }
    let #(state, told) =
      list.fold(
        events,
        #(armor_held_on_the_ally(tables:, ally:), #([], [])),
        fn(so_far, event) {
          let #(state, #(ally_told, control_told)) = so_far
          let #(state, taken) = connection_support.feed(state:, event:)
          #(
            state,
            #(
              list.append(
                ally_told,
                connection_support.news_told(taken:, viewer: ally.connection),
              ),
              list.append(
                control_told,
                connection_support.news_told(taken:, viewer: 2),
              ),
            ),
          )
        },
      )
    assert list.any(told.1, fn(news) { is_finish(news:) })
      as {
        reason <> ": the cast finishes for a viewer that stays, so it was held"
      }
    assert !list.any(told.0, fn(news) { is_finish(news:) }) as reason
    let #(_, moved) =
      connection_support.read(state:, bytes: connection_support.a_move(1.5))
    assert connection_support.news_told(taken: moved, viewer: ally.connection)
      == []
      as { reason <> ": the ally is out of the viewers" }
    assert list.any(connection_support.viewer_moves(taken: moved), fn(tell) {
      tell.0 == 2
    })
      as { reason <> ": the control viewer is still told the move" }
  })
}
