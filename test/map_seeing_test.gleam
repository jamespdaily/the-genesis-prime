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
//// - 0x638: at most 31 commands, since its count is 5 bits (opcode.0x638,
////   vector.opcode.0x638.body), and the encoder refuses 32; a unit comes back
////   into sight as 0x355 then 0x262 (0x1403d9590, 0x1403d9760).
//// - The map's clock: milliseconds since the map started, the monotonic time of
////   the input minus the monotonic time of `Started`, one clock for a unit's
////   0x262 and its 0x638s (the doc comment of `map.server_time`).

import character_support
import character_tables
import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/float32
import genesis_prime/message/movement_mode.{MovementMode}
import genesis_prime/message/relayed_movement.{type RelayedMovement}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_movement.{UnitMovement}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/step.{
  type Event, type ServiceEvent, type ServiceStep, Asked, CallerId, Connection,
  ConnectionId, LogError, OwnEffect, OwnEvent, Send, Started, Told, WatchEnded,
  WatchId,
}
import genesis_prime/store.{type Character, Character}
import genesis_prime/world_map/map.{
  type State, Join, Joined, Leave, Moved, MovedUnit, Seen, Unseen,
}
import genesis_prime/world_map/map_id.{MapId}
import genesis_prime/world_map/sight
import gleam/int
import gleam/list
import gleam/result
import owned_test
import place_support

const realm_id = 7

/// The time the map starts at on the monotonic clock, so a server time is not
/// the monotonic time.
const started_at_ms = 5000

fn started() -> State {
  let state =
    map.new(map.Settings(
      map: MapId(world_id: 3460, instance: 0),
      incarnation: 1,
      realm_id:,
      tables: character_tables.shared(),
    ))
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

fn character(number: Int) -> Character {
  Character(
    ..character_support.character(number:),
    look: character_tables.row_10_look(),
  )
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
        character: character(100 + connection),
        place:,
      ),
    )),
  )
}

fn position(x: Float) -> RelayedMovement {
  relayed_movement.Position(UnitPositionCommand(
    x: float32.to_bits(x),
    y: float32.to_bits(0.0),
    z: float32.to_bits(0.0),
    blends: 1,
  ))
}

fn mode(number: Int) -> RelayedMovement {
  relayed_movement.Mode(MovementMode(mode: number))
}

/// A move of connection `connection` to `x`, with `commands`, `elapsed_ms`
/// after the map started: a tell.
fn move(
  state state: State,
  connection connection: Int,
  x x: Float,
  commands commands: List(RelayedMovement),
  elapsed_ms elapsed_ms: Int,
) -> #(State, ServiceStep(map.Outgoing)) {
  feed(
    state: state,
    at_ms: started_at_ms + elapsed_ms,
    event: OwnEvent(
      Told(message: Moved(
        connection: ConnectionId(connection),
        place: at(x),
        commands:,
      )),
    ),
  )
}

/// Who the step sent what, in order: the connection's number and the message.
fn sends(taken: ServiceStep(map.Outgoing)) -> List(#(Int, map.Outgoing)) {
  list.filter_map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Send(to: Connection(ConnectionId(number)), message:)) ->
        Ok(#(number, message))
      OwnEffect(_)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> Error(Nil)
    }
  })
}

/// The unit ids a step's sends say, with the connection each goes to.
fn unit_id_of(message: map.Outgoing) -> Int {
  case message {
    Seen(unit:) -> unit.unit_id
    MovedUnit(unit_id:, ..) | Unseen(unit_id:) -> unit_id
    Joined(unit:, ..) -> unit.unit_id
    map.Left -> 0
  }
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
    sends(taken)
    as "the joiner is sent one Seen of the player in sight, and that player one of the joiner, each once"
  assert of_first.unit_id == 1 && of_second.unit_id == 2
    as "each Seen names the other's own unit id"
}

