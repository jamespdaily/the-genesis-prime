//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one item visual of a character: the slot,
//// the display, the colour set and the dye. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's `0x1400ab890`
//// names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record and has no use the client's code shows.
pub type ItemVisual {
  ItemVisual(slot: Int, display_id: Int, item_color_set_id: Int, dye: Int)
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: ItemVisual) -> Writer {
  writer
  |> bit_stream.write_unsigned("slot", record.slot, 7)
  |> bit_stream.write_unsigned("display_id", record.display_id, 15)
  |> bit_stream.write_unsigned(
    "item_color_set_id",
    record.item_color_set_id,
    14,
  )
  |> bit_stream.write_unsigned("dye", record.dye, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(ItemVisual, Reader), DecodeError) {
  use #(slot, reader) <- result.try(bit_stream.read_unsigned(reader, 7))
  use #(display_id, reader) <- result.try(bit_stream.read_unsigned(reader, 15))
  use #(item_color_set_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    14,
  ))
  use #(dye, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(ItemVisual(slot:, display_id:, item_color_set_id:, dye:), reader))
}
