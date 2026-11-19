//// The path a ForcedMove effect (`Spell4Effects.effectType.3`) throws a creature
//// along: a pure rule. The row's columns, two fractions drawn from the caster's
//// connection seed, the creature's place, velocity and radius, the place and radius of
//// the reference unit and the leash circle go in; the path the creature takes goes
//// out, which the creature's fight keeps (genesis_prime/world_map/creature_fight) and
//// sends its viewers as one 0x638 (genesis_prime/game/connection/frames `path_frame`).
////
//// ```
//// plan: a ForcedMove row aimed at other units (targetFlags 2, 4 or 6) is a `spell_plan.StruckMove`
////   (`of_row` decodes its columns when the plan loads; a target apply prerequisite fails the load)
//// cast go, for each creature the go Hit in the row's aim (`cast_control.struck_moves_armed`):
////   delay 0: `ForcedMoveStarts(unit_id, life, struck_at_ms, move)` in the go's step
////   else:    `Due.ForcedMoveStart(on, move, struck_at_ms)`, a cast timer at go + delay_time,
////            which fires `ForcedMoveStarts`; the end of the cast's node on that creature cancels it
////            (`creatures_ended`), as it cancels a modifier's start
//// casting (the connection) carries out `ForcedMoveStarts`:
////   `client_connection.draw(link, draw_bytes)` ─▶ `draws_of` the two fractions,
////   the player's place now and race radius ─▶ `Reference`
////   ─▶ Tell(Creature) ─▶ creature `Thrown(move, draws, reference, struck_at_ms)`
//// creature_fight `Thrown`: path(move, draws, place now, velocity now, radius, reference,
////   Circle(home, leash), now) ─▶ Timed ─▶ 0x638 [kind 0, kind 3 (+ kind 14)] to each viewer
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
////   the zone's map shows" is part of issue 1010 ("The server knows each zone's ground and walls").
//// - **No turn rate and no PositionSwitch.** dataBits08 feeds the client's kind 20 timed turn,
////   which is not decoded, so the creature does not spin; PositionSwitch has no data in the
////   client and moves a player. Both are issue 825.
////
//// What happens at each failure point of a throw:
////
//// | Point | What happens |
//// |---|---|
//// | the `ForcedMoveStart` timer fires | the cast tells the creature of the life the go struck: a node of the cast on it that ended first has cancelled the timer, as it cancels a modifier's start; a late timer throws from where the creature is then |
//// | the connection is gone before the timer fires | the timers of the cast go with the connection: nothing is drawn, told or thrown |
//// | the go struck a creature that is then dead or has stood again | the creature drops the tell (`struck_at_ms`) |
//// | the tell is in flight and the creature ended | the creature registry finds no process and drops the tell |
//// | the tell reaches a creature that walks home | the fight drops it: a leashed creature takes no strike either |
//// | the tell reaches a creature that does not run (run speed 0) | the fight drops it |
//// | the creature crashes in flight | its map's watch ends, every viewer is sent `Gone` and the spawn starts again at home |
//// | `FlightEnds` fires of an older generation | the fight finds no flight of that generation and does nothing |
//// | `FlightEnds` fires while a state holds the creature | no chase starts: the state's end resumes it |
//// | a state's end fires in flight | the creature stays still until `FlightEnds` |
//// | the creature dies in flight | `FlightEnds` is cancelled, the path is kept and the corpse lies at the landing |
//// | a viewer arrives in flight, or after it | it is sent the rest of the path, or the 0x262 at the landing |

import genesis_prime/game/start_place.{type Facing, type Place}
import genesis_prime/message/float32
import genesis_prime/random
import genesis_prime/table/spell4_effects
import genesis_prime/world_map/creature_path.{type Circle, type Path}
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam_community/maths

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

/// A type 3 row's move, decoded when the plan loads. Kind 10 always arcs, which `of_row`
/// writes as flag 0x10 in `flags`.
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

/// A throw ready for a creature to carry out: the `move` a row asks for, the `draws` the
/// caster's connection took from its seed for it and the `reference` unit it is measured
/// from.
pub type Throw {
  Throw(move: Move, draws: Draws, reference: Reference)
}

/// Why a row is no move.
pub type RowError {
  /// dataBits00 is not a kind from 0 to 15.
  UnknownKind(effect_id: Int, kind: Int)
  /// A float column (dataBits01, 02, 04, 06) holds infinity or no number.
  NotAFloat(effect_id: Int, column: String)
}

/// The bytes a throw draws from the caster's connection seed: two 32-bit words, one for
/// each fraction of `Draws`. The connection draws them when `ForcedMoveStarts` is carried
/// out, so a delayed throw draws at its own time and no rule keeps random state.
pub const draw_bytes = 8

/// The flag of dataBits05 that arcs the flight (`0x1405d6e12`).
const arc_flag = 0x10

