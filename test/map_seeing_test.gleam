//// Who sees whom in a map (`genesis_prime/world_map/map`, `sight`), run as the
//// pure rule it is: inputs in, new state and effects out. Expected values come
//// from these places.
//// - The sight range: 1024 units, 3D, at most (the decision on issue 272, from
////   `unit.range`: the client removes no unit by distance and draws out to
////   lod.viewDistance, 256 to 1024). A pair at exactly 1024.0 sees; 1024.01
////   does not.
//// - Unit ids: never 0 (a 0x262 with unit id 0 becomes the controlled unit,
////   0x1403d9760) and never given twice (the client does nothing for a unit it
////   has, 0x1403d9760).
//// - The design of issue 272 (the map's doc comment): the map decides sight and
////   sends the client no unit and no move; a pair that comes into sight is sent
////   `Watched` both ways in one step, a pair that leaves it `Unwatched`, and a
////   player whose connection ended is `Gone` to each player that saw it, which
////   its connection could not send itself.
//// - The map's clock: milliseconds since the map started, the monotonic time of
////   the input minus the monotonic time of `Started`, taken mod 2^32 because the
////   client's fields hold 32 bits (the doc comment of `map.server_time`);
////   `Joined` carries the origin.

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId, ConnectionId,
  LogError, OwnEvent, Started, Told, WatchEnded, WatchId,
}
import genesis_prime/world_map/map.{
  type State, Gone, Join, Joined, Leave, Moved, Unwatched, Watched,
}
import genesis_prime/world_map/sight
import gleam/int
import gleam/list
import gleam/string
import map_support
import owned_test
import place_support

const realm_id = map_support.realm_id

/// The time the map starts at on the monotonic clock, so a server time is not
/// the monotonic time.
const started_at_ms = 5000

fn started() -> State {
  let state = map_support.empty(incarnation: 1)
  let #(state, _) =
    feed(state: state, at_ms: started_at_ms, event: OwnEvent(Started))
  state
}

fn feed(
  state state: State,
  at_ms at_ms: Int,
  event event: Event(ServiceEvent(map.Message)),
) -> #(State, ServiceStep(map.Outgoing)) {
  map.step(state, support.input_at_ms(ms: at_ms, event:))
}

/// A place `x` units along the world's x axis.
fn at(x: Float) -> Place {
  place_support.at(world_id: 3460, world_zone_id: 6009, x:, y: 0.0, z: 0.0)
}

/// A join of connection `connection` at `place`, `elapsed_ms` after the map
/// started.
fn join(
  state state: State,
  connection connection: Int,
  place place: Place,
  elapsed_ms elapsed_ms: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state: state,
    at_ms: started_at_ms + elapsed_ms,
    event: OwnEvent(Asked(
      caller: CallerId(connection),
      message: Join(
        connection: ConnectionId(connection),
        character: map_support.character(100 + connection),
        place:,
      ),
    )),
  )
}

/// A move of connection `connection` to `x`, `elapsed_ms` after the map
/// started: a tell, which holds the place and nothing else.
fn move(
  state state: State,
  connection connection: Int,
  x x: Float,
  elapsed_ms elapsed_ms: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state: state,
    at_ms: started_at_ms + elapsed_ms,
    event: OwnEvent(
      Told(message: Moved(
        connection: ConnectionId(connection),
        place: at(x),
        seq: elapsed_ms,
      )),
    ),
  )
}

/// A leave of connection `connection`.
fn leave(
  state state: State,
  connection connection: Int,
  elapsed_ms elapsed_ms: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state: state,
    at_ms: started_at_ms + elapsed_ms,
    event: OwnEvent(Asked(
      CallerId(9),
      Leave(connection: ConnectionId(connection)),
    )),
  )
}

