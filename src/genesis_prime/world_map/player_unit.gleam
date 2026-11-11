//// A player character's unit: the character's own values, alive at the place
//// it was placed at, with the body the character list shows. The map, which
//// owns the units the client sees, builds it when the character joins and keeps
//// it while the player is in the map (genesis_prime/world_map/map); `create`
//// turns it into message 0x262, which creates the unit in the client, whenever
//// one is sent.
////
//// - **Alive:** stat 0 (health) above 0, or the client creates the player
////   dead (0x140457bc5). No client table or retail record gives a player's
////   health by class and level (0x1404585c0), so the player's own record carries
////   the health it enters with as stat 0 (`with_integer_stat`, `opcode.0x262`),
////   which the connection works out from the level's Base Health plus the worn
////   items' (genesis_prime/game/gear `max_health`, Jim's decision on goal 274).
//// - **Gear:** the unit holds none. `create` writes the body and the level only;
////   the worn items' gear comes through `with_gear` (genesis_prime/game/gear): the
////   properties 7 (Base Health), 35 and 36 (Assault Rating and Support Rating), 41
////   (ShieldCapacityMax), 42 (Armor), 175 (ShieldMitigationMax), 176
////   (ShieldRegenPct) and 178 (ShieldRebootTime), each as base and value alike
////   (0x1404584b0, 0x140458140) and none at its UnitProperty2 default, which the
////   client's unit starts at, the item visuals of the worn items after the
////   body's, and, with a shield, stat 20, its current shield. A record with no
////   shield has no stat 20. `with_gear` again replaces them when a worn item changes,
////   so a viewer created later is sent the current gear.
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
////   (opcode.0x262.player_fields). The client draws armor and a weapon only from item
////   visuals, on the player's own client and every other's, which are sent the same
////   0x262 (`opcode.0x262.worn_visuals`).
//// - **PvP flags** 0: the 3 bits are the unit's PvP flags, not the path
////   (0x1403b48b0).
//// - Every other field 0 or empty, each by its record
////   (opcode.0x262.player_fields, opcode.0x262.unit_fields).

import genesis_prime/game/class_resource.{type Resource}
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
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/store.{type Character, CharacterId}
import genesis_prime/table/id.{type RaceId, type UnitProperty2Id}
import genesis_prime/world_map/unit_fields
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// A player's unit in a map: the character as the unit `unit_id`, placed at
/// `place` with the item visuals of its `body`, holding its `loadout` (the abilities
/// and the innate). Only `new` builds one, so a unit always holds all of them.
pub opaque type PlayerUnit {
  PlayerUnit(
    character: Character,
    place: Place,
    unit_id: Int,
    body: List(ItemVisual),
    loadout: Loadout,
  )
}

/// The unit of the character as the unit `unit_id`, at `place`, with the item
/// visuals of its `body`.
pub fn new(
  character character: Character,
  place place: Place,
  unit_id unit_id: Int,
  body body: List(ItemVisual),
  loadout loadout: Loadout,
) -> PlayerUnit {
  PlayerUnit(character:, place:, unit_id:, body:, loadout:)
}

/// What the unit holds: the abilities and the innate.
pub fn loadout(unit unit: PlayerUnit) -> Loadout {
  unit.loadout
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

/// The race of the unit's character.
pub fn race_id(unit unit: PlayerUnit) -> RaceId {
  unit.character.race_id
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
  let PlayerUnit(character:, place:, unit_id:, body:, loadout: _) = unit
  let CharacterId(character_id) = character.character_id
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
      stats: [
        unit_fields.integer_stat(
          stat_id: unit_fields.level_stat,
          value: character.level,
        ),
      ],
      movement_commands: {
        let #(position, rotation) = standing(place:)
        [start_movement.Position(position), start_movement.Rotation(rotation)]
      },
      properties: [],
      item_visuals: body,
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

/// The player's 0x262 record with the integer stat `stat_id` set to `value`: the health
/// the client shows as stat 0 (`opcode.0x262`; `create` writes none, and a player who
/// enters with less than the maximum is created with what it has), the shield as stat 20
/// and the level as stat 10 (`opcode.0x938`), which a viewer created later is sent. A
/// record with no such stat gains it, in stat id order.
pub fn with_integer_stat(
  record record: UnitCreatePlayer,
  stat_id stat_id: Int,
  value value: Int,
) -> UnitCreatePlayer {
  let stat = unit_fields.integer_stat(stat_id:, value:)
  let stats = case
    list.any(record.tail.stats, fn(held) { held.stat_id == stat_id })
  {
    True ->
      list.map(record.tail.stats, fn(held) {
        case held.stat_id == stat_id {
          True -> stat
          False -> held
        }
      })
    False -> {
      let #(before, after) =
        list.split_while(record.tail.stats, fn(held) { held.stat_id < stat_id })
      list.flatten([before, [stat], after])
    }
  }
  UnitCreatePlayer(..record, tail: UnitCreateTail(..record.tail, stats:))
}

/// The player's 0x262 record with the gear of its worn items: `item_visuals`, the worn
/// items' visuals, in place of `replacing`, the ones the record lists after its body's
/// (none for a record that has no gear yet), the `bases` as the gear properties it holds,
/// base and value alike, except those equal to their `defaults`, which the client's unit
/// starts at (0x1404584b0) and the record leaves out, and, with a shield, `shield` as
/// stat 20, which a viewer created later is sent; with `None` the record holds no stat 20.
pub fn with_gear(
  record record: UnitCreatePlayer,
  replacing replacing: List(ItemVisual),
  item_visuals item_visuals: List(ItemVisual),
  bases bases: List(#(UnitProperty2Id, Float)),
  defaults defaults: List(#(UnitProperty2Id, Float)),
  shield shield: Option(Int),
) -> UnitCreatePlayer {
  let ids = list.map(bases, fn(base) { { base.0 }.value })
  let listed =
    list.filter(bases, fn(base) {
      case list.key_find(defaults, base.0) {
        Ok(default) -> float32.to_bits(default) != float32.to_bits(base.1)
        Error(Nil) -> True
      }
    })
  let properties =
    list.filter(record.tail.properties, fn(held) {
      !list.contains(ids, held.property_id)
    })
    |> list.append(
      list.map(listed, fn(base) {
        let bits = float32.to_bits(base.1)
        UnitProperty(property_id: { base.0 }.value, base: bits, value: bits)
      }),
    )
    |> list.sort(fn(first, second) {
      int.compare(first.property_id, second.property_id)
    })
  let body =
    list.filter(record.tail.item_visuals, fn(held) {
      !list.contains(replacing, held)
    })
  let record =
    UnitCreatePlayer(
      ..record,
      tail: UnitCreateTail(
        ..record.tail,
        properties:,
        item_visuals: list.append(body, item_visuals),
      ),
    )
  case shield {
    Some(value) ->
      with_integer_stat(record:, stat_id: unit_fields.shield_stat, value:)
    None ->
      UnitCreatePlayer(
        ..record,
        tail: UnitCreateTail(
          ..record.tail,
          stats: list.filter(record.tail.stats, fn(held) {
            held.stat_id != unit_fields.shield_stat
          }),
        ),
      )
  }
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
