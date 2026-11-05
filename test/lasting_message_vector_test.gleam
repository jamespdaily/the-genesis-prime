//// The two messages that take a cast off units (0x811) and one stack off a unit
//// (0x813), against the layouts the client's readers state: the reader of 0x811 reads
//// the cast id (32 bits), a count (32 bits) and that many unit ids (32 bits each)
//// (`opcode.0x811`, `0x14007a550`); the reader of 0x813 is `ReadTwoUint32Body`, the
//// cast id then the unit id (`opcode.0x813`, `0x14007a040`).

import genesis_prime/message/spell_stack_removed.{SpellStackRemoved}
import genesis_prime/message/spell_targets_removed.{SpellTargetsRemoved}
import message_support
import owned_test

pub fn the_message_numbers_are_the_clients_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_targets_removed.message_id == 0x811
    as "opcode.0x811: message 0x811 (2065)"
  assert spell_stack_removed.message_id == 0x813
    as "opcode.0x813: message 0x813 (2067)"
}

pub fn a_cast_taken_off_units_is_its_id_a_count_and_the_ids_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x811: cast id 0x80002804, a count of 2, unit ids 0x2001 and 0x2002, each in 32 bits",
    body: message_support.hex("04 28 00 80 02 00 00 00 01 20 00 00 02 20 00 00"),
    value: SpellTargetsRemoved(cast_id: 0x80002804, unit_ids: [0x2001, 0x2002]),
    encode: spell_targets_removed.encode,
    decode: spell_targets_removed.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x811: a count of 0 holds no unit id",
    body: message_support.hex("04 28 00 80 00 00 00 00"),
    value: SpellTargetsRemoved(cast_id: 0x80002804, unit_ids: []),
    encode: spell_targets_removed.encode,
    decode: spell_targets_removed.decode,
  )
}

pub fn a_stack_removed_is_the_cast_id_and_the_unit_id_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x813: cast id 0x80002804 then unit id 0x2001, each in 32 bits",
    body: message_support.hex("04 28 00 80 01 20 00 00"),
    value: SpellStackRemoved(cast_id: 0x80002804, unit_id: 0x2001),
    encode: spell_stack_removed.encode,
    decode: spell_stack_removed.decode,
  )
}
