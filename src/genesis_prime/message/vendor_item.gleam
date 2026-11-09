//// Generated from `schema.toml` by `genesis_prime/generate_messages`;
//// never edited by hand.
////
//// A record inside a message body: one item of a vendor's stock
//// (ReadVendorItem): the unique id the client buys by, the kind (0 item, 4
//// spell, 5 currency), the Item2, Spell4 or CurrencyType id, the currency type
//// (kind 5), the stock count (0 unlimited), the prerequisite, the amount (kind
//// 5), the tab, the flags (1 hide when the prerequisite fails, 2 special, 4
//// future stock), two values with no reader found, and two price slots. Its
//// fields are listed in `schema.toml` with the client's evidence, and the fact
//// file's `0x140097ae0` names the record.

import genesis_prime/message/bit_stream.{
  type DecodeError, type Reader, type Writer,
}
import genesis_prime/message/vendor_price_slot.{type VendorPriceSlot}
import gleam/result

/// The record's fields in wire order. A field named `field_N` is the Nth of the
/// record: its own doc names the fact that shows its value is safe, and one
/// with no such doc has no use the client's code shows.
pub type VendorItem {
  VendorItem(
    unique_id: Int,
    kind: Int,
    entry_id: Int,
    currency_type_id: Int,
    stock_count: Int,
    prerequisite_id: Int,
    amount: Int,
    tab_id: Int,
    flags: Int,
    /// Safe by `0x140097ae0`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_10: Int,
    /// Safe by `0x140097ae0`: the client's code gives this field no use the
    /// server needs, and that fact shows its value is safe.
    field_11: Int,
    price_slot_1: VendorPriceSlot,
    price_slot_2: VendorPriceSlot,
  )
}

/// Writes the record's fields to the stream.
pub fn write(writer writer: Writer, record record: VendorItem) -> Writer {
  writer
  |> bit_stream.write_unsigned("unique_id", record.unique_id, 32)
  |> bit_stream.write_unsigned("kind", record.kind, 4)
  |> bit_stream.write_unsigned("entry_id", record.entry_id, 32)
  |> bit_stream.write_unsigned("currency_type_id", record.currency_type_id, 32)
  |> bit_stream.write_unsigned("stock_count", record.stock_count, 32)
  |> bit_stream.write_unsigned("prerequisite_id", record.prerequisite_id, 17)
  |> bit_stream.write_unsigned("amount", record.amount, 32)
  |> bit_stream.write_unsigned("tab_id", record.tab_id, 32)
  |> bit_stream.write_unsigned("flags", record.flags, 32)
  |> bit_stream.write_unsigned("field_10", record.field_10, 64)
  |> bit_stream.write_unsigned("field_11", record.field_11, 32)
  |> vendor_price_slot.write(record.price_slot_1)
  |> vendor_price_slot.write(record.price_slot_2)
}

/// Reads the record from the stream, and the stream after it.
pub fn read(reader: Reader) -> Result(#(VendorItem, Reader), DecodeError) {
  use #(unique_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(kind, reader) <- result.try(bit_stream.read_unsigned(reader, 4))
  use #(entry_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(currency_type_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    32,
  ))
  use #(stock_count, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(prerequisite_id, reader) <- result.try(bit_stream.read_unsigned(
    reader,
    17,
  ))
  use #(amount, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(tab_id, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(flags, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(field_10, reader) <- result.try(bit_stream.read_unsigned(reader, 64))
  use #(field_11, reader) <- result.try(bit_stream.read_unsigned(reader, 32))
  use #(price_slot_1, reader) <- result.try(vendor_price_slot.read(reader))
  use #(price_slot_2, reader) <- result.try(vendor_price_slot.read(reader))
  Ok(#(
    VendorItem(
      unique_id:,
      kind:,
      entry_id:,
      currency_type_id:,
      stock_count:,
      prerequisite_id:,
      amount:,
      tab_id:,
      flags:,
      field_10:,
      field_11:,
      price_slot_1:,
      price_slot_2:,
    ),
    reader,
  ))
}
