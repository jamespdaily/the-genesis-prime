//// The picture of the units a client shows (`genesis_prime/game/shown`) and the
//// candidates an area takes from it. Expected values come from these places.
//// - A foe is a creature whose faction level toward the caster's player faction is
////   Hostile or Neutral, 7 or less; Friendly (8 to 10) is not attackable
////   (`0x1403ad540`, `Faction2Relationship.factionLevel`). The Virtual Battle Beast
////   (faction 1441) is hostile to Exiles and the Virtual Defense Dagun (1442) is
////   Friendly to them (`Creature2.73464`).
//// - No area strikes a dead unit, another player or the caster
////   (`Spell4ValidTargets.targetBitmask`, `Spell4Effects.targetFlags`).
//// - Dominion 166 and Exile 167 are the two player factions (`start_place`).

import genesis_prime/game/area.{Candidate, Point, Pose}
import genesis_prime/game/shown.{
  Dominion, Exile, ShownCreature, ShownObject, ShownPlayer,
}
import genesis_prime/game/start_place
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/creature_life.{
  type Attackable, Attackable, Hostile,
}
import genesis_prime/world_map/creature_path
import gleam/dict
import gleam/list
import owned_test
import place_support

const both = Attackable(exile: True, dominion: True)

const not_exiles = Attackable(exile: False, dominion: True)

fn creature(
  x x: Float,
  attackable attackable: Attackable,
  alive alive: Bool,
) -> shown.Shown {
  ShownCreature(
    creature_id: Creature2Id(73_464),
    path: creature_path.Standing(at: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x:,
      y: 0.0,
      z: -3.0,
    )),
    life: 4,
    alive:,
    hit_radius: 3.0,
    attackable:,
    hostile_to: Hostile(exile: False, dominion: False),
  )
}

/// A static object of no particular creature, standing at the origin.
fn an_object() -> shown.Shown {
  ShownObject(
    creature_id: Creature2Id(26_462),
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    ),
    hit_radius: 0.5,
  )
}

fn picture() -> shown.Picture {
  dict.from_list([
    #(1, creature(x: 1.0, attackable: both, alive: True)),
    #(2, creature(x: 2.0, attackable: both, alive: False)),
    #(3, ShownPlayer),
    #(4, creature(x: 4.0, attackable: not_exiles, alive: True)),
    #(5, creature(x: 5.0, attackable: both, alive: True)),
    #(7, creature(x: 7.0, attackable: both, alive: True)),
  ])
}

pub fn only_alive_hostile_or_neutral_creatures_other_than_the_caster_are_candidates_test() -> Nil {
  use <- owned_test.run(5000)
  assert shown.candidates(
      picture: picture(),
      faction: Exile,
      caster_unit_id: 7,
      now_ms: 0,
    )
    == [
      Candidate(unit_id: 1, at: Point(x: 1.0, z: -3.0), hit_radius: 3.0),
      Candidate(unit_id: 5, at: Point(x: 5.0, z: -3.0), hit_radius: 3.0),
    ]
    as "unit 2 is dead, 3 is a player, 4 is Friendly to Exiles (Friendly to Exiles), 7 is the caster; the Neutral unit 5 is struck"
}

pub fn a_creature_no_player_faction_may_attack_is_never_a_strike_candidate_test() -> Nil {
  use <- owned_test.run(5000)
  // `0x1403ad540`: a player attacks a Hostile or Neutral unit, not a Friendly
  // one; a quest giver Friendly to both player factions has neither flag.
  let picture =
    dict.from_list([
      #(1, creature(x: 1.0, attackable: Attackable(False, False), alive: True)),
    ])
  list.each([Exile, Dominion], fn(faction) {
    assert shown.candidates(picture:, faction:, caster_unit_id: 7, now_ms: 0)
      == []
      as "the Friendly creature is no candidate for either faction"
  })
}

pub fn a_shown_static_object_is_never_a_candidate_nor_a_creatures_place_or_life_test() -> Nil {
  use <- owned_test.run(5000)
  // A server choice of the static objects' design (the issue's "Design"
  // artifact): an object has no fight state, so no area strikes it.
  let picture = dict.insert(picture(), 6, an_object())
  list.each([Exile, Dominion], fn(faction) {
    assert !list.any(
      shown.candidates(picture:, faction:, caster_unit_id: 7, now_ms: 0),
      fn(candidate) { candidate.unit_id == 6 },
    )
      as "the object is no candidate for either faction"
  })
  assert shown.place_of(picture:, unit_id: 6, now_ms: 0) == Error(Nil)
    && shown.life_of(picture:, unit_id: 6) == Error(Nil)
    as "an object is not a creature: no place for a child cast, no life to address"
}

