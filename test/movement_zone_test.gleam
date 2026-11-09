//// The zone the player's movement keeps (`genesis_prime/game/movement`): the last
//// WorldZone id the client reported, which the saved place holds. Expected
//// values come from these places.
//// - The facts `opcode.0xf2` and `opcode.0x63a`: 0xF2 carries the WorldZone id
////   the player unit stands in, and 0x63A the id it left and the id it entered.
//// - The fact `0x14036d040` (`ProbeWorldAt`) and `0x140388a30`
////   (`ProbeChunkArea`): the id the client reports is the zone the terrain under
////   its unit is in, read from the world's own chunks. The client does not check
////   it against its WorldZone table, so it can be 0 (no zone) or the id of a
////   zone with no WorldZone row, and the server keeps it as the client says it.
////   The bit stream holds 15 bits of it (0 to 32767), and a body the client's own
////   reader would refuse is the refusal.

import character_support
import genesis_prime/game/movement.{
  type State, NotDecoded, Reported, ReportedByTerrainReady,
  ReportedByZoneChanged,
}
import genesis_prime/game/start_place
import genesis_prime/message/terrain_loaded.{TerrainLoaded}
import genesis_prime/message/world_zone_changed.{WorldZoneChanged}
import gleam/list
import gleam/result
import owned_test
import place_support

/// A player that entered World 3460, zone 6009, at (1.0, 2.0, 3.0).
fn entered() -> State {
  movement.entered(
    place: place_support.at(
      world_id: 3460,
      world_zone_id: 6009,
      x: 1.0,
      y: 2.0,
      z: 3.0,
    ),
    session_epoch: character_support.epoch(3),
  )
}

/// The state after the client's 0xF2 with this zone.
fn terrain_ready(state state: State, zone zone: Int) -> State {
  let assert Ok(body) =
    terrain_loaded.encode(TerrainLoaded(world_zone_id: zone))
    as "the zone is within 15 bits"
  let assert Ok(Reported(state:, world_zone_id:, by:)) =
    movement.take(state:, message: movement.TerrainReady, body:)
    as "a 0xF2 of the client's own shape is accepted"
  assert world_zone_id == zone && by == ReportedByTerrainReady
    as "the report still says the zone the client gave"
  state
}

/// The state after the client's 0x63A from `old` to `new`.
fn zone_changed(state state: State, old old: Int, new new: Int) -> State {
  let assert Ok(body) =
    world_zone_changed.encode(WorldZoneChanged(
      old_world_zone_id: old,
      new_world_zone_id: new,
    ))
    as "the zones are within 15 bits"
  let assert Ok(Reported(state:, world_zone_id:, by:)) =
    movement.take(state:, message: movement.ZoneChanged, body:)
    as "a 0x63A of the client's own shape is accepted"
  assert world_zone_id == new
    && by == ReportedByZoneChanged(old_world_zone_id: old)
    as "the report still says the zone the client gave and the one it left"
  state
}

fn zone_of(state: State) -> Int {
  start_place.world_zone_id(movement.place(state:))
}

pub fn a_reported_zone_becomes_the_players_zone_test() -> Nil {
  use <- owned_test.run(5000)
  let start = entered()
  assert zone_of(start) == 6009 as "the zone the player entered with"
  let after_terrain = terrain_ready(state: start, zone: 4962)
  assert zone_of(after_terrain) == 4962
    as "opcode.0xf2: the zone the player unit stands in is the zone it is in"
  let after_change = zone_changed(state: after_terrain, old: 4962, new: 1411)
  assert zone_of(after_change) == 1411
    as "opcode.0x63a: the player has entered the zone the message names"
  assert movement.place(state: after_change)
    == place_support.at(
      world_id: 3460,
      world_zone_id: 1411,
      x: 1.0,
      y: 2.0,
      z: 3.0,
    )
    as "only the zone differs: the world, the position and the facing stay"
}

pub fn a_reported_zone_with_no_world_zone_row_is_kept_as_reported_test() -> Nil {
  use <- owned_test.run(5000)
  // 0x14036d040 and 0x140388a30: the client reports the zone of the terrain
  // under its unit and does not check it against its WorldZone table, so zone 0
  // and a zone no WorldZone row names are zones it can report. The server keeps
  // them as reported (the saved zone is the last one the client reported), and
  // what it refuses is a body the client's own reader would refuse.
  list.each([0, 99, 32_767], fn(zone) {
    assert zone_of(terrain_ready(state: entered(), zone:)) == zone
      as "0xF2's zone is kept as reported"
    assert zone_of(zone_changed(state: entered(), old: 6009, new: zone)) == zone
      as "0x63A's new zone is kept as reported"
  })
  assert result.is_error(
    movement.take(state: entered(), message: movement.TerrainReady, body: <<>>),
  )
    as "a 0xF2 body shorter than its 15 bits is the refusal that ends the connection"
  let assert Error(NotDecoded(..)) =
    movement.take(state: entered(), message: movement.ZoneChanged, body: <<>>)
    as "a 0x63A body shorter than its two 15 bits is the refusal that ends the connection"
  Nil
}
