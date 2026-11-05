//// The static objects a map tells its players of (`genesis_prime/world_map/map`,
//// `ObjectsSeen` and `ObjectsUnseen`), run as the pure rule it is: inputs in, new
//// state and effects out. Expected values come from these places.
//// - The design of the static objects (the issue's "Design" artifact, its shape):
////   the map owns them, decides their sight with the creatures' and tells a
////   player's connection the objects it comes to see, in spawn order, in one
////   notice per decision, and the ones it stops seeing; a join answers `Joined`
////   first, then the objects, then the creatures; a leave sends nothing about them.
//// - Check 9 of the trace (`opcode.0x355`, `death.creature_respawn`): an object in
////   sight is created once, removed when it leaves sight, and created again under
////   the same unit id, since the client dropped it.
//// - Unit ids (check 10, `0x140561c30`, the map's unit id rule): one id space for
////   players, creatures and objects, never 0, never given to two units, below
////   2^20.
//// - Sight (`genesis_prime/world_map/sight`): 1024 units, 3D, inclusive.
//// - Server time (the map's clock rule): milliseconds since the map started, so
////   a join at 6000 of a map started at 5000 stamps 1000.

import connection_rule_support as support
import genesis_prime/message/unit_create_static.{type UnitCreateStatic}
import genesis_prime/step.{
  type ServiceStep, Asked, CallerId, ConnectionId, OwnEffect, OwnEvent, Reply,
  Send, Started,
}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/static_object.{type StaticObject, StaticObject}
import gleam/list
import gleam/option
import map_spawn_support as spawns
import map_support
import owned_test
import place_support
import spawn_support

/// A Holoring (Creature2 73416, a type 10 object of world 3460's start, the
/// trace's) numbered `number`, `x` units along the world's x axis.
fn holoring(number number: Int, x x: Float) -> StaticObject {
  StaticObject(
    id: SpawnId(number),
    unit_type: static_object.Simple,
    creature_id: Creature2Id(73_416),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: spawn_support.warfare_woods,
      x:,
      y: 0.0,
      z: 0.0,
    ),
    level: option.None,
    health: option.None,
    faction_id: 0,
    base_faction_id: 0,
    display_info_id: 1,
    outfit_info_id: 0,
    checklist_index: 0,
    world_object_id: 0,
    world_socket_id: 0,
  )
}

/// A map with Battle Beasts at `creatures` (spawns 1 up) and Holorings at
/// `objects` (spawns 101 up), started at `spawns.started_at_ms`.
fn started(
  creatures creatures: List(Float),
  objects objects: List(Float),
) -> State {
  let state =
    map_support.with_objects(
      incarnation: 1,
      spawns: list.index_map(creatures, fn(x, index) {
        spawn_support.battle_beast(number: index + 1, x:)
      }),
      objects: list.index_map(objects, fn(x, index) {
        holoring(number: index + 101, x:)
      }),
      kinds: spawns.default_kinds(),
    )
  let #(state, _) =
    spawns.feed(state:, at_ms: spawns.started_at_ms, event: OwnEvent(Started))
  state
}

/// What the step tells players of objects: the connection's number, then
/// `Seen` with the units or `Unseen` with the ids, in the order sent.
type ObjectNotice {
  Seen(connection: Int, units: List(UnitCreateStatic))
  Unseen(connection: Int, unit_ids: List(Int))
}

fn object_notices(taken: ServiceStep(map.Outgoing)) -> List(ObjectNotice) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      map.Noticed(notice: map.ObjectsSeen(units:), ..) ->
        Ok(Seen(sent.0, units))
      map.Noticed(notice: map.ObjectsUnseen(unit_ids:), ..) ->
        Ok(Unseen(sent.0, unit_ids))
      map.Noticed(notice: map.SeenBy(..), ..)
      | map.Noticed(notice: map.UnseenBy(..), ..)
      | map.Noticed(notice: map.Gone(..), ..)
      | map.Joined(..)
      | map.NotJoined(..)
      | map.Left
      | map.Watched(..)
      | map.Unwatched(..)
      | map.Retire
      | map.Approached(..)
      | map.Withdrew(..) -> Error(Nil)
    }
  })
}

/// The unit ids of the units, in order.
fn ids(units: List(UnitCreateStatic)) -> List(Int) {
  list.map(units, fn(unit) { unit.unit_id })
}

/// The kinds of the step's effects, in order, for the order of a join.
fn kinds_of(taken: ServiceStep(map.Outgoing)) -> List(String) {
  list.map(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Reply(answer: map.Joined(..), ..)) -> "Joined"
      OwnEffect(Send(message: map.Noticed(notice: map.ObjectsSeen(..), ..), ..)) ->
        "ObjectsSeen"
      OwnEffect(step.StartCreature(..)) -> "StartCreature"
      step.Watch(..) -> "Watch"
      OwnEffect(Reply(..))
      | OwnEffect(Send(..))
      | OwnEffect(step.StartServiceTimer(..))
      | OwnEffect(step.CancelServiceTimer(..))
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> "other"
    }
  })
}

pub fn a_join_in_sight_of_objects_answers_joined_then_tells_each_object_in_spawn_order_test() -> Nil {
  use <- owned_test.run(5000)
  // Objects 101 and 102 at 0 and 1024 are in sight of x 0; 103 at 1024.5 is not.
  let state = started(creatures: [500.0], objects: [1024.0, 0.0, 1024.5])
  let #(_, taken) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  assert kinds_of(taken) == ["Watch", "Joined", "ObjectsSeen", "StartCreature"]
    as "Joined first, then one notice of the objects, then the creature's start"
  let assert [Seen(connection: 1, units:)] = object_notices(taken)
    as "one notice of objects, to the joiner"
  assert list.map(units, fn(unit) { unit.creature_id }) == [73_416, 73_416]
  let assert [first, second] = units as "the two objects in sight"
  assert #(first.unit_id, second.unit_id) == #(2, 3)
    as "spawn order (101 then 102), each under the next id after the player's 1"
  assert first.tail.server_time_estimate_start == 1000
    && second.tail.server_time_estimate_start == 1000
    as "stamped with the map's clock: 6000 - 5000"
  let assert [start] = spawns.starts(taken) as "the creature in sight starts"
  assert { start.1 }.unit_id == 4
    as "the creature takes the id after the objects'"
}

