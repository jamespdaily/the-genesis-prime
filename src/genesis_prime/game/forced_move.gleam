//// The path a ForcedMove effect (`Spell4Effects.effectType.3`) throws a creature
//// along: a pure rule. The row's columns, two fractions drawn from the caster's
//// connection seed, the creature's place, velocity and radius, the place and radius of
//// the reference unit and the leash circle go in; the path the creature takes goes
//// out, which the creature's fight keeps (genesis_prime/world_map/creature_fight) and
//// sends its viewers as one 0x638 (genesis_prime/game/connection/frames `path_frame`).
////
//// ```
//// cast go ─▶ ForcedMoveStarts (at the go, or at go + delay_time, a cast timer)
////   casting: draws two fractions from the seed, takes the player's place and race radius
////   ─▶ Tell(Creature) ─▶ creature `Thrown(move, draws, reference, struck_at_ms)`
////   creature_fight `Thrown`: path(move, draws, place now, velocity now, radius, reference,
////     Circle(home, leash), now) ─▶ Timed ─▶ 0x638 [kind 0, kind 3 (+ kind 14)] to each viewer
//// ```
////
//// - **The row** is dataBits00, the kind 0 to 15, which is a way and a mover; 01 and 02 the
////   distance's minimum and maximum in metres; 03 the flight time in ms; 04 the gravity;
////   05 the flags (1 the reference unit is the effect's caster, 2 no stopping short by the
////   radii, 4 face the reference unit, 8 face along the move, 0x10 the arc); 06 the apex
////   height; 07 the turn angle, which the client uses only when the reference unit is the
////   moved unit; 08 the turn rate; 09, which the client does not read
////   (`Spell4Effects.effectType.3`). A kind above 15 fails the load (`UnknownKind`).
//// - **The ways** (`Spell4Effects.effectType.3.direction`): kinds 0, 3 and 11 move toward the
////   reference unit, 1, 4 and 12 away from it along the full 3D line with no radius cut,
////   2, 5 and 13 at the drawn angle on the ground plane, 6, 7 and 14 along the creature's
////   velocity (a creature that stands does not move), and 8, 9, 10 and 15 to the reference
////   unit's place less the radii and the distance.
//// - **The movers** (`Spell4Effects.effectType.3.other_unit.command_shape`): kinds 0, 1, 2, 7
////   and 8 set the creature at once (`Standing`, or one `Timed` point when it also turns); 3, 4,
////   5, 6, 9 and 10 fly it over dataBits03 ms; 11 to 15 launch it, which for a creature is the
////   same timed path built from the ballistic flight. A move with no time goes at once: a
////   kind 3 path whose span is under 1 ms samples its first point (`0x140783e10`).
//// - **The arc** is on when the gravity is not 0, flags & 0x10 is set or the kind is 10
////   (`0x14039fff0`). It has 9 points, 8 segments spread evenly in time, the server's choice, since
////   the client draws straight lines between the points of a path and checks none of them.
//// - **The distance** is `min + fraction * (max - min)`: the client draws it with
////   RandomFloatInRange, and the caster's connection draws the fraction from its seed, so the
////   creature keeps no random state.
//// - **The only clip** is the leash circle `creature_path.toward` clips a chase at.
////
//// Gaps, each stated where it is enforced:
////
//// - **No ground or walls.** The server holds no terrain, so a thrown creature can end inside a
////   wall or in the air past a ledge: "A thrown creature stops at walls and lands on the ground
////   the zone's map shows" is issue 824.
//// - **No turn rate and no PositionSwitch.** dataBits08 feeds the client's kind 20 timed turn,
////   which is not decoded, so the creature does not spin; PositionSwitch has no data in the
////   client and moves a player. Both are issue 825.
////
//// What happens at each failure point of a throw:
////
//// | Point | What happens |
//// |---|---|
//// | the cast's `ForcedMoveStarts` timer fires | the cast tells the creature of the life the go struck: no move is made if the connection is gone, and a late timer throws from where the creature is then |
//// | the tell is in flight and the creature ended | the creature registry finds no process and drops the tell |
//// | the tell reaches a creature that has stood again since `struck_at_ms`, or is dead | it is dropped |
//// | the tell reaches a creature that walks home | the fight drops it: a leashed creature takes no strike either |
//// | the tell reaches a creature that does not run (run speed 0) | the fight drops it |
//// | the creature crashes in flight | its map's watch ends, every viewer is sent `Gone` and the spawn starts again at home |
//// | `FlightEnds` fires of an older generation | the fight finds no flight of that generation and does nothing |
//// | `FlightEnds` fires while a state holds the creature | no chase starts: the state's end resumes it |
//// | a state's end fires in flight | the creature stays still until `FlightEnds` |
//// | the creature dies in flight | `FlightEnds` is cancelled, the path is kept and the corpse lies at the landing |
//// | a viewer arrives in flight, or after it | it is sent the rest of the path, or the 0x262 at the landing |

