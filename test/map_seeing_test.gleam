//// Who sees whom in a map (`genesis_prime/world_map/map`, `sight`), run as the
//// pure rule it is: inputs in, new state and effects out. Expected values come
//// from these places.
//// - The sight range: 1024 units, 3D, at most (the decision on issue 272, from
////   `unit.range`: the client removes no unit by distance and draws out to
////   lod.viewDistance, 256 to 1024). A pair at exactly 1024.0 sees; 1024.01
////   does not.
//// - The 0x262 a seen player is built as: the player's own 0x262
////   (opcode.0x262.other_player, opcode.0x262.player_fields): type 20, the
////   player's own unit id, a character id and realm that are not 0 (the client
////   refuses 0, 0x140456960), name, race, class and gender, stat 0 above 0
////   (without it the unit is created dead, 0x140457bc5), property 7, both
////   factions, a kind 2 at the unit's current place with its bit clear and a
////   kind 14.
//// - Unit ids: never 0 (a 0x262 with unit id 0 becomes the controlled unit,
////   0x1403d9760) and never given twice (the client does nothing for a unit it
////   has, 0x1403d9760).
//// - A unit comes back into sight as 0x355 then 0x262 (0x1403d9590,
////   0x1403d9760).
//// - The design of issue 272 (the map's doc comment): the map decides sight and
////   sends no move; with each `Seen` of a unit it sends that unit's connection a
////   `Watched`, and with each `Unseen` an `Unwatched`, in the same step.
//// - The map's clock: milliseconds since the map started, the monotonic time of
////   the input minus the monotonic time of `Started`, taken mod 2^32 because the
////   client's fields hold 32 bits (the doc comment of `map.server_time`);
////   `Joined` carries the origin.

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/float32
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId, ConnectionId,
  LogError, OwnEvent, Started, Told, WatchEnded, WatchId,
}
import genesis_prime/world_map/map.{
  type State, Join, Joined, Leave, Moved, Seen, Unseen, Unwatched, Watched,
}
import genesis_prime/world_map/sight
import gleam/int
import gleam/list
import gleam/result
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
      Told(message: Moved(connection: ConnectionId(connection), place: at(x))),
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

/// The units a step puts in sight or takes out of it: its sends of `Seen` and
/// `Unseen`, in order, with the connection each goes to.
fn units(taken: ServiceStep(map.Outgoing)) -> List(#(Int, map.Outgoing)) {
  list.filter(support.sends(taken), fn(sent) {
    case sent.1 {
      Seen(..) | Unseen(..) -> True
      Watched(..) | Unwatched(..) | Joined(..) | map.Left -> False
    }
  })
}

/// The viewers a step announces: its sends of `Watched` and `Unwatched`, in
/// order, with the connection each goes to.
fn notices(taken: ServiceStep(map.Outgoing)) -> List(#(Int, map.Outgoing)) {
  list.filter(support.sends(taken), fn(sent) {
    case sent.1 {
      Watched(..) | Unwatched(..) -> True
      Seen(..) | Unseen(..) | Joined(..) | map.Left -> False
    }
  })
}

/// The unit id a send of a unit says.
fn unit_id_of(message: map.Outgoing) -> Int {
  case message {
    Seen(unit:) -> unit.unit_id
    Unseen(unit_id:) -> unit_id
    Joined(unit:, ..) -> unit.unit_id
    Watched(..) | Unwatched(..) | map.Left -> 0
  }
}

/// Each send of a step as the connection it goes to and what it says, with
/// the unit ids and viewers by number: `Seen 1`, `Unseen 2`, `Watched by 2`.
fn shape(taken: ServiceStep(map.Outgoing)) -> List(#(Int, String)) {
  list.map(support.sends(taken), fn(sent) {
    #(sent.0, case sent.1 {
      Seen(unit:) -> "Seen " <> int.to_string(unit.unit_id)
      Unseen(unit_id:) -> "Unseen " <> int.to_string(unit_id)
      Watched(by: ConnectionId(number)) ->
        "Watched by " <> int.to_string(number)
      Unwatched(by: ConnectionId(number)) ->
        "Unwatched by " <> int.to_string(number)
      Joined(..) | map.Left -> "an answer"
    })
  })
}

/// A map with connections 1 and 2 joined at x 0 and `x`.
fn two_players(x: Float) -> #(State, ServiceStep(map.Outgoing)) {
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 100)
  join(state: state, connection: 2, place: at(x), elapsed_ms: 200)
}

// ---- who sees whom ----

pub fn a_player_joining_within_1024_units_is_seen_by_the_other_and_sees_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = two_players(1024.0)
  let assert [#(2, Seen(unit: of_first)), #(1, Seen(unit: of_second))] =
    units(taken)
    as "the joiner is sent one Seen of the player in sight, and that player one of the joiner, each once"
  assert of_first.unit_id == 1 && of_second.unit_id == 2
    as "each Seen names the other's own unit id"
}

