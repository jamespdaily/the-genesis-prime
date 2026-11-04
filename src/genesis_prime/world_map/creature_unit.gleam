//// A creature's unit: the spawn it stands at, alive at the place the spawn gives
//// it. The creature's process (genesis_prime/world_map/creature) turns it into
//// message 0x262, which creates the unit in a client, for each player who sees
//// it; `create` is the one place a creature's 0x262 is built.
////
//// - **Type 0** (a NonPlayer unit) with the Creature2 id, which the client
////   refuses unless it loaded the row, and the quest checklist index 0
////   (opcode.0x262.creature, `0x140095fb0`).
//// - **Health:** stat 0, which is above 0 for a creature that stands and 0 for one
////   that lies dead, which the client creates dead (opcode.0x262.creature); a
////   creature at full health holds the spawn's Base Health. Stat 10 is the spawn's
////   level (`0x140458140`).
//// - **Place:** a kind 2 movement command at the spawn's position and a kind 14
////   at its facing, each with its bit clear, which places the unit at once
////   (`genesis_prime/world_map/player_unit.standing`).
//// - **Factions:** the spawn's faction and base faction, which the client keeps
////   in place of the row's (opcode.0x262.creature).
//// - **Display and outfit:** the spawn's display info, since with 0 the creature
////   has no model, and its outfit info (opcode.0x262.creature).
//// - **Properties:** none; the client computes each from its tables
////   (`0x1404585c0`).
//// - Every other field 0 or empty, each by its record
////   (opcode.0x262.unit_fields).

import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_creature.{
  type UnitCreateCreature, UnitCreateCreature,
}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/unit_fields
import gleam/result

/// Message 0x262 for the creature at `spawn` as unit `unit_id` with `health`,
/// stamped with `server_time_estimate_start`, the map's server time
/// (`map.server_time`).
pub fn create(
  spawn spawn: Spawn,
  unit_id unit_id: Int,
  health health: Int,
  server_time_estimate_start server_time_estimate_start: Int,
) -> UnitCreateCreature {
  let Creature2Id(creature_id) = spawn.creature_id
  let #(position, rotation) = player_unit.standing(place: spawn.place)
  UnitCreateCreature(
    unit_id:,
    creature_id:,
    checklist_index: 0,
    tail: unit_fields.tail(
      stats: [
        UnitStat(stat_id: unit_fields.health_stat, value: health),
        UnitStat(stat_id: unit_fields.level_stat, value: spawn.level),
      ],
      movement_commands: [
        start_movement.Position(position),
        start_movement.Rotation(rotation),
      ],
      properties: [],
      item_visuals: [],
      faction_id: spawn.faction_id,
      base_faction_id: spawn.base_faction_id,
      display_info_id: spawn.display_info_id,
      outfit_info_id: spawn.outfit_info_id,
      server_time_estimate_start:,
    ),
  )
}

/// The health stat of a creature's 0x262: 0 for a creature that lies dead.
pub fn health_of(unit unit: UnitCreateCreature) -> Int {
  unit_fields.stat(tail: unit.tail, stat_id: unit_fields.health_stat)
  |> result.unwrap(0)
}
