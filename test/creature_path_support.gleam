//// Many-point runs for the tests of a creature's path (`genesis_prime/shared/creature_path`),
//// built from plain x, y, z points in the test map's world.

import genesis_prime/game/start_place.{type Place}
import genesis_prime/shared/creature_path
import gleam/int
import gleam/list
import place_support

/// The place at a point (x, y, z) in World 3460.
pub fn at(point: #(Float, Float, Float)) -> Place {
  place_support.at(
    world_id: 3460,
    world_zone_id: 6009,
    x: point.0,
    y: point.1,
    z: point.2,
  )
}

/// A run along `points` (two or more) started at `started_ms` at `speed`, built as
/// the type holds it: the first, those between, and the last.
pub fn running(
  points points: List(#(Float, Float, Float)),
  started_ms started_ms: Int,
  speed speed: Float,
) -> creature_path.Path {
  let assert [first, ..rest] = list.map(points, at) as "a run has two points"
  let assert [last, ..before_last] = list.reverse(rest)
    as "a run has two points"
  creature_path.Running(
    from: first,
    via: list.reverse(before_last),
    to: last,
    started_ms:,
    speed:,
  )
}

/// `count` points one unit apart along x, from the origin.
pub fn line(count count: Int) -> List(#(Float, Float, Float)) {
  list.index_map(list.repeat(Nil, count), fn(_, index) {
    #(int.to_float(index), 0.0, 0.0)
  })
}

/// Every point of a run, in order.
pub fn points_of(path path: creature_path.Path) -> List(Place) {
  let assert creature_path.Running(from:, via:, to:, ..) = path
    as "the path is a run"
  [from, ..list.append(via, [to])]
}

/// The x, y and z of a place.
pub fn coordinates(place: Place) -> #(Float, Float, Float) {
  #(start_place.x(place), start_place.y(place), start_place.z(place))
}