/// Each send of a step as the connection it goes to and what it says, with the
/// viewers and units by number: `Watched by 2`, `Unwatched by 1`, `Gone 2`.
fn shape(taken: ServiceStep(map.Outgoing)) -> List(#(Int, String)) {
  list.map(support.sends(taken), fn(sent) {
    #(sent.0, case sent.1 {
      Watched(by: ConnectionId(number), ..) ->
        "Watched by " <> int.to_string(number)
      Unwatched(by: ConnectionId(number)) ->
        "Unwatched by " <> int.to_string(number)
      Gone(unit_id:) -> "Gone " <> int.to_string(unit_id)
      Joined(..) | map.NotJoined(..) | map.Left -> "an answer"
      map.Retire -> "Retire"
      map.Approached(by: ConnectionId(number), ..) ->
        "Approached by " <> int.to_string(number)
      map.Withdrew(by: ConnectionId(number)) ->
        "Withdrew by " <> int.to_string(number)
    })
  })
}

/// A map with connections 1 and 2 joined at x 0 and `x`.
fn two_players(x: Float) -> #(State, ServiceStep(map.Outgoing)) {
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 100)
  join(state: state, connection: 2, place: at(x), elapsed_ms: 200)
}

pub fn a_watched_names_the_unit_of_the_player_who_sees_test() -> Nil {
  use <- owned_test.run(5000)
  // Unit ids start at 1 and go to the joins in order (the map's doc), so
  // connection 1's player is unit 1 and connection 2's unit 2.
  let #(_, taken) = two_players(10.0)
  let watched =
    list.filter_map(support.sends(taken), fn(sent) {
      case sent.1 {
        Watched(by:, unit_id:) -> Ok(#(sent.0, by, unit_id))
        Unwatched(..)
        | Gone(..)
        | Joined(..)
        | map.NotJoined(..)
        | map.Left
        | map.Retire
        | map.Approached(..)
        | map.Withdrew(..) -> Error(Nil)
      }
    })
  assert watched == [#(1, ConnectionId(2), 2), #(2, ConnectionId(1), 1)]
    as "each is told the other's unit, which every news it sends that player names"
}

/// The end of the connection `connection`'s watch: the watch the join opened as
/// the connection's number.
fn ends(
  state state: State,
  connection connection: Int,
  elapsed_ms elapsed_ms: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state: state,
    at_ms: started_at_ms + elapsed_ms,
    event: WatchEnded(WatchId(connection)),
  )
}

// ---- who sees whom ----

pub fn a_player_joining_within_1024_units_is_told_the_other_sees_it_and_tells_the_other_the_same_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = two_players(1024.0)
  assert shape(taken) == [#(1, "Watched by 2"), #(2, "Watched by 1")]
    as "each of the pair is told the other sees it, once, in the join's one step; the map sends no unit"
}

pub fn a_pair_at_exactly_1024_units_sees_each_other_and_one_at_1024_01_does_not_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, at_the_range) = two_players(1024.0)
  assert list.length(support.sends(at_the_range)) == 2
    as "1024.0 is within the range: the decision on issue 272, at most 1024 units"
  let #(_, past) = two_players(1024.01)
  assert support.sends(past) == []
    as "1024.01 is past the range: no Watched either way"
  assert sight.sees(at(0.0), at(1024.0)) && !sight.sees(at(0.0), at(1024.01))
}

pub fn sight_is_three_dimensional_test() -> Nil {
  use <- owned_test.run(5000)
  let up =
    place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 0.0,
      y: 600.0,
      z: 900.0,
    )
  // 600 and 900 units apart on two axes is about 1081.7 units: out of sight
  // in 3D though each axis is within 1024.
  assert !sight.sees(at(0.0), up)
}

pub fn a_joined_answer_is_the_players_own_0x262_for_the_connection_to_send_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) =
    join(state: started(), connection: 1, place: at(7.0), elapsed_ms: 10)
  let assert [#(_, Joined(unit: record, ..))] = support.replies(taken)
  let first = map_support.character(101)
  assert record.unit_id == 1
  assert record.character_id == 101 && record.character_id != 0
    as "the client refuses a character id of 0 (0x140456960)"
  assert record.realm_id == realm_id
    as "the map's realm, which is not 0 (0x140456960)"
  assert record.name == first.name
  assert record.tail.item_visuals != []
    as "item visuals: without them the body is likely black (opcode.0x262.body)"
}

