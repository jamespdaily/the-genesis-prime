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

import fixture_tables
import genesis_prime/game/area.{Candidate, Point, Pose}
import genesis_prime/game/shown.{
  Dominion, Exile, ShownCreature, ShownObject, ShownPlayer,
}
import genesis_prime/game/start_place
import genesis_prime/message/crowd_control_state
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/creature_life.{
  type Attackable, Attackable, Hostile,
}
import genesis_prime/world_map/creature_path
import genesis_prime/world_map/creature_turn
import gleam/dict
import gleam/float
import gleam/list
import gleam/option
import owned_test
import place_support

/// The viewer of the pose tests: unit 500, standing at the origin.
fn a_viewer() -> shown.Viewer {
  shown.Viewer(
    unit_id: 500,
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    ),
  )
}

const both = Attackable(exile: True, dominion: True)

const not_exiles = Attackable(exile: False, dominion: True)

fn creature(
  x x: Float,
  attackable attackable: Attackable,
  alive alive: Bool,
) -> shown.Shown {
  ShownCreature(
    creature_id: Creature2Id(73_464),
    faction_id: 0,
    checklist_index: 0,
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
    in_combat: False,
    held: [],
    unit_states: [],
    face: option.None,
  )
}

/// A static object of no particular creature, standing at the origin.
fn an_object() -> shown.Shown {
  ShownObject(
    creature_id: Creature2Id(26_462),
    faction_id: 0,
    checklist_index: 0,
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 0.0,
      y: 0.0,
      z: 0.0,
    ),
    hit_radius: 0.5,
    hostile_to: Hostile(exile: False, dominion: False),
  )
}

fn picture() -> shown.Picture {
  dict.from_list([
    #(1, creature(x: 1.0, attackable: both, alive: True)),
    #(2, creature(x: 2.0, attackable: both, alive: False)),
    #(3, ShownPlayer(at: option.None)),
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

pub fn combat_news_marks_only_a_shown_creature_in_combat_test() -> Nil {
  use <- owned_test.run(5000)
  let with_object = dict.insert(picture(), 8, an_object())
  let assert Ok(ShownCreature(in_combat: before, ..)) = dict.get(with_object, 1)
  assert !before as "a creature is shown out of combat"
  let fighting =
    shown.with_in_combat(picture: with_object, unit_id: 1, in_combat: True)
  let assert Ok(ShownCreature(in_combat: marked, ..)) = dict.get(fighting, 1)
  assert marked
    as "a CombatState news with in_combat sets the creature's state until the next one (0x89a; the client's unit word 0x2ac, read by 0x14047a060)"
  assert dict.delete(fighting, 1) == dict.delete(with_object, 1)
    as "no other unit changes"
  let calm =
    shown.with_in_combat(picture: fighting, unit_id: 1, in_combat: False)
  assert calm == with_object as "the next news clears it"
  assert shown.with_in_combat(picture: with_object, unit_id: 8, in_combat: True)
    == with_object
    as "a static object has no fight state"
  assert shown.with_in_combat(picture: with_object, unit_id: 3, in_combat: True)
    == with_object
    as "another player's unit is left as it was"
  assert shown.with_in_combat(
      picture: with_object,
      unit_id: 99,
      in_combat: True,
    )
    == with_object
    as "a unit that is not shown stays not shown"
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
    faction_id: 0,
    checklist_index: 0,
    path: creature_path.Standing(at: place),
    life: 4,
    alive: True,
    hit_radius: 3.0,
    attackable: both,
    hostile_to: Hostile(exile: False, dominion: False),
    in_combat: False,
    held: [],
    unit_states: [],
    face: option.None,
  )
}

pub fn a_standing_creatures_pose_is_its_place_and_the_yaw_of_its_0x262_test() -> Nil {
  use <- owned_test.run(5000)
  let picture = dict.from_list([#(1, facing_creature(x: 10.0, z: -20.0))])
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 0, viewer: a_viewer())
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
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 1000, viewer: a_viewer())
    == Ok(Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.7))
    as "at its start"
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 2000, viewer: a_viewer())
    == Ok(Pose(at: Point(x: 0.0, z: -10.0), yaw: 0.7))
    as "10 units along after a second, still facing 0.7"
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 9000, viewer: a_viewer())
    == Ok(Pose(at: Point(x: 0.0, z: -20.0), yaw: 0.7))
    as "at its end"
}

