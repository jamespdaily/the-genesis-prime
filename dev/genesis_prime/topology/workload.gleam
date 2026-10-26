//// The load a run puts on a prototype: who is on the map, where they start
//// and how fast they act. The values are start arguments, filled from the
//// client where it has them. Pure.

import genesis_prime/topology/position.{type Position, Position}
import genesis_prime/topology/unit.{type Unit}
import gleam/bool
import gleam/float
import gleam/int
import gleam/list

/// The start arguments of a load run. Distances are metres, speeds metres per
/// second, and `seed` fixes every random choice in the spawn list.
pub type Workload {
  Workload(
    /// Simulated players, each with one unit.
    players: Int,
    /// Creatures on the map.
    creatures: Int,
    /// Moves each player sends in one second.
    moves_per_second: Int,
    /// How far a unit can be seen from; also the width of a grid cell and the
    /// range in which a player attacks.
    visibility_range: Float,
    /// How far a creature notices a player.
    aggro_range: Float,
    /// How far a player's unit moves in one second.
    player_run_speed: Float,
    /// How far a creature moves in one think, which is one second.
    creature_walk_speed: Float,
    /// Health taken by each hit.
    hit_damage: Int,
    /// A creature's health at full.
    creature_maximum_health: Int,
    /// A player's health at full.
    player_maximum_health: Int,
    /// The side of the square map.
    map_size: Float,
    /// How many clusters the players start in.
    cluster_count: Int,
    /// The radius of one cluster; a player's random walk stays inside it.
    cluster_radius: Float,
    seed: Int,
  )
}

/// A workload to start from: the values a run changes are set one by one on
/// top of it.
pub fn default() -> Workload {
  Workload(
    players: 100,
    creatures: 10_000,
    // The client sends its movement (message 0x637) at most once per movement
    // send interval, 125 ms by default (0x140c3a004).
    moves_per_second: 8,
    // A stand-in, not a client fact: the client holds no visibility range.
    visibility_range: 100.0,
    // A stand-in, not a client fact.
    aggro_range: 20.0,
    // A stand-in, not a client fact.
    player_run_speed: 7.0,
    // A stand-in, not a client fact.
    creature_walk_speed: 3.0,
    // A stand-in, not a client fact.
    hit_damage: 7,
    // A stand-in, not a client fact.
    creature_maximum_health: 1000,
    // A stand-in, not a client fact.
    player_maximum_health: 1000,
    // A stand-in, not a client fact.
    map_size: 4096.0,
    // A stand-in, not a client fact.
    cluster_count: 4,
    // A stand-in, not a client fact.
    cluster_radius: 50.0,
    seed: 28,
  )
}

/// The workload of map `map_index`, counted from 0, when several maps run side
/// by side: the same arguments with the seed moved on by the index, so every
/// map has a different spawn list and the same index always gives the same one.
pub fn for_map(workload: Workload, map_index: Int) -> Workload {
  todo as "body in the build commit"
}

/// Every unit the map starts with, the same list for the same workload. The
/// players' units come first, ids 1 to `players`, spread over the clusters; the
/// creatures follow, spread uniformly over the map.
pub fn spawn_list(workload: Workload) -> List(Unit) {
  let random = start_random(workload.seed)
  let #(centres, random) =
    draw_centres(
      workload:,
      remaining: int.max(1, workload.cluster_count),
      random:,
      centres: [],
    )
  let #(players, random) =
    place_players(workload:, centres:, id: 1, random:, placed: [])
  let #(creatures, _) =
    place_creatures(workload:, id: workload.players + 1, random:, placed: [])
  list.append(players, creatures)
}

/// The modulus of the generator: 2^48.
const random_modulus = 281_474_976_710_656

/// The state of the seeded generator that places the units. It is a linear
/// congruential generator with the constants of Java's `java.util.Random`,
/// which is enough to spread units over a map, and the same seed gives the
/// same list on every machine.
type Random {
  Random(state: Int)
}

fn start_random(seed: Int) -> Random {
  Random(int.bitwise_exclusive_or(seed, 25_214_903_917) % random_modulus)
}

/// A float in [0, 1) and the next state.
fn next_fraction(random: Random) -> #(Float, Random) {
  let state = { random.state * 25_214_903_917 + 11 } % random_modulus
  #(int.to_float(state) /. int.to_float(random_modulus), Random(state:))
}

fn draw_centres(
  workload workload: Workload,
  remaining remaining: Int,
  random random: Random,
  centres centres: List(Position),
) -> #(List(Position), Random) {
  case remaining {
    0 -> #(list.reverse(centres), random)
    _ -> {
      let margin = float.min(workload.cluster_radius, workload.map_size /. 2.0)
      let width = workload.map_size -. 2.0 *. margin
      let #(x, random) = next_fraction(random)
      let #(y, random) = next_fraction(random)
      draw_centres(workload:, remaining: remaining - 1, random:, centres: [
        Position(x: margin +. x *. width, y: margin +. y *. width),
        ..centres
      ])
    }
  }
}

fn place_players(
  workload workload: Workload,
  centres centres: List(Position),
  id id: Int,
  random random: Random,
  placed placed: List(Unit),
) -> #(List(Unit), Random) {
  use <- bool.lazy_guard(id > workload.players, fn() {
    #(list.reverse(placed), random)
  })
  let assert Ok(centre) =
    list.drop(centres, { id - 1 } % list.length(centres))
    |> list.first
    as "a cluster for every player"
  let #(offset, random) = draw_in_disc(workload.cluster_radius, random)
  let position =
    clamp_to_map(
      Position(x: centre.x +. offset.x, y: centre.y +. offset.y),
      workload,
    )
  place_players(workload:, centres:, id: id + 1, random:, placed: [
    unit.new(id, unit.Player, position, workload.player_maximum_health),
    ..placed
  ])
}

fn place_creatures(
  workload workload: Workload,
  id id: Int,
  random random: Random,
  placed placed: List(Unit),
) -> #(List(Unit), Random) {
  use <- bool.lazy_guard(id > workload.players + workload.creatures, fn() {
    #(list.reverse(placed), random)
  })
  let #(x, random) = next_fraction(random)
  let #(y, random) = next_fraction(random)
  let position =
    clamp_to_map(
      Position(x: x *. workload.map_size, y: y *. workload.map_size),
      workload,
    )
  place_creatures(workload:, id: id + 1, random:, placed: [
    unit.new(id, unit.Creature, position, workload.creature_maximum_health),
    ..placed
  ])
}

/// A position inside the disc of `radius` around the origin, drawn uniformly
/// by redrawing a point of the enclosing square until it falls inside.
fn draw_in_disc(radius: Float, random: Random) -> #(Position, Random) {
  let #(x, random) = next_fraction(random)
  let #(y, random) = next_fraction(random)
  let offset =
    Position(x: { x *. 2.0 -. 1.0 } *. radius, y: { y *. 2.0 -. 1.0 } *. radius)
  case position.within(offset, Position(x: 0.0, y: 0.0), radius) {
    True -> #(offset, random)
    False -> draw_in_disc(radius, random)
  }
}

fn clamp_to_map(position: Position, workload: Workload) -> Position {
  Position(
    x: float.clamp(position.x, min: 0.0, max: workload.map_size),
    y: float.clamp(position.y, min: 0.0, max: workload.map_size),
  )
}
