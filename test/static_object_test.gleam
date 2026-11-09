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
//// - The vectors of types 4, 12, 14, 8 and 13: the type 10 vector above with the
////   type data its reader reads (`opcode.0x262.type_data`): types 4 and 12 the
////   18-bit Creature2 id alone (`0x140080d30`), type 14 that id and a 32-bit time
////   (`0x140095ed0`, 0 by `opcode.0x262.portal_time`), types 8 and 13 the id and
////   the 8-bit checklist index (`0x140095fb0`). Every reader ends where the shared
////   tail begins, and the type 10 vector's tail starts on a byte (32 + 6 + 18 + 8
////   bits), so each vector is the type 10 vector with its type bits and type data
////   swapped and the same tail bytes after them (a script of bit shifts, not the
////   encoder).

import genesis_prime/game/connection/frames
import genesis_prime/game/start_place.{Facing}
import genesis_prime/message/unit_create_player
import genesis_prime/message/unit_create_static
import genesis_prime/table/id.{Creature2Id}
import genesis_prime/world_map/creature_unit
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/static_object.{
  type StaticObject, Health, StaticObject,
}
import genesis_prime/world_map/unit_fields
import gleam/option.{Some}
import map_support
import message_support
import owned_test
import place_support
import spawn_support
import unit_support

/// The vectors' object: the support's Holoring at the vectors' place, facing the
/// vectors' yaw of 1.5, with the vectors' display, which each vector changes by
/// record update.
fn vectors_object() -> StaticObject {
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
    ..spawn_support.holoring(number: 1, place:),
    display_info_id: 26_565,
  )
}

/// The object's 0x262 as unit `unit_id`, encoded as the connection writes it.
fn encoded(object: StaticObject, unit_id: Int) -> BitArray {
  let frame =
    frames.object_created_frame(unit: static_object.create(
      object:,
      unit_id:,
      server_time_estimate_start: 0,
    ))
  assert frame.message_id == unit_create_static.message_id
    as "opcode.0x262: one message creates every unit"
  frame.body
}

pub fn a_static_object_is_created_as_the_vector_of_its_type_test() -> Nil {
  use <- owned_test.run(5000)
  let simple =
    StaticObject(..vectors_object(), creature_id: Creature2Id(73_707))
  assert encoded(simple, 0x2001)
    == message_support.hex(
      "01 20 00 00 ca fa 47 00 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
    )
    as "type 10 with no recorded stats: none sent, faction 0 sent as 0, no world object"
  let platform =
    StaticObject(
      ..vectors_object(),
      unit_type: static_object.Platform,
      creature_id: Creature2Id(72_051),
      level: Some(1),
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
    StaticObject(
      ..vectors_object(),
      unit_type: static_object.SimpleCollidable,
      creature_id: Creature2Id(73_500),
      level: Some(3),
      health: Some(Health(value: 442, source: unit_fields.Recorded)),
      faction_id: 1441,
      base_faction_id: 1441,
    )
  assert encoded(recorded, 0x2003)
    == message_support.hex(
      "03 20 00 00 20 c7 47 00 00 02 a0 1b 00 00 a0 18 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 10 70 00 00 d0 3d 04 00 d0 3d 04 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
    )
    as "type 32 with a recorded health: stat 0 = 442 above 0, level 3, Base Health 442.0 in both words"
  let client_default =
    StaticObject(
      ..vectors_object(),
      unit_type: static_object.SimpleCollidable,
      creature_id: Creature2Id(73_500),
      level: Some(1),
      health: Some(Health(value: 52, source: unit_fields.ClientDefault)),
      faction_id: 1441,
      base_faction_id: 1441,
    )
  assert encoded(client_default, 0x2004)
    == message_support.hex(
      "04 20 00 00 20 c7 47 00 00 02 40 03 00 00 a0 08 00 00 00 00 00 00 00 10 02 00 70 60 18 00 5a 8b 18 00 d8 74 88 03 00 00 fe 01 00 00 00 00 00 00 00 00 00 00 00 00 00 00 10 5a 84 16 00 00 00 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 00 00 08 00 00 00 00 00 00 00 a0 f8 0c 00 00",
    )
    as "type 32 with the client's Base Health: stat 0 = 52 and stat 10 = 1, no property, the client computes its own"
}

pub fn door_and_mailbox_create_has_creature_id_only_test() -> Nil {
  use <- owned_test.run(5000)
  let door =
    StaticObject(
      ..vectors_object(),
      unit_type: static_object.Door,
      creature_id: Creature2Id(73_707),
    )
  assert encoded(door, 0x2005)
    == message_support.hex(
      "05 20 00 00 c4 fa 47 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
    )
    as "type 4: the unit type, the 18-bit Creature2 id, then the tail, with no checklist index (0x140080d30)"
  let mailbox =
    StaticObject(
      ..vectors_object(),
      unit_type: static_object.Mailbox,
      creature_id: Creature2Id(73_707),
      checklist_index: 9,
    )
  assert encoded(mailbox, 0x2006)
    == message_support.hex(
      "06 20 00 00 cc fa 47 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
    )
    as "type 12 likewise, and a checklist index the row holds is not sent"
}

pub fn portal_create_has_time_left_zero_test() -> Nil {
  use <- owned_test.run(5000)
  let portal =
    StaticObject(
      ..vectors_object(),
      unit_type: static_object.InstancePortal,
      creature_id: Creature2Id(73_707),
    )
  assert encoded(portal, 0x2007)
    == message_support.hex(
      "07 20 00 00 ce fa 47 00 00 00 00 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
    )
    as "type 14: the 18-bit Creature2 id, then a 32-bit time of 0, then the tail (0x140095ed0, opcode.0x262.portal_time)"
}

pub fn collectible_and_turret_create_has_checklist_index_test() -> Nil {
  use <- owned_test.run(5000)
  let collectible =
    StaticObject(
      ..vectors_object(),
      unit_type: static_object.Collectible,
      creature_id: Creature2Id(73_707),
      checklist_index: 5,
    )
  assert encoded(collectible, 0x2008)
    == message_support.hex(
      "08 20 00 00 c8 fa 47 05 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
    )
    as "type 8: the Creature2 id, then the 8-bit checklist index 5 (0x140095fb0)"
  let turret =
    StaticObject(
      ..vectors_object(),
      unit_type: static_object.Turret,
      creature_id: Creature2Id(73_707),
      checklist_index: 255,
    )
  assert encoded(turret, 0x2009)
    == message_support.hex(
      "09 20 00 00 cd fa 47 ff 00 00 00 00 00 40 08 00 c0 81 61 00 68 2d 62 00 60 d3 21 0e 00 00 f8 07 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 00 00 20 00 00 00 00 00 00 00 80 e2 33 00 00",
    )
    as "type 13: the Creature2 id, then the 8-bit checklist index 255"
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
      interrupt_armor: option.None,
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