pub fn a_pair_at_exactly_1024_units_sees_each_other_and_one_at_1024_01_does_not_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, at_the_range) = two_players(1024.0)
  assert list.length(sends(at_the_range)) == 2
    as "1024.0 is within the range: the decision on issue 272, at most 1024 units"
  let #(_, past) = two_players(1024.01)
  assert sends(past) == [] as "1024.01 is past the range: no Seen either way"
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
  let assert [#(2, Seen(unit: record)), ..] = sends(taken)
  let first = character(101)
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
  let #(state, _) =
    move(
      state: state,
      connection: 1,
      x: 500.0,
      commands: [position(500.0)],
      elapsed_ms: 300,
    )
  let #(_, joined) =
    join(state: state, connection: 3, place: at(450.0), elapsed_ms: 400)
  let assert [#(3, Seen(unit: record)), ..] = sends(joined)
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
  let #(state, left) =
    feed(
      state: state,
      at_ms: started_at_ms + 30,
      event: OwnEvent(Asked(CallerId(9), Leave(connection: ConnectionId(1)))),
    )
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
      list.map(sends(taken), fn(sent) { unit_id_of(sent.1) })
    })
  assert list.all(named, fn(id) { id >= 1 })
    as "no Seen or Unseen names a unit id 0"
}

pub fn a_pair_in_sight_gets_no_second_seen_and_one_that_leaves_and_returns_gets_unseen_then_seen_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(state, near) =
    move(
      state: state,
      connection: 2,
      x: 300.0,
      commands: [position(300.0)],
      elapsed_ms: 300,
    )
  assert list.all(sends(near), fn(sent) {
    case sent.1 {
      MovedUnit(..) -> True
      Seen(..) | Unseen(..) | Joined(..) | map.Left -> False
    }
  })
    as "a pair that stays in sight is sent moves, never a second Seen"
  let #(state, away) =
    move(
      state: state,
      connection: 2,
      x: 5000.0,
      commands: [position(5000.0)],
      elapsed_ms: 400,
    )
  assert sends(away)
    == [
      #(1, Unseen(unit_id: 2)),
      #(2, Unseen(unit_id: 1)),
    ]
    as "the pair that leaves sight is sent Unseen both ways, in connection order of the viewer"
  let #(_, back) =
    move(
      state: state,
      connection: 2,
      x: 200.0,
      commands: [position(200.0)],
      elapsed_ms: 500,
    )
  let assert [#(1, Seen(unit: of_mover)), #(2, Seen(unit: of_other))] =
    sends(back)
    as "the pair that returns is sent Seen both ways"
  assert of_mover.unit_id == 2 && of_other.unit_id == 1
}

// ---- moves ----

pub fn a_move_is_relayed_once_to_each_player_who_sees_the_mover_and_to_no_other_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 20)
  let #(state, _) =
    join(state: state, connection: 3, place: at(50_000.0), elapsed_ms: 30)
  let #(_, taken) =
    move(
      state: state,
      connection: 2,
      x: 150.0,
      commands: [position(150.0)],
      elapsed_ms: 40,
    )
  let assert [#(1, MovedUnit(unit_id: 2, ..))] = sends(taken)
    as "the player who sees the mover is sent one MovedUnit; the mover and the player out of sight are sent none"
  Nil
}

pub fn a_moved_unit_carries_the_commands_in_order_with_their_bits_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let commands = [mode(1), position(120.0), mode(3), position(130.0)]
  let #(_, taken) =
    move(
      state: state,
      connection: 2,
      x: 130.0,
      commands: commands,
      elapsed_ms: 300,
    )
  let assert [#(1, MovedUnit(commands: relayed, ..))] = sends(taken)
  assert relayed == commands
    as "the relayed commands in the order sent, each with its own bit (the position's bit is 1 here)"
}

