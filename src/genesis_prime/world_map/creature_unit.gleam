//// A creature's unit: the spawn it stands at, alive at the place the spawn gives
//// it. The creature's process (genesis_prime/world_map/creature) turns it into
//// message 0x262, which creates the unit in a client, for each player who sees
//// it; `create` is the one place a creature's 0x262 is built.
////
//// - **Type 0** (a NonPlayer unit) with the Creature2 id, which the client
////   refuses unless it loaded the row, and the quest checklist index 0
////   (opcode.0x262.creature, `0x140095fb0`); **type 13** (Turret) for a spawn
////   that is a turret's, with the same type data and values (`body`,
////   opcode.0x262.simple).
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
//// - **Interrupt Armor:** stat 21 at the creature's current armor when it is above 0,
////   which the client reads from the create's stat list and clamps no further
////   (`opcode.0x938.interrupt_armor`); a creature with none or infinite armor sends no
////   stat, and the client's maximum (property 44, `UnitProperty2.InterruptArmor_Threshold`)
////   is its own. What the client's unit holds in stat 21 when the list has none is not
////   read: it is taken to be 0, which is right for no armor and unread for infinite armor.
//// - **Properties:** Base Health (property 7) at the spawn's health when that is a
////   recorded value, so the client's maximum is the spawn's, not its own formula's
////   (`opcode.0x262.creature`); otherwise none, and the client computes each from
////   its tables (`0x1404585c0`).
//// - **Create flags:** bit 4 (the vendor mark) when the spawn is a vendor's, else 0; the
////   vendor's prerequisite tag stays unsent, which the client reads as met.
//// - Every other field 0 or empty, each by its record
////   (opcode.0x262.unit_fields), the tail as every spawned unit's
////   (`unit_fields.spawned_tail`).

import genesis_prime/game/unit_properties.{type Properties}
import genesis_prime/message/bit_stream.{type EncodeError}
import genesis_prime/message/static_unit_type
import genesis_prime/message/unit_create_creature.{
  type UnitCreateCreature, UnitCreateCreature,
}
import genesis_prime/message/unit_create_static.{UnitCreateStatic}
import genesis_prime/message/unit_create_tail.{UnitCreateTail}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/spawn.{type Spawn}
import genesis_prime/world_map/unit_fields
import gleam/option.{type Option, Some}
import gleam/result

/// The create flag of a vendor (bit 4 of the 0x262's flags byte), which shows the
/// client the creature's bag icon (`opcode.0x262.vendor_flag`).
const vendor_flag = 4

/// Message 0x262 for the creature at `spawn` as unit `unit_id` with `health` and its
/// current Interrupt Armor when it has any above 0, stamped with `server_time_estimate_start`, the map's server time
/// (`map.server_time`).
pub fn create(
  spawn spawn: Spawn,
  unit_id unit_id: Int,
  health health: Int,
  interrupt_armor interrupt_armor: Option(Int),
  server_time_estimate_start server_time_estimate_start: Int,
) -> UnitCreateCreature {
  let Creature2Id(creature_id) = spawn.creature_id
  UnitCreateCreature(
    unit_id:,
    creature_id:,
    checklist_index: spawn.checklist_index,
    tail: unit_fields.spawned_tail(
      create_flags: case spawn.vendor {
        True -> vendor_flag
        False -> 0
      },
      health: Some(health),
      level: Some(spawn.level),
      interrupt_armor:,
      base_health: unit_fields.sent_base_health(
        max_health: spawn.health,
        health_source: spawn.health_source,
      ),
      standing: player_unit.standing(place: spawn.place),
      faction_id: spawn.faction_id,
      base_faction_id: spawn.base_faction_id,
      world_object_id: 0,
      world_socket_id: 0,
      display_info_id: spawn.display_info_id,
      outfit_info_id: spawn.outfit_info_id,
      server_time_estimate_start:,
    ),
  )
}

/// The bytes of the creature's 0x262: of type 0 as `create` built it, or of type 13
/// (Turret) when `turret` is set, which the client reads with the same type data
/// and the same values (`opcode.0x262.simple`), so only the type number differs.
pub fn body(
  unit unit: UnitCreateCreature,
  turret turret: Bool,
) -> Result(BitArray, EncodeError) {
  case turret {
    False -> unit_create_creature.encode(unit)
    True ->
      unit_create_static.encode(UnitCreateStatic(
        unit_id: unit.unit_id,
        unit_type: static_unit_type.Turret,
        creature_id: unit.creature_id,
        checklist_index: unit.checklist_index,
        tail: unit.tail,
      ))
  }
}

/// The creature's 0x262 with the current base and value of each property a live
/// modifier of `properties` changes in its property list
/// (`unit_properties.overlay`): the 0x262 a viewer that arrives while a modifier
/// lasts is sent.
pub fn overlaid(
  unit unit: UnitCreateCreature,
  properties properties: Properties,
) -> UnitCreateCreature {
  UnitCreateCreature(
    ..unit,
    tail: UnitCreateTail(
      ..unit.tail,
      properties: unit_properties.overlay(
        listed: unit.tail.properties,
        properties:,
      ),
    ),
  )
}

/// The health stat of a creature's 0x262: 0 for a creature that lies dead.
pub fn health_of(unit unit: UnitCreateCreature) -> Int {
  unit_fields.stat(tail: unit.tail, stat_id: unit_fields.health_stat)
  |> result.unwrap(0)
}
