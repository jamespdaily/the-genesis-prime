//// A static object: a world database spawn of unit type 4 (Door), 8
//// (Collectible), 10 (Simple), 11 (Platform), 12 (Mailbox), 13 (Turret), 14
//// (InstancePortal) or 32 (SimpleCollidable), which the client draws from a
//// Creature2 row and a display and places where its 0x262 says, and nothing
//// more: it has no process, no fight and no use. The map owns these units
//// (genesis_prime/world_map/map): it decides who sees each and tells the
//// player's connection, which writes the 0x262 this module builds and the 0x355.
////
//// ```
//// spawn.select (at start) ─▶ StaticObject, in its world's WorldSpawns
//// map: a player comes into sight ─▶ create(object, unit id, server time) ─▶ ObjectsSeen
//// ```
////
//// - **Type data**, by the unit type's reader (`opcode.0x262.type_data`): types 8,
////   10, 11, 13 and 32 the Creature2 id and the spawn's quest checklist index, as
////   a creature's (`0x140095fb0`, opcode.0x262.simple); types 4 and 12 the
////   Creature2 id alone (`0x140080d30`); type 14 the id and a time left of 0
////   (`0x140095ed0`, `opcode.0x262.portal_time`).
//// - **Health and level:** types 4, 8, 10, 11, 12 and 14 send stat 0 and stat 10
////   only as the spawn records them, since the client never creates them dead
////   (`0x140457bc5`); types 13 and 32 send both always, as a creature's
////   (genesis_prime/world_map/spawn): the recorded stats, else the creature's
////   `minLevel` and its Base Health at the level. A type 13 or 32 object with
////   health 0 is created dead, so the load leaves one out (`0x140457bc5`,
////   opcode.0x262.simple).
//// - **Place:** a kind 2 and a kind 14 command at the spawn's position and facing
////   (`player_unit.standing`, opcode.0x262.creature).
//// - **Factions** as the spawn records them, 0 included: drawing an object reads
////   no faction (opcode.0x262.simple).
//// - **The world object link:** the spawn's `active_prop_id` and world socket in
////   the second tagged value, 0 and 0 for none, when the unit builds its own actor
////   and world unit (`0x14043e900`, opcode.0x262.simple).
//// - Every other field as every spawned unit's (`unit_fields.spawned_tail`).

import genesis_prime/game/start_place.{type Place}
import genesis_prime/message/static_unit_type
import genesis_prime/message/unit_create_door.{
  type UnitCreateDoor, UnitCreateDoor,
}
import genesis_prime/message/unit_create_mailbox.{
  type UnitCreateMailbox, UnitCreateMailbox,
}
import genesis_prime/message/unit_create_portal.{
  type UnitCreatePortal, UnitCreatePortal,
}
import genesis_prime/message/unit_create_static.{
  type UnitCreateStatic, UnitCreateStatic,
}
import genesis_prime/table/id.{type Creature2Id, Creature2Id}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/spawn_id.{type SpawnId}
import genesis_prime/world_map/unit_fields.{type HealthSource}
import gleam/option.{type Option}

/// The unit type of a static object, as message 0x262 numbers it
/// (`0x140649e20`, `world_data.entity_type`): only these eight are static
/// objects, so no other type can be one.
pub type UnitType {
  /// Type 4: a door, drawn from its Creature2 row alone.
  Door
  /// Type 8: something a player collects.
  Collectible
  /// Type 10: drawn, and walked through (`0x14038d520` is not set for it).
  Simple
  /// Type 11: drawn and stood on.
  Platform
  /// Type 12: a mailbox, drawn from its Creature2 row alone.
  Mailbox
  /// Type 13: a turret, created dead with health 0.
  Turret
  /// Type 14: an instance portal, drawn with a time left.
  InstancePortal
  /// Type 32: drawn and solid, and created dead with health 0.
  SimpleCollidable
}

/// One static object's spawn and the values its 0x262 carries, so the 0x262
/// needs no table at run time.
pub type StaticObject {
  StaticObject(
    /// The spawn table's id, the object's number for the run.
    id: SpawnId,
    /// The 0x262's unit type, the row's entity type.
    unit_type: UnitType,
    /// The object's Creature2 row.
    creature_id: Creature2Id,
    /// Where the object stands and faces, in the row's world and area.
    place: Place,
    /// Stat 10, `None` for none sent: the row's recorded level, or for type 32 the
    /// creature's `minLevel`.
    level: Option(Int),
    /// Stat 0, `None` for none sent: the row's recorded health, or for type 32 the
    /// creature's Base Health at its level.
    health: Option(Health),
    /// The faction the 0x262 sends, 0 for none.
    faction_id: Int,
    /// The base faction the 0x262 sends, 0 for none.
    base_faction_id: Int,
    /// The Creature2DisplayInfo the 0x262 sends.
    display_info_id: Int,
    /// The Creature2OutfitInfo the 0x262 sends, 0 for none.
    outfit_info_id: Int,
    /// The row's quest checklist index, 0 to 255.
    checklist_index: Int,
    /// The row's `active_prop_id`: the 64-bit id of the world's object the unit
    /// claims, 0 for none.
    world_object_id: Int,
    /// The row's WorldSocket id, sent with `world_object_id`.
    world_socket_id: Int,
  )
}

