//// A connection's seed (genesis_prime/seed): exactly 32 bytes, made only by a
//// function that checks. Expected values come from these places.
//// - The seed's size: the 32 bytes the server draws from the operating system's
////   strong random source for each connection (`step.Accepted`, and the blocks
////   of 32 bytes `genesis_prime/random` draws from it).

import genesis_prime/seed
import gleam/bit_array
import gleam/list
import owned_test

pub fn bytes_of_any_other_length_than_32_are_no_seed_test() -> Nil {
  use <- owned_test.run(30_000)
  list.each([0, 1, 31, 33, 64], fn(count) {
    let bytes = bit_array.concat(list.repeat(<<7>>, count))
    assert seed.from_bytes(bytes) == Error(seed.WrongLength(found: count))
      as "a seed is 32 bytes and no other count"
  })
}

pub fn bytes_that_are_not_a_whole_number_of_bytes_are_no_seed_test() -> Nil {
  use <- owned_test.run(30_000)
  let thirty_two_bytes_and_a_bit = <<0:size(257)>>
  assert seed.from_bytes(thirty_two_bytes_and_a_bit)
    == Error(seed.WrongLength(found: 33))
    as "33 bytes are held by 257 bits, and a seed is whole bytes"
}

pub fn thirty_two_bytes_are_a_seed_that_gives_them_back_test() -> Nil {
  use <- owned_test.run(30_000)
  let bytes = bit_array.concat(list.repeat(<<0xA5>>, 32))
  let assert Ok(made) = seed.from_bytes(bytes) as "32 bytes are a seed"
  assert seed.bytes(made) == bytes
}

pub fn a_seed_from_the_system_is_32_bytes_and_each_is_new_test() -> Nil {
  use <- owned_test.run(30_000)
  let first = seed.from_system()
  let second = seed.from_system()
  assert bit_array.byte_size(seed.bytes(first)) == 32
  assert first != second as "each seed is drawn anew"
}
