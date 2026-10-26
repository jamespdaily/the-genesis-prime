//// The bit stream's arrays of unsigned values and floats, its lists counted by
//// another list and its fixed values, the primitives the messages of character
//// select and entering the world use. The bytes follow the stream rule of the
//// fact file's `vector.0x140336380.fields` (each value least significant bit
//// first, so one that starts mid-byte crosses into the next) and the layouts
//// of `opcode.0x25b` (a 32-bit count, then the labels, then the values with
//// no count of their own) and `opcode.0x117`'s character (a 4-bit count, then
//// 32-bit labels, then as many 32-bit values).

import genesis_prime/message/bit_stream
import gleam/result
import message_support
import owned_test

fn value_only(
  read: Result(#(a, bit_stream.Reader), bit_stream.DecodeError),
) -> Result(a, bit_stream.DecodeError) {
  result.map(read, fn(pair) { pair.0 })
}

pub fn an_array_of_unsigned_values_is_its_count_then_each_value_test() -> Nil {
  use <- owned_test.run(5000)
  let bytes = message_support.hex("12 00 00 00 20 00 00 00 00")
  assert bit_stream.new_writer()
    |> bit_stream.write_unsigned_array("labels", [1, 2], 4, 32)
    |> bit_stream.finish
    == Ok(bytes)
    as "vector.0x140336380.fields: a 4-bit count of 2, then 1 and 2 in 32 bits each, least significant bit first, is 68 bits: 12 00 00 00 20 00 00 00 00"
  assert bit_stream.read_unsigned_array(bit_stream.new_reader(bytes), 4, 32)
    |> value_only
    == Ok([1, 2])
    as "ReadCharacterListEntry 0x14007F720: the labels are read back"
}

pub fn a_list_counted_by_another_list_has_no_count_of_its_own_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_unsigned_array_like("values", [3, 4], [1, 2], 32)
    |> bit_stream.finish
    == Ok(message_support.hex("03 00 00 00 04 00 00 00"))
    as "opcode.0x25b: the values follow the labels, one 32-bit value for each label"
  assert bit_stream.read_unsigned_array_like(
      bit_stream.new_reader(message_support.hex("03 00 00 00 04 00 00 00")),
      [1, 2],
      32,
    )
    |> value_only
    == Ok([3, 4])
    as "as many values as the list that counts them"
}

pub fn a_list_counted_by_another_list_of_another_length_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_unsigned_array_like("values", [3], [1, 2], 32)
    |> bit_stream.finish
    == Error(bit_stream.ItemCountDisagrees("values", 2, 1))
    as "opcode.0x25b: the client's writer writes as many values as labels, so a list of another length is not a message the client's reader takes"
}

pub fn an_array_of_floats_is_written_as_32_bit_values_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_float32_array(
      "bone_values",
      [0x3F800000, 0xBF000000],
      32,
    )
    |> bit_stream.finish
    == Ok(message_support.hex("02 00 00 00 00 00 80 3f 00 00 00 bf"))
    as "vector.opcode.0x25b.body: the bone values 1.0 and -0.5 follow a 32-bit count of 2, as 0000803f and 000000bf"
  assert bit_stream.read_float32_array(
      bit_stream.new_reader(message_support.hex(
        "02 00 00 00 00 00 80 3f 00 00 00 bf",
      )),
      32,
    )
    |> value_only
    == Ok([0x3F800000, 0xBF000000])
    as "the bits read back as written"
}

pub fn a_count_wider_than_its_field_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  let sixteen = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  assert bit_stream.new_writer()
    |> bit_stream.write_unsigned_array("labels", sixteen, 4, 32)
    |> bit_stream.finish
    == Error(bit_stream.ValueDoesNotFit("labels", 4, 16))
    as "ReadCharacterListEntry 0x14007F720: the count of customisation labels is 4 bits, so 15 at most"
}

pub fn an_item_wider_than_its_field_is_refused_when_written_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_unsigned_array("ids", [0x1_0000_0000], 32, 32)
    |> bit_stream.finish
    == Error(bit_stream.ValueDoesNotFit("ids", 32, 0x1_0000_0000))
    as "ReadMessage0117Body 0x14007FAB0: the creation ids are 32 bits each"
}

pub fn a_count_that_promises_more_items_than_the_bytes_hold_is_a_decode_error_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.read_unsigned_array(
      bit_stream.new_reader(message_support.hex("ff ff ff ff 01 00 00 00")),
      32,
      32,
    )
    |> value_only
    == Error(bit_stream.EndOfData)
    as "vector.opcode.0x117.body: a reader that runs out of bytes inside a field fails; a count of 4 billion is no reason to build 4 billion items"
}

pub fn a_fixed_value_is_written_in_its_width_and_any_other_is_refused_when_read_test() -> Nil {
  use <- owned_test.run(5000)
  assert bit_stream.new_writer()
    |> bit_stream.write_constant("unit_type", 20, 6)
    |> bit_stream.finish
    == Ok(message_support.hex("14"))
    as "opcode.0x262: the unit type is 6 bits, and 20 is a player character"
  assert bit_stream.read_constant(
      bit_stream.new_reader(message_support.hex("14")),
      "unit_type",
      6,
      20,
    )
    |> result.map(fn(_) { Nil })
    == Ok(Nil)
    as "the value the schema fixes is accepted"
  assert bit_stream.read_constant(
      bit_stream.new_reader(message_support.hex("25")),
      "unit_type",
      6,
      20,
    )
    |> result.map(fn(_) { Nil })
    == Error(bit_stream.UnexpectedValue("unit_type", 37))
    as "vector.opcode.0x262.player: a type of 37 is another type"
}
