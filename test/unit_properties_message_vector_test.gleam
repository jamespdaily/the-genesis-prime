//// Message 0x93a against bytes packed by hand from the layout in the fact file
//// `opcode.0x93a`: the unit id in 32 bits, a count in 8 bits, and for each entry the
//// UnitProperty2 id in 8 bits, then the base and the value as 32-bit floats. Each vector
//// was packed by a script that follows the bit stream's rule, the least significant bit
//// of the first byte first, field by field with the widths the fact gives, and shares no
//// code with the codec; the floats are IEEE 754 single precision as the script's own
//// packer writes them. The values named beside each vector are the player's unit 5,
//// BaseCritChance (102) from 0.0 to 0.08 (0x3da3d70a) and BaseHealth (7) from 600.0 to
//// 700.0. The bytes decode to the values, the values encode back to them, and every
//// shorter run of the bytes ends inside a field.

import genesis_prime/message/unit_properties_changed.{UnitPropertiesChanged}
import genesis_prime/message/unit_property.{UnitProperty}
import message_support
import owned_test

pub fn a_message_with_one_entry_is_the_unit_the_count_and_the_id_base_and_value_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x93a: unit 5 in 32 bits, count 1 in 8, property 102, base 0.0, value 0.08",
    body: message_support.hex("05 00 00 00 01 66 00 00 00 00 0a d7 a3 3d"),
    value: UnitPropertiesChanged(unit_id: 5, properties: [
      UnitProperty(property_id: 102, base: 0x00000000, value: 0x3DA3D70A),
    ]),
    encode: unit_properties_changed.encode,
    decode: unit_properties_changed.decode,
  )
}

pub fn a_message_with_two_entries_holds_them_in_order_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x93a: count 2, property 102 as above, then property 7 from 600.0 to 700.0",
    body: message_support.hex(
      "05 00 00 00 02 66 00 00 00 00 0a d7 a3 3d 07 00 00 16 44 00 00 2f 44",
    ),
    value: UnitPropertiesChanged(unit_id: 5, properties: [
      UnitProperty(property_id: 102, base: 0x00000000, value: 0x3DA3D70A),
      UnitProperty(property_id: 7, base: 0x44160000, value: 0x442F0000),
    ]),
    encode: unit_properties_changed.encode,
    decode: unit_properties_changed.decode,
  )
}

pub fn a_message_with_no_entry_is_the_unit_and_a_count_of_0_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x93a: unit 5 and count 0",
    body: message_support.hex("05 00 00 00 00"),
    value: UnitPropertiesChanged(unit_id: 5, properties: []),
    encode: unit_properties_changed.encode,
    decode: unit_properties_changed.decode,
  )
}