pub fn a_thrown_creature_that_turns_has_the_yaw_of_its_turn_test() -> Nil {
  use <- owned_test.run(5000)
  // A throw's kind 14 turns the creature: its pose has that yaw during the flight and
  // after it, not the yaw of its 0x262.
  let assert ShownCreature(path: standing, ..) as from =
    facing_creature(x: 0.0, z: 0.0)
  let start = creature_path.end(path: standing)
  let picture =
    dict.from_list([
      #(
        1,
        ShownCreature(
          ..from,
          path: creature_path.Timed(
            first: #(1000, start),
            rest: [
              #(1400, start_place.moved(place: start, x: 0.0, y: 0.0, z: -20.0)),
            ],
            turned_to: option.Some(start_place.Facing(
              yaw: 2.0,
              pitch: 0.0,
              roll: 0.0,
            )),
          ),
        ),
      ),
    ])
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 1200, viewer: a_viewer())
    == Ok(Pose(at: Point(x: 0.0, z: -10.0), yaw: 2.0))
    as "during the flight"
  assert shown.pose_of(picture:, unit_id: 1, now_ms: 9000, viewer: a_viewer())
    == Ok(Pose(at: Point(x: 0.0, z: -20.0), yaw: 2.0))
    as "after it"
}

// ---- the cast group a unit belongs to ----

pub fn in_group_tests_the_shown_unit_against_the_group_test() -> Nil {
  use <- owned_test.run(10_000)
  // TargetGroup 5506 is of type 1 and lists Creature2 41604, 41609, 41611 and 41613
  // (`0x1403b4a20`: type 1 tests the unit's Creature2 id); 32668 is none of them.
  let tables = fixture_tables.shared()
  let assert ShownCreature(..) as from = facing_creature(x: 0.0, z: 0.0)
  let picture =
    dict.from_list([
      #(900, ShownCreature(..from, creature_id: Creature2Id(41_604))),
      #(902, ShownCreature(..from, creature_id: Creature2Id(32_668))),
      #(904, ShownPlayer(at: option.None)),
    ])
  assert shown.in_group(tables:, picture:, group: 5506, unit_id: 900)
    as "unit 900 is of Creature2 41604, which the group lists"
  assert !shown.in_group(tables:, picture:, group: 5506, unit_id: 902)
    as "unit 902 is of Creature2 32668, which it does not"
  assert !shown.in_group(tables:, picture:, group: 5506, unit_id: 903)
    as "a unit that is not shown is in no group"
  assert !shown.in_group(tables:, picture:, group: 5506, unit_id: 904)
    as "another player's unit has no Creature2 row to test"
}