pub fn a_pair_at_exactly_1024_units_sees_each_other_and_one_at_1024_01_does_not_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, at_the_range) = two_players(1024.0)
  assert list.length(units(at_the_range)) == 2
    as "1024.0 is within the range: the decision on issue 272, at most 1024 units"
  let #(_, past) = two_players(1024.01)
  assert support.sends(past) == []
    as "1024.01 is past the range: no Seen and no Watched either way"
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

pub fn a_seen_record_is_the_players_own_0x262_at_its_current_place_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = two_players(100.0)
  let assert [#(2, Seen(unit: record)), ..] = units(taken)
  let first = map_support.character(101)
  assert record.unit_id == 1
  assert record.character_id == 101 && record.character_id != 0
    as "the client refuses a character id of 0 (0x140456960)"
  assert record.realm_id == realm_id
    as "the map's realm, which is not 0 (0x140456960)"
  assert record.name == first.name
  assert record.race_id == first.race_id.value
    && record.class_id == first.class_id.value
    && record.gender == first.gender
  assert record.faction_id == first.faction_id
    && record.base_faction_id == first.faction_id
    as "both factions: without a base faction the unit has none (0x14045ac60)"
  let assert Ok(health) =
    list.find(record.stats, fn(stat) { stat.stat_id == 0 })
    as "stat 0: without it the client creates the unit dead (0x140457bc5)"
  assert health.value > 0
  assert list.any(record.properties, fn(property) { property.property_id == 7 })
    as "property 7, Base Health, which the client reads for the maximum health (0x1404584b0)"
  assert record.item_visuals != []
    as "item visuals: without them the body is likely black (opcode.0x262.body)"
  let assert [
    start_movement.Position(UnitPositionCommand(x:, blends: 0, ..)),
    start_movement.Rotation(_),
  ] = record.movement_commands
    as "a kind 2 with its bit clear, which places the unit at once, then a kind 14 (0x140714120)"
  assert x == float32.to_bits(0.0)
    as "the place the unit stands at, here the first player's join place"
  assert unit_create_player.encode(record) |> result.is_ok
    as "the record encodes as the client's reader takes it"
}

pub fn a_seen_record_names_the_place_the_unit_has_moved_to_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(state, _) = move(state: state, connection: 1, x: 500.0, elapsed_ms: 300)
  let #(_, joined) =
    join(state: state, connection: 3, place: at(450.0), elapsed_ms: 400)
  let assert [#(3, Seen(unit: record)), ..] = units(joined)
    as "the joiner is sent the first player first (the connections go in order)"
  let assert [start_movement.Position(UnitPositionCommand(x:, ..)), ..] =
    record.movement_commands
  assert x == float32.to_bits(500.0)
    as "the unit stands where its last move put it, not where it joined"
}

pub fn no_unit_id_is_0_and_none_is_given_twice_in_a_maps_life_test() -> Nil {
  use <- owned_test.run(10_000)
  // Players join, leave and rejoin; every Seen and every join names a unit id
  // of 1 or more, and each join is a new one.
  let #(state, first) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, second) =
    join(state: state, connection: 2, place: at(10.0), elapsed_ms: 20)
  let #(state, left) = leave(state: state, connection: 1, elapsed_ms: 30)
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
  let named =
    list.flat_map([first, second, left, again], fn(taken) {
      list.map(units(taken), fn(sent) { unit_id_of(sent.1) })
    })
  assert list.all(named, fn(id) { id >= 1 })
    as "no Seen or Unseen names a unit id 0"
}

pub fn a_pair_in_sight_gets_no_second_seen_and_one_that_leaves_and_returns_gets_unseen_then_seen_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(state, near) =
    move(state: state, connection: 2, x: 300.0, elapsed_ms: 300)
  assert support.sends(near) == []
    as "a pair that stays in sight is told nothing by the map: the mover's connection sends the moves"
  let #(state, away) =
    move(state: state, connection: 2, x: 5000.0, elapsed_ms: 400)
  assert units(away) == [#(2, Unseen(unit_id: 1)), #(1, Unseen(unit_id: 2))]
    as "the pair that leaves sight is sent Unseen both ways"
  let #(_, back) = move(state: state, connection: 2, x: 200.0, elapsed_ms: 500)
  let assert [#(2, Seen(unit: of_other)), #(1, Seen(unit: of_mover))] =
    units(back)
    as "the pair that returns is sent Seen both ways"
  assert of_mover.unit_id == 2 && of_other.unit_id == 1
}

// ---- who is watched ----

pub fn each_seen_of_a_join_is_sent_with_a_watched_to_the_seen_players_connection_in_the_same_step_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = two_players(100.0)
  assert shape(taken)
    == [
      #(2, "Seen 1"),
      #(1, "Watched by 2"),
      #(1, "Seen 2"),
      #(2, "Watched by 1"),
    ]
    as "player 1 is seen by the joiner, so it is told its viewer is 2; the joiner is seen by player 1, so it is told its viewer is 1: all four in the join's one step"
}

