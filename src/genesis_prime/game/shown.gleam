//// The units a player's client shows, as its connection knows them: the picture
//// the connection selects a go's targets from. It holds what a selection needs of
//// each unit and nothing the unit's owner decides.
////
//// ```
//// the creature's 0x262 news ─▶ shown(unit, ShownCreature(spawn id, creature id, Standing(place), life, alive, hit radius, attackable, hostile to))
//// its CreatureMoved news   ─▶ path changed          its CreatureFaces news ─▶ face changed
//// its Health and Died news ─▶ alive changed (a player's: and its health)        its 0x355 ─▶ the unit is no longer shown
//// its CombatState news     ─▶ in combat changed
//// candidates(picture, faction, caster, now) ─▶ the alive foes at place_at(path, now), as geometry's
////                                              candidates (genesis_prime/shared/area)
//// ally_candidates(picture, caster)          ─▶ the alive Friendly players with a place and the health
////                                              each misses, as candidates
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
////   (genesis_prime/shared/creature_path `place_at`), by the same function the
////   creature reads its own place with.
//// - **A creature's pose** (`pose_of`) is that place's ground point with the yaw its client
////   shows: the yaw of its 0x262 or of the path that turned it, or what its `CreatureFaces` news
////   set, so a position condition judges a creature by what its client shows
////   (`creature.facing`: kind 4 paths move a creature without turning it).
//// - **A strike's centre on another unit** (`strike_centre_of`) is a creature's pose, and for a
////   player the ground point of its place with no facing: the stored place carries the
////   viewer's own facing, and no message tells the player's.
//// - **A creature that faces a unit standing on its own ground point** keeps the yaw it showed
////   at the last news or move before (`with_resolved`, `ShownCreature.faced_yaw`).
//// - **An ally** is another player of the picture whose disposition toward the caster is
////   Friendly (`GetUnitDispositionTo` 0x14045a950), alive and placed (`ally_candidates`): the
////   units an area that finds the caster's allies selects from. It carries the health it
////   misses, its copy's maximum less its health (genesis_prime/game/player_state).
//// - **Another player's unit** keeps what a press at it judges (genesis_prime/game/player_state):
////   its life, combat, crowd-control states and the place its last position command gave
////   (`with_player_at`), changed by the news the viewer takes; the creatures that face it
////   read that place's ground point.
//// - **A creature's life** is the number of the map's watch it was started under,
////   which is part of its address (genesis_prime/step `Creature`).

import genesis_prime/game/held_state.{type HeldState}
import genesis_prime/game/player_state.{type PlayerState, PlayerState}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/target_group.{type Unit, Unit}
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/shared/area.{
  type Candidate, type Point, type Pose, Candidate,
}
import genesis_prime/shared/creature_combat.{type Attackable, type Hostile}
import genesis_prime/shared/creature_path.{type Path}
import genesis_prime/shared/creature_turn.{type Face}
import genesis_prime/shared/faction_level
import genesis_prime/shared/prerequisite.{
  type FirstUnit, NonPlayer, OtherPlayer, TheChecker,
}
import genesis_prime/table/creature2
import genesis_prime/table/id.{type Creature2Id, Faction2Id}
import genesis_prime/table/loader/store as table_store
import genesis_prime/world_map/spawn
import genesis_prime/world_map/spawn_id.{type SpawnId}
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

/// The player faction of a caster, which picks the faction a creature may be
/// attacked by.
pub type PlayerFaction {
  Exile
  Dominion
}

