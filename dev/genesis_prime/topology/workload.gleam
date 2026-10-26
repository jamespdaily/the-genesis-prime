//// The load a run puts on a prototype: who is on the map, where they start
//// and how fast they act. The values are start arguments, filled from the
//// client where it has them. Pure.

import genesis_prime/topology/unit.{type Unit}

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
  todo as "body in the build commit"
}

/// Every unit the map starts with, the same list for the same workload. The
/// players' units come first, ids 1 to `players`, spread over the clusters; the
/// creatures follow, spread uniformly over the map.
pub fn spawn_list(workload: Workload) -> List(Unit) {
  todo as "body in the build commit"
}