pub fn each_unseen_of_a_move_out_of_sight_is_sent_with_an_unwatched_in_the_same_step_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(_, away) = move(state: state, connection: 2, x: 5000.0, elapsed_ms: 300)
  assert shape(away)
    == [
      #(2, "Unseen 1"),
      #(1, "Unwatched by 2"),
      #(1, "Unseen 2"),
      #(2, "Unwatched by 1"),
    ]
    as "each player is told its unit is gone from the other's sight and the other is no longer its viewer, in one step"
}

pub fn a_move_into_sight_sends_seen_and_watched_both_ways_in_one_step_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, joined) =
    join(state: state, connection: 2, place: at(9000.0), elapsed_ms: 20)
  assert support.sends(joined) == [] as "far apart at the join: nothing is sent"
  let #(_, near) = move(state: state, connection: 2, x: 500.0, elapsed_ms: 30)
  assert notices(near)
    == [#(1, Watched(by: ConnectionId(2))), #(2, Watched(by: ConnectionId(1)))]
  assert list.length(units(near)) == 2
  assert list.length(support.sends(near)) == 4
    as "into sight: Seen and Watched both ways, and no move for a pair that was out of sight"
}

pub fn a_leave_sends_an_unseen_and_an_unwatched_to_each_player_who_saw_the_leaver_and_none_to_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 20)
  let #(state, _) =
    join(state: state, connection: 3, place: at(90_000.0), elapsed_ms: 30)
  let #(_, left) = leave(state: state, connection: 2, elapsed_ms: 40)
  assert support.sends(left)
    == [#(1, Unseen(unit_id: 2)), #(1, Unwatched(by: ConnectionId(2)))]
    as "the player who saw it is sent its Unseen and told its viewer 2 is gone; the leaver and the player out of sight are sent nothing"
}

pub fn a_connection_ending_sends_the_same_notices_and_a_unit_that_was_gone_is_not_unseen_twice_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 20)
  let #(state, ended) =
    feed(state: state, at_ms: started_at_ms + 30, event: WatchEnded(WatchId(2)))
  assert support.sends(ended)
    == [#(1, Unseen(unit_id: 2)), #(1, Unwatched(by: ConnectionId(2)))]
    as "a viewer's connection that is gone is no longer anyone's viewer, so the movers stop sending to it"
  let #(_, moved) = move(state: state, connection: 1, x: 50.0, elapsed_ms: 40)
  assert support.sends(moved) == [] as "the player that ended is no longer seen"
}

pub fn a_second_join_resends_the_joiner_a_seen_and_a_watched_of_each_player_it_sees_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(_, again) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 300)
  assert list.map(units(again), fn(sent) { #(sent.0, unit_id_of(sent.1)) })
    == [#(2, 1)]
    as "the joiner is sent a Seen of the one player it sees, as well as the error line"
  assert notices(again) == [#(2, Watched(by: ConnectionId(1)))]
    as "and told that player is its viewer, so a joiner that lost its viewers has them again"
  assert support.logs_of(step: again, level: LogError) != []
}

// ---- the map's clock ----

pub fn a_units_seen_reads_the_maps_clock_and_joined_carries_its_origin_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 100)
  let assert [#(_, Joined(clock_origin_ms:, ..))] = support.replies(first)
  assert clock_origin_ms == started_at_ms
    as "the origin is the monotonic time the map started at, from which a mover's connection stamps its 0x638s"
  let #(_, joined) =
    join(state: state, connection: 2, place: at(10.0), elapsed_ms: 250)
  let assert [#(2, Seen(unit: first_seen)), ..] = units(joined)
  assert first_seen.server_time_estimate_start == 250
    as "the join came 250 ms after the map started, whatever the monotonic time"
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
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 100)
  let #(_, joined) =
    join(
      state: state,
      connection: 2,
      place: at(10.0),
      elapsed_ms: wrap_ms + 250,
    )
  let assert [#(2, Seen(unit: seen)), ..] = units(joined)
  assert seen.server_time_estimate_start == 250
    as "a Seen 2^32 + 250 ms into the map's life says 250"
  assert map.server_time(origin_ms: 5000, monotonic_ms: 5000 + wrap_ms + 900)
    == 900
    as "the clock a mover's connection reads wraps the same way"
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
  assert list.length(units(away)) == 2
}

pub fn a_moved_after_the_connections_leave_is_ignored_with_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(state, _) = leave(state: state, connection: 2, elapsed_ms: 300)
  let #(_, taken) = move(state: state, connection: 2, x: 120.0, elapsed_ms: 400)
  assert support.sends(taken) == []
  assert support.logs_of(step: taken, level: LogError) != []
}
