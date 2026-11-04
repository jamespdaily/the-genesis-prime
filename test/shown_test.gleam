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

import genesis_prime/game/area.{Candidate, Point}
import genesis_prime/game/shown.{Dominion, Exile, ShownCreature, ShownPlayer}
import gleam/dict
import owned_test
import place_support

fn creature(
  x x: Float,
  levels levels: #(Int, Int),
  alive alive: Bool,
) -> shown.Shown {
  ShownCreature(
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 5967,
      x:,
      y: 0.0,
      z: -3.0,
    ),
    life: 4,
    alive:,
    hit_radius: 3.0,
    levels:,
  )
}

fn picture() -> shown.Picture {
  dict.from_list([
    #(1, creature(x: 1.0, levels: #(0, 0), alive: True)),
    #(2, creature(x: 2.0, levels: #(0, 0), alive: False)),
    #(3, ShownPlayer),
    #(4, creature(x: 4.0, levels: #(10, 0), alive: True)),
    #(5, creature(x: 5.0, levels: #(5, 5), alive: True)),
    #(7, creature(x: 7.0, levels: #(0, 0), alive: True)),
  ])
}

pub fn only_alive_hostile_or_neutral_creatures_other_than_the_caster_are_candidates_test() -> Nil {
  use <- owned_test.run(5000)
  assert shown.candidates(picture: picture(), faction: Exile, caster_unit_id: 7)
    == [
      Candidate(unit_id: 1, at: Point(x: 1.0, z: -3.0), hit_radius: 3.0),
      Candidate(unit_id: 5, at: Point(x: 5.0, z: -3.0), hit_radius: 3.0),
    ]
    as "unit 2 is dead, 3 is a player, 4 is Friendly to Exiles (level 10), 7 is the caster; the Neutral unit 5 (level 5) is struck"
}

pub fn the_faction_level_read_is_the_casters_own_test() -> Nil {
  use <- owned_test.run(5000)
  let for_dominion =
    shown.candidates(picture: picture(), faction: Dominion, caster_unit_id: 7)
  assert for_dominion
    == [
      Candidate(unit_id: 1, at: Point(x: 1.0, z: -3.0), hit_radius: 3.0),
      Candidate(unit_id: 4, at: Point(x: 4.0, z: -3.0), hit_radius: 3.0),
      Candidate(unit_id: 5, at: Point(x: 5.0, z: -3.0), hit_radius: 3.0),
    ]
    as "the second level of a creature is its level toward the Dominion: unit 4 is hostile to it"
}

pub fn a_creature_marked_dead_by_its_news_is_no_longer_a_candidate_test() -> Nil {
  use <- owned_test.run(5000)
  let after = shown.with_alive(picture: picture(), unit_id: 1, alive: False)
  assert shown.candidates(picture: after, faction: Exile, caster_unit_id: 7)
    == [Candidate(unit_id: 5, at: Point(x: 5.0, z: -3.0), hit_radius: 3.0)]
    as "a Died news sets alive false (opcode.0x88c)"
}
