//// The map's rule (`genesis_prime/world_map/map`), run as the pure function it
//// is: inputs in, new state and effects out. Expected values come from these
//// places.
//// - The rule's doc comment: a join is
////   answered with a unit id from 1, with the map's incarnation, and opens a
////   watch on the player's connection; a connection's end removes its player;
////   a second join answers the unit id the connection has and logs an error; a
////   watch that names no player is an error and changes nothing.
//// - The client: it refuses a 0x262 whose unit id it has already seen
////   (opcode.0x262), so no unit id is given twice in a map's life, whoever
////   leaves.

import connection_rule_support as support
import genesis_prime/step.{
  type Event, type Step, Asked, CallerId, Connection, ConnectionId, Effects,
  LogError, Reply, Started, Stop, Stopping, Watch, WatchEnded, WatchId,
}
import genesis_prime/world_map/map.{type State, Join, Joined}
import genesis_prime/world_map/map_id.{MapId}
import gleam/int
import gleam/list
import gleam/option.{Some}
import owned_test

const incarnation = 31

fn started() -> State {
  map.new(map.Settings(map: MapId(world_id: 3460, instance: 0), incarnation:))
}

fn feed(
  state: State,
  event: Event(map.Message, Nil),
) -> #(State, Step(map.Outgoing, Nil)) {
  map.step(state, support.input(event))
}

/// A join of the connection as the map's caller number `caller`.
fn join(
  state state: State,
  connection connection: Int,
  caller caller: Int,
) -> #(State, Step(map.Outgoing, Nil)) {
  feed(
    state,
    Asked(
      caller: CallerId(caller),
      message: Join(
        connection: ConnectionId(connection),
        character_id: 100 + connection,
      ),
    ),
  )
}

/// The unit id a join was answered with.
fn unit_of(taken: Step(map.Outgoing, Nil), caller: Int) -> Int {
  let assert [#(CallerId(number), Joined(unit_id:, incarnation: given))] =
    support.replies(taken)
    as "one reply answers the join"
  assert number == caller as "the reply is for the caller that joined"
  assert given == incarnation
    as "every Joined carries the map's incarnation, so the joiner watches the run that holds its player"
  unit_id
}

pub fn the_first_join_is_unit_1_with_a_watch_on_the_connection_and_the_maps_incarnation_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, taken) = join(state: started(), connection: 7, caller: 1)
  assert support.effects_of(taken)
    == [
      Watch(WatchId(1), Connection(ConnectionId(7))),
      Reply(CallerId(1), Joined(unit_id: 1, incarnation:)),
    ]
    as "the player's connection is watched, then the join is answered: unit ids start at 1"
}

pub fn started_does_nothing_and_stopping_stops_the_rule_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, taken) = feed(started(), Started)
  assert taken == Effects([]) as "a map starts empty"
  let #(_, taken) = feed(state, Stopping(deadline_ms: 9000))
  assert taken == Effects([Stop]) as "Stopping stops the rule at once"
}

pub fn each_join_gets_the_next_unit_id_and_its_own_watch_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(_, second) = join(state:, connection: 8, caller: 2)
  assert unit_of(first, 1) == 1
  assert unit_of(second, 2) == 2
  assert support.effects_of(second)
    == [
      Watch(WatchId(2), Connection(ConnectionId(8))),
      Reply(CallerId(2), Joined(unit_id: 2, incarnation:)),
    ]
    as "the watch ids go up too, so a watch is never taken for an older one"
}

pub fn a_unit_id_is_never_given_twice_across_leaves_and_rejoins_test() -> Nil {
  use <- owned_test.run(10_000)
  // Two connections join and leave in turn, ten rounds, each rejoining as the
  // same connection it was before: every join of the run is a new unit id.
  let #(_, ids) =
    int.range(from: 0, to: 10, with: #(started(), []), run: fn(held, round) {
      let #(state, ids) = held
      let #(state, joined) = join(state:, connection: 1, caller: 4 * round + 1)
      let #(state, joined_too) =
        join(state:, connection: 2, caller: 4 * round + 2)
      let first_watch = 2 * round + 1
      let #(state, _) = feed(state, WatchEnded(WatchId(first_watch)))
      let #(state, _) = feed(state, WatchEnded(WatchId(first_watch + 1)))
      #(state, [
        unit_of(joined_too, 4 * round + 2),
        unit_of(joined, 4 * round + 1),
        ..ids
      ])
    })
  assert list.reverse(ids)
    == int.range(from: 1, to: 21, with: [], run: fn(numbers, number) {
      list.append(numbers, [number])
    })
    as "opcode.0x262: the client refuses a unit id it has seen, so a connection that leaves and joins again is a new unit, and the ids are 1 to 20 with none repeated"
}

pub fn a_players_connection_ending_removes_the_player_so_its_next_join_is_a_new_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(state, ended) = feed(state, WatchEnded(WatchId(1)))
  assert ended == Effects([]) as "the player is removed; nothing is sent"
  let #(_, again) = join(state:, connection: 7, caller: 2)
  assert unit_of(first, 1) == 1
  assert unit_of(again, 2) == 2
    as "the connection that left is no longer in the map: its join is a new player, not the old unit"
  assert support.logs_of(step: again, level: LogError) == []
    as "no error: it is not a second join of a connection in the map"
}

pub fn a_second_join_from_a_connection_in_the_map_answers_its_unit_id_and_logs_an_error_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(state, second) = join(state:, connection: 7, caller: 2)
  assert unit_of(second, 2) == unit_of(first, 1)
    as "the join is answered with the unit id the connection has"
  let assert [line] = support.logs_of(step: second, level: LogError)
    as "the connection's rule joins once: a second is a bug, logged as an error"
  assert line.about
    == step.About(
      ..step.no_one,
      connection: Some(ConnectionId(7)),
      character_id: Some(107),
      map: Some(MapId(world_id: 3460, instance: 0)),
    )
    as "the line is about the connection, its character and the map, in its metadata, not in its text"
  assert support.watches(second) == [] as "no second watch is opened"
  assert list.length(support.effects_of(second)) == 2
    as "the error and the answer are all the step holds: nothing else changes"
  let #(_, third) = join(state:, connection: 8, caller: 3)
  assert unit_of(third, 3) == 2
    as "the next unit id is not spent by the second join"
}

pub fn a_watch_that_names_no_player_is_an_error_and_changes_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) = join(state: started(), connection: 7, caller: 1)
  let #(state, taken) = feed(state, WatchEnded(WatchId(9)))
  let assert [line] = support.logs_of(step: taken, level: LogError)
    as "a watch the rule never opened is a bug"
  assert line.about
    == step.About(..step.no_one, map: Some(MapId(world_id: 3460, instance: 0)))
    as "the line is about the map only: no connection or character is known"
  let #(_, second) = join(state:, connection: 7, caller: 2)
  assert unit_of(second, 2) == unit_of(first, 1)
    as "the player of connection 7 is still in the map"
}
