//// A player character's unit: the character's own values, alive at the place
//// it was placed at, with the body the character list shows. The map, which
//// owns the units the client sees, builds it when the character joins and keeps
//// it while the player is in the map (genesis_prime/world_map/map); `create`
//// turns it into message 0x262, which creates the unit in the client, whenever
//// one is sent.
////
//// - **Alive:** stat 0 (health) above 0, or the client creates the player
////   dead (0x140457bc5). No client table or retail record gives a player's
////   health by class and level (0x1404585c0), so the unit holds the maximum
////   health the loadout gives (`genesis_prime/game/loadout.max_health`: the
////   level's Base Health plus the gear's, Jim's decision on goal 274), which the
////   map works out at the join.
//// - **Gear:** `create` sets stat 0 to the maximum health and stat 20 (the
////   current shield) to the shield's capacity, a full shield on entry (a server
////   choice: the client holds no shield rule, `regen.client`), and the
////   properties 7 (Base Health), 35 and 36 (Assault Rating and Support Rating),
////   41 (ShieldCapacityMax), 42 (Armor), 175 (ShieldMitigationMax), 176
////   (ShieldRegenPct) and 178 (ShieldRebootTime), each as base and value alike
////   (0x1404584b0, 0x140458140). The shield's regeneration and reboot values
////   replace the unit property defaults (0.25, 2500) rather than add to them (a
////   server choice: the client sums nothing, `player.level1_gear_properties`). A
////   unit whose gear holds no shield has no stat 20 and no shield properties.
//// - **Health now:** the player's own record carries the health it enters with
////   as stat 0, which can be below the maximum (`with_health`,
////   `opcode.0x262`); property 7 stays the maximum.
//// - **Level:** stat 10 is the character's level (0x140458140).
//// - **Class resource:** the player's own record gains its class's resource
////   slot at its start, as stat slot + 2 in the float form, and the slot's
////   ResourceMax property at its maximum (`with_resource`,
////   `opcode.0x262.resource_stats`, `UnitProperty2.ResourceMax_0`): the client
////   holds 0 of each, with a maximum of 0, until the server sends them.
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
//// - **Worn:** the item visuals of the Novice set the loadout holds, after the
////   body's (genesis_prime/game/worn_visual): the client draws armor and a
////   weapon only from them, on the player's own client and every other's, which
////   are sent the same 0x262 (`opcode.0x262.worn_visuals`).
//// - **PvP flags** 0: the 3 bits are the unit's PvP flags, not the path
////   (0x1403b48b0).
//// - Every other field 0 or empty, each by its record
////   (opcode.0x262.player_fields, opcode.0x262.unit_fields).

import genesis_prime/game/class_resource.{type Resource}
import genesis_prime/game/item_property.{Shield}
import genesis_prime/game/loadout.{type Loadout}
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
import genesis_prime/message/unit_property.{type UnitProperty, UnitProperty}
import genesis_prime/store.{type Character, CharacterId}
import genesis_prime/world_map/unit_fields
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}

/// A player's unit in a map: the character as the unit `unit_id`, placed at
/// `place` with the item visuals of its `body`, holding its `loadout` and the
/// `max_health` the loadout gives at its level. Only `new` builds one, so a unit
/// always holds all of them.
pub opaque type PlayerUnit {
  PlayerUnit(
    character: Character,
    place: Place,
    unit_id: Int,
    body: List(ItemVisual),
    loadout: Loadout,
    max_health: Int,
  )
}

/// The unit of the character as the unit `unit_id`, at `place`, with the item
/// visuals of its `body` (the worn set's come from the loadout).
pub fn new(
  character character: Character,
  place place: Place,
  unit_id unit_id: Int,
  body body: List(ItemVisual),
  loadout loadout: Loadout,
  max_health max_health: Int,
) -> PlayerUnit {
  PlayerUnit(character:, place:, unit_id:, body:, loadout:, max_health:)
}

/// What the unit holds: the weapon, the abilities and the gear.
pub fn loadout(unit unit: PlayerUnit) -> Loadout {
  unit.loadout
}