/// A unit the client shows.
pub type Shown {
  /// Another player's unit, which no area strikes, with what a press at it judges of it
  /// (genesis_prime/game/player_state). Its place is where its last position command put
  /// it (none before one), whose ground point the yaw of a creature that faces it reads
  /// (`pose_of`).
  ShownPlayer(state: PlayerState)
  /// A static object the map told of (genesis_prime/world_map/static_object),
  /// which has no fight state, so no area strikes it. It holds what the
  /// client's range check of a right-click reads of it (`opcode.0x97.range`).
  ShownObject(
    /// The spawn the object stands at: what a quest objective remembers a use of it by.
    spawn_id: SpawnId,
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
    /// The spawn the creature was started at.
    spawn_id: SpawnId,
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
    /// Whether a player's area may pick the creature (`creature_combat.Combat.area_pickable`):
    /// an area picks no creature that is not.
    area_pickable: Bool,
    /// True from the creature's CombatState news that it entered combat until the one
    /// that it left it; the client gives a creature in combat no click
    /// (`PickInteractionKind`, `0x14047a060`).
    in_combat: Bool,
    /// The crowd-control states the creature holds as its viewer's client was told
    /// (0x87f without a later 0x880), which the target gate of a press reads.
    held: List(HeldState),
    /// The unit states the creature holds as its owner's news told (`UnitStateHeld` without
    /// a later `UnitStateEnded`): no frame carries them, so only the press's refusal reads
    /// them (genesis_prime/game/cast/press `unit_state_refusal`).
    unit_states: List(HeldUnitState),
    /// What the rotation of the creature's client is held to by the creature's own news
    /// (`CreatureFaces`): none from its 0x262 and after a path that turns it
    /// (`creature_path.Timed` with `turned_to`), which replaces the rotation the face held.
    face: Option(Face),
    /// The yaw the creature's client held at the last news before the present (`with_resolved`),
    /// which it keeps when the unit or point it faces is on the creature's own ground point or
    /// the unit is not found (`movement_command.kind_18`): none until such news and after a
    /// path that turns the creature; a fixed rotation sets its own yaw.
    faced_yaw: Option(Float),
  )
}

/// A unit state a shown creature holds (genesis_prime/shared/unit_state), with the `number`
/// its creature gave the hold, which the news that ends it names.
pub type HeldUnitState {
  HeldUnitState(state: Int, number: Int)
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
    ShownPlayer(..) -> Error(Nil)
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

/// The spawn of a shown creature or object, or `Error(Nil)` for another player's unit,
/// which stands at none.
pub fn spawn_of(shown shown: Shown) -> Result(SpawnId, Nil) {
  case shown {
    ShownPlayer(..) -> Error(Nil)
    ShownObject(spawn_id:, ..) | ShownCreature(spawn_id:, ..) -> Ok(spawn_id)
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
    ShownPlayer(..) -> Error(Nil)
    ShownObject(
      creature_id:,
      faction_id:,
      checklist_index:,
      place:,
      hit_radius:,
      hostile_to:,
      ..,
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
/// `caster_unit_id` and never a creature an area may not pick (`area_pickable`).
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
      ShownPlayer(..) | ShownObject(..) -> Error(Nil)
      ShownCreature(path:, alive:, hit_radius:, attackable:, area_pickable:, ..) ->
        case
          alive
          && area_pickable
          && unit_id != caster_unit_id
          && may_attack(faction:, attackable:)
        {
          True ->
            Ok(Candidate(
              unit_id:,
              at: area.point_of(creature_path.place_at(path:, now_ms:)),
              hit_radius:,
              missing_health: 0,
            ))
          False -> Error(Nil)
        }
    }
  })
}

