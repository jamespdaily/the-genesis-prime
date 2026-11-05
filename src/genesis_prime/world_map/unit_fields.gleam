//// What every unit's 0x262 holds the same way, a player's, a creature's and a
//// static object's: the stats and the property the server sets, by their client
//// ids, and the record after the type's data (`UnitCreateTail`) with every field
//// the server leaves at 0 or empty (opcode.0x262.unit_fields).
//// `genesis_prime/world_map/player_unit` makes its tail with `tail`;
//// `genesis_prime/world_map/creature_unit` and
//// `genesis_prime/world_map/static_object`, whose units stand at a spawn, with
//// `spawned_tail`; `genesis_prime/world_map/spawn` reads the property id.
////
//// - **The world object link** (the second tagged value: `world_object_id` and
////   `world_socket_id`) is 0 and 0 for a unit that builds its own actor and world
////   unit, a player's and a creature's; a static object sends its spawn's
////   (opcode.0x262.simple, `0x14043e900`).

import genesis_prime/message/float32
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/movement_rotation.{type MovementRotation}
import genesis_prime/message/start_movement.{type StartMovement}
import genesis_prime/message/unit_create_tail.{
  type UnitCreateTail, UnitCreateTail,
}
import genesis_prime/message/unit_position_command.{type UnitPositionCommand}
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/message/unit_stat.{type UnitStat, UnitStat}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

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

/// Where the health of a unit stood at a spawn comes from. `Recorded` is the world
/// database's stat 0, which the 0x262 sends as property 7 too, since the client's
/// own number for the creature is another; `ClientDefault` is the client's Base
/// Health at the spawn's level, which a 0x262 leaves out for the client to
/// compute.
pub type HealthSource {
  Recorded
  ClientDefault
}

/// The value of a stat of a unit's tail, `Error(Nil)` for a stat it does not hold.
pub fn stat(
  tail tail: UnitCreateTail,
  stat_id stat_id: Int,
) -> Result(Int, Nil) {
  list.find(tail.stats, fn(stat) { stat.stat_id == stat_id })
  |> result.map(fn(stat) { stat.value })
}

/// The record after a unit's type data: the stats, the movement commands that
/// place it, the properties, the item visuals, the faction and the base faction,
/// the world object it claims (0 and 0 for none), the display and the outfit,
/// and the time its place is stamped with; every other field 0 or empty.
pub fn tail(
  stats stats: List(UnitStat),
  movement_commands movement_commands: List(StartMovement),
  properties properties: List(UnitProperty),
  item_visuals item_visuals: List(ItemVisual),
  faction_id faction_id: Int,
  base_faction_id base_faction_id: Int,
  world_object_id world_object_id: Int,
  world_socket_id world_socket_id: Int,
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
    world_object_id:,
    world_socket_id:,
    cluster_id: 0,
    field_20: 0,
    minimap_marker_id: 0,
    display_info_id:,
    outfit_info_id:,
  )
}

/// The tail of a unit the server stands at a spawn, a creature's or a static
/// object's: stat 0 at `health` and stat 10 at `level`, each when given, the kind
/// 2 and kind 14 commands of `standing` (`player_unit.standing`), which place it
/// at once, Base Health (property 7) at `base_health` when given, no item
/// visuals, and the rest as given.
pub fn spawned_tail(
  health health: Option(Int),
  level level: Option(Int),
  base_health base_health: Option(Int),
  standing standing: #(UnitPositionCommand, MovementRotation),
  faction_id faction_id: Int,
  base_faction_id base_faction_id: Int,
  world_object_id world_object_id: Int,
  world_socket_id world_socket_id: Int,
  display_info_id display_info_id: Int,
  outfit_info_id outfit_info_id: Int,
  server_time_estimate_start server_time_estimate_start: Int,
) -> UnitCreateTail {
  let #(position, rotation) = standing
  tail(
    stats: option.values([
      option.map(health, fn(value) { UnitStat(stat_id: health_stat, value:) }),
      option.map(level, fn(value) { UnitStat(stat_id: level_stat, value:) }),
    ]),
    movement_commands: [
      start_movement.Position(position),
      start_movement.Rotation(rotation),
    ],
    properties: case base_health {
      Some(value) -> {
        let bits = float32.to_bits(int.to_float(value))
        [
          UnitProperty(
            property_id: base_health_property,
            field_2: bits,
            value: bits,
          ),
        ]
      }
      None -> []
    },
    item_visuals: [],
    faction_id:,
    base_faction_id:,
    world_object_id:,
    world_socket_id:,
    display_info_id:,
    outfit_info_id:,
    server_time_estimate_start:,
  )
}

/// The Base Health a spawned unit's 0x262 sends as property 7 for its maximum
/// health: the recorded one, both words the same as the player's
/// (`opcode.0x262.health`); none for the client's own default, which the client
/// computes itself.
pub fn sent_base_health(
  max_health max_health: Int,
  health_source health_source: HealthSource,
) -> Option(Int) {
  case health_source {
    Recorded -> Some(max_health)
    ClientDefault -> None
  }
}