pub fn moving_out_of_sight_unsees_the_objects_and_back_sees_them_under_the_same_ids_test() -> Nil {
  use <- owned_test.run(5000)
  let state = started(creatures: [], objects: [0.0, 100.0])
  let #(state, joined) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [Seen(1, units)] = object_notices(joined)
    as "both seen at the join"
  let given = ids(units)
  let #(state, away) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: spawns.far)
  assert object_notices(away) == [Unseen(1, given)]
    as "out of sight: the same ids, unseen, in one notice"
  let #(_, back) = spawns.move(state:, at_ms: 9000, connection: 1, x: 50.0)
  let assert [Seen(1, again)] = object_notices(back)
    as "back in sight: one notice"
  assert ids(again) == given
    as "the same unit ids: the client dropped them with the 0x355"
  assert list.all(again, fn(unit) {
    unit.tail.server_time_estimate_start == 4000
  })
    as "stamped at the move: 9000 - 5000"
}

pub fn objects_creatures_and_players_share_one_id_space_test() -> Nil {
  use <- owned_test.run(5000)
  let state = started(creatures: [10.0, 20.0], objects: [0.0, 30.0, 2000.0])
  let #(state, first) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(state, away) =
    spawns.move(state:, at_ms: 7000, connection: 1, x: 2000.0)
  let #(_, second) = spawns.join(state:, at_ms: 8000, connection: 2, x: 0.0)
  let players =
    list.flat_map([first, second], fn(taken) {
      list.filter_map(support.replies(taken), fn(reply) {
        case reply.1 {
          map.Joined(unit:, ..) -> Ok(unit.unit_id)
          map.NotJoined(..)
          | map.Left
          | map.Noticed(..)
          | map.Watched(..)
          | map.Unwatched(..)
          | map.Retire
          | map.Approached(..)
          | map.Withdrew(..) -> Error(Nil)
        }
      })
    })
  let creatures =
    list.flat_map([first, away, second], fn(taken) {
      list.map(spawns.starts(taken), fn(start) { { start.1 }.unit_id })
    })
  let objects =
    list.flat_map([first, away, second], fn(taken) {
      list.flat_map(object_notices(taken), fn(notice) {
        case notice {
          Seen(units:, ..) -> ids(units)
          Unseen(..) -> []
        }
      })
    })
    |> list.unique
  let every = list.flatten([players, creatures, objects])
  assert list.length(players) == 2
    && list.length(creatures) == 2
    && list.length(objects) == 3
    as "two players, two creatures and three objects were given ids"
  assert list.length(list.unique(every)) == list.length(every)
    as "no id is given to two units"
  assert list.all(every, fn(unit_id) { unit_id > 0 && unit_id < 1_048_576 })
    as "each id is above 0 and below 2^20"
}

pub fn two_players_see_one_object_under_one_id_and_one_leaving_tells_the_other_nothing_test() -> Nil {
  use <- owned_test.run(5000)
  let state = started(creatures: [], objects: [0.0])
  let #(state, first) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(state, second) =
    spawns.join(state:, at_ms: 6500, connection: 2, x: 10.0)
  let assert [Seen(1, [seen_by_first])] = object_notices(first)
  let assert [Seen(2, [seen_by_second])] = object_notices(second)
  assert seen_by_first.unit_id == seen_by_second.unit_id
    as "one object is one unit, whoever sees it"
  let #(_, left) = spawns.leave(state:, at_ms: 7000, connection: 1)
  assert object_notices(left) == []
    as "the other player still sees the object: nothing is sent about it"
}

pub fn a_leave_sends_nothing_about_objects_and_a_join_again_sees_them_under_the_same_ids_test() -> Nil {
  use <- owned_test.run(5000)
  let state = started(creatures: [], objects: [0.0, 5.0])
  let #(state, joined) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [Seen(1, units)] = object_notices(joined)
  let #(state, left) = spawns.leave(state:, at_ms: 7000, connection: 1)
  assert object_notices(left) == []
    as "the client leaves the world, and with it every unit: nothing is sent"
  let #(_, again) =
    spawns.feed(
      state:,
      at_ms: 8000,
      event: OwnEvent(Asked(
        caller: CallerId(1),
        message: map.Join(
          connection: ConnectionId(1),
          character: map_support.character(101),
          place: spawns.at(0.0),
          stay: map_support.stay(count: 2),
        ),
      )),
    )
  let assert [Seen(1, units_again)] = object_notices(again)
    as "the join again sees the objects"
  assert ids(units_again) == ids(units)
    as "under the same ids: each object keeps its id for the run"
}

pub fn a_move_that_changes_no_objects_sight_sends_no_object_notice_test() -> Nil {
  use <- owned_test.run(5000)
  // The failure table: a move is decided on the place it ends at, so an object
  // in sight before and after it is told nothing.
  let state = started(creatures: [], objects: [0.0, 5000.0])
  let #(state, _) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let #(_, moved) = spawns.move(state:, at_ms: 7000, connection: 1, x: 500.0)
  assert object_notices(moved) == []
    as "object 101 stays in sight and 102 out of it"
}
