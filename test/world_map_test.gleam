//// The rules of one world's map. A character that joins gets the next unit id
//// and, with the players within the visibility range of it, tells and is told;
//// a unit that leaves is told away to the players in range. The visibility
//// range is a stand-in of 100 metres: no client table or code holds one (the
//// topology trial, measure 0), so what is checked is that the map tells
//// exactly the players within the range it uses, against a full scan.

import genesis_prime/map/delivery.{Appeared, Disappeared}
import genesis_prime/map/position.{Position}
import genesis_prime/map/unit.{type Newcomer, Newcomer, PlayerUnit}
import genesis_prime/map/world_map.{CharacterAlreadyOnMap, Deliver}
import gleam/int
import gleam/list
import owned_test
import seeded

fn newcomer(character_id: Int, x: Float) -> Newcomer {
  Newcomer(
    character_id:,
    name: "Ab Cd",
    race_id: 1,
    class_id: 3,
    gender: 1,
    path: 2,
    faction_id: 167,
    position: Position(x:, y: 0.0, z: 0.0),
  )
}

fn joined(
  map map: world_map.WorldMap,
  character_id character_id: Int,
  x x: Float,
) -> #(world_map.WorldMap, unit.PlayerUnit, List(world_map.Effect)) {
  let assert Ok(#(map, unit, effects)) =
    world_map.join(map, newcomer(character_id, x))
    as "the character joins"
  #(map, unit, effects)
}

pub fn the_visibility_range_is_the_trials_stand_in_of_100_metres_test() -> Nil {
  use <- owned_test.run(5000)
  assert world_map.visibility_range_metres == 100.0
    as "the topology trial's stand-in, marked as not from the client (#28 measure 0)"
}

pub fn a_joined_character_gets_the_next_unit_id_and_its_own_facts_test() -> Nil {
  use <- owned_test.run(5000)
  let map = world_map.new(7)
  let #(map, first, _) = joined(map:, character_id: 11, x: 0.0)
  let #(map, second, _) = joined(map:, character_id: 12, x: 500.0)
  assert first
    == PlayerUnit(
      id: 1,
      character_id: 11,
      name: "Ab Cd",
      race_id: 1,
      class_id: 3,
      gender: 1,
      path: 2,
      faction_id: 167,
      position: Position(x: 0.0, y: 0.0, z: 0.0),
    )
    as "unit ids are given in order from 1, and the unit carries the character's facts"
  assert second.id == 2
  assert list.sort(world_map.units(map), fn(a, b) { int.compare(a.id, b.id) })
    == [first, second]
    as "the map holds both units"
}

pub fn a_character_is_one_unit_on_a_map_test() -> Nil {
  use <- owned_test.run(5000)
  let #(map, first, _) = joined(map: world_map.new(7), character_id: 11, x: 0.0)
  assert world_map.join(map, newcomer(11, 50.0))
    == Error(CharacterAlreadyOnMap(unit_id: first.id))
    as "a character that is on the map cannot join it again"
  assert world_map.units(map) == [first] as "the map is unchanged"
}

pub fn a_player_in_range_is_told_of_the_newcomer_and_tells_it_of_itself_test() -> Nil {
  use <- owned_test.run(5000)
  let #(map, first, _) = joined(map: world_map.new(7), character_id: 11, x: 0.0)
  let #(_, second, effects) = joined(map:, character_id: 12, x: 60.0)
  assert list.sort(effects, fn(a, b) { int.compare(a.about, b.about) })
    == [
      Deliver(delivery: Appeared(first), about: first.id, to: [second.id]),
      Deliver(delivery: Appeared(second), about: second.id, to: [first.id]),
    ]
    as "the first player is told of the newcomer, and the newcomer of the first; each delivery is about one unit, so one sender keeps the order of what is said about it"
}

pub fn a_player_exactly_at_the_range_is_told_and_one_beyond_it_is_not_test() -> Nil {
  use <- owned_test.run(5000)
  let #(map, _, _) = joined(map: world_map.new(7), character_id: 11, x: 0.0)
  let #(map, at_range, at_range_effects) =
    joined(map:, character_id: 12, x: 100.0)
  assert list.length(at_range_effects) == 2
    as "a position exactly in range is within range"
  let #(_, _, beyond_effects) = joined(map:, character_id: 13, x: -100.1)
  assert beyond_effects == []
    as "a newcomer 100.1 metres from the first player and 200.1 from the second is in range of neither"
  assert at_range.id == 2
}

