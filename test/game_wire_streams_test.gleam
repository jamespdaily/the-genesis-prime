//// Two players on the whole server, with the map's sends to the connections held back, as
//// the tests of one unit's frames at another player's client: the map is the one sender of a
//// player's unit to its viewers, so a delay in its sends delays the unit's 0x262 and 0x355
//// and holds nothing else apart from them. Every wait is for bytes the server writes, with a
//// deadline a passing test never reaches. Expected values come from these places.
//// - The client creates a unit once, removes it once and reads no frame of it before its 0x262
////   or after its 0x355 (`opcode.0x262`, `opcode.0x355`, `opcode.0x638`).
//// - A cast of a spell with propertyFlags 0x100 keeps its buff when its caster's unit is
////   removed (`cast.target_node_end`).
//// - A player's moves are the one thing its connection tells a viewer itself, stamped with the
////   generation of the sight (`genesis_prime/game/move_stamp`): while the map's 0x262 is late
////   a viewer holds them, and writes them in order after the 0x262.

import client_tables
import driven_time
import game_client
import game_connection_support as connection_support
import game_wire_support.{
  TwoEntered, started_with_the_maps_sends_delayed, two_players_enter, unit_of,
  walk_to,
}
import genesis_prime/connection/frame.{type Frame}
import gleam/dict
import gleam/list
import gleam/option.{type Option, Some}
import legal_order_support
import login_support
import owned_test
import unitest

/// How long the map's sends are held in these tests: the delay that made the race of #1409
/// happen on demand.
const delay_ms = 150

/// The opcodes of the frames that name the unit, in order: its 0x262, 0x638 and 0x355.
fn of_the_unit(frames frames: List(Frame), unit_id unit_id: Int) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case legal_order_support.unit_of(frame:) {
      Some(found) if found == unit_id -> Ok(frame.message_id)
      _ -> Error(Nil)
    }
  })
}

/// The ids of the cast frames among the frames.
fn cast_ids(frames frames: List(Frame)) -> List(Int) {
  list.filter_map(frames, fn(frame) {
    case frame.message_id {
      0x07FF | 0x07F4 | 0x07FE | 0x0811 -> Ok(frame.message_id)
      _ -> Error(Nil)
    }
  })
}

/// The frames after the first 0x355 of the unit.
fn after_the_removal(
  frames frames: List(Frame),
  unit_id unit_id: Int,
) -> List(Frame) {
  list.drop_while(frames, fn(frame) {
    !{
      frame.message_id == 0x0355 && of_the_unit(frames: [frame], unit_id:) != []
    }
  })
  |> list.drop(1)
}

pub fn no_frame_of_a_units_cast_reaches_a_viewer_after_that_units_removal_with_the_maps_sends_delayed_150_ms_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_with_the_maps_sends_delayed(tables:, time:, delay_ms:)
  let TwoEntered(first:, second:, seen_second:, second_burst:, second_have:, ..) =
    two_players_enter(started:, first_class: 3, level: 6)
  let esper = 1
  let medic = unit_of(seen_second)
  game_client.press_ability(
    game: first,
    client_cast_id: 1,
    bag_index: connection_support.bag_index_of(
      tables:,
      class_id: 3,
      level: 6,
      ability: 19_033,
    ),
    target: medic,
  )
  // The Esper walks in steps and then out of the Medic's sight (1040 along z, past 1024).
  list.each([10.0, 20.0, 30.0, 1040.0], fn(z) {
    walk_to(game: first, z:, clock: 1)
  })
  let #(read, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), esper)
    })
  let #(after_the_pong, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let frames = list.flatten([second_burst, read, after_the_pong])
  assert cast_ids(frames: after_the_removal(frames:, unit_id: esper)) == []
    as "no frame of the Esper's cast reaches the Medic's client after the Esper's 0x355, though the map's sends are held 150 ms"
  let moves = of_the_unit(frames:, unit_id: esper)
  assert list.first(moves) == Ok(0x0262) && list.last(moves) == Ok(0x0355)
    as "the Esper's frames at the Medic begin with its 0x262 and end with its 0x355"
  assert list.all(
    list.drop(list.take(moves, list.length(moves) - 1), 1),
    fn(id) { id == 0x0638 },
  )
    as "and every frame of it between them is a move: none after the 0x355 and none before the 0x262"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}