pub fn a_list_of_40_commands_is_sent_as_31_and_9_in_order_and_the_encoder_refuses_32_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let commands =
    list.index_map(list.repeat(Nil, 40), fn(_, n) { position(int.to_float(n)) })
  let #(_, taken) =
    move(
      state: state,
      connection: 2,
      x: 39.0,
      commands: commands,
      elapsed_ms: 300,
    )
  let assert [
    #(1, MovedUnit(commands: first, ..)),
    #(1, MovedUnit(commands: second, ..)),
  ] = sends(taken)
    as "opcode.0x638: the count is 5 bits, so 40 commands are two messages"
  assert list.length(first) == 31 && list.length(second) == 9
  assert list.append(first, second) == commands as "in order"
  let message = fn(commands) {
    unit_movement.encode(UnitMovement(
      unit_id: 2,
      server_time: 1,
      reset_movement: 0,
      kept: 0,
      commands:,
    ))
  }
  assert result.is_ok(message(first))
  assert !result.is_ok(message(list.append(first, [position(0.0)])))
    as "32 commands do not fit the 5-bit count"
}

pub fn a_move_with_nothing_to_relay_sends_no_moved_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(_, taken) =
    move(state: state, connection: 2, x: 100.0, commands: [], elapsed_ms: 300)
  assert sends(taken) == []
    as "a 0x638 with no command carries nothing, so none is sent"
}

pub fn a_units_seen_and_moved_unit_read_the_maps_one_clock_and_it_never_goes_back_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 100)
  let #(state, joined) =
    join(state: state, connection: 2, place: at(10.0), elapsed_ms: 250)
  let assert [#(2, Seen(unit: first_seen)), _] = sends(joined)
  assert first_seen.server_time_estimate_start == 250
    as "the join came 250 ms after the map started, whatever the monotonic time"
  let #(state, moved_once) =
    move(
      state: state,
      connection: 2,
      x: 20.0,
      commands: [position(20.0)],
      elapsed_ms: 250,
    )
  let assert [#(1, MovedUnit(server_time_ms: same, ..))] = sends(moved_once)
  assert same == 250 as "the same input time reads the same clock"
  let #(_, moved_later) =
    move(
      state: state,
      connection: 2,
      x: 30.0,
      commands: [position(30.0)],
      elapsed_ms: 900,
    )
  let assert [#(1, MovedUnit(server_time_ms: later, ..))] = sends(moved_later)
  assert later == 900 && later >= same
    as "the clock only goes forward with the monotonic time"
}

pub fn a_clock_past_2_to_the_32_ms_is_written_mod_2_to_the_32_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x638's server time and 0x262's estimate start are 32 bits
  // (opcode.0x638, schema.toml); a map 2^32 ms old is 49.7 days of one map's
  // life, and its clock then counts from 0 again.
  let wrap_ms = 4_294_967_296
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 100)
  let #(state, joined) =
    join(
      state: state,
      connection: 2,
      place: at(10.0),
      elapsed_ms: wrap_ms + 250,
    )
  let assert [#(2, Seen(unit: seen)), _] = sends(joined)
  assert seen.server_time_estimate_start == 250
    as "a Seen 2^32 + 250 ms into the map's life says 250"
  let #(_, moved) =
    move(
      state: state,
      connection: 2,
      x: 20.0,
      commands: [position(20.0)],
      elapsed_ms: wrap_ms + 900,
    )
  let assert [#(1, MovedUnit(server_time_ms:, ..))] = sends(moved)
  assert server_time_ms == 900
    as "a MovedUnit 2^32 + 900 ms into the map's life says 900"
}

pub fn a_move_that_takes_a_player_out_of_sight_is_unseen_both_ways_and_into_sight_seen_both_ways_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, joined) =
    join(state: state, connection: 2, place: at(9000.0), elapsed_ms: 20)
  assert sends(joined) == [] as "far apart at the join: no Seen"
  let #(state, near) =
    move(
      state: state,
      connection: 2,
      x: 500.0,
      commands: [position(500.0)],
      elapsed_ms: 30,
    )
  let assert [#(1, Seen(unit: _)), #(2, Seen(unit: _))] = sends(near)
    as "into sight: Seen both ways, and no MovedUnit for a pair that was out of sight"
  let #(_, far) =
    move(
      state: state,
      connection: 2,
      x: 9000.0,
      commands: [position(9000.0)],
      elapsed_ms: 40,
    )
  assert sends(far) == [#(1, Unseen(unit_id: 2)), #(2, Unseen(unit_id: 1))]
    as "out of sight: Unseen both ways"
}

pub fn a_pair_that_crosses_sight_twice_in_one_batch_is_decided_on_the_final_place_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(9000.0), elapsed_ms: 20)
  // One Moved whose commands go in and out of sight and end out: at most one
  // Seen or Unseen for the pair, and here none, since it was out and ends out.
  let #(_, taken) =
    move(
      state: state,
      connection: 2,
      x: 9100.0,
      commands: [position(500.0), position(9100.0)],
      elapsed_ms: 30,
    )
  assert sends(taken) == []
    as "decided on the final place, which is out of sight as the pair was"
}

