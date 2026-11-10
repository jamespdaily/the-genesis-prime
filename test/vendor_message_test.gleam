//// The two messages of a vendor purchase through the generated codec: the client's
//// 0xBE (`opcode.0xbe`: the unique id of the stock item and the quantity of lots, 32
//// bits each) and the server's 0x919 (`opcode.0x919`: the currency kind in 5 bits,
//// the total in 64, and two 32-bit fields the client gives no use). Every value of
//// the widths the fields hold round-trips.
////
//// The server's 0xBA (`opcode.0xba`) carries one buyback entry of 908 bits: the id
//// (32), the Item2 id (18), the quantity (32), 18 property fields as message 0x111's
//// are read (fields 4 to 21: 64, 32, 64, 64, 18 bits, then 13 of 32), the two amounts
//// (64 each, `opcode.0xba.price`), their two currency types (4 each) and a last 32. The
//// client's 0x166 (`opcode.0x166`) is a place (location 9 bits, bag index 32) and a
//// quantity (32).

import genesis_prime/message/buyback_added.{BuybackAdded}
import genesis_prime/message/buyback_entry.{type BuybackEntry, BuybackEntry}
import genesis_prime/message/buyback_list.{BuybackList}
import genesis_prime/message/buyback_removed.{BuybackRemoved}
import genesis_prime/message/currency_changed.{CurrencyChanged}
import genesis_prime/message/item_place.{ItemPlace}
import genesis_prime/message/vendor_buyback.{VendorBuyback}
import genesis_prime/message/vendor_purchase.{VendorPurchase}
import genesis_prime/message/vendor_sale.{VendorSale}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import owned_test
import qcheck

pub fn the_0x919_and_0xbe_codecs_round_trip_test() -> Nil {
  use <- owned_test.run(10_000)
  use #(kind, total, field_3, field_4) <- qcheck.given(qcheck.tuple4(
    qcheck.bounded_int(from: 0, to: 31),
    qcheck.bounded_int(from: 0, to: 9_223_372_036_854_775_807),
    qcheck.bounded_int(from: 0, to: 4_294_967_295),
    qcheck.bounded_int(from: 0, to: 4_294_967_295),
  ))
  let changed = CurrencyChanged(kind:, total:, field_3:, field_4:)
  assert currency_changed.encode(changed)
    |> result_decode(currency_changed.decode)
    == Ok(changed)
    as "opcode.0x919: the kind in 5 bits, the total in 64 and two fields of 32"
  let purchase = VendorPurchase(unique_id: field_3, quantity: field_4)
  assert vendor_purchase.encode(purchase)
    |> result_decode(vendor_purchase.decode)
    == Ok(purchase)
    as "opcode.0xbe: the unique id and the quantity, 32 bits each"
}

/// The width in bits of each field of the buyback entry, in wire order.
const entry_widths = [
  32, 18, 32, 64, 32, 64, 64, 18, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32,
  32, 64, 64, 4, 4, 32,
]

/// A buyback entry of these values, which are the fields in wire order.
fn entry_of(values: List(Int)) -> BuybackEntry {
  let assert [
    buyback_id,
    item_id,
    quantity,
    random_stats,
    field_5,
    field_6,
    field_7,
    field_8,
    multiplier_1,
    multiplier_2,
    multiplier_3,
    multiplier_4,
    multiplier_5,
    field_14,
    field_15,
    field_16,
    field_17,
    field_18,
    field_19,
    field_20,
    field_21,
    amount_1,
    amount_2,
    currency_type_1,
    currency_type_2,
    field_26,
  ] = values
    as "the entry has 26 fields: the three named, 4 to 8, the five multipliers, 14 to 21, then the amounts, the types and the last"
  BuybackEntry(
    buyback_id:,
    item_id:,
    quantity:,
    random_stats:,
    field_5:,
    field_6:,
    field_7:,
    field_8:,
    multiplier_1:,
    multiplier_2:,
    multiplier_3:,
    multiplier_4:,
    multiplier_5:,
    field_14:,
    field_15:,
    field_16:,
    field_17:,
    field_18:,
    field_19:,
    field_20:,
    field_21:,
    amount_1:,
    amount_2:,
    currency_type_1:,
    currency_type_2:,
    field_26:,
  )
}

