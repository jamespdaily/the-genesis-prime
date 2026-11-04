//// Where a creature that runs is at any moment: the one straight path it was last
//// sent as a 0x638 of kind 4, and its place along it. The creature keeps it
//// (genesis_prime/world_map/creature_fight), and so does each viewer's connection
//// from the creature's own news (genesis_prime/game/shown), so a player's cast and
//// the creature find the creature at the same place by one function.
////
//// ```
//// creature_fight: chase or home ─▶ toward(from, to, ..) ─▶ Path ─▶ 0x638 [kind 0, kind 4] to its viewers
//// creature and viewer: place_at(path, now) ─▶ the place along it, the end once it is run
//// ```
////
//// - **One straight path of two points**, kind 4 type 0 (straight lines), at the
////   creature's run speed in units a second (`movement_command.kind_4`). The client
////   runs it from the time of the 0x638's kind 0 (`movement_command.kind_0`).
//// - **A path is clipped at the leash circle**: no point of it lies farther from the
////   spawn than the circle's radius, so a creature never runs past the circle it
////   leashes at. Distances are in three dimensions, as sight's are
////   (genesis_prime/world_map/sight).
//// - **Time** is the monotonic time of the node in milliseconds, the clock both the
////   creature and its viewers' connections read their inputs at.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/world_map/sight
import gleam/bool
import gleam/float
import gleam/int

/// A creature's movement: standing at a place, or running a straight path from
/// `from` to `to`, started at monotonic time `started_ms`, at `speed` units a
/// second.
pub type Path {
  Standing(at: Place)
  Running(from: Place, to: Place, started_ms: Int, speed: Float)
}

/// The circle a creature's paths stay inside: its spawn's place and the leash
/// range (genesis_prime/world_map/game_number).
pub type Circle {
  Circle(centre: Place, radius: Float)
}

/// The place along the path at monotonic time `now_ms`: its start before it began,
/// its end once it is run, and the straight-line point between at `speed`.
pub fn place_at(path path: Path, now_ms now_ms: Int) -> Place {
  case path {
    Standing(at:) -> at
    Running(from:, to:, started_ms:, speed:) -> {
      let length = distance(from: from, to: to)
      let run = speed *. int.to_float(int.max(0, now_ms - started_ms)) /. 1000.0
      case length <=. 0.0 || run >=. length {
        True -> to
        False -> along(from:, to:, fraction: run /. length)
      }
    }
  }
}

/// The place the path ends at.
pub fn end(path path: Path) -> Place {
  case path {
    Standing(at:) -> at
    Running(to:, ..) -> to
  }
}

/// The path from `from` toward `target` started at `now_ms` at `speed`, ending
/// `stop_short` units before the target and clipped at `circle`; `Standing(from)`
/// when that end is `from` itself.
pub fn toward(
  from from: Place,
  target target: Place,
  stop_short stop_short: Float,
  circle circle: Circle,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Path {
  let length = distance(from: from, to: target)
  let wanted = case length <=. stop_short {
    True -> from
    False ->
      along(from:, to: target, fraction: { length -. stop_short } /. length)
  }
  let end = clipped(from:, to: wanted, circle:)
  case distance(from: from, to: end) <=. 0.0 {
    True -> Standing(at: from)
    False -> Running(from:, to: end, started_ms: now_ms, speed:)
  }
}

/// The path from `from` to `to` itself, started at `now_ms` at `speed`: a walk home.
pub fn straight(
  from from: Place,
  to to: Place,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Path {
  use <- bool.guard(
    when: distance(from: from, to: to) <=. 0.0,
    return: Standing(at: to),
  )
  Running(from:, to:, started_ms: now_ms, speed:)
}

/// The monotonic time the path is run by: `started_ms` plus its length over its
/// speed, rounded up to the millisecond; `now_ms` for a standing path.
pub fn arrives_ms(path path: Path, now_ms now_ms: Int) -> Int {
  case path {
    Standing(..) -> now_ms
    Running(from:, to:, started_ms:, speed:) ->
      started_ms
      + float.truncate(float.ceiling(
        distance(from: from, to: to) /. speed *. 1000.0,
      ))
  }
}

/// The distance between two places, in three dimensions.
pub fn distance(from first: Place, to second: Place) -> Float {
  case float.square_root(sight.squared_distance(first:, second:)) {
    Ok(root) -> root
    Error(Nil) -> 0.0
  }
}

/// The point `fraction` of the way from `from` to `to`, facing as `from` does.
fn along(from from: Place, to to: Place, fraction fraction: Float) -> Place {
  start_place.moved(
    place: from,
    x: start_place.x(from)
      +. { start_place.x(to) -. start_place.x(from) }
      *. fraction,
    y: start_place.y(from)
      +. { start_place.y(to) -. start_place.y(from) }
      *. fraction,
    z: start_place.z(from)
      +. { start_place.z(to) -. start_place.z(from) }
      *. fraction,
  )
}

/// `to`, or the point where the segment from `from` to it leaves the circle when
/// `to` lies outside it. A `from` outside the circle stays where it is.
fn clipped(from from: Place, to to: Place, circle circle: Circle) -> Place {
  use <- bool.guard(
    when: distance(from: circle.centre, to: to) <=. circle.radius,
    return: to,
  )
  use <- bool.guard(
    when: distance(from: circle.centre, to: from) >=. circle.radius,
    return: from,
  )
  along(from:, to:, fraction: exit_fraction(from:, to:, circle:))
}

/// The fraction t in [0, 1] of the segment at which |from + t (to - from) - centre|
/// equals the radius, for a `from` inside the circle and a `to` outside it.
fn exit_fraction(
  from from: Place,
  to to: Place,
  circle circle: Circle,
) -> Float {
  let fx = start_place.x(from) -. start_place.x(circle.centre)
  let fy = start_place.y(from) -. start_place.y(circle.centre)
  let fz = start_place.z(from) -. start_place.z(circle.centre)
  let dx = start_place.x(to) -. start_place.x(from)
  let dy = start_place.y(to) -. start_place.y(from)
  let dz = start_place.z(to) -. start_place.z(from)
  // The roots of quadratic * t^2 + linear * t + constant = 0.
  let quadratic = dx *. dx +. dy *. dy +. dz *. dz
  let linear = 2.0 *. { fx *. dx +. fy *. dy +. fz *. dz }
  let constant =
    fx *. fx +. fy *. fy +. fz *. fz -. circle.radius *. circle.radius
  let discriminant =
    float.max(0.0, linear *. linear -. 4.0 *. quadratic *. constant)
  let root = case float.square_root(discriminant) {
    Ok(root) -> root
    Error(Nil) -> 0.0
  }
  float.clamp(
    { 0.0 -. linear +. root } /. { 2.0 *. quadratic },
    min: 0.0,
    max: 1.0,
  )
}
