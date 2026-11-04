//// A creature's 0x262 (`genesis_prime/world_map/creature_unit`). Expected values
//// come from the client's vector of message 0x262 for a creature
//// (`opcode.0x262.creature`, `0x140095fb0`), which `combat_message_vector_test`
//// pins to the codec: unit 0x1001, type 0, Creature2 73464, checklist 0, stats 0
//// = 52 and 10 = 1, kind 2 at (-131.5, -875.25, 333.5), kind 14 with yaw 1.5,
//// both factions 1441, display 26565.

import genesis_prime/game/start_place.{Facing}
import genesis_prime/message/unit_create_creature
import genesis_prime/table/id.{Creature2Id, WorldLocation2Id}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/spawn.{Spawn, WorldDatabase}
import genesis_prime/world_map/spawn_id.{SpawnId}
import message_support
import owned_test

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
      area: WorldLocation2Id(51_739),
      source: WorldDatabase(row_id: 29_113),
      level: 1,
      health: 52,
      faction_id: 1441,
      display_info_id: 26_565,
    )
  assert unit_create_creature.encode(creature_unit.create(
      spawn: beast,
      unit_id: 0x1001,
      server_time_estimate_start: 0,
    ))
    == Ok(message_support.hex(
      "01 10 00 00 00 be 47 00 00 02 40 03 00 00 a0 08 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
    ))
    as "opcode.0x262.creature: the creature's 0x262 is the client's vector"
}