// ---- leaving ----

pub fn a_leave_sends_one_unseen_to_each_player_who_saw_the_leaver_and_none_to_it_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 20)
  let #(state, _) =
    join(state: state, connection: 3, place: at(90_000.0), elapsed_ms: 30)
  let #(_, left) =
    feed(
      state: state,
      at_ms: started_at_ms + 40,
      event: OwnEvent(Asked(CallerId(9), Leave(connection: ConnectionId(2)))),
    )
  assert sends(left) == [#(1, Unseen(unit_id: 2))]
    as "the player who saw it is sent its Unseen; the leaver and the player out of sight are sent nothing"
}

pub fn a_connection_ending_sends_the_same_unseen_and_a_unit_that_was_gone_is_not_unseen_twice_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) =
    join(state: started(), connection: 1, place: at(0.0), elapsed_ms: 10)
  let #(state, _) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 20)
  let #(state, ended) =
    feed(state: state, at_ms: started_at_ms + 30, event: WatchEnded(WatchId(2)))
  assert sends(ended) == [#(1, Unseen(unit_id: 2))]
  let #(_, moved) =
    move(
      state: state,
      connection: 1,
      x: 50.0,
      commands: [position(50.0)],
      elapsed_ms: 40,
    )
  assert sends(moved) == []
    as "the player that ended is no longer seen, so a move is relayed to no one"
}

pub fn a_second_join_resends_the_joiner_a_seen_of_each_player_it_sees_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(_, again) =
    join(state: state, connection: 2, place: at(100.0), elapsed_ms: 300)
  assert list.map(sends(again), fn(sent) { #(sent.0, unit_id_of(sent.1)) })
    == [#(2, 1)]
    as "the joiner is sent a Seen of the one player it sees, as well as the error line"
  assert support.logs_of(step: again, level: LogError) != []
}

// ---- failures ----

pub fn a_moved_from_a_connection_not_in_the_map_changes_nothing_and_logs_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(after, taken) =
    move(
      state: state,
      connection: 9,
      x: 50.0,
      commands: [position(50.0)],
      elapsed_ms: 300,
    )
  assert sends(taken) == []
  assert support.logs_of(step: taken, level: LogError) != []
    as "a connection's rule tells only while joined, so this is a bug"
  // The map is as it was: a move of a player in it is relayed as before.
  let #(_, relayed) =
    move(
      state: after,
      connection: 2,
      x: 120.0,
      commands: [position(120.0)],
      elapsed_ms: 400,
    )
  assert list.length(sends(relayed)) == 1
}

pub fn a_moved_after_the_connections_leave_is_ignored_with_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, _) = two_players(100.0)
  let #(state, _) =
    feed(
      state: state,
      at_ms: started_at_ms + 300,
      event: OwnEvent(Asked(CallerId(9), Leave(connection: ConnectionId(2)))),
    )
  let #(_, taken) =
    move(
      state: state,
      connection: 2,
      x: 120.0,
      commands: [position(120.0)],
      elapsed_ms: 400,
    )
  assert sends(taken) == []
  assert support.logs_of(step: taken, level: LogError) != []
}
