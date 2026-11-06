//// The message that fails a cast with a result (0x7f9) and the cast results of the
//// prerequisite checks. Expected values come from these places:
//// - `opcode.0x7f9` (`0x140095020`): the body is the cast id in 32 bits, a CastResult
////   in 9, a unit id in 32 and one bit. No client vector exists: the message is
////   one the server sends and the client only reads. The vectors below were packed by
////   hand by the bit stream's rule, the least significant bit of the first byte first,
////   field by field, sharing no code with the codec.
//// - `0x1405648a0`: 151 is Prereq_CasterCast, 281 Prereq_TargetCast, 282
////   Prereq_CasterPersistence and 283 Prereq_TargetPersistence (`Spell4CastResult` rows
////   151, 281, 282 and 283).

import genesis_prime/message/cast_result.{
  PrereqCasterCast, PrereqCasterPersistence, PrereqTargetCast,
  PrereqTargetPersistence,
}
import genesis_prime/message/spell_failed.{SpellFailed}
import message_support
import owned_test

pub fn the_message_number_is_the_clients_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_failed.message_id == 0x7F9
    as "opcode.0x7f9: message 0x7f9 (2041)"
}

pub fn a_failed_cast_is_the_cast_id_a_result_a_unit_id_and_a_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x7f9: cast id 0x80002803 in 32 bits, result 282 in 9, unit id 0x2001 in 32, bit 0",
    body: message_support.hex("03 28 00 80 1a 03 40 00 00 00"),
    value: SpellFailed(
      cast_id: 0x80002803,
      result: PrereqCasterPersistence,
      unit_id: 0x2001,
      field_4: 0,
    ),
    encode: spell_failed.encode,
    decode: spell_failed.decode,
  )
  message_support.assert_codec(
    name: "opcode.0x7f9: result 283 and the bit set",
    body: message_support.hex("03 28 00 80 1b 03 40 00 00 02"),
    value: SpellFailed(
      cast_id: 0x80002803,
      result: PrereqTargetPersistence,
      unit_id: 0x2001,
      field_4: 1,
    ),
    encode: spell_failed.encode,
    decode: spell_failed.decode,
  )
}

pub fn the_prerequisite_results_151_and_281_to_283_have_names_test() -> Nil {
  use <- owned_test.run(5000)
  assert cast_result.from_value(151) == PrereqCasterCast
    as "0x1405648a0: 151 Prereq_CasterCast"
  assert cast_result.from_value(281) == PrereqTargetCast
    as "281 Prereq_TargetCast"
  assert cast_result.from_value(282) == PrereqCasterPersistence
    as "282 Prereq_CasterPersistence"
  assert cast_result.from_value(283) == PrereqTargetPersistence
    as "283 Prereq_TargetPersistence"
  assert [
      cast_result.to_value(PrereqCasterCast),
      cast_result.to_value(PrereqTargetCast),
      cast_result.to_value(PrereqCasterPersistence),
      cast_result.to_value(PrereqTargetPersistence),
    ]
    == [151, 281, 282, 283]
}
