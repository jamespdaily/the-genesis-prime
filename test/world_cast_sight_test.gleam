//// A player that comes into sight of a casting player, through the map's rule and the two
//// players' game connections (`genesis_prime/game/connection`), each run as the pure function
//// it is, the test carrying the map's notices and the connections' tells between them as the
//// shell does. Expected values come from `opcode.0x262.casts` (the create lists the cast the
//// player holds the bar of) and `cast.target_node_end` (the client ends a cast only by the
//// 0x7fe it is sent, so the viewer must be sent it).

import game_connection_support as support
import genesis_prime/client_connection.{type Request, SentByMap}
import genesis_prime/game/connection as game_connection
import genesis_prime/game/connection/state.{Settings}
import genesis_prime/message/unit_create_cast.{UnitCreateCast}
import genesis_prime/message/unit_create_player
import genesis_prime/step.{type ConnectionStep}
import genesis_prime/store.{Character}
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/map
import gleam/list
import owned_test

/// The connection the arriving player has in the map: 2 to 5 are the map's other players.
const viewer_connection = 6

/// What the viewer's connection takes from the tells a step makes it, in order: its state and
/// the steps it took.
fn viewer_takes(
  viewer viewer: game_connection.State,
  taken taken: List(ConnectionStep(Request)),
) -> #(game_connection.State, List(ConnectionStep(Request))) {
  list.fold(taken, #(viewer, []), fn(held, step) {
    list.fold(support.peer_tells(step), held, fn(held, tell) {
      case tell.0 == viewer_connection {
        True -> {
          let #(viewer, steps) = held
          let #(viewer, taken) =
            support.feed(viewer, support.sent_by_a_peer(tell.1))
          #(viewer, list.append(steps, [taken]))
        }
        False -> held
      }
    })
  })
}

fn frame_ids(steps: List(ConnectionStep(Request))) -> List(Int) {
  list.flat_map(steps, support.written_ids)
}

pub fn a_viewer_joining_beside_a_casting_player_shows_its_cast_bar_and_writes_its_end_test() -> Nil {
  use <- owned_test.run(60_000)
  use tables <- support.with_a_cast_bar(channeled: False)
  let #(owner, map_state, _) =
    support.joined_among(
      settings: Settings(..support.settings(), tables:),
      character: Character(..support.world_character(), class_id: ClassId(4)),
      map_state: support.map_with_four_players(),
      connection: 1,
    )
  let #(owner, pressed) =
    support.pressed_until(
      state: owner,
      bag_index: 2,
      client_cast_id: 1,
      ms: 1000,
      until_ms: 1000,
    )
  let assert [press, ..] = pressed as "the press is the first step"
  let assert [start] =
    support.cast_starts(support.news_told(taken: press, viewer: 2))
    as "a watcher is told one cast started"
  let #(viewer, _, told) =
    support.joined_among(
      settings: support.settings(),
      character: support.world_character(),
      map_state:,
      connection: viewer_connection,
    )
  let #(owner, noticed) =
    list.fold(told, #(owner, []), fn(held, sent) {
      case sent {
        #(1, map.Noticed(stay:, notice:)) -> {
          let #(owner, steps) = held
          let #(owner, taken) =
            support.feed(
              state: owner,
              event: support.for_stay(stay:, sent: SentByMap(notice)),
            )
          #(owner, list.append(steps, [taken]))
        }
        #(_, _) -> held
      }
    })
  let #(viewer, arrival) = viewer_takes(viewer:, taken: noticed)
  let assert [created] =
    support.decoded(
      support.heard(
        {
          let assert [taken] = arrival
            as "the owner's create reaches the viewer"
          taken
        },
        support.keyed(),
      ),
      0x0262,
      unit_create_player.decode,
    )
    as "the viewer is created the owner's unit"
  assert created.unit_id == support.own_unit_id
  assert created.tail.casts
    == [
      UnitCreateCast(
        caster_unit_id: support.own_unit_id,
        primary_target_unit_id: start.primary_target_unit_id,
        cast_id: start.cast_id,
        spell4_id: start.spell4_id,
        started: 1,
        targets: [],
        initial_positions: [],
        telegraph_positions: [],
      ),
    ]
    as "the create lists the cast the owner holds the bar of, not yet gone"
  assert created.tail.cast_id == start.cast_id
    as "and names it as the cast in progress"
  let #(_, timers) =
    support.casts_run(
      state: owner,
      pending: support.cast_timers(steps: pressed, ms: 1000),
      until_ms: 60_000,
      steps: [],
    )
  let #(_, later) = viewer_takes(viewer:, taken: timers)
  assert list.filter(frame_ids(later), fn(id) { id == 0x07F4 || id == 0x07FE })
    == [0x07F4, 0x07FE]
    as "the viewer is written the cast's go and its end, since the cast is one it was given"
}
