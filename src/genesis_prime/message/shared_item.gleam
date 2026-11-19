//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: the item record message 0x111 carries: the
//// GUID, the item id, the location and bag index, the stack count and charges,
//// the random-stat word, the durability, the dye, the flags, the refund and
//// trade windows, the refund price entries, the rune slots and rune data, the
//// stat multipliers and the level-scaling input. Its fields are listed in
//// `schema.toml` with the client's evidence, and the fact file's
//// `opcode.0x111.ability_bag` names the record.

import genesis_prime/gap
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
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    crafter_character_id: Int,
    item_id: Int,
    location: Int,
    bag_index: Int,
    stack_count: Int,
    charges: Int,
    random_stats: Int,
    rune_slots: Int,
    /// Open: What reads the 64-bit rune value's 4-bit part and three 10-bit
    /// parts in the current item format, and what does retail send for a new
    /// item? No reader of the unpacked parts was found; 0x14040c610 reads it
    /// only to convert the old format (opcode.0x111.shared_item_fields).
    field_10: Int,
    durability: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    dye_channels: Int,
    item_flags: Int,
    /// Open: How long is the refund window a bought item gets, and which
    /// message asks for the refund? opcode.0x111.shared_item_unnamed names the
    /// field; the retail length and the request are unread, so the server sends
    /// 0 and refunds are off.
    refund_window_ms: Int,
    time_left_ms: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    soulbound_trade_window_ms: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    refund_cost_0_kind: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    refund_cost_0_value_a: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    refund_cost_0_value_b: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    refund_cost_1_kind: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    refund_cost_1_value_a: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    refund_cost_1_value_b: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    budget_item_id: Int,
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    stat_multipliers: List(Int),
    /// Safe by `opcode.0x111.shared_item_unnamed`: the client's code gives this
    /// field no use the server needs, and that fact shows its value is safe.
    socketed_rune_item_ids: List(Int),
    /// Open: What must the server send in the level-scaling input for an item
    /// whose Item2 flags bit 20 asks for a power level override? The client
    /// reads its low 16 bits as that override and its bits 16 to 23 as a
    /// quality override (0x140445320, 0x14040c610); 0 shows the row's own level
    /// and quality, scaled by the player's level.
    field_27: Int,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: SharedItem) -> Writer {
  writer
  |> bit_stream.write_unsigned("item_guid", record.item_guid, 64)
  |> bit_stream.write_unsigned(
    "crafter_character_id",
    record.crafter_character_id,
    64,
  )
  |> bit_stream.write_unsigned("item_id", record.item_id, 18)
  |> bit_stream.write_unsigned("location", record.location, 9)
  |> bit_stream.write_unsigned("bag_index", record.bag_index, 32)
  |> bit_stream.write_unsigned("stack_count", record.stack_count, 32)
  |> bit_stream.write_unsigned("charges", record.charges, 32)
  |> bit_stream.write_unsigned("random_stats", record.random_stats, 64)
  |> bit_stream.write_unsigned("rune_slots", record.rune_slots, 32)
  |> bit_stream.write_unsigned("field_10", record.field_10, 64)
  |> bit_stream.write_float32_bits("durability", record.durability)
  |> bit_stream.write_unsigned("dye_channels", record.dye_channels, 32)
  |> bit_stream.write_unsigned("item_flags", record.item_flags, 8)
  |> bit_stream.write_unsigned("refund_window_ms", record.refund_window_ms, 32)
  |> bit_stream.write_unsigned("time_left_ms", record.time_left_ms, 32)
  |> bit_stream.write_unsigned(
    "soulbound_trade_window_ms",
    record.soulbound_trade_window_ms,
    32,
  )
  |> bit_stream.write_unsigned(
    "refund_cost_0_kind",
    record.refund_cost_0_kind,
    3,
  )
  |> bit_stream.write_unsigned(
    "refund_cost_0_value_a",
    record.refund_cost_0_value_a,
    32,
  )
  |> bit_stream.write_unsigned(
    "refund_cost_0_value_b",
    record.refund_cost_0_value_b,
    32,
  )
  |> bit_stream.write_unsigned(
    "refund_cost_1_kind",
    record.refund_cost_1_kind,
    3,
  )
  |> bit_stream.write_unsigned(
    "refund_cost_1_value_a",
    record.refund_cost_1_value_a,
    32,
  )
  |> bit_stream.write_unsigned(
    "refund_cost_1_value_b",
    record.refund_cost_1_value_b,
    32,
  )
  |> bit_stream.write_unsigned("budget_item_id", record.budget_item_id, 18)
  |> bit_stream.write_unsigned_array(
    "stat_multipliers",
    record.stat_multipliers,
    3,
    32,
  )
  |> bit_stream.write_unsigned_array(
    "socketed_rune_item_ids",
    record.socketed_rune_item_ids,
    4,
    32,
  )
  |> bit_stream.write_constant("no_character_ids", 0, 6)
  |> bit_stream.write_unsigned("field_27", record.field_27, 32)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(SharedItem, Reader), DecodeError) {
  use #(item_guid, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(crafter_character_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    64,
  ))
  use #(item_id, reader) <- result.try(bit_stream.read_unsigned(reader, 18))
  use #(location, reader) <- result.try(bit_stream.read_unsigned(reader, 9))
  use #(bag_index, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(stack_count, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(charges, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(random_stats, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(rune_slots, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(durability, reader) <- result.try(bit_stream.read_float32_bits(reader))
  use #(dye_channels, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(item_flags, reader) <- result.try(bit_stream.read_unsigned(reader, 8))
  use #(refund_window_ms, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(time_left_ms, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(soulbound_trade_window_ms, reader) <- result.try(
    bit_stream.read_unsigned(reader, 32),
  )
  use #(refund_cost_0_kind, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    3,
  ))
  use #(refund_cost_0_value_a, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(refund_cost_0_value_b, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(refund_cost_1_kind, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    3,
  ))
  use #(refund_cost_1_value_a, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(refund_cost_1_value_b, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(budget_item_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    18,
  ))
  use #(stat_multipliers, reader) <- result.try(bit_stream.read_unsigned_array(
    reader,
    3,
    32,
  ))
  use #(socketed_rune_item_ids, reader) <- result.try(
    bit_stream.read_unsigned_array(reader, 4, 32),
  )
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
      crafter_character_id:,
      item_id:,
      location:,
      bag_index:,
      stack_count:,
      charges:,
      random_stats:,
      rune_slots:,
      field_10:,
      durability:,
      dye_channels:,
      item_flags:,
      refund_window_ms:,
      time_left_ms:,
      soulbound_trade_window_ms:,
      refund_cost_0_kind:,
      refund_cost_0_value_a:,
      refund_cost_0_value_b:,
      refund_cost_1_kind:,
      refund_cost_1_value_a:,
      refund_cost_1_value_b:,
      budget_item_id:,
      stat_multipliers:,
      socketed_rune_item_ids:,
      field_27:,
    ),
    reader,
  ))
}

/// What this record's codec leaves unhandled, which the coverage measure prints.
pub fn gaps() -> List(gap.Entry) {
  [
    gap.Entry(
      area: "Item records",
      missing: "the length of the refund window a bought item gets and the message that asks for a refund: the server writes a refund window of 0 and no refund price, so no item can be refunded",
    ),
    gap.Entry(
      area: "Item records",
      missing: "the ids in an item record's list of realm and character ids: the server writes a count of 0, since the width of one entry is not read",
    ),
  ]
}