/// The alive players of the picture whose disposition toward the caster is Friendly
/// (`GetUnitDispositionTo` 0x14045a950), as candidates for an area that finds the caster's
/// allies, in unit id order: never the caster `caster_unit_id`, a creature, or a player with
/// no place yet. A player stands where its last position command put it, and misses its
/// maximum health less its health (`player_state.missing_health`). An area whose
/// valid targets hold no bit 8 strikes only the living (`Spell4ValidTargets.targetBitmask`).
pub fn ally_candidates(
  picture picture: Picture,
  caster_unit_id caster_unit_id: Int,
) -> List(Candidate) {
  dict.to_list(picture)
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.filter_map(fn(entry) {
    let #(unit_id, shown) = entry
    case shown {
      ShownCreature(..) | ShownObject(..) -> Error(Nil)
      ShownPlayer(
        state: PlayerState(
          alive: True,
          disposition: faction_level.Friendly,
          place: Some(place),
          ..,
        ) as state,
      )
        if unit_id != caster_unit_id
      ->
        Ok(Candidate(
          unit_id:,
          at: area.point_of(place),
          hit_radius: state.hit_radius,
          missing_health: player_state.missing_health(state:),
        ))
      ShownPlayer(..) -> Error(Nil)
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
    Ok(ShownPlayer(..)) | Ok(ShownObject(..)) | Error(Nil) -> Error(Nil)
  }
}

/// What the creature's rotation is held to by its owner's `CreatureFaces` news, or none for a
/// unit that is not a shown creature, a creature no news has turned, and one a path that
/// turned it has since set (`with_path`).
pub fn face_of(picture picture: Picture, unit_id unit_id: Int) -> Option(Face) {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(face:, ..)) -> face
    Ok(ShownPlayer(..)) | Ok(ShownObject(..)) | Error(Nil) -> None
  }
}

/// The viewer's own unit and where it stands, which a creature that faces the viewer is
/// turned toward.
pub type Viewer {
  Viewer(unit_id: Int, place: Place)
}

/// The ground point and yaw of a shown creature at monotonic time `now_ms`, or `Error(Nil)`
/// for a unit that is not shown or not a creature: where its path puts it, facing as its
/// client shows it. The client holds the yaw of the creature's 0x262 until a rotation command
/// replaces it (`creature.facing`): a path of kind 4 leaves it, a path that turns it
/// (`Timed` with `turned_to`) sets it, and the creature's own `CreatureFaces` news sets it
/// to a fixed yaw or keeps it toward a unit or a point (`creature_turn`). A creature that
/// faces a unit has the bearing to that unit's ground point: the viewer's own unit at its
/// place, another player's at the point its last position command gave; a unit the picture
/// has no point for leaves the yaw as it was, as the client leaves it for a unit it does not
/// find (`movement_command.kind_18`). This is the one place a shown creature's facing is read.
pub fn pose_of(
  picture picture: Picture,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
  viewer viewer: Viewer,
) -> Result(Pose, Nil) {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(path:, face:, faced_yaw:, ..)) -> {
      let place = creature_path.place_at(path:, now_ms:)
      let body = area.pose_of(place:)
      let held = case faced_yaw {
        Some(yaw) -> area.Pose(..body, yaw:)
        None -> body
      }
      let aim = case face {
        None -> Error(Nil)
        Some(creature_turn.Fixed(facing:))
        | Some(creature_turn.Home(facing:)) -> Ok(Fixed(facing.yaw))
        Some(creature_turn.Point(place: point)) ->
          Ok(Toward(area.point_of(place: point)))
        Some(creature_turn.Unit(unit_id: faced)) ->
          case faced == viewer.unit_id, dict.get(picture, faced) {
            True, _ -> Ok(Toward(area.point_of(place: viewer.place)))
            False, Ok(ShownPlayer(state: PlayerState(place: Some(place), ..)))
            -> Ok(Toward(area.point_of(place:)))
            False, _ -> Error(Nil)
          }
      }
      Ok(case aim {
        Ok(Fixed(yaw)) -> area.Pose(..body, yaw:)
        Ok(Toward(point)) ->
          case point == body.at {
            True -> held
            False ->
              area.Pose(
                ..body,
                yaw: area.bearing(from: body.at, target: point, yaw: 0.0),
              )
          }
        Error(Nil) -> held
      })
    }
    Ok(ShownPlayer(..)) | Ok(ShownObject(..)) | Error(Nil) -> Error(Nil)
  }
}

