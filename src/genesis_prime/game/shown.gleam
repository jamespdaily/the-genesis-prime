//// The units a player's client shows, as its connection knows them: the picture
//// the connection selects a go's targets from. It holds what a selection needs of
//// each unit and nothing the unit's owner decides.
////
//// ```
//// the creature's 0x262 news ─▶ shown(unit, ShownCreature(place, life, alive, hit radius, levels))
//// its Health and Died news ─▶ alive changed        its 0x355 ─▶ the unit is no longer shown
//// candidates(picture, faction, caster) ─▶ the alive foes, as geometry's candidates (genesis_prime/game/area)
//// ```
////
//// - **The picture is one news message stale at worst.** A creature that died in
////   flight is refused by its owner (`Refused(Dead)`) and left out of the go.
//// - **A foe** is a creature whose faction level toward the caster's player
////   faction is Hostile or Neutral, 7 or less (`0x1403ad540`, `Creature2.73464`); a
////   Friendly creature, another player and the caster are never struck. The levels
////   are worked out when the content loads, since Faction2 is a content-only table
////   (genesis_prime/world_map/spawn `faction_levels`).
//// - **A creature's life** is the number of the map's watch it was started under,
////   which is part of its address (genesis_prime/step `Creature`).

import genesis_prime/game/area.{type Candidate}
import genesis_prime/game/start_place.{type Place}
import gleam/dict.{type Dict}

/// The player faction of a caster, which picks the faction level the creature
/// holds toward it.
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
    /// False once the creature's Died news arrived.
    alive: Bool,
    /// Creature2DisplayInfo.hitRadius.
    hit_radius: Float,
    /// The creature's faction level toward the Exile and the Dominion faction.
    levels: #(Int, Int),
  )
}

/// The units the client shows, by unit id.
pub type Picture =
  Dict(Int, Shown)

/// The faction of a character, by its Faction2 id (Dominion 166, Exile 167), or
/// `Error(Nil)` for any other.
pub fn faction_of(faction_id faction_id: Int) -> Result(PlayerFaction, Nil) {
  case faction_id {
    166 -> Ok(Dominion)
    167 -> Ok(Exile)
    _ -> Error(Nil)
  }
}

/// The alive foes of a player of `faction` in the picture, as candidates for an
/// area, in unit id order, never the caster `caster_unit_id`.
pub fn candidates(
  picture picture: Picture,
  faction faction: PlayerFaction,
  caster_unit_id caster_unit_id: Int,
) -> List(Candidate) {
  unbuilt(inputs: #(picture, faction, caster_unit_id))
}

/// The place of a shown creature, for the centre of a child cast made on it, or
/// `Error(Nil)` for a unit that is not shown or not a creature.
pub fn place_of(
  picture picture: Picture,
  unit_id unit_id: Int,
) -> Result(Place, Nil) {
  unbuilt(inputs: #(picture, unit_id))
}

/// The picture with the creature marked alive or dead by its owner's news.
pub fn with_alive(
  picture picture: Picture,
  unit_id unit_id: Int,
  alive alive: Bool,
) -> Picture {
  unbuilt(inputs: #(picture, unit_id, alive))
}

/// The body of a function the shape names and the build writes: the arguments
/// are used, and the call stops.
fn unbuilt(inputs _inputs: inputs) -> output {
  panic as "not built: the shape holds the types"
}
