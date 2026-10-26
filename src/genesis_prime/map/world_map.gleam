//// The rules of one world's map: which players are on it, where, and who is
//// told when a player joins or leaves. Pure: the process that owns the state
//// (`world_map_process`) carries out the effects. One world can have many maps;
//// each is one state.

import genesis_prime/map/delivery.{type Delivery}
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit}

/// How far a player sees other players, in metres: a stand-in, not the
/// client's. No client table or code holds a unit visibility range (the
/// topology trial's measure 0 searched the client's strings and the column
/// names of its tables), so players within this range of each other are told
/// about each other until the client's value is found.
pub const visibility_range_metres = 100.0

/// A map's state: its world, the next unit id, the units on it by id and by
/// character, and the grid of their positions.
pub opaque type WorldMap {
  WorldMap
}

/// Something a map's process must tell connections: a delivery about the unit
/// `about`, to the players whose unit ids are listed in `to`. Everything said
/// about one unit goes through one sender, chosen by `about`, so players hear
/// it in the order the map decided it.
pub type Effect {
  Deliver(delivery: Delivery, about: Int, to: List(Int))
}

/// Why a character cannot join a map.
pub type JoinRefused {
  /// The character already has a unit on this map: one character is one unit.
  CharacterAlreadyOnMap(unit_id: Int)
}

/// A map of the world with the id, with no one on it.
pub fn new(world_id world_id: Int) -> WorldMap {
  todo as "an empty map"
}

/// A character joins: its unit gets the next unit id and is put on the grid.
/// The players within `visibility_range_metres` of it are told it appeared, and
/// it is told about each of them.
pub fn join(
  map map: WorldMap,
  newcomer newcomer: Newcomer,
) -> Result(#(WorldMap, PlayerUnit, List(Effect)), JoinRefused) {
  todo as "a character joins"
}

/// A unit leaves: it is taken off the grid, and the players within range of it
/// are told it disappeared. A unit that is not on the map changes nothing.
pub fn leave(
  map map: WorldMap,
  unit_id unit_id: Int,
) -> #(WorldMap, List(Effect)) {
  todo as "a unit leaves"
}

/// The units on the map, by unit id.
pub fn units(map map: WorldMap) -> List(PlayerUnit) {
  todo as "the units on the map"
}
