//// A float as the bits of a 32-bit float (IEEE 754 binary32), which the
//// client's messages carry (ReadFloat 0x14006C1C0). The values 1.0, -2.5,
//// 100.25, 0.0 and 3.5 are the floats of vector.opcode.0xad.body, whose bits
//// the vector gives as 0x3F800000, 0xC0200000, 0x42C88000, 0 and 0x40600000.

import genesis_prime/message/float32
import gleam/int
import gleam/list
import gleam/result
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

pub fn the_bits_of_a_float_the_client_sent_hold_the_float_it_sent_test() -> Nil {
  use <- owned_test.run(5000)
  let assert Ok(one) = float32.bits(0x3F800000)
  assert float32.value(one) == Ok(1.0)
    as "IEEE 754 binary32: 0x3F800000 is 1.0 (vector.opcode.0xad.body)"
  let assert Ok(minus_two_and_a_half) = float32.bits(0xC0200000)
  assert float32.value(minus_two_and_a_half) == Ok(-2.5)
    as "IEEE 754 binary32: 0xC0200000 is -2.5 (vector.opcode.0xad.body)"
  let assert Ok(zero) = float32.bits(0)
  assert float32.value(zero) == Ok(0.0) as "IEEE 754 binary32: 0 is 0.0"
  let assert Ok(largest) = float32.bits(0x7F7FFFFF)
  assert float32.value(largest) == Ok(3.4028234663852886e38)
    as "IEEE 754 binary32: 0x7F7FFFFF is the largest finite single, 3.4028234663852886e38"
}

pub fn infinity_and_a_number_that_is_not_one_are_bits_but_no_float_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000, 0x7F800001, 0xFFFFFFFF],
    fn(number) {
      let assert Ok(bits) = float32.bits(number)
        as "the pattern is 32 bits, whatever it holds"
      assert float32.value(bits) == Error(Nil)
        as {
          "IEEE 754 binary32: an exponent of all ones, 0x"
          <> int.to_base16(number)
          <> ", is infinity or not a number, which no finite float is"
        }
    },
  )
}

pub fn a_number_wider_than_32_bits_or_below_0_is_no_bits_test() -> Nil {
  use <- owned_test.run(5000)
  assert result.is_ok(float32.bits(0xFFFFFFFF))
    as "the largest 32-bit pattern is 32 bits"
  assert float32.bits(0x100000000) == Error(Nil)
    as "33 bits are more than the 32 a message carries a float in"
  assert float32.bits(-1) == Error(Nil) as "a number below 0 is no bits"
}

pub fn the_bits_of_a_float_the_server_writes_give_back_that_float_test() -> Nil {
  use <- owned_test.run(5000)
  list.each(
    [0.0, 0.5, 1.5, -2.25, 4110.7099609375, -5145.47998046875],
    fn(value) {
      let assert Ok(bits) = float32.bits(float32.to_bits(value))
        as "to_bits gives 32 bits"
      assert float32.value(bits) == Ok(value)
        as "each value is exactly a 32-bit float, so the round trip changes nothing"
    },
  )
}

pub fn a_float_beyond_the_largest_single_is_the_largest_single_test() -> Nil {
  use <- owned_test.run(5000)
  assert float32.to_bits(1.0e39) == 0x7F7FFFFF
    as "IEEE 754 binary32: the largest finite single is 0x7F7FFFFF, about 3.4028235e38"
  assert float32.to_bits(-1.0e39) == 0xFF7FFFFF
    as "IEEE 754 binary32: the largest finite single with a minus sign is 0xFF7FFFFF"
}
