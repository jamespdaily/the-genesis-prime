//// Where a creature that runs or is thrown is at any moment: the one path it was last
//// sent as a 0x638 (a straight one of kind 4, or a timed one of kind 3), and its place along it. The creature keeps it
//// (genesis_prime/world_map/creature_fight), and so does each viewer's connection
//// from the creature's own news (genesis_prime/game/shown), so a player's cast and
//// the creature find the creature at the same place by one function.
////
//// ```
//// creature_fight: chase or home ─▶ toward(from, to, ..) ─▶ Path ─▶ 0x638 [kind 0, kind 4] to its viewers
//// creature_fight: a late viewer ─▶ rest_of(path, now); a speed change ─▶ with_speed(path, speed, now)
//// creature_fight: a throw ─▶ forced_move.path(..) ─▶ Timed ─▶ 0x638 [kind 0, kind 3 (+ kind 14)] to its viewers
//// creature and viewer: place_at(path, now) ─▶ the place along it, the end once it is run
//// ```
////
//// - **A run** (`Running`) is straight lines through 2 to 1023 points, kind 4 type 0, at one
////   speed in units a second over the whole length (`movement_command.kind_4`). The client
////   runs it from the time of the 0x638's kind 0 (`movement_command.kind_0`), point i at
////   the start plus its summed 3D length over the speed, and holds the last point after
////   the end (`0x1407813d0`). The server's timing is that model from the command's time with the
////   speed as sent and continuous distance, where the client starts at its first update at
////   or after the command and rounds each point's time to a millisecond. A leg of length 0 is
////   skipped, and a point passed exactly belongs to the next leg.
//// - **A timed path** (`Timed`) is the points of a throw (genesis_prime/game/forced_move) with the
////   monotonic time of each, kind 3 type 0 (`movement_command.kind_3`): the client draws straight
////   lines between the points, holds the first before the first time and the last after the last
////   (`0x140783e10`). A path of one point is a creature set at once at that point at that time,
////   which is kind 2 and has no flight; it is the form of a move that turns the creature
////   (`turned_to`, kind 14).
//// - **A path from `toward` is clipped at the leash circle** (it has one leg; `through` clips
////   nothing): no point of it lies farther from the
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

/// A creature's movement: standing at a place, running straight lines from `from`
/// through each of `via` in order to `to`, started at monotonic time `started_ms`, at
/// `speed` units a second over the whole length, or thrown along timed points.
pub type Path {
  Standing(at: Place)
  Running(
    from: Place,
    via: List(Place),
    to: Place,
    started_ms: Int,
    speed: Float,
  )
  /// The points a throw passes, each at its monotonic time in milliseconds: `first`
  /// and then `rest`, so a timed path always has a point, and the times rise along
  /// them; the creature turns to `turned_to` when it has one.
  Timed(
    first: #(Int, Place),
    rest: List(#(Int, Place)),
    turned_to: Option(Facing),
  )
}

/// The most points a kind 4 path holds: its count is 10 bits
/// (`movement_command.kind_4`).
pub const most_points = 1023

/// A path given more points than a kind 4 holds.
pub type TooManyPoints {
  TooManyPoints(count: Int)
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
    Timed(first:, rest:, turned_to:) ->
      facing_of_turn(place: timed_place_at(first:, rest:, now_ms:), turned_to:)
    Running(from:, via:, to:, started_ms:, speed:) ->
      case walked(from:, via:, to:, started_ms:, speed:, now_ms:) {
        Arrived -> to
        On(from:, via:, to:, into:) -> along_leg(from:, via:, to:, into:)
      }
  }
}

/// The place `into` units along the leg of a run that starts at `from`.
fn along_leg(
  from from: Place,
  via via: List(Place),
  to to: Place,
  into into: Float,
) -> Place {
  let next = next_point(via:, to:)
  along(from:, to: next, fraction: into /. distance(from:, to: next))
}

/// Where a run has got to: on the leg that starts at `from`, `into` units along it, with
/// the points after that leg's start in `via` and then `to`, or at its end.
type Walked {
  On(from: Place, via: List(Place), to: Place, into: Float)
  Arrived
}

