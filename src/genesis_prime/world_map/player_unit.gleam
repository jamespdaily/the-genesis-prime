//// A player character's unit as message 0x262 creates it in the client: the
//// character's own values, alive at its saved place, with the body the
//// character list shows. It lives with the map, which owns the units the
//// client sees, not with the connection.
////
//// - **Alive:** stat 0 (health) above 0, or the client creates the player
////   dead (0x140457bc5). No client table or retail record gives a player's
////   health by class and level (0x1404585c0), so health and property 7 (Base
////   Health) are `stand_in_health`, 136, the client's level-1 creature Base
////   Health (CreatureLevel row 1). A player's health is missing in the
////   coverage measure.
//// - **Level:** stat 10 is the character's level (0x140458140).
//// - **Place:** one kind 2 movement command at the saved position; after 0xAD
////   the client never drops the player to the ground, so it must be on the
////   floor (0x1404586e0, 0x1403e828a).
//// - **Body:** the item visuals the character list sends
////   (genesis_prime/game/appearance), and the stored bone values
////   (opcode.0x262.player_fields).
//// - **PvP flags** 0: the 3 bits are the unit's PvP flags, not the path
////   (0x1403b48b0).
//// - Every other field 0 or empty, each by its record
////   (opcode.0x262.player_fields, opcode.0x262.unit_fields).

import genesis_prime/message/float32
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_position_command.{UnitPositionCommand}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{UnitStat}
import genesis_prime/store.{type Character, CharacterId}
import gleam/int

/// Every player's health: the client's level-1 creature Base Health
/// (0x1404585c0), which stands in for a health no table gives.
pub const stand_in_health = 136

/// The stat the client keeps a unit's health in (0x140458140).
const health_stat = 0

/// The stat the client keeps a unit's level in (0x140458140); a unit created
/// without it is level 1 (0x1404543c1).
const level_stat = 10

/// The UnitProperty2 id of Base Health, the property Unit:GetMaxHealth reads
/// (0x1404584b0).
const base_health_property = 7

/// Message 0x262 for the character as the unit `unit_id`, in the realm, with
/// the body `visuals`.
pub fn create(
  character character: Character,
  unit_id unit_id: Int,
  realm_id realm_id: Int,
  visuals visuals: List(ItemVisual),
) -> UnitCreatePlayer {
  let CharacterId(character_id) = character.character_id
  let health = float32.to_bits(int.to_float(stand_in_health))
  UnitCreatePlayer(
    unit_id:,
    character_id:,
    realm_id:,
    name: character.name,
    race_id: character.race_id.value,
    class_id: character.class_id.value,
    gender: character.gender,
    group_id: 0,
    owned_unit_ids: [],
    guild_name: "",
    guild_type: 0,
    guild_ids: [],
    bone_values: character.bones,
    pvp_flags: 0,
    premium_tier: 0,
    title_id: 0,
    create_flags: 0,
    stats: [
      UnitStat(stat_id: health_stat, value: stand_in_health),
      UnitStat(stat_id: level_stat, value: character.level),
    ],
    server_time_estimate_start: 0,
    movement_commands: [
      UnitPositionCommand(
        x: float32.to_bits(character.position_x),
        y: float32.to_bits(character.position_y),
        z: float32.to_bits(character.position_z),
        blends: 0,
      ),
    ],
    properties: [
      UnitProperty(
        property_id: base_health_property,
        field_2: health,
        value: health,
      ),
    ],
    item_visuals: visuals,
    cast_id: 0,
    faction_id: character.faction_id,
    base_faction_id: character.faction_id,
    tagged_by_unit_id: 0,
    tagged_by_group_id: 0,
    field_31: 0,
    field_33: 0,
    world_socket_id: 0,
    cluster_id: 0,
    field_37: 0,
    minimap_marker_id: 0,
    display_info_id: 0,
    outfit_info_id: 0,
  )
}
