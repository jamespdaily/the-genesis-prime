//// A static object's 0x262 (`genesis_prime/world_map/static_object.create`).
//// Expected values come from these places.
//// - The vectors of message 0x262 for types 10, 11 and 32 that
////   `combat_message_vector_test` pins to the codec, and one more of type 32 with
////   no Base Health property, packed by hand from `opcode.0x262.simple`,
////   `0x140095fb0` and `opcode.0x262.unit_fields` by a script that first
////   reproduced the client-checked creature vector (`opcode.0x262.creature`): each
////   at the creature vector's place (-131.5, -875.25, 333.5) and yaw 1.5, display
////   26565.
//// - The trace's field table (the issue's "Client trace" of the static objects):
////   the type data is the unit type, the Creature2 id and the quest checklist
////   index; stat 0 and stat 10 go when the spawn records them, and a type 32
////   object always has stat 0 above 0; both factions are the spawn's, 0 included;
////   the second tagged value carries the spawn's `active_prop_id` and WorldSocket
////   id, 0 and 0 for none (`0x14043e900`); Base Health (property 7) goes for a
////   recorded health only, as for a creature (`opcode.0x262.creature`).
//// - `opcode.0x262.unit_fields`: a player's and a creature's tagged value is 0
////   and 0, the unit's own world unit.

import genesis_prime/game/start_place.{Facing}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_create_static
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/spawn_id.{SpawnId}
import genesis_prime/world_map/static_object.{
  type StaticObject, Health, StaticObject,
}
import genesis_prime/world_map/unit_fields
import gleam/option.{type Option, None, Some}
import map_support
import message_support
import owned_test
import place_support
import spawn_support
import unit_support

/// A static object at the vectors' place with these values.
fn object(
  unit_type unit_type: static_object.UnitType,
  creature_id creature_id: Int,
  level level: Option(Int),
  health health: Option(static_object.Health),
  faction_id faction_id: Int,
  base_faction_id base_faction_id: Int,
  checklist_index checklist_index: Int,
  world_object_id world_object_id: Int,
  world_socket_id world_socket_id: Int,
  outfit_info_id outfit_info_id: Int,
) -> StaticObject {
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
  StaticObject(
    id: SpawnId(1),
    unit_type:,
    creature_id: Creature2Id(creature_id),
    place:,
    level:,
    health:,
    faction_id:,
    base_faction_id:,
    display_info_id: 26_565,
    outfit_info_id:,
    checklist_index:,
    world_object_id:,
    world_socket_id:,
  )
}

/// The object's 0x262 as unit `unit_id`, encoded.
fn encoded(object: StaticObject, unit_id: Int) -> BitArray {
  let assert Ok(bytes) =
    unit_create_static.encode(static_object.create(
      object:,
      unit_id:,
      server_time_estimate_start: 0,
    ))
    as "the object's 0x262 encodes"
  bytes
}

pub fn a_static_object_is_created_as_the_vector_of_its_type_test() -> Nil {
  use <- owned_test.run(5000)
  let simple =
    object(
      unit_type: static_object.Simple,
      creature_id: 73_707,
      level: None,
      health: None,
      faction_id: 0,
      base_faction_id: 0,
      checklist_index: 0,
      world_object_id: 0,
      world_socket_id: 0,
      outfit_info_id: 0,
    )
  assert encoded(simple, 0x2001)
    == message_support.hex(
      "01 20 00 00 ca fa 47 00 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
    )
    as "type 10 with no recorded stats: none sent, faction 0 sent as 0, no world object"
  let platform =
    object(
      unit_type: static_object.Platform,
      creature_id: 72_051,
      level: Some(1),
      health: None,
      faction_id: 1441,
      base_faction_id: 1442,
      checklist_index: 4,
      world_object_id: 0x369123456789,
      world_socket_id: 0x1234,
      outfit_info_id: 0x2A,
    )
  assert encoded(platform, 0x2002)
    == message_support.hex(
      "02 20 00 00 cb 5c 46 04 00 41 11 00 00 00 00 00 00 00 20 04 00 e0 c0 30 00 b4 16 31 00 b0 e9 10 07 00 00 fc 03 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 b4 10 2d 00 00 00 00 00 00 00 00 00 00 00 00 50 e2 59 d1 48 a4 0d 00 00 8d 14 00 00 00 00 00 00 00 40 f1 19 15 00",
    )
    as "type 11 with a recorded level alone: stat 10, checklist 4, each faction its own, the world object and its socket, outfit 0x2a"
  let recorded =
    object(
      unit_type: static_object.SimpleCollidable,
      creature_id: 73_500,
      level: Some(3),
      health: Some(Health(value: 442, source: unit_fields.Recorded)),
      faction_id: 1441,
      base_faction_id: 1441,
      checklist_index: 0,
      world_object_id: 0,
      world_socket_id: 0,
      outfit_info_id: 0,
    )
  assert encoded(recorded, 0x2003)
    == message_support.hex(
      "03 20 00 00 20 c7 47 00 00 02 a0 1b 00 00 a0 18 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 10 70 00 00 d0 3d 04 00 d0 3d 04 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
    )
    as "type 32 with a recorded health: stat 0 = 442 above 0, level 3, Base Health 442.0 in both words"
  let client_default =
    object(
      unit_type: static_object.SimpleCollidable,
      creature_id: 73_500,
      level: Some(1),
      health: Some(Health(value: 52, source: unit_fields.ClientDefault)),
      faction_id: 1441,
      base_faction_id: 1441,
      checklist_index: 0,
      world_object_id: 0,
      world_socket_id: 0,
      outfit_info_id: 0,
    )
  assert encoded(client_default, 0x2004)
    == message_support.hex(
      "04 20 00 00 20 c7 47 00 00 02 40 03 00 00 a0 08 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
    )
    as "type 32 with the client's Base Health: stat 0 = 52 and stat 10 = 1, no property, the client computes its own"
}

pub fn a_players_and_a_creatures_0x262_claim_no_world_object_test() -> Nil {
  use <- owned_test.run(5000)
  let player =
    player_unit.create(
      unit: unit_support.bare_unit(
        character: map_support.character(number: 1),
        place: place_support.live_character_place(),
        unit_id: 1,
        body: [],
      ),
      realm_id: 1,
    )
  let creature =
    creature_unit.create(
      spawn: spawn_support.battle_beast(number: 1, x: 0.0),
      unit_id: 2,
      health: 52,
      server_time_estimate_start: 0,
    )
  assert #(player.tail.world_object_id, player.tail.world_socket_id) == #(0, 0)
    as "opcode.0x262.unit_fields: a player's unit is its own world unit"
  assert #(creature.tail.world_object_id, creature.tail.world_socket_id)
    == #(0, 0)
    as "opcode.0x262.unit_fields: a creature's unit is its own world unit"
  assert unit_create_player.message_id == unit_create_static.message_id
    as "opcode.0x262: one message creates every unit"
}