pub fn the_faction_level_read_is_the_casters_own_test() -> Nil {
  use <- owned_test.run(5000)
  let for_dominion =
    shown.candidates(
      picture: picture(),
      faction: Dominion,
      caster_unit_id: 7,
      now_ms: 0,
    )
  assert for_dominion
    == [
      Candidate(unit_id: 1, at: Point(x: 1.0, z: -3.0), hit_radius: 3.0),
      Candidate(unit_id: 4, at: Point(x: 4.0, z: -3.0), hit_radius: 3.0),
      Candidate(unit_id: 5, at: Point(x: 5.0, z: -3.0), hit_radius: 3.0),
    ]
    as "the creature's news says whom it may be attacked by: unit 4 may be attacked by the Dominion"
}

pub fn a_creature_marked_dead_by_its_news_is_no_longer_a_candidate_test() -> Nil {
  use <- owned_test.run(5000)
  let after = shown.with_alive(picture: picture(), unit_id: 1, alive: False)
  assert shown.candidates(
      picture: after,
      faction: Exile,
      caster_unit_id: 7,
      now_ms: 0,
    )
    == [Candidate(unit_id: 5, at: Point(x: 5.0, z: -3.0), hit_radius: 3.0)]
    as "a Died news sets alive false (opcode.0x88c)"
}

// ---- a creature's pose, for a position condition ----

/// A creature standing at x and z that its 0x262 gave the yaw 0.7 (the kind 14 yaw of its
/// create message, which nothing turns afterwards: `creature.facing`).
fn facing_creature(x x: Float, z z: Float) -> shown.Shown {
  let place =
    start_place.turned(
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 5967,
        x:,
        y: 0.0,
        z:,
      ),
      facing: start_place.Facing(yaw: 0.7, pitch: 0.0, roll: 0.0),
    )
  ShownCreature(
    creature_id: Creature2Id(73_464),
    path: creature_path.Standing(at: place),
    life: 4,
    alive: True,
    hit_radius: 3.0,
    attackable: both,
    hostile_to: Hostile(exile: False, dominion: False),
  )
}

pub fn a_standing_creatures_pose_is_its_place_and_the_yaw_of_its_0x262_test() -> Nil {
  use <- owned_test.run(5000)
  let picture = dict.from_list([#(1, facing_creature(x: 10.0, z: -20.0))])
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 0)
    == Ok(Pose(at: Point(x: 10.0, z: -20.0), yaw: 0.7))
}

pub fn a_running_creatures_pose_is_where_its_path_puts_it_with_the_yaw_its_path_does_not_turn_test() -> Nil {
  use <- owned_test.run(5000)
  // A path of kind 4 moves a creature without turning it (`creature.facing`): from (0, 0)
  // to (0, -20) at 10 a second from 1000 ms, the creature faces its 0x262's yaw all along.
  let assert ShownCreature(path: standing, ..) as from =
    facing_creature(x: 0.0, z: 0.0)
  let start = creature_path.end(path: standing)
  let picture =
    dict.from_list([
      #(
        1,
        ShownCreature(
          ..from,
          path: creature_path.Running(
            from: start,
            to: start_place.moved(place: start, x: 0.0, y: 0.0, z: -20.0),
            started_ms: 1000,
            speed: 10.0,
          ),
        ),
      ),
    ])
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 1000)
    == Ok(Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.7))
    as "at its start"
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 2000)
    == Ok(Pose(at: Point(x: 0.0, z: -10.0), yaw: 0.7))
    as "10 units along after a second, still facing 0.7"
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 9000)
    == Ok(Pose(at: Point(x: 0.0, z: -20.0), yaw: 0.7))
    as "at its end"
}

pub fn a_unit_that_is_not_a_shown_creature_has_no_pose_test() -> Nil {
  use <- owned_test.run(5000)
  let picture =
    dict.from_list([
      #(1, facing_creature(x: 10.0, z: -20.0)),
      #(2, ShownPlayer),
      #(3, an_object()),
    ])
  assert shown.pose_of(picture:, unit_id: 2, now_ms: 0) == Error(Nil)
  assert shown.pose_of(picture:, unit_id: 3, now_ms: 0) == Error(Nil)
  assert shown.pose_of(picture:, unit_id: 99, now_ms: 0) == Error(Nil)
  assert shown.poses_of(picture:, unit_ids: [1, 2, 3, 99], now_ms: 0)
    == dict.from_list([#(1, Pose(at: Point(x: 10.0, z: -20.0), yaw: 0.7))])
    as "the poses of the units asked for that are shown creatures, and no other"
}
