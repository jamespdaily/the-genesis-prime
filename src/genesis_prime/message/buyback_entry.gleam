//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one buyback entry (message 0xBA's layout):
//// the buyback id, the Item2 id and the quantity are named; the other widths
//// are in the client's order and have no reader found. Its fields are listed
//// in `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0xba` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type BuybackEntry {
  BuybackEntry(
    buyback_id: Int,
    item_id: Int,
    quantity: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_4: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_5: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_6: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_7: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_8: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_9: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_10: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_11: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_12: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_13: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_14: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_15: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_16: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_17: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_18: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_19: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_20: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_21: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_22: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_23: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_24: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_25: Int,
    /// Safe by `opcode.0xba`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_26: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: BuybackEntry) -> Writer {
  writer
  |> bit_stream.write_unsigned("buyback_id", record.buyback_id, 32)
  |> bit_stream.write_unsigned("item_id", record.item_id, 18)
  |> bit_stream.write_unsigned("quantity", record.quantity, 32)
  |> bit_stream.write_unsigned("field_4", record.field_4, 64)
  |> bit_stream.write_unsigned("field_5", record.field_5, 32)
  |> bit_stream.write_unsigned("field_6", record.field_6, 64)
  |> bit_stream.write_unsigned("field_7", record.field_7, 64)
  |> bit_stream.write_unsigned("field_8", record.field_8, 18)
  |> bit_stream.write_unsigned("field_9", record.field_9, 32)
  |> bit_stream.write_unsigned("field_10", record.field_10, 32)
  |> bit_stream.write_unsigned("field_11", record.field_11, 32)
  |> bit_stream.write_unsigned("field_12", record.field_12, 32)
  |> bit_stream.write_unsigned("field_13", record.field_13, 32)
  |> bit_stream.write_unsigned("field_14", record.field_14, 32)
  |> bit_stream.write_unsigned("field_15", record.field_15, 32)
  |> bit_stream.write_unsigned("field_16", record.field_16, 32)
  |> bit_stream.write_unsigned("field_17", record.field_17, 32)
  |> bit_stream.write_unsigned("field_18", record.field_18, 32)
  |> bit_stream.write_unsigned("field_19", record.field_19, 32)
  |> bit_stream.write_unsigned("field_20", record.field_20, 32)
  |> bit_stream.write_unsigned("field_21", record.field_21, 32)
  |> bit_stream.write_unsigned("field_22", record.field_22, 64)
  |> bit_stream.write_unsigned("field_23", record.field_23, 64)
  |> bit_stream.write_unsigned("field_24", record.field_24, 4)
  |> bit_stream.write_unsigned("field_25", record.field_25, 4)
  |> bit_stream.write_unsigned("field_26", record.field_26, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(BuybackEntry, Reader), DecodeError) {
  use #(buyback_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(item_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(quantity, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_4, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_5, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_8, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(field_9, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_11, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_12, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_13, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_14, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_15, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_16, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_17, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_18, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_19, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_20, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_21, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_22, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_23, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_24, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(field_25, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(field_26, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(
    BuybackEntry(
      buyback_id:,
      item_id:,
      quantity:,
      field_4:,
      field_5:,
      field_6:,
      field_7:,
      field_8:,
      field_9:,
      field_10:,
      field_11:,
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
      field_24:,
      field_25:,
      field_26:,
    ),
    reader,
  ))
}
