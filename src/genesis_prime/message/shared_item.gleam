//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: the item record message 0x111 carries: the
//// GUID, the item id, the location and bag index, the stack count and charges,
//// the durability and the values the client's code names only by width and
//// position. Gap: the server writes no id in the list of realm and character
//// ids (a count of 0), since the width of one entry is not read. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x111.ability_bag` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type SharedItem {
  SharedItem(
    item_guid: Int,
    field_2: Int,
    item_id: Int,
    location: Int,
    bag_index: Int,
    stack_count: Int,
    charges: Int,
    field_8: Int,
    field_9: Int,
    field_10: Int,
    durability: Int,
    field_12: Int,
    field_13: Int,
    field_14: Int,
    field_15: Int,
    field_16: Int,
    field_17: Int,
    field_18: Int,
    field_19: Int,
    field_20: Int,
    field_21: Int,
    field_22: Int,
    field_23: Int,
    list_a: List(Int),
    list_b: List(Int),
    field_27: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SharedItem) -> Writer {
  writer
  |> bit_stream.write_unsigned("item_guid", record.item_guid, 64)
  |> bit_stream.write_unsigned("field_2", record.field_2, 64)
  |> bit_stream.write_unsigned("item_id", record.item_id, 18)
  |> bit_stream.write_unsigned("location", record.location, 9)
  |> bit_stream.write_unsigned("bag_index", record.bag_index, 32)
  |> bit_stream.write_unsigned("stack_count", record.stack_count, 32)
  |> bit_stream.write_unsigned("charges", record.charges, 32)
  |> bit_stream.write_unsigned("field_8", record.field_8, 64)
  |> bit_stream.write_unsigned("field_9", record.field_9, 32)
  |> bit_stream.write_unsigned("field_10", record.field_10, 64)
  |> bit_stream.write_float32_bits("durability", record.durability)
  |> bit_stream.write_unsigned("field_12", record.field_12, 32)
  |> bit_stream.write_unsigned("field_13", record.field_13, 8)
  |> bit_stream.write_unsigned("field_14", record.field_14, 32)
  |> bit_stream.write_unsigned("field_15", record.field_15, 32)
  |> bit_stream.write_unsigned("field_16", record.field_16, 32)
  |> bit_stream.write_unsigned("field_17", record.field_17, 3)
  |> bit_stream.write_unsigned("field_18", record.field_18, 32)
  |> bit_stream.write_unsigned("field_19", record.field_19, 32)
  |> bit_stream.write_unsigned("field_20", record.field_20, 3)
  |> bit_stream.write_unsigned("field_21", record.field_21, 32)
  |> bit_stream.write_unsigned("field_22", record.field_22, 32)
  |> bit_stream.write_unsigned("field_23", record.field_23, 18)
  |> bit_stream.write_unsigned_array("list_a", record.list_a, 3, 32)
  |> bit_stream.write_unsigned_array("list_b", record.list_b, 4, 32)
  |> bit_stream.write_constant("no_character_ids", 0, 6)
  |> bit_stream.write_unsigned("field_27", record.field_27, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(SharedItem, Reader), DecodeError) {
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_2, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(item_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(location, reader) <- result.try(bit_stream.read_unsigned(reader, 9))
  use #(bag_index, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(stack_count, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(charges, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_8, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_9, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(durability, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(field_12, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_13, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(field_14, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_15, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_16, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_17, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(field_18, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_19, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_20, reader) <- result.try(bit_stream.read_unsigned(reader, 3))
  use #(field_21, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_22, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_23, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(list_a, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    3,
    32,
  ))
  use #(list_b, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    4,
    32,
  ))
  use reader <- result.try(bit_stream.read_constant(
    reader,
    "no_character_ids",
    6,
    0,
  ))
  use #(field_27, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(
    SharedItem(
      item_guid:,
      field_2:,
      item_id:,
      location:,
      bag_index:,
      stack_count:,
      charges:,
      field_8:,
      field_9:,
      field_10:,
      durability:,
      field_12:,
      field_13:,
      field_14:,
      field_15:,
      field_16:,
      field_17:,
      field_18:,
      field_19:,
      field_20:,
      field_21:,
      field_22:,
      field_23:,
      list_a:,
      list_b:,
      field_27:,
    ),
    reader,
  ))
}
