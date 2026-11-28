//// The address a map issues each unit of a player (`genesis_prime/world_map/map`,
//// `genesis_prime/world_map/unit_address`), run as the pure rule it is. Expected values come
//// from these places.
//// - Design 6.4 of issue 1483: an address names one join of one run of a map, so it is never
////   issued twice on a node: the run's incarnation is unique (`world_map/registry`) and the
////   map's number only grows.
//// - The review of part 3 (M3): the connection counts its stays and fences by that count, so
////   the map keeps the stay the Join named beside the address and sends every player-bound
////   message for it.
//// - A second Join of a connection that is in the map ends its first unit as a Leave ends
////   it and joins a new unit (the map's doc comment): the connection joins again only after
////   its Leave, so the map's old second-join path is gone.

import connection_rule_support as support
import genesis_prime/map/message.{Joined} as map_message
import genesis_prime/shared/strike_tell
import genesis_prime/step.{type ServiceStep, OwnEvent, Started, Told, WatchEnded}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/stay
import genesis_prime/world_map/unit_address.{type UnitAddress}
import gleam/dict
import gleam/list
import gleam/set
import map_player_support as player_support
import map_spawn_support as spawns
import map_support
import owned_test
import qcheck
import spawn_support

fn started(incarnation incarnation: Int) -> State {
  let state = map_support.empty(incarnation:)
  let #(state, _) = spawns.feed(state:, at_ms: 5000, event: OwnEvent(Started))
  state
}

/// The address the step's `Joined` answer names, when it answers one.
fn joined_address(
  taken: ServiceStep(map_message.Outgoing),
) -> Result(UnitAddress, Nil) {
  list.find_map(support.replies(taken), fn(reply) {
    case reply.1 {
      Joined(address:, ..) -> Ok(address)
      _ -> Error(Nil)
    }
  })
}

/// The watch the step opens on the joiner.
fn watch_of(
  taken: ServiceStep(map_message.Outgoing),
) -> Result(step.WatchId, Nil) {
  list.find_map(support.effects_of(taken), fn(effect) {
    case effect {
      step.Watch(watch:, ..) -> Ok(watch)
      _ -> Error(Nil)
    }
  })
}

// ---- the property ----

/// One input to a run: connection `connection` (1 to 4) joins, leaves or ends.
type Op {
  Joins(connection: Int)
  Leaves(connection: Int)
  Ends(connection: Int)
}

fn op_of(number: Int) -> Op {
  let connection = number % 4 + 1
  case number / 4 % 3 {
    0 -> Joins(connection:)
    1 -> Leaves(connection:)
    _ -> Ends(connection:)
  }
}

/// The addresses a run issues over the ops, in order, and the watch of each connection
/// that is in the map.
fn issued(ops ops: List(Op)) -> List(UnitAddress) {
  let #(_, _, addresses) =
    list.fold(ops, #(started(incarnation: 1), dict.new(), []), fn(held, op) {
      let #(state, watches, addresses) = held
      let at_ms = 6000 + list.length(addresses) * 10
      case op {
        Joins(connection:) -> {
          let #(state, taken) = spawns.join(state:, at_ms:, connection:, x: 0.0)
          let watches = case watch_of(taken) {
            Ok(watch) -> dict.insert(watches, connection, watch)
            Error(Nil) -> watches
          }
          case joined_address(taken) {
            Ok(address) -> #(state, watches, [address, ..addresses])
            Error(Nil) -> #(state, watches, addresses)
          }
        }
        Leaves(connection:) -> {
          let #(state, _) = spawns.leave(state:, at_ms:, connection:)
          #(state, dict.delete(watches, connection), addresses)
        }
        Ends(connection:) ->
          case dict.get(watches, connection) {
            Ok(watch) -> {
              let #(state, _) =
                spawns.feed(state:, at_ms:, event: WatchEnded(watch))
              #(state, dict.delete(watches, connection), addresses)
            }
            Error(Nil) -> #(state, watches, addresses)
          }
      }
    })
  list.reverse(addresses)
}

pub fn a_map_run_never_issues_one_address_twice_over_any_sequence_of_joins_leaves_and_ends_test() -> Nil {
  use <- owned_test.run(10_000)
  use numbers <- qcheck.given(qcheck.generic_list(
    qcheck.bounded_int(from: 0, to: 1000),
    qcheck.bounded_int(from: 1, to: 40),
  ))
  let addresses = issued(ops: list.map(numbers, op_of))
  assert list.length(list.unique(addresses)) == list.length(addresses)
    as "every join of the run, a second join of one connection and a join after a leave or an end included, is given an address no other join had"
  assert list.map(addresses, fn(address) { unit_address.number(address:) })
    == list.index_map(addresses, fn(_, index) { index + 1 })
    as "the addresses are the run's own, numbered from 1 in the order of the joins"
}

// ---- the rows ----

