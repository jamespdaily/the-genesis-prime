//// The units a player's client shows, as its connection knows them: the picture
//// the connection selects a go's targets from. It holds what a selection needs of
//// each unit and nothing the unit's owner decides.
////
//// ```
//// the creature's 0x262 news ─▶ shown(unit, ShownCreature(place, life, alive, hit radius, attackable))
//// its Health and Died news ─▶ alive changed        its 0x355 ─▶ the unit is no longer shown
//// candidates(picture, faction, caster) ─▶ the alive foes, as geometry's candidates (genesis_prime/game/area)
//// ```
////
//// - **The picture is one news message stale at worst.** A creature that died in
////   flight is refused by its owner (`Refused(Dead)`) and left out of the go.
//// - **A foe** is a creature that may be attacked by a player of the caster's faction:
////   its faction level toward that faction is Hostile or Neutral, 7 or less
////   (`0x1403ad540`, `Creature2.73464`), which the creature's own news carries for each
////   player faction (worked out when the content loads, since Faction2 is a content-only
////   table, by genesis_prime/world_map/spawn). A Friendly creature, another player and the
////   caster are never struck.
//// - **A creature's life** is the number of the map's watch it was started under,
////   which is part of its address (genesis_prime/step `Creature`).

import genesis_prime/game/area.{type Candidate, Candidate, Point}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/world_map/creature_life.{type Attackable}
import genesis_prime/world_map/spawn
import gleam/dict.{type Dict}
import gleam/int
import gleam/list

/// The player faction of a caster, which picks the faction a creature may be
/// attacked by.
pub type PlayerFaction {
  Exile
  Dominion
}

/// A unit the client shows.
pub type Shown {
  /// Another player's unit, which no area strikes.
  ShownPlayer
  /// A creature, as its 0x262 news gave it.
  ShownCreature(
    place: Place,
    /// The creature's life, which its address needs to be told a strike.
    life: Int,
    /// False once the creature's Died news arrived, or when it was created dead.
    alive: Bool,
    /// Creature2DisplayInfo.hitRadius.
    hit_radius: Float,
    /// Whom the creature may be attacked by.
    attackable: Attackable,
  )
}

/// The units the client shows, by unit id.
pub type Picture =
  Dict(Int, Shown)

/// The faction of a character, by its Faction2 id (Dominion 166, Exile 167), or
/// `Error(Nil)` for any other.
pub fn faction_of(faction_id faction_id: Int) -> Result(PlayerFaction, Nil) {
  case faction_id == spawn.exile_faction, faction_id == spawn.dominion_faction {
    True, _ -> Ok(Exile)
    _, True -> Ok(Dominion)
    False, False -> Error(Nil)
  }
}

/// The alive foes of a player of `faction` in the picture, as candidates for an
/// area, in unit id order, never the caster `caster_unit_id`.
pub fn candidates(
  picture picture: Picture,
  faction faction: PlayerFaction,
  caster_unit_id caster_unit_id: Int,
) -> List(Candidate) {
  dict.to_list(picture)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.filter_map(fn(entry) {
    let #(unit_id, shown) = entry
    case shown {
      ShownPlayer -> Error(Nil)
      ShownCreature(place:, alive:, hit_radius:, attackable:, ..) ->
        case
          alive
          && unit_id != caster_unit_id
          && may_attack(faction:, attackable:)
        {
          True ->
            Ok(Candidate(
              unit_id:,
              at: Point(x: start_place.x(place), z: start_place.z(place)),
              hit_radius:,
            ))
          False -> Error(Nil)
        }
    }
  })
}

fn may_attack(
  faction faction: PlayerFaction,
  attackable attackable: Attackable,
) -> Bool {
  case faction {
    Exile -> attackable.exile
    Dominion -> attackable.dominion
  }
}

/// The place of a shown creature, for the centre of a child cast made on it, or
/// `Error(Nil)` for a unit that is not shown or not a creature.
pub fn place_of(
  picture picture: Picture,
  unit_id unit_id: Int,
) -> Result(Place, Nil) {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(place:, ..)) -> Ok(place)
    Ok(ShownPlayer) | Error(Nil) -> Error(Nil)
  }
}

/// The creature's life, for its address, or `Error(Nil)` for a unit that is not a
/// shown creature.
pub fn life_of(
  picture picture: Picture,
  unit_id unit_id: Int,
) -> Result(Int, Nil) {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(life:, ..)) -> Ok(life)
    Ok(ShownPlayer) | Error(Nil) -> Error(Nil)
  }
}

/// The picture with the creature marked alive or dead by its owner's news; a unit
/// that is not a shown creature is as it was.
pub fn with_alive(
  picture picture: Picture,
  unit_id unit_id: Int,
  alive alive: Bool,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(..) as creature) ->
      dict.insert(picture, unit_id, ShownCreature(..creature, alive:))
    Ok(ShownPlayer) | Error(Nil) -> picture
  }
}
