//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one shortcut of an action set: the type (4
//// is an ability by its Spell4Base id, 0 empties the slot), an item location,
//// the bar slot in the field the client calls the bag index (0 to 47) and the
//// object id. Its fields are listed in `schema.toml` with the client's
//// evidence, and the fact file's `opcode.0x19d` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type ActionShortcut {
  ActionShortcut(
    shortcut_type: Int,
    location: Int,
    bag_index: Int,
    object_id: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: ActionShortcut) -> Writer {
  writer
  |> bit_stream.write_unsigned("shortcut_type", record.shortcut_type, 4)
  |> bit_stream.write_unsigned("location", record.location, 9)
  |> bit_stream.write_unsigned_below("bag_index", record.bag_index, 32, 48)
  |> bit_stream.write_unsigned("object_id", record.object_id, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(ActionShortcut, Reader), DecodeError) {
  use #(shortcut_type, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(location, reader) <- result.try(bit_stream.read_unsigned(reader, 9))
  use #(bag_index, reader) <- result.try(bit_stream.read_unsigned_below(
    reader,
    "bag_index",
    32,
    48,
  ))
  use #(object_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(
    ActionShortcut(shortcut_type:, location:, bag_index:, object_id:),
    reader,
  ))
}
