//// The units a player's client shows, as its connection knows them: the picture
//// the connection selects a go's targets from. It holds what a selection needs of
//// each unit and nothing the unit's owner decides.
////
//// ```
//// the creature's 0x262 news ─▶ shown(unit, ShownCreature(creature id, Standing(place), life, alive, hit radius, attackable, hostile to))
//// its CreatureMoved news   ─▶ path changed
//// its Health and Died news ─▶ alive changed        its 0x355 ─▶ the unit is no longer shown
//// its CombatState news     ─▶ in combat changed
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
//// - **A talkable unit** (`talkable`) is a creature or a static object: the client's
////   click on a unit checks its row, life, disposition and range and not its unit type,
////   so an object is alive, never in combat, and Hostile to the players its faction is
////   (`hostile_to`, filled when the object is shown).
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
import genesis_prime/game/target_group.{type Unit, Unit}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/table/creature2
import genesis_prime/table/id.{type Creature2Id, Faction2Id}
import genesis_prime/table/loader/store as table_store
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
  /// which has no fight state, so no area strikes it. It holds what the
  /// client's range check of a right-click reads of it (`opcode.0x97.range`).
  ShownObject(
    /// The Creature2 row of its 0x262.
    creature_id: Creature2Id,
    /// The Faction2 id its 0x262 gave it, 0 for none.
    faction_id: Int,
    /// The checklist index its 0x262 gave it, 0 for a type that sends none.
    checklist_index: Int,
    /// Where its 0x262 puts it, in the world and zone of the player it was shown to.
    place: Place,
    /// Creature2DisplayInfo.hitRadius of its display, 0.0 when the display has no
    /// row.
    hit_radius: Float,
    /// Which player factions the object is Hostile to (the client's own disposition of
    /// the unit toward the player, `0x14045a950`), worked out from its faction.
    hostile_to: Hostile,
  )
  /// A creature, as its 0x262 news gave it and its 0x638 news moved it.
  ShownCreature(
    /// The Creature2 row it was created from.
    creature_id: Creature2Id,
    /// The Faction2 id its 0x262 gave it.
    faction_id: Int,
    /// The checklist index its 0x262 gave it.
    checklist_index: Int,
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
    /// True from the creature's CombatState news that it entered combat until the one
    /// that it left it; the client gives a creature in combat no click
    /// (`PickInteractionKind`, `0x14047a060`).
    in_combat: Bool,
    /// The crowd-control states the creature holds as its viewer's client was told
    /// (0x87f without a later 0x880), which the target gate of a press reads.
    held: List(HeldState),
  )
}

/// A crowd-control state a shown creature holds, with the instance id its 0x87f gave.
pub type HeldState {
  HeldState(state: CrowdControlState, instance_id: Int)
}

/// The units the client shows, by unit id.
pub type Picture =
  Dict(Int, Shown)

/// The unit as the client's group test reads it and its checklist index, for a shown
/// creature or object, or `Error(Nil)` for a unit that is not one (another player). The
/// Creature2 row is in the tables the spawn was loaded from, so a missing one is no
/// unit either.
pub fn target_of(
  tables tables: table_store.Tables,
  shown shown: Shown,
) -> Result(#(Unit, Int), Nil) {
  case shown {
    ShownPlayer -> Error(Nil)
    ShownObject(creature_id:, faction_id:, checklist_index:, ..)
    | ShownCreature(creature_id:, faction_id:, checklist_index:, ..) ->
      creature2.get(tables, creature_id)
      |> result.map(fn(row) {
        #(
          Unit(
            creature_id:,
            faction_id: Faction2Id(faction_id),
            unit_race_id: creature2.unit_race_id(row),
          ),
          checklist_index,
        )
      })
  }
}