pub fn a_restarted_run_that_reuses_a_wire_unit_id_names_another_address_test() -> Nil {
  use <- owned_test.run(5000)
  let #(_, first) =
    spawns.join(
      state: started(incarnation: 1),
      at_ms: 6000,
      connection: 1,
      x: 0.0,
    )
  let #(_, second) =
    spawns.join(
      state: started(incarnation: 2),
      at_ms: 6000,
      connection: 1,
      x: 0.0,
    )
  assert spawns.joined_unit_id(first) == 1 && spawns.joined_unit_id(second) == 1
    as "both runs give the unit id 1 to their first joiner"
  assert joined_address(first)
    == Ok(map_support.address_in(incarnation: 1, number: 1))
    as "the first run's address names its incarnation"
  assert joined_address(second)
    == Ok(map_support.address_in(incarnation: 2, number: 1))
    as "the restarted run's address names its own incarnation"
  assert joined_address(first) != joined_address(second)
    as "so a message for the first run's unit names no unit of the second"
}

/// The stay of the notice sent to each connection, for each connection.
fn notice_stays(
  taken: ServiceStep(map_message.Outgoing),
) -> List(#(Int, stay.Stay)) {
  list.map(player_support.notices(taken:), fn(sent) { #(sent.0, sent.1) })
}

pub fn a_join_issues_the_next_address_and_keeps_the_connections_stay_test() -> Nil {
  use <- owned_test.run(5000)
  let #(state, first) =
    spawns.join_in_stay(
      state: started(incarnation: 1),
      at_ms: 6000,
      connection: 1,
      stay_count: 3,
      x: 0.0,
      alive: True,
      hidden: set.new(),
    )
  let #(_, second) =
    spawns.join_in_stay(
      state:,
      at_ms: 6100,
      connection: 2,
      stay_count: 5,
      x: 10.0,
      alive: True,
      hidden: set.new(),
    )
  assert joined_address(first) == Ok(map_support.address(number: 1))
    && joined_address(second) == Ok(map_support.address(number: 2))
    as "each join is answered with the next address of the run"
  assert notice_stays(second)
    == [
      #(1, map_support.stay(count: 3)),
      #(2, map_support.stay(count: 5)),
    ]
    as "the notices of the second join go to each connection for the stay its own Join named, which the address does not replace"
}

pub fn a_second_join_of_one_joiner_removes_its_first_unit_as_a_leave_does_and_joins_a_new_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
    ])
  let #(state, first) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(state, _) = spawns.join(state:, at_ms: 6100, connection: 2, x: 10.0)
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  // The map as a Leave of connection 1 leaves it, from the same state.
  let #(_, left) = spawns.leave(state:, at_ms: 6200, connection: 1)
  let #(_, again) =
    spawns.join_in_stay(
      state:,
      at_ms: 6200,
      connection: 1,
      stay_count: 2,
      x: 0.0,
      alive: True,
      hidden: set.new(),
    )
  let old = map_support.address(number: 1)
  assert joined_address(first) == Ok(old)
  assert joined_address(again)
    == Ok(map_support.address_for(incarnation: 1, number: 3, joiner: 1))
    as "the second join is a new unit under the next address of the run"
  assert spawns.joined_unit_id(again) != spawns.joined_unit_id(first)
    as "with a unit id of its own: the first unit is gone, the map keeps no unit for it"
  assert spawns.creatures_told(again)
    |> list.take(list.length(spawns.creatures_told(left)))
    == spawns.creatures_told(left)
    as "its creatures are told what a Leave tells them: Unseen and CasterGone of the old address, in the same order"
  assert list.contains(spawns.creatures_told(again), #(
    unit_id,
    life,
    "Seen by 1",
  ))
    as "and then Seen of the new address"
  assert support.logs_of(step: again, level: step.LogError) == []
    as "a join of a connection in the map is no error: the connection never sends it, and the rule is a leave and a join"
}

pub fn a_creature_relay_reaches_the_host_by_the_connection_and_the_connections_stay_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    spawns.started_with_spawns(spawns: [
      spawn_support.battle_beast(number: 1, x: 0.0),
    ])
  let #(state, _) =
    spawns.join_in_stay(
      state:,
      at_ms: 6000,
      connection: 7,
      stay_count: 4,
      x: 0.0,
      alive: True,
      hidden: set.new(),
    )
  let #(unit_id, life) = spawns.creature_of(state:, spawn: 1)
  let payload = map_message.Fight(told: strike_tell.Released(unit_id:))
  let #(_, taken) =
    spawns.feed(
      state:,
      at_ms: 7000,
      event: OwnEvent(
        Told(message: map_message.Relay(
          unit_id:,
          life:,
          to: map_support.address_for(incarnation: 1, number: 1, joiner: 7),
          payload:,
        )),
      ),
    )
  assert support.sends(taken)
    == [
      #(
        7,
        map_message.Relayed(
          stay: map_support.stay(count: 4),
          delivered: map_message.Tell(payload:),
        ),
      ),
    ]
    as "the relay to the address goes to the connection that joined it, for the stay of that join"
}
