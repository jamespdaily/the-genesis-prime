//// What a map shows a player whose visibility prerequisites fail
//// (`genesis_prime/world_map/map`, `Join.hidden` and `VisibilityChanged`), run as the
//// pure rule it is: inputs in, new state and effects out. Expected values come from
//// these places.
//// - The client's Creature2 rows (`table_rows -- Creature2 73707 73619 72051`):
////   73707 (the Start Arrow) holds prerequisiteIdVisibility 41803, 73619 (the
////   hoverboard hologram) 41795 and 72051 (the other arrows) 0, shown to every
////   player.
//// - The design of issue 601 (its "Design" artifact, design C): the map holds each
////   player's hidden set, leaves a unit whose prerequisite is in it out of the
////   player's sight, and, when the set changes, shows and hides the units in the
////   player's sight with the unit ids they keep. A creature of a hidden spawn takes
////   no player into its ring.
//// - Sight (`genesis_prime/world_map/sight`): 1024 units, 3D, inclusive; the ring of
////   a hostile creature is the map's aggro range, 10 units.
//// - A Dagun is hostile to the Dominion player the map's tests join as
////   (`map_ring_test`).

import connection_rule_support as support
import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/unit_create_static.{type UnitCreateStatic}
import genesis_prime/step.{type ServiceStep, OwnEffect, OwnEvent, Reply, Started}
import genesis_prime/table/id.{type PrerequisiteId, Creature2Id, PrerequisiteId}
import genesis_prime/world_map/map.{type State}
import genesis_prime/world_map/spawn.{type Spawn, Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/spawn_source
import genesis_prime/world_map/static_object.{
  type StaticObject, CreatedWithChecklist, StaticObject,
}
import gleam/list
import gleam/option.{Some}
import gleam/set
import map_spawn_support as spawns
import map_support
import owned_test
import place_support
import spawn_support

/// Creature2.prerequisiteIdVisibility of the Start Arrow (73707): quest 10527 or 10532
/// has its objective 3 open.
const start_arrow_prerequisite = 41_803

/// Creature2.prerequisiteIdVisibility of the hoverboard hologram (73619).
const hologram_prerequisite = 41_795

fn prerequisite(number: Int) -> PrerequisiteId {
  PrerequisiteId(number)
}

fn hidden(numbers: List(Int)) -> set.Set(PrerequisiteId) {
  set.from_list(list.map(numbers, prerequisite))
}

fn place_at(x: Float) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: spawn_support.warfare_woods,
    x:,
    y: 0.0,
    z: 0.0,
  )
}

/// A static object of this creature standing at `x`, shown or hidden by its
/// prerequisite.
fn object(
  number number: Int,
  creature creature: Int,
  visibility visibility: option.Option(PrerequisiteId),
  x x: Float,
) -> StaticObject {
  StaticObject(
    ..spawn_support.holoring(number:, place: place_at(x)),
    creature_id: Creature2Id(creature),
    visibility:,
  )
}

/// A Start Arrow (Creature2 73707) at `x`.
fn arrow(number number: Int, x x: Float) -> StaticObject {
  object(
    number:,
    creature: 73_707,
    visibility: Some(prerequisite(start_arrow_prerequisite)),
    x:,
  )
}

/// A hoverboard hologram (Creature2 73619) at `x`.
fn hologram(number number: Int, x x: Float) -> StaticObject {
  object(
    number:,
    creature: 73_619,
    visibility: Some(prerequisite(hologram_prerequisite)),
    x:,
  )
}

/// One of the arrows with no prerequisite (Creature2 72051) at `x`.
fn plain(number number: Int, x x: Float) -> StaticObject {
  object(number:, creature: 72_051, visibility: option.None, x:)
}

/// A Battle Beast whose creature's visibility prerequisite is the Start Arrow's.
fn hidden_beast(number number: Int, x x: Float) -> Spawn {
  Spawn(
    ..spawn_support.battle_beast(number:, x:),
    visibility: Some(prerequisite(start_arrow_prerequisite)),
  )
}

