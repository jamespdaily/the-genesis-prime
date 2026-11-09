//// The units a player's client shows, as its connection knows them: the picture
//// the connection selects a go's targets from. It holds what a selection needs of
//// each unit and nothing the unit's owner decides.
////
//// ```
//// the creature's 0x262 news ─▶ shown(unit, ShownCreature(creature id, Standing(place), life, alive, hit radius, attackable, hostile to))
//// its CreatureMoved news   ─▶ path changed
//// its Health and Died news ─▶ alive changed        its 0x355 ─▶ the unit is no longer shown
//// candidates(picture, faction, caster, now) ─▶ the alive foes at place_at(path, now), as geometry's
////                                              candidates (genesis_prime/game/area)
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
//// - **A running creature** is where its last path puts it at the time of the go
////   (genesis_prime/world_map/creature_path `place_at`), by the same function the
////   creature reads its own place with.
//// - **A creature's pose** (`pose_of`) is that place's ground point with the yaw of its
////   0x262, which no path turns, so a position condition judges a creature by what its
////   client shows (`creature.facing`: kind 4 paths move a creature without turning it).
//// - **A creature's life** is the number of the map's watch it was started under,
////   which is part of its address (genesis_prime/step `Creature`).

import genesis_prime/game/area.{type Candidate, type Pose, Candidate}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/table/id.{type Creature2Id}
import genesis_prime/world_map/creature_life.{type Attackable, type Hostile}
import genesis_prime/world_map/creature_path.{type Path}
import genesis_prime/world_map/spawn
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

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
  /// A static object the map told of (genesis_prime/world_map/static_object),
  /// which has no fight state, so no area strikes it.
  ShownObject
  /// A creature, as its 0x262 news gave it and its 0x638 news moved it.
  ShownCreature(
    /// The Creature2 row it was created from.
    creature_id: Creature2Id,
    /// Where it stands or runs: standing at the place of its 0x262 until a
    /// CreatureMoved news.
    path: Path,
    /// The creature's life, which its address needs to be told a strike.
    life: Int,
    /// False once the creature's Died news arrived, or when it was created dead.
    alive: Bool,
    /// Creature2DisplayInfo.hitRadius.
    hit_radius: Float,
    /// Whom the creature may be attacked by.
    attackable: Attackable,
    /// Which player factions the creature is Hostile to (the client's own
    /// disposition of the creature toward the player, `0x14045a950`).
    hostile_to: Hostile,
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
/// area at monotonic time `now_ms`, in unit id order, never the caster
/// `caster_unit_id`.
pub fn candidates(
  picture picture: Picture,
  faction faction: PlayerFaction,
  caster_unit_id caster_unit_id: Int,
  now_ms now_ms: Int,
) -> List(Candidate) {
  dict.to_list(picture)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.filter_map(fn(entry) {
    let #(unit_id, shown) = entry
    case shown {
      ShownPlayer | ShownObject -> Error(Nil)
      ShownCreature(path:, alive:, hit_radius:, attackable:, ..) ->
        case
          alive
          && unit_id != caster_unit_id
          && may_attack(faction:, attackable:)
        {
          True ->
            Ok(Candidate(
              unit_id:,
              at: area.point_of(creature_path.place_at(path:, now_ms:)),
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

/// The place of a shown creature at monotonic time `now_ms`, for the centre of a
/// child cast made on it, or `Error(Nil)` for a unit that is not shown or not a
/// creature.
pub fn place_of(
  picture picture: Picture,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> Result(Place, Nil) {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(path:, ..)) -> Ok(creature_path.place_at(path:, now_ms:))
    Ok(ShownPlayer) | Ok(ShownObject) | Error(Nil) -> Error(Nil)
  }
}

/// The ground point and yaw of a shown creature at monotonic time `now_ms`, or `Error(Nil)`
/// for a unit that is not shown or not a creature: where its path puts it, with the yaw of
/// that place. The client holds the yaw of the creature's 0x262 and no position path turns
/// it (`creature.facing`); the place's yaw equals it because every place a creature's path
/// holds keeps the spawn's facing (`creature_path` `along`, and the home the creature
/// walks to is its spawn). This is the one place a shown creature's facing is read.
pub fn pose_of(
  picture picture: Picture,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> Result(Pose, Nil) {
  place_of(picture:, unit_id:, now_ms:)
  |> result.map(fn(place) { area.pose_of(place:) })
}

/// The poses of the shown creatures among the units, by unit id; a unit that is not a shown
/// creature has none.
pub fn poses_of(
  picture picture: Picture,
  unit_ids unit_ids: List(Int),
  now_ms now_ms: Int,
) -> Dict(Int, Pose) {
  list.filter_map(unit_ids, fn(unit_id) {
    pose_of(picture:, unit_id:, now_ms:)
    |> result.map(fn(pose) { #(unit_id, pose) })
  })
  |> dict.from_list
}

/// The creature's life, for its address, or `Error(Nil)` for a unit that is not a
/// shown creature.
pub fn life_of(
  picture picture: Picture,
  unit_id unit_id: Int,
) -> Result(Int, Nil) {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(life:, ..)) -> Ok(life)
    Ok(ShownPlayer) | Ok(ShownObject) | Error(Nil) -> Error(Nil)
  }
}

/// The picture with the creature running `path` by its owner's news; a unit that
/// is not a shown creature is as it was.
pub fn with_path(
  picture picture: Picture,
  unit_id unit_id: Int,
  path path: Path,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(..) as creature) ->
      dict.insert(picture, unit_id, ShownCreature(..creature, path:))
    Ok(ShownPlayer) | Ok(ShownObject) | Error(Nil) -> picture
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
    Ok(ShownPlayer) | Ok(ShownObject) | Error(Nil) -> picture
  }
}
