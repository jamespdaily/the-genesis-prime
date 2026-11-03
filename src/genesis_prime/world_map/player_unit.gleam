//// A player character's unit: the character's own values, alive at the place
//// it was placed at, with the body the character list shows. The map, which
//// owns the units the client sees, builds it when the character joins and keeps
//// it while the player is in the map (genesis_prime/world_map/map); `create`
//// turns it into message 0x262, which creates the unit in the client, whenever
//// one is sent.
////
//// - **Alive:** stat 0 (health) above 0, or the client creates the player
////   dead (0x140457bc5). No client table or retail record gives a player's
////   health by class and level (0x1404585c0), so health and property 7 (Base
////   Health) are `stand_in_health`, 136, the client's level-1 creature Base
////   Health (CreatureLevel row 1), until a marked retail record gives a player's.
//// - **Level:** stat 10 is the character's level (0x140458140).
//// - **Place:** the unit's own place, which the map is given with the join
////   (the saved place, bounded to the box the client bounds a unit's position
////   to): a kind 2 movement command at its position, with its bit clear, which
////   places the unit at once, then a kind 14 with its yaw, pitch and roll,
////   which turns it (0x1404586e0, 0x140715350); after 0xAD the client never
////   drops the player to the ground, so it must be on the floor (0x1403e828a).
////   The character's own `place` field is never read: a unit holds the
////   character for its other values, and its place only as the unit's own.
//// - **Body:** the item visuals the character list sends
////   (genesis_prime/game/appearance), and the stored bone values
////   (opcode.0x262.player_fields).
//// - **PvP flags** 0: the 3 bits are the unit's PvP flags, not the path
////   (0x1403b48b0).
//// - Every other field 0 or empty, each by its record
////   (opcode.0x262.player_fields, opcode.0x262.unit_fields).

import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/float32
import genesis_prime/message/item_visual.{type ItemVisual}
import genesis_prime/message/movement_rotation.{
  type MovementRotation, MovementRotation,
}
import genesis_prime/message/start_movement
import genesis_prime/message/unit_create_player.{
  type UnitCreatePlayer, UnitCreatePlayer,
}
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
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

/// A player's unit in a map: the character as the unit `unit_id`, placed at
/// `place` with the body `visuals`. Only `new` builds one, so a unit always
/// holds all four.
pub opaque type PlayerUnit {
  PlayerUnit(
    character: Character,
    place: Place,
    unit_id: Int,
    visuals: List(ItemVisual),
  )
}

/// The unit of the character as the unit `unit_id`, at `place` with the body
/// `visuals`.
pub fn new(
  character character: Character,
  place place: Place,
  unit_id unit_id: Int,
  visuals visuals: List(ItemVisual),
) -> PlayerUnit {
  PlayerUnit(character:, place:, unit_id:, visuals:)
}

/// The unit's id in its map.
pub fn unit_id(unit unit: PlayerUnit) -> Int {
  unit.unit_id
}

/// Where the unit stands: the place it joined at, then the one each move gave
/// it.
pub fn place(unit unit: PlayerUnit) -> Place {
  unit.place
}

/// The unit standing at `place`, in the same map with the same body.
pub fn moved(unit unit: PlayerUnit, place place: Place) -> PlayerUnit {
  PlayerUnit(..unit, place:)
}

/// Message 0x262 for the unit as another player is sent it: `create`, with the
/// map's server time in milliseconds as the first sample of the unit's time
/// estimate (opcode.0x262), and the unit's current place as its kind 2 with the
/// bit clear, then its kind 14.
pub fn seen(
  unit unit: PlayerUnit,
  realm_id realm_id: Int,
  server_time_ms server_time_ms: Int,
) -> UnitCreatePlayer {
  UnitCreatePlayer(
    ..create(unit:, realm_id:),
    server_time_estimate_start: server_time_ms,
  )
}

/// The movement commands that put a unit at `place` as the client's reader
/// takes them: the kind 2 at its position and the kind 14 at its facing, each
/// with its bit clear, which places the unit at once (0x140714120). A 0x262
/// starts a unit with them, and a mover's connection sends them to a viewer it
/// has just been told of.
pub fn standing(
  place place: Place,
) -> #(UnitPositionCommand, MovementRotation) {
  let facing = start_place.facing(place)
  #(
    UnitPositionCommand(
      x: float32.to_bits(start_place.x(place)),
      y: float32.to_bits(start_place.y(place)),
      z: float32.to_bits(start_place.z(place)),
      blends: 0,
    ),
    MovementRotation(
      yaw: float32.to_bits(facing.yaw),
      pitch: float32.to_bits(facing.pitch),
      roll: float32.to_bits(facing.roll),
      blends: 0,
    ),
  )
}

/// The id of the unit's character, for a log line.
pub fn character_id(unit unit: PlayerUnit) -> Int {
  let CharacterId(character_id) = unit.character.character_id
  character_id
}

/// Message 0x262 for the unit, in the realm.
pub fn create(
  unit unit: PlayerUnit,
  realm_id realm_id: Int,
) -> UnitCreatePlayer {
  let PlayerUnit(character:, place:, unit_id:, visuals:) = unit
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
    movement_commands: {
      let #(position, rotation) = standing(place:)
      [start_movement.Position(position), start_movement.Rotation(rotation)]
    },
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