pub fn no_unit_id_is_0_and_none_is_given_twice_in_a_maps_life_test() -> Nil {
  use <- owned_test.run(10_000)
  // Players join, leave and rejoin; every join names a unit id of 1 or more,
  // and each join is a new one.
  let #(state, first) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, second) =
    join(state: state, connection: 2, place: at(10.0), elapsed_ms: 20)
  let #(state, _) = leave(state: state, connection: 1, elapsed_ms: 30)
  let #(_, again) =
    join(state: state, connection: 1, place: at(0.0), elapsed_ms: 40)
  let joined_ids =
    list.filter_map([first, second, again], fn(taken) {
      case support.replies(taken) {
        [#(_, Joined(unit:, ..))] -> Ok(unit.unit_id)
        _ -> Error(Nil)
      }
    })
  assert joined_ids == [1, 2, 3]
    as "unit ids start at 1, which the client needs, and a unit that left and joined again is a new one"
}

pub fn a_pair_in_sight_is_told_nothing_by_a_move_and_one_that_leaves_and_returns_is_told_unwatched_then_watched_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(state, near) =
    move(state: state, connection: 2, x: 300.0, elapsed_ms: 300)
  assert support.sends(near) == []
    as "a pair that stays in sight is told nothing by the map: the owners' connections send the moves"
  let #(state, away) =
    move(state: state, connection: 2, x: 5000.0, elapsed_ms: 400)
  assert shape(away) == [#(1, "Unwatched by 2"), #(2, "Unwatched by 1")]
    as "the pair that leaves sight is told it in one step"
  let #(_, back) = move(state: state, connection: 2, x: 200.0, elapsed_ms: 500)
  assert shape(back) == [#(1, "Watched by 2"), #(2, "Watched by 1")]
    as "the pair that returns is told it again"
}

pub fn a_move_into_sight_tells_both_players_and_one_that_stays_far_tells_none_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, joined) =
    join(state: state, connection: 2, place: at(9000.0), elapsed_ms: 20)
  assert support.sends(joined) == [] as "far apart at the join: nothing is sent"
  let #(state, still_far) =
    move(state: state, connection: 2, x: 8000.0, elapsed_ms: 25)
  assert support.sends(still_far) == []
  let #(_, near) = move(state: state, connection: 2, x: 500.0, elapsed_ms: 30)
  assert shape(near) == [#(1, "Watched by 2"), #(2, "Watched by 1")]
}

pub fn a_pair_that_crosses_sight_twice_in_one_batch_is_decided_on_the_final_place_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(9000.0), elapsed_ms: 20)
  // One Moved says only the place it ends at, so a pair that was out and ends
  // out is told nothing, whatever the player passed through.
  let #(_, taken) = move(state: state, connection: 2, x: 9100.0, elapsed_ms: 30)
  assert support.sends(taken) == []
}

// ---- leaving ----

pub fn a_leave_tells_each_player_who_saw_the_leaver_unwatched_and_none_gone_and_none_the_leaver_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 20)
  let #(state, _) =
    join(state: state, connection: 3, place: at(90_000.0), elapsed_ms: 30)
  let #(_, left) = leave(state: state, connection: 2, elapsed_ms: 40)
  assert shape(left) == [#(1, "Unwatched by 2")]
    as "the player who saw it is told its viewer 2 is gone; the leaver, who sent its viewers their 0x355 itself, and the player out of sight are sent nothing, and no Gone"
}

pub fn a_connection_ending_tells_each_player_who_saw_it_unwatched_and_gone_once_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 20)
  let #(state, _) =
    join(state: state, connection: 3, place: at(90_000.0), elapsed_ms: 30)
  let #(state, ended) = ends(state:, connection: 2, elapsed_ms: 40)
  assert list.sort(shape(ended), fn(first, second) {
      string.compare(
        int.to_string(first.0) <> first.1,
        int.to_string(second.0) <> second.1,
      )
    })
    == [#(1, "Gone 2"), #(1, "Unwatched by 2"), #(3, "Gone 2")]
    as "a connection that ended sends no 0x355, so the map says the unit is gone, to every player: the one that saw it is also told Unwatched"
  let #(_, moved) = move(state: state, connection: 1, x: 50.0, elapsed_ms: 50)
  assert support.sends(moved) == [] as "the player that ended is no longer seen"
}