pub fn a_leaving_unit_is_told_away_to_the_players_in_range_only_test() -> Nil {
  use <- owned_test.run(5000)
  let #(map, near, _) = joined(map: world_map.new(7), character_id: 11, x: 0.0)
  let #(map, leaving, _) = joined(map:, character_id: 12, x: 50.0)
  let #(map, _far, _) = joined(map:, character_id: 13, x: 900.0)
  let #(left, effects) = world_map.leave(map, leaving.id)
  assert effects
    == [
      Deliver(delivery: Disappeared(leaving.id), about: leaving.id, to: [
        near.id,
      ]),
    ]
    as "only the player in range of the leaving unit is told"
  assert list.length(world_map.units(left)) == 2 as "the unit is off the map"
}

pub fn a_unit_that_is_not_on_the_map_leaves_nothing_changed_test() -> Nil {
  use <- owned_test.run(5000)
  let #(map, _, _) = joined(map: world_map.new(7), character_id: 11, x: 0.0)
  let #(left, effects) = world_map.leave(map, 999)
  assert left == map
  assert effects == []
}

pub fn a_character_that_left_can_join_again_with_a_new_unit_test() -> Nil {
  use <- owned_test.run(5000)
  let #(map, first, _) = joined(map: world_map.new(7), character_id: 11, x: 0.0)
  let #(map, _) = world_map.leave(map, first.id)
  let #(_, again, _) = joined(map:, character_id: 11, x: 0.0)
  assert again.id != first.id
    as "a unit id is not given twice, so a message about the old unit never names the new"
}

pub fn the_players_told_of_a_newcomer_are_exactly_those_a_full_scan_finds_in_range_test() -> Nil {
  use <- owned_test.run(60_000)
  let checked =
    int.range(from: 0, to: 100, with: #(20_261_304, 0), run: fn(random, _) {
      let #(random, checked) = random
      let #(map, units, random) = join_many(random:, count: 40)
      let #(_, newcomer_unit, effects) =
        joined_at_random(map:, random:, character_id: 1000)
      let in_range =
        list.filter(units, fn(unit) {
          position.within(unit.position, newcomer_unit.position, 100.0)
        })
        |> list.map(fn(unit) { unit.id })
        |> list.sort(int.compare)
      let told =
        list.flat_map(effects, fn(effect) {
          case effect.delivery {
            Appeared(unit) if unit.id == newcomer_unit.id -> effect.to
            Appeared(_) | Disappeared(_) -> []
          }
        })
        |> list.sort(int.compare)
      assert told == in_range
        as "the players told of the newcomer are the ones within range of it, and no other"
      let newcomer_told_of =
        list.flat_map(effects, fn(effect) {
          case effect.delivery {
            Appeared(unit) if unit.id != newcomer_unit.id -> [unit.id]
            Appeared(_) | Disappeared(_) -> []
          }
        })
        |> list.sort(int.compare)
      assert newcomer_told_of == in_range
        as "the newcomer is told of the players within range of it, and no other"
      #(random, checked + 1)
    })
  assert checked.1 == 100 as "every layout was checked"
}

fn join_many(
  random random: Int,
  count count: Int,
) -> #(world_map.WorldMap, List(unit.PlayerUnit), Int) {
  int.range(
    from: 0,
    to: count,
    with: #(world_map.new(7), [], random),
    run: fn(state, character_id) {
      let #(map, units, random) = state
      let #(x, random) = seeded.up_to(state: random, most: 600)
      let #(z, random) = seeded.up_to(state: random, most: 600)
      let assert Ok(#(map, unit, _)) =
        world_map.join(
          map,
          Newcomer(
            ..newcomer(character_id, int.to_float(x)),
            position: Position(x: int.to_float(x), y: 0.0, z: int.to_float(z)),
          ),
        )
        as "a character joins"
      #(map, [unit, ..units], random)
    },
  )
}

fn joined_at_random(
  map map: world_map.WorldMap,
  random random: Int,
  character_id character_id: Int,
) -> #(world_map.WorldMap, unit.PlayerUnit, List(world_map.Effect)) {
  let #(x, random) = seeded.up_to(state: random, most: 600)
  let #(z, _) = seeded.up_to(state: random, most: 600)
  let assert Ok(result) =
    world_map.join(
      map,
      Newcomer(
        ..newcomer(character_id, 0.0),
        position: Position(x: int.to_float(x), y: 0.0, z: int.to_float(z)),
      ),
    )
    as "the newcomer joins"
  result
}