/// Where a strike centres an area on another unit: a creature at its pose (`pose_of`), a
/// player at the place its last position command gave with no facing (yaw 0.0), and no
/// centre for an object, a player with no place yet or a unit the picture does not show. A
/// player's stored place carries the viewer's own facing (`viewers.player_place` moves the
/// viewer's place), not the player's, which the server does not hold, so a shape that reads a
/// facing is not built for a player (`spell_area.start_placed`). `pose_of` stays creature
/// only: the target gates read a position condition on a unit only when it has a pose.
pub fn strike_centre_of(
  picture picture: Picture,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
  viewer viewer: Viewer,
) -> Result(Pose, Nil) {
  case dict.get(picture, unit_id) {
    Ok(ShownPlayer(state: PlayerState(place: Some(place), ..))) ->
      Ok(area.Pose(at: area.point_of(place:), yaw: 0.0))
    Ok(ShownPlayer(..))
    | Ok(ShownCreature(..))
    | Ok(ShownObject(..))
    | Error(Nil) -> pose_of(picture:, unit_id:, now_ms:, viewer:)
  }
}

/// The picture with each creature that faces a unit or a point holding the yaw its client
/// shows now (`pose_of`), as the yaw it keeps when the unit it faces then stands on its own
/// ground point (`ShownCreature.faced_yaw`). The connection calls it before it takes the news or
/// the move that changes where a creature or the unit it faces stands.
pub fn with_resolved(
  picture picture: Picture,
  now_ms now_ms: Int,
  viewer viewer: Viewer,
) -> Picture {
  dict.map_values(picture, fn(unit_id, unit) {
    case unit {
      ShownCreature(face: Some(creature_turn.Unit(..)), ..) as creature
      | ShownCreature(face: Some(creature_turn.Point(..)), ..) as creature ->
        case pose_of(picture:, unit_id:, now_ms:, viewer:) {
          Ok(pose) -> ShownCreature(..creature, faced_yaw: Some(pose.yaw))
          Error(Nil) -> unit
        }
      ShownCreature(..) | ShownPlayer(..) | ShownObject(..) -> unit
    }
  })
}

/// Where a creature's client has it face.
type Aim {
  Fixed(yaw: Float)
  Toward(point: Point)
}

/// The poses of the shown creatures among the units, by unit id; a unit that is not a shown
/// creature has none.
pub fn poses_of(
  picture picture: Picture,
  unit_ids unit_ids: List(Int),
  now_ms now_ms: Int,
  viewer viewer: Viewer,
) -> Dict(Int, Pose) {
  list.filter_map(unit_ids, fn(unit_id) {
    pose_of(picture:, unit_id:, now_ms:, viewer:)
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
      ShownPlayer(..) -> Error(Nil)
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
      Ok(ShownPlayer(..)) | Error(Nil) -> Error(Nil)
    }
  })
  |> dict.from_list
}

