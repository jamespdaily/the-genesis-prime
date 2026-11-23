//// What a press judges of another player, for the tests: a live player in sight at the
//// defaults below, changed by record update.

import genesis_prime/game/faction_level
import genesis_prime/game/player_state.{type PlayerState, PlayerState}
import genesis_prime/game/start_place
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import place_support

/// A player alive and out of combat, holding no crowd-control state, with no position command
/// yet, the hit radius the Race rows give every player race (`place_support.player_hit_radius`),
/// Friendly to the viewer, not PvP flagged and in no group.
pub fn a_player() -> PlayerState {
  PlayerState(
    alive: True,
    in_combat: False,
    held: [],
    place: None,
    hit_radius: place_support.player_hit_radius,
    disposition: faction_level.Friendly,
    pvp_flagged: False,
    group_id: 0,
  )
}

/// A player `east` metres east of the live character's place and `up` metres above it, which
/// is where `cast_support.caster()` stands, otherwise as `a_player` is.
pub fn beside_the_caster(east east: Float, up up: Float) -> PlayerState {
  around_the_caster(east:, south: 0.0, up:)
}

/// A player `east` metres east, `south` metres south (towards +z, behind a character that has
/// never turned) and `up` metres above the live character's place, otherwise as `a_player` is.
pub fn around_the_caster(
  east east: Float,
  south south: Float,
  up up: Float,
) -> PlayerState {
  let live = place_support.live_character_place()
  PlayerState(
    ..a_player(),
    place: Some(place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: start_place.x(live) +. east,
      y: start_place.y(live) +. up,
      z: start_place.z(live) +. south,
    )),
  )
}

/// The units as players in sight of `cast_support.caster()`, each at the defaults 10 m east of
/// it: what its connection's picture holds of a player it can press at.
pub fn in_range_of_the_caster(
  units units: List(Int),
) -> Dict(Int, PlayerState) {
  list.map(units, fn(unit_id) {
    #(unit_id, beside_the_caster(east: 10.0, up: 0.0))
  })
  |> dict.from_list
}
