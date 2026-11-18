//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one buyback entry as messages 0xBA and 0xBC
//// carry it: the buyback id, the Item2 id and the quantity, the item property
//// inputs (fields 4 to 21, read as message 0x111's are; the server writes the
//// random-stat word, field 4, as the item's, the five multipliers, fields 9 to
//// 13, as the float 1.0 and the rest as 0), the rune slots, the budget item id
//// and the eight socketed rune item ids among them, the two amounts and their
//// currency types as the tab shows them, and a last 32-bit value. Its fields
//// are listed in `schema.toml` with the client's evidence, and the fact file's
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
    random_stats: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    rune_slots: Int,
    /// Open: What reads the 64-bit rune value's 4-bit part and three 10-bit
    /// parts in the current item format, and what does retail send for a new
    /// item? No reader of the unpacked parts was found; 0x14040c610 reads it
    /// only to convert the old format (opcode.0x111.shared_item_fields).
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_6: Int,
    /// Open: What does the 64-bit value after the rune value do?
    /// GetBuybackItems has no reader for it (opcode.0xba.random_stats).
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_7: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    budget_item_id: Int,
    multiplier_1: Int,
    multiplier_2: Int,
    multiplier_3: Int,
    multiplier_4: Int,
    multiplier_5: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    socketed_rune_item_id_1: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    socketed_rune_item_id_2: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    socketed_rune_item_id_3: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    socketed_rune_item_id_4: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    socketed_rune_item_id_5: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    socketed_rune_item_id_6: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    socketed_rune_item_id_7: Int,
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    socketed_rune_item_id_8: Int,
    amount_1: Int,
    amount_2: Int,
    currency_type_1: Int,
    currency_type_2: Int,
    /// Open: What must the server send in the level-scaling input for an item
    /// whose Item2 flags bit 20 asks for a power level override? The client
    /// reads its low 16 bits as that override and its bits 16 to 23 as a
    /// quality override (0x140445320, 0x14040c610); 0 shows the row's own level
    /// and quality, scaled by the player's level.
    /// Safe by `opcode.0xba.price`: the client's code gives this field no use
    /// the server needs, and that fact shows its value is safe.
    field_26: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: BuybackEntry) -> Writer {
  writer
  |> bit_stream.write_unsigned("buyback_id", record.buyback_id, 32)
  |> bit_stream.write_unsigned("item_id", record.item_id, 18)
  |> bit_stream.write_unsigned("quantity", record.quantity, 32)
  |> bit_stream.write_unsigned("random_stats", record.random_stats, 64)
  |> bit_stream.write_unsigned("rune_slots", record.rune_slots, 32)
  |> bit_stream.write_unsigned("field_6", record.field_6, 64)
  |> bit_stream.write_unsigned("field_7", record.field_7, 64)
  |> bit_stream.write_unsigned("budget_item_id", record.budget_item_id, 18)
  |> bit_stream.write_float32_bits("multiplier_1", record.multiplier_1)
  |> bit_stream.write_float32_bits("multiplier_2", record.multiplier_2)
  |> bit_stream.write_float32_bits("multiplier_3", record.multiplier_3)
  |> bit_stream.write_float32_bits("multiplier_4", record.multiplier_4)
  |> bit_stream.write_float32_bits("multiplier_5", record.multiplier_5)
  |> bit_stream.write_unsigned(
    "socketed_rune_item_id_1",
    record.socketed_rune_item_id_1,
    32,
  )
  |> bit_stream.write_unsigned(
    "socketed_rune_item_id_2",
    record.socketed_rune_item_id_2,
    32,
  )
  |> bit_stream.write_unsigned(
    "socketed_rune_item_id_3",
    record.socketed_rune_item_id_3,
    32,
  )
  |> bit_stream.write_unsigned(
    "socketed_rune_item_id_4",
    record.socketed_rune_item_id_4,
    32,
  )
  |> bit_stream.write_unsigned(
    "socketed_rune_item_id_5",
    record.socketed_rune_item_id_5,
    32,
  )
  |> bit_stream.write_unsigned(
    "socketed_rune_item_id_6",
    record.socketed_rune_item_id_6,
    32,
  )
  |> bit_stream.write_unsigned(
    "socketed_rune_item_id_7",
    record.socketed_rune_item_id_7,
    32,
  )
  |> bit_stream.write_unsigned(
    "socketed_rune_item_id_8",
    record.socketed_rune_item_id_8,
    32,
  )
  |> bit_stream.write_unsigned("amount_1", record.amount_1, 64)
  |> bit_stream.write_unsigned("amount_2", record.amount_2, 64)
  |> bit_stream.write_unsigned("currency_type_1", record.currency_type_1, 4)
  |> bit_stream.write_unsigned("currency_type_2", record.currency_type_2, 4)
  |> bit_stream.write_unsigned("field_26", record.field_26, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(BuybackEntry, Reader), DecodeError) {
  use #(buyback_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(item_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(quantity, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(random_stats, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(rune_slots, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_6, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_7, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(budget_item_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(multiplier_1, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(multiplier_2, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(multiplier_3, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(multiplier_4, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(multiplier_5, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(socketed_rune_item_id_1, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(socketed_rune_item_id_2, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(socketed_rune_item_id_3, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(socketed_rune_item_id_4, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(socketed_rune_item_id_5, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(socketed_rune_item_id_6, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(socketed_rune_item_id_7, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(socketed_rune_item_id_8, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(amount_1, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(amount_2, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(currency_type_1, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    4,
  ))
  use #(currency_type_2, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    4,
  ))
  use #(field_26, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  Ok(#(
    BuybackEntry(
      buyback_id:,
      item_id:,
      quantity:,
      random_stats:,
      rune_slots:,
      field_6:,
      field_7:,
      budget_item_id:,
      multiplier_1:,
      multiplier_2:,
      multiplier_3:,
      multiplier_4:,
      multiplier_5:,
      socketed_rune_item_id_1:,
      socketed_rune_item_id_2:,
      socketed_rune_item_id_3:,
      socketed_rune_item_id_4:,
      socketed_rune_item_id_5:,
      socketed_rune_item_id_6:,
      socketed_rune_item_id_7:,
      socketed_rune_item_id_8:,
      amount_1:,
      amount_2:,
      currency_type_1:,
      currency_type_2:,
      field_26:,
    ),
    reader,
  ))
}
