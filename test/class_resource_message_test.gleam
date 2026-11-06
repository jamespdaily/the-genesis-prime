//// The messages a class resource travels in: the player's own 0x262, which sets a
//// resource slot only by a stat in the float form and its maximum by the slot's
//// ResourceMax property, and 0x935, the only message that changes a slot after it.
//// Expected values come from these places:
//// - The client: `0x140096230` (a 0x262 stat is a 5-bit id, a 2-bit form and its
////   value: form 0 a 32-bit integer, form 1 a 32-bit float), `0x140458140` and
////   `opcode.0x262.resource_stats` (stats 2 to 9 set slots 0 to 7 only in form 1),
////   `UnitProperty2.ResourceMax_0` and `0x140466360` (ResourceMax_n is property 9 +
////   n for slots 0 to 6), `0x1404584b0` (a property's base and value),
////   `0x1400975b0` and `opcode.0x935` (0x935 is a 32-bit unit, a 5-bit stat and a
////   float), `opcode.0x938.resource_stats` (0x938 of stats 2 to 9 zeroes the slot).
//// - The step's design (issue 403, the Design artifact's values table): each
////   class's slot, maximum and start.
//// - The bit stream writes each field from its lowest bit up, in field order, as
////   the client's reader reads it (the 0x938 vector of combat_message_vector_test).
////
//// Gap: no vector here is a client's or a recording's bytes. The 0x935 vector and
//// the bytes of each 0x262 resource stat are built by hand from the schema's field
//// order and sizes. The loadout session recorded live (`wire_recording`) shows the
//// client taking the 0x262 with the stat and the ResourceMax property (its verdict
//// holds no failure), but it holds no 0x935 and does not state the stat's bytes.

import class_resource_support
import game_connection_support
import genesis_prime/message/bit_stream
import genesis_prime/message/float32
import genesis_prime/message/unit_create_player.{type UnitCreatePlayer}
import genesis_prime/message/unit_float_stat_changed.{UnitFloatStatChanged}
import genesis_prime/message/unit_stat.{type UnitStat, UnitStat}
import genesis_prime/message/unit_stat_changed
import genesis_prime/message/unit_stat_float.{UnitStatFloat}
import genesis_prime/message/unit_stat_value
import genesis_prime/store
import genesis_prime/table/id.{ClassId}
import genesis_prime/world_map/player_unit
import genesis_prime/world_map/unit_fields
import gleam/list
import gleam/result
import message_support
import owned_test
import place_support
import unit_support

/// The bytes a stat is written as, alone.
fn stat_bytes(stat: UnitStat) -> BitArray {
  let assert Ok(bytes) =
    bit_stream.new_writer()
    |> unit_stat.write(stat)
    |> bit_stream.finish
    as "a stat fits its fields"
  bytes
}

/// The record of a new player of the class, as its own client is created with it.
fn player_of(class_id: Int) -> UnitCreatePlayer {
  let character =
    store.Character(
      ..game_connection_support.world_character(),
      class_id: ClassId(class_id),
    )
  let unit =
    unit_support.bare_unit(
      character:,
      place: place_support.live_character_place(),
      unit_id: 9,
      body: [],
    )
  player_unit.with_resource(
    record: player_unit.create(unit:, realm_id: 1),
    resource: class_resource_support.resource_of(class_id),
  )
}

// ---- 1: the start value, as a stat in the float form ----

pub fn a_new_players_0x262_carries_its_slots_stat_in_the_float_form_at_its_start_for_each_class_test() -> Nil {
  use <- owned_test.run(30_000)
  // Class id, the stat (slot + 2) and the bytes of the stat at its start: the stat
  // in 5 bits, form 1 in 2, then the float's 32 bits.
  let expected = [
    #(1, 3, "23 00 00 00 00"),
    #(2, 3, "23 00 00 00 00"),
    #(3, 3, "23 00 00 00 00"),
    #(4, 3, "23 00 00 40 20"),
    #(5, 5, "25 00 00 64 21"),
    #(7, 6, "26 00 00 64 21"),
  ]
  list.each(expected, fn(class) {
    let #(class_id, stat_id, bytes) = class
    let player = player_of(class_id)
    let assert [stat] =
      list.filter(player.tail.stats, fn(stat) {
        stat.stat_id >= 2 && stat.stat_id <= 9
      })
      as "one resource stat: the slot the class's bar reads (0x14064fdb0)"
    assert stat.stat_id == stat_id
    assert stat_bytes(stat) == message_support.hex(bytes)
      as "Warrior, Engineer and Esper start at 0.0; the Medic at 4.0 (0x40800000); the Stalker and Spellslinger at 100.0 (0x42C80000); the bytes are built by hand from the schema (module gap)"
  })
}

