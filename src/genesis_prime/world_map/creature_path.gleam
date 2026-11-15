//// Where a creature that runs or is thrown is at any moment: the one path it was last
//// sent as a 0x638 (a straight one of kind 4, or a timed one of kind 3), and its place along it. The creature keeps it
//// (genesis_prime/world_map/creature_fight), and so does each viewer's connection
//// from the creature's own news (genesis_prime/game/shown), so a player's cast and
//// the creature find the creature at the same place by one function.
////
//// ```
//// creature_fight: chase or home ─▶ toward(from, to, ..) ─▶ Path ─▶ 0x638 [kind 0, kind 4] to its viewers
//// creature_fight: a throw ─▶ forced_move.path(..) ─▶ Timed ─▶ 0x638 [kind 0, kind 3 (+ kind 14)] to its viewers
//// creature and viewer: place_at(path, now) ─▶ the place along it, the end once it is run
//// ```
////
//// - **One straight path of two points**, kind 4 type 0 (straight lines), at the
////   creature's run speed in units a second (`movement_command.kind_4`). The client
////   runs it from the time of the 0x638's kind 0 (`movement_command.kind_0`).
//// - **A timed path** (`Timed`) is the points of a throw (genesis_prime/game/forced_move) with the
////   monotonic time of each, kind 3 type 0 (`movement_command.kind_3`): the client draws straight
////   lines between the points, holds the first before the first time and the last after the last
////   (`0x140783e10`). A path of one point is a creature set at once at that point at that time,
////   which is kind 2 and has no flight; it is the form of a move that turns the creature
////   (`turned_to`, kind 14).
//// - **A path is clipped at the leash circle**: no point of it lies farther from the
////   spawn than the circle's radius, so a creature never runs past the circle it
////   leashes at. Distances are in three dimensions, as sight's are
////   (genesis_prime/world_map/sight).
//// - **Time** is the monotonic time of the node in milliseconds, the clock both the
////   creature and its viewers' connections read their inputs at.

import genesis_prime/game/start_place.{type Facing, type Place}
import genesis_prime/world_map/sight
import gleam/bool
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}

/// A creature's movement: standing at a place, running a straight path from
/// `from` to `to`, started at monotonic time `started_ms`, at `speed` units a
/// second, or thrown along timed points.
pub type Path {
  Standing(at: Place)
  Running(from: Place, to: Place, started_ms: Int, speed: Float)
  /// The points a throw passes, each at its monotonic time in milliseconds: `first`
  /// and then `rest`, so a timed path always has a point, and the times rise along
  /// them; the creature turns to `turned_to` when it has one.
  Timed(
    first: #(Int, Place),
    rest: List(#(Int, Place)),
    turned_to: Option(Facing),
  )
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
    Timed(first:, rest:, ..) -> timed_place_at(first:, rest:, now_ms:)
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
    Timed(first:, rest:, ..) -> last_of(first:, rest:).1
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
    Timed(first:, rest:, ..) -> last_of(first:, rest:).0
    Running(from:, to:, started_ms:, speed:) ->
      started_ms
      + float.truncate(float.ceiling(
        distance(from: from, to: to) /. speed *. 1000.0,
      ))
  }
}

/// The rest of the path from `now_ms` on, as a path of its own: a running path from
/// where the creature is now to the same end at the same speed, a timed path from
/// its place now and the points still ahead of it, and a standing one itself. What a
/// viewer that arrives mid-path is sent.
pub fn rest_of(path path: Path, now_ms now_ms: Int) -> Path {
  case path {
    Standing(..) | Running(..) -> path
    Timed(first:, rest:, turned_to:) ->
      case list.filter([first, ..rest], fn(point) { point.0 > now_ms }) {
        [] -> Standing(at: last_of(first:, rest:).1)
        ahead ->
          Timed(
            first: #(now_ms, timed_place_at(first:, rest:, now_ms:)),
            rest: ahead,
            turned_to:,
          )
      }
  }
}

/// The creature's velocity along the path at `now_ms` in units a second, the
/// direction of the path's segment now times its speed; zero when it stands, or
/// when the path is run.
pub fn velocity(path path: Path, now_ms now_ms: Int) -> #(Float, Float, Float) {
  case path {
    Standing(..) -> #(0.0, 0.0, 0.0)
    Running(from:, to:, started_ms:, speed:) -> {
      let length = distance(from:, to:)
      let run = speed *. int.to_float(int.max(0, now_ms - started_ms)) /. 1000.0
      case length <=. 0.0 || run >=. length {
        True -> #(0.0, 0.0, 0.0)
        False -> {
          let scale = speed /. length
          #(
            { start_place.x(to) -. start_place.x(from) } *. scale,
            { start_place.y(to) -. start_place.y(from) } *. scale,
            { start_place.z(to) -. start_place.z(from) } *. scale,
          )
        }
      }
    }
    Timed(first:, rest:, ..) -> timed_velocity(first:, rest:, now_ms:)
  }
}

/// The last point of a timed path.
fn last_of(
  first first: #(Int, Place),
  rest rest: List(#(Int, Place)),
) -> #(Int, Place) {
  case list.last(rest) {
    Ok(last) -> last
    Error(Nil) -> first
  }
}

/// The two points of the segment a timed path is on at `now_ms`: the last point not
/// after it and the first point after it. `Error(Nil)` before the first time and after
/// the last, where the path holds a point.
fn segment_at(
  first first: #(Int, Place),
  rest rest: List(#(Int, Place)),
  now_ms now_ms: Int,
) -> Result(#(#(Int, Place), #(Int, Place)), Nil) {
  case rest {
    [] -> Error(Nil)
    [next, ..later] ->
      case now_ms < first.0 {
        True -> Error(Nil)
        False ->
          case now_ms < next.0 {
            True -> Ok(#(first, next))
            False -> segment_at(first: next, rest: later, now_ms:)
          }
      }
  }
}

fn timed_place_at(
  first first: #(Int, Place),
  rest rest: List(#(Int, Place)),
  now_ms now_ms: Int,
) -> Place {
  case segment_at(first:, rest:, now_ms:) {
    Ok(#(before, after)) ->
      along(
        from: before.1,
        to: after.1,
        fraction: int.to_float(now_ms - before.0)
          /. int.to_float(after.0 - before.0),
      )
    Error(Nil) ->
      case now_ms < first.0 {
        True -> first.1
        False -> last_of(first:, rest:).1
      }
  }
}

fn timed_velocity(
  first first: #(Int, Place),
  rest rest: List(#(Int, Place)),
  now_ms now_ms: Int,
) -> #(Float, Float, Float) {
  case segment_at(first:, rest:, now_ms:) {
    Ok(#(before, after)) -> {
      let seconds = int.to_float(after.0 - before.0) /. 1000.0
      #(
        { start_place.x(after.1) -. start_place.x(before.1) } /. seconds,
        { start_place.y(after.1) -. start_place.y(before.1) } /. seconds,
        { start_place.z(after.1) -. start_place.z(before.1) } /. seconds,
      )
    }
    Error(Nil) -> #(0.0, 0.0, 0.0)
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
pub fn along(
  from from: Place,
  to to: Place,
  fraction fraction: Float,
) -> Place {
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
pub fn clipped(from from: Place, to to: Place, circle circle: Circle) -> Place {
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
