//// The rules of one world's map: which players are on it, where, and who is
//// told when a player joins or leaves. Pure: the process that owns the state
//// (`world_map_process`) carries out the effects. One world can have many maps;
//// each is one state.

import genesis_prime/map/delivery.{type Delivery, Appeared, Disappeared}
import genesis_prime/map/grid.{type Grid}
import genesis_prime/map/position.{type Position}
import genesis_prime/map/unit.{type Newcomer, type PlayerUnit, PlayerUnit}
import gleam/dict.{type Dict}
import gleam/list

/// How far a player sees other players, in metres: a stand-in, not the
/// client's. No client table or code holds a unit visibility range (the
/// topology trial's measure 0 searched the client's strings and the column
/// names of its tables), so players within this range of each other are told
/// about each other until the client's value is found.
pub const visibility_range_metres = 100.0

/// A map's state: its world, the next unit id, the units on it by id and by
/// character, and the grid of their positions.
pub opaque type WorldMap {
  WorldMap(
    world_id: Int,
    next_unit_id: Int,
    units: Dict(Int, PlayerUnit),
    unit_of_character: Dict(Int, Int),
    players: Grid,
  )
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
  WorldMap(
    world_id:,
    next_unit_id: 1,
    units: dict.new(),
    unit_of_character: dict.new(),
    players: grid.new(cell_size: visibility_range_metres),
  )
}

/// The World row the map is of.
pub fn world_id(map map: WorldMap) -> Int {
  map.world_id
}

/// A character joins: its unit gets the next unit id and is put on the grid.
/// The players within `visibility_range_metres` of it are told it appeared, and
/// it is told about each of them.
pub fn join(
  map map: WorldMap,
  newcomer newcomer: Newcomer,
) -> Result(#(WorldMap, PlayerUnit, List(Effect)), JoinRefused) {
  case dict.get(map.unit_of_character, newcomer.character_id) {
    Ok(unit_id) -> Error(CharacterAlreadyOnMap(unit_id:))
    Error(Nil) -> {
      let unit =
        PlayerUnit(
          id: map.next_unit_id,
          character_id: newcomer.character_id,
          name: newcomer.name,
          race_id: newcomer.race_id,
          class_id: newcomer.class_id,
          gender: newcomer.gender,
          path: newcomer.path,
          position: newcomer.position,
        )
      let observers = in_range(map:, of: unit.position)
      let told_of_the_newcomer = case observers {
        [] -> []
        [_, ..] -> [
          Deliver(
            delivery: Appeared(unit),
            about: unit.id,
            to: list.map(observers, fn(observer) { observer.id }),
          ),
        ]
      }
      let newcomer_told =
        list.map(observers, fn(observer) {
          Deliver(delivery: Appeared(observer), about: observer.id, to: [
            unit.id,
          ])
        })
      let joined =
        WorldMap(
          ..map,
          next_unit_id: map.next_unit_id + 1,
          units: dict.insert(map.units, unit.id, unit),
          unit_of_character: dict.insert(
            map.unit_of_character,
            unit.character_id,
            unit.id,
          ),
          players: grid.insert(map.players, unit.id, unit.position),
        )
      Ok(#(joined, unit, list.append(told_of_the_newcomer, newcomer_told)))
    }
  }
}

/// A unit leaves: it is taken off the grid, and the players within range of it
/// are told it disappeared. A unit that is not on the map changes nothing.
pub fn leave(
  map map: WorldMap,
  unit_id unit_id: Int,
) -> #(WorldMap, List(Effect)) {
  case dict.get(map.units, unit_id) {
    Error(Nil) -> #(map, [])
    Ok(unit) -> {
      let left =
        WorldMap(
          ..map,
          units: dict.delete(map.units, unit_id),
          unit_of_character: dict.delete(
            map.unit_of_character,
            unit.character_id,
          ),
          players: grid.remove(map.players, unit_id),
        )
      let observers = in_range(map: left, of: unit.position)
      let effects = case observers {
        [] -> []
        [_, ..] -> [
          Deliver(
            delivery: Disappeared(unit_id),
            about: unit_id,
            to: list.map(observers, fn(observer) { observer.id }),
          ),
        ]
      }
      #(left, effects)
    }
  }
}

/// The units on the map, by unit id.
pub fn units(map map: WorldMap) -> List(PlayerUnit) {
  dict.values(map.units)
}

/// The units within the visibility range of a position, read from the grid.
fn in_range(map map: WorldMap, of position: Position) -> List(PlayerUnit) {
  grid.near(map.players, position, visibility_range_metres)
  |> list.filter_map(fn(unit_id) { dict.get(map.units, unit_id) })
}