pub fn the_same_stat_in_the_integer_form_is_another_form_on_the_wire_test() -> Nil {
  use <- owned_test.run(5000)
  let float_form =
    UnitStat(
      stat_id: 5,
      value: unit_stat_value.Float(UnitStatFloat(value: float32.to_bits(100.0))),
    )
  let integer_form = unit_fields.integer_stat(stat_id: 5, value: 100)
  assert stat_bytes(integer_form) == message_support.hex("05 32 00 00 00")
    as "form 0 (bits 5 and 6 clear), then the integer 100: the client stores 0 in the slot for it (opcode.0x262.resource_stats)"
  assert stat_bytes(float_form) == message_support.hex("25 00 00 64 21")
    as "form 1, then the float 100.0; both vectors are built by hand from the schema (module gap)"
  let assert Ok(#(read, _)) =
    unit_stat.read(bit_stream.new_reader(stat_bytes(float_form)))
  assert read == float_form as "the float form reads back as written"
}

// ---- 2: the maximum, as the slot's ResourceMax property ----

pub fn a_new_players_0x262_carries_its_slots_resource_max_at_the_classes_maximum_test() -> Nil {
  use <- owned_test.run(30_000)
  let expected = [
    #(1, 10, 1000.0),
    #(2, 10, 100.0),
    #(3, 10, 5.0),
    #(4, 10, 4.0),
    #(5, 12, 100.0),
    #(7, 13, 100.0),
  ]
  list.each(expected, fn(class) {
    let #(class_id, property_id, max) = class
    let player = player_of(class_id)
    let assert Ok(property) =
      list.find(player.tail.properties, fn(property) {
        property.property_id == property_id
      })
      as "ResourceMax_1 is property 10, ResourceMax_3 12, ResourceMax_4 13 (UnitProperty2.ResourceMax_0)"
    assert property.value == float32.to_bits(max)
      && property.base == float32.to_bits(max)
      as "base and value alike (0x1404584b0), at the design's maximum"
    assert list.filter(player.tail.properties, fn(property) {
        property.property_id >= 9 && property.property_id <= 15
      })
      == [property]
      as "no other resource slot is given a maximum"
  })
}

// ---- 3: 0x935, and never 0x938, for a slot's change ----

pub fn a_slot_change_is_0x935_of_a_32_bit_unit_a_5_bit_stat_and_a_float_test() -> Nil {
  use <- owned_test.run(5000)
  assert unit_float_stat_changed.message_id == 0x935
    as "opcode.0x935: message 0x935 (2357)"
  message_support.assert_codec(
    name: "opcode.0x935: unit 0x1001, stat 5 (slot 3), 35.0 (0x420C0000); bytes built by hand from the schema, no recorded 0x935 (module gap)",
    body: message_support.hex("01 10 00 00 05 00 80 41 08"),
    value: UnitFloatStatChanged(
      unit_id: 0x1001,
      stat_id: 5,
      value: float32.to_bits(35.0),
    ),
    encode: unit_float_stat_changed.encode,
    decode: unit_float_stat_changed.decode,
  )
}

pub fn the_server_writes_0x938_only_for_the_shield_never_a_resource_stat_test() -> Nil {
  use <- owned_test.run(5000)
  // A 0x938 of stat 3 (slot 1), value 123: the stat's 5 bits are 3.
  let resource = message_support.hex("01 10 00 00 63 0f 00 00 00")
  assert unit_stat_changed.decode(resource) |> result.is_error
    as "opcode.0x938.resource_stats: a 0x938 of stats 2 to 9 sets the slot to 0, so the server's 0x938 holds stat 20 alone"
}