pub fn a_connection_ending_tells_gone_to_every_player_in_the_map_even_one_that_no_longer_sees_it_test() -> Nil {
  use <- owned_test.run(5000)
  // A (1), V (2) and C (3) are in sight. V moves out of sight: the map drops V
  // from A's `sees` and tells both Unwatched, so A's connection never sends V
  // its 0x355 if it ends before it takes the notice (an end runs the save ask
  // first). V's client still shows A's unit, which only the map's Gone removes.
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 20)
  let #(state, _) =
    join(state: state, connection: 3, place: at(50.0), elapsed_ms: 30)
  let #(state, away) =
    move(state: state, connection: 2, x: 9000.0, elapsed_ms: 40)
  assert list.length(support.sends(away)) == 4
    as "V is out of sight of A and of C: both are told, and so is V"
  let #(_, ended) = ends(state:, connection: 1, elapsed_ms: 50)
  assert list.sort(shape(ended), fn(first, second) {
      string.compare(
        int.to_string(first.0) <> first.1,
        int.to_string(second.0) <> second.1,
      )
    })
    == [#(2, "Gone 1"), #(3, "Gone 1"), #(3, "Unwatched by 1")]
    as "C saw A, so it is told Unwatched and Gone; V no longer did, and is told Gone all the same, since A's connection cannot send V its 0x355"
}

pub fn a_second_join_resends_the_joiner_a_watched_for_each_player_it_sees_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(_, again) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 300)
  assert shape(again) == [#(2, "Watched by 1"), #(1, "Watched by 2")]
    as "the joiner is told the player it sees is its viewer, so one that lost its viewers has them again, and that player is told the joiner is its viewer, so it sends its 0x262 again, as well as the error line"
  assert support.logs_of(step: again, level: LogError) != []
}

// ---- the map's clock ----

pub fn joined_carries_the_origin_of_the_maps_clock_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, first) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 100)
  let assert [#(_, Joined(clock_origin_ms:, ..))] = support.replies(first)
  assert clock_origin_ms == started_at_ms
    as "the origin is the monotonic time the map started at, from which a connection stamps its unit's 0x262 and 0x638s"
  assert map.server_time(origin_ms: clock_origin_ms, monotonic_ms: 5000 + 250)
    == 250
    as "a connection reads the same clock from the origin"
}

pub fn a_clock_past_2_to_the_32_ms_is_written_mod_2_to_the_32_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x638's server time and 0x262's estimate start are 32 bits
  // (opcode.0x638, schema.toml); a map 2^32 ms old is 49.7 days of one map's
  // life, and its clock then counts from 0 again.
  let wrap_ms = 4_294_967_296
  assert map.server_time(origin_ms: 5000, monotonic_ms: 5000 + wrap_ms + 900)
    == 900
  assert map.server_time(origin_ms: 5000, monotonic_ms: 5000 + wrap_ms - 1)
    == wrap_ms - 1
}

// ---- failures ----

pub fn a_moved_from_a_connection_not_in_the_map_changes_nothing_and_logs_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(after, taken) =
    move(state: state, connection: 9, x: 50.0, elapsed_ms: 300)
  assert support.sends(taken) == []
  assert support.logs_of(step: taken, level: LogError) != []
    as "a connection's rule tells only while joined, so this is a bug"
  // The map is as it was: a move of a player in it still decides sight.
  let #(_, away) = move(state: after, connection: 2, x: 9000.0, elapsed_ms: 400)
  assert list.length(support.sends(away)) == 2
}

pub fn a_moved_after_the_connections_leave_is_ignored_with_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(state, _) = leave(state: state, connection: 2, elapsed_ms: 300)
  let #(_, taken) = move(state: state, connection: 2, x: 120.0, elapsed_ms: 400)
  assert support.sends(taken) == []
  assert support.logs_of(step: taken, level: LogError) != []
}