/// A Dagun, hostile to the Dominion, whose visibility prerequisite is the Start
/// Arrow's.
fn hidden_dagun(number number: Int, x x: Float) -> Spawn {
  Spawn(
    ..spawn_support.dagun(number:, x:),
    visibility: Some(prerequisite(start_arrow_prerequisite)),
  )
}

/// A map with these creature spawns and static objects, started.
fn started(
  creatures creatures: List(Spawn),
  objects objects: List(StaticObject),
) -> State {
  let state =
    map_support.with_objects(
      incarnation: 1,
      spawns: creatures,
      objects:,
      kinds: spawns.default_kinds(),
    )
  let #(state, _) =
    spawns.feed(state:, at_ms: spawns.started_at_ms, event: OwnEvent(Started))
  state
}

/// What the step tells players of objects: the connection's number, then the
/// creature ids and the unit ids of the units sent (`Seen`) or the unit ids removed
/// (`Unseen`).
type ObjectNotice {
  Seen(connection: Int, creatures: List(Int), unit_ids: List(Int))
  Unseen(connection: Int, unit_ids: List(Int))
}

fn holoring_message(created: static_object.Created) -> UnitCreateStatic {
  let assert CreatedWithChecklist(message) = created
    as "a Holoring-made object is type 10: its 0x262 is the checklist kind"
  message
}

fn object_notices(taken: ServiceStep(map.Outgoing)) -> List(ObjectNotice) {
  list.filter_map(support.sends(taken), fn(sent) {
    case sent.1 {
      map.Noticed(notice: map.ObjectsSeen(units:), ..) ->
        Ok(Seen(
          sent.0,
          list.map(units, fn(unit) { holoring_message(unit).creature_id }),
          list.map(units, fn(unit) { holoring_message(unit).unit_id }),
        ))
      map.Noticed(notice: map.ObjectsUnseen(unit_ids:), ..) ->
        Ok(Unseen(sent.0, unit_ids))
      map.Noticed(notice: map.SeenBy(..), ..)
      | map.Noticed(notice: map.UnseenBy(..), ..)
      | map.Noticed(notice: map.Gone(..), ..)
      | map.Joined(..)
      | map.NotJoined(..)
      | map.Left
      | map.Summoned(..)
      | map.NotSummoned(..)
      | map.Watched(..)
      | map.Unwatched(..)
      | map.Retire
      | map.Approached(..)
      | map.Withdrew(..)
      | map.PlayerDied(..) -> Error(Nil)
    }
  })
}