/// What each of the units is to a prerequisite that names its first unit, by unit id: the
/// caster's own unit is the checker, a creature or object the picture shows is that
/// Creature2 row, another player is a player. A unit the picture does not hold has no
/// entry, which the check reads as unknown. A type 38 condition reads the Creature2 id.
pub fn first_units_of(
  picture picture: Picture,
  unit_ids unit_ids: List(Int),
  caster_unit caster_unit: Int,
) -> Dict(Int, FirstUnit) {
  list.filter_map(unit_ids, fn(unit_id) {
    case unit_id == caster_unit, dict.get(picture, unit_id) {
      True, _ -> Ok(#(unit_id, TheChecker))
      False, Ok(ShownCreature(creature_id:, ..))
      | False, Ok(ShownObject(creature_id:, ..))
      -> Ok(#(unit_id, NonPlayer(creature2_id: creature_id.value)))
      False, Ok(ShownPlayer(..)) -> Ok(#(unit_id, OtherPlayer))
      False, Error(Nil) -> Error(Nil)
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
    Ok(ShownPlayer(..)) | Ok(ShownObject(..)) | Error(Nil) -> Error(Nil)
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
    Ok(ShownCreature(..) as creature) -> {
      let moved = ShownCreature(..creature, path:)
      let moved = case path {
        creature_path.Timed(turned_to: Some(_), ..) ->
          ShownCreature(..moved, face: None, faced_yaw: None)
        creature_path.Timed(..)
        | creature_path.Standing(..)
        | creature_path.Running(..) -> moved
      }
      dict.insert(picture, unit_id, moved)
    }
    Ok(ShownPlayer(..)) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature's rotation held to `face` by its owner's news; a unit that
/// is not a shown creature is as it was.
pub fn with_face(
  picture picture: Picture,
  unit_id unit_id: Int,
  face face: Face,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(..) as creature) -> {
      let faced_yaw = case face {
        creature_turn.Fixed(facing:) | creature_turn.Home(facing:) ->
          Some(facing.yaw)
        creature_turn.Unit(..) | creature_turn.Point(..) -> creature.faced_yaw
      }
      dict.insert(
        picture,
        unit_id,
        ShownCreature(..creature, face: Some(face), faced_yaw:),
      )
    }
    Ok(ShownPlayer(..)) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the player's unit at `place` by a position command of its movement; a
/// unit that is not a shown player is as it was.
pub fn with_player_at(
  picture picture: Picture,
  unit_id unit_id: Int,
  place place: Place,
) -> Picture {
  with_player_state(picture:, unit_id:, change: fn(state) {
    PlayerState(..state, place: Some(place))
  })
}

/// The picture with the shown player's state changed; a unit that is not a shown player is
/// as it was.
fn with_player_state(
  picture picture: Picture,
  unit_id unit_id: Int,
  change change: fn(PlayerState) -> PlayerState,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownPlayer(state:)) ->
      dict.insert(picture, unit_id, ShownPlayer(state: change(state)))
    Ok(ShownCreature(..)) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the shown player's health set by its owner's `Health` news and the player
/// alive or dead by the news's dead bit; a creature, an object or a unit not shown is as it
/// was (a creature's life is its own news's).
pub fn with_player_health(
  picture picture: Picture,
  unit_id unit_id: Int,
  health health: Int,
  dead dead: Bool,
) -> Picture {
  with_player_state(picture:, unit_id:, change: fn(state) {
    PlayerState(..state, health:, alive: !dead)
  })
}

/// The picture with the shown player's maximum health set to the Base Health (property 7) the
/// properties of its owner's `PropertiesChanged` news give; one that names none, a creature,
/// an object or a unit not shown is as it was.
pub fn with_base_health(
  picture picture: Picture,
  unit_id unit_id: Int,
  properties properties: List(UnitProperty),
) -> Picture {
  case player_state.base_health_of(properties:) {
    Ok(maximum_health) ->
      with_player_state(picture:, unit_id:, change: fn(state) {
        PlayerState(..state, maximum_health:)
      })
    Error(Nil) -> picture
  }
}

/// The picture with the creature or player marked alive or dead by its owner's news, a dead
/// unit holding no crowd-control or unit state; an object or a unit not shown is as it was.
pub fn with_alive(
  picture picture: Picture,
  unit_id unit_id: Int,
  alive alive: Bool,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownPlayer(state:)) ->
      dict.insert(
        picture,
        unit_id,
        ShownPlayer(
          state: PlayerState(..state, alive:, held: case alive {
            True -> state.held
            False -> []
          }),
        ),
      )
    Ok(ShownCreature(..) as creature) ->
      dict.insert(
        picture,
        unit_id,
        ShownCreature(
          ..creature,
          alive:,
          held: case alive {
            True -> creature.held
            False -> []
          },
          unit_states: case alive {
            True -> creature.unit_states
            False -> []
          },
        ),
      )
    Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature or player holding the state its owner's news gave, under
/// the 0x87f's instance id; an object or a unit not shown is as it was.
pub fn with_held_applied(
  picture picture: Picture,
  unit_id unit_id: Int,
  state state: CrowdControlState,
  instance_id instance_id: Int,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownPlayer(..)) ->
      with_player_state(picture:, unit_id:, change: fn(player) {
        PlayerState(
          ..player,
          held: held_state.applied(held: player.held, state:, instance_id:),
        )
      })
    Ok(ShownCreature(held:, ..) as creature) ->
      dict.insert(
        picture,
        unit_id,
        ShownCreature(
          ..creature,
          held: held_state.applied(held:, state:, instance_id:),
        ),
      )
    Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature holding the unit state its owner's news gave, under the
/// creature's `number` for the hold, after the holds it has; a unit that is not a shown
/// creature is as it was.
pub fn with_unit_state_held(
  picture picture: Picture,
  unit_id unit_id: Int,
  state state: Int,
  number number: Int,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(unit_states:, ..) as creature) ->
      dict.insert(
        picture,
        unit_id,
        ShownCreature(
          ..creature,
          unit_states: list.append(unit_states, [
            HeldUnitState(state:, number:),
          ]),
        ),
      )
    Ok(ShownPlayer(..)) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature no longer holding its unit state of that `number`, its
/// other holds kept; a unit that is not a shown creature is as it was.
pub fn with_unit_state_ended(
  picture picture: Picture,
  unit_id unit_id: Int,
  number number: Int,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(unit_states:, ..) as creature) ->
      dict.insert(
        picture,
        unit_id,
        ShownCreature(
          ..creature,
          unit_states: list.filter(unit_states, fn(held) {
            held.number != number
          }),
        ),
      )
    Ok(ShownPlayer(..)) | Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// Whether the unit shown holds a state under that instance id: the 0x87f that gave it was
/// written to this client and no 0x880 has ended it. A unit not shown or an object holds none.
pub fn holds_instance(
  picture picture: Picture,
  unit_id unit_id: Int,
  instance_id instance_id: Int,
) -> Bool {
  let held = case dict.get(picture, unit_id) {
    Ok(ShownPlayer(state:)) -> state.held
    Ok(ShownCreature(held:, ..)) -> held
    Ok(ShownObject(..)) | Error(Nil) -> []
  }
  list.any(held, fn(one) { one.instance_id == instance_id })
}

/// The picture with the creature or player no longer holding the state of that instance id
/// (the 0x880 names one instance), its other instances kept; an object or a unit not shown
/// is as it was.
pub fn with_held_ended(
  picture picture: Picture,
  unit_id unit_id: Int,
  instance_id instance_id: Int,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownPlayer(..)) ->
      with_player_state(picture:, unit_id:, change: fn(player) {
        PlayerState(
          ..player,
          held: held_state.ended(held: player.held, instance_id:),
        )
      })
    Ok(ShownCreature(held:, ..) as creature) ->
      dict.insert(
        picture,
        unit_id,
        ShownCreature(..creature, held: held_state.ended(held:, instance_id:)),
      )
    Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}

/// The picture with the creature or player marked in combat or out of it by its owner's
/// news; an object or a unit not shown is as it was.
pub fn with_in_combat(
  picture picture: Picture,
  unit_id unit_id: Int,
  in_combat in_combat: Bool,
) -> Picture {
  case dict.get(picture, unit_id) {
    Ok(ShownCreature(..) as creature) ->
      dict.insert(picture, unit_id, ShownCreature(..creature, in_combat:))
    Ok(ShownPlayer(..)) ->
      with_player_state(picture:, unit_id:, change: fn(player) {
        PlayerState(..player, in_combat:)
      })
    Ok(ShownObject(..)) | Error(Nil) -> picture
  }
}