/// Where the client's model of other units, built from the frames in order, stands the unit:
/// its 0x262 places it, each 0x638 moves it, and its 0x355 removes it.
fn place_at_the_viewer(
  frames frames: List(Frame),
  unit_id unit_id: Int,
) -> Option(#(Float, Float, Float)) {
  list.fold(frames, dict.new(), fn(others, frame) {
    game_client.observe(others:, frame:)
  })
  |> dict.get(unit_id)
  |> option.from_result
}

/// Whether every 0x638 among the opcodes of one unit's frames lies after a 0x262 and before the
/// next 0x355: the client reads no move of a unit it does not show.
fn moves_only_while_shown(ids ids: List(Int)) -> Bool {
  list.fold(ids, #(False, True), fn(so_far, id) {
    let #(shown, all_shown) = so_far
    case id {
      0x0262 -> #(True, all_shown)
      0x0355 -> #(False, all_shown)
      0x0638 -> #(shown, all_shown && shown)
      _ -> so_far
    }
  }).1
}

pub fn a_viewer_is_written_every_move_a_walking_player_makes_after_its_0x262_with_the_maps_sends_delayed_150_ms_test() -> Nil {
  use <- owned_test.run(10_000)
  use <- unitest.guard(client_tables.present())
  let time = driven_time.new()
  let tables = client_tables.shared()
  let started = started_with_the_maps_sends_delayed(tables:, time:, delay_ms:)
  let TwoEntered(
    first:,
    second:,
    seen_second:,
    second_burst:,
    first_have:,
    second_have:,
    ..,
  ) = two_players_enter(started:, first_class: 4, level: 1)
  let walker = 1
  assert unit_of(seen_second) == 2 as "the Medic is the second unit"
  // The walker leaves the viewer's sight and comes back, and walks on while the map's sight
  // of it, and its snapshot, are held: its moves reach the viewer first and are held there.
  walk_to(game: first, z: 1040.0, clock: 1)
  let #(left, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.contains(game_client.removals_in(frames:), walker)
    })
  walk_to(game: first, z: 0.0, clock: 2)
  // The walker's connection answers a ping after what the map sent it before the ping, and the
  // map sent it the notice of the new sight right after the move: two pings take the notice
  // before the walker walks on, so its moves go to the viewer while the viewer's 0x262 is late
  // and are held there. The assertions below hold whichever order the notice and the moves
  // are taken in.
  let #(_, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 1)
  let #(_, first_have) =
    game_client.read_until_pong(game: first, have: first_have, number: 2)
  let steps = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0]
  list.index_map(steps, fn(z, index) {
    walk_to(game: first, z:, clock: 3 + index)
  })
  let last_step = #(1.5, 2.5, 8.0)
  let #(back, second_have) =
    game_client.read_until(game: second, have: second_have, found: fn(frames) {
      list.count(
        of_the_unit(
          frames: list.flatten([second_burst, left, frames]),
          unit_id: walker,
        ),
        fn(id) { id == 0x0262 },
      )
      == 2
    })
  // The walker's connection took every move before its pong and told the viewer what it
  // told it before the pong: the viewer's pong holds all of it, held moves released.
  let #(_, _) =
    game_client.read_until_pong(game: first, have: first_have, number: 3)
  let #(after_the_pong, _) =
    game_client.read_until_pong(game: second, have: second_have, number: 1)
  let back = list.append(back, after_the_pong)
  let at_the_viewer =
    of_the_unit(
      frames: list.flatten([second_burst, left, back]),
      unit_id: walker,
    )
  assert moves_only_while_shown(ids: at_the_viewer)
    as "every move the viewer is written lies between a 0x262 of the walker and its next 0x355, whatever the timing of the map's sends"
  let after_the_second_sight =
    list.drop_while(list.drop(at_the_viewer, 1), fn(id) { id != 0x0262 })
  assert list.first(after_the_second_sight) == Ok(0x0262)
    as "the second sight is written as a 0x262 of the walker after its 0x355"
  assert list.all(list.drop(after_the_second_sight, 1), fn(id) { id == 0x0638 })
    as "after the second 0x262 the viewer is written only moves of the new sight, none of the sight that ended"
  assert place_at_the_viewer(
      frames: list.flatten([second_burst, left, back]),
      unit_id: walker,
    )
    == Some(last_step)
    as "the viewer's last place of the walker is the last place the walker walked to: no move made while the sight was late is lost"
  game_client.close(game: first)
  game_client.close(game: second)
  login_support.stop(started)
}