pub fn a_unit_that_is_not_a_shown_creature_has_no_pose_test() -> Nil {
  use <- owned_test.run(5000)
  let picture =
    dict.from_list([
      #(1, facing_creature(x: 10.0, z: -20.0)),
      #(2, ShownPlayer(at: option.None)),
      #(3, an_object()),
    ])
  assert shown.pose_of(picture:, unit_id: 2, now_ms: 0, viewer: a_viewer())
    == Error(Nil)
  assert shown.pose_of(picture:, unit_id: 3, now_ms: 0, viewer: a_viewer())
    == Error(Nil)
  assert shown.pose_of(picture:, unit_id: 99, now_ms: 0, viewer: a_viewer())
    == Error(Nil)
  assert shown.poses_of(
      picture:,
      unit_ids: [1, 2, 3, 99],
      now_ms: 0,
      viewer: a_viewer(),
    )
    == dict.from_list([#(1, Pose(at: Point(x: 10.0, z: -20.0), yaw: 0.7))])
    as "the poses of the units asked for that are shown creatures, and no other"
}

pub fn a_died_news_clears_a_creatures_held_states_and_only_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  let holding =
    shown.with_held_applied(
      picture: picture(),
      unit_id: 1,
      state: crowd_control_state.Stun,
      instance_id: 28_673,
    )
  let assert Ok(ShownCreature(held:, ..)) = dict.get(holding, 1)
  assert held == [shown.HeldState(crowd_control_state.Stun, 28_673)]
    as "a 0x87f gives the creature the state under its instance id"
  let dead = shown.with_alive(picture: holding, unit_id: 1, alive: False)
  let assert Ok(ShownCreature(held: after, ..)) = dict.get(dead, 1)
  assert after == []
    as "a Died news (opcode.0x88c, SetUnitDead) ends the creature's states with its life"
  assert shown.with_held_applied(
      picture: picture(),
      unit_id: 3,
      state: crowd_control_state.Stun,
      instance_id: 1,
    )
    == picture()
    as "another player's unit holds no state in the picture"
}

pub fn a_unit_state_is_held_ended_by_its_number_and_cleared_at_death_test() -> Nil {
  use <- owned_test.run(5000)
  // Two casters hold state 6 on one creature under two numbers (its creature gave 1 and 2);
  // a hold ends by its own number (`Spell4Effects.effectType.15`: no frame names a state, so
  // the creature's news is the only record).
  let held_by_two =
    picture()
    |> shown.with_unit_state_held(unit_id: 1, state: 6, number: 1)
    |> shown.with_unit_state_held(unit_id: 1, state: 19, number: 2)
    |> shown.with_unit_state_held(unit_id: 1, state: 6, number: 3)
  let assert Ok(ShownCreature(unit_states:, ..)) = dict.get(held_by_two, 1)
  assert unit_states
    == [
      shown.HeldUnitState(state: 6, number: 1),
      shown.HeldUnitState(state: 19, number: 2),
      shown.HeldUnitState(state: 6, number: 3),
    ]
    as "each hold is kept under its number, in the order told, the same state twice included"
  let ended =
    shown.with_unit_state_ended(picture: held_by_two, unit_id: 1, number: 1)
  let assert Ok(ShownCreature(unit_states: after, ..)) = dict.get(ended, 1)
  assert after
    == [
      shown.HeldUnitState(state: 19, number: 2),
      shown.HeldUnitState(state: 6, number: 3),
    ]
    as "an end drops its own number only: the second state 6 is still held"
  assert shown.with_unit_state_ended(picture: ended, unit_id: 1, number: 99)
    == ended
    as "a number the creature holds no more changes nothing"
  let dead = shown.with_alive(picture: held_by_two, unit_id: 1, alive: False)
  let assert Ok(ShownCreature(unit_states: at_death, ..)) = dict.get(dead, 1)
  assert at_death == []
    as "a Died news ends the creature's unit states with its life, and the creature sends no end for them"
  assert shown.with_unit_state_held(
      picture: picture(),
      unit_id: 3,
      state: 6,
      number: 1,
    )
    == picture()
    as "another player's unit holds no state in the picture"
  assert shown.with_unit_state_held(
      picture: picture(),
      unit_id: 99,
      state: 6,
      number: 1,
    )
    == picture()
    as "nor does a unit the client does not show"
}

// ---- a creature that faces a unit, a point or a way ----

/// A quarter turn: the yaw that faces a target along -x from a unit on the origin, by the
/// client's own direction (`movement_command.kind_14.facing`, `area.bearing` with yaw 0:
/// atan2(-dx, -dz)); a target straight ahead along -z is yaw 0.
const quarter_turn = 1.5707963267948966

fn faced_creature(face face: creature_turn.Face) -> shown.Picture {
  let assert ShownCreature(..) as from = facing_creature(x: 0.0, z: 0.0)
  dict.from_list([#(1, ShownCreature(..from, face: option.Some(face)))])
}

pub fn a_shown_creature_that_faces_the_viewer_is_posed_along_the_bearing_to_the_viewer_test() -> Nil {
  use <- owned_test.run(5000)
  // The creature stands on the origin; the viewer's unit 500 stands 10 along -x, a quarter
  // turn from straight ahead.
  let viewer =
    shown.Viewer(
      unit_id: 500,
      place: place_support.at(
        world_id: 3460,
        world_zone_id: 5967,
        x: -10.0,
        y: 0.0,
        z: 0.0,
      ),
    )
  let picture = faced_creature(face: creature_turn.Unit(unit_id: 500))
  let assert Ok(pose) = shown.pose_of(picture:, unit_id: 1, now_ms: 0, viewer:)
  assert float.loosely_equals(pose.yaw, quarter_turn, tolerating: 0.000001)
    as "it faces the viewer, not the 0.7 of its 0x262"
  assert pose.at == Point(x: 0.0, z: 0.0)
    as "the creature stays where it stands"
  assert shown.pose_of(
      picture: faced_creature(face: creature_turn.Unit(unit_id: 501)),
      unit_id: 1,
      now_ms: 0,
      viewer:,
    )
    == Ok(Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.7))
    as "a unit the picture has no place for leaves the yaw as it was, as the client leaves it"
}

pub fn a_creature_that_faces_another_player_is_posed_toward_that_player_where_the_last_position_command_put_it_test() -> Nil {
  use <- owned_test.run(5000)
  // Player B's picture: the creature faces player A (unit 501), whom B's client shows at
  // 10 along +x (minus a quarter turn) once a position command put it there.
  let before =
    dict.insert(
      faced_creature(face: creature_turn.Unit(unit_id: 501)),
      501,
      ShownPlayer(at: option.None),
    )
  assert shown.pose_of(
      picture: before,
      unit_id: 1,
      now_ms: 0,
      viewer: a_viewer(),
    )
    == Ok(Pose(at: Point(x: 0.0, z: 0.0), yaw: 0.7))
    as "before A's first position command the picture has no place for A"
  let picture =
    shown.with_player_at(
      picture: before,
      unit_id: 501,
      at: Point(x: 10.0, z: 0.0),
    )
  let assert Ok(pose) =
    shown.pose_of(picture:, unit_id: 1, now_ms: 0, viewer: a_viewer())
  assert float.loosely_equals(
    pose.yaw,
    0.0 -. quarter_turn,
    tolerating: 0.000001,
  )
    as "the creature faces A, as B's client shows it"
  let moved =
    shown.with_player_at(picture:, unit_id: 501, at: Point(x: -10.0, z: 0.0))
  let assert Ok(pose) =
    shown.pose_of(picture: moved, unit_id: 1, now_ms: 0, viewer: a_viewer())
  assert float.loosely_equals(pose.yaw, quarter_turn, tolerating: 0.000001)
    as "and follows A to the other side"
}

pub fn a_creature_that_faces_a_point_or_a_fixed_way_is_posed_so_and_a_turning_path_clears_the_face_test() -> Nil {
  use <- owned_test.run(5000)
  let home =
    place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x: 0.0,
      y: 0.0,
      z: -10.0,
    )
  let assert Ok(ahead) =
    shown.pose_of(
      picture: faced_creature(face: creature_turn.Point(place: home)),
      unit_id: 1,
      now_ms: 0,
      viewer: a_viewer(),
    )
  assert float.loosely_equals(ahead.yaw, 0.0, tolerating: 0.000001)
    as "a point 10 along -z is straight ahead: yaw 0, not the 0x262's 0.7"
  assert shown.pose_of(
      picture: faced_creature(
        face: creature_turn.Fixed(facing: start_place.Facing(
          yaw: 2.5,
          pitch: 0.0,
          roll: 0.0,
        )),
      ),
      unit_id: 1,
      now_ms: 0,
      viewer: a_viewer(),
    )
    == Ok(Pose(at: Point(x: 0.0, z: 0.0), yaw: 2.5))
    as "a fixed facing is its yaw"
  let faced = faced_creature(face: creature_turn.Unit(unit_id: 500))
  let placed =
    shown.with_path(
      picture: faced,
      unit_id: 1,
      path: creature_path.Standing(at: home),
    )
  let assert Ok(ShownCreature(face: kept, ..)) = dict.get(placed, 1)
  assert kept == option.Some(creature_turn.Unit(unit_id: 500))
    as "a path that does not turn leaves the face"
  let turned =
    shown.with_path(
      picture: faced,
      unit_id: 1,
      path: creature_path.Timed(
        first: #(0, home),
        rest: [],
        turned_to: option.Some(start_place.Facing(
          yaw: 1.0,
          pitch: 0.0,
          roll: 0.0,
        )),
      ),
    )
  let assert Ok(ShownCreature(face: cleared, ..)) = dict.get(turned, 1)
  assert cleared == option.None as "a path that turns it replaces the face"
}