/// The unit's maximum health.
pub fn max_health(unit unit: PlayerUnit) -> Int {
  unit.max_health
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

/// The Faction2 id of the unit's character: Exile 167 or Dominion 166.
pub fn faction_id(unit unit: PlayerUnit) -> Int {
  unit.character.faction_id
}

/// The id of the unit's character, for a log line.
pub fn character_id(unit unit: PlayerUnit) -> Int {
  let CharacterId(character_id) = unit.character.character_id
  character_id
}

/// The properties a player's 0x262 lists from its loadout, in id order, each with its
/// base and value alike: its maximum health as BaseHealth (7), the gear's Assault Rating
/// (35), Support Rating (36) and Armor (42), and its shield's ShieldCapacityMax (41),
/// ShieldMitigationMax (175), ShieldRegenPct (176) and ShieldRebootTime (178), when it
/// holds a shield (`opcode.0x262`, `player.level1_gear_properties`).
pub fn gear_properties(
  loadout loadout: Loadout,
  max_health max_health: Int,
) -> List(UnitProperty) {
  let gear = loadout.properties
  let shield_properties = case gear.shield {
    Some(Shield(capacity_max:, mitigation_max:, regen_percent:, reboot_time_ms:)) -> [
      #(41, capacity_max),
      #(175, mitigation_max),
      #(176, regen_percent),
      #(178, int.to_float(reboot_time_ms)),
    ]
    None -> []
  }
  list.flatten([
    [
      #(unit_fields.base_health_property, int.to_float(max_health)),
      #(35, gear.assault_rating),
      #(36, gear.support_rating),
      #(42, gear.armor),
    ],
    shield_properties,
  ])
  |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
  |> list.map(fn(pair) {
    let bits = float32.to_bits(pair.1)
    UnitProperty(property_id: pair.0, base: bits, value: bits)
  })
}

/// Message 0x262 for the unit, in the realm.
pub fn create(
  unit unit: PlayerUnit,
  realm_id realm_id: Int,
) -> UnitCreatePlayer {
  let PlayerUnit(character:, place:, unit_id:, body:, loadout:, max_health:) =
    unit
  let CharacterId(character_id) = character.character_id
  let gear = loadout.properties
  let shield_stats = case gear.shield {
    Some(Shield(capacity_max:, ..)) -> [
      unit_fields.integer_stat(
        stat_id: unit_fields.shield_stat,
        value: float.round(capacity_max),
      ),
    ]
    None -> []
  }
  let properties = gear_properties(loadout:, max_health:)
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
    tail: unit_fields.tail(
      stats: list.flatten([
        [
          unit_fields.integer_stat(
            stat_id: unit_fields.health_stat,
            value: max_health,
          ),
          unit_fields.integer_stat(
            stat_id: unit_fields.level_stat,
            value: character.level,
          ),
        ],
        shield_stats,
      ]),
      movement_commands: {
        let #(position, rotation) = standing(place:)
        [start_movement.Position(position), start_movement.Rotation(rotation)]
      },
      properties:,
      item_visuals: list.append(body, loadout.item_visuals(loadout:)),
      faction_id: character.faction_id,
      base_faction_id: character.faction_id,
      world_object_id: 0,
      world_socket_id: 0,
      display_info_id: 0,
      outfit_info_id: 0,
      server_time_estimate_start: 0,
    ),
  )
}

/// The player's 0x262 record with `health` as its stat 0, the health the client
/// shows (`opcode.0x262`: stat 0 is the unit's health), and property 7 (Base
/// Health, the maximum Unit:GetMaxHealth reads) as `create` wrote it
/// (`vector.opcode.0x262.health`). `create` writes the maximum health; a player
/// who enters with less is created with what it has.
pub fn with_health(
  record record: UnitCreatePlayer,
  health health: Int,
) -> UnitCreatePlayer {
  UnitCreatePlayer(
    ..record,
    tail: UnitCreateTail(
      ..record.tail,
      stats: list.map(record.tail.stats, fn(stat) {
        case stat.stat_id == unit_fields.health_stat {
          True ->
            unit_fields.integer_stat(
              stat_id: unit_fields.health_stat,
              value: health,
            )
          False -> stat
        }
      }),
    ),
  )
}

/// The player's 0x262 record with `shield` as its stat 20, the shield the client
/// shows (`opcode.0x938`), in place of the full one `create` wrote; a unit with no
/// shield stat keeps none.
pub fn with_shield(
  record record: UnitCreatePlayer,
  shield shield: Int,
) -> UnitCreatePlayer {
  UnitCreatePlayer(
    ..record,
    tail: UnitCreateTail(
      ..record.tail,
      stats: list.map(record.tail.stats, fn(stat) {
        case stat.stat_id == unit_fields.shield_stat {
          True ->
            unit_fields.integer_stat(
              stat_id: unit_fields.shield_stat,
              value: shield,
            )
          False -> stat
        }
      }),
    ),
  )
}

/// The player's 0x262 record with `level` as its stat 10, the level the client shows
/// (`opcode.0x938`) and a viewer created later is sent.
pub fn with_level(
  record record: UnitCreatePlayer,
  level level: Int,
) -> UnitCreatePlayer {
  UnitCreatePlayer(
    ..record,
    tail: UnitCreateTail(
      ..record.tail,
      stats: list.map(record.tail.stats, fn(stat) {
        case stat.stat_id == unit_fields.level_stat {
          True ->
            unit_fields.integer_stat(
              stat_id: unit_fields.level_stat,
              value: level,
            )
          False -> stat
        }
      }),
    ),
  )
}

/// The player's 0x262 record with its class's resource, as its own client is
/// created with it: the stat of the resource's slot at its start, in the float form
/// (`opcode.0x262.resource_stats`), and the slot's ResourceMax property at its
/// maximum, base and value alike, since a player's maximum is 0 until the server
/// sends it (`UnitProperty2.ResourceMax_0`, `0x1404584b0`, `0x1405e75d0`).
pub fn with_resource(
  record record: UnitCreatePlayer,
  resource resource: Resource,
) -> UnitCreatePlayer {
  let bits = float32.to_bits(resource.max)
  UnitCreatePlayer(
    ..record,
    tail: UnitCreateTail(
      ..record.tail,
      stats: list.append(record.tail.stats, [
        unit_fields.resource_stat(slot: resource.slot, value: resource.start),
      ]),
      properties: [
          UnitProperty(
            property_id: unit_fields.resource_max_property(slot: resource.slot),
            base: bits,
            value: bits,
          ),
          ..record.tail.properties
        ]
        |> list.sort(fn(first, second) {
          int.compare(first.property_id, second.property_id)
        }),
    ),
  )
}
