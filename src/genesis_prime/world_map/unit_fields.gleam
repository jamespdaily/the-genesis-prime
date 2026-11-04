//// What every unit's 0x262 holds the same way, a player's and a creature's: the
//// stats and the property the server sets, by their client ids, and the record
//// after the type's data (`UnitCreateTail`) with every field the server leaves
//// at 0 or empty (opcode.0x262.unit_fields). `genesis_prime/world_map/player_unit`
//// and `genesis_prime/world_map/creature_unit` make their tails with `tail`, and
//// `genesis_prime/world_map/spawn` reads the property id.

import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/start_movement.{type StartMovement}
import genesis_prime/message/unit_create_tail.{
  type UnitCreateTail, UnitCreateTail,
}
import genesis_prime/message/unit_property.{type UnitProperty}
import genesis_prime/message/unit_stat.{type UnitStat}

/// The stat the client keeps a unit's health in (0x140458140).
pub const health_stat = 0

/// The stat the client keeps a unit's level in (0x140458140); a unit created
/// without it is level 1 (0x1404543c1).
pub const level_stat = 10

/// The stat the client keeps a unit's current shield in (0x140458140).
pub const shield_stat = 20

/// The UnitProperty2 id of Base Health, the property Unit:GetMaxHealth reads
/// (0x1404584b0).
pub const base_health_property = 7

/// The record after a unit's type data: the stats, the movement commands that
/// place it, the properties, the item visuals, the faction and the base faction,
/// the display and the outfit, and the time its place is stamped with; every
/// other field 0 or empty.
pub fn tail(
  stats stats: List(UnitStat),
  movement_commands movement_commands: List(StartMovement),
  properties properties: List(UnitProperty),
  item_visuals item_visuals: List(ItemVisual),
  faction_id faction_id: Int,
  base_faction_id base_faction_id: Int,
  display_info_id display_info_id: Int,
  outfit_info_id outfit_info_id: Int,
  server_time_estimate_start server_time_estimate_start: Int,
) -> UnitCreateTail {
  UnitCreateTail(
    create_flags: 0,
    stats:,
    server_time_estimate_start:,
    movement_commands:,
    properties:,
    item_visuals:,
    cast_id: 0,
    faction_id:,
    base_faction_id:,
    tagged_by_unit_id: 0,
    tagged_by_group_id: 0,
    field_14: 0,
    field_16: 0,
    world_socket_id: 0,
    cluster_id: 0,
    field_20: 0,
    minimap_marker_id: 0,
    display_info_id:,
    outfit_info_id:,
  )
}