pub fn the_buyback_entry_codec_round_trips_test() -> Nil {
  use <- owned_test.run(10_000)
  assert list.fold(entry_widths, 0, int.add) == 908
    as "opcode.0xba: one entry is 908 bits"
  use #(draws, place_and_quantity) <- qcheck.given(qcheck.tuple2(
    qcheck.fixed_length_list_from(
      qcheck.bounded_int(from: 0, to: 9_223_372_036_854_775_807),
      list.length(entry_widths),
    ),
    qcheck.tuple3(
      qcheck.bounded_int(from: 0, to: 511),
      qcheck.bounded_int(from: 0, to: 4_294_967_295),
      qcheck.bounded_int(from: 0, to: 4_294_967_295),
    ),
  ))
  // Each draw cut to its field's width, so every width is met with values of its own size.
  let values =
    list.map2(draws, entry_widths, fn(draw, width) {
      int.bitwise_and(draw, int.bitwise_shift_left(1, width) - 1)
    })
  let added = BuybackAdded(entry: entry_of(values))
  let assert Ok(body) = buyback_added.encode(added)
    as "values of the fields' widths are written"
  assert bit_array.byte_size(body) == 114
    as "opcode.0xba: 908 bits are 114 bytes, the last 4 bits padding"
  assert buyback_added.decode(body) == Ok(added)
    as "opcode.0xba: the entry reads back as it was written"
  let #(location, bag_index, quantity) = place_and_quantity
  let sale = VendorSale(place: ItemPlace(location:, bag_index:), quantity:)
  let assert Ok(sale_body) = vendor_sale.encode(sale)
    as "a 9-bit location and two 32-bit values are written"
  assert bit_array.byte_size(sale_body) == 10
    as "opcode.0x166: 73 bits are 10 bytes"
  assert vendor_sale.decode(sale_body) == Ok(sale)
    as "opcode.0x166: the place and the quantity read back as they were written"
}

fn result_decode(
  encoded: Result(BitArray, encode_error),
  decode: fn(BitArray) -> Result(a, decode_error),
) -> Result(a, Nil) {
  use body <- result.try(result.replace_error(encoded, Nil))
  result.replace_error(decode(body), Nil)
}

pub fn the_buyback_list_codec_round_trips_test() -> Nil {
  use <- owned_test.run(10_000)
  use #(entry_draws, buyback_id) <- qcheck.given(qcheck.tuple2(
    qcheck.generic_list(
      qcheck.fixed_length_list_from(
        qcheck.bounded_int(from: 0, to: 9_223_372_036_854_775_807),
        list.length(entry_widths),
      ),
      qcheck.bounded_int(from: 0, to: 4),
    ),
    qcheck.bounded_int(from: 0, to: 4_294_967_295),
  ))
  let entries =
    list.map(entry_draws, fn(draws) {
      entry_of(
        list.map2(draws, entry_widths, fn(draw, width) {
          int.bitwise_and(draw, int.bitwise_shift_left(1, width) - 1)
        }),
      )
    })
  let listed = BuybackList(entries:)
  let assert Ok(body) = buyback_list.encode(listed)
    as "values of the fields' widths are written"
  assert bit_array.byte_size(body)
    == { 32 + list.length(entries) * 908 + 7 } / 8
    as "opcode.0xbc: a 32-bit count, then each entry's 908 bits, padded to the byte"
  assert buyback_list.decode(body) == Ok(listed)
    as "opcode.0xbc: the list reads back as it was written, in order"
  let buy_back = VendorBuyback(buyback_id:)
  let assert Ok(buy_back_body) = vendor_buyback.encode(buy_back)
    as "a 32-bit id is written"
  assert bit_array.byte_size(buy_back_body) == 4
    as "opcode.0xbb: the body is one 32-bit id"
  assert vendor_buyback.decode(buy_back_body) == Ok(buy_back)
    as "opcode.0xbb: the id reads back as it was written"
  let removed = BuybackRemoved(buyback_id:)
  let assert Ok(removed_body) = buyback_removed.encode(removed)
    as "a 32-bit id is written"
  assert buyback_removed.decode(removed_body) == Ok(removed)
    as "opcode.0xbd: the id reads back as it was written"
}