/// The health an object's 0x262 sends: stat 0 at `value`, and Base Health
/// (property 7) at it too when `source` is `Recorded`.
pub type Health {
  Health(value: Int, source: HealthSource)
}

/// The static object type of a row's entity type, the 0x262's unit type, or
/// `Error(Nil)` for a type that is not one. Types 8, 10, 11, 13 and 32 are the
/// generated `static_unit_type`'s; types 4 (Door), 12 (Mailbox) and 14
/// (InstancePortal) are numbered by `opcode.0x262.type_data`, the reader table
/// of message 0x262 (`0x140096fa0`), and are the constants the schema's
/// `unit_create_door`, `unit_create_mailbox` and `unit_create_portal` write.
pub fn unit_type_of(entity_type entity_type: Int) -> Result(UnitType, Nil) {
  case static_unit_type.from_value(entity_type) {
    static_unit_type.Collectible -> Ok(Collectible)
    static_unit_type.Simple -> Ok(Simple)
    static_unit_type.Platform -> Ok(Platform)
    static_unit_type.Turret -> Ok(Turret)
    static_unit_type.SimpleCollidable -> Ok(SimpleCollidable)
    static_unit_type.Other(4) -> Ok(Door)
    static_unit_type.Other(12) -> Ok(Mailbox)
    static_unit_type.Other(14) -> Ok(InstancePortal)
    static_unit_type.Other(_) -> Error(Nil)
  }
}

/// The 0x262's number of the type: 4, 8, 10, 11, 12, 13, 14 or 32. The numbers 4,
/// 12 and 14 are those of `unit_type_of`, from `opcode.0x262.type_data`.
pub fn type_number(unit_type unit_type: UnitType) -> Int {
  case unit_type {
    Door -> 4
    Collectible -> static_unit_type.to_value(static_unit_type.Collectible)
    Simple -> static_unit_type.to_value(static_unit_type.Simple)
    Platform -> static_unit_type.to_value(static_unit_type.Platform)
    Mailbox -> 12
    Turret -> static_unit_type.to_value(static_unit_type.Turret)
    InstancePortal -> 14
    SimpleCollidable ->
      static_unit_type.to_value(static_unit_type.SimpleCollidable)
  }
}

/// Message 0x262 for an object, in the form of its unit type's reader: types 4,
/// 12 and 14 each have a message of their own, and the types that read a quest
/// checklist index share one.
pub type Created {
  /// Types 8, 10, 11, 13 and 32 (`0x140095fb0`).
  CreatedWithChecklist(UnitCreateStatic)
  /// Type 4 (`0x140080d30`).
  CreatedDoor(UnitCreateDoor)
  /// Type 12 (`0x140080d30`).
  CreatedMailbox(UnitCreateMailbox)
  /// Type 14 (`0x140095ed0`).
  CreatedPortal(UnitCreatePortal)
}

/// The id of the unit a 0x262 creates.
pub fn unit_id(created created: Created) -> Int {
  case created {
    CreatedWithChecklist(message) -> message.unit_id
    CreatedDoor(message) -> message.unit_id
    CreatedMailbox(message) -> message.unit_id
    CreatedPortal(message) -> message.unit_id
  }
}

/// Message 0x262 for the object as unit `unit_id`, stamped with
/// `server_time_estimate_start`, the map's server time (`map.server_time`).
pub fn create(
  object object: StaticObject,
  unit_id unit_id: Int,
  server_time_estimate_start server_time_estimate_start: Int,
) -> Created {
  let Creature2Id(creature_id) = object.creature_id
  let tail =
    unit_fields.spawned_tail(
      interrupt_armor: option.None,
      health: option.map(object.health, fn(health) { health.value }),
      level: object.level,
      base_health: option.then(object.health, fn(health) {
        unit_fields.sent_base_health(
          max_health: health.value,
          health_source: health.source,
        )
      }),
      standing: player_unit.standing(place: object.place),
      faction_id: object.faction_id,
      base_faction_id: object.base_faction_id,
      world_object_id: object.world_object_id,
      world_socket_id: object.world_socket_id,
      display_info_id: object.display_info_id,
      outfit_info_id: object.outfit_info_id,
      server_time_estimate_start:,
    )
  let with_checklist = fn(wire_type) {
    CreatedWithChecklist(UnitCreateStatic(
      unit_id:,
      unit_type: wire_type,
      creature_id:,
      checklist_index: object.checklist_index,
      tail:,
    ))
  }
  case object.unit_type {
    Door -> CreatedDoor(UnitCreateDoor(unit_id:, creature_id:, tail:))
    Mailbox -> CreatedMailbox(UnitCreateMailbox(unit_id:, creature_id:, tail:))
    InstancePortal ->
      CreatedPortal(UnitCreatePortal(
        unit_id:,
        creature_id:,
        time_left: 0,
        tail:,
      ))
    Collectible -> with_checklist(static_unit_type.Collectible)
    Simple -> with_checklist(static_unit_type.Simple)
    Platform -> with_checklist(static_unit_type.Platform)
    Turret -> with_checklist(static_unit_type.Turret)
    SimpleCollidable -> with_checklist(static_unit_type.SimpleCollidable)
  }
}