/// The distance a run that began at `started_ms` has covered at `now_ms`: its speed over the
/// time since the start, 0 before it.
fn run_by(
  started_ms started_ms: Int,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Float {
  speed *. int.to_float(int.max(0, now_ms - started_ms)) /. 1000.0
}

/// The rule every function of a run reads: a run is over at its arrival time
/// (`arrives_ms`), and before it is on the leg its distance covered falls in, the legs
/// measured as cumulative lengths from the start, so arrival and leg agree on one sum.
fn walked(
  from from: Place,
  via via: List(Place),
  to to: Place,
  started_ms started_ms: Int,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Walked {
  use <- bool.guard(
    when: runs(speed:)
      && now_ms >= run_over_ms(from:, via:, to:, started_ms:, speed:),
    return: Arrived,
  )
  walk(from:, via:, to:, before: 0.0, run: run_by(started_ms:, speed:, now_ms:))
}

/// The leg a run of `run` units is on, `before` units being the length of the legs
/// already left behind: a leg is left behind once `run` reaches its end, so a leg of
/// length 0 is skipped and a point passed exactly belongs to the next leg. The last leg
/// is never left, and a run past it is at its end.
fn walk(
  from from: Place,
  via via: List(Place),
  to to: Place,
  before before: Float,
  run run: Float,
) -> Walked {
  let length = distance(from:, to: next_point(via:, to:))
  let end = before +. length
  case run >=. end, via {
    True, [point, ..more] ->
      walk(from: point, via: more, to:, before: end, run:)
    True, [] -> On(from:, via:, to:, into: length)
    False, _ -> On(from:, via:, to:, into: run -. before)
  }
}

/// The end of the leg that starts a run's `via` list: its first point, or `to`.
fn next_point(via via: List(Place), to to: Place) -> Place {
  case via {
    [] -> to
    [point, ..] -> point
  }
}

/// The place the path ends at.
pub fn end(path path: Path) -> Place {
  case path {
    Standing(at:) -> at
    Running(to:, ..) -> to
    Timed(first:, rest:, turned_to:) ->
      facing_of_turn(place: last_of(first:, rest:).1, turned_to:)
  }
}

/// The place with the facing a throw turns the creature to (kind 14 sets the unit's
/// rotation and the path moves its position only), the place itself when the throw does
/// not turn it.
fn facing_of_turn(
  place place: Place,
  turned_to turned_to: Option(Facing),
) -> Place {
  case turned_to {
    option.Some(facing) -> start_place.turned(place:, facing:)
    option.None -> place
  }
}

/// Whether a creature runs at `speed`: only a speed above 0 moves it. A root leaves property
/// 100 at 0 (Spell4Effects 1781), and stacked negative flats take it below 0
/// (Spell4Effects 192472, 213219, 5181, 230841). A creature at a speed below 0 stands
/// as at 0: a server's choice, since no client fact covers a negative speed.
pub fn runs(speed speed: Float) -> Bool {
  speed >. 0.0
}

/// The path from `from` toward `target` started at `now_ms` at `speed`, ending
/// `stop_short` units before the target and clipped at `circle`; `Standing(from)`
/// when that end is `from` itself, or when the creature does not run at `speed`.
pub fn toward(
  from from: Place,
  target target: Place,
  stop_short stop_short: Float,
  circle circle: Circle,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Path {
  use <- bool.guard(when: !runs(speed:), return: Standing(at: from))
  let length = distance(from: from, to: target)
  let wanted = case length <=. stop_short {
    True -> from
    False ->
      along(from:, to: target, fraction: { length -. stop_short } /. length)
  }
  let end = clipped(from:, to: wanted, circle:)
  case distance(from: from, to: end) <=. 0.0 {
    True -> Standing(at: from)
    False -> Running(from:, via: [], to: end, started_ms: now_ms, speed:)
  }
}

/// The path from `from` to `to` itself, started at `now_ms` at `speed`: a walk home.
/// A creature already at `to` stands there at any speed; one that does not run at
/// `speed` stands at `from`.
pub fn straight(
  from from: Place,
  to to: Place,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Path {
  let assert Ok(path) = through(from:, via: [], to:, speed:, now_ms:)
    as "two points are under the most a kind 4 holds"
  path
}

/// The path from `from` through each of `via` in order to `to`, started at `now_ms`
/// at `speed` over its whole length (`0x1407813d0`): `straight`'s guards on its total
/// length (0 stands at `to`, so a loop back to `from` still runs) and speed, and
/// `Error` for more points than `most_points`.
pub fn through(
  from from: Place,
  via via: List(Place),
  to to: Place,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Result(Path, TooManyPoints) {
  let count = 2 + list.length(via)
  use <- bool.guard(
    when: count > most_points,
    return: Error(TooManyPoints(count:)),
  )
  use <- bool.guard(
    when: total_length(from:, via:, to:) <=. 0.0,
    return: Ok(Standing(at: to)),
  )
  use <- bool.guard(when: !runs(speed:), return: Ok(Standing(at: from)))
  Ok(Running(from:, via:, to:, started_ms: now_ms, speed:))
}

/// The sum of the lengths of the legs from `from` through `via` to `to`, added left
/// to right from 0.0.
fn total_length(from from: Place, via via: List(Place), to to: Place) -> Float {
  list.fold(
    list.window_by_2([from, ..list.append(via, [to])]),
    0.0,
    fn(sum, leg) { sum +. distance(from: leg.0, to: leg.1) },
  )
}

/// The monotonic time the path is run by: `started_ms` plus its length over its
/// speed, rounded up to the millisecond; `now_ms` for a standing path. The builders
/// (`toward`, `straight`) make no running path of a speed that is not above 0, so a
/// running path of one is a bug and crashes here rather than arriving at once.
pub fn arrives_ms(path path: Path, now_ms now_ms: Int) -> Int {
  case path {
    Standing(..) -> now_ms
    Timed(first:, rest:, ..) -> last_of(first:, rest:).0
    Running(from:, via:, to:, started_ms:, speed:) -> {
      let assert True = runs(speed:) as "a running path has a speed above 0"
      run_over_ms(from:, via:, to:, started_ms:, speed:)
    }
  }
}

/// The monotonic time a run is over: `started_ms` plus its length over its speed,
/// rounded up to the millisecond.
fn run_over_ms(
  from from: Place,
  via via: List(Place),
  to to: Place,
  started_ms started_ms: Int,
  speed speed: Float,
) -> Int {
  started_ms
  + float.truncate(float.ceiling(
    total_length(from:, via:, to:) /. speed *. 1000.0,
  ))
}

/// The rest of the path from `now_ms` on, as a path of its own: a running path from
/// where the creature is now through the points still ahead of it to the same end at
/// the same speed (itself before it starts, standing at its end once it is run), a
/// timed path from its place now and the points still ahead of it, and a standing one
/// itself. What a viewer that arrives mid-path is sent.
pub fn rest_of(path path: Path, now_ms now_ms: Int) -> Path {
  case path {
    Standing(..) -> path
    Running(from:, via:, to:, started_ms:, speed:) ->
      case now_ms < started_ms {
        True -> path
        False ->
          case walked(from:, via:, to:, started_ms:, speed:, now_ms:) {
            Arrived -> Standing(at: to)
            On(from:, via: ahead, to:, into:) ->
              Running(
                from: along_leg(from:, via: ahead, to:, into:),
                via: ahead,
                to:,
                started_ms: now_ms,
                speed:,
              )
          }
      }
    Timed(first:, rest:, turned_to:) ->
      case list.filter([first, ..rest], fn(point) { point.0 > now_ms }) {
        [] ->
          Standing(at: facing_of_turn(
            place: last_of(first:, rest:).1,
            turned_to:,
          ))
        ahead ->
          Timed(
            first: #(now_ms, timed_place_at(first:, rest:, now_ms:)),
            rest: ahead,
            turned_to:,
          )
      }
  }
}

/// The rest of a running path from `now_ms` on at another `speed`: the same points
/// from where the creature is, as `rest_of`; `Standing` where it is when it does not run
/// at `speed` (`runs`). A standing or timed path is itself. What a change of run speed
/// makes of the path under way.
pub fn with_speed(
  path path: Path,
  speed speed: Float,
  now_ms now_ms: Int,
) -> Path {
  case rest_of(path:, now_ms:) {
    Running(from:, via:, to:, started_ms:, ..) ->
      case runs(speed:) {
        True -> Running(from:, via:, to:, started_ms:, speed:)
        False -> Standing(at: place_at(path:, now_ms:))
      }
    Standing(..) as unchanged | Timed(..) as unchanged -> unchanged
  }
}

/// The creature's velocity along the path at `now_ms` in units a second, the
/// direction of the path's leg now times its speed; zero when it stands, or
/// when the path is run.
pub fn velocity(path path: Path, now_ms now_ms: Int) -> #(Float, Float, Float) {
  case path {
    Standing(..) -> #(0.0, 0.0, 0.0)
    Running(from:, via:, to:, started_ms:, speed:) ->
      case walked(from:, via:, to:, started_ms:, speed:, now_ms:) {
        Arrived -> #(0.0, 0.0, 0.0)
        On(from:, via:, to:, ..) -> {
          let next = next_point(via:, to:)
          let scale = speed /. distance(from:, to: next)
          #(
            { start_place.x(next) -. start_place.x(from) } *. scale,
            { start_place.y(next) -. start_place.y(from) } *. scale,
            { start_place.z(next) -. start_place.z(from) } *. scale,
          )
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
