//// A creature's 0x262 (`genesis_prime/world_map/creature_unit`). Expected values
//// come from the client's vector of message 0x262 for a creature
//// (`opcode.0x262.creature`, `0x140095fb0`), which `combat_message_vector_test`
//// pins to the codec: unit 0x1001, type 0, Creature2 73464, checklist 0, stats 0
//// = 52 and 10 = 1, kind 2 at (-131.5, -875.25, 333.5), kind 14 with yaw 1.5,
//// both factions 1441, display 26565.

import genesis_prime/game/start_place.{Facing}
import genesis_prime/message/unit_create_creature
import genesis_prime/message/unit_property.{UnitProperty}
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/spawn.{Spawn}
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/unit_fields
import message_support
import owned_test
import spawn_support

pub fn a_creature_is_created_as_the_clients_vector_of_a_battle_beast_is_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(place) =
    start_place.place(
      world_id: 3460,
      world_zone_id: 5967,
      x: -131.5,
      y: -875.25,
      z: 333.5,
      facing: Facing(yaw: 1.5, pitch: 0.0, roll: 0.0),
    )
    as "World 3460 is a world"
  let beast =
    Spawn(
      id: SpawnId(1),
      creature_id: Creature2Id(73_464),
      place:,
      level: 1,
      health: 52,
      health_source: unit_fields.ClientDefault,
      faction_id: 1441,
      base_faction_id: 1441,
      display_info_id: 26_565,
      outfit_info_id: 0,
      combat: spawn_support.beast_combat(),
    )
  assert unit_create_creature.encode(creature_unit.create(
      spawn: beast,
      unit_id: 0x1001,
      health: 52,
      server_time_estimate_start: 0,
    ))
    == Ok(message_support.hex(
      "01 10 00 00 00 be 47 00 00 02 40 03 00 00 a0 08 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
    ))
    as "opcode.0x262.creature: the creature's 0x262 is the client's vector"
}

pub fn a_recorded_health_is_sent_as_stat_0_and_as_base_health_test() -> Nil {
  use <- owned_test.run(5000)
  // `opcode.0x262.creature`: the property list sets property 7, which
  // Unit:GetMaxHealth reads; the player's vector (`opcode.0x262.health`) sends the
  // id 7 with the one float in both words. 442.0 is 0x43DD0000 as a 32-bit float
  // (sign 0, exponent 135, mantissa 0x5D0000). A viewer who comes while the creature
  // is hurt gets the current health in stat 0 and the same maximum.
  let beast =
    Spawn(
      ..spawn_support.battle_beast(number: 1, x: 0.0),
      health: 442,
      health_source: unit_fields.Recorded,
    )
  let unit =
    creature_unit.create(
      spawn: beast,
      unit_id: 0x1001,
      health: 300,
      server_time_estimate_start: 0,
    )
  let assert Ok(bytes) = unit_create_creature.encode(unit)
    as "the creature's 0x262 encodes"
  let assert Ok(read) = unit_create_creature.decode(bytes)
    as "the client's reader reads it back"
  assert creature_unit.health_of(unit: read) == 300
  assert read.tail.properties
    == [
      UnitProperty(property_id: 7, field_2: 0x43DD0000, value: 0x43DD0000),
    ]
    as "Base Health 442.0 in both words"
}
