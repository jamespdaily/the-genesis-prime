//// The four threshold messages the server sends (0x814 to 0x817): each number is
//// the client's, each body is the layout its reader takes, and every value of the
//// widths the fields hold round-trips through the generated codec. The layouts
//// are the fact file's `opcode.0x814`, `opcode.0x815`, `opcode.0x816` and
//// `opcode.0x817`: bits least significant first, the fields in the order the
//// reader reads them.

import genesis_prime/message/spell_threshold_closed.{SpellThresholdClosed}
import genesis_prime/message/spell_threshold_ended.{SpellThresholdEnded}
import genesis_prime/message/spell_threshold_index.{SpellThresholdIndex}
import genesis_prime/message/spell_threshold_opened.{SpellThresholdOpened}
import gleam/result
import message_support
import owned_test
import qcheck

pub fn the_threshold_message_numbers_are_the_clients_test() -> Nil {
  use <- owned_test.run(5000)
  assert spell_threshold_closed.message_id == 0x814
    as "opcode.0x814: message 0x814 (2068)"
  assert spell_threshold_ended.message_id == 0x815
    as "opcode.0x815: message 0x815 (2069)"
  assert spell_threshold_opened.message_id == 0x816
    as "opcode.0x816: message 0x816 (2070)"
  assert spell_threshold_index.message_id == 0x817
    as "opcode.0x817: message 0x817 (2071)"
}

pub fn a_closed_threshold_is_a_spell_in_18_bits_and_the_cooldown_bit_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x814: the spell 34718 (0x879E) in 18 bits, then the bit 1 at bit 18",
    body: message_support.hex("9E 87 04"),
    value: SpellThresholdClosed(spell4_id: 34_718, start_cooldowns: 1),
    encode: spell_threshold_closed.encode,
    decode: spell_threshold_closed.decode,
  )
}

pub fn an_ended_threshold_is_a_spell_in_18_bits_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x815: the spell 34718 in 18 bits",
    body: message_support.hex("9E 87 00"),
    value: SpellThresholdEnded(spell4_id: 34_718),
    encode: spell_threshold_ended.encode,
    decode: spell_threshold_ended.decode,
  )
}

pub fn an_opened_threshold_is_three_spells_in_18_bits_and_a_cast_id_in_32_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x816: 34718 at bit 0, 34718 at bit 18, 0 at bit 36 and the cast id 0x80002804 in 32 bits at bit 54",
    body: message_support.hex("9E 87 78 1E 02 00 00 01 0A 00 20"),
    value: SpellThresholdOpened(
      spell4_id: 34_718,
      resolving_spell4_id: 34_718,
      cooldown_spell4_id: 0,
      cancel_cast_id: 0x80002804,
    ),
    encode: spell_threshold_opened.encode,
    decode: spell_threshold_opened.decode,
  )
}

pub fn a_threshold_index_is_a_spell_in_18_bits_and_an_index_in_8_test() -> Nil {
  use <- owned_test.run(5000)
  message_support.assert_codec(
    name: "opcode.0x817: the spell 34718 in 18 bits, then the index 2 in 8 bits at bit 18",
    body: message_support.hex("9E 87 08 00"),
    value: SpellThresholdIndex(spell4_id: 34_718, index: 2),
    encode: spell_threshold_index.encode,
    decode: spell_threshold_index.decode,
  )
}

pub fn every_value_of_the_threshold_messages_round_trips_test() -> Nil {
  use <- owned_test.run(10_000)
  use #(spell, other, third, cast_id, small) <- qcheck.given(qcheck.tuple5(
    qcheck.bounded_int(from: 0, to: 262_143),
    qcheck.bounded_int(from: 0, to: 262_143),
    qcheck.bounded_int(from: 0, to: 262_143),
    qcheck.bounded_int(from: 0, to: 4_294_967_295),
    qcheck.bounded_int(from: 0, to: 255),
  ))
  let bit = small % 2
  let closed = SpellThresholdClosed(spell4_id: spell, start_cooldowns: bit)
  assert spell_threshold_closed.encode(closed)
    |> result_decode(spell_threshold_closed.decode)
    == Ok(closed)
    as "opcode.0x814: 18 bits and 1 bit"
  let ended = SpellThresholdEnded(spell4_id: spell)
  assert spell_threshold_ended.encode(ended)
    |> result_decode(spell_threshold_ended.decode)
    == Ok(ended)
    as "opcode.0x815: 18 bits"
  let opened =
    SpellThresholdOpened(
      spell4_id: spell,
      resolving_spell4_id: other,
      cooldown_spell4_id: third,
      cancel_cast_id: cast_id,
    )
  assert spell_threshold_opened.encode(opened)
    |> result_decode(spell_threshold_opened.decode)
    == Ok(opened)
    as "opcode.0x816: three 18-bit spells and a 32-bit value"
  let index = SpellThresholdIndex(spell4_id: spell, index: small)
  assert spell_threshold_index.encode(index)
    |> result_decode(spell_threshold_index.decode)
    == Ok(index)
    as "opcode.0x817: 18 bits and 8 bits"
}

fn result_decode(
  encoded: Result(BitArray, encode_error),
  decode: fn(BitArray) -> Result(a, decode_error),
) -> Result(a, Nil) {
  use body <- result.try(result.replace_error(encoded, Nil))
  result.replace_error(decode(body), Nil)
}