import genesis_prime/game/start_place.{type Place}
import genesis_prime/table/spell4_effects
import genesis_prime/world_map/creature_path.{type Circle, type Path}

/// Where the move goes relative to the reference unit (`Spell4Effects.effectType.3.direction`).
pub type Way {
  /// Kinds 0, 3 and 11: the distance along the line to the reference unit, capped at its place
  /// and shortened by the two radii unless flags & 2.
  Toward
  /// Kinds 1, 4 and 12: from the reference unit through the creature, the distance further.
  Away
  /// Kinds 2, 5 and 13: the distance at the drawn angle on the ground plane.
  Random
  /// Kinds 6, 7 and 14: the creature's velocity times the distance.
  AlongVelocity
  /// Kinds 8, 9, 10 and 15: the reference unit's place, shortened by the two radii plus the distance.
  ToUnit
}

/// How the creature gets there (`Spell4Effects.effectType.3.other_unit.command_shape`).
pub type Mover {
  /// Kinds 0, 1, 2, 7 and 8.
  AtOnce
  /// Kinds 3, 4, 5, 6, 9 and 10.
  Flight
  /// Kinds 11 to 15.
  Launch
}

/// A type 3 row's move, decoded when the plan loads.
pub type Move {
  Move(
    way: Way,
    mover: Mover,
    min_distance: Float,
    max_distance: Float,
    flight_ms: Int,
    gravity: Float,
    flags: Int,
    height: Float,
  )
}

/// The two fractions in [0, 1) the caster's connection draws from its seed
/// (genesis_prime/random `fraction`): the first picks the distance between the row's
/// minimum and maximum, the second the angle of a random way, a turn of that fraction.
pub type Draws {
  Draws(distance: Float, angle: Float)
}

/// The unit the move is measured from: where the casting player stands when the go
/// reaches the creature, and its race's hit radius.
pub type Reference {
  Reference(place: Place, radius: Float)
}

/// Why a row is no move.
pub type RowError {
  /// dataBits00 is not a kind from 0 to 15, or a float column holds no finite float.
  UnknownKind(effect_id: Int, kind: Int)
}

/// The move a type 3 row asks for.
pub fn of_row(
  row _row: spell4_effects.Spell4Effects,
) -> Result(Move, RowError) {
  panic as "shape: decoding a row is built in the step's code commit"
}

/// The path the creature takes from `from` at `now_ms`, running at `velocity` (units a
/// second) with hit radius `radius`: `Standing` at the destination for a move that goes at
/// once, one `Timed` point when it also turns, and else `Timed` points from `from` at `now_ms`
/// to the destination (clipped at the leash circle as `creature_path.toward` clips) at `now_ms` plus the
/// flight's milliseconds, with the arc's points between. A creature that is not moved
/// (a velocity way of a creature that stands, an away way from its own place) gets
/// `Standing(from)`.
pub fn path(
  move _move: Move,
  draws _draws: Draws,
  from _from: Place,
  velocity _velocity: #(Float, Float, Float),
  radius _radius: Float,
  reference _reference: Reference,
  circle _circle: Circle,
  now_ms _now_ms: Int,
) -> Path {
  panic as "shape: the path of a move is built in the step's code commit"
}