/// The creature ids of what the step sends each connection as `ObjectsSeen`.
fn seen_creatures(taken: ServiceStep(map.Outgoing)) -> List(#(Int, List(Int))) {
  list.filter_map(object_notices(taken), fn(notice) {
    case notice {
      Seen(connection:, creatures:, ..) -> Ok(#(connection, creatures))
      Unseen(..) -> Error(Nil)
    }
  })
}

/// The unit ids the step's `ObjectsSeen` gives, in order.
fn seen_unit_ids(taken: ServiceStep(map.Outgoing)) -> List(Int) {
  list.flat_map(object_notices(taken), fn(notice) {
    case notice {
      Seen(unit_ids:, ..) -> unit_ids
      Unseen(..) -> []
    }
  })
}

/// The unit ids of what the step sends each connection as `ObjectsUnseen`.
fn unseen_ids(taken: ServiceStep(map.Outgoing)) -> List(#(Int, List(Int))) {
  list.filter_map(object_notices(taken), fn(notice) {
    case notice {
      Unseen(connection:, unit_ids:) -> Ok(#(connection, unit_ids))
      Seen(..) -> Error(Nil)
    }
  })
}

/// The spawns the step starts a creature at, in order.
fn started_spawns(
  taken: ServiceStep(map.Outgoing),
) -> List(spawn_source.SpawnSource) {
  list.map(spawns.starts(taken), fn(start) { { start.1 }.spawn })
}

/// The number of log lines the step writes.
fn logged(taken: ServiceStep(map.Outgoing)) -> Int {
  list.count(support.effects_of(taken), fn(effect) {
    case effect {
      step.Log(..) -> True
      OwnEffect(..) | step.Watch(..) | step.Unwatch(..) | step.Stop -> False
    }
  })
}

/// Whether the step answers a join.
fn answers_the_join(taken: ServiceStep(map.Outgoing)) -> Bool {
  list.any(support.effects_of(taken), fn(effect) {
    case effect {
      OwnEffect(Reply(answer: map.Joined(..), ..)) -> True
      OwnEffect(..)
      | step.Watch(..)
      | step.Unwatch(..)
      | step.Log(..)
      | step.Stop -> False
    }
  })
}

pub fn a_join_with_a_hidden_prerequisite_leaves_its_objects_and_creatures_out_of_sight_test() -> Nil {
  use <- owned_test.run(5000)
  // Four objects and two creatures, all in sight of x 0: the two arrows (41803), the
  // hologram (41795) and an arrow of no prerequisite, and a beast of the Start
  // Arrow's prerequisite and a plain one.
  let state =
    started(
      creatures: [
        hidden_beast(number: 1, x: 5.0),
        spawn_support.battle_beast(number: 2, x: 6.0),
      ],
      objects: [
        arrow(number: 101, x: 0.0),
        arrow(number: 102, x: 10.0),
        hologram(number: 103, x: 20.0),
        plain(number: 104, x: 30.0),
      ],
    )
  let #(_, shown) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  assert seen_creatures(shown) == [#(1, [73_707, 73_707, 73_619, 72_051])]
    as "a player for whom nothing fails sees every object, in spawn order"
  assert started_spawns(shown)
    == [
      spawn_source.Stored(SpawnId(1)),
      spawn_source.Stored(SpawnId(2)),
    ]
    as "and every creature starts"
  let #(_, without_arrows) =
    spawns.join_hiding(
      state:,
      at_ms: 6000,
      connection: 1,
      x: 0.0,
      alive: True,
      hidden: hidden([start_arrow_prerequisite]),
    )
  assert seen_creatures(without_arrows) == [#(1, [73_619, 72_051])]
    as "with 41803 failing the two arrows are not sent: the hologram and the plain arrow are"
  assert started_spawns(without_arrows) == [spawn_source.Stored(SpawnId(2))]
    as "and the creature of that prerequisite is not started"
  let #(_, without_both) =
    spawns.join_hiding(
      state:,
      at_ms: 6000,
      connection: 1,
      x: 0.0,
      alive: True,
      hidden: hidden([start_arrow_prerequisite, hologram_prerequisite]),
    )
  assert seen_creatures(without_both) == [#(1, [72_051])]
    as "with 41795 failing as well the hologram goes too: only a unit with no prerequisite is shown"
  let #(_, unrelated) =
    spawns.join_hiding(
      state:,
      at_ms: 6000,
      connection: 1,
      x: 0.0,
      alive: True,
      hidden: hidden([19]),
    )
  assert seen_creatures(unrelated) == seen_creatures(shown)
    as "a failing prerequisite that no unit here names hides nothing"
}

pub fn visibility_changed_shows_and_hides_the_units_in_sight_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started(creatures: [hidden_beast(number: 1, x: 5.0)], objects: [
      arrow(number: 101, x: 0.0),
      arrow(number: 102, x: 10.0),
      arrow(number: 103, x: 5000.0),
    ])
  // Connection 2 sees everything, so the creature is live; connection 1 stands at
  // the same place with the Start Arrow's prerequisite failing.
  let #(state, second) = spawns.join(state:, at_ms: 6000, connection: 2, x: 0.0)
  let assert [start] = spawns.starts(second)
    as "the creature starts for connection 2"
  let creature = { start.1 }.unit_id
  let #(state, first) =
    spawns.join_hiding(
      state:,
      at_ms: 6100,
      connection: 1,
      x: 0.0,
      alive: True,
      hidden: hidden([start_arrow_prerequisite]),
    )
  assert object_notices(first) == []
    as "connection 1 is sent no arrow at its join"
  assert spawns.creature_sends(first) == []
    as "and its creature is not told of it"
  let #(state, shown) =
    spawns.visibility_changed(
      state:,
      at_ms: 7000,
      connection: 1,
      hidden: set.new(),
    )
  assert seen_creatures(shown) == [#(1, [73_707, 73_707])]
    as "the prerequisite passing sends the two arrows in sight, not the one out of sight"
  assert spawns.creature_sends(shown) == [#(creature, "Watched by 1")]
    as "and tells the live creature it is watched"
  assert spawns.starts(shown) == [] as "no second creature starts"
  let given = seen_unit_ids(shown)
  let #(state, hid) =
    spawns.visibility_changed(
      state:,
      at_ms: 8000,
      connection: 1,
      hidden: hidden([start_arrow_prerequisite]),
    )
  assert unseen_ids(hid) == [#(1, given)]
    as "the prerequisite failing again removes the same unit ids"
  assert spawns.creature_sends(hid) == [#(creature, "Unwatched by 1")]
    as "and tells the creature it is no longer watched"
  let #(_, again) =
    spawns.visibility_changed(
      state:,
      at_ms: 9000,
      connection: 1,
      hidden: set.new(),
    )
  assert seen_unit_ids(again) == given
    as "shown once more, the arrows are sent under the ids they had"
  // A creature no one else sees is started for the player it is shown to.
  let alone = started(creatures: [hidden_beast(number: 1, x: 5.0)], objects: [])
  let #(alone, _) =
    spawns.join_hiding(
      state: alone,
      at_ms: 6000,
      connection: 1,
      x: 0.0,
      alive: True,
      hidden: hidden([start_arrow_prerequisite]),
    )
  let #(_, dormant) =
    spawns.visibility_changed(
      state: alone,
      at_ms: 7000,
      connection: 1,
      hidden: set.new(),
    )
  assert started_spawns(dormant) == [spawn_source.Stored(SpawnId(1))]
    as "a dormant spawn shown to a player starts a creature for it"
  // Out of sight: nothing is sent either way.
  let far =
    started(creatures: [hidden_beast(number: 1, x: 5.0)], objects: [
      arrow(number: 101, x: 0.0),
    ])
  let #(far, _) =
    spawns.join_hiding(
      state: far,
      at_ms: 6000,
      connection: 1,
      x: spawns.far,
      alive: True,
      hidden: hidden([start_arrow_prerequisite]),
    )
  let #(_, out_of_range) =
    spawns.visibility_changed(
      state: far,
      at_ms: 7000,
      connection: 1,
      hidden: set.new(),
    )
  assert support.effects_of(out_of_range) == []
    as "units out of sight are neither sent nor started"
}

pub fn a_hidden_hostile_spawn_takes_no_player_into_its_ring_test() -> Nil {
  use <- owned_test.run(5000)
  // A Dagun at x 100 whose prerequisite fails for connection 1. Connection 2 at 80
  // sees it, which makes it live; connection 1 stands 8 from it, inside the 10-unit ring.
  let state =
    started(creatures: [hidden_dagun(number: 1, x: 100.0)], objects: [])
  let #(state, second) =
    spawns.join(state:, at_ms: 6000, connection: 2, x: 80.0)
  let assert [start] = spawns.starts(second)
    as "the Dagun starts for connection 2"
  let creature = { start.1 }.unit_id
  let #(state, _) =
    spawns.join_hiding(
      state:,
      at_ms: 6100,
      connection: 1,
      x: 92.0,
      alive: True,
      hidden: hidden([start_arrow_prerequisite]),
    )
  let #(state, ready) = spawns.ready(state:, at_ms: 6200, connection: 1)
  assert spawns.ring_sends(ready) == []
    as "a hidden Dagun's ring holds no one: the ready player gets no Approached"
  let #(state, inside) =
    spawns.move(state:, at_ms: 6300, connection: 1, x: 95.0)
  assert spawns.creature_sends(inside) == []
    as "a move inside the hidden Dagun's ring sends it nothing"
  let #(state, shown) =
    spawns.visibility_changed(
      state:,
      at_ms: 7000,
      connection: 1,
      hidden: set.new(),
    )
  assert spawns.creature_sends(shown)
    == [#(creature, "Watched by 1"), #(creature, "Approached by 1")]
    as "shown while standing inside the ring: it is watched, then the player is approached"
  let #(_, hid) =
    spawns.visibility_changed(
      state:,
      at_ms: 8000,
      connection: 1,
      hidden: hidden([start_arrow_prerequisite]),
    )
  assert spawns.creature_sends(hid)
    == [#(creature, "Unwatched by 1"), #(creature, "Withdrew by 1")]
    as "hidden again in the middle of the ring: unwatched, then withdrawn, as when a player leaves its sight"
}

pub fn a_late_or_unchanged_visibility_changed_gives_no_effect_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started(creatures: [hidden_beast(number: 1, x: 5.0)], objects: [
      arrow(number: 101, x: 0.0),
    ])
  let #(state, _) =
    spawns.join_hiding(
      state:,
      at_ms: 6000,
      connection: 1,
      x: 0.0,
      alive: True,
      hidden: hidden([start_arrow_prerequisite]),
    )
  let #(state, equal) =
    spawns.visibility_changed(
      state:,
      at_ms: 7000,
      connection: 1,
      hidden: hidden([start_arrow_prerequisite]),
    )
  assert support.effects_of(equal) == []
    as "the set the map already holds changes nothing and writes nothing"
  let #(state, unknown) =
    spawns.visibility_changed(
      state:,
      at_ms: 7100,
      connection: 5,
      hidden: set.new(),
    )
  assert spawns.sends(unknown) == [] && spawns.starts(unknown) == []
    as "a connection never in the map is sent nothing and starts nothing"
  assert logged(unknown) == 1 as "and is one error line"
  let #(state, _) = spawns.leave(state:, at_ms: 7200, connection: 1)
  let #(_, late) =
    spawns.visibility_changed(
      state:,
      at_ms: 7300,
      connection: 1,
      hidden: set.new(),
    )
  assert spawns.sends(late) == [] && spawns.starts(late) == []
    as "a tell that arrives after the player's leave is dropped"
  assert logged(late) == 1 as "with one error line, as a late Moved is"
}

pub fn a_second_join_with_a_newly_hidden_unit_removes_it_and_replays_the_rest_test() -> Nil {
  use <- owned_test.run(5000)
  let state =
    started(creatures: [hidden_beast(number: 1, x: 5.0)], objects: [
      arrow(number: 101, x: 0.0),
      plain(number: 102, x: 10.0),
    ])
  let #(state, first) = spawns.join(state:, at_ms: 6000, connection: 1, x: 0.0)
  let assert [start] = spawns.starts(first)
    as "the creature starts for the first join"
  let creature = { start.1 }.unit_id
  assert seen_creatures(first) == [#(1, [73_707, 72_051])]
    as "the first join sees both objects"
  let assert [arrow_unit_id, _] = seen_unit_ids(first)
    as "each object has its own unit id"
  // The same connection joins again, now with the Start Arrow's prerequisite failing.
  let #(state, again) =
    spawns.join_hiding(
      state:,
      at_ms: 7000,
      connection: 1,
      x: 0.0,
      alive: True,
      hidden: hidden([start_arrow_prerequisite]),
    )
  assert answers_the_join(again) as "the second join is answered"
  assert seen_creatures(again) == [#(1, [72_051])]
    as "the replay writes only the object still shown: the arrow, newly hidden, gets no create"
  assert unseen_ids(again) == [#(1, [arrow_unit_id])]
    as "and one ObjectsUnseen removes the arrow the first join showed, under the unit id it was shown with"
  assert spawns.creature_sends(again) == [#(creature, "Unwatched by 1")]
    as "and the creature, newly hidden, is told the player no longer watches it, not that it does"
  // The map's sight now matches the hidden set, so showing again sends the arrow.
  let #(_, shown) =
    spawns.visibility_changed(
      state:,
      at_ms: 8000,
      connection: 1,
      hidden: set.new(),
    )
  assert seen_creatures(shown) == [#(1, [73_707])]
    as "a later change sends the arrow the replay left out, so the map held it as unseen"
  assert spawns.creature_sends(shown) == [#(creature, "Watched by 1")]
    as "and the creature is watched again"
}