/// The flag that stops the move short by no radius.
const no_radius_flag = 2

/// The flag that faces the creature toward the reference unit.
const face_reference_flag = 4

/// The flag that faces the creature along its move.
const face_move_flag = 8

/// The two fractions of the `draw_bytes` bytes drawn: each big-endian 32-bit word as the
/// fraction below 1 it is (genesis_prime/random `fraction`), the distance's first.
pub fn draws_of(bytes bytes: BitArray) -> Draws {
  let assert <<distance:size(32), angle:size(32), _:bits>> = bytes
    as "the connection draws draw_bytes bytes"
  Draws(distance: random.fraction(distance), angle: random.fraction(angle))
}

/// The move a type 3 row asks for.
pub fn of_row(row row: spell4_effects.Spell4Effects) -> Result(Move, RowError) {
  use #(way, mover) <- result.try(case row.data_bits00 {
    0 | 1 | 2 | 7 | 8 -> Ok(#(kind_way(kind: row.data_bits00), AtOnce))
    3 | 4 | 5 | 6 | 9 | 10 -> Ok(#(kind_way(kind: row.data_bits00), Flight))
    11 | 12 | 13 | 14 | 15 -> Ok(#(kind_way(kind: row.data_bits00), Launch))
    kind -> Error(UnknownKind(effect_id: row.id, kind:))
  })
  use min_distance <- result.try(float_of(row:, column: "dataBits01"))
  use max_distance <- result.try(float_of(row:, column: "dataBits02"))
  use gravity <- result.try(float_of(row:, column: "dataBits04"))
  use height <- result.try(float_of(row:, column: "dataBits06"))
  let flags = case row.data_bits00 {
    10 -> int.bitwise_or(row.data_bits05, arc_flag)
    _ -> row.data_bits05
  }
  Ok(Move(
    way:,
    mover:,
    min_distance:,
    max_distance:,
    flight_ms: row.data_bits03,
    gravity:,
    flags:,
    height:,
  ))
}

fn kind_way(kind kind: Int) -> Way {
  case kind {
    0 | 3 | 11 -> Toward
    1 | 4 | 12 -> Away
    2 | 5 | 13 -> Random
    6 | 7 | 14 -> AlongVelocity
    _ -> ToUnit
  }
}

fn float_of(
  row row: spell4_effects.Spell4Effects,
  column column: String,
) -> Result(Float, RowError) {
  let number = case column {
    "dataBits01" -> row.data_bits01
    "dataBits02" -> row.data_bits02
    "dataBits04" -> row.data_bits04
    _ -> row.data_bits06
  }
  float32.of_column(number:)
  |> result.replace_error(NotAFloat(effect_id: row.id, column:))
}

/// The path the creature takes from `from` at `now_ms`, running at `velocity` (units a
/// second) with hit radius `radius`: `Standing` at the destination for a move that goes at
/// once, one `Timed` point when it also turns, and else `Timed` points from `from` at `now_ms`
/// to the destination (clipped at the leash circle as `creature_path.toward` clips) at `now_ms` plus the
/// flight's milliseconds, with the arc's points between. A creature that is not moved
/// (a velocity way of a creature that stands, an away way from its own place) gets
/// `Standing(from)`.
pub fn path(
  move move: Move,
  draws draws: Draws,
  from from: Place,
  velocity velocity: #(Float, Float, Float),
  radius radius: Float,
  reference reference: Reference,
  circle circle: Circle,
  now_ms now_ms: Int,
) -> Path {
  let distance =
    move.min_distance
    +. draws.distance
    *. { move.max_distance -. move.min_distance }
  let wanted =
    destination(move:, draws:, distance:, from:, velocity:, radius:, reference:)
  let end = creature_path.clipped(from:, to: wanted, circle:)
  use <- bool.guard(
    when: creature_path.distance(from:, to: end) <=. 0.0,
    return: creature_path.Standing(at: from),
  )
  let turn = turn_of(move:, from:, end:, reference:)
  let arcs = arc_on(move:)
  let lift = case arcs {
    True -> arc_height(move:)
    False -> 0.0
  }
  let span = case move.mover, arcs {
    AtOnce, _ -> 0
    Launch, True ->
      float.round(2000.0 *. result.unwrap(float.square_root(lift /. 16.0), 0.0))
    Flight, _ | Launch, False -> move.flight_ms
  }
  case span < 1 {
    True ->
      case turn {
        None -> creature_path.Standing(at: end)
        Some(_) ->
          creature_path.Timed(first: #(now_ms, end), rest: [], turned_to: turn)
      }
    False ->
      creature_path.Timed(
        first: #(now_ms, from),
        rest: points(from:, end:, lift:, span:, now_ms:),
        turned_to: turn,
      )
  }
}

/// Whether the flight arcs: gravity, flag 0x10 (which `of_row` also sets for kind 10).
fn arc_on(move move: Move) -> Bool {
  move.gravity != 0.0 || int.bitwise_and(move.flags, arc_flag) != 0
}

/// The apex height of the arc: dataBits06, or the gravity's `g t^2 / 8` over the flight,
/// and at least 2 metres.
fn arc_height(move move: Move) -> Float {
  let wanted = case move.height >. 0.0 {
    True -> move.height
    False -> {
      let seconds = int.to_float(move.flight_ms) /. 1000.0
      move.gravity *. seconds *. seconds /. 8.0
    }
  }
  float.max(wanted, 2.0)
}

/// The points after the first: the end alone for a flight with no arc, else the arc's
/// nine points of eight segments, spread evenly in time, whose height above the straight
/// line is `4 h s (1 - s)` for the fraction `s` of the way.
fn points(
  from from: Place,
  end end: Place,
  lift lift: Float,
  span span: Int,
  now_ms now_ms: Int,
) -> List(#(Int, Place)) {
  case lift <=. 0.0 {
    True -> [#(now_ms + span, end)]
    False ->
      list.index_map(list.repeat(Nil, arc_segments), fn(_, index) { index + 1 })
      |> list.map(fn(index) {
        let fraction = int.to_float(index) /. int.to_float(arc_segments)
        let line = creature_path.along(from:, to: end, fraction:)
        #(
          now_ms + span * index / arc_segments,
          start_place.moved(
            place: line,
            x: start_place.x(line),
            y: start_place.y(line)
              +. 4.0
              *. lift
              *. fraction
              *. { 1.0 -. fraction },
            z: start_place.z(line),
          ),
        )
      })
  }
}

const arc_segments = 8

/// Where the move ends before the leash circle clips it, in three dimensions.
fn destination(
  move move: Move,
  draws draws: Draws,
  distance distance: Float,
  from from: Place,
  velocity velocity: #(Float, Float, Float),
  radius radius: Float,
  reference reference: Reference,
) -> Place {
  let radii = case int.bitwise_and(move.flags, no_radius_flag) {
    0 -> radius +. reference.radius
    _ -> 0.0
  }
  let gap = creature_path.distance(from:, to: reference.place)
  case move.way {
    Toward ->
      toward_reference(
        from:,
        reference:,
        gap:,
        travel: float.max(0.0, float.min(distance, gap) -. radii),
      )
    ToUnit ->
      toward_reference(
        from:,
        reference:,
        gap:,
        travel: float.max(0.0, gap -. radii -. distance),
      )
    Away ->
      case gap <=. 0.0 {
        True -> from
        False -> {
          let scale = distance /. gap
          start_place.moved(
            place: from,
            x: start_place.x(from)
              +. { start_place.x(from) -. start_place.x(reference.place) }
              *. scale,
            y: start_place.y(from)
              +. { start_place.y(from) -. start_place.y(reference.place) }
              *. scale,
            z: start_place.z(from)
              +. { start_place.z(from) -. start_place.z(reference.place) }
              *. scale,
          )
        }
      }
    Random -> {
      let turn = draws.angle *. 2.0 *. maths.pi()
      start_place.moved(
        place: from,
        x: start_place.x(from) +. distance *. maths.cos(turn),
        y: start_place.y(from),
        z: start_place.z(from) +. distance *. maths.sin(turn),
      )
    }
    AlongVelocity ->
      start_place.moved(
        place: from,
        x: start_place.x(from) +. velocity.0 *. distance,
        y: start_place.y(from) +. velocity.1 *. distance,
        z: start_place.z(from) +. velocity.2 *. distance,
      )
  }
}

/// The point `travel` along the line from `from` to the reference unit's place.
fn toward_reference(
  from from: Place,
  reference reference: Reference,
  gap gap: Float,
  travel travel: Float,
) -> Place {
  use <- bool.guard(when: gap <=. 0.0, return: from)
  creature_path.along(from:, to: reference.place, fraction: travel /. gap)
}

/// The way the creature faces at its end: toward the reference unit for flag 4, else
/// along its move for flag 8, a yaw of `atan2(-dx, -dz)` as the client's facing is read
/// (genesis_prime/game/area).
fn turn_of(
  move move: Move,
  from from: Place,
  end end: Place,
  reference reference: Reference,
) -> Option(Facing) {
  case
    int.bitwise_and(move.flags, face_reference_flag),
    int.bitwise_and(move.flags, face_move_flag)
  {
    0, 0 -> None
    0, _ -> Some(facing_along(from:, to: end))
    _, _ -> Some(facing_along(from: end, to: reference.place))
  }
}

fn facing_along(from from: Place, to to: Place) -> Facing {
  start_place.Facing(
    yaw: float32.rounded(maths.atan2(
      float.negate(start_place.x(to) -. start_place.x(from)),
      float.negate(start_place.z(to) -. start_place.z(from)),
    )),
    pitch: 0.0,
    roll: 0.0,
  )
}