/// Whether the unit is a shown creature or object the TargetGroup row `group` holds
/// (`0x1403b4a20`). A unit that is not shown, or another player, is in no group.
pub fn in_group(
  tables tables: table_store.Tables,
  picture picture: Picture,
  group group: Int,
  unit_id unit_id: Int,
) -> Bool {
  case dict.get(picture, unit_id) {
    Error(Nil) -> False
    Ok(shown) ->
      case target_of(tables:, shown:) {
        Ok(#(unit, _)) -> target_group.contains(tables:, group:, unit:)
        Error(Nil) -> False
      }
  }
}

/// A unit a player may talk to, as the client's click reads it: what its 0x262 gave it
/// and the body its reach and its disposition are judged on.
pub type Talkable {
  Talkable(
    /// The Creature2 row of its 0x262.
    creature_id: Creature2Id,
    /// The Faction2 id its 0x262 gave it.
    faction_id: Int,
    /// The checklist index its 0x262 gave it.
    checklist_index: Int,
    /// Where the unit stands at the time asked.
    place: Place,
    /// Creature2DisplayInfo.hitRadius of its display.
    hit_radius: Float,
    /// False for a creature that died; a static object is never created dead, so an
    /// object is always alive (`opcode.0x262.simple`).
    alive: Bool,
    /// Which player factions the unit is Hostile to.
    hostile_to: Hostile,
  )
}

/// The shown creature or object as a click on it reads it, at monotonic time `now_ms`,
/// or `Error(Nil)` for another player's unit. A static object is alive and never in
/// combat, which the client's click accepts (`0x14047a060`, `0x1403add00`): it checks
/// the unit's life, disposition and range and not its unit type.
pub fn talkable(
  shown shown: Shown,
  now_ms now_ms: Int,
) -> Result(Talkable, Nil) {
  case shown {
    ShownPlayer -> Error(Nil)
    ShownObject(
      creature_id:,
      faction_id:,
      checklist_index:,
      place:,
      hit_radius:,
      hostile_to:,
    ) ->
      Ok(Talkable(
        creature_id:,
        faction_id:,
        checklist_index:,
        place:,
        hit_radius:,
        alive: True,
        hostile_to:,
      ))
    ShownCreature(
      creature_id:,
      faction_id:,
      checklist_index:,
      path:,
      alive:,
      hit_radius:,
      hostile_to:,
      ..,
    ) ->
      Ok(Talkable(
        creature_id:,
        faction_id:,
        checklist_index:,
        place: creature_path.place_at(path:, now_ms:),
        hit_radius:,
        alive:,
        hostile_to:,
      ))
  }
}

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
      ShownPlayer | ShownObject(..) -> Error(Nil)
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
    Ok(ShownPlayer) | Ok(ShownObject(..)) | Error(Nil) -> Error(Nil)
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

/// A creature or object the picture shows, as a place counts it: the unit as the
/// client's group test reads it, its checklist index and where it stands.
pub type Standing {
  Standing(unit: Unit, checklist_index: Int, world_id: Int, x: Float, z: Float)
}

/// The creatures and objects the picture shows and where each stands at monotonic time
/// `now_ms`, in unit id order. Another player's unit is no creature or object, and a
/// unit with no Creature2 row in the tables is not one either (`target_of`).
pub fn standing(
  tables tables: table_store.Tables,
  picture picture: Picture,
  now_ms now_ms: Int,
) -> List(Standing) {
  dict.to_list(picture)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.filter_map(fn(entry) {
    let shown = entry.1
    use #(unit, checklist_index) <- result.try(target_of(tables:, shown:))
    let place = case shown {
      ShownCreature(path:, ..) -> Ok(creature_path.place_at(path:, now_ms:))
      ShownObject(place:, ..) -> Ok(place)
      ShownPlayer -> Error(Nil)
    }
    use place <- result.map(place)
    Standing(
      unit:,
      checklist_index:,
      world_id: start_place.world_id(place),
      x: start_place.x(place),
      z: start_place.z(place),
    )
  })
}

/// The checklist indexes the units' 0x262 carried, by unit id: the creatures and objects
/// the picture shows among them. A type 94 condition reads the struck unit's index.
pub fn checklist_indexes_of(
  picture picture: Picture,
  unit_ids unit_ids: List(Int),
) -> Dict(Int, Int) {
  list.filter_map(unit_ids, fn(unit_id) {
    case dict.get(picture, unit_id) {
      Ok(ShownCreature(checklist_index:, ..))
      | Ok(ShownObject(checklist_index:, ..)) -> Ok(#(unit_id, checklist_index))
      Ok(ShownPlayer) | Error(Nil) -> Error(Nil)
    }
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
    Ok(ShownPlayer) | Ok(ShownObject(..)) | Error(Nil) -> Error(Nil)
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
    Ok(ShownPlayer) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature marked alive or dead by its owner's news, a dead
/// creature holding no state; a unit that is not a shown creature is as it was.
pub fn with_alive(
  picture picture: Picture,
  unit_id unit_id: Int,
  alive alive: Bool,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(..) as creature) ->
      dict.insert(
        picture,
        unit_id,
        ShownCreature(..creature, alive:, held: case alive {
          True -> creature.held
          False -> []
        }),
      )
    Ok(ShownPlayer) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature holding the state its owner's news gave, under the
/// 0x87f's instance id; a unit that is not a shown creature is as it was.
pub fn with_held_applied(
  picture picture: Picture,
  unit_id unit_id: Int,
  state state: CrowdControlState,
  instance_id instance_id: Int,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(held:, ..) as creature) ->
      dict.insert(
        picture,
        unit_id,
        ShownCreature(
          ..creature,
          held: list.append(held, [HeldState(state:, instance_id:)]),
        ),
      )
    Ok(ShownPlayer) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature no longer holding the state of that instance id (the
/// 0x880 names one instance), the creature's other instances kept; a unit that is not a
/// shown creature is as it was.
pub fn with_held_ended(
  picture picture: Picture,
  unit_id unit_id: Int,
  instance_id instance_id: Int,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(held:, ..) as creature) ->
      dict.insert(
        picture,
        unit_id,
        ShownCreature(
          ..creature,
          held: list.filter(held, fn(one) { one.instance_id != instance_id }),
        ),
      )
    Ok(ShownPlayer) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature marked in combat or out of it by its owner's news; a
/// unit that is not a shown creature is as it was.
pub fn with_in_combat(
  picture picture: Picture,
  unit_id unit_id: Int,
  in_combat in_combat: Bool,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(..) as creature) ->
      dict.insert(picture, unit_id, ShownCreature(..creature, in_combat:))
    Ok(ShownPlayer) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}
