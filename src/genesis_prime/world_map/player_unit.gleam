//// A player character's unit: the character's own values, alive at the place
//// it was placed at, with the body the character list shows. The map, which
//// owns the units the client sees, builds it when the character joins and keeps
//// it while the player is in the map (genesis_prime/world_map/map); `create`
//// turns it into message 0x262, which creates the unit in the client, whenever
//// one is sent.
////
//// - **Alive:** stat 0 (health) above 0, or the client creates the player
////   dead (0x140457bc5). No client table or retail record gives a player's
////   health by class and level (0x1404585c0), so `create` gives health and
////   property 7 (Base Health) as `stand_in_health`, 136, the client's level-1
////   creature Base Health (CreatureLevel row 1), and `with_gear` replaces it
////   with the health the loadout's gear gives (genesis_prime/game/loadout),
////   which world entry applies to the map's unit.
//// - **Gear:** `with_gear` sets stat 0 to the maximum health and stat 20 (the
////   current shield) to the shield's capacity, a full shield on entry (a server
////   choice: the client holds no shield rule, `regen.client`), and the
////   properties 7 (Base Health), 35 and 36 (Assault Rating and Support Rating),
////   41 (ShieldCapacityMax), 42 (Armor), 175 (ShieldMitigationMax), 176
////   (ShieldRegenPct) and 178 (ShieldRebootTime), each as base and value alike
////   (0x1404584b0, 0x140458140). The shield's regeneration and reboot values
////   replace the unit property defaults (0.25, 2500) rather than add to them (a
////   server choice: the client sums nothing, `player.level1_gear_properties`).
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

import genesis_prime/game/item_property.{type ItemProperties, Shield}
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
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/message/unit_position_command.{
  type UnitPositionCommand, UnitPositionCommand,
}
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/message/unit_stat.{type UnitStat, UnitStat}
import genesis_prime/store.{type Character, CharacterId}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}

/// Every player's health: the client's level-1 creature Base Health
/// (0x1404585c0), which stands in for a health no table gives.
pub const stand_in_health = 136

/// The stat the client keeps a unit's health in (0x140458140).
const health_stat = 0

/// The stat the client keeps a unit's level in (0x140458140); a unit created
/// without it is level 1 (0x1404543c1).
const level_stat = 10

/// The stat the client keeps a unit's current shield in (0x140458140).
const shield_stat = 20

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
    tail: UnitCreateTail(
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
      field_14: 0,
      field_16: 0,
      world_socket_id: 0,
      cluster_id: 0,
      field_20: 0,
      minimap_marker_id: 0,
      display_info_id: 0,
      outfit_info_id: 0,
    ),
  )
}

/// The unit's 0x262 with the gear's values: stat 0 the maximum health, stat 20
/// the shield, full, and the properties the gear gives, in the order of their
/// ids. A unit whose gear holds no shield has no stat 20 and no shield
/// properties.
pub fn with_gear(
  record record: UnitCreatePlayer,
  max_health max_health: Int,
  gear gear: ItemProperties,
) -> UnitCreatePlayer {
  let tail = record.tail
  let shield_stats = case gear.shield {
    Some(Shield(capacity_max:, ..)) -> [
      UnitStat(stat_id: shield_stat, value: float.round(capacity_max)),
    ]
    None -> []
  }
  let shield_properties = case gear.shield {
    Some(Shield(capacity_max:, mitigation_max:, regen_percent:, reboot_time_ms:)) -> [
      #(41, capacity_max),
      #(175, mitigation_max),
      #(176, regen_percent),
      #(178, int.to_float(reboot_time_ms)),
    ]
    None -> []
  }
  let properties =
    list.flatten([
      [
        #(base_health_property, int.to_float(max_health)),
        #(35, gear.assault_rating),
        #(36, gear.support_rating),
        #(42, gear.armor),
      ],
      shield_properties,
    ])
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.map(fn(pair) {
      let bits = float32.to_bits(pair.1)
      UnitProperty(property_id: pair.0, field_2: bits, value: bits)
    })
  UnitCreatePlayer(
    ..record,
    tail: UnitCreateTail(
      ..tail,
      stats: list.flatten([
        [
          UnitStat(stat_id: health_stat, value: max_health),
          UnitStat(stat_id: level_stat, value: level_of(tail.stats)),
        ],
        shield_stats,
      ]),
      properties:,
    ),
  )
}

/// The level among a unit's stats; a unit with none is level 1 (0x1404543c1).
fn level_of(stats: List(UnitStat)) -> Int {
  case list.find(stats, fn(stat) { stat.stat_id == level_stat }) {
    Ok(stat) -> stat.value
    Error(Nil) -> 1
  }
}
