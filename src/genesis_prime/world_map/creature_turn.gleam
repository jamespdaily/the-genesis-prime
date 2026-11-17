//// How a creature that fights is turned: the rotation its viewers' clients hold for it.
//// The client never turns a creature by itself (`creature.facing`): it faces where the last
//// rotation command of its 0x262 or 0x638 turned it, and a position path (kind 4, or the
//// position of kind 2 and 3) leaves the rotation as it was.
////
//// ```
//// creature_fight: Face ─▶ CreatureFaces news ─▶ viewer's 0x638 [kind 0, kind 18, kind 19 or kind 14]
//// creature and viewer: yaw_of(face, from, ..) ─▶ the yaw the client shows, for a gate's arc
//// ```
////
//// - **`Unit`** is kind 18: the client keeps the unit facing another unit every update, finding
////   the unit by its id; a unit it does not find, or one closer than 1e-5, leaves the facing
////   where it was (`movement_command.kind_18`, `0x140782cd0`).
//// - **`Point`** is kind 19, the same toward a fixed point (`movement_command.kind_19`).
//// - **`Fixed`** is kind 14: one yaw, pitch and roll until the next rotation command
////   (`movement_command.kind_14`).
//// - **The yaw toward a target** is the angle `area.bearing` gives for the yaw that faces it
////   (`movement_command.kind_14.facing`), and the facing it was when the target is on the
////   unit's own ground point (the client's too-close case). The client blends a kind 18 or 19
////   over half a second (`0x140715c00`); the server takes the turn as done at once, which
////   makes its arcs exact outside that half second.

import genesis_prime/game/area
import genesis_prime/game/start_place.{type Facing, type Place}

/// What a creature's rotation is held to.
pub type Face {
  /// Facing the unit with this id, wherever it goes.
  Unit(unit_id: Int)
  /// Facing the point.
  Point(place: Place)
  /// Facing one way, until a later rotation command.
  Fixed(facing: Facing)
}

/// The facing of a unit at `from` that faces `target`, keeping `kept` when the target is on
/// its own ground point.
pub fn toward(
  from from: Place,
  target target: Place,
  kept kept: Facing,
) -> Facing {
  let at = area.point_of(place: from)
  let aim = area.point_of(place: target)
  case at == aim {
    True -> kept
    False ->
      start_place.Facing(
        ..kept,
        yaw: area.bearing(from: at, target: aim, yaw: 0.0),
      )
  }
}
