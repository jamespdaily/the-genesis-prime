//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// Message 0x090B (vendor_items), server to client: a vendor's stock: the
//// vendor's unit id, its tabs (none puts every item under one tab), its items,
//// the buy and sell multipliers the client keeps on the unit, and three bits:
//// open (the client opens the vendor window), full list (the items replace the
//// list the client holds, not one item of it) and refuse (with open, the
//// client ends the interaction itself and shows nothing). Gap: the 64-bit and
//// 32-bit values after each item's amounts have no reader found and are sent
//// as 0. Its fields are listed in `schema.toml` with the client's evidence,
//// and the fact file's `opcode.0x90b` names the message.

import genesis_prime/message/bit_stream.{type DecodeError, type EncodeError}
import genesis_prime/message/vendor_item.{type VendorItem}
import genesis_prime/message/vendor_tab.{type VendorTab}
import gleam/result

/// The message's number.
pub const message_id = 0x090B

/// The body of message 0x090B, its fields in wire order. A field named
/// `field_N` is the Nth of the body: its own doc names the fact that shows its
/// value is safe, and one with no such doc has no use the client's code shows.
pub type VendorItems {
  VendorItems(
    unit_id: Int,
    tabs: List(VendorTab),
    items: List(VendorItem),
    buy_multiplier: Int,
    sell_multiplier: Int,
    open: Int,
    full_list: Int,
    refuse: Int,
  )
}

/// The message as the bytes of its body, or the first field that cannot be
/// written.
pub fn encode(message: VendorItems) -> Result(BitArray, EncodeError) {
  bit_stream.new_writer()
  |> bit_stream.write_unsigned("unit_id", message.unit_id, 32)
  |> bit_stream.write_array("tabs", message.tabs, 32, vendor_tab.write)
  |> bit_stream.write_array("items", message.items, 32, vendor_item.write)
  |> bit_stream.write_float32_bits("buy_multiplier", message.buy_multiplier)
  |> bit_stream.write_float32_bits("sell_multiplier", message.sell_multiplier)
  |> bit_stream.write_unsigned("open", message.open, 1)
  |> bit_stream.write_unsigned("full_list", message.full_list, 1)
  |> bit_stream.write_unsigned("refuse", message.refuse, 1)
  |> bit_stream.finish
}

/// The message read from the bytes of a body, or why they are not one.
pub fn decode(body: BitArray) -> Result(VendorItems, DecodeError) {
  let reader = bit_stream.new_reader(body)
  use #(unit_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(tabs, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    vendor_tab.read,
  ))
  use #(items, reader) <- result.try(bit_stream.read_array(
    reader,
    32,
    vendor_item.read,
  ))
  use #(buy_multiplier, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(sell_multiplier, reader) <- result.try(bit_stream.read_float32_bits(
    reader,
  ))
  use #(open, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(full_list, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use #(refuse, reader) <- result.try(bit_stream.read_unsigned(reader, 1))
  use Nil <- result.try(bit_stream.finish_reading(reader))
  Ok(VendorItems(
    unit_id:,
    tabs:,
    items:,
    buy_multiplier:,
    sell_multiplier:,
    open:,
    full_list:,
    refuse:,
  ))
}
