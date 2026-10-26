//// A float as the bits of a 32-bit float (IEEE 754 binary32), which the
//// client's messages carry (ReadFloat 0x14006C1C0). The values 1.0, -2.5,
//// 100.25, 0.0 and 3.5 are the floats of vector.opcode.0xad.body, whose bits
//// the vector gives as 0x3F800000, 0xC0200000, 0x42C88000, 0 and 0x40600000.

import genesis_prime/message/float32
import owned_test

pub fn the_floats_of_the_enter_world_vector_have_the_vectors_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert float32.to_bits(1.0) == 0x3F800000
    as "vector.opcode.0xad.body: 1.0 is the 32 bits 0000803f"
  assert float32.to_bits(-2.5) == 0xC0200000
    as "vector.opcode.0xad.body: -2.5 is the 32 bits 000020c0"
  assert float32.to_bits(100.25) == 0x42C88000
    as "vector.opcode.0xad.body: 100.25 is the 32 bits 0080c842"
  assert float32.to_bits(0.0) == 0
    as "vector.opcode.0xad.body: 0.0 is the 32 bits 00000000"
  assert float32.to_bits(3.5) == 0x40600000
    as "vector.opcode.0xad.body: 3.5 is the 32 bits 00006040"
}

pub fn a_float_that_a_single_cannot_hold_is_rounded_to_the_nearest_single_test() -> Nil {
  use <- owned_test.run(5000)
  assert float32.to_bits(0.1) == 0x3DCCCCCD
    as "IEEE 754 binary32: 0.1 rounds to 0x3DCCCCCD, 0.100000001490116"
  assert float32.to_bits(16_777_217.0) == 0x4B800000
    as "IEEE 754 binary32: 2^24 + 1 is a tie between 2^24 and 2^24 + 2, and rounds to even, 2^24 = 0x4B800000"
}

pub fn a_float_beyond_the_largest_single_is_the_largest_single_test() -> Nil {
  use <- owned_test.run(5000)
  assert float32.to_bits(1.0e39) == 0x7F7FFFFF
    as "IEEE 754 binary32: the largest finite single is 0x7F7FFFFF, about 3.4028235e38"
  assert float32.to_bits(-1.0e39) == 0xFF7FFFFF
    as "IEEE 754 binary32: the largest finite single with a minus sign is 0xFF7FFFFF"
}
