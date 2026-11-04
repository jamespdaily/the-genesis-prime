//// A creature's unit: the spawn it stands at, alive at the place the spawn gives
//// it. The creature's process (genesis_prime/world_map/creature) turns it into
//// message 0x262, which creates the unit in a client, for each player who sees
//// it; `create` is the one place a creature's 0x262 is built.
////
//// - **Type 0** (a NonPlayer unit) with the Creature2 id, which the client
////   refuses unless it loaded the row, and the quest checklist index 0
////   (opcode.0x262.creature, `0x140095fb0`).
//// - **Alive:** stat 0 (health) above 0, or the client creates the creature
////   dead (opcode.0x262.creature); it is the spawn's Base Health. Stat 10 is
////   the spawn's level (`0x140458140`).
//// - **Place:** a kind 2 movement command at the spawn's position and a kind 14
////   at its facing, each with its bit clear, which places the unit at once
////   (`genesis_prime/world_map/player_unit.standing`).
//// - **Factions:** Creature2.factionId in both fields, which the client keeps
////   in place of the row's (opcode.0x262.creature).
//// - **Display:** the spawn's display info, since with 0 the creature has no
////   model (opcode.0x262.creature).
//// - **Properties:** none; the client computes each from its tables
////   (`0x1404585c0`).
//// - Every other field 0 or empty, each by its record
////   (opcode.0x262.unit_fields).

import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_creature.{
  type UnitCreateCreature, UnitCreateCreature,
}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/spawn.{type Spawn}

/// The stat the client keeps a unit's health in (`0x140458140`).
const health_stat = 0

/// The stat the client keeps a unit's level in (`0x140458140`).
const level_stat = 10

/// Message 0x262 for the creature at `spawn` as unit `unit_id`, stamped with
/// `server_time_estimate_start`, the map's server time (`map.server_time`).
pub fn create(
  spawn spawn: Spawn,
  unit_id unit_id: Int,
  server_time_estimate_start server_time_estimate_start: Int,
) -> UnitCreateCreature {
  let Creature2Id(creature_id) = spawn.creature_id
  let #(position, rotation) = player_unit.standing(place: spawn.place)
  UnitCreateCreature(
    unit_id:,
    creature_id:,
    checklist_index: 0,
    tail: UnitCreateTail(
      create_flags: 0,
      stats: [
        UnitStat(stat_id: health_stat, value: spawn.health),
        UnitStat(stat_id: level_stat, value: spawn.level),
      ],
      server_time_estimate_start:,
      movement_commands: [
        start_movement.Position(position),
        start_movement.Rotation(rotation),
      ],
      properties: [],
      item_visuals: [],
      cast_id: 0,
      faction_id: spawn.faction_id,
      base_faction_id: spawn.faction_id,
      tagged_by_unit_id: 0,
      tagged_by_group_id: 0,
      field_14: 0,
      field_16: 0,
      world_socket_id: 0,
      cluster_id: 0,
      field_20: 0,
      minimap_marker_id: 0,
      display_info_id: spawn.display_info_id,
      outfit_info_id: 0,
    ),
  )
}
